# Sync Shuttle - Project Specification

## Project Intent

Sync Shuttle is a **safe, idempotent file synchronization tool** designed for manual, 
on-demand file transfers between a home computer and remote servers. It prioritizes 
safety over convenience, ensuring files are never accidentally deleted or overwritten.

## Key Assumptions

1. **Manual Execution**: This is NOT a real-time sync daemon; it runs on-demand
2. **Known Paths Only**: All operations are sandboxed to `~/.sync-shuttle/` directory
3. **SSH-Based**: Remote transfers use scp/rsync over SSH (keys recommended)
4. **Single User**: Designed for personal use, not multi-tenant environments
5. **Idempotent**: Running the same sync twice produces the same result safely
6. **Append-Only Philosophy**: Files are added/versioned, never deleted by the tool

## Product Objectives

| Objective | Description | Priority |
|-----------|-------------|----------|
| Safety | Never delete or overwrite without explicit consent | P0 |
| Simplicity | Easy to understand, configure, and run | P0 |
| Auditability | Complete logging of all operations | P0 |
| Idempotency | Safe to run multiple times | P1 |
| Extensibility | S3 backup, additional protocols | P2 |
| Usability | CLI flags + optional TUI | P2 |

## Core Features

### 1. Safe File Transfer
- Push files TO remote servers
- Pull files FROM remote servers
- Configurable server profiles
- No overwrites without `--force` flag

### 2. Sandboxed Operations
- All files stored in `~/.sync-shuttle/`
- Structure: `~/.sync-shuttle/remote/<server_id>/files/`
- Local shares: `~/.sync-shuttle/local/outbox/` (global/ or <server_id>/)
- Incoming files: `~/.sync-shuttle/local/inbox/`

### 3. Comprehensive Logging
- UUID per operation
- Timestamps (ISO 8601)
- Source/destination paths
- Bytes transferred
- Success/failure status
- Structured JSON logs

### 4. CLI Interface
- `--dry-run`: Preview without executing
- `--force`: Allow overwrites (with confirmation)
- `--server <id>`: Target specific server
- `--direction <push|pull>`: Transfer direction
- `--verbose`: Detailed output
- `--quiet`: Minimal output

### 5. Optional TUI
- Interactive server selection
- Visual file browser
- Transfer progress display
- Log viewer

### 6. Optional S3 Integration
- Archive completed transfers
- Use as intermediate storage
- Configurable retention

## Directory Structure (Runtime)

```
~/.sync-shuttle/
├── config/
│   ├── sync-shuttle.conf      # Main configuration
│   └── servers.toml           # Server definitions
├── remote/
│   └── <server_id>/
│       └── files/             # Files synced from this server
├── local/
│   ├── inbox/                 # Files received from remotes
│   │   └── <server_id>/       # Per-server incoming files
│   └── outbox/                # Files shared with remotes
│       ├── global/            # Available to all servers
│       └── <server_id>/       # Server-specific shares
├── logs/
│   ├── sync.log               # Human-readable log
│   └── sync.jsonl             # Machine-readable log (JSON Lines)
├── archive/                   # Versioned backups (optional)
│   └── <timestamp>/
└── tmp/                       # Temporary files during transfer
```

## Schema Contracts

### Server Configuration Schema
```
ServerConfig {
    id: string (alphanumeric, lowercase, 3-32 chars)
    name: string (display name)
    host: string (hostname or IP)
    port: integer (1-65535, default: 22)
    user: string (SSH username)
    identity_file: string (path to SSH key, optional)
    remote_base: string (remote sync-shuttle path)
    enabled: boolean
    s3_backup: boolean (optional)
}
```

### Sync Request Schema (Input)
```
SyncRequest {
    uuid: string (UUIDv4, auto-generated)
    timestamp: string (ISO 8601)
    server_id: string
    direction: enum (PUSH | PULL)
    source_path: string
    dest_path: string (computed)
    options: {
        dry_run: boolean
        force: boolean
        verbose: boolean
    }
}
```

### Sync Result Schema (Output)
```
SyncResult {
    uuid: string (matches request)
    timestamp_start: string (ISO 8601)
    timestamp_end: string (ISO 8601)
    status: enum (SUCCESS | PARTIAL | FAILED | SKIPPED)
    server_id: string
    direction: enum (PUSH | PULL)
    source_path: string
    dest_path: string
    files: [{
        name: string
        size_bytes: integer
        status: enum (TRANSFERRED | SKIPPED | FAILED)
        reason: string (if skipped/failed)
    }]
    total_bytes: integer
    error_message: string (if failed)
}
```

### Log Entry Schema
```
LogEntry {
    uuid: string
    timestamp: string (ISO 8601)
    level: enum (INFO | WARN | ERROR | DEBUG)
    operation: string
    server_id: string
    source_path: string
    dest_path: string
    bytes_transferred: integer
    status: string
    message: string
    metadata: object (flexible)
}
```

## Access Patterns

### Read Patterns
1. List configured servers → Read `servers.toml`
2. View sync history → Read `logs/sync.jsonl`
3. Browse remote files → List `remote/<server_id>/files/`
4. Check shared files → List `local/outbox/global/` or `local/outbox/<server_id>/`

### Write Patterns
1. Add server → Append to `servers.toml`
2. Push files → Copy to `remote/<server_id>/files/` + rsync
3. Pull files → Rsync + copy to `local/inbox/`
4. Log operation → Append to both log files

## Safety Mechanisms

1. **Path Validation**: All paths must be within `~/.sync-shuttle/`
2. **No Deletion**: Tool never deletes files (archive only)
3. **Collision Detection**: Check for existing files before write
4. **Dry Run Default**: Recommend dry-run for first use
5. **Confirmation Prompts**: Required for `--force` operations
6. **Atomic Operations**: Use tmp + move pattern
7. **Rollback Capability**: Archive before modify

## Future Extensibility

### Phase 2 Features
- [ ] S3 as intermediate storage layer
- [ ] S3 archival with lifecycle policies
- [ ] Multiple S3 buckets per server
- [ ] Encryption at rest (GPG)

### Phase 3 Features
- [ ] Watch mode (inotify-based)
- [ ] Conflict resolution strategies
- [ ] Bandwidth limiting
- [ ] Resume interrupted transfers
- [ ] Checksum verification

### Integration Points
- [ ] Systemd timer for scheduled syncs
- [ ] Desktop notifications
- [ ] Webhook callbacks
- [ ] Prometheus metrics endpoint
