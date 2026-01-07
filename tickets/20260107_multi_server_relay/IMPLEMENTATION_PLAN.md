# Implementation Plan: Multi-Server Relay

**Ticket:** 20260107_multi_server_relay
**Status:** Awaiting Approval
**Created:** 2026-01-07

---

## Git Strategy

**Branch:** `feature/multi-server-relay`
**Base:** `main` (after any pending PRs are merged)

---

## Task Overview

| # | Task | Status | Complexity | Est. Lines |
|---|------|--------|------------|-----------|
| 1 | Add runtime variables for relay (`FROM_SERVER`, `TO_SERVER`) | [ ] | Low | ~10 |
| 2 | Add `--from` and `--to` argument parsing | [ ] | Low | ~25 |
| 3 | Add `relay` to command parser and dispatcher | [ ] | Low | ~15 |
| 4 | Update `show_usage()` with relay command documentation | [ ] | Low | ~20 |
| 5 | Add `validate_relay_params()` in lib/validation.sh | [ ] | Medium | ~40 |
| 6 | Add `preflight_relay()` in lib/validation.sh | [ ] | Medium | ~30 |
| 7 | Implement `action_relay()` main function | [ ] | High | ~120 |
| 8 | Add relay operation logging support | [ ] | Low | ~15 |
| 9 | Update documentation (SPECIFICATION.md, README.md) | [ ] | Low | ~40 |
| 10 | Add unit tests for relay validation | [ ] | Medium | ~60 |
| 11 | Add integration tests for relay operation | [ ] | Medium | ~80 |
| 12 | Verify end-to-end relay workflow | [ ] | High | ~40 |

---

$---

## Task 1: Add Runtime Variables for Relay

### Description

Add new runtime variables to track source and destination servers for relay operations.

### Current Code (sync-shuttle.sh:339-351)

```bash
#===============================================================================
# RUNTIME VARIABLES (set by argument parsing)
#===============================================================================
ACTION=""
SERVER_ID=""
SOURCE_PATH=""
DRY_RUN="false"
FORCE="false"
VERBOSE="false"
QUIET="false"
S3_ARCHIVE="false"
GLOBAL_MODE="false"
LIST_MODE="false"
REMOVE_MODE="false"
OPERATION_UUID=""
CONFIG_ARGS=()
```

### Proposed Change

Add after line 351 (after `CONFIG_ARGS=()`):

```bash
# Relay-specific variables
FROM_SERVER=""
TO_SERVER=""
```

### Files Affected

- `sync-shuttle.sh` (lines 339-352)

### Verification Steps

1. Run `bash -n sync-shuttle.sh` - syntax check passes
2. Variables are accessible in functions
3. No conflict with existing variables

### Rollback

Remove the two added lines.

$---

## Task 2: Add `--from` and `--to` Argument Parsing

### Description

Add argument parsing for `--from`/`-F` and `--to`/`-T` flags to specify source and destination servers for relay.

### Current Code (sync-shuttle.sh:532-600)

The argument parsing `while` loop handles options like `-s`, `-S`, `--dry-run`, etc.

### Proposed Change

Add after line 586 (after `--remove` handling):

```bash
            -F|--from)
                FROM_SERVER="${2:-}"
                if [[ -z "$FROM_SERVER" ]]; then
                    log_error "--from requires a server ID argument"
                    exit 2
                fi
                shift 2
                ;;
            -T|--to)
                TO_SERVER="${2:-}"
                if [[ -z "$TO_SERVER" ]]; then
                    log_error "--to requires a server ID argument"
                    exit 2
                fi
                shift 2
                ;;
```

### Why These Short Flags?

- `-F` for "from" (source)
- `-T` for "to" (target/destination)
- Avoids conflict with existing `-f` (force) and `-s` (server)

### Files Affected

- `sync-shuttle.sh` (lines 532-600)

### Verification Steps

