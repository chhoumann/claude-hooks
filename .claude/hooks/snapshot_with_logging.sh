#!/bin/bash

# Enhanced snapshot script with logging and error handling

set -euo pipefail

LOG_FILE=".claude/snapshot.log"
STATS_FILE=".claude/snapshot_stats.json"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Initialize logging
mkdir -p .claude
log "=== Snapshot hook triggered ==="

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log "ERROR: Not in a git repository"
    exit 0
fi

# Update git index
git update-index -q --refresh 2>/dev/null || true

# Get repository statistics
MODIFIED_COUNT=$(git diff --name-only | wc -l)
UNTRACKED_COUNT=$(git ls-files --others --exclude-standard | wc -l)
STAGED_COUNT=$(git diff --cached --name-only | wc -l)

log "Repository state: $MODIFIED_COUNT modified, $UNTRACKED_COUNT untracked, $STAGED_COUNT staged"

# Check if there are any changes to snapshot
if [ "$MODIFIED_COUNT" -eq 0 ] && [ "$UNTRACKED_COUNT" -eq 0 ] && [ "$STAGED_COUNT" -eq 0 ]; then
    log "No changes to snapshot"
    exit 0
fi

# Create snapshot
SNAPSHOT_NAME="claude-snapshot-$(date +%s)"
SNAPSHOT_DESC="Claude Code snapshot at $(date '+%Y-%m-%d %H:%M:%S')"

# Try to create snapshot
if git stash push -u -q -m "$SNAPSHOT_NAME" 2>/dev/null; then
    STASH_REF=$(git rev-parse stash@{0})
    
    # Pop the stash to restore state
    git stash pop -q 2>/dev/null || true
    
    # Store snapshot info
    echo "$STASH_REF" > .claude/last_snapshot
    echo "$SNAPSHOT_NAME" > .claude/last_snapshot_name
    
    # Update statistics
    cat > "$STATS_FILE" <<EOF
{
  "last_snapshot": "$SNAPSHOT_NAME",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "ref": "$STASH_REF",
  "files": {
    "modified": $MODIFIED_COUNT,
    "untracked": $UNTRACKED_COUNT,
    "staged": $STAGED_COUNT
  }
}
EOF
    
    log "SUCCESS: Created snapshot $SNAPSHOT_NAME ($STASH_REF)"
    echo "Created snapshot: $SNAPSHOT_NAME" >&2
else
    log "ERROR: Failed to create snapshot"
    exit 1
fi