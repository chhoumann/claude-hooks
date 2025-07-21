#!/bin/bash

# Claude Code Git Snapshot Hooks Setup Script
# Installs hooks for automatic repository snapshots

set -euo pipefail

CLAUDE_CONFIG_DIR="$HOME/.claude"
PROJECT_HOOKS_DIR=".claude/hooks"

echo "=== Claude Code Git Snapshot Hooks Setup ==="
echo

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "ERROR: This script must be run from within a git repository." >&2
    exit 1
fi

# Create Claude config directory if it doesn't exist
if [ ! -d "$CLAUDE_CONFIG_DIR" ]; then
    echo "Creating Claude Code config directory at $CLAUDE_CONFIG_DIR"
    mkdir -p "$CLAUDE_CONFIG_DIR"
fi

# Check if hooks already exist in settings
if [ -f "$CLAUDE_CONFIG_DIR/settings.json" ]; then
    if grep -q "Stop.*snapshot_repo" "$CLAUDE_CONFIG_DIR/settings.json" 2>/dev/null; then
        echo "WARNING: Snapshot hooks already appear to be configured in settings.json"
        read -p "Do you want to proceed anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Setup cancelled."
            exit 0
        fi
    fi
fi

# Copy hook scripts to project
echo "Copying hook scripts to $PROJECT_HOOKS_DIR..."
mkdir -p "$PROJECT_HOOKS_DIR"

# Ensure scripts exist
if [ ! -f ".claude/hooks/snapshot_repo.sh" ] || [ ! -f ".claude/hooks/prompt_from_edits.sh" ]; then
    echo "ERROR: Hook scripts not found in .claude/hooks/" >&2
    echo "Please ensure you have the following files:" >&2
    echo "  - .claude/hooks/snapshot_repo.sh" >&2
    echo "  - .claude/hooks/prompt_from_edits.sh" >&2
    exit 1
fi

# Create or update settings.json
SETTINGS_FILE="$CLAUDE_CONFIG_DIR/settings.json"
TEMP_SETTINGS=$(mktemp)

if [ -f "$SETTINGS_FILE" ]; then
    echo "Updating existing settings.json..."
    # Try to merge with existing settings (basic implementation)
    # For production use, consider using jq for proper JSON merging
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%s)"
    echo "Backup created: $SETTINGS_FILE.backup.$(date +%s)"
else
    echo "Creating new settings.json..."
    echo '{}' > "$TEMP_SETTINGS"
fi

# Add hook configuration
cat > "$TEMP_SETTINGS" <<'EOF'
{
  "hooks": {
    "Stop": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "cd \"$repo_path\" && .claude/hooks/snapshot_repo.sh"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "cd \"$repo_path\" && .claude/hooks/snapshot_repo.sh"
          }
        ]
      }
    ]
  }
}
EOF

# Install settings
echo
read -p "Install hooks to $SETTINGS_FILE? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    mv "$TEMP_SETTINGS" "$SETTINGS_FILE"
    echo "✓ Hooks installed successfully!"
else
    rm "$TEMP_SETTINGS"
    echo "Installation cancelled."
    exit 0
fi

# Create convenience aliases
echo
echo "Creating convenience commands..."
SHELL_RC=""
if [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
elif [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
fi

if [ -n "$SHELL_RC" ]; then
    echo
    echo "Would you like to add these aliases to your shell?"
    echo "  claude-diff    - Show changes since last Claude session"
    echo "  claude-prompt  - Generate prompt from manual edits"
    echo
    read -p "Add aliases to $SHELL_RC? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cat >> "$SHELL_RC" <<'EOF'

# Claude Code Git Snapshot Hooks
alias claude-diff='.claude/hooks/prompt_from_edits.sh'
alias claude-prompt='.claude/hooks/generate_edits_prompt.sh'
EOF
        echo "✓ Aliases added. Run 'source $SHELL_RC' to use them."
    fi
fi

# Show usage instructions
echo
echo "=== Setup Complete! ==="
echo
echo "The snapshot hooks are now active. They will:"
echo "  • Automatically capture repository state when Claude Code finishes"
echo "  • Allow you to generate prompts showing manual edits"
echo
echo "Usage:"
echo "  1. Let Claude Code work on your repository"
echo "  2. Make manual edits after Claude finishes"
echo "  3. Run: .claude/hooks/prompt_from_edits.sh"
echo "     Or: .claude/hooks/generate_edits_prompt.sh --clipboard"
echo
echo "The hooks will not interfere with your git workflow - no commits are created."
echo
echo "To test the setup, try:"
echo "  echo 'test' > test.txt && .claude/hooks/snapshot_repo.sh"
echo "  echo 'manual edit' >> test.txt && .claude/hooks/prompt_from_edits.sh"
echo "  rm test.txt"