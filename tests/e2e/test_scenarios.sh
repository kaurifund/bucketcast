#!/usr/bin/env bash
#===============================================================================
# END-TO-END TESTS - USER SCENARIOS
#===============================================================================
# Tests that verify complete user workflows from start to finish.
# These tests run the actual sync-shuttle.sh script.
#===============================================================================

readonly SYNC_SHUTTLE="${PROJECT_ROOT}/sync-shuttle.sh"

#===============================================================================
# SETUP
#===============================================================================
setup_e2e() {
    export HOME="${TEST_DIR}/home"
    export SYNC_BASE_DIR="${HOME}/.sync-shuttle"
    
    mkdir -p "$HOME"
    
    # Make script executable
    chmod +x "$SYNC_SHUTTLE"
}

#===============================================================================
# INIT SCENARIO TESTS
#===============================================================================

test_e2e_init_creates_structure() {
    setup_e2e
    
    # Run init
    "$SYNC_SHUTTLE" init &>/dev/null
    
    # Verify structure
    assert_dir_exists "$SYNC_BASE_DIR"
    assert_dir_exists "${SYNC_BASE_DIR}/config"
    assert_dir_exists "${SYNC_BASE_DIR}/remote"
    assert_dir_exists "${SYNC_BASE_DIR}/local/inbox"
    assert_dir_exists "${SYNC_BASE_DIR}/local/outbox"
    assert_dir_exists "${SYNC_BASE_DIR}/logs"
    assert_dir_exists "${SYNC_BASE_DIR}/archive"
    assert_dir_exists "${SYNC_BASE_DIR}/tmp"
}

test_e2e_init_creates_config_files() {
    setup_e2e
    
    # Run init
    "$SYNC_SHUTTLE" init &>/dev/null
    
    # Verify config files
    assert_file_exists "${SYNC_BASE_DIR}/config/sync-shuttle.conf"
    assert_file_exists "${SYNC_BASE_DIR}/config/servers.toml"
}

test_e2e_init_creates_log_files() {
    setup_e2e
    
    # Run init
    "$SYNC_SHUTTLE" init &>/dev/null
    
    # Verify log files
    assert_file_exists "${SYNC_BASE_DIR}/logs/sync.log"
    assert_file_exists "${SYNC_BASE_DIR}/logs/sync.jsonl"
}

test_e2e_init_is_idempotent() {
    setup_e2e
    
    # Run init twice
    "$SYNC_SHUTTLE" init &>/dev/null
    "$SYNC_SHUTTLE" init &>/dev/null
    
    # Should still work without errors
    assert_dir_exists "$SYNC_BASE_DIR"
}

#===============================================================================
# HELP AND VERSION TESTS
#===============================================================================

test_e2e_help_shows_usage() {
    setup_e2e
    
    local output
    output=$("$SYNC_SHUTTLE" --help 2>&1)
    
    assert_contains "$output" "USAGE" "Help should show usage"
    assert_contains "$output" "COMMANDS" "Help should show commands"
    assert_contains "$output" "OPTIONS" "Help should show options"
}

test_e2e_version_shows_version() {
    setup_e2e
    
    local output
    output=$("$SYNC_SHUTTLE" --version 2>&1)
    
    assert_contains "$output" "sync-shuttle" "Version should show name"
    assert_contains "$output" "version" "Version should show version word"
}

#===============================================================================
# LIST COMMANDS TESTS
#===============================================================================

test_e2e_list_servers_works() {
    setup_e2e
    
    # Init first
    "$SYNC_SHUTTLE" init &>/dev/null
    
    # List servers
    local output
    output=$("$SYNC_SHUTTLE" list servers 2>&1)
    
    # Should output something (even if empty)
    # At minimum should show header
    assert_contains "$output" "Server" "Should show servers header or content"
}

test_e2e_list_files_requires_server() {
    setup_e2e
    
    # Init first
    "$SYNC_SHUTTLE" init &>/dev/null
    
    # List files without server should fail
    if "$SYNC_SHUTTLE" list files 2>/dev/null; then
        echo "Should require server ID for list files"
        return 1
    fi
}

#===============================================================================
# STATUS COMMAND TESTS
#===============================================================================

