#!/bin/bash
# Host-side daemon: watches notify/ dir for event files,
# plays macOS sounds via afplay, debounces per agent.

NOTIFY_DIR="${1:-.}/notify"
COOLDOWN=10  # seconds between sounds per agent
DEFAULT_SOUND="/System/Library/Sounds/Glass.aiff"

declare -A LAST_PLAYED
declare -A AGENT_SOUNDS

# Load agent sound preferences from config
load_agent_sounds() {
    local config_dir="${1:-.}/config/agents"
    if [ -d "$config_dir" ]; then
        for conf in "$config_dir"/*.conf; do
            [ -f "$conf" ] || continue
            local name="" sound=""
            while IFS='=' read -r key val; do
                key=$(echo "$key" | xargs)
                val=$(echo "$val" | xargs | tr -d '"')
                case "$key" in
                    AGENT_NAME) name="$val" ;;
                    NOTIFY_SOUND) sound="$val" ;;
                esac
            done < "$conf"
            if [ -n "$name" ] && [ -n "$sound" ]; then
                local sound_path="/System/Library/Sounds/${sound}.aiff"
                if [ -f "$sound_path" ]; then
                    AGENT_SOUNDS["$name"]="$sound_path"
                fi
            fi
        done
    fi
}

load_agent_sounds "$(dirname "$NOTIFY_DIR")"

echo "Watching $NOTIFY_DIR for notifications..."
echo "Cooldown: ${COOLDOWN}s per agent"
echo "Press Ctrl-C to stop."

mkdir -p "$NOTIFY_DIR"

while true; do
    # Check for new event files
    for event_file in "$NOTIFY_DIR"/*; do
        [ -f "$event_file" ] || continue

        agent_name=$(cat "$event_file" 2>/dev/null)
        rm -f "$event_file"

        [ -z "$agent_name" ] && continue

        # Debounce: check cooldown
        now=$(date +%s)
        last=${LAST_PLAYED["$agent_name"]:-0}
        elapsed=$((now - last))

        if [ "$elapsed" -ge "$COOLDOWN" ]; then
            sound="${AGENT_SOUNDS[$agent_name]:-$DEFAULT_SOUND}"
            afplay "$sound" &
            LAST_PLAYED["$agent_name"]=$now
        fi
    done

    sleep 1
done
