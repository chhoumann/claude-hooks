# Claude Code Git Snapshot Hooks

A non-invasive hook system for Claude Code that captures repository snapshots and generates prompts from manual edits - all without interfering with your git workflow.

## Features

- **Automatic Snapshots**: Captures repository state when Claude Code finishes working
- **Zero Git Pollution**: Uses git stash internally - no commits on your branch
- **Edit Tracking**: Shows exactly what you changed manually after Claude's session
- **Prompt Generation**: Creates formatted prompts showing your manual edits
- **Clipboard Support**: Copy prompts directly to clipboard

## Quick Start

1. **Clone or copy the hooks to your project:**
   ```bash
   cp -r .claude your-project/
   cp setup_claude_hooks.sh your-project/
   ```

2. **Run the setup script:**
   ```bash
   cd your-project
   ./setup_claude_hooks.sh
   ```

3. **That's it!** The hooks are now active.

## How It Works

1. When Claude Code finishes (Stop event), a snapshot is created using `git stash`
2. The stash is immediately popped, leaving your working directory unchanged
3. The snapshot reference is stored in `.claude/last_snapshot`
4. When you run the prompt generator, it diffs the snapshot against your current state

## Usage

### Automatic Snapshots
Snapshots happen automatically - no action needed! Check `.claude/snapshot.log` for history.

### Generate Prompt from Edits
After making manual changes:

```bash
# Show diff in terminal
.claude/hooks/prompt_from_edits.sh

# Copy to clipboard
.claude/hooks/generate_edits_prompt.sh --clipboard

# Save to file
.claude/hooks/generate_edits_prompt.sh --file edits.md
```

### Example Output
```markdown
# Manual Edits Since Last Claude Session

**Snapshot**: claude-snapshot-1737474123
**Changes**: 1 added, 2 modified, 0 deleted

## Files Changed:
```
M       src/app.js
M       src/utils.js
A       src/new-feature.js
```

## Detailed Changes:
```diff
diff --git a/src/app.js b/src/app.js
index abc123..def456 100644
--- a/src/app.js
+++ b/src/app.js
@@ -10,7 +10,7 @@ function main() {
-    console.log("Hello");
+    console.log("Hello, World!");
```
```

## Configuration

The hooks are configured in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [{
      "matcher": ".*",
      "hooks": [{
        "type": "command",
        "command": "cd \"$repo_path\" && .claude/hooks/snapshot_repo.sh"
      }]
    }]
  }
}
```

## Files

- `.claude/hooks/snapshot_repo.sh` - Creates git snapshots
- `.claude/hooks/prompt_from_edits.sh` - Generates diff prompts
- `.claude/hooks/generate_edits_prompt.sh` - Enhanced prompt generator
- `.claude/hooks/snapshot_with_logging.sh` - Version with detailed logging
- `.claude/example-settings.json` - Example hooks configuration
- `setup_claude_hooks.sh` - Installation script

## Advanced Features

### Logging Version
Use `snapshot_with_logging.sh` for detailed logging:
- Tracks file counts (modified/untracked/staged)
- Logs to `.claude/snapshot.log`
- Creates statistics in `.claude/snapshot_stats.json`

### Multiple Sessions
Each snapshot has a unique timestamp, supporting parallel Claude sessions.

### Cleanup
Old snapshots are automatically cleaned by git's stash garbage collection.

## Troubleshooting

**"No previous snapshot found"**
- Claude Code needs to run at least once to create a baseline

**"Snapshot reference no longer exists"**
- The git stash may have been cleared. Let Claude run again to create a new snapshot.

**No changes detected**
- There are no differences between the snapshot and current state

## Security Notes

- Hooks run with your user permissions
- Only affects the current repository
- No network access required
- All data stays local

## License

MIT