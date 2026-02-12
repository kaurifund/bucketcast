# Implementation Plan Part 2: Relay Fixes & Enhancements

**Ticket:** 20260107_multi_server_relay
**Status:** Awaiting Approval
**Created:** 2026-01-07
**Depends On:** Audit findings from AUDIT_REPORT.md

---

## Context

This plan addresses issues found during the code audit. Some fixes depend on the merge of the `outbox_inbox_symmetry` branch which introduces `GLOBAL_MODE`, `--global`, and the `share` command.

---

## Task Overview

| # | Task | Status | Blocking | Depends On |
|---|------|--------|----------|------------|
| P2-1 | Fix performance: move config loading outside loop | N/A | Re-evaluated | Already correct in batch impl |
| P2-2 | Fix performance: batch staging directory | [x] | High | - |
| P2-3 | Fix dry-run logic bug | [x] | Critical | - |
| P2-4 | Support multiple -S flags (SOURCE_PATHS array) | [x] | Medium | - |
| P2-5 | Add --global flag support for relay | [x] | High | With rebase notes |
| P2-6 | Update documentation for --global | [x] | Low | P2-5 |
| P2-7 | Add missing test scenarios | [x] | Medium | P2-1 to P2-5 |
| P2-8 | Update IMPLEMENTATION_PLAN.md task statuses | [x] | Low | All |

---

$---

## Task P2-1: Fix Performance - Move Config Loading Outside Loop

### Priority: CRITICAL

### Problem

`get_server_config()` is called inside the file loop, causing a Python subprocess spawn for EVERY file:

```bash
# sync-shuttle.sh:1192-1227
for file in "${files_to_relay[@]}"; do
    # ...
    local to_config
    to_config=$(get_server_config "$TO_SERVER")  # EXPENSIVE! Called N times
    eval "$to_config"
```

### Fix

Move config loading BEFORE the loop:

**Location:** `sync-shuttle.sh` action_relay() around line 1175

**Current Code (lines 1175-1191):**
```bash
    # Phase 3: Push to destination server
    log_header "Phase 3: Pushing to ${TO_SERVER}"

    # Load destination server config
    local to_config
    to_config=$(get_server_config "$TO_SERVER")
    eval "$to_config"

    # Validate remote_base
    if ! validate_remote_base "$server_remote_base" "$TO_SERVER"; then
        log_error "Invalid remote_base for $TO_SERVER"
        exit 4
    fi

    local push_count=0
    local push_failed=0

    for file in "${files_to_relay[@]}"; do
```

**This part is already outside the loop - the issue is the staging directory creation inside the loop.**

Wait, let me re-read... Actually the config loading IS outside the loop at line 1178-1181. The issue is:
1. Staging dir created per file (line 1202)
2. File copied to staging (line 1206)
3. Sync to remote (line 1213)
4. Staging deleted (line 1225)

This should be batched.

### Actual Fix Required

The config loading is fine. The real issue is **staging per file**. This will be addressed in P2-2.

**Status:** Re-evaluated - config loading is already outside loop. Mark as N/A.

### Verification

- N/A - Issue was misidentified in audit

$---

## Task P2-2: Fix Performance - Batch Staging Directory

### Priority: HIGH

### Problem

Currently, for each file:
1. Create staging dir
2. Copy file to staging
3. Sync to remote
4. Delete staging dir

This means N rsync operations for N files.

**Current Code (lines 1200-1226):**
```bash
for file in "${files_to_relay[@]}"; do
    # ...
    if [[ "$DRY_RUN" == "true" ]]; then
        # ...
    else
        # Create staging directory
        local staging_dir="${REMOTE_DIR}/${TO_SERVER}/relay-${OPERATION_UUID}"
        mkdir -p "$staging_dir"

        # Copy file to staging
        cp -r "$file" "$staging_dir/"

        # Sync to remote
        if sync_to_remote "$TO_SERVER" "$staging_dir"; then
            ((push_count++))
            log_success "Relayed: $filename"
        else
            ((push_failed++))
            log_error "Failed to relay: $filename"
        fi

        # Cleanup staging
        rm -rf "$staging_dir"
    fi
done
```

