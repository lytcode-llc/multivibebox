#!/bin/bash
# Explicit file-open command for use inside the container.
# Writes a file path to /open/ so the host watcher can open it in the editor.
# Usage: mvb-open <file-path>

FILE_PATH="$1"

if [ -z "$FILE_PATH" ]; then
    echo "Usage: mvb-open <file-path>"
    exit 1
fi

# Resolve relative paths
if [[ "$FILE_PATH" != /* ]]; then
    FILE_PATH="$(pwd)/$FILE_PATH"
fi

# Verify file exists
if [ ! -f "$FILE_PATH" ]; then
    echo "File not found: $FILE_PATH"
    exit 1
fi

timestamp=$(date +%s%N)
echo "$FILE_PATH" > "/open/manual-${timestamp}"
echo "Opening $FILE_PATH on host..."
