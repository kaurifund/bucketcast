#!/usr/bin/env bash
#===============================================================================
# SYNC SHUTTLE - TEST HELPERS
#===============================================================================
# Common utilities and fixtures for all test types.
# Source this file at the start of any test script.
#
# Usage:
#   source "$(dirname "$0")/../helpers/test_helpers.sh"
#
# Provides:
#   - Test isolation (temp directories)
#   - Assertion functions
#   - Mock server setup
#   - Cleanup handlers
#===============================================================================

set -o errexit
set -o nounset
set -o pipefail

#===============================================================================
# TEST CONFIGURATION
#===============================================================================
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
readonly SYNC_SHUTTLE="${PROJECT_ROOT}/sync-shuttle.sh"

# Test isolation - each test gets its own temp directory
TEST_TMP=""
TEST_HOME=""
TEST_SYNC_BASE=""

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Current test name
CURRENT_TEST=""

#===============================================================================
# COLORS
#===============================================================================
if [[ -t 1 ]]; then
    readonly C_RED='\033[0;31m'
    readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[0;33m'
    readonly C_BLUE='\033[0;34m'
    readonly C_BOLD='\033[1m'
    readonly C_RESET='\033[0m'
else
    readonly C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_BOLD='' C_RESET=''
fi

#===============================================================================
# SETUP / TEARDOWN
#===============================================================================

# Call at start of test file
setup_test_environment() {
    # Create isolated temp directory
    TEST_TMP=$(mktemp -d -t sync-shuttle-test.XXXXXX)
    TEST_HOME="${TEST_TMP}/home"
    TEST_SYNC_BASE="${TEST_HOME}/.sync-shuttle"
    
    mkdir -p "$TEST_HOME"
    
    # Export for sync-shuttle to use
    export HOME="$TEST_HOME"
    export SYNC_BASE_DIR="$TEST_SYNC_BASE"
    
    # Trap cleanup on exit
    trap cleanup_test_environment EXIT
    
    echo -e "${C_BLUE}[SETUP]${C_RESET} Test environment: ${TEST_TMP}"
}

# Called automatically on exit
cleanup_test_environment() {
    local exit_code=$?
    
    if [[ -n "$TEST_TMP" && -d "$TEST_TMP" ]]; then
        # Only remove if tests passed or KEEP_TEST_DIR not set
        if [[ $exit_code -eq 0 && "${KEEP_TEST_DIR:-}" != "1" ]]; then
            rm -rf "$TEST_TMP"
        else
            echo -e "${C_YELLOW}[CLEANUP]${C_RESET} Keeping test dir: ${TEST_TMP}"
        fi
    fi
    
    return $exit_code
}

# Initialize sync-shuttle in test environment
init_sync_shuttle() {
    "$SYNC_SHUTTLE" init >/dev/null 2>&1
}

#===============================================================================
# ASSERTION FUNCTIONS
#===============================================================================

# Assert that a command succeeds
assert_success() {
    local description="$1"
    shift
    
    if "$@" >/dev/null 2>&1; then
        pass "$description"
    else
        fail "$description" "Command failed: $*"
    fi
}

# Assert that a command fails
assert_failure() {
    local description="$1"
    shift
    
    if "$@" >/dev/null 2>&1; then
        fail "$description" "Expected failure but succeeded: $*"
    else
        pass "$description"
    fi
}

# Assert two values are equal
assert_equals() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    
    if [[ "$expected" == "$actual" ]]; then
        pass "$description"
    else
        fail "$description" "Expected: '$expected', Got: '$actual'"
    fi
}

# Assert string contains substring
assert_contains() {
    local description="$1"
    local haystack="$2"
    local needle="$3"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$description"
    else
        fail "$description" "String does not contain '$needle'"
    fi
}

# Assert file exists
assert_file_exists() {
    local description="$1"
    local filepath="$2"
    
    if [[ -f "$filepath" ]]; then
        pass "$description"
    else
        fail "$description" "File not found: $filepath"
    fi
}

# Assert directory exists
assert_dir_exists() {
    local description="$1"
    local dirpath="$2"
    
    if [[ -d "$dirpath" ]]; then
        pass "$description"
    else
        fail "$description" "Directory not found: $dirpath"
    fi
}

# Assert file does NOT exist
assert_file_not_exists() {
    local description="$1"
    local filepath="$2"
    
    if [[ ! -f "$filepath" ]]; then
        pass "$description"
    else
        fail "$description" "File should not exist: $filepath"
    fi
}

# Assert file contains text
assert_file_contains() {
    local description="$1"
    local filepath="$2"
    local pattern="$3"
    
    if grep -q "$pattern" "$filepath" 2>/dev/null; then
        pass "$description"
    else
        fail "$description" "File '$filepath' does not contain '$pattern'"
    fi
}