1. Run `sync-shuttle relay --from a --to b` - parses correctly
2. Run `sync-shuttle relay -F a -T b` - short form works
3. Missing argument shows proper error
4. Works with other flags like `--dry-run`

### Rollback

Remove the added case blocks.

$---

## Task 3: Add `relay` to Command Parser and Dispatcher

### Description

Register `relay` as a valid command and route it to the action handler.

### Current Code - Command Parser (sync-shuttle.sh:503-517)

```bash
    case "${1:-}" in
        init|push|pull|list|status|config|share|tui|help|--help|-h)
            ACTION="${1}"
            shift
            ;;
```

### Proposed Change - Command Parser

Update line 504:

```bash
        init|push|pull|list|status|config|share|relay|tui|help|--help|-h)
```

### Current Code - Dispatcher (sync-shuttle.sh:778-811)

```bash
dispatch_action() {
    case "$ACTION" in
        init)
            action_init
            ;;
        push)
            validate_server_required
            action_push
            ;;
        # ... etc
    esac
}
```

### Proposed Change - Dispatcher

Add after `share` case (around line 803):

```bash
        relay)
            validate_relay_servers_required
            action_relay
            ;;
```

Also add helper function before `dispatch_action()`:

```bash
validate_relay_servers_required() {
    if [[ -z "$FROM_SERVER" ]]; then
        log_error "Source server is required for relay operation"
        echo "Use: $SCRIPT_NAME relay --from <server_id> --to <server_id>"
        exit 2
    fi
    if [[ -z "$TO_SERVER" ]]; then
        log_error "Destination server is required for relay operation"
        echo "Use: $SCRIPT_NAME relay --from <server_id> --to <server_id>"
        exit 2
    fi
    if [[ "$FROM_SERVER" == "$TO_SERVER" ]]; then
        log_error "Source and destination servers cannot be the same"
        exit 2
    fi
}
```

### Files Affected

- `sync-shuttle.sh` (lines 503-517, 778-811)

### Verification Steps

1. Run `sync-shuttle relay --from a --to b` - dispatches correctly
2. Run `sync-shuttle relay` without args - shows proper error
3. Run `sync-shuttle relay --from a` - shows missing --to error
4. Run `sync-shuttle relay --from a --to a` - shows same-server error

### Rollback

Remove `relay` from case statement and dispatcher.

$---

## Task 4: Update `show_usage()` with Relay Documentation

### Description

Add relay command documentation to the help output.

### Current Code (sync-shuttle.sh:425-434)

```bash
${BOLD}COMMANDS:${RESET}
    init                    Initialize sync-shuttle directory structure
    push                    Push files TO a remote server
    pull                    Pull files FROM a remote server
    share                   Share files via outbox (for others to pull)
    list <servers|files>    List servers or files in a server's directory
    status                  Show sync status and recent operations
    config <subcommand>     Manage server configuration
    tui                     Launch interactive terminal UI
```

### Proposed Change

Add after `share` line (line 429):

```bash
    relay                   Relay files between servers (via local)
```

Also update OPTIONS section (after line 451):

```bash
    -F, --from <id>         Source server for relay
    -T, --to <id>           Destination server for relay
```

Also update EXAMPLES section (after line 477):

```bash
    # Relay files from server A to server B
    $SCRIPT_NAME relay --from serverA --to serverB --dry-run
    $SCRIPT_NAME relay --from serverA --to serverB

    # Relay specific files only
    $SCRIPT_NAME relay --from serverA --to serverB -S myfile.txt
```

### Files Affected

- `sync-shuttle.sh` (lines 418-486)

### Verification Steps

1. Run `sync-shuttle --help` - shows relay command
2. Shows `--from` and `--to` options
3. Shows relay examples
4. Formatting is consistent with other commands

### Rollback

Remove added lines from show_usage().

$---

## Task 5: Add `validate_relay_params()` in lib/validation.sh

### Description

Add comprehensive validation for relay parameters including server existence and accessibility.

