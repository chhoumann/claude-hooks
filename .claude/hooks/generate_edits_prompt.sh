#!/bin/bash

# Enhanced prompt generator V2 with output options
# Works with the new tree-based snapshot system
# Usage: ./generate_edits_prompt_v2.sh [--file output.md] [--clipboard] [--include-ignored]

set -euo pipefail

OUTPUT_FILE=""
USE_CLIPBOARD=false
INCLUDE_IGNORED=false
MAX_DIFF_LINES=500
OPEN_IN_EDITOR=false

# Cross-platform clipboard helper (macOS, Linux X11/Wayland, Windows/WSL)
copy_to_clipboard() {
    local _data="$1"
    if command -v pbcopy >/dev/null 2>&1; then
        printf "%s" "$_data" | pbcopy
        echo "Prompt copied to clipboard (macOS)" >&2
        return 0
    elif command -v wl-copy >/dev/null 2>&1; then
        printf "%s" "$_data" | wl-copy
        echo "Prompt copied to clipboard (Wayland)" >&2
        return 0
    elif command -v xclip >/dev/null 2>&1; then
        printf "%s" "$_data" | xclip -selection clipboard
        echo "Prompt copied to clipboard (X11)" >&2
        return 0
    elif command -v clip >/dev/null 2>&1; then
        # Native Windows (Git Bash / PowerShell)
        printf "%s" "$_data" | clip
        echo "Prompt copied to clipboard (Windows)" >&2
        return 0
    elif command -v clip.exe >/dev/null 2>&1; then
        # WSL fallback
        printf "%s" "$_data" | clip.exe
        echo "Prompt copied to clipboard (WSL)" >&2
        return 0
    fi

    return 1
}

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
        --include-ignored)
            INCLUDE_IGNORED=true
            shift
            ;;
        --max-lines)
            MAX_DIFF_LINES="$2"
            shift 2
            ;;
        --open)
            OPEN_IN_EDITOR=true
            shift
            ;;
        --help)
            cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --file <output.md>    Save prompt to file
  --clipboard          Copy prompt to clipboard
  --include-ignored    Include changes to .gitignored files in prompt
  --max-lines <n>      Maximum diff lines to include (default: 500)
  --open               Open the output file in your editor (requires --file)
  --help               Show this help message

Examples:
  $0                           # Output to stdout
  $0 --clipboard               # Copy to clipboard
  $0 --file changes.md         # Save to file
  $0 --clipboard --max-lines 1000  # Copy with larger diff
  $0 --file changes.md --open      # Save to file and open in editor
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

# Validate arguments
if [ "$OPEN_IN_EDITOR" = true ] && [ -z "$OUTPUT_FILE" ]; then
    echo "Error: --open requires --file <output.md>" >&2
    exit 1
fi

# Generate the prompt using prompt script
PROMPT_OUTPUT=$(.claude/hooks/prompt_from_edits.sh)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    # Error occurred or no changes
    if [ -n "$OUTPUT_FILE" ] || [ "$USE_CLIPBOARD" = true ]; then
        echo "$PROMPT_OUTPUT" >&2
    else
        echo "$PROMPT_OUTPUT"
    fi
    exit $EXIT_CODE
fi

# Check if diff is too large and truncate if needed
LINE_COUNT=$(echo "$PROMPT_OUTPUT" | wc -l)
if [ "$LINE_COUNT" -gt "$MAX_DIFF_LINES" ]; then
    # Find where the diff section starts
    DIFF_START=$(echo "$PROMPT_OUTPUT" | grep -n '```diff' | cut -d: -f1)
    DIFF_END=$(echo "$PROMPT_OUTPUT" | grep -n '```$' | tail -1 | cut -d: -f1)
    
    if [ -n "$DIFF_START" ] && [ -n "$DIFF_END" ]; then
        # Extract parts
        HEADER=$(echo "$PROMPT_OUTPUT" | head -n "$DIFF_START")
        FOOTER=$(echo "$PROMPT_OUTPUT" | tail -n +$((DIFF_END + 1)))
        DIFF_CONTENT=$(echo "$PROMPT_OUTPUT" | sed -n "$((DIFF_START + 1)),$((DIFF_END - 1))p")
        
        # Truncate diff
        TRUNCATED_DIFF=$(echo "$DIFF_CONTENT" | head -n $((MAX_DIFF_LINES - 100)))
        
        # Rebuild prompt
        PROMPT_OUTPUT=$(cat <<EOF
$HEADER
$TRUNCATED_DIFF

... [Diff truncated at $MAX_DIFF_LINES lines. Full diff contains $LINE_COUNT lines] ...
\`\`\`
$FOOTER
EOF
)
        
        echo "Warning: Diff truncated to $MAX_DIFF_LINES lines (was $LINE_COUNT lines)" >&2
    fi
fi

# Add additional context if requested
if [ "$INCLUDE_IGNORED" = true ]; then
    IGNORED_COUNT=$(git ls-files --others --ignored --exclude-standard | wc -l)
    if [ "$IGNORED_COUNT" -gt 0 ]; then
        PROMPT_OUTPUT="$PROMPT_OUTPUT

Note: This snapshot includes $IGNORED_COUNT ignored files (.gitignore'd files)."
    fi
fi

# Handle output options
if [ -n "$OUTPUT_FILE" ]; then
    echo "$PROMPT_OUTPUT" > "$OUTPUT_FILE"
    echo "Prompt saved to: $OUTPUT_FILE" >&2
    echo "Size: $(wc -c < "$OUTPUT_FILE") bytes, $(wc -l < "$OUTPUT_FILE") lines" >&2
    
    # Open in editor if requested
    if [ "$OPEN_IN_EDITOR" = true ]; then
        # Try to use the user's preferred editor
        EDITOR_CMD="${VISUAL:-${EDITOR:-vi}}"
        echo "Opening in editor: $EDITOR_CMD" >&2
        "$EDITOR_CMD" "$OUTPUT_FILE"
    fi
fi

if [ "$USE_CLIPBOARD" = true ]; then
    if ! copy_to_clipboard "$PROMPT_OUTPUT"; then
        echo "Warning: No clipboard utility found. Install pbcopy (macOS), wl-copy/xclip (Linux), or ensure clip.exe is available on Windows." >&2
        # Fallback to stdout if no other output target
        if [ -z "$OUTPUT_FILE" ]; then
            echo "$PROMPT_OUTPUT"
        fi
    fi
fi

# If no output option specified, print to stdout
if [ -z "$OUTPUT_FILE" ] && [ "$USE_CLIPBOARD" = false ]; then
    echo "$PROMPT_OUTPUT"
fi

# Show snapshot info
if [ -f .claude/hooks/list_snapshots.sh ]; then
    echo >&2
    echo "Snapshot info: $(.claude/hooks/list_snapshots.sh | grep CURRENT | head -1)" >&2
fi