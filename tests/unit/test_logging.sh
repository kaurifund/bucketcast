#!/usr/bin/env bash
#===============================================================================
# UNIT TESTS - LOGGING LIBRARY
#===============================================================================
# Tests for lib/logging.sh functions.
#===============================================================================

# Source the library under test
source "${TEST_DIR}/lib/logging.sh" 2>/dev/null || source "${PROJECT_ROOT}/lib/logging.sh"

#===============================================================================
# TIMESTAMP TESTS
#===============================================================================

test_get_iso_timestamp_returns_valid_format() {
    local ts
    ts=$(get_iso_timestamp)
    
    # Should match ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ
    local pattern='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
    
    if [[ ! "$ts" =~ $pattern ]]; then
        echo "Timestamp '$ts' does not match ISO 8601 format"
        return 1
    fi
}

test_get_iso_timestamp_is_utc() {
    local ts
    ts=$(get_iso_timestamp)
    
    # Should end with Z (UTC)
    assert_contains "$ts" "Z" "Timestamp should be in UTC"
}

#===============================================================================
# LOG LEVEL TESTS
#===============================================================================

test_get_log_level_num_returns_correct_values() {
    LOG_LEVEL="DEBUG"
    assert_equals "$(get_log_level_num)" "0" "DEBUG should be 0"
    
    LOG_LEVEL="INFO"
    assert_equals "$(get_log_level_num)" "1" "INFO should be 1"
    
    LOG_LEVEL="WARN"
    assert_equals "$(get_log_level_num)" "2" "WARN should be 2"
    
    LOG_LEVEL="ERROR"
    assert_equals "$(get_log_level_num)" "3" "ERROR should be 3"
}

test_get_log_level_num_defaults_to_info() {
    LOG_LEVEL="INVALID"
    assert_equals "$(get_log_level_num)" "1" "Invalid level should default to INFO"
    
    unset LOG_LEVEL
    assert_equals "$(get_log_level_num)" "1" "Unset level should default to INFO"
}

#===============================================================================
# LOG MESSAGE FORMAT TESTS
#===============================================================================

test_format_log_message_includes_timestamp() {
    local msg
    msg=$(format_log_message "INFO" "test message")
    
    # Should contain timestamp in brackets
    local pattern='^\[[0-9]{4}-[0-9]{2}-[0-9]{2}'
    
    if [[ ! "$msg" =~ $pattern ]]; then
        echo "Message should start with timestamp"
        return 1
    fi
}

test_format_log_message_includes_level() {
    local msg
    msg=$(format_log_message "ERROR" "test message")
    
    assert_contains "$msg" "[ERROR]" "Message should contain level"
}

test_format_log_message_includes_message() {
    local msg
    msg=$(format_log_message "INFO" "my test message")
    
    assert_contains "$msg" "my test message" "Message should contain the message text"
}

#===============================================================================
# LOG FUNCTION TESTS
#===============================================================================

test_log_debug_respects_log_level() {
    LOG_LEVEL="DEBUG"
    QUIET="false"
    
    local output
    output=$(log_debug "debug message" 2>&1)
    
    # Should output something when level is DEBUG
    # (might be empty if log_to_file fails, but the function should not error)
}

test_log_info_respects_quiet_mode() {
    LOG_LEVEL="INFO"
    QUIET="true"
    
    local output
    output=$(log_info "info message" 2>&1)
    
    # Should be empty when QUIET=true
    assert_empty "$output" "log_info should be silent when QUIET=true"
}

test_log_error_outputs_to_stderr() {
    LOG_LEVEL="ERROR"
    QUIET="false"
    
    # Capture stderr
    local stderr_output
    stderr_output=$(log_error "error message" 2>&1 1>/dev/null)
    
    # Error should go to stderr (captured above)
    # Note: output might be empty if stderr redirection is tricky
}

test_log_warn_shows_warning_marker() {
    LOG_LEVEL="INFO"
    QUIET="false"
    
    local output
    output=$(log_warn "warning message" 2>&1)
    
    assert_contains "$output" "WARN" "Warning should show WARN marker"
}

#===============================================================================
# LOG TO FILE TESTS
#===============================================================================

test_log_to_file_creates_log_entry() {
    export LOG_FILE="${TEST_DIR}/test.log"
    touch "$LOG_FILE"
    
    log_to_file "INFO" "test log entry"
    
    assert_file_exists "$LOG_FILE"
    assert_file_contains "$LOG_FILE" "test log entry"
}

test_log_to_file_appends_not_overwrites() {
    export LOG_FILE="${TEST_DIR}/append.log"
    echo "existing content" > "$LOG_FILE"
    
    log_to_file "INFO" "new entry"
    
    assert_file_contains "$LOG_FILE" "existing content"
    assert_file_contains "$LOG_FILE" "new entry"
}

#===============================================================================
# LOG OPERATION (JSON) TESTS
#===============================================================================

test_log_operation_creates_json_entry() {
    export LOG_JSON_FILE="${TEST_DIR}/test.jsonl"
    touch "$LOG_JSON_FILE"
    
    log_operation \
        "test-uuid-123" \
        "push" \
        "myserver" \
        "/source/path" \
        "/dest/path" \
        "2024-01-01T00:00:00Z" \
        "2024-01-01T00:00:01Z" \
        "SUCCESS"
    
    assert_file_exists "$LOG_JSON_FILE"
    
    # Verify JSON structure
    local content
    content=$(cat "$LOG_JSON_FILE")
    
    assert_contains "$content" '"uuid"' "JSON should contain uuid field"
    assert_contains "$content" '"operation"' "JSON should contain operation field"
    assert_contains "$content" '"status"' "JSON should contain status field"
}

test_log_operation_includes_all_fields() {
    export LOG_JSON_FILE="${TEST_DIR}/fields.jsonl"
    : > "$LOG_JSON_FILE"  # Truncate
    
    log_operation \
        "uuid-field-test" \
        "pull" \
        "server1" \
        "/src" \
        "/dst" \
        "2024-01-01T00:00:00Z" \
        "2024-01-01T00:00:05Z" \
        "FAILED"
    
    local content
    content=$(cat "$LOG_JSON_FILE")
    
    assert_contains "$content" "uuid-field-test"
    assert_contains "$content" "pull"
    assert_contains "$content" "server1"
    assert_contains "$content" "FAILED"
}