### Current Code Pattern (lib/validation.sh:202-232)

```bash
validate_server_id() {
    local server_id="$1"
    # ... validation logic
}
```

### Proposed Change

Add after `preflight_pull()` (around line 463):

```bash
#===============================================================================
# VALIDATE: Relay parameters
#===============================================================================
validate_relay_params() {
    local from_server="$1"
    local to_server="$2"

    log_debug "Validating relay parameters..."

    # Validate from_server ID format
    if ! validate_server_id "$from_server"; then
        log_error "Invalid source server ID: $from_server"
        return 1
    fi

    # Validate to_server ID format
    if ! validate_server_id "$to_server"; then
        log_error "Invalid destination server ID: $to_server"
        return 1
    fi

    # Check both servers exist in config
    local from_config
    if ! from_config=$(get_server_config "$from_server" 2>/dev/null); then
        log_error "Source server not found or disabled: $from_server"
        return 1
    fi

    local to_config
    if ! to_config=$(get_server_config "$to_server" 2>/dev/null); then
        log_error "Destination server not found or disabled: $to_server"
        return 1
    fi

    # Verify both servers are reachable (optional, can be skipped with --skip-check)
    # This is done in preflight_relay() instead

    log_debug "Relay parameters validated: $from_server -> $to_server"
    return 0
}
```

### Files Affected

- `lib/validation.sh` (add after line 463)

### Verification Steps

1. Valid servers pass validation
2. Invalid server ID format fails
3. Non-existent server fails
4. Disabled server fails
5. Error messages are clear

### Rollback

Remove `validate_relay_params()` function.

$---

## Task 6: Add `preflight_relay()` in lib/validation.sh

### Description

Add preflight checks specific to relay operations - validates both servers are accessible.

### Current Code Pattern (lib/validation.sh:423-463)

```bash
preflight_push() {
    local source="$1"
    local dest="$2"
    # ... checks
}

preflight_pull() {
    local dest="$1"
    # ... checks
}
```

### Proposed Change

Add after `validate_relay_params()`:

```bash
#===============================================================================
# PREFLIGHT: Relay operation checks
#===============================================================================
preflight_relay() {
    local from_server="$1"
    local to_server="$2"

    log_debug "Running preflight checks for relay..."

    # Validate relay parameters first
    if ! validate_relay_params "$from_server" "$to_server"; then
        return 1
    fi

    # Load and check FROM server config
    local from_config
    from_config=$(get_server_config "$from_server")
    eval "$from_config"
    local from_host="$server_host"
    local from_port="$server_port"
    local from_user="$server_user"

    # Build SSH options for from_server
    local from_ssh_opts="-p ${from_port} -o StrictHostKeyChecking=accept-new -o ConnectTimeout=${SSH_CONNECT_TIMEOUT:-10}"
    if [[ -n "${server_identity_file:-}" ]]; then
        local expanded_key="${server_identity_file/#\~/$HOME}"
        if [[ -f "$expanded_key" ]]; then
            from_ssh_opts+=" -i ${expanded_key}"
        fi
    fi

    # Validate SSH to from_server
    if ! validate_ssh_connection "$from_host" "$from_port" "$from_user" "$from_ssh_opts"; then
        log_error "Cannot connect to source server: $from_server"
        return 1
    fi

    # Load and check TO server config (reset server_* vars)
    local to_config
    to_config=$(get_server_config "$to_server")
    eval "$to_config"

    # Build SSH options for to_server
    local to_ssh_opts="-p ${server_port} -o StrictHostKeyChecking=accept-new -o ConnectTimeout=${SSH_CONNECT_TIMEOUT:-10}"
    if [[ -n "${server_identity_file:-}" ]]; then
        local expanded_key="${server_identity_file/#\~/$HOME}"
        if [[ -f "$expanded_key" ]]; then
            to_ssh_opts+=" -i ${expanded_key}"
        fi
    fi

    # Validate SSH to to_server
    if ! validate_ssh_connection "$server_host" "$server_port" "$server_user" "$to_ssh_opts"; then
        log_error "Cannot connect to destination server: $to_server"
        return 1
    fi

    log_debug "Preflight checks passed for relay: $from_server -> $to_server"
    return 0
}
```

