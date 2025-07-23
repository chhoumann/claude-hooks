#!/bin/bash

# Claude Code Snapshot Hook
# Uses git tree objects to capture ALL files including untracked files
# Stores snapshots as refs without affecting working directory

set -euo pipefail

# Configuration
SNAPSHOT_REF_PREFIX="refs/claude/snapshots"
METADATA_DIR=".claude/snapshot_metadata"
LOG_FILE=".claude/snapshot.log"
LOG_MAX_SIZE=10240  # 10KB
LOG_MAX_LINES=1000  # Keep last 1000 lines

# Simple log rotation
rotate_log() {
    if [ -f "$LOG_FILE" ]; then
        # Check file size
        local size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt "$LOG_MAX_SIZE" ]; then
            # Keep last N lines
            tail -n "$LOG_MAX_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
        fi
    fi
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Initialize
mkdir -p .claude "$METADATA_DIR"
rotate_log
log "=== Snapshot hook triggered ==="

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log "ERROR: Not in a git repository"
    exit 0
fi

# Create a temporary index to avoid disturbing the user's staging area
TEMP_INDEX=$(mktemp)
export GIT_INDEX_FILE="$TEMP_INDEX"

# Initialize the temporary index by reading the current HEAD
git read-tree HEAD 2>/dev/null || true

# Capture current state
TIMESTAMP=$(date +%s)
SNAPSHOT_NAME="claude-snapshot-$TIMESTAMP"
SNAPSHOT_DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Get repository statistics before adding
TRACKED_MODIFIED=$(git diff --name-only 2>/dev/null | wc -l)
TRACKED_STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l)
UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
IGNORED=$(git ls-files --others --ignored --exclude-standard 2>/dev/null | wc -l)
DELETED=$(git ls-files --deleted 2>/dev/null | wc -l)

log "Repository state: $TRACKED_MODIFIED modified, $TRACKED_STAGED staged, $UNTRACKED untracked, $IGNORED ignored, $DELETED deleted"

# Check if there's anything to snapshot
TOTAL_CHANGES=$((TRACKED_MODIFIED + TRACKED_STAGED + UNTRACKED + DELETED))
if [ "$TOTAL_CHANGES" -eq 0 ]; then
    log "No changes to snapshot"
    unset GIT_INDEX_FILE
    rm -f "$TEMP_INDEX"
    exit 0
fi

# Add all files to temporary index
# -A adds everything including deletions
if ! git add -A . 2>/dev/null; then
    log "WARNING: Some files could not be added to snapshot"
fi

# Create tree object
TREE_HASH=$(git write-tree)
log "Created tree object: $TREE_HASH"

# Create commit object with metadata
PARENT=$(git rev-parse HEAD 2>/dev/null || echo "")
COMMIT_MSG="Claude Code Snapshot

Date: $SNAPSHOT_DATE
Modified files: $TRACKED_MODIFIED
Staged files: $TRACKED_STAGED
Untracked files: $UNTRACKED
Ignored files: $IGNORED
Deleted files: $DELETED"

if [ -n "$PARENT" ]; then
    COMMIT_HASH=$(echo "$COMMIT_MSG" | git commit-tree "$TREE_HASH" -p "$PARENT")
else
    # Initial commit case
    COMMIT_HASH=$(echo "$COMMIT_MSG" | git commit-tree "$TREE_HASH")
fi

# Store snapshot as hidden ref
SNAPSHOT_REF="$SNAPSHOT_REF_PREFIX/$TIMESTAMP"
git update-ref "$SNAPSHOT_REF" "$COMMIT_HASH"

# Store metadata
cat > "$METADATA_DIR/$TIMESTAMP.json" <<EOF
{
  "name": "$SNAPSHOT_NAME",
  "timestamp": "$TIMESTAMP",
  "date": "$SNAPSHOT_DATE",
  "tree": "$TREE_HASH",
  "commit": "$COMMIT_HASH",
  "ref": "$SNAPSHOT_REF",
  "parent": "$PARENT",
  "stats": {
    "modified": $TRACKED_MODIFIED,
    "staged": $TRACKED_STAGED,
    "untracked": $UNTRACKED,
    "ignored": $IGNORED,
    "deleted": $DELETED,
    "total_changes": $TOTAL_CHANGES
  }
}
EOF

# Update references for easy access
echo "$COMMIT_HASH" > .claude/last_snapshot
ln -sf "$TIMESTAMP.json" "$METADATA_DIR/latest.json"

# Store snapshot name for compatibility
echo "$SNAPSHOT_NAME" > .claude/last_snapshot_name
echo "$TIMESTAMP" > .claude/last_snapshot_timestamp

# Cleanup temporary index
unset GIT_INDEX_FILE
rm -f "$TEMP_INDEX"

log "SUCCESS: Created snapshot $SNAPSHOT_NAME (commit: $COMMIT_HASH, ref: $SNAPSHOT_REF)"
echo "Created snapshot: $SNAPSHOT_NAME (captured all $TOTAL_CHANGES changes)" >&2

# Optional: Cleanup old snapshots (keep last 50)
SNAPSHOT_COUNT=$(git for-each-ref --count=51 --format='%(refname)' "$SNAPSHOT_REF_PREFIX" | wc -l)
if [ "$SNAPSHOT_COUNT" -gt 50 ]; then
    log "Cleaning up old snapshots (keeping last 50)"
    git for-each-ref --sort=committerdate --format='%(refname)' "$SNAPSHOT_REF_PREFIX" | 
        head -n -50 | 
        xargs -r -n1 git update-ref -d
fi