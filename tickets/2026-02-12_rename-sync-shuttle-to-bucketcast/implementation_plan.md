# Implementation Plan: Rename sync-shuttle to bucketcast

## Constraint

**ONLY name changes.** No logic, formatting, structure, or behavior changes whatsoever.
This ticket WILL be rejected if anything else is modified.

## Strategy

Use `sed` for in-place content replacement across all 29 files, then `git mv` for the 4 file renames.
Order: content changes first, file renames second (so sed targets exist during replacement).

## Phase 1: Content Replacements (in-place sed)

Apply replacements in order from most-specific to least-specific to avoid partial matches.

### Step 1.1 - Compound / long patterns first

These must be replaced before their substrings to avoid double-replacement.

| Order | Old | New | Reason |
|---|---|---|---|
| 1 | `SyncShuttleTUI` | `BucketcastTUI` | PascalCase class (longest compound) |
| 2 | `SYNC_SHUTTLE` | `BUCKETCAST` | UPPER_SNAKE env vars |
| 3 | `SYNC-SHUTTLE` | `BUCKETCAST` | UPPER-KEBAB headers |
| 4 | `SYNC SHUTTLE` | `BUCKETCAST` | UPPER SPACE banners |
| 5 | `Sync Shuttle` | `Bucketcast` | Title Case prose |
| 6 | `sync-shuttle` | `bucketcast` | kebab-case (most common) |
| 7 | `sync_shuttle` | `bucketcast` | snake_case variables |
| 8 | `.syncshuttlerc` | `.bucketcastrc` | rc filename (before generic) |
| 9 | `syncshuttle` | `bucketcast` | no-separator residuals |
| 10 | `sync_tui` | `bucketcast_tui` | TUI module name |

### Step 1.2 - Target files

All 29 files listed in research.md. Apply sed to each.

**Exclusions from sed:** None. All files get all applicable patterns.

## Phase 2: File Renames (git mv)

| Order | Old | New |
|---|---|---|
| 1 | `sync-shuttle.sh` | `bucketcast.sh` |
| 2 | `config/sync-shuttle.conf.example` | `config/bucketcast.conf.example` |
| 3 | `config/.syncshuttlerc.example` | `config/.bucketcastrc.example` |
| 4 | `tui/sync_tui.py` | `tui/bucketcast_tui.py` |

## Phase 3: Verification

Run `test.sh` which performs:
1. **Zero old references**: grep for all old name variants, expect 0 matches (excluding ticket folder itself)
2. **New files exist**: check renamed files are present
3. **Old files gone**: check old filenames no longer exist
4. **New references present**: grep confirms new names appear in expected locations
5. **No untracked/unexpected changes**: git diff shows only name changes

## Phase 4: Commit

Single commit: `refactor: rename sync-shuttle to bucketcast across entire codebase`

## Execution Commands

```bash
# Phase 1: Content replacements
# Applied to all 29 affected files using sed -i

FILES=(
  .gitignore
  README.md
  SPECIFICATION.md
  install.sh
  sync-shuttle.sh
  lib/core.sh
  lib/logging.sh
  lib/s3.sh
  lib/transfer.sh
  lib/validation.sh
  lib/config_parser.py
  config/sync-shuttle.conf.example
  config/.syncshuttlerc.example
  config/servers.toml.example
  tui/sync_tui.py
  tui/requirements.txt
  tests/run_tests.sh
  tests/helpers/test_helpers.sh
  tests/helpers/fixtures.sh
  tests/e2e/test_scenarios.sh
  tests/integration/test_config.sh
  tests/integration/test_transfer.sh
  tests/fixtures/sample_config.conf
  tests/fixtures/sample_servers.conf
  _other/AUDIT_REPORT.md
  _other/llm.txt
  _other/llm-v1.0.txt
  tickets/BUG_RSYNC_FOLDER_STRUCTURE.md
  tickets/BUG_STAGING_ACCUMULATION.md
)

# Replacements in order (most specific first):
sed -i 's/SyncShuttleTUI/BucketcastTUI/g'
sed -i 's/SYNC_SHUTTLE/BUCKETCAST/g'
sed -i 's/SYNC-SHUTTLE/BUCKETCAST/g'
sed -i 's/SYNC SHUTTLE/BUCKETCAST/g'
sed -i 's/Sync Shuttle/Bucketcast/g'
sed -i 's/sync-shuttle/bucketcast/g'
sed -i 's/sync_shuttle/bucketcast/g'
sed -i 's/\.syncshuttlerc/.bucketcastrc/g'
sed -i 's/syncshuttle/bucketcast/g'
sed -i 's/sync_tui/bucketcast_tui/g'

# Phase 2: File renames
git mv sync-shuttle.sh bucketcast.sh
git mv config/sync-shuttle.conf.example config/bucketcast.conf.example
git mv config/.syncshuttlerc.example config/.bucketcastrc.example
git mv tui/sync_tui.py tui/bucketcast_tui.py

# Phase 3: Run test.sh
bash tickets/2026-02-12_rename-sync-shuttle-to-bucketcast/test.sh

# Phase 4: Commit
git add -A
git commit -m "refactor: rename sync-shuttle to bucketcast across entire codebase"
```

## Rollback

```bash
git checkout main -- .
git checkout main
git branch -D refactor/rename-sync-shuttle-to-bucketcast
```
