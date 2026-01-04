# File Discovery Feature Design

## Problem

Users need to easily discover what files are available across their sync-shuttle network:
- What's in my local inbox/outbox?
- What's available to pull from remote servers?
- Where is a specific file?
- What did I receive recently?

Currently there's no unified way to see all available files or search across locations.

## User Stories

1. **Quick overview**: "Show me everything available to me right now"
2. **Server browse**: "What files are on server X that I can pull?"
3. **Search**: "Find any file matching 'config*' across all my servers"
4. **Recent activity**: "What files arrived in the last 24 hours?"
5. **By type**: "Show me all PDFs available"

## Proposed Interface

### Option A: Single unified command

```bash
# Overview - shows counts and recent files
sync-shuttle files

# Search across all locations
sync-shuttle files --search "*.pdf"
sync-shuttle files -q "config"

# Filter by location
sync-shuttle files --inbox          # Files received
sync-shuttle files --outbox         # Files you're sharing
sync-shuttle files --remote         # Files on remote servers (requires SSH)

# Filter by server
sync-shuttle files -s dev-server

# Combine filters
sync-shuttle files -s dev-server --outbox --search "*.log"

# Output formats
sync-shuttle files --json           # For scripting
sync-shuttle files --tree           # Tree view

# Shorthand tree command
sync-shuttle tree                   # Tree view of all locations
sync-shuttle tree -s dev-server     # Tree view of one server
sync-shuttle tree --remote          # Include remote files in tree
```

### Option B: Interactive TUI browser

```bash
sync-shuttle browse
```

Opens a full-screen TUI with:
- Left panel: Location tree (Local Inbox, Local Outbox, Server1, Server2...)
- Right panel: File list with details
- Bottom: Search bar
- Keyboard navigation (vim-style?)

### Option C: Hybrid approach (Recommended)

Both CLI and TUI:
- `sync-shuttle files [options]` - Quick CLI queries
- `sync-shuttle browse` - Interactive exploration

## CLI Output Design

```
$ sync-shuttle files

📥 INBOX (3 files, 2.4 MB)
────────────────────────────────────────────────────────────
  From: dev-server (2 files)
    config.json          1.2 KB    2 hours ago
    data.csv            45.0 KB    2 hours ago

  From: prod-backup (1 file)
    database.sql         2.3 MB    yesterday

📤 OUTBOX (1 file, 512 B)
────────────────────────────────────────────────────────────
    notes.txt           512 B     just now

📡 REMOTE SERVERS
────────────────────────────────────────────────────────────
  dev-server: 5 files available (use --remote to fetch list)
  prod-backup: 0 files available

$ sync-shuttle files --remote -s dev-server

📡 dev-server - Available to Pull
────────────────────────────────────────────────────────────
    logs/app.log        12.3 MB   10 min ago
    logs/error.log       1.1 MB   10 min ago
    backup.tar.gz      156.0 MB   1 day ago
    config.json          2.1 KB   3 days ago
    readme.md            4.5 KB   1 week ago

Total: 5 files (169.6 MB)
Tip: Run 'sync-shuttle pull -s dev-server' to download

$ sync-shuttle files -q "*.log"

Search results for "*.log":
────────────────────────────────────────────────────────────
  📥 inbox/dev-server/debug.log      45 KB
  📡 dev-server/logs/app.log        12.3 MB
  📡 dev-server/logs/error.log       1.1 MB

Found 3 matches across 2 locations

$ sync-shuttle tree

~/.sync-shuttle/
├── 📥 inbox/
│   ├── dev-server/
│   │   ├── config.json (1.2 KB)
│   │   └── data.csv (45 KB)
│   └── prod-backup/
│       └── database.sql (2.3 MB)
├── 📤 outbox/
│   └── notes.txt (512 B)
└── 📡 remote/
    ├── dev-server/ (use --remote to fetch)
    └── prod-backup/ (use --remote to fetch)

$ sync-shuttle tree --remote

~/.sync-shuttle/
├── 📥 inbox/
│   ├── dev-server/
│   │   ├── config.json (1.2 KB)
│   │   └── data.csv (45 KB)
│   └── prod-backup/
│       └── database.sql (2.3 MB)
├── 📤 outbox/
│   └── notes.txt (512 B)
└── 📡 remote/
    ├── dev-server/
    │   ├── logs/
    │   │   ├── app.log (12.3 MB)
    │   │   └── error.log (1.1 MB)
    │   ├── backup.tar.gz (156 MB)
    │   └── config.json (2.1 KB)
    └── prod-backup/
        └── (empty)
```

## TUI Browser Design

```
┌─ Sync Shuttle Browser ─────────────────────────────────────────────────┐
│ ┌─ Locations ──────────┐ ┌─ Files ─────────────────────────────────────┐│
│ │ 📥 Inbox          (3)│ │ Name              Size      Modified       ││
│ │   └ dev-server    (2)│ │ ─────────────────────────────────────────  ││
│ │   └ prod-backup   (1)│ │ > config.json     1.2 KB    2 hours ago    ││
│ │ 📤 Outbox         (1)│ │   data.csv       45.0 KB    2 hours ago    ││
│ │ 📡 Remote            │ │                                            ││
│ │   └ dev-server    (5)│ │                                            ││
│ │   └ prod-backup   (0)│ │                                            ││
│ └──────────────────────┘ └────────────────────────────────────────────┘│
│ ┌─ Preview ────────────────────────────────────────────────────────────┐│
│ │ config.json (1.2 KB) - From: dev-server - Received: 2 hours ago     ││
│ │ Path: ~/.sync-shuttle/local/inbox/dev-server/config.json            ││
│ └──────────────────────────────────────────────────────────────────────┘│
│ [/] Search  [p] Pull  [d] Delete  [o] Open  [r] Refresh  [q] Quit      │
└────────────────────────────────────────────────────────────────────────┘
```

## Technical Considerations

### Caching Remote Queries
- SSH queries are slow; cache results with TTL
- Store in `~/.sync-shuttle/cache/remote-files.json`
- Auto-refresh on pull/push operations
- Manual refresh with `--refresh` flag

### Performance
- Local queries should be instant
- Remote queries: parallel SSH to all servers
- Show spinners for long operations
- Timeout after 10s per server

### Search Implementation
- Glob patterns: `*.pdf`, `config*`
- Regex support: `--regex`
- Case insensitive by default
- Search filename only (not content)

## Implementation Plan

1. [ ] Add `files` command with basic local listing
2. [ ] Add `tree` command for hierarchical view
3. [ ] Add search/filter functionality (-q, --search)
4. [ ] Add remote server querying (--remote, parallel SSH)
5. [ ] Add caching layer for remote queries
6. [ ] Add JSON output format (--json)
7. [ ] Add TUI browser `browse` command (separate PR)

## Open Questions

1. Should remote queries be opt-in (slow) or default?
2. Cache TTL - how long before stale?
3. Should we support content search (grep-like)?
4. File actions from the browser (delete, move, open)?