### Files Affected

- `lib/validation.sh` (add after `validate_relay_params()`)

### Verification Steps

1. Both servers reachable - passes
2. From server unreachable - fails with clear error
3. To server unreachable - fails with clear error
4. Works with identity files
5. Respects SSH timeout

### Rollback

Remove `preflight_relay()` function.

$---

## Task 7: Implement `action_relay()` Main Function

### Description

Implement the core relay action that pulls from source server and pushes to destination server.

### Current Code Pattern (sync-shuttle.sh:985-1068 for push, 1073-1127 for pull)

Both `action_push()` and `action_pull()` follow this pattern:
1. Generate UUID
2. Record start timestamp
3. Load server config
4. Validate paths
5. Perform transfer
6. Log operation
7. Report success

### Proposed Change

Add after `action_share()` (around line 1262):

```bash
#===============================================================================
# ACTION: RELAY
# Forward files from one server to another via local
#===============================================================================
action_relay() {
    OPERATION_UUID=$(generate_uuid)
    local timestamp_start
    timestamp_start=$(get_iso_timestamp)

    log_info "Starting RELAY operation [${OPERATION_UUID}]"
    log_info "From: ${FROM_SERVER} -> To: ${TO_SERVER}"

    # Run preflight checks for both servers
    if ! preflight_relay "$FROM_SERVER" "$TO_SERVER"; then
        log_error "Preflight checks failed for relay"
        exit 4
    fi

    # Phase 1: Pull from source server
    log_header "Phase 1: Pulling from ${FROM_SERVER}"

    local inbox_dir="${INBOX_DIR}/${FROM_SERVER}"
    mkdir -p "$inbox_dir"

    # Temporarily set SERVER_ID for pull operation
    local original_server_id="$SERVER_ID"
    SERVER_ID="$FROM_SERVER"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would pull from: ${FROM_SERVER}"
        perform_rsync_pull "$FROM_SERVER" "$inbox_dir" "--dry-run"
    else
        perform_rsync_pull "$FROM_SERVER" "$inbox_dir" ""
    fi

    # Phase 2: Determine files to push
    log_header "Phase 2: Identifying files to relay"

    local files_to_relay=()
    local file_count=0

    if [[ -n "$SOURCE_PATH" ]]; then
        # Specific file(s) requested
        local target_file="${inbox_dir}/$(basename "$SOURCE_PATH")"
        if [[ -e "$target_file" ]]; then
            files_to_relay+=("$target_file")
            ((file_count++))
        else
            log_warn "Requested file not found in inbox: $SOURCE_PATH"
        fi
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
        log_warn "No files to relay from ${FROM_SERVER}"
        log_info "Hint: Ensure files are shared in outbox/global/ or outbox/${HOSTNAME}/ on ${FROM_SERVER}"
        SERVER_ID="$original_server_id"
        return 0
    fi

    log_info "Found $file_count file(s) to relay"

    # Phase 3: Push to destination server
    log_header "Phase 3: Pushing to ${TO_SERVER}"

    SERVER_ID="$TO_SERVER"

    local push_count=0
    local push_failed=0

    for file in "${files_to_relay[@]}"; do
        local filename
        filename=$(basename "$file")
        log_info "Relaying: $filename"

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would push: $filename -> ${TO_SERVER}"
            ((push_count++))
        else
            # Use existing push mechanism
            local to_config
            to_config=$(get_server_config "$TO_SERVER")
            eval "$to_config"

            # Validate remote_base
            if ! validate_remote_base "$server_remote_base" "$TO_SERVER"; then
                log_error "Invalid remote_base for $TO_SERVER"
                ((push_failed++))
                continue
            fi

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

    # Restore original SERVER_ID
    SERVER_ID="$original_server_id"

    # Summary
    local timestamp_end
    timestamp_end=$(get_iso_timestamp)

    log_header "Relay Summary"
    log_info "Source:      ${FROM_SERVER}"
    log_info "Destination: ${TO_SERVER}"
    log_info "Files found: ${file_count}"
    log_info "Relayed:     ${push_count}"
    if [[ $push_failed -gt 0 ]]; then
        log_warn "Failed:      ${push_failed}"
    fi

    # Log the operation
    local status="SUCCESS"
    if [[ $push_failed -gt 0 && $push_count -eq 0 ]]; then
        status="FAILED"
    elif [[ $push_failed -gt 0 ]]; then
        status="PARTIAL"
    fi

    log_operation "$OPERATION_UUID" "relay" "${FROM_SERVER}->${TO_SERVER}" \
        "${inbox_dir}" "${TO_SERVER}" \
        "$timestamp_start" "$timestamp_end" "$status"

    if [[ "$status" == "FAILED" ]]; then
        log_error "Relay operation failed [${OPERATION_UUID}]"
        exit 5
    else
        log_success "Relay operation completed [${OPERATION_UUID}]"
    fi
}
```

