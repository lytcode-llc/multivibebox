#!/bin/bash
# Launches an agent in a pane with auto-restart on exit

AGENT_NAME="${1:-claude}"
AGENT_WORKDIR="${2:-}"
AGENT_CONF="/config/agents/${AGENT_NAME}.conf"
FALLBACK_CONF="/opt/mvb/config/agents/${AGENT_NAME}.conf"
PANE_INDEX="${MVB_PANE_INDEX:-0}"

# cd to workdir if provided
if [ -n "$AGENT_WORKDIR" ]; then
    cd "$AGENT_WORKDIR"
fi

# Source agent config
if [ -f "$AGENT_CONF" ]; then
    source "$AGENT_CONF"
elif [ -f "$FALLBACK_CONF" ]; then
    source "$FALLBACK_CONF"
else
    echo "No config found for agent: $AGENT_NAME"
    echo "Expected: $AGENT_CONF"
    echo "Falling back to shell."
    AGENT_CMD="bash"
    AGENT_ARGS=""
fi

# Run install command if agent binary not found
if [ -n "$AGENT_INSTALL" ] && ! command -v "$AGENT_CMD" &>/dev/null; then
    echo "Installing $AGENT_NAME..."
    eval "$AGENT_INSTALL"
fi

# Agent-specific pre-flight checks
if [ "$AGENT_CMD" = "claude" ]; then
    # Ensure onboarding flags are set to skip browser login dialog.
    # Claude Code may overwrite .claude.json with its own fields,
    # so we merge our required flags in every time.
    if [ -f "$HOME/.claude.json" ]; then
        python3 -c "
import json
with open('$HOME/.claude.json') as f:
    data = json.load(f)
data['hasCompletedOnboarding'] = True
data['hasAvailableSubscription'] = True
with open('$HOME/.claude.json', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null
    else
        cat > "$HOME/.claude.json" <<'CCEOF'
{
  "hasCompletedOnboarding": true,
  "hasAvailableSubscription": true
}
CCEOF
    fi

    # Configure notification hooks (replaces pane-monitor polling).
    # UserPromptSubmit records start time; Notification checks elapsed
    # time and only notifies the host if response took > 30 seconds.
    mkdir -p "$HOME/.claude"
    cat > "$HOME/.claude/settings.json" <<HOOKEOF
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/opt/mvb/scripts/notify-hook.sh start $AGENT_NAME $PANE_INDEX"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/opt/mvb/scripts/notify-hook.sh notify $AGENT_NAME $PANE_INDEX"
          }
        ]
      }
    ]
  }
}
HOOKEOF

    # Auth priority:
    # 1. CLAUDE_CODE_OAUTH_TOKEN env var (Pro subscription via Keychain)
    # 2. ANTHROPIC_API_KEY env var (API usage billing)
    if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        echo "Using Pro subscription (OAuth token)."
        unset ANTHROPIC_API_KEY
    elif [ -n "$ANTHROPIC_API_KEY" ]; then
        echo "Using API key (API usage billing)."
    else
        echo ""
        echo "ERROR: No Claude Code authentication found."
        echo "Browser login doesn't work inside containers."
        echo ""
        echo "  Option 1: Pro subscription (recommended)"
        echo "    Log in to Claude Code on the host first: claude"
        echo "    mvb automatically extracts your token from the macOS Keychain."
        echo ""
        echo "  Option 2: API key"
        echo "    Get a key from https://console.anthropic.com/settings/keys"
        echo "    Run: mvb config"
        echo "    Set: ANTHROPIC_API_KEY=sk-ant-..."
        echo ""
        exec bash
    fi
fi

# Check for existing conversation history (Claude Code specific)
# Claude stores conversations in ~/.claude/projects/<path-with-dashes>/
has_conversation_history() {
    if [ "$AGENT_CMD" != "claude" ]; then
        return 1
    fi
    local project_dir
    project_dir="$HOME/.claude/projects/$(pwd | tr '/' '-')"
    [ -d "$project_dir" ] && ls "$project_dir"/*.jsonl &>/dev/null
}

# Main loop: run agent, restart on exit
while true; do
    # On first run, resume prior conversation if one exists
    local_args="$AGENT_ARGS"
    if has_conversation_history; then
        echo "Resuming previous conversation..."
        local_args="$AGENT_ARGS --continue"
    fi

    echo "Starting $AGENT_NAME..."
    echo "---"

    # Run the agent
    $AGENT_CMD $local_args

    EXIT_CODE=$?
    echo ""
    echo "--- $AGENT_NAME exited (code: $EXIT_CODE) ---"
    echo "Press Enter to restart, or Ctrl-C to stay in shell."

    read -r -t 30 || true

    # If user hit Ctrl-C during read, drop to shell
    if [ $? -gt 128 ]; then
        exec bash
    fi
done
