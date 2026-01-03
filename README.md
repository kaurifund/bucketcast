# Sync Shuttle 🚀

**Safe, Idempotent File Synchronization for Manual Transfers**

Sync Shuttle is a command-line tool for safely transferring files between your home computer and remote servers. It prioritizes safety and auditability over speed, ensuring files are never accidentally deleted or overwritten.

## Features

- 🔒 **Safe by Design**: Never deletes files, never overwrites without consent
- 📁 **Sandboxed Operations**: All files stored in `~/.sync-shuttle/`
- 🔄 **Bidirectional Sync**: Push to and pull from remote servers
- 📝 **Comprehensive Logging**: JSON and human-readable logs
- 🎯 **Idempotent**: Safe to run multiple times
- ☁️ **Optional S3 Integration**: Archive to S3 for backup
- 🖥️ **Optional TUI**: Interactive terminal interface

## Quick Start

```bash
# 1. Clone or download
git clone https://github.com/user/sync-shuttle.git
cd sync-shuttle

# 2. Initialize
./sync-shuttle.sh init

# 3. Configure a server
# Edit ~/.sync-shuttle/config/servers.conf

# 4. Test with dry-run
./sync-shuttle.sh push --server myserver --source ~/myfile.txt --dry-run

# 5. Execute
./sync-shuttle.sh push --server myserver --source ~/myfile.txt
```

## Installation

### Prerequisites

- **Bash 4.0+** (check with `bash --version`)
- **rsync 3.0+** (check with `rsync --version`)
- **SSH** with key-based authentication configured
- **uuidgen** (usually pre-installed)

### Optional

- **AWS CLI** (for S3 integration)
- **Python 3** with `textual` and `rich` (for TUI)
- **jq** (for log parsing)

### Install

```bash
# Clone the repository
git clone https://github.com/user/sync-shuttle.git

# Add to PATH (optional)
echo 'export PATH="$PATH:/path/to/sync-shuttle"' >> ~/.bashrc
source ~/.bashrc

# Initialize
sync-shuttle.sh init
```

## Directory Structure

After initialization, Sync Shuttle creates:

```
~/.sync-shuttle/
├── config/
│   ├── sync-shuttle.conf    # Main configuration
│   └── servers.conf         # Server definitions
├── remote/
│   └── <server_id>/
│       └── files/           # Files synced with this server
├── local/
│   ├── inbox/               # Files received from remotes
│   └── outbox/              # Files staged for sending
├── logs/
│   ├── sync.log             # Human-readable log
│   └── sync.jsonl           # JSON Lines log
├── archive/                 # Versioned backups
└── tmp/                     # Temporary files
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `init` | Initialize directory structure |
| `push` | Push files TO a remote server |
| `pull` | Pull files FROM a remote server |
| `list servers` | List configured servers |
| `list files` | List files for a server |
| `status` | Show sync status |
| `tui` | Launch interactive TUI |

### Options

| Flag | Description |
|------|-------------|
| `-s, --server <id>` | Target server ID |
| `-S, --source <path>` | Source file/directory |
| `-n, --dry-run` | Preview without executing |
| `-f, --force` | Allow overwrites (prompts) |
| `-v, --verbose` | Verbose output |
| `-q, --quiet` | Minimal output |
| `--s3-archive` | Archive to S3 after sync |

### Examples

```bash
# Push a single file
sync-shuttle.sh push -s myserver -S ~/document.pdf

# Push a directory
sync-shuttle.sh push -s myserver -S ~/projects/myapp/

# Pull from a server
sync-shuttle.sh pull -s myserver

# Dry-run (always recommended first!)
sync-shuttle.sh push -s myserver -S ~/data.zip --dry-run

# Force overwrite (archives existing)
sync-shuttle.sh push -s myserver -S ~/updated.txt --force