### Fix

Batch all files into staging first, then sync once:

```bash
    # Phase 3: Push to destination server
    log_header "Phase 3: Pushing to ${TO_SERVER}"

    # Load destination server config (already done above)

    local push_count=0
    local push_failed=0

    if [[ "$DRY_RUN" == "true" ]]; then
        # Dry-run: just report what would happen
        for file in "${files_to_relay[@]}"; do
            local filename
            filename=$(basename "$file")
            log_info "[DRY-RUN] Would push: $filename -> ${TO_SERVER}"
            ((push_count++))
        done
    else
        # Create single staging directory for all files
        local staging_dir="${REMOTE_DIR}/${TO_SERVER}/relay-${OPERATION_UUID}"
        mkdir -p "$staging_dir"

        # Copy ALL files to staging
        for file in "${files_to_relay[@]}"; do
            local filename
            filename=$(basename "$file")
            log_info "Staging: $filename"
            cp -r "$file" "$staging_dir/"
        done

        # Single sync operation for all files
        log_info "Syncing ${file_count} file(s) to ${TO_SERVER}..."

        local original_server_id="$SERVER_ID"
        SERVER_ID="$TO_SERVER"

        if sync_to_remote "$TO_SERVER" "$staging_dir"; then
            push_count=$file_count
            log_success "Relayed ${push_count} file(s)"
        else
            push_failed=$file_count
            log_error "Failed to relay files"
        fi

        SERVER_ID="$original_server_id"

        # Cleanup staging
        rm -rf "$staging_dir"
    fi
```

### Files Affected

- `sync-shuttle.sh` (lines 1189-1227 approximately)

### Verification Steps

1. Relay multiple files - should see single rsync operation
2. Check logs - single sync message instead of per-file
3. Verify all files arrive at destination

### Rollback

Revert to per-file staging if batching causes issues.

$---

## Task P2-3: Fix Dry-Run Logic Bug

### Priority: CRITICAL

### Problem

In dry-run mode:
1. `perform_rsync_pull` is called with `--dry-run` flag
2. Files are NOT actually pulled to inbox
3. Then we try to find files in inbox (lines 1157-1164)
4. `file_count` will be 0 because nothing was actually pulled
5. User sees "No files to relay" even when files exist on source

**Current Code (lines 1135-1170):**
```bash
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would pull from: ${FROM_SERVER}"
        perform_rsync_pull "$FROM_SERVER" "$inbox_dir" "--dry-run"
    else
        perform_rsync_pull "$FROM_SERVER" "$inbox_dir" ""
    fi

    # Phase 2: Determine files to relay
    log_header "Phase 2: Identifying files to relay"

    local files_to_relay=()
    local file_count=0

    if [[ -n "$SOURCE_PATH" ]]; then
        # ... check for specific file
    else
        # All files from inbox
        if [[ -d "$inbox_dir" ]]; then
            while IFS= read -r -d '' file; do
                files_to_relay+=("$file")
                ((file_count++))
            done < <(find "$inbox_dir" -type f -print0 2>/dev/null)
        fi
    fi

    if [[ $file_count -eq 0 ]]; then
        log_warn "No files to relay from ${FROM_SERVER}"  # WRONG in dry-run!
```

### Fix

In dry-run mode, parse rsync output to show what WOULD be transferred:

