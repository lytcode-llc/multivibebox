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