### Files Affected

- `sync-shuttle.sh` (add after line 1262)

### Verification Steps

1. `relay --from a --to b --dry-run` - shows what would happen
2. `relay --from a --to b` - executes transfer
3. Files appear in destination's inbox
4. Single UUID tracks entire operation
5. Summary shows correct counts
6. Handles empty inbox gracefully
7. Handles missing files gracefully
8. Staging directories cleaned up

### Rollback

Remove `action_relay()` function.

$---

## Task 8: Add Relay Operation Logging Support

### Description

Ensure the log_operation function properly handles relay operations with dual-server context.

### Current Code (lib/logging.sh:142-167)

```bash
log_operation() {
    local uuid="$1"
    local operation="$2"
    local server_id="$3"
    # ...
}
```

### Proposed Change

The current implementation already supports arbitrary strings for `server_id`. For relay, we pass `"${FROM_SERVER}->${TO_SERVER}"` as the server_id, which provides clear audit trail.

Optionally, add a helper for consistent formatting:

```bash
#===============================================================================
# LOG: Format relay server identifier
#===============================================================================
format_relay_servers() {
    local from="$1"
    local to="$2"
    echo "${from}->${to}"
}
```

This is optional since the current logging already handles this.

### Files Affected

- `lib/logging.sh` (optional addition)

### Verification Steps

1. Run relay operation
2. Check `~/.sync-shuttle/logs/sync.jsonl`
3. Verify `server_id` field shows `"serverA->serverB"`
4. Verify `operation` field shows `"relay"`

### Rollback

Remove helper function if added.

$---

## Task 9: Update Documentation

### Description

Update SPECIFICATION.md and README.md with relay command documentation.

### SPECIFICATION.md Changes

Add to Core Features section (around line 36):

```markdown
### 7. Multi-Server Relay
- Relay files from one server to another via local
- Maintains hub-and-spoke model (servers don't need to know each other)
- Single command: `relay --from <source> --to <dest>`
- Supports dry-run and specific file selection
```

Update CLI Interface section (around line 55):

```markdown
- `--from <id>`: Source server for relay
- `--to <id>`: Destination server for relay
```

### README.md Changes

Add to Commands table (around line 100):

```markdown
| `relay` | Relay files between servers via local |
```

Add to Options table (around line 115):

```markdown
| `-F, --from <id>` | Source server for relay |
| `-T, --to <id>` | Destination server for relay |
```

Add to Examples section (around line 150):

```markdown
# Relay files from one server to another
sync-shuttle relay --from serverA --to serverB --dry-run
sync-shuttle relay --from serverA --to serverB

# Relay specific file only
sync-shuttle relay --from serverA --to serverB -S myfile.txt
```