```bash
    # Phase 1: Pull from source server
    log_header "Phase 1: Pulling from ${FROM_SERVER}"

    local inbox_dir="${INBOX_DIR}/${FROM_SERVER}"
    mkdir -p "$inbox_dir"

    local pull_output=""
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would pull from: ${FROM_SERVER}"
        # Capture dry-run output to parse file list
        pull_output=$(perform_rsync_pull "$FROM_SERVER" "$inbox_dir" "--dry-run" 2>&1)
        echo "$pull_output" | grep -E "^[^/].*[^/]$" | while read -r line; do
            log_info "  Would pull: $line"
        done
    else
        perform_rsync_pull "$FROM_SERVER" "$inbox_dir" ""
    fi

    # Phase 2: Determine files to relay
    log_header "Phase 2: Identifying files to relay"

    local files_to_relay=()
    local file_count=0

    if [[ "$DRY_RUN" == "true" ]]; then
        # In dry-run, we can't find actual files - parse from rsync output
        # or check what's ALREADY in inbox from previous pulls
        if [[ -d "$inbox_dir" ]]; then
            while IFS= read -r -d '' file; do
                files_to_relay+=("$file")
                ((file_count++))
            done < <(find "$inbox_dir" -type f -print0 2>/dev/null)
        fi

        if [[ $file_count -eq 0 ]]; then
            log_info "[DRY-RUN] No files currently in inbox. Files would be pulled then relayed."
            log_info "[DRY-RUN] Run without --dry-run to see actual file count."
            # Don't warn/error - this is expected in dry-run
            return 0
        fi
    else
        # ... existing logic for actual run
```

### Alternative Simpler Fix

Just change the message in dry-run mode:

```bash
    if [[ $file_count -eq 0 ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] No files in local inbox yet."
            log_info "[DRY-RUN] Files would be pulled from ${FROM_SERVER} then relayed to ${TO_SERVER}."
            log_info "[DRY-RUN] Run without --dry-run to execute."
        else
            log_warn "No files to relay from ${FROM_SERVER}"
            log_info "Hint: Ensure files are shared in outbox/global/ or outbox/${HOSTNAME}/ on ${FROM_SERVER}"
        fi
        return 0
    fi
```

### Files Affected

- `sync-shuttle.sh` (lines 1135-1171 approximately)

### Verification Steps

1. Run `relay --from a --to b --dry-run` with empty inbox
2. Should show informative message, not error
3. Run actual relay, then dry-run again - should show files

### Rollback

Revert message changes.

$---

## Task P2-4: Support Multiple -S Flags

### Priority: MEDIUM

### Problem

`-S` flag only supports one file because `SOURCE_PATH` is a string:

```bash
# sync-shuttle.sh:341
SOURCE_PATH=""

# sync-shuttle.sh:538-545
-S|--source)
    SOURCE_PATH="${2:-}"  # Overwrites previous value!
```

User expects:
```bash
sync-shuttle relay --from a --to b -S file1.txt -S file2.txt
```

### Fix

Convert to array:

**Step 1: Change variable declaration (line 341)**
```bash
# Before:
SOURCE_PATH=""

# After:
SOURCE_PATHS=()
```

**Step 2: Change argument parsing (lines 538-545)**
```bash
# Before:
-S|--source)
    SOURCE_PATH="${2:-}"
    if [[ -z "$SOURCE_PATH" ]]; then
        log_error "--source requires an argument"
        exit 2
    fi
    SOURCE_PATH="${SOURCE_PATH%/}"
    shift 2
    ;;

# After:
-S|--source)
    local src_path="${2:-}"
    if [[ -z "$src_path" ]]; then
        log_error "--source requires an argument"
        exit 2
    fi
    src_path="${src_path%/}"
    SOURCE_PATHS+=("$src_path")
    shift 2
    ;;
```

**Step 3: Update action_push to handle array (multiple places)**

This requires changes to action_push() as well. For now, maintain backward compatibility:

```bash
# At start of action_push:
if [[ ${#SOURCE_PATHS[@]} -eq 0 && -n "$SOURCE_PATH" ]]; then
    # Legacy single path support
    SOURCE_PATHS=("$SOURCE_PATH")
fi
```

**Step 4: Update action_relay file selection (lines 1148-1156)**
```bash
# Before:
if [[ -n "$SOURCE_PATH" ]]; then
    local target_file="${inbox_dir}/$(basename "$SOURCE_PATH")"
    if [[ -e "$target_file" ]]; then
        files_to_relay+=("$target_file")
        ((file_count++))
    else
        log_warn "Requested file not found in inbox: $SOURCE_PATH"
    fi

# After:
if [[ ${#SOURCE_PATHS[@]} -gt 0 ]]; then
    for src in "${SOURCE_PATHS[@]}"; do
        local target_file="${inbox_dir}/$(basename "$src")"
        if [[ -e "$target_file" ]]; then
            files_to_relay+=("$target_file")
            ((file_count++))
        else
            log_warn "Requested file not found in inbox: $src"
        fi
    done
```

