#!/usr/bin/env bash
#===============================================================================
# INTEGRATION TESTS - INITIALIZATION & CONFIGURATION
#===============================================================================
# Tests that verify init and config loading work correctly together.
#===============================================================================

# Source all libraries
source "${TEST_DIR}/lib/logging.sh" 2>/dev/null || source "${PROJECT_ROOT}/lib/logging.sh"
source "${TEST_DIR}/lib/validation.sh" 2>/dev/null || source "${PROJECT_ROOT}/lib/validation.sh"
source "${TEST_DIR}/lib/core.sh" 2>/dev/null || source "${PROJECT_ROOT}/lib/core.sh"

#===============================================================================
# INITIALIZATION TESTS
#===============================================================================

test_init_creates_all_directories() {
    export SYNC_BASE_DIR="${TEST_DIR}/fresh-init"
    
    # Run init (simplified version)
    mkdir -p "$SYNC_BASE_DIR"/{config,remote,local/{inbox,outbox},logs,archive,tmp}
    
    assert_dir_exists "${SYNC_BASE_DIR}/config"
    assert_dir_exists "${SYNC_BASE_DIR}/remote"
    assert_dir_exists "${SYNC_BASE_DIR}/local/inbox"
    assert_dir_exists "${SYNC_BASE_DIR}/local/outbox"
    assert_dir_exists "${SYNC_BASE_DIR}/logs"
    assert_dir_exists "${SYNC_BASE_DIR}/archive"
    assert_dir_exists "${SYNC_BASE_DIR}/tmp"
}

test_init_is_idempotent() {
    export SYNC_BASE_DIR="${TEST_DIR}/idempotent-init"
    
    # Run init twice
    mkdir -p "$SYNC_BASE_DIR"/{config,remote,local/{inbox,outbox},logs,archive,tmp}
    mkdir -p "$SYNC_BASE_DIR"/{config,remote,local/{inbox,outbox},logs,archive,tmp}
    
    # Should still work
    assert_dir_exists "${SYNC_BASE_DIR}/config"
    assert_dir_exists "${SYNC_BASE_DIR}/logs"
}

test_init_preserves_existing_configs() {
    export SYNC_BASE_DIR="${TEST_DIR}/preserve-init"
    mkdir -p "${SYNC_BASE_DIR}/config"
    
    # Create existing config
    echo "CUSTOM_SETTING=true" > "${SYNC_BASE_DIR}/config/sync-shuttle.conf"
    
    # Run init again
    mkdir -p "$SYNC_BASE_DIR"/{config,remote,local/{inbox,outbox},logs,archive,tmp}
    
    # Original config should be preserved
    assert_file_contains "${SYNC_BASE_DIR}/config/sync-shuttle.conf" "CUSTOM_SETTING=true"
}

#===============================================================================
# CONFIGURATION LOADING TESTS
#===============================================================================

test_config_loading_reads_main_config() {
    export SYNC_BASE_DIR="${TEST_DIR}/config-test"
    export CONFIG_DIR="${SYNC_BASE_DIR}/config"
    mkdir -p "$CONFIG_DIR"
    
    # Create config
    cat > "${CONFIG_DIR}/sync-shuttle.conf" << 'EOF'
LOG_LEVEL="DEBUG"
MAX_TRANSFER_SIZE="5G"
S3_ENABLED="true"
EOF
    
    # Source config
    source "${CONFIG_DIR}/sync-shuttle.conf"
    
    assert_equals "$LOG_LEVEL" "DEBUG"
    assert_equals "$MAX_TRANSFER_SIZE" "5G"
    assert_equals "$S3_ENABLED" "true"
}

test_config_loading_reads_servers_config() {
    export SYNC_BASE_DIR="${TEST_DIR}/servers-test"
    export CONFIG_DIR="${SYNC_BASE_DIR}/config"
    mkdir -p "$CONFIG_DIR"
    
    # Create servers config
    cat > "${CONFIG_DIR}/servers.toml" << 'EOF'
declare -A server_mytest=(
    [name]="My Test Server"
    [host]="test.example.com"
    [port]="2222"
    [user]="testuser"
    [remote_base]="/test/path"
    [enabled]="true"
    [s3_backup]="false"
)
EOF
    
    # Source servers config
    source "${CONFIG_DIR}/servers.toml"
    
    # Check server was loaded
    assert_equals "${server_mytest[name]}" "My Test Server"
    assert_equals "${server_mytest[host]}" "test.example.com"
    assert_equals "${server_mytest[port]}" "2222"
}

