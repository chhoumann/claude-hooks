#!/bin/bash

# Clean up old Claude Code snapshots with configurable retention

set -euo pipefail

SNAPSHOT_REF_PREFIX="refs/claude/snapshots"
METADATA_DIR=".claude/snapshot_metadata"

# Default: keep last 20 snapshots or 7 days, whichever is more
KEEP_COUNT=${1:-20}
KEEP_DAYS=${2:-7}

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository" >&2
    exit 1
fi

echo "Claude Code Snapshot Cleanup"
echo "==========================="
echo "Policy: Keep last $KEEP_COUNT snapshots AND all snapshots from last $KEEP_DAYS days"
echo

# Get current timestamp
CURRENT_TIME=$(date +%s)
CUTOFF_TIME=$((CURRENT_TIME - (KEEP_DAYS * 24 * 60 * 60)))

# Get all snapshots sorted by date (oldest first)
SNAPSHOTS=$(git for-each-ref --sort=committerdate --format='%(refname) %(committerdate:unix)' "$SNAPSHOT_REF_PREFIX")

# Count total snapshots
TOTAL_COUNT=$(echo "$SNAPSHOTS" | wc -l)

if [ "$TOTAL_COUNT" -eq 0 ]; then
    echo "No snapshots found."
    exit 0
fi

echo "Total snapshots: $TOTAL_COUNT"

# Build list of snapshots to keep
KEEP_REFS=""

# Keep by count (last N snapshots)
echo "$SNAPSHOTS" | tail -n "$KEEP_COUNT" | while read -r ref timestamp; do
    KEEP_REFS="$KEEP_REFS $ref"
done

# Keep by age
echo "$SNAPSHOTS" | while read -r ref timestamp; do
    if [ "$timestamp" -gt "$CUTOFF_TIME" ]; then
        KEEP_REFS="$KEEP_REFS $ref"
    fi
done

# Get unique refs to keep
KEEP_REFS=$(echo $KEEP_REFS | tr ' ' '\n' | sort -u)
KEEP_COUNT=$(echo "$KEEP_REFS" | wc -l)

# Find refs to delete
DELETE_COUNT=0
DELETE_REFS=""

echo "$SNAPSHOTS" | while read -r ref timestamp; do
    if ! echo "$KEEP_REFS" | grep -q "$ref"; then
        DELETE_REFS="$DELETE_REFS $ref"
        DELETE_COUNT=$((DELETE_COUNT + 1))
    fi
done

DELETE_COUNT=$(echo $DELETE_REFS | wc -w)

if [ "$DELETE_COUNT" -eq 0 ]; then
    echo "No snapshots to clean up."
    exit 0
fi

echo "Snapshots to keep: $KEEP_COUNT"
echo "Snapshots to delete: $DELETE_COUNT"
echo

# Show what will be deleted
echo "Snapshots to be deleted:"
for ref in $DELETE_REFS; do
    TIMESTAMP=$(basename "$ref")
    COMMIT=$(git rev-parse "$ref")
    DATE=$(git show -s --format=%ci "$COMMIT" | cut -d' ' -f1,2)
    echo "  - claude-snapshot-$TIMESTAMP ($DATE) ${COMMIT:0:7}"
done

echo
read -p "Proceed with cleanup? (y/N) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Delete the refs
for ref in $DELETE_REFS; do
    git update-ref -d "$ref"
    
    # Also delete metadata if exists
    TIMESTAMP=$(basename "$ref")
    rm -f "$METADATA_DIR/$TIMESTAMP.json"
done

echo "✓ Deleted $DELETE_COUNT snapshots."

# Run git gc to actually free up space
echo
read -p "Run 'git gc' to reclaim disk space? (y/N) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Running git garbage collection..."
    git gc --prune=now
    echo "✓ Garbage collection complete."
fi