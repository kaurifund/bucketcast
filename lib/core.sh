#!/usr/bin/env bash
#===============================================================================
# SYNC SHUTTLE - CORE LIBRARY
#===============================================================================
# Provides core utility functions and server management.
#
# Functions:
#   generate_uuid()       - Generate UUIDv4 for operation tracking
#   get_server_config()   - Load server configuration
#   list_all_servers()    - List all configured servers
#   resolve_path()        - Resolve relative paths
#===============================================================================

#===============================================================================
# GENERATE: UUID for operation tracking
#===============================================================================
generate_uuid() {
    local uuid
    
    if command -v uuidgen &> /dev/null; then
        uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        uuid=$(cat /proc/sys/kernel/random/uuid)
    else
        # Fallback: generate pseudo-random UUID
        uuid=$(printf '%04x%04x-%04x-%04x-%04x-%04x%04x%04x' \
            $((RANDOM)) $((RANDOM)) \
            $((RANDOM)) \
            $(((RANDOM & 0x0fff) | 0x4000)) \
            $(((RANDOM & 0x3fff) | 0x8000)) \
            $((RANDOM)) $((RANDOM)) $((RANDOM)))
    fi
    
    echo "$uuid"
}

#===============================================================================
# GET: Server configuration by ID
# Outputs variables that can be eval'd: server_host, server_port, etc.
#===============================================================================
get_server_config() {
    local server_id="$1"
    local servers_file="${CONFIG_DIR}/servers.conf"
    
    # Validate server ID format
    if ! validate_server_id "$server_id"; then
        return 1
    fi
    
    # Check servers file exists
    if [[ ! -f "$servers_file" ]]; then
        log_error "Servers configuration not found: $servers_file"
        return 1
    fi
    
    # Source the servers file
    source "$servers_file"
    
    # Check if server array exists
    local array_name="server_${server_id//-/_}"
    
    # Use nameref if available (bash 4.3+)
    if [[ "${BASH_VERSINFO[0]}" -ge 4 && "${BASH_VERSINFO[1]}" -ge 3 ]]; then
        local -n server_ref="$array_name" 2>/dev/null || {
            log_error "Server not found: $server_id"
            return 1
        }
        
        # Check if enabled
        if [[ "${server_ref[enabled]:-false}" != "true" ]]; then
            log_error "Server is disabled: $server_id"
            return 1
        fi
        
        # Output variables for eval
        echo "server_name='${server_ref[name]:-$server_id}'"
        echo "server_host='${server_ref[host]:-}'"
        echo "server_port='${server_ref[port]:-22}'"
        echo "server_user='${server_ref[user]:-}'"
        echo "server_identity_file='${server_ref[identity_file]:-}'"
        echo "server_remote_base='${server_ref[remote_base]:-}'"
        echo "server_s3_backup='${server_ref[s3_backup]:-false}'"
    else
        # Fallback for older bash
        log_error "Bash 4.3+ required for server configuration"
        return 1
    fi
    
    return 0
}

#===============================================================================
# LIST: All configured servers
#===============================================================================
list_all_servers() {
    local servers_file="${CONFIG_DIR}/servers.conf"
    
    if [[ ! -f "$servers_file" ]]; then
        return 1
    fi
    
    # Source servers config
    source "$servers_file"
    
    # Find all server_* arrays
    local servers=()
    for var in $(compgen -A variable | grep '^server_'); do
        local server_id="${var#server_}"
        servers+=("$server_id")
    done
    
    printf '%s\n' "${servers[@]}"
}

