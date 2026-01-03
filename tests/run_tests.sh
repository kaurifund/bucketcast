#!/usr/bin/env bash
#===============================================================================
# SYNC SHUTTLE - TEST RUNNER
#===============================================================================
# Main entry point for running all tests.
#
# Usage:
#   ./tests/run_tests.sh              # Run all tests
#   ./tests/run_tests.sh unit         # Run only unit tests
#   ./tests/run_tests.sh integration  # Run only integration tests
#   ./tests/run_tests.sh e2e          # Run only end-to-end tests
#   ./tests/run_tests.sh --verbose    # Verbose output
#
# Test Categories:
#   unit/        - Pure function tests (fast, no I/O)
#   integration/ - Component integration tests
#   e2e/         - End-to-end scenario tests
#
# Design Principles:
#   - Idempotent: Safe to run multiple times
#   - Isolated: Each test cleans up after itself
#   - No Side Effects: Tests use temporary directories
#   - Deterministic: Same input = same output
#===============================================================================

set -o errexit
set -o nounset
set -o pipefail

#===============================================================================
# CONFIGURATION
#===============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly TEST_TMP_BASE="/tmp/sync-shuttle-tests"
readonly TEST_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly TEST_TMP_DIR="${TEST_TMP_BASE}/${TEST_TIMESTAMP}"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Options
VERBOSE="${VERBOSE:-false}"
TEST_FILTER=""