### Files Affected

- `SPECIFICATION.md`
- `README.md`

### Verification Steps

1. Read updated docs - accurate and clear
2. Examples are correct syntax
3. No broken formatting
4. Consistent with existing style

### Rollback

Revert documentation changes.

$---

## Task 10: Add Unit Tests for Relay Validation

### Description

Add unit tests for `validate_relay_params()` and related validation functions.

### Current Test Pattern (tests/unit/test_validation.sh)

Tests follow this pattern:
```bash
test_validate_server_id_valid() {
    # Setup
    # Execute
    # Assert
}
```

### Proposed Tests

Add to `tests/unit/test_validation.sh`:

```bash
#===============================================================================
# Tests for relay validation
#===============================================================================

test_validate_relay_params_valid() {
    local result
    # Mock get_server_config to return success for "server-a" and "server-b"
    result=$(validate_relay_params "server-a" "server-b" 2>&1)
    assert_success $? "validate_relay_params should succeed for valid servers"
}

test_validate_relay_params_same_server() {
    # Same server should fail (handled in dispatcher, but test anyway)
    local result
    result=$(validate_relay_params "server-a" "server-a" 2>&1)
    # This test depends on implementation - may pass validation but fail in dispatcher
}

test_validate_relay_params_invalid_from() {
    local result
    result=$(validate_relay_params "invalid--server" "server-b" 2>&1)
    assert_failure $? "validate_relay_params should fail for invalid from server"
    assert_contains "$result" "Invalid" "Should mention invalid server"
}

test_validate_relay_params_invalid_to() {
    local result
    result=$(validate_relay_params "server-a" "global" 2>&1)
    assert_failure $? "validate_relay_params should fail for reserved name"
    assert_contains "$result" "reserved" "Should mention reserved"
}

test_validate_relay_params_nonexistent() {
    local result
    result=$(validate_relay_params "server-a" "nonexistent" 2>&1)
    assert_failure $? "validate_relay_params should fail for nonexistent server"
    assert_contains "$result" "not found" "Should mention not found"
}
```

### Files Affected

- `tests/unit/test_validation.sh`

### Verification Steps

1. Run `./tests/run_tests.sh` - all tests pass
2. New tests cover edge cases
3. Test output is clear

### Rollback

Remove added test functions.

$---

## Task 11: Add Integration Tests for Relay Operation

### Description

Add integration tests that test the full relay workflow with mocked servers.

### Proposed Tests

Create `tests/integration/test_relay.sh`:

```bash
#!/usr/bin/env bash
#===============================================================================
# Integration Tests: Relay Operation
#===============================================================================

source "$(dirname "$0")/../helpers/test_helpers.sh"
source "$(dirname "$0")/../helpers/fixtures.sh"
source "$(dirname "$0")/../helpers/mocks.sh"

setup() {
    create_test_environment
    create_mock_servers "server-a" "server-b"
}

teardown() {
    cleanup_test_environment
}

test_relay_dry_run() {
    setup

    # Create test file on mock server-a outbox
    create_mock_outbox_file "server-a" "global" "testfile.txt" "Hello from A"

    # Run relay dry-run
    local result
    result=$(sync-shuttle relay --from server-a --to server-b --dry-run 2>&1)

    assert_success $? "Relay dry-run should succeed"
    assert_contains "$result" "DRY-RUN" "Should show dry-run mode"
    assert_contains "$result" "testfile.txt" "Should list the file"

    # Verify file NOT actually transferred
    assert_file_not_exists "${INBOX_DIR}/server-a/testfile.txt"

    teardown
}

test_relay_basic() {
    setup

    # Create test file on mock server-a outbox
    create_mock_outbox_file "server-a" "global" "testfile.txt" "Hello from A"

    # Run relay
    local result
    result=$(sync-shuttle relay --from server-a --to server-b 2>&1)

    assert_success $? "Relay should succeed"
    assert_contains "$result" "Relay operation completed" "Should show success"

    # Verify file arrived at destination
    assert_file_exists "${TEST_INBOX}/server-b/testfile.txt"

    teardown
}

test_relay_specific_file() {
    setup

    # Create multiple files
    create_mock_outbox_file "server-a" "global" "file1.txt" "File 1"
    create_mock_outbox_file "server-a" "global" "file2.txt" "File 2"

    # Relay only file1
    local result
    result=$(sync-shuttle relay --from server-a --to server-b -S file1.txt 2>&1)

    assert_success $? "Relay should succeed"
    assert_contains "$result" "file1.txt" "Should mention file1"

    teardown
}

test_relay_empty_inbox() {
    setup

    # No files in outbox
    local result
    result=$(sync-shuttle relay --from server-a --to server-b 2>&1)

    assert_success $? "Relay should succeed even with no files"
    assert_contains "$result" "No files to relay" "Should indicate no files"

    teardown
}

test_relay_same_server_error() {
    setup

    local result
    result=$(sync-shuttle relay --from server-a --to server-a 2>&1)

    assert_failure $? "Relay to same server should fail"
    assert_contains "$result" "cannot be the same" "Should explain error"

    teardown
}

# Run all tests
run_tests
```

