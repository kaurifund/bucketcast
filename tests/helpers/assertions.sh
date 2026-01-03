#!/usr/bin/env bash
#===============================================================================
# TEST HELPERS - ASSERTIONS
#===============================================================================
# Provides assertion functions for tests.
# All assertions are idempotent and have no side effects.
#
# Functions:
#   assert_equals VALUE EXPECTED [MESSAGE]
#   assert_not_equals VALUE UNEXPECTED [MESSAGE]
#   assert_true EXPRESSION [MESSAGE]
#   assert_false EXPRESSION [MESSAGE]
#   assert_empty VALUE [MESSAGE]
#   assert_not_empty VALUE [MESSAGE]
#   assert_contains STRING SUBSTRING [MESSAGE]
#   assert_not_contains STRING SUBSTRING [MESSAGE]
#   assert_file_exists PATH [MESSAGE]
#   assert_file_not_exists PATH [MESSAGE]
#   assert_dir_exists PATH [MESSAGE]
#   assert_exit_code EXPECTED COMMAND...
#   assert_output_contains SUBSTRING COMMAND...
#   skip_test MESSAGE
#===============================================================================

# Assertion failure handler
_assert_fail() {
    local message="${1:-Assertion failed}"
    echo "ASSERTION FAILED: $message" >&2
    return 1
}

# Assert two values are equal
assert_equals() {
    local actual="$1"
    local expected="$2"
    local message="${3:-Expected '$expected' but got '$actual'}"
    
    if [[ "$actual" != "$expected" ]]; then
        _assert_fail "$message"
    fi
}

# Assert two values are not equal
assert_not_equals() {
    local actual="$1"
    local unexpected="$2"
    local message="${3:-Expected value to not be '$unexpected'}"
    
    if [[ "$actual" == "$unexpected" ]]; then
        _assert_fail "$message"
    fi
}

# Assert expression is true (exit code 0)
assert_true() {
    local expression="$1"
    local message="${2:-Expected true but got false}"
    
    if ! eval "$expression" &>/dev/null; then
        _assert_fail "$message"
    fi
}

# Assert expression is false (exit code non-zero)
assert_false() {
    local expression="$1"
    local message="${2:-Expected false but got true}"
    
    if eval "$expression" &>/dev/null; then
        _assert_fail "$message"
    fi
}

# Assert value is empty
assert_empty() {
    local value="$1"
    local message="${2:-Expected empty but got '$value'}"
    
    if [[ -n "$value" ]]; then
        _assert_fail "$message"
    fi
}

# Assert value is not empty
assert_not_empty() {
    local value="$1"
    local message="${2:-Expected non-empty value}"
    
    if [[ -z "$value" ]]; then
        _assert_fail "$message"
    fi
}

# Assert string contains substring
assert_contains() {
    local string="$1"
    local substring="$2"
    local message="${3:-Expected '$string' to contain '$substring'}"
    
    if [[ "$string" != *"$substring"* ]]; then
        _assert_fail "$message"
    fi
}

# Assert string does not contain substring
assert_not_contains() {
    local string="$1"
    local substring="$2"
    local message="${3:-Expected '$string' to not contain '$substring'}"
    
    if [[ "$string" == *"$substring"* ]]; then
        _assert_fail "$message"
    fi
}

# Assert file exists
assert_file_exists() {
    local path="$1"
    local message="${2:-Expected file to exist: $path}"
    
    if [[ ! -f "$path" ]]; then
        _assert_fail "$message"
    fi
}

# Assert file does not exist
assert_file_not_exists() {
    local path="$1"
    local message="${2:-Expected file to not exist: $path}"
    
    if [[ -f "$path" ]]; then
        _assert_fail "$message"
    fi
}

# Assert directory exists
assert_dir_exists() {
    local path="$1"
    local message="${2:-Expected directory to exist: $path}"
    
    if [[ ! -d "$path" ]]; then
        _assert_fail "$message"
    fi
}

# Assert directory does not exist
assert_dir_not_exists() {
    local path="$1"
    local message="${2:-Expected directory to not exist: $path}"
    
    if [[ -d "$path" ]]; then
        _assert_fail "$message"
    fi
}

# Assert command exits with expected code
assert_exit_code() {
    local expected="$1"
    shift
    local cmd=("$@")
    local message="Expected exit code $expected from: ${cmd[*]}"
    
    local actual
    set +e
    "${cmd[@]}" &>/dev/null
    actual=$?
    set -e
    
    if [[ $actual -ne $expected ]]; then
        _assert_fail "$message (got $actual)"
    fi
}

# Assert command output contains string
assert_output_contains() {
    local substring="$1"
    shift
    local cmd=("$@")
    local message="Expected output to contain '$substring' from: ${cmd[*]}"
    
    local output
    set +e
    output=$("${cmd[@]}" 2>&1)
    set -e
    
    if [[ "$output" != *"$substring"* ]]; then
        _assert_fail "$message"
    fi
}

# Assert command output does not contain string
assert_output_not_contains() {
    local substring="$1"
    shift
    local cmd=("$@")
    local message="Expected output to not contain '$substring'"
    
    local output
    set +e
    output=$("${cmd[@]}" 2>&1)
    set -e
    
    if [[ "$output" == *"$substring"* ]]; then
        _assert_fail "$message"
    fi
}

# Assert file contains text
assert_file_contains() {
    local file="$1"
    local text="$2"
    local message="${3:-Expected file '$file' to contain '$text'}"
    
    if [[ ! -f "$file" ]]; then
        _assert_fail "File does not exist: $file"
    fi
    
    if ! grep -qF "$text" "$file"; then
        _assert_fail "$message"
    fi
}

# Assert file permissions
assert_file_permissions() {
    local file="$1"
    local expected="$2"
    local message="${3:-Expected permissions '$expected' on '$file'}"
    
    local actual
    actual=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%OLp" "$file" 2>/dev/null)
    
    if [[ "$actual" != "$expected" ]]; then
        _assert_fail "$message (got $actual)"
    fi
}

# Skip a test (exit code 77 is conventional for skip)
skip_test() {
    local reason="${1:-Test skipped}"
    echo "SKIPPED: $reason" >&2
    exit 77
}

# Skip test if command not available
skip_if_no_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        skip_test "Required command not found: $cmd"
    fi
}
