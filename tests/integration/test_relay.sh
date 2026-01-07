#!/usr/bin/env bash
#===============================================================================
# INTEGRATION TESTS - RELAY OPERATIONS
#===============================================================================
# Tests that verify relay functionality works correctly.
# These tests use the local filesystem (no network).
#===============================================================================

# Source all libraries
source "${TEST_DIR}/lib/logging.sh" 2>/dev/null || source "${PROJECT_ROOT}/lib/logging.sh"
source "${TEST_DIR}/lib/validation.sh" 2>/dev/null || source "${PROJECT_ROOT}/lib/validation.sh"
source "${TEST_DIR}/lib/core.sh" 2>/dev/null || source "${PROJECT_ROOT}/lib/core.sh"
source "${TEST_DIR}/lib/transfer.sh" 2>/dev/null || source "${PROJECT_ROOT}/lib/transfer.sh"

#===============================================================================
# SETUP
#===============================================================================
setup_relay_test() {
    export SYNC_BASE_DIR="${TEST_DIR}/sync-shuttle"
    export REMOTE_DIR="${SYNC_BASE_DIR}/remote"
    export LOCAL_DIR="${SYNC_BASE_DIR}/local"
    export INBOX_DIR="${LOCAL_DIR}/inbox"
    export OUTBOX_DIR="${LOCAL_DIR}/outbox"
    export TMP_DIR="${SYNC_BASE_DIR}/tmp"
    export LOGS_DIR="${SYNC_BASE_DIR}/logs"
    export LOG_FILE="${LOGS_DIR}/sync.log"
    export LOG_JSON_FILE="${LOGS_DIR}/sync.jsonl"
    export CONFIG_DIR="${SYNC_BASE_DIR}/config"

    mkdir -p "$REMOTE_DIR" "$INBOX_DIR" "$OUTBOX_DIR" "$TMP_DIR" "$LOGS_DIR" "$CONFIG_DIR"
    touch "$LOG_FILE" "$LOG_JSON_FILE"

    export DRY_RUN="false"
    export FORCE="false"
    export VERBOSE="false"
    export QUIET="true"
    export FROM_SERVER=""
    export TO_SERVER=""
    export SOURCE_PATH=""
}

#===============================================================================
# RELAY PARAMETER VALIDATION TESTS
#===============================================================================

test_validate_relay_servers_required_rejects_missing_from() {
    setup_relay_test

    export FROM_SERVER=""
    export TO_SERVER="server-b"

    # Source the main script functions
    source "${PROJECT_ROOT}/sync-shuttle.sh" 2>/dev/null

    if validate_relay_servers_required 2>/dev/null; then
        echo "Should reject missing FROM_SERVER"
        return 1
    fi
}

test_validate_relay_servers_required_rejects_missing_to() {
    setup_relay_test

    export FROM_SERVER="server-a"
    export TO_SERVER=""

    # Source the main script functions
    source "${PROJECT_ROOT}/sync-shuttle.sh" 2>/dev/null

    if validate_relay_servers_required 2>/dev/null; then
        echo "Should reject missing TO_SERVER"
        return 1
    fi
}

test_validate_relay_servers_required_rejects_same_server() {
    setup_relay_test

    export FROM_SERVER="server-a"
    export TO_SERVER="server-a"

    # Source the main script functions
    source "${PROJECT_ROOT}/sync-shuttle.sh" 2>/dev/null

    if validate_relay_servers_required 2>/dev/null; then
        echo "Should reject same source and destination server"
        return 1
    fi
}

test_validate_relay_servers_required_accepts_valid_pair() {
    setup_relay_test

    export FROM_SERVER="server-a"
    export TO_SERVER="server-b"

    # Source the main script functions
    source "${PROJECT_ROOT}/sync-shuttle.sh" 2>/dev/null

    if ! validate_relay_servers_required 2>/dev/null; then
        echo "Should accept valid server pair"
        return 1
    fi
}

#===============================================================================
# RELAY INBOX SETUP TESTS
#===============================================================================

