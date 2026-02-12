# Research: Rename sync-shuttle to bucketcast

## Scope

Pure name rename. No logic, structure, or behavior changes.

## Name Variants Found

| Old Pattern | New Pattern | Context |
|---|---|---|
| `sync-shuttle` | `bucketcast` | kebab-case: filenames, paths, CLI commands, config keys |
| `sync_shuttle` | `bucketcast` | snake_case: bash variables, function names, Python imports |
| `Sync Shuttle` | `Bucketcast` | Title Case: prose, UI strings, comments |
| `SYNC SHUTTLE` | `BUCKETCAST` | Upper banner: ASCII art headers, banners |
| `SYNC_SHUTTLE` | `BUCKETCAST` | UPPER_SNAKE: env vars (SYNC_SHUTTLE_DIR, etc.) |
| `SYNC-SHUTTLE` | `BUCKETCAST` | UPPER-KEBAB: .gitignore header, llm.txt header |
| `syncshuttle` | `bucketcast` | no-separator: .syncshuttlerc filename refs |
| `SyncShuttle` | `Bucketcast` | PascalCase: Python class name (SyncShuttleTUI) |
| `sync_tui` | `bucketcast_tui` | Python TUI module name |
| `SyncTui` | `BucketcastTui` | (not found but check) |

## Files to RENAME (4 files)

| Old Path | New Path |
|---|---|
| `sync-shuttle.sh` | `bucketcast.sh` |
| `config/sync-shuttle.conf.example` | `config/bucketcast.conf.example` |
| `config/.syncshuttlerc.example` | `config/.bucketcastrc.example` |
| `tui/sync_tui.py` | `tui/bucketcast_tui.py` |

## Files Requiring Content Changes (29 files, ~435 occurrences)

### Core (6 files)
- `sync-shuttle.sh` (55 occurrences) - main script, rename + content
- `install.sh` (30 occurrences) - installer
- `lib/core.sh` (2 occurrences)
- `lib/logging.sh` (1 occurrence)
- `lib/s3.sh` (4 occurrences)
- `lib/transfer.sh` (2 occurrences)
- `lib/validation.sh` (4 occurrences)
- `lib/config_parser.py` (6 occurrences)

### Config (3 files)
- `config/sync-shuttle.conf.example` (8 occurrences) - rename + content
- `config/.syncshuttlerc.example` (11 occurrences) - rename + content
- `config/servers.toml.example` (5 occurrences)

### TUI (2 files)
- `tui/sync_tui.py` (13 occurrences) - rename + content
- `tui/requirements.txt` (1 occurrence)

### Tests (9 files)
- `tests/run_tests.sh` (5 occurrences)
- `tests/helpers/test_helpers.sh` (9 occurrences)
- `tests/helpers/fixtures.sh` (9 occurrences)
- `tests/e2e/test_scenarios.sh` (34 occurrences)
- `tests/integration/test_config.sh` (5 occurrences)
- `tests/integration/test_transfer.sh` (1 occurrence)
- `tests/fixtures/sample_config.conf` (1 occurrence)
- `tests/fixtures/sample_servers.conf` (2 occurrences)

### Docs / Meta (7 files)
- `README.md` (34 occurrences)
- `SPECIFICATION.md` (11 occurrences)
- `.gitignore` (6 occurrences)
- `_other/AUDIT_REPORT.md` (15 occurrences)
- `_other/llm.txt` (44 occurrences)
- `_other/llm-v1.0.txt` (102 occurrences)

### Existing Tickets (2 files)
- `tickets/BUG_RSYNC_FOLDER_STRUCTURE.md` (8 occurrences)
- `tickets/BUG_STAGING_ACCUMULATION.md` (7 occurrences)

## Key Replacement Details

### Environment Variables (install.sh, config)
- `SYNC_SHUTTLE_DIR` -> `BUCKETCAST_DIR`
- `SYNC_SHUTTLE_BRANCH` -> `BUCKETCAST_BRANCH`
- `SYNC_SHUTTLE_NO_RC` -> `BUCKETCAST_NO_RC`
- `SYNC_SHUTTLE_REPO` -> `BUCKETCAST_REPO`
- `SYNC_SHUTTLE_EDITOR` -> `BUCKETCAST_EDITOR`
- `SYNC_SHUTTLE_DRY_RUN_DEFAULT` -> `BUCKETCAST_DRY_RUN_DEFAULT`
- `SYNC_SHUTTLE_VERBOSE_DEFAULT` -> `BUCKETCAST_VERBOSE_DEFAULT`
- `SYNC_SHUTTLE_CONFIRM_FORCE` -> `BUCKETCAST_CONFIRM_FORCE`
- `SYNC_SHUTTLE_ALIAS_*` -> `BUCKETCAST_ALIAS_*`

### Path References
- `~/.sync-shuttle/` -> `~/.bucketcast/`
- `~/.local/share/sync-shuttle/` -> `~/.local/share/bucketcast/`
- `~/.syncshuttlerc` -> `~/.bucketcastrc`
- `/tmp/sync-shuttle-test*` -> `/tmp/bucketcast-test*`
- `sync-shuttle-archive` -> `bucketcast-archive` (S3 prefix)
- `sync-shuttle-bucket` -> `bucketcast-bucket` (S3 bucket name)

### Function Names (bash)
- `init_sync_shuttle()` -> `init_bucketcast()`
- `initialize_sync_shuttle()` -> `initialize_bucketcast()`
- `init_test_sync_shuttle()` -> `init_test_bucketcast()`

### Python Class Names
- `SyncShuttleTUI` -> `BucketcastTUI`

### Script References (cross-file)
- `sync-shuttle.sh` -> `bucketcast.sh` (referenced in tests, TUI, docs)
- `sync_tui.py` -> `bucketcast_tui.py` (referenced in sync-shuttle.sh, docs)
- `sync-shuttle.conf` -> `bucketcast.conf` (referenced everywhere)
- `.syncshuttlerc` -> `.bucketcastrc` (referenced in config, .gitignore)

## Risks / Watch Items

1. **Ordering matters**: Rename files AFTER content changes (or use git mv which tracks)
2. **No functional changes**: Only name strings change. No logic, no structure, no formatting
3. **Case sensitivity**: Must handle all 8+ case variants listed above
4. **S3 prefix/bucket names**: These are config values, not code - still rename for consistency
5. **Remote path defaults**: `remote_base` values like `/home/user/.sync-shuttle` must change
6. **Git repo URL**: `https://github.com/kaurifund/bucketcast` already says bucketcast - no change needed
