#!/bin/bash
set -e

# Initialize home directory from skeleton if empty (first run with fresh volume)
if [ ! -f "$HOME/.bashrc" ]; then
    echo "Initializing home directory from skeleton..."
    cp -a /opt/mvb/skel/. "$HOME/"
fi

# Clone repo into workspace if MVB_REPO_URL is set
if [ -n "${MVB_REPO_URL:-}" ]; then
    if [ -d /workspace/.git ]; then
        echo "Repo already cloned, pulling latest..."
        cd /workspace
        git pull --ff-only 2>/dev/null || echo "Warning: git pull failed (diverged or detached). Skipping."
        cd /
    elif [ -z "$(ls -A /workspace 2>/dev/null)" ]; then
        echo "Cloning $MVB_REPO_URL into /workspace..."
        git clone "$MVB_REPO_URL" /workspace
    else
        echo "Warning: /workspace is not empty and not a git repo. Skipping clone."
    fi
fi

MVB_LAYOUT="${MVB_LAYOUT:-tiled}"
MVB_PROJECT="${MVB_PROJECT:-default}"
MVB_SHARED="${MVB_SHARED:-false}"
MVB_MAX_PANES="${MVB_MAX_PANES:-6}"

# ---- Multi-project mode ----
# MVB_PANES format: "agent|workdir|pane_name;agent|workdir|pane_name;..."
# Each entry specifies the agent, its working directory, and the pane title.
if [ -n "$MVB_PANES" ]; then
    IFS=';' read -ra PANE_SPECS <<< "$MVB_PANES"
    PANE_COUNT=${#PANE_SPECS[@]}

    echo "Multi-project mode: $PANE_COUNT panes"

    # Start tmux session
    tmux -f /opt/mvb/config/tmux.conf new-session -d -s mvb -n main

    # Helper: set pane title and lock it against application overrides
    lock_pane_title() {
        local pane="$1" title="$2"
        tmux select-pane -t "$pane" -T "$title"
        tmux set-option -p -t "$pane" @mvb_title "$title"
    }

    # Hook: reset pane title whenever an application tries to change it
    tmux set-hook -g pane-title-changed "run-shell 'title=\"\$(tmux show-option -p -t \"#{pane_id}\" -v @mvb_title 2>/dev/null)\"; [ -n \"\$title\" ] && tmux select-pane -t \"#{pane_id}\" -T \"\$title\"'"

    # First pane (already exists in new session)
    IFS='|' read -r first_agent first_workdir first_pane_name <<< "${PANE_SPECS[0]}"
    tmux send-keys -t mvb:main "MVB_PANE_INDEX=0 exec /opt/mvb/scripts/agent-wrapper.sh $first_agent $first_workdir" Enter
    lock_pane_title mvb:main.0 "$first_pane_name │ $first_workdir"
    tmux select-pane -t mvb:main -P 'bg=black'

    # Remaining panes
    for i in $(seq 1 $((PANE_COUNT - 1))); do
        IFS='|' read -r agent workdir pane_name <<< "${PANE_SPECS[$i]}"

        tmux split-window -t mvb:main
        tmux send-keys -t mvb:main "MVB_PANE_INDEX=$i exec /opt/mvb/scripts/agent-wrapper.sh $agent $workdir" Enter
        lock_pane_title mvb:main "$pane_name │ $workdir"
        # Checkerboard: odd panes get dark gray, even panes stay black
        if [ $((i % 2)) -eq 1 ]; then
            tmux select-pane -t mvb:main -P 'bg=colour233'
        else
            tmux select-pane -t mvb:main -P 'bg=black'
        fi


        # Rebalance layout after each split
        tmux select-layout -t mvb:main "$MVB_LAYOUT" 2>/dev/null || tmux select-layout -t mvb:main tiled
    done

    # Select first pane and attach (loop keeps container alive on detach)
    tmux select-pane -t mvb:main.0
    while tmux has-session -t mvb 2>/dev/null; do
        tmux attach-session -t mvb || sleep 1
    done
    exit 0
fi

# ---- Single-project mode ----
MVB_AGENTS="${MVB_AGENTS:-claude}"

# Parse agents list
IFS=',' read -ra AGENTS <<< "$MVB_AGENTS"
AGENT_COUNT=${#AGENTS[@]}

# Warn if too many panes
if [ "$AGENT_COUNT" -gt "$MVB_MAX_PANES" ]; then
    echo "WARNING: $AGENT_COUNT agents requested, but MVB_MAX_PANES=$MVB_MAX_PANES."
    echo "Too many panes may cause readability and resource issues."
    echo "Proceeding with first $MVB_MAX_PANES agents only."
    AGENTS=("${AGENTS[@]:0:$MVB_MAX_PANES}")
    AGENT_COUNT=$MVB_MAX_PANES
fi

# Create stable per-pane working directories.
# Each pane always gets /workspace-<agent>-<index>/ so that Claude Code
# conversation history is tied to a consistent path regardless of whether
# the session has 1 pane or many.
setup_workdirs() {
    local is_git=false
    if [ -d /workspace/.git ]; then
        is_git=true
    fi

    local use_worktrees=false
    if [ "$MVB_SHARED" != "true" ] && [ "$is_git" = "true" ]; then
        use_worktrees=true
    fi

    if [ "$use_worktrees" = "true" ]; then
        cd /workspace
        local base_branch
        base_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    fi

    local agent_index=0
    for agent in "${AGENTS[@]}"; do
        agent=$(echo "$agent" | xargs)
        local workdir="/workspace-${agent}-${agent_index}"

        if [ "$use_worktrees" = "true" ]; then
            local branch_name="agent/${agent}-${agent_index}"

            if [ -d "$workdir" ]; then
                echo "Worktree already exists at $workdir"
            else
                if ! git show-ref --verify --quiet "refs/heads/${branch_name}"; then
                    git branch "$branch_name" "$base_branch" 2>/dev/null || true
                fi
                git worktree add "$workdir" "$branch_name" 2>/dev/null || {
                    echo "Warning: Could not create worktree for $agent-$agent_index"
                    # Fall back to symlink so the path still works
                    ln -sfn /workspace "$workdir"
                }
            fi
        else
            # Shared or non-git: symlink so every pane gets a stable unique path
            if [ ! -e "$workdir" ]; then
                ln -sfn /workspace "$workdir"
            fi
        fi

        agent_index=$((agent_index + 1))
    done

    [ "$use_worktrees" = "true" ] && cd /workspace
}

setup_workdirs

# Start tmux session
tmux -f /opt/mvb/config/tmux.conf new-session -d -s mvb -n main

# Helper: set pane title and lock it against application overrides
lock_pane_title() {
    local pane="$1" title="$2"
    tmux select-pane -t "$pane" -T "$title"
    tmux set-option -p -t "$pane" @mvb_title "$title"
}

# Hook: reset pane title whenever an application tries to change it
tmux set-hook -g pane-title-changed "run-shell 'title=\"\$(tmux show-option -p -t \"#{pane_id}\" -v @mvb_title 2>/dev/null)\"; [ -n \"\$title\" ] && tmux select-pane -t \"#{pane_id}\" -T \"\$title\"'"

# Set up first agent in the initial pane
first_agent=$(echo "${AGENTS[0]}" | xargs)
tmux send-keys -t mvb:main "cd /workspace-${first_agent}-0 && MVB_PANE_INDEX=0 exec /opt/mvb/scripts/agent-wrapper.sh $first_agent /workspace-${first_agent}-0" Enter
lock_pane_title mvb:main.0 "${first_agent}-0 │ /workspace-${first_agent}-0"
tmux select-pane -t mvb:main -P 'bg=black'

# Create additional panes for remaining agents
for i in $(seq 1 $((AGENT_COUNT - 1))); do
    agent=$(echo "${AGENTS[$i]}" | xargs)

    tmux split-window -t mvb:main
    tmux send-keys -t mvb:main "cd /workspace-${agent}-${i} && MVB_PANE_INDEX=$i exec /opt/mvb/scripts/agent-wrapper.sh $agent /workspace-${agent}-${i}" Enter
    lock_pane_title mvb:main "${agent}-${i} │ /workspace-${agent}-${i}"
    # Checkerboard: odd panes get dark gray, even panes stay black
    if [ $((i % 2)) -eq 1 ]; then
        tmux select-pane -t mvb:main -P 'bg=colour233'
    else
        tmux select-pane -t mvb:main -P 'bg=black'
    fi

    # Rebalance layout after each split
    tmux select-layout -t mvb:main "$MVB_LAYOUT" 2>/dev/null || tmux select-layout -t mvb:main tiled
done

# Select first pane and attach (loop keeps container alive on detach)
tmux select-pane -t mvb:main.0
while tmux has-session -t mvb 2>/dev/null; do
    tmux attach-session -t mvb || sleep 1
done