# Assert command output matches
assert_output_contains() {
    local description="$1"
    local expected="$2"
    shift 2
    
    local output
    output=$("$@" 2>&1) || true
    
    if [[ "$output" == *"$expected"* ]]; then
        pass "$description"
    else
        fail "$description" "Output does not contain '$expected'"
    fi
}

# Assert exit code
assert_exit_code() {
    local description="$1"
    local expected_code="$2"
    shift 2
    
    local actual_code
    "$@" >/dev/null 2>&1 && actual_code=0 || actual_code=$?
    
    if [[ "$actual_code" -eq "$expected_code" ]]; then
        pass "$description"
    else
        fail "$description" "Expected exit code $expected_code, got $actual_code"
    fi
}

#===============================================================================
# TEST RESULT FUNCTIONS
#===============================================================================

pass() {
    local description="$1"
    ((TESTS_PASSED++))
    echo -e "  ${C_GREEN}✓${C_RESET} ${description}"
}

fail() {
    local description="$1"
    local message="${2:-}"
    ((TESTS_FAILED++))
    echo -e "  ${C_RED}✗${C_RESET} ${description}"
    if [[ -n "$message" ]]; then
        echo -e "    ${C_RED}→ ${message}${C_RESET}"
    fi
}

skip() {
    local description="$1"
    local reason="${2:-}"
    ((TESTS_SKIPPED++))
    echo -e "  ${C_YELLOW}○${C_RESET} ${description} ${C_YELLOW}(skipped${reason:+: $reason})${C_RESET}"
}

#===============================================================================
# TEST LIFECYCLE
#===============================================================================

# Declare a test function
test_case() {
    local name="$1"
    CURRENT_TEST="$name"
    ((TESTS_RUN++))
    echo -e "\n${C_BOLD}TEST:${C_RESET} ${name}"
}

# Print test summary
print_summary() {
    echo ""
    echo -e "${C_BOLD}════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}TEST SUMMARY${C_RESET}"
    echo -e "${C_BOLD}════════════════════════════════════════════════${C_RESET}"
    echo -e "  Total:   ${TESTS_RUN}"
    echo -e "  ${C_GREEN}Passed:  ${TESTS_PASSED}${C_RESET}"
    echo -e "  ${C_RED}Failed:  ${TESTS_FAILED}${C_RESET}"
    echo -e "  ${C_YELLOW}Skipped: ${TESTS_SKIPPED}${C_RESET}"
    echo ""
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${C_RED}${C_BOLD}TESTS FAILED${C_RESET}"
        return 1
    else
        echo -e "${C_GREEN}${C_BOLD}ALL TESTS PASSED${C_RESET}"
        return 0
    fi
}

#===============================================================================
# MOCK / FIXTURE HELPERS
#===============================================================================

# Create a test file with content
create_test_file() {
    local filepath="$1"
    local content="${2:-test content}"
    
    mkdir -p "$(dirname "$filepath")"
    echo "$content" > "$filepath"
}

# Create a test directory with files
create_test_dir() {
    local dirpath="$1"
    local file_count="${2:-3}"
    
    mkdir -p "$dirpath"
    for i in $(seq 1 "$file_count"); do
        echo "test file $i" > "${dirpath}/file${i}.txt"
    done
}

# Create a mock server config
create_mock_server_config() {
    local server_id="$1"
    local servers_file="${TEST_SYNC_BASE}/config/servers.toml"
    
    mkdir -p "$(dirname "$servers_file")"
    
    cat >> "$servers_file" << EOF

declare -A server_${server_id}=(
    [name]="Test Server ${server_id}"
    [host]="localhost"
    [port]="22"
    [user]="testuser"
    [remote_base]="/tmp/sync-shuttle-remote"
    [enabled]="true"
    [s3_backup]="false"
)
EOF
}

# Get file checksum
file_checksum() {
    local filepath="$1"
    
    if command -v md5sum >/dev/null; then
        md5sum "$filepath" | cut -d' ' -f1
    elif command -v md5 >/dev/null; then
        md5 -q "$filepath"
    else
        # Fallback: use file size + mtime
        stat -c "%s-%Y" "$filepath" 2>/dev/null || stat -f "%z-%m" "$filepath"
    fi
}

#===============================================================================
# SKIP CONDITIONS
#===============================================================================

# Skip if command not available
skip_unless_command() {
    local cmd="$1"
    local test_name="$2"
    
    if ! command -v "$cmd" >/dev/null; then
        skip "$test_name" "$cmd not available"
        return 1
    fi
    return 0
}

# Skip if not root
skip_unless_root() {
    local test_name="$1"
    
    if [[ $EUID -ne 0 ]]; then
        skip "$test_name" "requires root"
        return 1
    fi
    return 0
}

# Skip if no network
skip_unless_network() {
    local test_name="$1"
    
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        skip "$test_name" "no network"
        return 1
    fi
    return 0
}