### Files Affected

- `sync-shuttle.sh` (lines 341, 538-545, 976-984, 1148-1156)

### Verification Steps

1. `relay --from a --to b -S file1.txt -S file2.txt` - both files relayed
2. `push -s server -S file1.txt -S file2.txt` - both files pushed
3. Existing single -S usage still works

### Rollback

Keep SOURCE_PATH as fallback for compatibility.

$---

## Task P2-5: Add --global Flag Support for Relay

### Priority: HIGH
### ⚠️ DEPENDS ON: REBASE from `outbox_inbox_symmetry` branch

This task CANNOT be completed until the `outbox_inbox_symmetry` branch is merged, which introduces:
- `GLOBAL_MODE` variable
- `--global` flag parsing
- `share` command with global/per-server outbox

### Problem

User wants:
```bash
sync-shuttle relay --from a --to b --global
```

To only relay files from `outbox/global/` and not `outbox/<hostname>/`.

### Pre-Rebase Preparation

Add placeholder comment in action_relay():

```bash
    # Phase 1: Pull from source server
    log_header "Phase 1: Pulling from ${FROM_SERVER}"

    local inbox_dir="${INBOX_DIR}/${FROM_SERVER}"
    mkdir -p "$inbox_dir"

    # TODO(P2-5): After rebase from outbox_inbox_symmetry, add:
    # if [[ "$GLOBAL_MODE" == "true" ]]; then
    #     # Only pull from global outbox
    #     perform_rsync_pull "$FROM_SERVER" "$inbox_dir" "" "--global-only"
    # else
    #     perform_rsync_pull "$FROM_SERVER" "$inbox_dir" ""
    # fi
```

### Post-Rebase Implementation

After rebase, implement:

1. **Update perform_rsync_pull to support --global-only**

   In `lib/transfer.sh`, modify remote source path:
   ```bash
   if [[ "$4" == "--global-only" ]]; then
       local remote_src="${server_user}@${server_host}:${server_remote_base}/local/outbox/global/"
   else
       local remote_src="${server_user}@${server_host}:${server_remote_base}/local/outbox/"
   fi
   ```

2. **Update action_relay to pass flag**

   ```bash
   if [[ "$DRY_RUN" == "true" ]]; then
       if [[ "$GLOBAL_MODE" == "true" ]]; then
           log_info "[DRY-RUN] Would pull GLOBAL files only from: ${FROM_SERVER}"
           perform_rsync_pull "$FROM_SERVER" "$inbox_dir" "--dry-run" "--global-only"
       else
           log_info "[DRY-RUN] Would pull from: ${FROM_SERVER}"
           perform_rsync_pull "$FROM_SERVER" "$inbox_dir" "--dry-run"
       fi
   else
       if [[ "$GLOBAL_MODE" == "true" ]]; then
           perform_rsync_pull "$FROM_SERVER" "$inbox_dir" "" "--global-only"
       else
           perform_rsync_pull "$FROM_SERVER" "$inbox_dir" ""
       fi
   fi
   ```

3. **Update help text**

   Add to show_usage() relay examples:
   ```bash
   # Relay only global shared files
   $SCRIPT_NAME relay --from serverA --to serverB --global
   ```

### Files Affected (Post-Rebase)

- `sync-shuttle.sh` (action_relay, show_usage)
- `lib/transfer.sh` (perform_rsync_pull)

### Verification Steps

1. Share file with `--global` on server A
2. Share file without `--global` on server A
3. `relay --from a --to b --global` - only global file relayed
4. `relay --from a --to b` - both files relayed

### Rollback

Remove --global handling, revert to all-files behavior.

$---

