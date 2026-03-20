#!/bin/bash
# Claude Code notification hook script.
# Called by hooks on UserPromptSubmit (to record start time)
# and Notification (to check elapsed time and notify host).
#
# Usage:
#   notify-hook.sh start <agent-name>    — record prompt start time
#   notify-hook.sh notify <agent-name>   — check elapsed time, notify if > 30s

ACTION="$1"
AGENT_NAME="${2:-claude}"
PANE_INDEX="${3:-0}"
MIN_DURATION="${MVB_NOTIFY_MIN_DURATION:-30}"
STATE_FILE="/tmp/mvb-prompt-start-${AGENT_NAME}-${PANE_INDEX}"

case "$ACTION" in
    start)
        # Record when the user submitted a prompt
        date +%s > "$STATE_FILE"
        ;;
    notify)
        # Check how long Claude has been working
        if [ ! -f "$STATE_FILE" ]; then
            exit 0
        fi

        start_time=$(cat "$STATE_FILE")
        now=$(date +%s)
        elapsed=$((now - start_time))

        # Clean up state file
        rm -f "$STATE_FILE"

        # Only notify if response took longer than threshold
        if [ "$elapsed" -ge "$MIN_DURATION" ]; then
            timestamp=$(date +%s%N)
            echo "${AGENT_NAME}:${PANE_INDEX}" > "/notify/${AGENT_NAME}-${PANE_INDEX}-${timestamp}"
        fi
        ;;
esac
