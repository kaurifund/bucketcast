# Ticket: Enable rsync Delta Transfers for Performance

**Type:** Performance Bug
**Priority:** High
**Status:** Open
**Created:** 2026-01-05

---

## Problem

Sync-shuttle is significantly slower than it should be because `--ignore-existing` prevents rsync's delta transfer algorithm from working.

### Current Behavior

In `lib/transfer.sh:53`:
```bash
options+=("--ignore-existing" "--backup" "--backup-dir=.sync-shuttle-backup")
```

The `--ignore-existing` flag tells rsync to **skip any file that already exists** at the destination, regardless of whether it has changed.

### Impact

| Scenario | Expected | Actual |
|----------|----------|--------|
| Push new file | Copy file | Copy file ✓ |
| Push changed file | Delta transfer (only changes) | **SKIPPED entirely** |
| Push unchanged file | Skip (no transfer) | Skip ✓ |
| Re-push same file | Skip or delta | **SKIPPED, no update** |

### Why This Matters

rsync's delta transfer algorithm is its killer feature:
- For a 100MB file with 1KB change → transfers ~1KB
- With `--ignore-existing` → transfers 0 bytes (file skipped, no update)

Users who modify a file and re-push will see:
1. rsync reports "0 files transferred"
2. File on remote is NOT updated
3. User uses `--force` in frustration
4. `--force` triggers full file copy (no delta)

---

## Root Cause Analysis

The `--ignore-existing` flag was likely added for safety (don't overwrite remote files). However, this completely bypasses rsync's incremental update capability.

### Code Path

```
sync-shuttle push -s server -S file.txt
        │
        ▼
perform_rsync_push(source, staging/)     ← --ignore-existing
        │
        ▼
sync_to_remote(server, staging/)         ← --ignore-existing
        │
        ▼
Remote: inbox/<hostname>/file.txt        ← Never updated if exists
```

---

## Proposed Solutions

### Option A: Use `--update` (Recommended)

Replace `--ignore-existing` with `--update`:

```bash
# Before
options+=("--ignore-existing" "--backup" "--backup-dir=.sync-shuttle-backup")

# After
options+=("--update" "--backup" "--backup-dir=.sync-shuttle-backup")
```

**Behavior:**
- Only overwrites if source is **newer** (by mtime)
- Enables delta transfers for changed files
- Still safe: won't overwrite newer destination files

**Pros:**
- Simple one-line change
- Enables delta transfers
- Still prevents accidental overwrites of newer files

**Cons:**
- Relies on mtime accuracy
- Won't update if dest is newer (even if user wants to)

---

### Option B: Use `--checksum` with `--update`

```bash
options+=("--checksum" "--update" "--backup" "--backup-dir=.sync-shuttle-backup")
```

**Behavior:**
- Compares files by checksum, not mtime
- Only transfers if content actually differs
- Delta transfer for changed content

**Pros:**
- Most accurate change detection
- Works even if mtimes are unreliable

**Cons:**
- Slower initial scan (must checksum all files)
- More CPU usage

---

### Option C: Remove `--ignore-existing` entirely

```bash
options+=("--backup" "--backup-dir=.sync-shuttle-backup")
```

**Behavior:**
- Always syncs source to destination
- Existing files are backed up before overwrite
- Full delta transfer capability

**Pros:**
- Maximum rsync efficiency
- Backups provide safety net

**Cons:**
- May overwrite files user wanted to keep
- Relies on backup for recovery

---

### Option D: Make it configurable

Add to `sync-shuttle.conf`:
```bash
# Sync mode: "safe" (ignore-existing), "update" (newer wins), "sync" (always)
SYNC_MODE="update"
```

**Pros:**
- User choice
- Backward compatible (default to current behavior)

**Cons:**
- More complexity
- Users must understand the options

---

## Recommendation

**Option A (`--update`)** provides the best balance:
- Enables delta transfers (major performance win)
- Still safe (won't overwrite newer files)
- Simple change, low risk

For users who need checksum-based comparison, add `--checksum` to `RSYNC_OPTIONS` in config.

---

## Files to Change

| File | Change |
|------|--------|
| `lib/transfer.sh:53` | Replace `--ignore-existing` with `--update` |
| `SPECIFICATION.md` | Document sync behavior |
| `README.md` | Note about delta transfers |

---

## Testing Plan

1. Create a 10MB test file, push to remote
2. Modify 1 byte in the file
3. Push again, verify:
   - rsync shows delta transfer (not full file)
   - File on remote is updated
   - Transfer completes in < 1 second
4. Push unchanged file, verify skip
5. Test `--force` still works

---

## Performance Expectation

| File Size | Change Size | Current | With Fix |
|-----------|-------------|---------|----------|
| 100 MB | 1 KB | Skipped (no update) | ~1 KB transfer |
| 100 MB | 1 KB + force | 100 MB | ~1 KB transfer |
| 1 GB | 10 KB | Skipped | ~10 KB transfer |

---

## References

- rsync man page: `--ignore-existing`, `--update`, `--checksum`
- rsync delta algorithm: https://rsync.samba.org/tech_report/
