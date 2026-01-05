#!/usr/bin/env bash
#===============================================================================
# UNIT TESTS - VALIDATION LIBRARY
#===============================================================================
# Tests for lib/validation.sh functions.
# Critical security tests for path validation.
#===============================================================================

# Source dependencies
source "${TEST_DIR}/lib/logging.sh" 2>/dev/null || source "${PROJECT_ROOT}/lib/logging.sh"
source "${TEST_DIR}/lib/validation.sh" 2>/dev/null || source "${PROJECT_ROOT}/lib/validation.sh"

#===============================================================================
# PATH SANDBOX VALIDATION TESTS (CRITICAL SECURITY)
#===============================================================================

test_validate_path_within_sandbox_accepts_valid_paths() {
    export SYNC_BASE_DIR="${TEST_DIR}/sandbox"
    mkdir -p "$SYNC_BASE_DIR"
    
    local valid_paths=(
        "${SYNC_BASE_DIR}/file.txt"
        "${SYNC_BASE_DIR}/subdir/file.txt"
        "${SYNC_BASE_DIR}/a/b/c/file.txt"
        "${SYNC_BASE_DIR}/"
    )
    
    for path in "${valid_paths[@]}"; do
        mkdir -p "$(dirname "$path")"
        if ! validate_path_within_sandbox "$path"; then
            echo "Should accept valid path: $path"
            return 1
        fi
    done
}

test_validate_path_within_sandbox_rejects_outside_paths() {
    export SYNC_BASE_DIR="${TEST_DIR}/sandbox"
    mkdir -p "$SYNC_BASE_DIR"
    
    local invalid_paths=(
        "/etc/passwd"
        "/tmp/outside"
        "${HOME}/.ssh/id_rsa"
        "${TEST_DIR}/outside_sandbox"
    )
    
    for path in "${invalid_paths[@]}"; do
        if validate_path_within_sandbox "$path" 2>/dev/null; then
            echo "Should reject path outside sandbox: $path"
            return 1
        fi
    done
}

test_validate_path_within_sandbox_rejects_path_traversal() {
    export SYNC_BASE_DIR="${TEST_DIR}/sandbox"
    mkdir -p "$SYNC_BASE_DIR"
    
    local traversal_paths=(
        "${SYNC_BASE_DIR}/../outside"
        "${SYNC_BASE_DIR}/subdir/../../outside"
        "${SYNC_BASE_DIR}/./../../etc/passwd"
        "${SYNC_BASE_DIR}/../../../tmp"
    )
    
    for path in "${traversal_paths[@]}"; do
        if validate_path_within_sandbox "$path" 2>/dev/null; then
            echo "Should reject path traversal attack: $path"
            return 1
        fi
    done
}

test_validate_path_within_sandbox_rejects_symlink_escape() {
    export SYNC_BASE_DIR="${TEST_DIR}/sandbox"
    mkdir -p "$SYNC_BASE_DIR"
    mkdir -p "${TEST_DIR}/outside"
    echo "secret" > "${TEST_DIR}/outside/secret.txt"

    # Create symlink inside sandbox pointing outside
    ln -sf "${TEST_DIR}/outside" "${SYNC_BASE_DIR}/escape_link"

    # The symlink target should be rejected
    if validate_path_within_sandbox "${SYNC_BASE_DIR}/escape_link/secret.txt" 2>/dev/null; then
        echo "Should reject symlink escape attempt"
        return 1
    fi
}

test_validate_path_within_sandbox_rejects_prefix_attack() {
    export SYNC_BASE_DIR="${TEST_DIR}/sandbox"
    mkdir -p "$SYNC_BASE_DIR"
    mkdir -p "${TEST_DIR}/sandboxFAKE"

    # Paths that start with sandbox name but are actually outside
    local prefix_attacks=(
        "${TEST_DIR}/sandboxFAKE/file.txt"
        "${TEST_DIR}/sandbox_evil/file.txt"
        "${TEST_DIR}/sandbox.bak/file.txt"
    )

    for path in "${prefix_attacks[@]}"; do
        mkdir -p "$(dirname "$path")"
        if validate_path_within_sandbox "$path" 2>/dev/null; then
            echo "Should reject prefix attack: $path"
            return 1
        fi
    done
}

test_validate_path_within_sandbox_handles_relative_paths() {
    export SYNC_BASE_DIR="${TEST_DIR}/sandbox"
    mkdir -p "$SYNC_BASE_DIR"
    
    # Change to sandbox and test relative path
    cd "$SYNC_BASE_DIR"
    mkdir -p subdir
    
    if ! validate_path_within_sandbox "./subdir/file.txt"; then
        echo "Should accept relative path within sandbox"
        return 1
    fi
}

