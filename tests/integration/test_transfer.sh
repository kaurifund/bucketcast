#!/usr/bin/env bash
#===============================================================================
# INTEGRATION TESTS - TRANSFER OPERATIONS
#===============================================================================
# Tests that verify transfer functions work correctly together.
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
setup_transfer_test() {
    export SYNC_BASE_DIR="${TEST_DIR}/sync-shuttle"
    export REMOTE_DIR="${SYNC_BASE_DIR}/remote"
    export LOCAL_DIR="${SYNC_BASE_DIR}/local"
    export INBOX_DIR="${LOCAL_DIR}/inbox"
    export OUTBOX_DIR="${LOCAL_DIR}/outbox"
    export TMP_DIR="${SYNC_BASE_DIR}/tmp"
    export LOGS_DIR="${SYNC_BASE_DIR}/logs"
    export LOG_FILE="${LOGS_DIR}/sync.log"
    export LOG_JSON_FILE="${LOGS_DIR}/sync.jsonl"
    
    mkdir -p "$REMOTE_DIR" "$INBOX_DIR" "$OUTBOX_DIR" "$TMP_DIR" "$LOGS_DIR"
    touch "$LOG_FILE" "$LOG_JSON_FILE"
    
    export DRY_RUN="false"
    export FORCE="false"
    export VERBOSE="false"
    export QUIET="true"
}

#===============================================================================
# RSYNC OPTIONS TESTS
#===============================================================================

test_build_rsync_options_includes_base_options() {
    setup_transfer_test
    
    local options
    options=$(build_rsync_options "")
    
    assert_contains "$options" "--archive" "Should include archive flag"
    assert_contains "$options" "--compress" "Should include compress flag"
    assert_contains "$options" "--partial" "Should include partial flag"
}

test_build_rsync_options_adds_dry_run_flag() {
    setup_transfer_test
    
    local options
    options=$(build_rsync_options "--dry-run")
    
    assert_contains "$options" "--dry-run" "Should include dry-run flag"
}

test_build_rsync_options_never_includes_delete() {
    setup_transfer_test
    
    local options
    options=$(build_rsync_options "")
    
    assert_not_contains "$options" "--delete" "Should NEVER include delete flag"
}

test_build_rsync_options_includes_ignore_existing() {
    setup_transfer_test
    
    local options
    options=$(build_rsync_options "")
    
    assert_contains "$options" "--ignore-existing" "Should include ignore-existing for safety"
}

#===============================================================================
# LOCAL TRANSFER TESTS (rsync without network)
#===============================================================================

test_perform_rsync_push_copies_file_locally() {
    setup_transfer_test
    
    # Create source file
    local source_file="${TEST_DIR}/source_file.txt"
    echo "test content" > "$source_file"
    
    # Create destination
    local dest_dir="${REMOTE_DIR}/testserver/files"
    mkdir -p "$dest_dir"
    
    # Perform local rsync
    perform_rsync_push "$source_file" "$dest_dir" ""
    
    # Verify file was copied
    assert_file_exists "${dest_dir}/source_file.txt"
    assert_file_contains "${dest_dir}/source_file.txt" "test content"
}

test_perform_rsync_push_copies_directory() {
    setup_transfer_test
    
    # Create source directory with files
    local source_dir="${TEST_DIR}/source_dir"
    mkdir -p "${source_dir}/subdir"
    echo "file1" > "${source_dir}/file1.txt"
    echo "file2" > "${source_dir}/subdir/file2.txt"
    
    # Create destination
    local dest_dir="${REMOTE_DIR}/testserver/files"
    mkdir -p "$dest_dir"
    
    # Perform local rsync
    perform_rsync_push "$source_dir" "$dest_dir" ""
    
    # Verify files were copied
    assert_file_exists "${dest_dir}/source_dir/file1.txt"
    assert_file_exists "${dest_dir}/source_dir/subdir/file2.txt"
}

test_perform_rsync_push_dry_run_no_changes() {
    setup_transfer_test
    
    # Create source file
    local source_file="${TEST_DIR}/dry_run_file.txt"
    echo "test content" > "$source_file"
    
    # Create destination
    local dest_dir="${REMOTE_DIR}/testserver/files"
    mkdir -p "$dest_dir"
    
    # Perform dry-run
    perform_rsync_push "$source_file" "$dest_dir" "--dry-run"
    
    # File should NOT exist (dry-run)
    assert_file_not_exists "${dest_dir}/dry_run_file.txt"
}

test_perform_rsync_push_preserves_existing_files() {
    setup_transfer_test
    
    # Create destination with existing file
    local dest_dir="${REMOTE_DIR}/testserver/files"
    mkdir -p "$dest_dir"
    echo "original content" > "${dest_dir}/existing.txt"
    
    # Create source with same filename
    local source_file="${TEST_DIR}/existing.txt"
    echo "new content" > "$source_file"
    
    # Perform push (should ignore existing)
    perform_rsync_push "$source_file" "$dest_dir" ""
    
    # Original file should be preserved
    assert_file_contains "${dest_dir}/existing.txt" "original content"
}

#===============================================================================
# TRANSFER VERIFICATION TESTS
#===============================================================================

test_verify_transfer_passes_for_complete_transfer() {
    setup_transfer_test
    
    local source_file="${TEST_DIR}/verify_source.txt"
    local dest_file="${TEST_DIR}/verify_dest.txt"
    
    echo "content" > "$source_file"
    cp "$source_file" "$dest_file"
    
    # Both files exist and match
    if ! verify_transfer "$source_file" "$dest_file"; then
        echo "Should pass verification for matching files"
        return 1
    fi
}

test_verify_transfer_fails_for_missing_destination() {
    setup_transfer_test
    
    local source_file="${TEST_DIR}/verify_source.txt"
    echo "content" > "$source_file"
    
    # Destination doesn't exist
    if verify_transfer "$source_file" "/nonexistent/path" 2>/dev/null; then
        echo "Should fail verification for missing destination"
        return 1
    fi
}

#===============================================================================
# TRANSFER STATS TESTS
#===============================================================================

test_get_transfer_stats_returns_size() {
    setup_transfer_test
    
    local test_file="${TEST_DIR}/stats_test.txt"
    echo "12345" > "$test_file"  # 6 bytes including newline
    
    local size
    size=$(get_file_size "$test_file")
    
    assert_not_empty "$size" "Should return file size"
}

test_get_transfer_stats_handles_directory() {
    setup_transfer_test
    
    local test_dir="${TEST_DIR}/stats_dir"
    mkdir -p "$test_dir"
    echo "file1" > "${test_dir}/file1.txt"
    echo "file2" > "${test_dir}/file2.txt"
    
    local size
    size=$(get_directory_size "$test_dir")
    
    assert_not_empty "$size" "Should return directory size"
}