### Files Affected

- `tests/integration/test_relay.sh` (new file)
- `tests/helpers/fixtures.sh` (may need mock helpers)
- `tests/helpers/mocks.sh` (may need mock server helpers)

### Verification Steps

1. Run `./tests/run_tests.sh` - all tests pass
2. Integration tests use realistic scenarios
3. Mocks properly simulate server behavior

### Rollback

Remove `tests/integration/test_relay.sh`.

$---

## Task 12: Verify End-to-End Relay Workflow

### Description

Manual verification of the complete relay workflow with actual servers (or local test setup).

### Test Scenarios

1. **Basic Relay**
   ```bash
   # On server A
   echo "test content" > ~/testfile.txt
   sync-shuttle share --global -S ~/testfile.txt

   # On local
   sync-shuttle relay --from a --to b --dry-run
   sync-shuttle relay --from a --to b

   # On server B
   ls ~/.sync-shuttle/local/inbox/
   cat ~/.sync-shuttle/local/inbox/*/testfile.txt
   ```

2. **Multiple Files**
   ```bash
   # Create multiple files on A, relay all to B
   ```

3. **Specific File Selection**
   ```bash
   sync-shuttle relay --from a --to b -S specific-file.txt
   ```

4. **Error Handling**
   - Test with unreachable server
   - Test with invalid server ID
   - Test with same source/destination

### Verification Checklist

- [ ] Dry-run shows accurate preview
- [ ] Files transfer correctly
- [ ] Operation logged with correct UUID
- [ ] Error messages are clear
- [ ] Staging directories cleaned up
- [ ] Works with identity files
- [ ] Works with non-standard ports

### Files Affected

- None (manual testing)

### Rollback

N/A - manual testing only.

$---

## Execution Order

**Phase 1: Foundation (Tasks 1-4)**
- Add variables and argument parsing
- Register command
- Update help

**Phase 2: Validation (Tasks 5-6)**
- Add relay-specific validation
- Add preflight checks

**Phase 3: Core Implementation (Task 7)**
- Implement action_relay()
- This is the largest task

**Phase 4: Integration (Task 8)**
- Ensure logging works correctly

**Phase 5: Documentation & Testing (Tasks 9-12)**
- Update docs
- Add tests
- E2E verification

---

## Work Log

Track completed tasks in `work_log.md` in this directory.

---

## Approval Workflow

After each task:
1. Implement the change
2. Verify it works as specified
3. Report completion and verification results
4. **Wait for user approval** before proceeding to next task

Upon approval:
1. Update `work_log.md` with task completion
2. Mark task as `[x]` in the Task Overview table above
3. Proceed to next task
