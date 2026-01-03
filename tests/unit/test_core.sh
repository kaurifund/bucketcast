#!/usr/bin/env bash
#===============================================================================
# UNIT TESTS - CORE LIBRARY
#===============================================================================
# Tests for lib/core.sh functions.
# These tests are idempotent and have no external dependencies.
#===============================================================================

# Source the library under test
source "${TEST_DIR}/lib/core.sh" 2>/dev/null || source "${PROJECT_ROOT}/lib/core.sh"

#===============================================================================
# UUID GENERATION TESTS
#===============================================================================

test_generate_uuid_returns_valid_format() {
    local uuid
    uuid=$(generate_uuid)
    
    # UUID should match pattern: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    local pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    
    if [[ ! "$uuid" =~ $pattern ]]; then
        echo "UUID '$uuid' does not match expected pattern"
        return 1
    fi
}

test_generate_uuid_returns_unique_values() {
    local uuid1 uuid2 uuid3
    
    uuid1=$(generate_uuid)
    uuid2=$(generate_uuid)
    uuid3=$(generate_uuid)
    
    assert_not_equals "$uuid1" "$uuid2" "UUIDs should be unique"
    assert_not_equals "$uuid2" "$uuid3" "UUIDs should be unique"
    assert_not_equals "$uuid1" "$uuid3" "UUIDs should be unique"
}

test_generate_uuid_lowercase() {
    local uuid
    uuid=$(generate_uuid)
    
    # Should be lowercase
    assert_equals "$uuid" "$(echo "$uuid" | tr '[:upper:]' '[:lower:]')" \
        "UUID should be lowercase"
}

#===============================================================================
# SERVER CONFIG TESTS
#===============================================================================

test_get_server_config_returns_error_for_missing_server() {
    # Create minimal servers.toml without the requested server
    create_test_server "existing"
    
    # This should fail for a non-existent server
    if get_server_config "nonexistent" &>/dev/null; then
        echo "Should have failed for non-existent server"
        return 1
    fi
}

test_get_server_config_returns_error_for_disabled_server() {
    create_test_server "testserver"
    create_disabled_server "disabled"
    
    if get_server_config "disabled" &>/dev/null; then
        echo "Should have failed for disabled server"
        return 1
    fi
}

test_get_server_config_returns_config_for_valid_server() {
    create_test_server "myserver"
    
    local config
    config=$(get_server_config "myserver")
    
    assert_contains "$config" "server_host=" "Config should contain host"
    assert_contains "$config" "server_port=" "Config should contain port"
    assert_contains "$config" "server_user=" "Config should contain user"
}

#===============================================================================
# VALIDATE SERVER ID TESTS
#===============================================================================

test_validate_server_id_accepts_valid_ids() {
    local valid_ids=(
        "server1"
        "my-server"
        "dev"
        "prod-web-01"
        "abcdefghijklmnopqrstuvwxyz12345"
    )
    
    for id in "${valid_ids[@]}"; do
        if ! validate_server_id "$id" &>/dev/null; then
            echo "Should accept valid server ID: $id"
            return 1
        fi
    done
}

test_validate_server_id_rejects_invalid_ids() {
    local invalid_ids=(
        "ab"              # too short
        "Server1"         # uppercase
        "my--server"      # double dash
        "-server"         # starts with dash
        "server-"         # ends with dash
        "my_server"       # underscore (we use these internally)
        "server with space"
        ""
    )
    
    for id in "${invalid_ids[@]}"; do
        if validate_server_id "$id" &>/dev/null; then
            echo "Should reject invalid server ID: '$id'"
            return 1
        fi
    done
}

#===============================================================================
# DIRECTORY UTILITY TESTS
#===============================================================================

test_ensure_directory_creates_missing_dir() {
    local test_path="${TEST_DIR}/new_dir"
    
    assert_dir_not_exists "$test_path"
    
    ensure_directory "$test_path"
    
    assert_dir_exists "$test_path"
}

test_ensure_directory_is_idempotent() {
    local test_path="${TEST_DIR}/idempotent_dir"
    
    # Create twice
    ensure_directory "$test_path"
    ensure_directory "$test_path"
    
    # Should still exist
    assert_dir_exists "$test_path"
}

test_ensure_directory_creates_nested_dirs() {
    local test_path="${TEST_DIR}/a/b/c/d/e"
    
    ensure_directory "$test_path"
    
    assert_dir_exists "$test_path"
}
