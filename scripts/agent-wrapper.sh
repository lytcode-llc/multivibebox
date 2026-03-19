#!/bin/bash
# Launches an agent in a pane with auto-restart on exit

AGENT_NAME="${1:-claude}"
AGENT_CONF="/config/agents/${AGENT_NAME}.conf"
FALLBACK_CONF="/opt/mvb/config/agents/${AGENT_NAME}.conf"

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
    # Create config to skip first-run onboarding (browser login)
    if [ ! -f "$HOME/.claude.json" ]; then
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
            "command": "/opt/mvb/scripts/notify-hook.sh start $AGENT_NAME"
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
            "command": "/opt/mvb/scripts/notify-hook.sh notify $AGENT_NAME"
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

# Main loop: run agent, restart on exit
while true; do
    echo "Starting $AGENT_NAME..."
    echo "---"

    # Run the agent
    $AGENT_CMD $AGENT_ARGS

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
