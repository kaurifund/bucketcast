# Sync Shuttle - Feature Ideas

## High-Impact Features

### 1. Fan-out / Multi-server Push
```bash
# Push to multiple servers at once
sync-shuttle push -s prod-1,prod-2,prod-3 -S ./config.json

# Push to server group
sync-shuttle push --group production -S ./deploy/
```

### 2. Server Groups & Tags
```toml
# servers.toml
[servers.prod-1]
host = "10.0.1.1"
tags = ["production", "us-east"]
group = "web-servers"

[servers.prod-2]
host = "10.0.1.2"
tags = ["production", "us-west"]
group = "web-servers"
```
```bash
sync-shuttle push --tag production -S ./hotfix.sh
sync-shuttle files --group web-servers
```

### 3. Watch Mode (auto-sync on change)
```bash
sync-shuttle watch -s dev-server -S ./src/
# Uses inotify, syncs on file save
```

### 4. Sync Profiles / Presets
```bash
# Save a common operation
sync-shuttle profile save deploy-prod \
  --servers prod-1,prod-2 \
  --source ./dist/ \
  --exclude "*.map"

# Run it later
sync-shuttle deploy-prod
```

### 5. Ignore Patterns (.syncignore)
```
# .sync-shuttle/ignore
node_modules/
.git/
*.log
.env
__pycache__/
```

### 6. Quick Actions in TUI
- `y` - yank/copy file path
- `m` - move file between inbox/outbox
- `c` - copy to another server
- `Space` - multi-select files
- `Enter` on remote file - pull it immediately

### 7. Inbox Notifications
```bash
# Desktop notification when files arrive
sync-shuttle daemon --notify

# Webhook on receive
sync-shuttle daemon --webhook https://slack.com/...
```

### 8. Diff Before Sync
```bash
sync-shuttle diff -s prod-server
# Shows what would change

# In TUI: 'd' to diff selected file with remote
```

## Medium Priority

| Feature | Description |
|---------|-------------|
| **Projects** | Group servers + source paths as a named project |
| **History browser** | TUI view of past operations, with undo |
| **Delta sync** | Only transfer changed bytes (rdiff) |
| **Encryption** | GPG encrypt before transfer |
| **Scheduling** | `sync-shuttle schedule "0 2 * * *" pull -s backup` |
| **Conflict UI** | When file exists both places, prompt resolution |

## Quick Wins for TUI

1. **Status bar** showing: connected servers, pending files, last sync time
2. **Fuzzy search** (`/` then type) across all files
3. **Batch operations** - select multiple files, push/delete all
4. **File preview pane** - show text content, image thumbnails
5. **Keyboard-driven server switcher** - `1-9` to quick-switch servers

## Maintenance & Cleanup

### Cleanup Command
```bash
sync-shuttle cleanup              # Interactive cleanup wizard
sync-shuttle cleanup --logs       # Remove logs older than 30 days
sync-shuttle cleanup --archive    # Remove archives per retention policy
sync-shuttle cleanup --cache      # Clear all cached data
sync-shuttle cleanup --inbox      # List old inbox files for review
sync-shuttle cleanup --all        # Run all cleanup tasks
sync-shuttle cleanup --dry-run    # Show what would be removed
```

### Auto-cleanup Daemon
```bash
sync-shuttle daemon --cleanup-interval 24h
# Runs cleanup automatically every 24 hours
```

### Storage Stats
```bash
sync-shuttle stats
# Output:
#   Inbox:    45 files (123 MB)
#   Outbox:   12 files (45 MB)
#   Archive:  89 files (234 MB) - 30 day retention
#   Logs:     156 MB
#   Cache:    2.3 MB
#   Total:    458 MB