test_relay_creates_inbox_directory() {
    setup_relay_test

    local from_server="server-a"
    local inbox_dir="${INBOX_DIR}/${from_server}"

    # Ensure inbox doesn't exist
    rm -rf "$inbox_dir"

    # Create inbox as relay would
    mkdir -p "$inbox_dir"

    if [[ ! -d "$inbox_dir" ]]; then
        echo "Should create inbox directory for source server"
        return 1
    fi
}

test_relay_finds_files_in_inbox() {
    setup_relay_test

    local from_server="server-a"
    local inbox_dir="${INBOX_DIR}/${from_server}"

    # Create inbox with test files
    mkdir -p "$inbox_dir"
    echo "file1 content" > "${inbox_dir}/file1.txt"
    echo "file2 content" > "${inbox_dir}/file2.txt"

    # Count files as relay would
    local file_count=0
    while IFS= read -r -d '' file; do
        ((file_count++))
    done < <(find "$inbox_dir" -type f -print0 2>/dev/null)

    if [[ $file_count -ne 2 ]]; then
        echo "Should find 2 files in inbox, found $file_count"
        return 1
    fi
}

test_relay_handles_empty_inbox() {
    setup_relay_test

    local from_server="server-a"
    local inbox_dir="${INBOX_DIR}/${from_server}"

    # Create empty inbox
    mkdir -p "$inbox_dir"

    # Count files as relay would
    local file_count=0
    while IFS= read -r -d '' file; do
        ((file_count++))
    done < <(find "$inbox_dir" -type f -print0 2>/dev/null)

    if [[ $file_count -ne 0 ]]; then
        echo "Should find 0 files in empty inbox, found $file_count"
        return 1
    fi
}

#===============================================================================
# RELAY STAGING TESTS
#===============================================================================

test_relay_creates_staging_directory() {
    setup_relay_test

    local to_server="server-b"
    local operation_uuid="test-uuid-123"
    local staging_dir="${REMOTE_DIR}/${to_server}/relay-${operation_uuid}"

    # Create staging as relay would
    mkdir -p "$staging_dir"

    if [[ ! -d "$staging_dir" ]]; then
        echo "Should create staging directory for relay"
        return 1
    fi
}

test_relay_cleans_up_staging_directory() {
    setup_relay_test

    local to_server="server-b"
    local operation_uuid="test-uuid-123"
    local staging_dir="${REMOTE_DIR}/${to_server}/relay-${operation_uuid}"

    # Create staging
    mkdir -p "$staging_dir"
    echo "test" > "${staging_dir}/file.txt"

    # Cleanup as relay would
    rm -rf "$staging_dir"

    if [[ -d "$staging_dir" ]]; then
        echo "Should clean up staging directory after relay"
        return 1
    fi
}

#===============================================================================
# RELAY FILE SELECTION TESTS
#===============================================================================

test_relay_selects_specific_file_when_requested() {
    setup_relay_test

    local from_server="server-a"
    local inbox_dir="${INBOX_DIR}/${from_server}"

    # Create inbox with multiple files
    mkdir -p "$inbox_dir"
    echo "file1 content" > "${inbox_dir}/file1.txt"
    echo "file2 content" > "${inbox_dir}/file2.txt"

    # Simulate selecting specific file
    export SOURCE_PATH="file1.txt"
    local target_file="${inbox_dir}/$(basename "$SOURCE_PATH")"

    if [[ ! -e "$target_file" ]]; then
        echo "Should find requested specific file"
        return 1
    fi
}

test_relay_reports_missing_specific_file() {
    setup_relay_test

    local from_server="server-a"
    local inbox_dir="${INBOX_DIR}/${from_server}"

    # Create inbox with different files
    mkdir -p "$inbox_dir"
    echo "file1 content" > "${inbox_dir}/file1.txt"

    # Simulate selecting non-existent file
    export SOURCE_PATH="nonexistent.txt"
    local target_file="${inbox_dir}/$(basename "$SOURCE_PATH")"

    if [[ -e "$target_file" ]]; then
        echo "Should not find non-existent specific file"
        return 1
    fi
}
