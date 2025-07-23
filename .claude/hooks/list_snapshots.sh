#!/bin/bash

# List all Claude Code snapshots with details

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SNAPSHOT_REF_PREFIX="refs/claude/snapshots"
METADATA_DIR=".claude/snapshot_metadata"

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}Error: Not in a git repository${NC}" >&2
    exit 1
fi

# Check if we have any snapshots
SNAPSHOT_COUNT=$(git for-each-ref --format='%(refname)' "$SNAPSHOT_REF_PREFIX" 2>/dev/null | wc -l)

if [ "$SNAPSHOT_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}No snapshots found.${NC}"
    echo "Snapshots are created automatically when Claude Code finishes working."
    exit 0
fi

echo -e "${BOLD}Claude Code Snapshots${NC} (Total: ${GREEN}$SNAPSHOT_COUNT${NC})"
echo -e "${BLUE}=================================================${NC}"
echo

# Get current snapshot if exists
CURRENT_SNAPSHOT=""
if [ -f .claude/last_snapshot_timestamp ]; then
    CURRENT_SNAPSHOT=$(cat .claude/last_snapshot_timestamp)
fi

# List snapshots in reverse chronological order
git for-each-ref --sort=-committerdate --format='%(refname:short) %(committerdate:iso8601) %(subject)' "$SNAPSHOT_REF_PREFIX" | \
while IFS=' ' read -r ref date time subject; do
    # Extract timestamp from ref
    TIMESTAMP=$(basename "$ref")
    
    # Mark current snapshot
    MARKER=""
    COLOR="$NC"
    if [ "$TIMESTAMP" = "$CURRENT_SNAPSHOT" ]; then
        MARKER=" ${GREEN}[CURRENT]${NC}"
        COLOR="$GREEN"
    fi
    
    # Try to load metadata
    STATS=""
    if [ -f "$METADATA_DIR/$TIMESTAMP.json" ]; then
        # Extract stats from JSON
        MODIFIED=$(grep '"modified"' "$METADATA_DIR/$TIMESTAMP.json" | grep -o '[0-9]*' | head -1)
        UNTRACKED=$(grep '"untracked"' "$METADATA_DIR/$TIMESTAMP.json" | grep -o '[0-9]*' | head -1)
        DELETED=$(grep '"deleted"' "$METADATA_DIR/$TIMESTAMP.json" | grep -o '[0-9]*' | head -1)
        STATS=" (M:$MODIFIED U:$UNTRACKED D:$DELETED)"
    fi
    
    # Get commit hash
    COMMIT=$(git rev-parse "$ref")
    
    # Format output
    printf "${COLOR}%-25s${NC} ${CYAN}%s %s${NC} ${YELLOW}%s${NC}%s%s\n" \
        "claude-snapshot-$TIMESTAMP" \
        "$date" \
        "$time" \
        "${COMMIT:0:7}" \
        "$STATS" \
        "$MARKER"
done

echo
echo -e "${BOLD}Commands:${NC}"
echo -e "  ${BLUE}View changes:${NC}     claude-diff    ${CYAN}(or .claude/hooks/prompt_from_edits.sh)${NC}"
echo -e "  ${BLUE}Restore snapshot:${NC} claude-restore ${CYAN}(or .claude/hooks/restore_snapshot.sh <timestamp>)${NC}"
echo -e "  ${BLUE}Clean old:${NC}        claude-cleanup ${CYAN}(or .claude/hooks/cleanup_snapshots.sh)${NC}"