# Colors
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[0;33m'
    readonly BLUE='\033[0;34m'
    readonly MAGENTA='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly BOLD='\033[1m'
    readonly RESET='\033[0m'
else
    readonly RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' BOLD='' RESET=''
fi

#===============================================================================
# TEST FRAMEWORK FUNCTIONS
#===============================================================================

# Source test helpers
source "${SCRIPT_DIR}/helpers/assertions.sh"
source "${SCRIPT_DIR}/helpers/fixtures.sh"
source "${SCRIPT_DIR}/helpers/mocks.sh"

# Setup test environment (called before each test file)
setup_test_env() {
    export TEST_DIR="${TEST_TMP_DIR}/$$_${RANDOM}"
    export SYNC_BASE_DIR="${TEST_DIR}/sync-shuttle"
    export HOME="${TEST_DIR}/home"
    
    mkdir -p "$TEST_DIR" "$SYNC_BASE_DIR" "$HOME"
    
    # Copy project files to test environment
    cp -r "${PROJECT_ROOT}/lib" "${TEST_DIR}/"
    cp "${PROJECT_ROOT}/sync-shuttle.sh" "${TEST_DIR}/"
    
    # Source libraries for unit testing
    export SCRIPT_DIR="${TEST_DIR}"
    export CONFIG_DIR="${SYNC_BASE_DIR}/config"
    export LOGS_DIR="${SYNC_BASE_DIR}/logs"
    
    mkdir -p "$CONFIG_DIR" "$LOGS_DIR"
    
    # Silence logging in tests unless verbose
    if [[ "$VERBOSE" != "true" ]]; then
        export QUIET="true"
    fi
}

# Teardown test environment (called after each test file)
teardown_test_env() {
    if [[ -d "${TEST_DIR:-}" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# Run a single test function
run_test() {
    local test_name="$1"
    local test_func="$2"
    
    ((TESTS_RUN++))
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "  ${CYAN}RUN${RESET}  $test_name"
    fi
    
    # Run test in subshell to isolate failures
    local test_output
    local test_exit_code
    
    set +e
    test_output=$("$test_func" 2>&1)
    test_exit_code=$?
    set -e
    
    if [[ $test_exit_code -eq 0 ]]; then
        ((TESTS_PASSED++))
        echo -e "  ${GREEN}PASS${RESET} $test_name"
    elif [[ $test_exit_code -eq 77 ]]; then
        ((TESTS_SKIPPED++))
        echo -e "  ${YELLOW}SKIP${RESET} $test_name"
    else
        ((TESTS_FAILED++))
        echo -e "  ${RED}FAIL${RESET} $test_name"
        if [[ -n "$test_output" ]]; then
            echo "$test_output" | sed 's/^/       /'
        fi
    fi
}

# Run all tests in a file
run_test_file() {
    local test_file="$1"
    local test_name
    test_name=$(basename "$test_file" .sh)
    
    echo -e "\n${BOLD}${test_name}${RESET}"
    echo "─────────────────────────────────────────"
    
    # Setup
    setup_test_env
    
    # Source the test file
    source "$test_file"
    
    # Find and run all test_* functions
    local funcs
    funcs=$(declare -F | awk '{print $3}' | grep '^test_' || true)
    
    for func in $funcs; do
        # Apply filter if specified
        if [[ -n "$TEST_FILTER" && "$func" != *"$TEST_FILTER"* ]]; then
            continue
        fi
        run_test "$func" "$func"
    done
    
    # Teardown
    teardown_test_env
    
    # Unset test functions to avoid pollution
    for func in $funcs; do
        unset -f "$func" 2>/dev/null || true
    done
}

# Run all tests in a directory
run_test_suite() {
    local suite_dir="$1"
    local suite_name
    suite_name=$(basename "$suite_dir")
    
    echo -e "\n${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${MAGENTA}  ${suite_name^^} TESTS${RESET}"
    echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════${RESET}"
    
    if [[ ! -d "$suite_dir" ]]; then
        echo -e "${YELLOW}  No tests found in $suite_dir${RESET}"
        return
    fi
    
    local test_files
    test_files=$(find "$suite_dir" -name "test_*.sh" -type f | sort)
    
    if [[ -z "$test_files" ]]; then
        echo -e "${YELLOW}  No test files found${RESET}"
        return
    fi
    
    for test_file in $test_files; do
        run_test_file "$test_file"
    done
}

# Print test summary
print_summary() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  TEST SUMMARY${RESET}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
    echo ""
    echo -e "  Total:   ${TESTS_RUN}"
    echo -e "  ${GREEN}Passed:  ${TESTS_PASSED}${RESET}"
    echo -e "  ${RED}Failed:  ${TESTS_FAILED}${RESET}"
    echo -e "  ${YELLOW}Skipped: ${TESTS_SKIPPED}${RESET}"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}  All tests passed!${RESET}"
    else
        echo -e "${RED}${BOLD}  Some tests failed.${RESET}"
    fi
    echo ""
}

#===============================================================================
# ARGUMENT PARSING
#===============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            unit|integration|e2e)
                TEST_FILTER="$1"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -f|--filter)
                TEST_FILTER="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [unit|integration|e2e] [--verbose] [--filter PATTERN]"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

#===============================================================================
# MAIN
#===============================================================================
main() {
    parse_args "$@"
    
    echo ""
    echo -e "${BOLD}╔═══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║           SYNC SHUTTLE TEST SUITE                         ║${RESET}"
    echo -e "${BOLD}╚═══════════════════════════════════════════════════════════╝${RESET}"
    
    # Create temp directory
    mkdir -p "$TEST_TMP_DIR"
    
    # Run test suites
    if [[ -z "$TEST_FILTER" || "$TEST_FILTER" == "unit" ]]; then
        run_test_suite "${SCRIPT_DIR}/unit"
    fi
    
    if [[ -z "$TEST_FILTER" || "$TEST_FILTER" == "integration" ]]; then
        run_test_suite "${SCRIPT_DIR}/integration"
    fi
    
    if [[ -z "$TEST_FILTER" || "$TEST_FILTER" == "e2e" ]]; then
        run_test_suite "${SCRIPT_DIR}/e2e"
    fi
    
    # Cleanup temp directory
    rm -rf "$TEST_TMP_DIR"
    
    # Print summary
    print_summary
    
    # Exit with failure if any tests failed
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
