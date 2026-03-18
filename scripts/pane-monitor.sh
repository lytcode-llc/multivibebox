#!/bin/bash
# In-container daemon: polls tmux panes for output changes,
# writes event files to /notify/ for the host watcher to pick up.

POLL_INTERVAL=2
HASH_DIR="/tmp/mvb-pane-hashes"
mkdir -p "$HASH_DIR"

while true; do
    # Get list of panes in the mvb session
    panes=$(tmux list-panes -t mvb -F "#{pane_index}:#{pane_title}" 2>/dev/null) || {
        sleep "$POLL_INTERVAL"
        continue
    }

    while IFS=: read -r pane_index pane_title; do
        [ -z "$pane_index" ] && continue

        # Capture last 5 lines of pane content
        content=$(tmux capture-pane -t "mvb:main.${pane_index}" -p -S -5 2>/dev/null) || continue

        # Hash the content
        new_hash=$(echo "$content" | md5sum | cut -d' ' -f1)
        hash_file="${HASH_DIR}/${pane_index}"

        # Compare with previous hash
        old_hash=""
        [ -f "$hash_file" ] && old_hash=$(cat "$hash_file")

        if [ "$new_hash" != "$old_hash" ]; then
            echo "$new_hash" > "$hash_file"

            # Don't notify on first observation (initial state)
            if [ -n "$old_hash" ]; then
                agent_name="${pane_title:-pane${pane_index}}"
                timestamp=$(date +%s%N)
                echo "$agent_name" > "/notify/${agent_name}-${timestamp}"
            fi
        fi
    done <<< "$panes"

    sleep "$POLL_INTERVAL"
done
