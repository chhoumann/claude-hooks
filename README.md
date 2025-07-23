# Claude Snapshot Hooks

A non-invasive hook system for Claude Code that captures repository snapshots and generates prompts from manual edits - all without interfering with your git workflow.

## Features

- **Automatic Snapshots**: Captures repository state when Claude Code finishes working
- **Zero Git Pollution**: No commits on your branch - uses git internals
- **Complete Capture**: Captures all tracked and untracked files (respects .gitignore)
- **Edit Tracking**: Shows exactly what you changed manually after Claude's session
- **Prompt Generation**: Creates formatted prompts showing your manual edits
- **Snapshot Management**: List, restore, and cleanup snapshots
- **Clipboard Support**: Copy prompts directly to clipboard
- **Local Installation**: Everything stays within your repository

## Quick Start

```bash
# Navigate to your project
cd /path/to/your-project

# Download and run the installer
curl -fsSL https://raw.githubusercontent.com/chhoumann/claude-hooks/master/install_claude_hooks.sh | bash

# Or download first, then run
wget https://raw.githubusercontent.com/chhoumann/claude-hooks/master/install_claude_hooks.sh
chmod +x install_claude_hooks.sh
./install_claude_hooks.sh
```

The installer will:
- Ask for your permission before making changes
- Create a `.claude/` directory in your repository
- Download hook scripts from GitHub
- Automatically configure the hooks in `.claude/settings.json`

That's it! The hooks are now active. Claude Code automatically reads the local `.claude/settings.json` file in your project.

### Set Up Aliases (Optional)

Source the generated aliases file:

```bash
source /path/to/your-project/.claude/aliases.sh
```

Or add it to your shell config (`~/.bashrc` or `~/.zshrc`).

## How It Works

1. When Claude Code finishes, a git tree object is created with all tracked and untracked files (respecting .gitignore)
2. The tree is stored as a hidden ref (`refs/claude/snapshots/<timestamp>`)
3. Your working directory remains completely unchanged
4. When generating prompts, it diffs the tree against current state

## Usage

### Automatic Snapshots
Snapshots happen automatically - no action needed!

### Generate Prompt from Edits
After making manual changes:

```bash
# Show diff in terminal
claude-diff

# Copy to clipboard
claude-prompt --clipboard

# Save to file with options
claude-prompt --file edits.md --max-lines 1000
```

### Manage Snapshots

```bash
# List all snapshots
claude-list

# Restore to a previous snapshot
claude-restore <timestamp>
claude-restore latest

# Clean up old snapshots
claude-cleanup
```

### Example Output
````markdown
# Manual Edits Since Last Claude Session

**Snapshot**: claude-snapshot-1737474123
**Snapshot Date**: 2024-01-21 15:30:45
**Changes**: 2 added, 1 modified, 0 deleted (Total: 3)

## Summary of Changes

### New Files (2)
```
+ src/new-feature.js
+ docs/feature.md
```

### Modified Files (1)
```
M src/app.js
```

## Detailed Changes
```diff
diff --git a/src/app.js b/src/app.js
index abc123..def456 100644
--- a/src/app.js
+++ b/src/app.js
@@ -10,7 +10,7 @@ function main() {
-    console.log("Hello");
+    console.log("Hello, World!");
```
````

## Configuration

### Automatic Setup

The installer automatically configures the hooks by creating/updating `.claude/settings.json` in your project directory. No manual configuration is needed!

The installer will:
- Create the settings file if it doesn't exist
- Update existing settings if they already have hooks configured (with your permission)
- Preserve any other settings you may have

### Manual Configuration (if needed)

If you need to manually configure the hooks, add this to `.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/your-project/.claude/hooks/snapshot_repo.sh"
          }
        ]
      }
    ]
  }
}
```

**Key Points**:
- Hooks are configured per-project in `.claude/settings.json`
- No global configuration needed - Claude Code automatically finds project settings
- The installer handles all configuration automatically
- Each project can have its own independent hook configuration

### Environment Variables

- `CLAUDE_SNAPSHOT_KEEP=50` - Number of snapshots to keep (default: 50)
- `CLAUDE_SNAPSHOT_INCLUDE_IGNORED=true` - Include .gitignored files in snapshots

## Advanced Features

### Large Diff Handling
Truncate large diffs:
```bash
claude-prompt --max-lines 1000
```

### Include Ignored Files
To see changes to .gitignored files:
```bash
claude-prompt --include-ignored
```

## Shell Aliases

The installer creates a local aliases file (`.claude/aliases.sh`) with these commands:

```bash
alias claude-list      # List all snapshots
alias claude-restore   # Restore a snapshot
alias claude-cleanup   # Clean up old snapshots
alias claude-diff      # Show diff in terminal
alias claude-prompt    # Generate a prompt from edits
```

## Troubleshooting

**"No previous snapshot found"**
- Claude Code needs to run at least once to create a baseline

**"Snapshot reference no longer exists"**
- Run `claude-cleanup` to clean up broken references

**No changes detected**
- There are no differences between the snapshot and current state

## Uninstalling

To remove Claude Snapshot Hooks from a project:

```bash
cd /path/to/your-project

# Download and run the uninstaller
curl -fsSL https://raw.githubusercontent.com/chhoumann/claude-hooks/master/uninstall_claude_hooks.sh | bash

# Or if you have the scripts locally
./uninstall_claude_hooks.sh
```

The uninstaller will:
- Ask for permission before removing anything
- Only remove files from the local repository
- Clean up all hooks and settings

## Security Notes

- Hooks run with your user permissions
- Only affects the current repository
- Installation is completely local - no global system changes
- No network access required
- All data stays local
- Snapshots may include sensitive data - handle accordingly
- The installer asks for permission before making any changes

## License

MIT