#===============================================================================
# RESOLVE: Path to absolute
#===============================================================================
resolve_path() {
    local path="$1"
    local base_dir="${2:-$(pwd)}"
    
    # If already absolute, just clean it
    if [[ "$path" == /* ]]; then
        echo "$path"
        return 0
    fi
    
    # Expand ~
    if [[ "$path" == ~* ]]; then
        path="${path/#\~/$HOME}"
    fi
    
    # Make relative path absolute
    if [[ -e "$path" ]]; then
        cd "$(dirname "$path")" && pwd -P
        return 0
    fi
    
    # Path doesn't exist, resolve based on base_dir
    echo "${base_dir}/${path}"
}

#===============================================================================
# ENSURE: Directory exists (create if needed)
#===============================================================================
ensure_directory() {
    local dir_path="$1"
    
    if [[ ! -d "$dir_path" ]]; then
        if ! mkdir -p "$dir_path" 2>/dev/null; then
            log_error "Cannot create directory: $dir_path"
            return 1
        fi
        log_debug "Created directory: $dir_path"
    fi
    
    return 0
}

#===============================================================================
# CLEANUP: Old archives based on retention policy
#===============================================================================
cleanup_old_archives() {
    local retention_days="${ARCHIVE_RETENTION_DAYS:-30}"
    
    if [[ "$retention_days" -eq 0 ]]; then
        log_debug "Archive retention disabled (set to 0)"
        return 0
    fi
    
    if [[ ! -d "$ARCHIVE_DIR" ]]; then
        return 0
    fi
    
    log_debug "Cleaning archives older than $retention_days days"
    
    # Find and remove old archive directories
    find "$ARCHIVE_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"$retention_days" | while read -r old_dir; do
        log_debug "Removing old archive: $old_dir"
        # Note: We're intentionally using safe removal here
        # Only removes if it's within ARCHIVE_DIR
        if [[ "$old_dir" == "$ARCHIVE_DIR"/* ]]; then
            rm -r "$old_dir"
        fi
    done
}

#===============================================================================
# CALCULATE: Human readable size
#===============================================================================
human_readable_size() {
    local bytes="$1"
    
    if command -v numfmt &> /dev/null; then
        numfmt --to=iec "$bytes"
    else
        # Fallback calculation
        if [[ $bytes -lt 1024 ]]; then
            echo "${bytes}B"
        elif [[ $bytes -lt 1048576 ]]; then
            echo "$((bytes / 1024))K"
        elif [[ $bytes -lt 1073741824 ]]; then
            echo "$((bytes / 1048576))M"
        else
            echo "$((bytes / 1073741824))G"
        fi
    fi
}

#===============================================================================
# GET: File checksum
#===============================================================================
get_file_checksum() {
    local file_path="$1"
    local algorithm="${2:-sha256}"
    
    case "$algorithm" in
        sha256)
            if command -v sha256sum &> /dev/null; then
                sha256sum "$file_path" | cut -d' ' -f1
            elif command -v shasum &> /dev/null; then
                shasum -a 256 "$file_path" | cut -d' ' -f1
            else
                log_warn "No SHA256 tool available"
                echo ""
            fi
            ;;
        md5)
            if command -v md5sum &> /dev/null; then
                md5sum "$file_path" | cut -d' ' -f1
            elif command -v md5 &> /dev/null; then
                md5 -q "$file_path"
            else
                log_warn "No MD5 tool available"
                echo ""
            fi
            ;;
        *)
            log_error "Unknown checksum algorithm: $algorithm"
            echo ""
            ;;
    esac
}

#===============================================================================
# LOCK: Acquire operation lock
#===============================================================================
acquire_lock() {
    local lock_name="${1:-default}"
    local lock_file="${TMP_DIR}/${lock_name}.lock"
    local lock_timeout="${2:-30}"
    
    ensure_directory "$TMP_DIR"
    
    # Check for stale lock
    if [[ -f "$lock_file" ]]; then
        local lock_pid
        lock_pid=$(cat "$lock_file" 2>/dev/null)
        
        if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            log_debug "Removing stale lock file"
            rm -f "$lock_file"
        else
            log_error "Another operation is in progress (PID: $lock_pid)"
            return 1
        fi
    fi
    
    # Create lock file
    echo $$ > "$lock_file"
    log_debug "Acquired lock: $lock_name"
    
    return 0
}

#===============================================================================
# LOCK: Release operation lock
#===============================================================================
release_lock() {
    local lock_name="${1:-default}"
    local lock_file="${TMP_DIR}/${lock_name}.lock"
    
    if [[ -f "$lock_file" ]]; then
        rm -f "$lock_file"
        log_debug "Released lock: $lock_name"
    fi
}

#===============================================================================
# TRAP: Cleanup on exit
#===============================================================================
cleanup_on_exit() {
    local exit_code=$?
    
    # Release any locks
    release_lock "sync-shuttle"
    
    # Clean up temp files
    if [[ -d "$TMP_DIR" ]]; then
        find "$TMP_DIR" -maxdepth 1 -type f -name "*.tmp" -mmin +60 -delete 2>/dev/null || true
    fi
    
    exit $exit_code
}

# Set up exit trap
trap cleanup_on_exit EXIT

#===============================================================================
# PROMPT: Yes/No confirmation
#===============================================================================
confirm_action() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"
    
    if [[ ! -t 0 ]]; then
        # Non-interactive: use default
        [[ "$default" == "y" ]]
        return $?
    fi
    
    local yn_prompt
    if [[ "$default" == "y" ]]; then
        yn_prompt="[Y/n]"
    else
        yn_prompt="[y/N]"
    fi
    
    read -rp "$prompt $yn_prompt: " response
    
    case "${response,,}" in
        y|yes) return 0 ;;
        n|no) return 1 ;;
        "") [[ "$default" == "y" ]] && return 0 || return 1 ;;
        *) return 1 ;;
    esac
}

#===============================================================================
# SANITIZE: String for use in filenames
#===============================================================================
sanitize_filename() {
    local input="$1"
    
    # Replace dangerous characters with underscores
    echo "$input" | tr -cs '[:alnum:]._-' '_' | sed 's/_\+/_/g; s/^_//; s/_$//'
}

#===============================================================================
# FORMAT: Duration in human readable form
#===============================================================================
format_duration() {
    local seconds="$1"
    
    if [[ $seconds -lt 60 ]]; then
        echo "${seconds}s"
    elif [[ $seconds -lt 3600 ]]; then
        local mins=$((seconds / 60))
        local secs=$((seconds % 60))
        echo "${mins}m ${secs}s"
    else
        local hours=$((seconds / 3600))
        local mins=$(((seconds % 3600) / 60))
        echo "${hours}h ${mins}m"
    fi
}