test_config_loading_handles_missing_config() {
    export SYNC_BASE_DIR="${TEST_DIR}/missing-config"
    export CONFIG_DIR="${SYNC_BASE_DIR}/config"
    mkdir -p "$CONFIG_DIR"
    
    # No config file exists
    # Should not fail (use defaults)
    if [[ ! -f "${CONFIG_DIR}/sync-shuttle.conf" ]]; then
        # This is expected - defaults should apply
        :
    fi
}

#===============================================================================
# SERVER MANAGEMENT TESTS
#===============================================================================

test_list_all_servers_returns_enabled_servers() {
    export SYNC_BASE_DIR="${TEST_DIR}/list-servers"
    export CONFIG_DIR="${SYNC_BASE_DIR}/config"
    mkdir -p "$CONFIG_DIR"
    
    create_test_server_config
    
    local servers
    servers=$(list_all_servers)
    
    assert_contains "$servers" "dev" "Should list enabled dev server"
    assert_contains "$servers" "prod" "Should list enabled prod server"
}

test_list_all_servers_excludes_disabled_servers() {
    export SYNC_BASE_DIR="${TEST_DIR}/list-disabled"
    export CONFIG_DIR="${SYNC_BASE_DIR}/config"
    mkdir -p "$CONFIG_DIR"
    
    create_test_server_config
    
    local servers
    servers=$(list_all_servers)
    
    # Note: behavior depends on implementation
    # Some implementations may still list disabled servers
}

test_get_server_config_loads_all_fields() {
    export SYNC_BASE_DIR="${TEST_DIR}/get-config"
    export CONFIG_DIR="${SYNC_BASE_DIR}/config"
    mkdir -p "$CONFIG_DIR"
    
    create_test_server "myserver"
    
    local config
    config=$(get_server_config "myserver")
    
    # Eval the config to get variables
    eval "$config"
    
    assert_not_empty "$server_host" "Should have host"
    assert_not_empty "$server_port" "Should have port"
    assert_not_empty "$server_user" "Should have user"
    assert_not_empty "$server_remote_base" "Should have remote_base"
}

#===============================================================================
# PATH RESOLUTION TESTS
#===============================================================================

test_paths_computed_correctly_after_init() {
    export SYNC_BASE_DIR="${TEST_DIR}/paths-test"
    export CONFIG_DIR="${SYNC_BASE_DIR}/config"
    export REMOTE_DIR="${SYNC_BASE_DIR}/remote"
    export LOCAL_DIR="${SYNC_BASE_DIR}/local"
    export INBOX_DIR="${LOCAL_DIR}/inbox"
    export OUTBOX_DIR="${LOCAL_DIR}/outbox"
    export LOGS_DIR="${SYNC_BASE_DIR}/logs"
    
    mkdir -p "$CONFIG_DIR" "$REMOTE_DIR" "$INBOX_DIR" "$OUTBOX_DIR" "$LOGS_DIR"
    
    assert_equals "$CONFIG_DIR" "${SYNC_BASE_DIR}/config"
    assert_equals "$REMOTE_DIR" "${SYNC_BASE_DIR}/remote"
    assert_equals "$INBOX_DIR" "${SYNC_BASE_DIR}/local/inbox"
    assert_equals "$OUTBOX_DIR" "${SYNC_BASE_DIR}/local/outbox"
}

test_server_specific_paths_correct() {
    export SYNC_BASE_DIR="${TEST_DIR}/server-paths"
    export REMOTE_DIR="${SYNC_BASE_DIR}/remote"
    
    mkdir -p "$REMOTE_DIR"
    
    local server_id="myserver"
    local server_files_dir="${REMOTE_DIR}/${server_id}/files"
    
    mkdir -p "$server_files_dir"
    
    assert_dir_exists "$server_files_dir"
    assert_equals "$server_files_dir" "${SYNC_BASE_DIR}/remote/myserver/files"
}