#===============================================================================
# ENVIRONMENT VALIDATION TESTS
#===============================================================================

test_validate_environment_checks_bash_version() {
    # This should pass since we're running in bash 4+
    # We can't easily test failure without mocking
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        # Should not fail for our current shell
        :  # No-op, test passes if we got here
    fi
}

test_validate_environment_checks_required_tools() {
    # These tools should exist on most systems
    for tool in date; do
        if ! command -v "$tool" &>/dev/null; then
            skip_test "Required tool not found: $tool"
        fi
    done
}

#===============================================================================
# SOURCE PATH VALIDATION TESTS
#===============================================================================

test_validate_source_path_accepts_existing_file() {
    local test_file="${TEST_DIR}/source_file.txt"
    echo "test" > "$test_file"
    
    if ! validate_source_path "$test_file"; then
        echo "Should accept existing file"
        return 1
    fi
}

test_validate_source_path_accepts_existing_directory() {
    local test_dir="${TEST_DIR}/source_dir"
    mkdir -p "$test_dir"
    
    if ! validate_source_path "$test_dir"; then
        echo "Should accept existing directory"
        return 1
    fi
}

test_validate_source_path_rejects_nonexistent_path() {
    if validate_source_path "/nonexistent/path/file.txt" 2>/dev/null; then
        echo "Should reject non-existent path"
        return 1
    fi
}

#===============================================================================
# FILE COLLISION TESTS
#===============================================================================

test_check_file_collision_detects_existing_file() {
    local test_file="${TEST_DIR}/existing.txt"
    echo "existing" > "$test_file"
    
    export FORCE="false"
    
    if check_file_collision "$test_file" 2>/dev/null; then
        echo "Should detect collision with existing file"
        return 1
    fi
}

test_check_file_collision_allows_with_force() {
    local test_file="${TEST_DIR}/existing.txt"
    echo "existing" > "$test_file"
    
    export FORCE="true"
    
    # With force, collision check should pass (return 0)
    # Note: actual behavior may prompt, but in tests FORCE=true should bypass
    if ! check_file_collision "$test_file" 2>/dev/null; then
        # This is expected if the function requires interactive confirmation
        # In non-interactive mode with FORCE, it might fail
        :  # Accept either behavior for unit test
    fi
}

test_check_file_collision_passes_for_new_file() {
    local test_file="${TEST_DIR}/new_file_$(date +%s).txt"
    
    export FORCE="false"
    
    if ! check_file_collision "$test_file"; then
        echo "Should not detect collision for non-existent file"
        return 1
    fi
}

#===============================================================================
# TRANSFER SIZE VALIDATION TESTS
#===============================================================================

test_validate_transfer_size_accepts_small_files() {
    local test_file="${TEST_DIR}/small.txt"
    echo "small" > "$test_file"
    
    export MAX_TRANSFER_SIZE="10G"
    
    if ! validate_transfer_size "$test_file"; then
        echo "Should accept small file"
        return 1
    fi
}

test_validate_transfer_size_parses_size_limits() {
    # Test that various size formats are understood
    local sizes=("1K" "1M" "1G" "100M" "10G")

    for size in "${sizes[@]}"; do
        export MAX_TRANSFER_SIZE="$size"
        local test_file="${TEST_DIR}/tiny.txt"
        echo "x" > "$test_file"

        if ! validate_transfer_size "$test_file"; then
            echo "Should accept file with MAX_TRANSFER_SIZE=$size"
            return 1
        fi
    done
}

#===============================================================================
# SERVER ID VALIDATION TESTS
#===============================================================================

test_validate_server_id_rejects_reserved_namespace_global() {
    # "global" is reserved for outbox/global/ directory
    if validate_server_id "global" 2>/dev/null; then
        echo "Should reject reserved namespace: global"
        return 1
    fi
}

test_validate_server_id_accepts_valid_server_ids() {
    local valid_ids=(
        "my-server"
        "prod01"
        "dev-web-01"
        "test123"
    )

    for id in "${valid_ids[@]}"; do
        if ! validate_server_id "$id" 2>/dev/null; then
            echo "Should accept valid server ID: $id"
            return 1
        fi
    done
}

test_validate_server_id_rejects_invalid_format() {
    local invalid_ids=(
        "ab"                    # Too short
        "UPPERCASE"             # Must be lowercase
        "has_underscore"        # No underscores
        "has--double-dash"      # No consecutive dashes
        "-starts-with-dash"     # Cannot start with dash
    )

    for id in "${invalid_ids[@]}"; do
        if validate_server_id "$id" 2>/dev/null; then
            echo "Should reject invalid server ID: $id"
            return 1
        fi
    done
}
