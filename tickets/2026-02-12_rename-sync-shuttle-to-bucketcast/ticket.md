# TICKET: Rename sync-shuttle to bucketcast

**Date:** 2026-02-12
**Branch:** `refactor/rename-sync-shuttle-to-bucketcast`
**Type:** Refactor (pure rename)
**Priority:** High

## Summary

Rename all references to "sync-shuttle" (and all case variants) to "bucketcast" across the entire codebase. This includes file names, directory path references, environment variables, function names, class names, CLI command names, config file names, and documentation.

## Scope

- **29 files** with content changes (~435 occurrences)
- **4 files** to rename
- **10 name variants** to replace (see research.md)

## Constraints

- **ONLY name changes.** Zero logic, formatting, structure, or behavior changes.
- No lines added or removed (except where line length changes from the name swap).
- No reordering, no whitespace changes, no comment edits beyond the name itself.
- This ticket WILL BE REJECTED if anything other than name substitutions is present in the diff.

## Acceptance Criteria

1. `grep -ri 'sync.shuttle' .` returns zero matches (excluding this ticket folder)
2. `grep -ri 'sync_shuttle' .` returns zero matches (excluding this ticket folder)
3. `grep -ri 'syncshuttle' .` returns zero matches (excluding this ticket folder)
4. `grep -r 'sync_tui' .` returns zero matches (excluding this ticket folder)
5. File `bucketcast.sh` exists; `sync-shuttle.sh` does not
6. File `config/bucketcast.conf.example` exists; `config/sync-shuttle.conf.example` does not
7. File `config/.bucketcastrc.example` exists; `config/.syncshuttlerc.example` does not
8. File `tui/bucketcast_tui.py` exists; `tui/sync_tui.py` does not
9. New name "bucketcast" appears in expected locations (README title, main script, etc.)
10. `git diff main` shows ONLY name substitutions and file renames - no other changes
11. `test.sh` passes all checks

## Files

- `research.md` - Full inventory of all rename targets
- `implementation_plan.md` - Step-by-step execution plan
- `test.sh` - Automated verification script
- `work_log.md` - Progress log
