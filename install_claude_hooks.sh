#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

echo -e "${BOLD}Claude Snapshot Hooks Installer${NC}"
echo "================================="
echo

# 1. Detect repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Repository detected: $REPO_ROOT"
echo

# 2. Explain what will be installed
echo -e "${BOLD}This installer will:${NC}"
echo "  • Create .claude/hooks/ directory in this repository"
echo "  • Copy hook scripts to .claude/hooks/"
echo "  • Create a local .claude/settings.json configuration"
echo "  • Provide shell aliases for convenient usage"
echo
echo -e "${YELLOW}Note: This installer only modifies files within this repository.${NC}"
echo

# 3. Ask for permission
read_input -p "Do you want to proceed with the installation? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

echo

# 4. Create .claude/hooks/ if absent
HOOKS_DIR="$REPO_ROOT/.claude/hooks"
CLAUDE_DIR="$REPO_ROOT/.claude"

if [ ! -d "$CLAUDE_DIR" ]; then
    echo -n "Create .claude directory? (y/N) "
    read_input -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mkdir -p "$CLAUDE_DIR"
        echo -e "${GREEN}✓${NC} Created .claude directory"
    else
        echo -e "${RED}Cannot proceed without .claude directory${NC}"
        exit 1
    fi
fi

if [ ! -d "$HOOKS_DIR" ]; then
    mkdir -p "$HOOKS_DIR"
    echo -e "${GREEN}✓${NC} Created hooks directory: $HOOKS_DIR"
else
    echo -e "${GREEN}✓${NC} Hooks directory exists: $HOOKS_DIR"
fi

# 5. Download hook scripts from GitHub
GITHUB_BASE_URL="https://raw.githubusercontent.com/chhoumann/claude-hooks/master/.claude/hooks"
HOOK_SCRIPTS=(
    "snapshot_repo.sh"
    "generate_edits_prompt.sh"
    "prompt_from_edits.sh"
    "list_snapshots.sh"
    "restore_snapshot.sh"
    "cleanup_snapshots.sh"
)

echo
echo -e "${BOLD}Downloading hook scripts...${NC}"
scripts_installed=0

# Check for download command
if command -v curl &> /dev/null; then
    DOWNLOAD_CMD="curl -fsSL"
elif command -v wget &> /dev/null; then
    DOWNLOAD_CMD="wget -qO-"
else
    echo -e "${RED}Error: Neither curl nor wget found. Please install one of them.${NC}"
    exit 1
fi

for script in "${HOOK_SCRIPTS[@]}"; do
    # Check if file already exists
    if [ -f "$HOOKS_DIR/$script" ]; then
        echo -e "  ${YELLOW}!${NC} $script already exists"
        echo -n "    Overwrite? (y/N) "
        read_input -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "    ${YELLOW}○${NC} Skipped $script"
            continue
        fi
    fi
    
    # Download the script
    echo -ne "  ${BLUE}↓${NC} Downloading $script..."
    if $DOWNLOAD_CMD "$GITHUB_BASE_URL/$script" > "$HOOKS_DIR/$script.tmp" 2>/dev/null; then
        mv "$HOOKS_DIR/$script.tmp" "$HOOKS_DIR/$script"
        chmod +x "$HOOKS_DIR/$script"
        echo -e "\r  ${GREEN}✓${NC} Downloaded $script    "
        scripts_installed=$((scripts_installed + 1))
    else
        rm -f "$HOOKS_DIR/$script.tmp"
        echo -e "\r  ${RED}✗${NC} Failed to download $script"
        echo -e "    ${YELLOW}URL: $GITHUB_BASE_URL/$script${NC}"
    fi
done

if [ $scripts_installed -eq 0 ]; then
    echo -e "${RED}No scripts were installed. Check your internet connection.${NC}"
    exit 1
fi

# 6. Configure local settings.json
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
HOOK_COMMAND="$HOOKS_DIR/snapshot_repo.sh"

# Function to update settings.json
update_settings() {
    local settings_file="$1"
    local hook_cmd="$2"
    
    # Check if we have jq or python for JSON manipulation
    if command -v jq &> /dev/null; then
        # Use jq to update settings
        if [ -f "$settings_file" ] && [ -s "$settings_file" ]; then
            # Check if UserPromptSubmit hook already exists
            if jq -e '.hooks.UserPromptSubmit' "$settings_file" > /dev/null 2>&1; then
                echo -e "${YELLOW}UserPromptSubmit hook already configured${NC}"
                echo -n "Update to use our snapshot hook? (y/N) "
                read_input -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    # Update existing hook
                    jq --arg cmd "$hook_cmd" '.hooks.UserPromptSubmit = [{
                        "matcher": ".*",
                        "hooks": [{
                            "type": "command",
                            "command": $cmd
                        }]
                    }]' "$settings_file" > "$settings_file.tmp" && mv "$settings_file.tmp" "$settings_file"
                    echo -e "${GREEN}✓${NC} Updated UserPromptSubmit hook"
                    return 0
                else
                    echo -e "${YELLOW}○${NC} Kept existing hook configuration"
                    return 1
                fi
            else
                # Add new hook
                jq --arg cmd "$hook_cmd" '. + {
                    "hooks": (.hooks // {} | . + {
                        "UserPromptSubmit": [{
                            "matcher": ".*",
                            "hooks": [{
                                "type": "command",
                                "command": $cmd
                            }]
                        }]
                    })
                }' "$settings_file" > "$settings_file.tmp" && mv "$settings_file.tmp" "$settings_file"
                echo -e "${GREEN}✓${NC} Added UserPromptSubmit hook to existing settings"
                return 0
            fi
        else
            # Create new settings file
            cat > "$settings_file" <<EOF
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "$hook_cmd"
          }
        ]
      }
    ]
  }
}
EOF
            echo -e "${GREEN}✓${NC} Created settings.json with hook configuration"
            return 0
        fi
    else
        # Fallback to Python
        python3 -c "
