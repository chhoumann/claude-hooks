#!/bin/bash

# Enhanced prompt generator with output options
# Usage: ./generate_edits_prompt.sh [--file output.md] [--clipboard]

set -euo pipefail

OUTPUT_FILE=""
USE_CLIPBOARD=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --clipboard)
            USE_CLIPBOARD=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--file output.md] [--clipboard]" >&2
            exit 1
            ;;
    esac
done

# Generate the prompt
PROMPT_OUTPUT=$(.claude/hooks/prompt_from_edits.sh)

# Handle output options
if [ -n "$OUTPUT_FILE" ]; then
    echo "$PROMPT_OUTPUT" > "$OUTPUT_FILE"
    echo "Prompt saved to: $OUTPUT_FILE" >&2
fi

if [ "$USE_CLIPBOARD" = true ]; then
    # Try different clipboard commands based on OS
    if command -v pbcopy >/dev/null 2>&1; then
        # macOS
        echo "$PROMPT_OUTPUT" | pbcopy
        echo "Prompt copied to clipboard (macOS)" >&2
    elif command -v xclip >/dev/null 2>&1; then
        # Linux with xclip
        echo "$PROMPT_OUTPUT" | xclip -selection clipboard
        echo "Prompt copied to clipboard (Linux/xclip)" >&2
    elif command -v clip.exe >/dev/null 2>&1; then
        # WSL
        echo "$PROMPT_OUTPUT" | clip.exe
        echo "Prompt copied to clipboard (WSL)" >&2
    else
        echo "Warning: No clipboard command found" >&2
        USE_CLIPBOARD=false
    fi
fi

# If no output option specified, print to stdout
if [ -z "$OUTPUT_FILE" ] && [ "$USE_CLIPBOARD" = false ]; then
    echo "$PROMPT_OUTPUT"
fi