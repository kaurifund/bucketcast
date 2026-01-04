# Bug: rsync Destroys Folder Structure When Trailing Slash Used

**Type:** Bug
**Severity:** High
**Status:** In Progress
**Branch:** hotfix/rsync-folder-structure

## Summary

When pushing a directory with a trailing slash (e.g., `00081/`), the folder structure is not preserved. Contents are scattered directly into the inbox instead of being wrapped in the original folder.

## Steps to Reproduce

```bash
# On local machine - NOTE THE TRAILING SLASH
sync-shuttle push -s myserver -S ~/myproject/

# Expected on remote:
~/.sync-shuttle/local/inbox/<hostname>/myproject/
├── file1.txt
├── file2.txt
└── subdir/

# Actual on remote:
~/.sync-shuttle/local/inbox/<hostname>/
├── file1.txt      ← contents dumped directly, folder name lost
├── file2.txt
└── subdir/
```

## Root Cause

The user-provided SOURCE_PATH is passed directly to rsync without normalizing trailing slashes.

In rsync:
- `rsync dir dest/` → copies `dir` INTO `dest/` (creates `dest/dir/`) ✓
- `rsync dir/ dest/` → copies **CONTENTS** of `dir` into `dest/` (no folder!) ✗

When user provides `00081/` with trailing slash:
```
perform_rsync_push("00081/", "files/")
                        ↑ trailing slash from user input
```
rsync copies CONTENTS of `00081` directly into staging, losing the folder name.

## Fix

Strip trailing slashes from SOURCE_PATH in argument parsing:

```bash
# In sync-shuttle.sh, after setting SOURCE_PATH
SOURCE_PATH="${SOURCE_PATH%/}"  # Remove trailing slash
```

## Why NOT in sync_to_remote?

The `sync_to_remote()` function correctly uses `$local_dir/` with trailing slash because:
- `local_dir` = `~/.sync-shuttle/remote/<server>/files` (staging container)
- We WANT to copy contents of `files/` (which contains `mydir/`) to remote
- Result: `inbox/hostname/mydir/` ✓

The bug is in the input, not the sync function.

## Impact

- Directory pushes with trailing slash lose folder structure
- File pushes unaffected
- Directory pushes WITHOUT trailing slash work correctly
- Data is not lost, but folder organization is destroyed

## Testing

```bash
# Should preserve folder name
sync-shuttle push -s test -S ./testdir/ --dry-run
# Verify staging: ~/.sync-shuttle/remote/test/files/testdir/ exists

# Without trailing slash should also work
sync-shuttle push -s test -S ./testdir --dry-run
```