## Task P2-6: Update Documentation for --global

### Priority: LOW
### DEPENDS ON: P2-5

### Changes Required

**SPECIFICATION.md:**
Add to Multi-Server Relay section:
```markdown
- `--global` flag to relay only globally shared files
```

**README.md:**
Add to relay examples:
```markdown
# Relay only globally shared files
sync-shuttle relay --from serverA --to serverB --global
```

**show_usage() in sync-shuttle.sh:**
Already covered in P2-5.

### Files Affected

- `SPECIFICATION.md`
- `README.md`

$---

## Task P2-7: Add Missing Test Scenarios

### Priority: MEDIUM
### DEPENDS ON: P2-1 through P2-5

### Missing Unit Tests

Add to `tests/unit/test_validation.sh`:

```bash
test_validate_relay_params_accepts_valid_servers() {
    # Need mock for get_server_config
    # Test that valid server IDs pass
}
```

### Missing Integration Tests

Add to `tests/integration/test_relay.sh`:

```bash
test_relay_dry_run_empty_inbox_message() {
    setup_relay_test

    # Empty inbox, dry-run should show informative message
    export DRY_RUN="true"
    # ... test that message is informative, not error
}

test_relay_multiple_files_batched() {
    setup_relay_test

    # Create multiple files
    # Verify single rsync operation
}

test_relay_multiple_S_flags() {
    setup_relay_test

    # Create files
    # Run with -S file1.txt -S file2.txt
    # Verify both relayed
}

# POST-REBASE:
test_relay_global_only() {
    setup_relay_test

    # Create global and non-global files
    # Relay with --global
    # Verify only global relayed
}
```

### Files Affected

- `tests/unit/test_validation.sh`
- `tests/integration/test_relay.sh`

$---

## Task P2-8: Update Implementation Plan Status

### Priority: LOW

Update `IMPLEMENTATION_PLAN.md` Task Overview table with accurate status:

```markdown
| # | Task | Status | Notes |
|---|------|--------|-------|
| 1-12 | Original tasks | [x] | Completed with issues |
| P2-1 | Config loading fix | [x] | Re-evaluated: not needed |
| P2-2 | Batch staging | [ ] | Performance fix |
| P2-3 | Dry-run fix | [ ] | Critical bug fix |
| P2-4 | Multiple -S | [ ] | Feature enhancement |
| P2-5 | --global support | [ ] | BLOCKED: awaiting rebase |
| P2-6 | --global docs | [ ] | BLOCKED: depends on P2-5 |
| P2-7 | Test scenarios | [ ] | After P2-2 to P2-5 |
| P2-8 | Update status | [ ] | This task |
```

Also update `work_log.md` with Part 2 progress.

---

## Execution Order

```
Phase 1: Critical Fixes (No Dependencies)
├── P2-2: Batch staging directory
└── P2-3: Fix dry-run logic

Phase 2: Enhancements (No Dependencies)
└── P2-4: Multiple -S support

Phase 3: Post-Rebase (After outbox_inbox_symmetry merge)
├── P2-5: --global flag support
└── P2-6: Documentation update

Phase 4: Cleanup
├── P2-7: Add test scenarios
└── P2-8: Update status
```

---

## Rebase Integration Notes

When rebasing from `outbox_inbox_symmetry`:

1. **Expect conflicts in:**
   - `sync-shuttle.sh` (runtime variables section)
   - `sync-shuttle.sh` (argument parsing section)
   - Possibly `lib/validation.sh`

2. **Variables to merge:**
   - `GLOBAL_MODE` (from other branch)
   - `FROM_SERVER`, `TO_SERVER` (from this branch)

3. **Commands to merge:**
   - `share` (from other branch)
   - `relay` (from this branch)

4. **After rebase, immediately:**
   - Implement P2-5 (--global for relay)
   - Run full test suite
   - Verify both share and relay work together

---

## Approval Workflow

Same as Part 1:
1. Implement change
2. Verify with tests
3. Report completion
4. **Wait for approval**
5. Update work_log.md
6. Proceed to next task
