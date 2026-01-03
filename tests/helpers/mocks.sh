#!/usr/bin/env bash
#===============================================================================
# TEST HELPERS - MOCKS
#===============================================================================
# Provides mock functions for testing without side effects.
#
# Functions:
#   mock_command NAME [EXIT_CODE] [OUTPUT]
#   unmock_command NAME
#   mock_ssh_success
#   mock_ssh_failure
#   mock_rsync_success
#   mock_rsync_failure
#   mock_aws_success
#   mock_aws_failure
#   record_call NAME ARGS...
#   get_call_count NAME
#   get_call_args NAME [INDEX]
#   reset_mocks
#===============================================================================

# Storage for mock call tracking
declare -A _MOCK_CALL_COUNTS
declare -a _MOCK_CALL_ARGS

# Create a mock command
mock_command() {
    local name="$1"
    local exit_code="${2:-0}"
    local output="${3:-}"
    
    # Create mock function
    eval "
    ${name}() {
        record_call '${name}' \"\$@\"
        if [[ -n '${output}' ]]; then
            echo '${output}'
        fi
        return ${exit_code}
    }
    "
    
    export -f "$name"
}

# Remove a mock command
unmock_command() {
    local name="$1"
    unset -f "$name" 2>/dev/null || true
}

# Record a mock call
record_call() {
    local name="$1"
    shift
    local args="$*"
    
    _MOCK_CALL_COUNTS[$name]=$(( ${_MOCK_CALL_COUNTS[$name]:-0} + 1 ))
    _MOCK_CALL_ARGS+=("${name}:${args}")
}

# Get call count for a mock
get_call_count() {
    local name="$1"
    echo "${_MOCK_CALL_COUNTS[$name]:-0}"
}

# Get call arguments for a mock
get_call_args() {
    local name="$1"
    local index="${2:-0}"
    local count=0
    
    for call in "${_MOCK_CALL_ARGS[@]}"; do
        if [[ "$call" == "${name}:"* ]]; then
            if [[ $count -eq $index ]]; then
                echo "${call#*:}"
                return
            fi
            ((count++))
        fi
    done
}

# Reset all mocks
reset_mocks() {
    _MOCK_CALL_COUNTS=()
    _MOCK_CALL_ARGS=()
}

#===============================================================================
# PRE-BUILT MOCKS
#===============================================================================

# Mock successful SSH
mock_ssh_success() {
    mock_command "ssh" 0 ""
}

# Mock failed SSH
mock_ssh_failure() {
    mock_command "ssh" 255 "Connection refused"
}

# Mock successful rsync
mock_rsync_success() {
    mock_command "rsync" 0 "sending incremental file list
sent 100 bytes  received 50 bytes  300.00 bytes/sec
total size is 100  speedup is 0.67"
}

# Mock failed rsync
mock_rsync_failure() {
    mock_command "rsync" 12 "rsync: connection unexpectedly closed"
}

# Mock successful AWS CLI
mock_aws_success() {
    mock_command "aws" 0 ""
}

# Mock failed AWS CLI
mock_aws_failure() {
    mock_command "aws" 1 "An error occurred (AccessDenied)"
}

# Mock uuidgen
mock_uuidgen() {
    local uuid="${1:-12345678-1234-1234-1234-123456789abc}"
    mock_command "uuidgen" 0 "$uuid"
}

#===============================================================================
# MOCK FILESYSTEM (for sandbox tests)
#===============================================================================

# Create a mock symlink attack scenario
create_symlink_attack_scenario() {
    local test_dir="$1"
    
    mkdir -p "${test_dir}/safe"
    mkdir -p "${test_dir}/unsafe"
    echo "sensitive" > "${test_dir}/unsafe/secret.txt"
    
    # Create symlink pointing outside sandbox
    ln -sf "${test_dir}/unsafe" "${test_dir}/safe/escape"
    
    echo "${test_dir}/safe"
}

# Create mock transfer scenario
create_mock_transfer_scenario() {
    local test_dir="$1"
    
    mkdir -p "${test_dir}/source"
    mkdir -p "${test_dir}/dest"
    
    echo "file1" > "${test_dir}/source/file1.txt"
    echo "file2" > "${test_dir}/source/file2.txt"
    
    echo "${test_dir}"
}

#===============================================================================
# STUB FUNCTIONS (replace real functions with testable versions)
#===============================================================================

# Stub for SSH connectivity test
stub_test_ssh_connection() {
    local host="$1"
    local port="$2"
    local user="$3"
    
    # Return based on host
    case "$host" in
        "localhost"|"127.0.0.1"|"good.example.com")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Stub for file transfer
stub_transfer_file() {
    local source="$1"
    local dest="$2"
    
    if [[ -f "$source" ]]; then
        cp "$source" "$dest"
        return 0
    else
        return 1
    fi
}