import json
import os
import sys

settings_file = '$settings_file'
hook_cmd = '$hook_cmd'

settings = {}
if os.path.exists(settings_file) and os.path.getsize(settings_file) > 0:
    try:
        with open(settings_file, 'r') as f:
            settings = json.load(f)
    except:
        print('${YELLOW}Warning: Existing settings.json is invalid${NC}')
        settings = {}

# Check if UserPromptSubmit already exists
if 'hooks' in settings and 'UserPromptSubmit' in settings.get('hooks', {}):
    print('${YELLOW}UserPromptSubmit hook already configured${NC}')
    response = input('Update to use our snapshot hook? (y/N) ')
    if response.lower() != 'y':
        print('${YELLOW}○${NC} Kept existing hook configuration')
        sys.exit(1)

# Update settings
if 'hooks' not in settings:
    settings['hooks'] = {}

settings['hooks']['UserPromptSubmit'] = [{
    'matcher': '.*',
    'hooks': [{
        'type': 'command',
        'command': hook_cmd
    }]
}]

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)

print('${GREEN}✓${NC} Configured UserPromptSubmit hook')
"
        return $?
    fi
}

echo
echo -e "${BOLD}Configuring hooks...${NC}"
if update_settings "$SETTINGS_FILE" "$HOOK_COMMAND"; then
    HOOK_CONFIGURED=true
else
    HOOK_CONFIGURED=false
fi

# 7. Create convenience script for aliases
ALIASES_FILE="$CLAUDE_DIR/aliases.sh"
cat > "$ALIASES_FILE" <<EOF
#!/bin/bash
# Claude Snapshot Hooks aliases
# Source this file in your shell: source $ALIASES_FILE

alias claude-list='$HOOKS_DIR/list_snapshots.sh'
alias claude-restore='$HOOKS_DIR/restore_snapshot.sh'
alias claude-cleanup='$HOOKS_DIR/cleanup_snapshots.sh'
alias claude-diff='$HOOKS_DIR/generate_edits_prompt.sh'
alias claude-prompt='$HOOKS_DIR/prompt_from_edits.sh'
EOF
chmod +x "$ALIASES_FILE"
echo -e "${GREEN}✓${NC} Created aliases script: .claude/aliases.sh"

# 8. Print summary and instructions
echo
echo -e "${GREEN}${BOLD}Installation Complete!${NC}"
echo -e "====================="
echo

if [ "$HOOK_CONFIGURED" = true ]; then
    echo -e "${GREEN}✓${NC} Hooks are now active for this repository!"
    echo -e "${GREEN}✓${NC} Claude Code will automatically create snapshots before each prompt"
else
    echo -e "${YELLOW}!${NC} Hook configuration was skipped"
    echo -e "  To manually configure, add the hook to .claude/settings.json"
fi

echo
echo -e "${BOLD}Optional: Set up command aliases${NC}"
echo
echo "For convenient command aliases, add to your ~/.bashrc or ~/.zshrc:"
echo -e "${BLUE}  source $ALIASES_FILE${NC}"
echo
echo "Or run this command now for the current session:"
echo -e "${BLUE}  source $ALIASES_FILE${NC}"
echo
echo -e "${BOLD}Available commands (after sourcing aliases):${NC}"
echo -e "  ${GREEN}claude-list${NC}     - List all snapshots"
echo -e "  ${GREEN}claude-restore${NC}  - Restore a snapshot"
echo -e "  ${GREEN}claude-cleanup${NC}  - Clean up old snapshots"
echo -e "  ${GREEN}claude-diff${NC}     - Generate a diff prompt from changes"
echo -e "  ${GREEN}claude-prompt${NC}   - Create a prompt from edited files"
echo
if [ "$HOOK_CONFIGURED" = true ]; then
    echo -e "${GREEN}That's it! The hooks are ready to use.${NC}"
else
    echo -e "${YELLOW}Note: Remember to configure the hook in .claude/settings.json to activate snapshots.${NC}"
fi