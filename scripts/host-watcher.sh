#!/bin/bash
# Host-side daemon: watches notify/ dir for event files,
# plays sounds on agent output, debounces per agent.
# Supports macOS (afplay), Linux (paplay/aplay), and WSL (powershell.exe).

NOTIFY_DIR="${1:-.}/notify"
COOLDOWN=10  # seconds between sounds per agent

declare -A LAST_PLAYED
declare -A AGENT_SOUNDS

# --- Platform detection ---

detect_platform() {
    case "$(uname -s)" in
        Darwin)
            MVB_PLATFORM="macos"
            ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                MVB_PLATFORM="wsl"
            else
                MVB_PLATFORM="linux"
            fi
            ;;
        *)
            MVB_PLATFORM="unknown"
            ;;
    esac
}

detect_platform

# --- Sound resolution per platform ---

# macOS: system sounds in /System/Library/Sounds/<Name>.aiff
# Linux: bundled sounds in repo sounds/ dir, or system sounds
# WSL:   Windows system sounds via powershell.exe

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CUSTOM_SOUNDS_DIR="$REPO_DIR/sounds"

resolve_sound_macos() {
    local name="$1"
    local path="/System/Library/Sounds/${name}.aiff"
    if [ -f "$path" ]; then
        echo "$path"
    else
        echo "/System/Library/Sounds/Glass.aiff"
    fi
}

resolve_sound_linux() {
    local name="$1"
    # Check repo sounds/ dir first
    for ext in wav ogg aiff; do
        local path="$CUSTOM_SOUNDS_DIR/${name}.${ext}"
        if [ -f "$path" ]; then
            echo "$path"
            return
        fi
    done
    # Fall back to system sounds
    for path in \
        "/usr/share/sounds/freedesktop/stereo/complete.oga" \
        "/usr/share/sounds/freedesktop/stereo/bell.oga" \
        "/usr/share/sounds/sound-icons/glass-water-1.wav"; do
        if [ -f "$path" ]; then
            echo "$path"
            return
        fi
    done
    echo ""
}

resolve_sound_wsl() {
    local name="$1"
    # Check repo sounds/ dir first (accessible from WSL)
    for ext in wav ogg aiff; do
        local path="$CUSTOM_SOUNDS_DIR/${name}.${ext}"
        if [ -f "$path" ]; then
            echo "$path"
            return
        fi
    done
    # Fall back to Windows system sounds
    echo "C:\\Windows\\Media\\notify.wav"
}

resolve_sound() {
    case "$MVB_PLATFORM" in
        macos) resolve_sound_macos "$1" ;;
        linux) resolve_sound_linux "$1" ;;
        wsl)   resolve_sound_wsl "$1" ;;
        *)     echo "" ;;
    esac
}

DEFAULT_SOUND=$(resolve_sound "Glass")

# --- Play sound per platform ---

play_sound() {
    local sound="$1"
    [ -z "$sound" ] && return

    case "$MVB_PLATFORM" in
        macos)
            afplay "$sound" &
            ;;
        linux)
            if command -v paplay &>/dev/null; then
                paplay "$sound" &
            elif command -v aplay &>/dev/null; then
                aplay -q "$sound" &
            fi
            ;;
        wsl)
            if [[ "$sound" == /* ]]; then
                # WSL path — convert to Windows path
                local win_path
                win_path=$(wslpath -w "$sound" 2>/dev/null || echo "$sound")
                powershell.exe -NoProfile -c "(New-Object Media.SoundPlayer '$win_path').PlaySync()" &
            else
                # Already a Windows path
                powershell.exe -NoProfile -c "(New-Object Media.SoundPlayer '$sound').PlaySync()" &
            fi
            ;;
    esac
}

# --- Load agent sound preferences from config ---

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
                local resolved
                resolved=$(resolve_sound "$sound")
                if [ -n "$resolved" ]; then
                    AGENT_SOUNDS["$name"]="$resolved"
                fi
            fi
        done
    fi
}

load_agent_sounds "$(dirname "$NOTIFY_DIR")"

echo "Platform: $MVB_PLATFORM"
echo "Watching $NOTIFY_DIR for notifications..."
echo "Cooldown: ${COOLDOWN}s per agent"
if [ "$MVB_PLATFORM" = "unknown" ]; then
    echo "WARNING: Unknown platform — audio notifications disabled."
fi
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
            play_sound "$sound"
            LAST_PLAYED["$agent_name"]=$now
        fi
    done

    sleep 1
done
