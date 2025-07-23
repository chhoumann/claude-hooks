#!/bin/bash

# Restore working directory to a specific Claude Code snapshot
# This is useful for reviewing or recovering previous states

set -euo pipefail

SNAPSHOT_REF_PREFIX="refs/claude/snapshots"

# Check arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <timestamp|snapshot-name> [--dry-run]"
    echo
    echo "Examples:"
    echo "  $0 1234567890                    # Restore to timestamp"
    echo "  $0 claude-snapshot-1234567890    # Restore to named snapshot"
    echo "  $0 latest                        # Restore to latest snapshot"
    echo "  $0 1234567890 --dry-run          # Show what would change"
    echo
    echo "Use 'list_snapshots.sh' to see available snapshots."
    exit 1
fi

# Parse arguments
SNAPSHOT_ID="$1"
DRY_RUN=false
if [ "${2:-}" = "--dry-run" ]; then
    DRY_RUN=true
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository" >&2
    exit 1
fi

# Handle special case: latest
if [ "$SNAPSHOT_ID" = "latest" ]; then
    if [ -f .claude/last_snapshot_timestamp ]; then
        SNAPSHOT_ID=$(cat .claude/last_snapshot_timestamp)
    else
        echo "Error: No latest snapshot found" >&2
        exit 1
    fi
fi

# Extract timestamp from snapshot name if needed
if [[ "$SNAPSHOT_ID" =~ ^claude-snapshot-(.+)$ ]]; then
    SNAPSHOT_ID="${BASH_REMATCH[1]}"
fi

# Build ref name
SNAPSHOT_REF="$SNAPSHOT_REF_PREFIX/$SNAPSHOT_ID"

# Verify snapshot exists
if ! git rev-parse "$SNAPSHOT_REF" >/dev/null 2>&1; then
    echo "Error: Snapshot not found: $SNAPSHOT_ID" >&2
    echo "Use '.claude/hooks/list_snapshots.sh' to see available snapshots." >&2
    exit 1
fi

# Get snapshot details
SNAPSHOT_COMMIT=$(git rev-parse "$SNAPSHOT_REF")
SNAPSHOT_TREE=$(git rev-parse "$SNAPSHOT_REF^{tree}")
SNAPSHOT_DATE=$(git show -s --format=%ci "$SNAPSHOT_COMMIT" | cut -d' ' -f1,2)

echo "Snapshot: claude-snapshot-$SNAPSHOT_ID"
echo "Date: $SNAPSHOT_DATE"
echo "Commit: ${SNAPSHOT_COMMIT:0:7}"
echo

# Check for uncommitted changes
if ! git diff-index --quiet HEAD -- || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo "WARNING: You have uncommitted changes in your working directory."
    echo "These will be LOST if you proceed with the restore."
    echo
    
    if [ "$DRY_RUN" = false ]; then
        read -p "Create a safety snapshot before restoring? (Y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "Creating safety snapshot..."
            .claude/hooks/snapshot_repo_v2.sh
            echo
        fi
    fi
fi

if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN - Showing what would change:"
    echo
    
    # Create temporary index for current state
    TEMP_INDEX=$(mktemp)
    export GIT_INDEX_FILE="$TEMP_INDEX"
    git read-tree HEAD 2>/dev/null || true
    git add -A . 2>/dev/null || true
    CURRENT_TREE=$(git write-tree)
    unset GIT_INDEX_FILE
    rm -f "$TEMP_INDEX"
    
    # Show diff
    git diff-tree --no-commit-id --name-status -r "$CURRENT_TREE" "$SNAPSHOT_TREE" | \
    while read -r status file; do
        case "$status" in
            A) echo "+ $file (will be created)" ;;
            D) echo "- $file (will be deleted)" ;;
            M) echo "M $file (will be modified)" ;;
        esac
    done
    
    echo
    echo "Use without --dry-run to actually restore."
    exit 0
fi

# Confirm restore
echo "This will restore your working directory to the snapshot state."
echo "All current changes will be LOST."
echo
read -p "Proceed with restore? (y/N) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Restore cancelled."
    exit 0
fi

# Perform the restore
echo "Restoring to snapshot..."

# Method: Use git read-tree and checkout-index
# This preserves the git history while updating the working directory
git read-tree "$SNAPSHOT_TREE"
git checkout-index -a -f

# Remove files that don't exist in snapshot
git clean -fd

echo "✓ Restored to claude-snapshot-$SNAPSHOT_ID"
echo
echo "Your working directory now matches the snapshot."
echo "Use 'git status' to see the changes."
echo "Use 'git reset --hard' to also reset the git index."