test_e2e_status_shows_info() {
    setup_e2e
    
    # Init first
    "$SYNC_SHUTTLE" init &>/dev/null
    
    # Check status
    local output
    output=$("$SYNC_SHUTTLE" status 2>&1)
    
    assert_contains "$output" "Status" "Should show status header"
}

#===============================================================================
# PUSH COMMAND TESTS
#===============================================================================

test_e2e_push_requires_server() {
    setup_e2e
    
    "$SYNC_SHUTTLE" init &>/dev/null
    
    # Push without server should fail
    if "$SYNC_SHUTTLE" push 2>/dev/null; then
        echo "Should require server for push"
        return 1
    fi
}

test_e2e_push_requires_source() {
    setup_e2e
    
    "$SYNC_SHUTTLE" init &>/dev/null
    
    # Add a test server
    cat > "${SYNC_BASE_DIR}/config/servers.toml" << 'EOF'
declare -A server_test=(
    [name]="Test Server"
    [host]="localhost"
    [port]="22"
    [user]="nobody"
    [remote_base]="/tmp"
    [enabled]="true"
    [s3_backup]="false"
)
EOF
    
    # Push without source should fail
    if "$SYNC_SHUTTLE" push --server test 2>/dev/null; then
        echo "Should require source for push"
        return 1
    fi
}

test_e2e_push_validates_source_exists() {
    setup_e2e
    
    "$SYNC_SHUTTLE" init &>/dev/null
    
    # Add a test server
    cat > "${SYNC_BASE_DIR}/config/servers.toml" << 'EOF'
declare -A server_test=(
    [name]="Test Server"
    [host]="localhost"
    [port]="22"
    [user]="nobody"
    [remote_base]="/tmp"
    [enabled]="true"
    [s3_backup]="false"
)
EOF
    
    # Push with non-existent source should fail
    if "$SYNC_SHUTTLE" push --server test --source /nonexistent/path 2>/dev/null; then
        echo "Should validate source exists"
        return 1
    fi
}

test_e2e_push_dry_run_makes_no_changes() {
    setup_e2e
    
    "$SYNC_SHUTTLE" init &>/dev/null
    
    # Create test file
    local test_file="${TEST_DIR}/dry_run_test.txt"
    echo "test" > "$test_file"
    
    # Add a test server
    cat > "${SYNC_BASE_DIR}/config/servers.toml" << 'EOF'
declare -A server_test=(
    [name]="Test Server"
    [host]="localhost"
    [port]="22"
    [user]="nobody"
    [remote_base]="/tmp/sync-shuttle-test"
    [enabled]="true"
    [s3_backup]="false"
)
EOF
    
    # Dry run (will fail SSH but should show dry-run message)
    local output
    output=$("$SYNC_SHUTTLE" push --server test --source "$test_file" --dry-run 2>&1) || true
    
    assert_contains "$output" "DRY" "Should indicate dry-run mode"
}

#===============================================================================
# PULL COMMAND TESTS
#===============================================================================

test_e2e_pull_requires_server() {
    setup_e2e
    
    "$SYNC_SHUTTLE" init &>/dev/null
    
    # Pull without server should fail
    if "$SYNC_SHUTTLE" pull 2>/dev/null; then
        echo "Should require server for pull"
        return 1
    fi
}

#===============================================================================
# ERROR HANDLING TESTS
#===============================================================================

test_e2e_unknown_command_fails() {
    setup_e2e
    
    if "$SYNC_SHUTTLE" unknowncommand 2>/dev/null; then
        echo "Should fail for unknown command"
        return 1
    fi
}

test_e2e_invalid_option_fails() {
    setup_e2e
    
    if "$SYNC_SHUTTLE" init --invalid-option 2>/dev/null; then
        echo "Should fail for invalid option"
        return 1
    fi
}

#===============================================================================
# EXIT CODE TESTS
#===============================================================================

test_e2e_success_returns_zero() {
    setup_e2e
    
    local exit_code
    "$SYNC_SHUTTLE" --help &>/dev/null
    exit_code=$?
    
    assert_equals "$exit_code" "0" "Help should return exit code 0"
}

test_e2e_error_returns_nonzero() {
    setup_e2e
    
    local exit_code
    "$SYNC_SHUTTLE" invalid 2>/dev/null || exit_code=$?
    
    assert_not_equals "${exit_code:-0}" "0" "Error should return non-zero exit code"
}
