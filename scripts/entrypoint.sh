#!/bin/bash
set -e

MVB_AGENTS="${MVB_AGENTS:-claude}"
MVB_LAYOUT="${MVB_LAYOUT:-tiled}"
MVB_PROJECT="${MVB_PROJECT:-default}"
MVB_SHARED="${MVB_SHARED:-false}"
MVB_MAX_PANES="${MVB_MAX_PANES:-6}"

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

# Set up git worktrees if not shared mode and workspace is a git repo
setup_worktrees() {
    if [ "$MVB_SHARED" = "true" ]; then
        echo "Shared mode: all agents work in /workspace"
        return
    fi

    if [ ! -d /workspace/.git ]; then
        echo "Not a git repo — using shared mode"
        MVB_SHARED="true"
        return
    fi

    cd /workspace

    # Ensure we have a branch to base worktrees on
    local base_branch
    base_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

    for agent in "${AGENTS[@]}"; do
        agent=$(echo "$agent" | xargs)  # trim whitespace
        local worktree_dir="/workspace-${agent}"
        local branch_name="agent/${agent}"

        if [ -d "$worktree_dir" ]; then
            echo "Worktree for $agent already exists at $worktree_dir"
            continue
        fi

        # Create branch if it doesn't exist
        if ! git show-ref --verify --quiet "refs/heads/${branch_name}"; then
            git branch "$branch_name" "$base_branch" 2>/dev/null || true
        fi

        git worktree add "$worktree_dir" "$branch_name" 2>/dev/null || {
            echo "Warning: Could not create worktree for $agent, using shared workspace"
        }
    done

    cd /workspace
}

# Determine working directory for an agent
agent_workdir() {
    local agent="$1"
    if [ "$MVB_SHARED" = "true" ]; then
        echo "/workspace"
    elif [ -d "/workspace-${agent}" ]; then
        echo "/workspace-${agent}"
    else
        echo "/workspace"
    fi
}

# Set up worktrees
setup_worktrees

# Start tmux session
tmux -f /opt/mvb/config/tmux.conf new-session -d -s mvb -n main

# Set up first agent in the initial pane
first_agent=$(echo "${AGENTS[0]}" | xargs)
first_workdir=$(agent_workdir "$first_agent")
tmux send-keys -t mvb:main "cd $first_workdir && exec /opt/mvb/scripts/agent-wrapper.sh $first_agent" Enter
tmux select-pane -t mvb:main -T "$first_agent"

# Create additional panes for remaining agents
for i in $(seq 1 $((AGENT_COUNT - 1))); do
    agent=$(echo "${AGENTS[$i]}" | xargs)
    workdir=$(agent_workdir "$agent")

    tmux split-window -t mvb:main
    tmux send-keys -t mvb:main "cd $workdir && exec /opt/mvb/scripts/agent-wrapper.sh $agent" Enter
    tmux select-pane -t mvb:main -T "$agent"

    # Rebalance layout after each split
    tmux select-layout -t mvb:main "$MVB_LAYOUT" 2>/dev/null || tmux select-layout -t mvb:main tiled
done

# Select first pane
tmux select-pane -t mvb:main.0

# Attach to session
exec tmux attach-session -t mvb
