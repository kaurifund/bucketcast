# Bug: Push Staging Area Accumulates Indefinitely

**Type:** Bug (Design Oversight)
**Severity:** Medium
**Status:** Fixed
**Commits:**
- `64bf36f` (PR #5) - Initial fix using tmp/ (incorrect location)
- `2b20f28` - Corrected to use remote/<server>/ (proper location)

## Summary

The push staging directory (`~/.sync-shuttle/remote/<server>/files/`) accumulates files across pushes. Each subsequent push re-syncs ALL previously staged files to the remote, not just the new ones.

## Steps to Reproduce

```bash
# Day 1: Push 10 files
sync-shuttle push -s myserver file1 file2 ... file10
# Result: 10 files synced ✓

# Day 2: Push 1 new file
sync-shuttle push -s myserver newfile.txt
# Expected: 1 file synced
# Actual: 11 files synced (10 old + 1 new)
```

## Root Cause

1. Files are staged to persistent directory: `~/.sync-shuttle/remote/<server>/files/`
2. `sync_to_remote()` syncs entire staging directory to remote
3. No cleanup after successful sync
4. Staging accumulates indefinitely

## Impact

- **Not unsafe** - no data loss, `--ignore-existing` prevents overwrites
- **Inefficient** - re-transfers all previously staged files
- **Confusing** - user expects atomic push, gets cumulative sync
- **Wasteful** - bandwidth, SSH overhead

## Investigation

Full analysis confirmed this is a **design oversight**:
- ARCHITECTURE.md lists what should accumulate (`archive/`, `cache/`, `logs/`, `inbox/`)
- `remote/` staging is NOT listed - was meant to be temporary like `tmp/`
- No docs, comments, or tests validating accumulation as intentional
- Cleanup exists for `tmp/` (on exit) but not for staging

## Fix: Operation-Scoped Staging

Instead of a shared `files/` directory, use **per-operation staging with UUID**:

```bash
# Before (accumulates):
staging_dir="${REMOTE_DIR}/${SERVER_ID}/files"

# After (isolated per push):
staging_dir="${REMOTE_DIR}/${SERVER_ID}/push-${OPERATION_UUID}"
```

### Why `remote/<server>/` not `tmp/`?
- `remote/` is for per-server data - staging is server-specific
- `tmp/` is for ephemeral scratch (locks, markers)
- Keeping staging under `remote/<server>/` maintains logical organization

### Benefits:
- Each push is isolated - no accumulation possible
- Server-specific organization preserved
- Explicit cleanup after successful sync
- Operation UUID provides auditability

### Implementation:

**In `action_push()` (sync-shuttle.sh:954-990):**

```bash
# Create operation-specific staging directory under server's remote dir
# Uses UUID for isolation - each push gets its own staging, cleaned after sync
local staging_dir="${REMOTE_DIR}/${SERVER_ID}/push-${OPERATION_UUID}"
mkdir -p "$staging_dir"

# Stage files
perform_rsync_push "$SOURCE_PATH" "$staging_dir" ""

# Sync to remote
sync_to_remote "$SERVER_ID" "$staging_dir"

# Cleanup after successful sync
rm -rf "$staging_dir"
```

**Cleanup on failure/interrupt:**
- Failed operations leave staging for debugging
- Can be manually cleaned: `rm -rf ~/.sync-shuttle/remote/*/push-*`

### Migration:

Old staging dirs can be cleaned manually or via future `cleanup` command:
```bash
rm -rf ~/.sync-shuttle/remote/*/files/*
```

## Safety Checklist

- [x] Never touches user source files
- [x] Never touches remote files
- [x] Only cleans OUR temp directories
- [x] Idempotent - can re-push anytime
- [x] Auditable - logs preserve history
- [x] Aligned with tool philosophy

## Alternatives Considered

1. **`rm -rf` after sync** - Works but risky on persistent path
2. **Keep N most recent** - Complex, still accumulates
3. **Per-operation staging** ✓ - Cleanest, no accumulation possible
