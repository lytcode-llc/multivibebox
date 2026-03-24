#!/bin/bash
# Host-side daemon: watches notify/ dir for event files,
# plays sounds on agent output, debounces per agent.
# Supports macOS (afplay), Linux (paplay/aplay), and WSL (powershell.exe).

NOTIFY_DIR="${1:-.}/notify"
OPEN_DIR="${1:-.}/open"
PROJECTS_DIR="${1:-.}/config/projects"
COOLDOWN=10  # seconds between sounds per agent

MVB_TMP_DIR="/tmp/mvb-watcher-$$"
mkdir -p "$MVB_TMP_DIR"
trap 'rm -rf "$MVB_TMP_DIR"' EXIT

get_agent_sound() {
    local f="$MVB_TMP_DIR/sound_${1}"
    if [ -f "$f" ]; then cat "$f"; else echo "$DEFAULT_SOUND"; fi
}

get_last_played() {
    local f="$MVB_TMP_DIR/last_${1}"
    if [ -f "$f" ]; then cat "$f"; else echo 0; fi
}

set_last_played() {
    echo "$2" > "$MVB_TMP_DIR/last_${1}"
}

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

# --- Announce pane number via text-to-speech ---

announce_pane() {
    local pane="$1"
    case "$MVB_PLATFORM" in
        macos)
            say "pane $pane" &
            ;;
        linux)
            if command -v espeak &>/dev/null; then
                espeak "pane $pane" &
            elif command -v spd-say &>/dev/null; then
                spd-say "pane $pane" &
            fi
            ;;
        wsl)
            powershell.exe -NoProfile -c "Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('pane $pane')" &
            ;;
    esac
}

# --- Translate container path to host path ---

translate_path() {
    local container_path="$1"
    local host_path=""

    # Search project files for path mappings
    for pfile in "$PROJECTS_DIR"/*.json; do
        [ -f "$pfile" ] || continue
        local path_map
        path_map=$(jq -r '.path_map // empty' "$pfile" 2>/dev/null)
        [ -z "$path_map" ] && continue

        # path_map format: "container=host" or "container=host;container2=host2"
        IFS=';' read -ra mappings <<< "$path_map"
        for mapping in "${mappings[@]}"; do
            local cprefix="${mapping%%=*}"
            local hprefix="${mapping#*=}"
            if [[ "$container_path" == "$cprefix"* ]]; then
                host_path="${hprefix}${container_path#$cprefix}"
                echo "$host_path"
                return
            fi
        done
    done

    echo ""
}

# --- Open file on host ---

open_file() {
    local host_path="$1"
    [ -z "$host_path" ] && return
    [ ! -f "$host_path" ] && return

    case "$MVB_PLATFORM" in
        macos)
            if [ -n "$EDITOR" ]; then
                $EDITOR "$host_path" &
            else
                open "$host_path" &
            fi
            ;;
        linux)
            if [ -n "$EDITOR" ]; then
                $EDITOR "$host_path" &
            elif command -v xdg-open &>/dev/null; then
                xdg-open "$host_path" &
            fi
            ;;
        wsl)
            local win_path
            win_path=$(wslpath -w "$host_path" 2>/dev/null || echo "$host_path")
            cmd.exe /c start "" "$win_path" &
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
                    echo "$resolved" > "$MVB_TMP_DIR/sound_${name}"
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

mkdir -p "$NOTIFY_DIR" "$OPEN_DIR"

while true; do
    # Check for new event files
    for event_file in "$NOTIFY_DIR"/*; do
        [ -f "$event_file" ] || continue

        event_data=$(cat "$event_file" 2>/dev/null)
        rm -f "$event_file"

        [ -z "$event_data" ] && continue

        # Parse agent_name:pane_index
        agent_name="${event_data%%:*}"
        pane_index="${event_data#*:}"

        # Debounce: check cooldown (per pane)
        debounce_key="${agent_name}-${pane_index}"
        now=$(date +%s)
        last=$(get_last_played "$debounce_key")
        elapsed=$((now - last))

        if [ "$elapsed" -ge "$COOLDOWN" ]; then
            sound=$(get_agent_sound "$agent_name")
            play_sound "$sound"
            announce_pane "$pane_index"
            set_last_played "$debounce_key" "$now"
        fi
    done

    # Check for file-open requests
    for open_file_event in "$OPEN_DIR"/*; do
        [ -f "$open_file_event" ] || continue

        container_path=$(cat "$open_file_event" 2>/dev/null)
        rm -f "$open_file_event"

        [ -z "$container_path" ] && continue

        host_path=$(translate_path "$container_path")
        if [ -n "$host_path" ]; then
            open_file "$host_path"
        fi
    done

    sleep 1
done
