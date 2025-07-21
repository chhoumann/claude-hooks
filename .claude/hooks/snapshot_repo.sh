#!/bin/bash

# Claude Code Snapshot Hook
# Creates a git snapshot without affecting user's workflow
# Uses git stash for simplicity (can switch to hidden refs if needed)

set -euo pipefail

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Not in a git repository, skipping snapshot" >&2
    exit 0
fi

# Update git index to ensure accurate status
git update-index -q --refresh 2>/dev/null || true

# Check if there are any changes to snapshot
if git diff-index --quiet HEAD -- && ! git ls-files --others --exclude-standard | grep -q .; then
    echo "No changes to snapshot" >&2
    exit 0
fi

# Create snapshot using git stash
SNAPSHOT_NAME="claude-snapshot-$(date +%s)"
SNAPSHOT_DESC="Claude Code snapshot at $(date '+%Y-%m-%d %H:%M:%S')"

# Stash all changes including untracked files
# Using -u to include untracked files, -q for quiet operation
git stash push -u -q -m "$SNAPSHOT_NAME" 2>/dev/null

# Get the stash reference
STASH_REF=$(git rev-parse stash@{0})

# Pop the stash immediately to restore working directory
# This leaves the snapshot in the reflog but restores the user's state
git stash pop -q 2>/dev/null || true

# Store the snapshot reference
mkdir -p .claude
echo "$STASH_REF" > .claude/last_snapshot
echo "$SNAPSHOT_NAME" > .claude/last_snapshot_name

echo "Created snapshot: $SNAPSHOT_NAME ($STASH_REF)" >&2