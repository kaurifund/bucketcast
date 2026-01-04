# Bug: Push Staging Area Accumulates Indefinitely

**Type:** Bug (Design Oversight)
**Severity:** Medium
**Status:** Open
**Branch:** TBD

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

## Proposed Fix: Operation-Scoped Staging

Instead of `rm -rf` on a shared directory, use **temp staging per operation**:

```bash
# Before (accumulates):
dest_dir="${REMOTE_DIR}/${SERVER_ID}/files"

# After (isolated per push):
dest_dir="${TMP_DIR}/push-${OPERATION_UUID}"
```

### Benefits:
- Each push is isolated - no accumulation possible
- Natural cleanup - temp dir removed after operation
- No `rm -rf` on persistent user paths
- Aligns with existing `tmp/` cleanup pattern
- Operation UUID provides auditability

### Implementation:

**In `action_push()` (sync-shuttle.sh):**

```bash
# Create operation-specific staging directory
local staging_dir="${TMP_DIR}/push-${OPERATION_UUID}"
mkdir -p "$staging_dir"

# Stage files
perform_rsync_push_multi "${SOURCE_PATHS[@]}" "$staging_dir" ""

# Sync to remote
sync_to_remote "$SERVER_ID" "$staging_dir"

# Cleanup (only on success, automatic for temp)
rm -rf "$staging_dir"
```

**Cleanup on failure/interrupt:**
- `TMP_DIR` is already cleaned on exit via `cleanup_on_exit()` trap in `lib/core.sh`
- Failed operations leave staging for debugging, cleaned on next run

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
