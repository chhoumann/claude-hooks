#!/bin/bash

# Claude Code Prompt Generation from Manual Edits
# Generates a prompt showing all manual edits since last Claude session

set -euo pipefail

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository" >&2
    exit 1
fi

# Check if we have a last snapshot
if [ ! -f .claude/last_snapshot ]; then
    echo "Error: No previous snapshot found. Claude Code needs to run at least once to create a baseline." >&2
    exit 1
fi

SNAPSHOT_REF=$(cat .claude/last_snapshot)
SNAPSHOT_NAME=$(cat .claude/last_snapshot_name 2>/dev/null || echo "unknown")

# Verify the snapshot still exists
if ! git rev-parse "$SNAPSHOT_REF" >/dev/null 2>&1; then
    echo "Error: Snapshot reference $SNAPSHOT_REF no longer exists" >&2
    exit 1
fi

# Generate diff excluding .claude directory
DIFF_OUTPUT=$(git diff "$SNAPSHOT_REF" -- . ':!**/.claude/**' 2>/dev/null || true)

if [ -z "$DIFF_OUTPUT" ]; then
    echo "No changes detected since last Claude Code session (snapshot: $SNAPSHOT_NAME)"
    exit 0
fi

# Get file change summary
FILES_CHANGED=$(git diff --name-status "$SNAPSHOT_REF" -- . ':!**/.claude/**' 2>/dev/null || true)

# Count changes
ADDED=$(echo "$FILES_CHANGED" | grep -c '^A' || true)
MODIFIED=$(echo "$FILES_CHANGED" | grep -c '^M' || true)
DELETED=$(echo "$FILES_CHANGED" | grep -c '^D' || true)

# Generate the prompt
cat <<EOF
# Manual Edits Since Last Claude Session

**Snapshot**: $SNAPSHOT_NAME
**Changes**: $ADDED added, $MODIFIED modified, $DELETED deleted

## Files Changed:
\`\`\`
$FILES_CHANGED
\`\`\`

## Detailed Changes:
\`\`\`diff
$DIFF_OUTPUT
\`\`\`

---
*These changes were made manually after Claude Code finished its last session.*
EOF