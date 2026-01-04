# Sync Shuttle Architecture

## How It Works

### Directory Structure

```
~/.sync-shuttle/
├── config/
│   ├── sync-shuttle.conf    # Main settings
│   └── servers.toml         # Server definitions
├── local/
│   ├── inbox/               # Files RECEIVED from remotes
│   │   ├── server-a/        # From server-a
│   │   └── server-b/        # From server-b
│   └── outbox/              # Files TO SEND (stage here)
├── remote/
│   └── <server-id>/
│       └── files/           # Local mirror before push
├── cache/
│   └── remote-*.cache       # Cached remote file listings (5min TTL)
├── archive/
│   └── 20240115_143022/     # Timestamped backups (before overwrites)
├── logs/
│   ├── sync.log             # Human-readable log
│   └── sync.jsonl           # Machine-readable JSON log
└── tmp/                     # Temporary staging
```

### Push Flow

```
                            YOUR MACHINE                          REMOTE SERVER
┌─────────────────────────────────────────────────────────────┐   ┌──────────────────────┐
│                                                             │   │                      │
│  ~/my-file.txt                                              │   │  ~/.sync-shuttle/    │
│       │                                                     │   │  └── local/          │
│       │ sync-shuttle push -s server-a -S ~/my-file.txt      │   │      └── inbox/      │
│       ▼                                                     │   │          └── your-   │
│  ┌─────────────────┐                                        │   │              host/   │
│  │ 1. Validate     │ Check path is safe, size limits        │   │              └── my- │
│  │    & Preflight  │                                        │   │                  file│
│  └────────┬────────┘                                        │   │                  .txt│
│           ▼                                                 │   │                      │
│  ┌─────────────────┐                                        │   └──────────────────────┘
│  │ 2. Stage to     │ ~/.sync-shuttle/remote/server-a/files/ │             ▲
│  │    local mirror │                                        │             │
│  └────────┬────────┘                                        │             │
│           ▼                                                 │             │
│  ┌─────────────────┐         rsync over SSH                 │             │
│  │ 3. rsync to     │ ───────────────────────────────────────┼─────────────┘
│  │    remote       │                                        │
│  └────────┬────────┘                                        │
│           ▼                                                 │
│  ┌─────────────────┐                                        │
│  │ 4. Log          │ Write to sync.log + sync.jsonl         │
│  │    operation    │                                        │
│  └─────────────────┘                                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Pull Flow

```
      REMOTE SERVER                           YOUR MACHINE
┌──────────────────────┐   ┌─────────────────────────────────────────────────────────────┐
│                      │   │                                                             │
│  ~/.sync-shuttle/    │   │  sync-shuttle pull -s server-a                              │
│  └── local/          │   │       │                                                     │
│      └── outbox/     │   │       ▼                                                     │
│          └── file.txt│   │  ┌─────────────────┐                                        │
│               │      │   │  │ 1. Validate     │ Check SSH connection                   │
│               │      │   │  │    & Connect    │                                        │
│               │      │   │  └────────┬────────┘                                        │
│               │      │   │           ▼                                                 │
│               │      │   │  ┌─────────────────┐       rsync over SSH                   │
│               └──────┼───┼─▶│ 2. rsync from   │◀──────────────────────                 │
│                      │   │  │    remote       │                                        │
│                      │   │  └────────┬────────┘                                        │
│                      │   │           ▼                                                 │
│                      │   │  ┌─────────────────┐                                        │
│                      │   │  │ 3. Save to      │ ~/.sync-shuttle/local/inbox/server-a/  │
│                      │   │  │    inbox        │                                        │
│                      │   │  └────────┬────────┘                                        │
│                      │   │           ▼                                                 │
│                      │   │  ┌─────────────────┐                                        │
│                      │   │  │ 4. Log          │                                        │
│                      │   │  │    operation    │                                        │
│                      │   │  └─────────────────┘                                        │
│                      │   │                                                             │
└──────────────────────┘   └─────────────────────────────────────────────────────────────┘
```

### Multi-Machine Topology

```
                              ┌─────────────────┐
                              │   Server A      │
                              │  (dev-server)   │
                         ┌───▶│                 │◀───┐
                         │    │ inbox/  outbox/ │    │
                         │    └─────────────────┘    │
                         │                           │
    ┌────────────────────┴───┐               ┌───────┴────────────────┐
    │                        │               │                        │
    │     Your Laptop        │               │    Your Desktop        │
    │                        │               │                        │
    │  outbox/ ──push──▶     │               │     ◀──push── outbox/  │
    │  inbox/  ◀──pull──     │               │     ──pull──▶ inbox/   │
    │                        │               │                        │
    └────────────────────────┘               └────────────────────────┘
                         │                           │
                         │    ┌─────────────────┐    │
                         │    │   Server B      │    │
                         └───▶│ (prod-backup)   │◀───┘
                              │                 │
                              │ inbox/  outbox/ │
                              └─────────────────┘
```

### File Discovery Flow

```
sync-shuttle files --remote
        │
        ▼
┌───────────────────┐     ┌───────────────────┐     ┌───────────────────┐
│  Check Local      │     │  Check Cache      │     │  SSH Query        │
│  inbox/outbox     │     │  (5 min TTL)      │     │  (parallel)       │
└─────────┬─────────┘     └─────────┬─────────┘     └─────────┬─────────┘
          │                         │                         │
          │ instant                 │ if valid                │ if cache miss
          ▼                         ▼                         ▼
     ┌─────────────────────────────────────────────────────────────┐
     │                      Display Results                        │
     │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
     │  │ Outbox (1)  │  │ Inbox (3)   │  │ Remote (5) [cached] │  │
     │  │ - file.txt  │  │ - from A    │  │ - server-a: 2 files │  │
     │  │             │  │ - from B    │  │ - server-b: 3 files │  │
     │  └─────────────┘  └─────────────┘  └─────────────────────┘  │
     └─────────────────────────────────────────────────────────────┘
```

## Cleanup & Maintenance

### What Accumulates

| Location | What | Auto-cleanup? |
|----------|------|---------------|
| `archive/` | Backup copies before overwrites | Yes (30 days default) |
| `cache/` | Remote file listings | Yes (5 min TTL) |
| `logs/` | Operation logs | No |
| `inbox/` | Received files | No (user manages) |
| `tmp/` | Transfer staging | Yes (on exit) |

### Missing: `cleanup` Command

```bash
# Suggested commands (not yet implemented)

sync-shuttle cleanup              # Interactive cleanup wizard
sync-shuttle cleanup --logs       # Remove logs older than 30 days
sync-shuttle cleanup --archive    # Remove archives per retention policy
sync-shuttle cleanup --cache      # Clear all cached data
sync-shuttle cleanup --inbox      # List old inbox files for review
sync-shuttle cleanup --dry-run    # Show what would be removed
```

### Retention Config

```bash
# In sync-shuttle.conf
ARCHIVE_RETENTION_DAYS=30    # 0 = keep forever
LOG_RETENTION_DAYS=90        # Not yet implemented
```

## Safety Guarantees

1. **Never deletes source files** - sync-shuttle only copies
2. **Never overwrites without backup** - archives old version first
3. **Sandbox enforcement** - all operations confined to ~/.sync-shuttle/
4. **Path traversal protection** - blocks `../` attacks
5. **Dry-run by default culture** - always preview with `--dry-run` first
