#!/bin/bash

# Claude Code Prompt Generation V2 - Works with tree object snapshots
# Shows ALL changes including new untracked files and deletions

set -euo pipefail

# Configuration
METADATA_DIR=".claude/snapshot_metadata"

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

# Read snapshot information
SNAPSHOT_COMMIT=$(cat .claude/last_snapshot 2>/dev/null)
SNAPSHOT_NAME=$(cat .claude/last_snapshot_name 2>/dev/null || echo "unknown")

# Try to load metadata
METADATA_FILE="$METADATA_DIR/latest.json"
if [ -f "$METADATA_FILE" ]; then
    SNAPSHOT_DATE=$(grep '"date"' "$METADATA_FILE" | cut -d'"' -f4)
    TOTAL_CHANGES_AT_SNAPSHOT=$(grep '"total_changes"' "$METADATA_FILE" | grep -o '[0-9]*')
else
    SNAPSHOT_DATE="unknown"
    TOTAL_CHANGES_AT_SNAPSHOT="unknown"
fi

# Verify the snapshot still exists
if ! git rev-parse "$SNAPSHOT_COMMIT^{commit}" >/dev/null 2>&1; then
    echo "Error: Snapshot commit $SNAPSHOT_COMMIT no longer exists" >&2
    exit 1
fi

# Create temporary index for current state
TEMP_INDEX=$(mktemp)
export GIT_INDEX_FILE="$TEMP_INDEX"

# Initialize the temporary index
git read-tree HEAD 2>/dev/null || true

# Add all current files to temporary index (including untracked files)
git add -A . 2>/dev/null || true

# Get current tree
CURRENT_TREE=$(git write-tree)

# Restore normal index
unset GIT_INDEX_FILE
rm -f "$TEMP_INDEX"

# Get snapshot tree
SNAPSHOT_TREE=$(git rev-parse "$SNAPSHOT_COMMIT^{tree}")

# Generate comprehensive diff
DIFF_OUTPUT=$(git diff "$SNAPSHOT_TREE" "$CURRENT_TREE" 2>/dev/null || true)

if [ -z "$DIFF_OUTPUT" ]; then
    echo "No changes detected since last Claude Code session (snapshot: $SNAPSHOT_NAME)"
    exit 0
fi

# Get detailed file changes
# Using diff-tree to compare trees directly
FILE_CHANGES=$(git diff-tree --no-commit-id --name-status -r "$SNAPSHOT_TREE" "$CURRENT_TREE" 2>/dev/null || true)

# Categorize changes
ADDED_FILES=$(echo "$FILE_CHANGES" | grep '^A' | cut -f2- || true)
MODIFIED_FILES=$(echo "$FILE_CHANGES" | grep '^M' | cut -f2- || true)
DELETED_FILES=$(echo "$FILE_CHANGES" | grep '^D' | cut -f2- || true)

# Count changes
if [ -n "$ADDED_FILES" ]; then
    ADDED_COUNT=$(echo "$ADDED_FILES" | wc -l)
else
    ADDED_COUNT=0
fi

if [ -n "$MODIFIED_FILES" ]; then
    MODIFIED_COUNT=$(echo "$MODIFIED_FILES" | wc -l)
else
    MODIFIED_COUNT=0
fi

if [ -n "$DELETED_FILES" ]; then
    DELETED_COUNT=$(echo "$DELETED_FILES" | wc -l)
else
    DELETED_COUNT=0
fi
TOTAL_COUNT=$((ADDED_COUNT + MODIFIED_COUNT + DELETED_COUNT))

# Generate categorized output
cat <<EOF
# Manual Edits Since Last Claude Session

**Snapshot**: $SNAPSHOT_NAME
**Snapshot Date**: $SNAPSHOT_DATE
**Changes**: $ADDED_COUNT added, $MODIFIED_COUNT modified, $DELETED_COUNT deleted (Total: $TOTAL_COUNT)

## Summary of Changes

EOF

# Show categorized files
if [ "$ADDED_COUNT" -gt 0 ]; then
    echo "### New Files ($ADDED_COUNT)"
    echo '```'
    echo "$ADDED_FILES" | sed 's/^/+ /'
    echo '```'
    echo
fi

if [ "$MODIFIED_COUNT" -gt 0 ]; then
    echo "### Modified Files ($MODIFIED_COUNT)"
    echo '```'
    echo "$MODIFIED_FILES" | sed 's/^/M /'
    echo '```'
    echo
fi

if [ "$DELETED_COUNT" -gt 0 ]; then
    echo "### Deleted Files ($DELETED_COUNT)"
    echo '```'
    echo "$DELETED_FILES" | sed 's/^/- /'
    echo '```'
    echo
fi

# Show full diff
cat <<EOF
## Detailed Changes
\`\`\`diff
$DIFF_OUTPUT
\`\`\`

---
*These changes were made manually after Claude Code finished its last session.*
*This snapshot captured ALL files including untracked files.*
EOF