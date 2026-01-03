#!/usr/bin/env bash
#===============================================================================
# SYNC SHUTTLE - LOGGING LIBRARY
#===============================================================================
# Provides structured logging functions for both human-readable and
# machine-readable (JSON) output.
#
# Functions:
#   log_debug()     - Debug level messages (only with VERBOSE)
#   log_info()      - Informational messages
#   log_warn()      - Warning messages
#   log_error()     - Error messages
#   log_success()   - Success messages (green)
#   log_operation() - Structured JSON operation log
#   log_to_file()   - Append to log files
#===============================================================================

#===============================================================================
# LOG LEVEL CONSTANTS
#===============================================================================
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

#===============================================================================
# HELPER: Get numeric log level
#===============================================================================
get_log_level_num() {
    case "${LOG_LEVEL:-INFO}" in
        DEBUG) echo $LOG_LEVEL_DEBUG ;;
        INFO)  echo $LOG_LEVEL_INFO ;;
        WARN)  echo $LOG_LEVEL_WARN ;;
        ERROR) echo $LOG_LEVEL_ERROR ;;
        *)     echo $LOG_LEVEL_INFO ;;
    esac
}

#===============================================================================
# HELPER: Get ISO 8601 timestamp
#===============================================================================
get_iso_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

#===============================================================================
# HELPER: Format log message
#===============================================================================
format_log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    echo "[$timestamp] [$level] $message"
}

#===============================================================================
# LOG: Debug
#===============================================================================
log_debug() {
    local message="$1"
    local current_level
    current_level=$(get_log_level_num)
    
    if [[ $current_level -le $LOG_LEVEL_DEBUG ]]; then
        echo -e "${CYAN}[DEBUG]${RESET} $message" >&2
        log_to_file "DEBUG" "$message"
    fi
}

#===============================================================================
# LOG: Info
#===============================================================================
log_info() {
    local message="$1"
    local current_level
    current_level=$(get_log_level_num)
    
    if [[ $current_level -le $LOG_LEVEL_INFO ]]; then
        if [[ "${QUIET:-false}" != "true" ]]; then
            echo -e "${BLUE}[INFO]${RESET} $message"
        fi
        log_to_file "INFO" "$message"
    fi
}

#===============================================================================
# LOG: Warning
#===============================================================================
log_warn() {
    local message="$1"
    local current_level
    current_level=$(get_log_level_num)
    
    if [[ $current_level -le $LOG_LEVEL_WARN ]]; then
        echo -e "${YELLOW}[WARN]${RESET} $message" >&2
        log_to_file "WARN" "$message"
    fi
}

#===============================================================================
# LOG: Error
#===============================================================================
log_error() {
    local message="$1"
    
    echo -e "${RED}[ERROR]${RESET} $message" >&2
    log_to_file "ERROR" "$message"
}

#===============================================================================
# LOG: Success
#===============================================================================
log_success() {
    local message="$1"
    
    if [[ "${QUIET:-false}" != "true" ]]; then
        echo -e "${GREEN}[SUCCESS]${RESET} $message"
    fi
    log_to_file "SUCCESS" "$message"
}

#===============================================================================
# LOG: Write to file
#===============================================================================
log_to_file() {
    local level="$1"
    local message="$2"
    
    # Only write to file if log directory exists
    if [[ -n "${LOG_FILE:-}" && -d "$(dirname "$LOG_FILE")" ]]; then
        local formatted
        formatted=$(format_log_message "$level" "$message")
        echo "$formatted" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

#===============================================================================
# LOG: Structured operation log (JSON)
#===============================================================================
log_operation() {
    local uuid="$1"
    local operation="$2"
    local server_id="$3"
    local source_path="$4"
    local dest_path="$5"
    local timestamp_start="$6"
    local timestamp_end="$7"
    local status="$8"
    local bytes="${9:-0}"
    local error_message="${10:-}"
    
    # Only write if log file is configured
    if [[ -z "${LOG_JSON_FILE:-}" || ! -d "$(dirname "$LOG_JSON_FILE")" ]]; then
        return 0
    fi
    
    # Build JSON manually (avoids jq dependency for writing)
    local json_entry
    json_entry=$(cat << JSONEOF
{"uuid":"${uuid}","operation":"${operation}","server_id":"${server_id}","source_path":"${source_path//\"/\\\"}","dest_path":"${dest_path//\"/\\\"}","timestamp_start":"${timestamp_start}","timestamp_end":"${timestamp_end}","status":"${status}","bytes_transferred":${bytes},"error_message":"${error_message//\"/\\\"}","dry_run":${DRY_RUN:-false},"force":${FORCE:-false}}
JSONEOF
)
    
    echo "$json_entry" >> "$LOG_JSON_FILE" 2>/dev/null || true
}

#===============================================================================
# LOG: Print separator line
#===============================================================================
log_separator() {
    if [[ "${QUIET:-false}" != "true" ]]; then
        echo "─────────────────────────────────────────────────────────"
    fi
}

#===============================================================================
# LOG: Print header
#===============================================================================
log_header() {
    local title="$1"
    
    if [[ "${QUIET:-false}" != "true" ]]; then
        echo ""
        echo "${BOLD}${title}${RESET}"
        log_separator
    fi
}

#===============================================================================
# LOG: Progress indicator
#===============================================================================
log_progress() {
    local current="$1"
    local total="$2"
    local message="${3:-Processing}"
    
    if [[ "${QUIET:-false}" != "true" && -t 1 ]]; then
        local percent=$((current * 100 / total))
        local bar_width=30
        local filled=$((percent * bar_width / 100))
        local empty=$((bar_width - filled))
        
        printf "\r${CYAN}[%-${bar_width}s]${RESET} %3d%% %s" \
            "$(printf '%*s' "$filled" '' | tr ' ' '#')$(printf '%*s' "$empty" '')" \
            "$percent" \
            "$message"
        
        if [[ $current -eq $total ]]; then
            echo ""
        fi
    fi
}

#===============================================================================
# LOG: Dry run notice
#===============================================================================
log_dry_run_notice() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════╗${RESET}"
        echo -e "${YELLOW}║${RESET}  ${BOLD}DRY RUN MODE${RESET} - No changes will be made             ${YELLOW}║${RESET}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════╝${RESET}"
        echo ""
    fi
}
