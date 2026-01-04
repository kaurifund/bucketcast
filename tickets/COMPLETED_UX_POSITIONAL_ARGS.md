# Completed: Positional Arguments for Push Command

**Date:** 2026-01-04
**Status:** Done

## Problem

The push command required a `-S` flag before specifying source files:

```bash
# Old syntax (awkward)
sync-shuttle push -s myserver -S ~/file.txt
sync-shuttle push -s myserver -S ./config.json
```

This went against Unix conventions where source files are positional arguments (like `cp`, `rsync`, `scp`, `git add`).

## Solution

Source files are now positional arguments:

```bash
# New syntax (natural)
sync-shuttle push -s myserver file.txt
sync-shuttle push -s myserver file1.txt file2.txt dir/
sync-shuttle push -s myserver .
```

The `-S` flag still works for backwards compatibility.

## Changes Made

### sync-shuttle.sh

1. **Added `resolve_source_path()` helper** (line 428-438)
   - Resolves `.`, `..`, and relative paths to absolute paths
   - Ensures directory names are preserved when pushing

2. **Changed `SOURCE_PATH` to `SOURCE_PATHS` array** (line 341)
   - Supports multiple source files in a single push

3. **Updated argument parser**
   - Positional args collected as sources (line 649-652)
   - `-S` flag appends to array for backwards compat (line 572-580)
   - Fixed `servers|files` case to only match for `list` command (line 634-643)

4. **Updated `action_push()`** (line 1008-1097)
   - Validates all source paths exist
   - Calls `perform_rsync_push_multi()` for transfer

5. **Updated help text and examples**

### lib/transfer.sh

1. **Added `perform_rsync_push_multi()`** (line 122-181)
   - Handles multiple source files in single rsync call
   - Same error handling as single-file version

## Testing

| Test Case | Result |
|-----------|--------|
| `push -s server file.txt` | Pass |
| `push -s server file1.txt file2.txt` | Pass |
| `push -s server .` | Pass (resolves to full path) |
| `push -s server -S file.txt` (legacy) | Pass |
| `push -s server` (no files) | Proper error |
| `push -s server nonexistent.txt` | Proper error |
| `list servers` | Still works |
| File named `servers` can be pushed | Pass |
| Syntax check (`bash -n`) | Pass |

## Before/After

```bash
# Before
sync-shuttle push --server myserver --source ~/file.txt --dry-run
sync-shuttle push -s myserver -S ~/project/ -S ~/config.json

# After
sync-shuttle push -s myserver ~/file.txt --dry-run
sync-shuttle push -s myserver ~/project/ ~/config.json
sync-shuttle push -s myserver .
```