# With S3 archival
sync-shuttle.sh push -s myserver -S ~/backup/ --s3-archive
```

## Configuration

### Server Configuration

Edit `~/.sync-shuttle/config/servers.conf`:

```bash
declare -A server_myserver=(
    [name]="My Development Server"
    [host]="192.168.1.100"
    [port]="22"
    [user]="myuser"
    [remote_base]="/home/myuser/.sync-shuttle"
    [enabled]="true"
    [s3_backup]="false"
)
```

### Main Configuration

Edit `~/.sync-shuttle/config/sync-shuttle.conf`:

```bash
# Log level: DEBUG, INFO, WARN, ERROR
LOG_LEVEL="INFO"

# Maximum transfer size
MAX_TRANSFER_SIZE="10G"

# Archive retention days
ARCHIVE_RETENTION_DAYS=30

# S3 settings (optional)
S3_ENABLED="true"
S3_BUCKET="my-backup-bucket"
S3_PREFIX="sync-shuttle-archive"
```

## Safety Features

1. **Path Validation**: All paths must be within `~/.sync-shuttle/`
2. **No Deletion**: The tool never deletes files
3. **No Overwrites**: Existing files are never overwritten without `--force`
4. **Confirmation Prompts**: Force mode requires explicit confirmation
5. **Automatic Archival**: Files are archived before overwrite
6. **Dry Run**: Preview any operation without changes
7. **Operation Logging**: Every operation is logged with UUID

## S3 Integration

Enable S3 for cloud backup:

```bash
# In sync-shuttle.conf
S3_ENABLED="true"
S3_BUCKET="my-sync-shuttle-bucket"
S3_PREFIX="archive"

# Use with any sync
sync-shuttle.sh push -s myserver -S ~/data/ --s3-archive

# Or use S3 as intermediate layer
sync-shuttle.sh s3-push -s myserver -S ~/data/
# On another machine:
sync-shuttle.sh s3-pull --transfer-id <uuid>
```

## TUI (Terminal User Interface)

Launch the interactive interface:

```bash
# Install dependencies
pip install textual rich

# Launch TUI
sync-shuttle.sh tui
```

The TUI provides:
- Server list and status
- Recent operations history
- File browser for inbox/outbox
- Push/pull wizards with options

## Logs

### Human-Readable Log

```
[2024-01-15 10:30:45] [INFO] Starting PUSH operation [abc123-...]
[2024-01-15 10:30:46] [INFO] Transferring: ~/file.txt -> ~/.sync-shuttle/remote/myserver/files/
[2024-01-15 10:30:50] [SUCCESS] Push operation completed
```

### JSON Log (for parsing)

```json
{"uuid":"abc123...","operation":"push","server_id":"myserver","status":"SUCCESS","bytes_transferred":1024,"timestamp_start":"2024-01-15T10:30:45Z"}
```

### View Logs

```bash
# Recent operations
tail -f ~/.sync-shuttle/logs/sync.log

# Parse JSON logs (requires jq)
cat ~/.sync-shuttle/logs/sync.jsonl | jq 'select(.status=="FAILED")'
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Configuration error |
| 4 | Path validation failed |
| 5 | Transfer failed |
| 6 | Collision (no --force) |
| 7 | User cancelled |
| 8 | Required tool missing |

## Troubleshooting

### SSH Connection Failed

```bash
# Test SSH manually
ssh -p 22 user@host 'echo OK'

# Ensure key-based auth
ssh-copy-id -p 22 user@host
```

### Permission Denied

```bash
# Check directory permissions
ls -la ~/.sync-shuttle/

# Fix if needed
chmod -R u+rwX ~/.sync-shuttle/
```

### Rsync Errors

```bash
# Run with verbose
sync-shuttle.sh push -s myserver -S ~/file.txt --verbose

# Common fixes:
# - Ensure rsync is installed on remote
# - Check remote path exists
# - Verify SSH connectivity
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `./tests/test_sync.sh`
5. Submit a pull request

## License

MIT License - See LICENSE file for details.

## Acknowledgments

- Built with safety-first principles
- Inspired by the need for simple, reliable file sync
- Thanks to the rsync and SSH communities
