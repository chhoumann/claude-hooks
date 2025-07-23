#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to read input properly whether piped or interactive
read_input() {
    if [ -t 0 ]; then
        read "$@"
    else
        read "$@" < /dev/tty
    fi
}

echo -e "${BOLD}Claude Snapshot Hooks Uninstaller${NC}"
echo "==================================="
echo

# Get repository root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Repository detected: $REPO_ROOT"
echo

# Check what exists
CLAUDE_DIR="$REPO_ROOT/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
has_hooks=false
has_snapshots=false
has_metadata=false
has_config=false

if [ -d "$HOOKS_DIR" ]; then
    has_hooks=true
fi

if git for-each-ref --format='%(refname)' refs/claude/snapshots/ 2>/dev/null | grep -q .; then
    has_snapshots=true
fi

if [ -d "$CLAUDE_DIR/snapshot_metadata" ] || [ -f "$CLAUDE_DIR/snapshot.log" ]; then
    has_metadata=true
fi

if [ -f "$CLAUDE_DIR/settings.json" ] || [ -f "$CLAUDE_DIR/settings.example.json" ] || [ -f "$CLAUDE_DIR/aliases.sh" ]; then
    has_config=true
fi

# Show what will be removed
echo -e "${BOLD}This uninstaller will remove:${NC}"
if [ "$has_hooks" = true ]; then
    echo "  • Hook scripts in .claude/hooks/"
fi
if [ "$has_config" = true ]; then
    echo "  • Local configuration files (.claude/settings.json, aliases.sh)"
fi
if [ "$has_metadata" = true ]; then
    echo "  • Snapshot metadata and logs"
fi
if [ "$has_snapshots" = true ]; then
    SNAPSHOT_COUNT=$(git for-each-ref --format='%(refname)' refs/claude/snapshots/ | wc -l)
    echo "  • Git snapshot refs ($SNAPSHOT_COUNT snapshots)"
fi

echo
echo -e "${YELLOW}Note: This uninstaller only removes files from this repository.${NC}"
echo

# Ask for overall permission
read_input -p "Do you want to proceed with uninstallation? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo

# 1. Remove hooks directory
if [ "$has_hooks" = true ]; then
    echo -n "Remove hooks directory (.claude/hooks/)? (y/N) "
    read_input -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$HOOKS_DIR"
        echo -e "${GREEN}✓${NC} Removed hooks directory"
    else
        echo -e "${YELLOW}○${NC} Kept hooks directory"
    fi
else
    echo -e "${YELLOW}○${NC} No hooks directory found"
fi

# 2. Remove configuration files
if [ "$has_config" = true ]; then
    echo
    echo -n "Remove configuration files? (y/N) "
    read_input -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.example.json" "$CLAUDE_DIR/aliases.sh"
        echo -e "${GREEN}✓${NC} Removed configuration files"
    else
        echo -e "${YELLOW}○${NC} Kept configuration files"
    fi
fi

# 3. Remove metadata
if [ "$has_metadata" = true ]; then
    echo
    echo -n "Remove snapshot metadata and logs? (y/N) "
    read_input -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CLAUDE_DIR/snapshot_metadata"
        rm -f "$CLAUDE_DIR/snapshot.log"
        rm -f "$CLAUDE_DIR/last_snapshot"*
        echo -e "${GREEN}✓${NC} Removed metadata and logs"
    else
        echo -e "${YELLOW}○${NC} Kept metadata and logs"
    fi
fi

# 4. Remove snapshot refs
if [ "$has_snapshots" = true ]; then
    echo
    echo -e "${YELLOW}Found $SNAPSHOT_COUNT snapshot(s) in git refs${NC}"
    echo -n "Remove all git snapshot refs? (y/N) "
    read_input -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git for-each-ref --format='%(refname)' refs/claude/snapshots/ | while read ref; do
            git update-ref -d "$ref"
        done
        echo -e "${GREEN}✓${NC} Removed all snapshot refs"
    else
        echo -e "${YELLOW}○${NC} Kept snapshot refs"
    fi
fi

# 5. Clean up empty .claude directory
if [ -d "$CLAUDE_DIR" ]; then
    if [ -z "$(ls -A "$CLAUDE_DIR")" ]; then
        echo
        echo -n "Remove empty .claude directory? (y/N) "
        read_input -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rmdir "$CLAUDE_DIR"
            echo -e "${GREEN}✓${NC} Removed empty .claude directory"
        fi
    fi
fi

echo
echo -e "${GREEN}${BOLD}Uninstall Complete!${NC}"
echo
echo "Notes:"
echo "- If you added aliases to your shell config, remove them manually"
echo "- To reinstall, run: ./install_claude_hooks.sh"