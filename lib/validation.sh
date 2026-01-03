#!/usr/bin/env bash
#===============================================================================
# SYNC SHUTTLE - VALIDATION LIBRARY
#===============================================================================
# Provides validation and safety check functions to ensure operations
# are secure and within expected parameters.
#
# Functions:
#   validate_environment()          - Check required tools exist
#   validate_path_within_sandbox()  - Security: path containment check
#   validate_remote_base()          - Security: remote path safety check
#   validate_server_id()            - Validate server ID format
#   validate_source_path()          - Validate source exists and is readable
#   check_file_collision()          - Check for existing files
#   validate_transfer_size()        - Check against size limits
#===============================================================================

#===============================================================================
# REQUIRED TOOLS
#===============================================================================
readonly REQUIRED_TOOLS=(
    "rsync"
    "ssh"
    "date"
)

readonly OPTIONAL_TOOLS=(
    "uuidgen"
    "jq"
    "tree"
)

#===============================================================================
# VALIDATE: Environment and dependencies
#===============================================================================
validate_environment() {
    log_debug "Validating environment..."
    
    # Check Bash version
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        log_error "Bash 4.0 or higher is required (found: ${BASH_VERSION})"
        exit 8
    fi
    
    # Check required tools
    local missing_tools=()
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools and try again."
        exit 8
    fi
    
    # Check optional tools and warn
    for tool in "${OPTIONAL_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_debug "Optional tool not found: $tool (some features may be limited)"
        fi
    done
    
    # Check sync-shuttle directory exists
    if [[ ! -d "$SYNC_BASE_DIR" ]]; then
        log_error "Sync Shuttle not initialized"
        echo "Run '$SCRIPT_NAME init' first."
        exit 3
    fi
    
    # Check config directory exists
    if [[ ! -d "$CONFIG_DIR" ]]; then
        log_error "Configuration directory not found: $CONFIG_DIR"
        echo "Run '$SCRIPT_NAME init' to create it."
        exit 3
    fi
    
    log_debug "Environment validation passed"
    return 0
}

#===============================================================================
# VALIDATE: Path is within sandbox
# This is a CRITICAL security function that prevents path traversal attacks
#===============================================================================
validate_path_within_sandbox() {
    local path_to_check="$1"
    local sandbox="${SYNC_BASE_DIR}"

    # Resolve to absolute path
    local resolved_path
    local dir_part
    dir_part=$(dirname "$path_to_check")

    if [[ -d "$dir_part" ]]; then
        # Directory exists, resolve it
        resolved_path=$(cd "$dir_part" && pwd)/$(basename "$path_to_check")
    elif [[ "$path_to_check" == /* ]]; then
        # Already absolute, use as-is
        resolved_path="$path_to_check"
    else
        # Relative path, make absolute
        resolved_path="$(pwd)/$path_to_check"
    fi
    
    # Resolve sandbox to absolute path
    local resolved_sandbox
    resolved_sandbox=$(cd "$sandbox" 2>/dev/null && pwd) || {
        log_error "Sandbox directory does not exist: $sandbox"
        return 1
    }
    
    # Check if path starts with sandbox (must be exact match or inside sandbox/)
    # Using trailing slash to prevent /home/user/.sync-shuttleFAKE from matching
    if [[ "$resolved_path" != "$resolved_sandbox" && "$resolved_path" != "$resolved_sandbox"/* ]]; then
        log_error "Security violation: Path is outside sandbox"
        log_error "  Path:    $resolved_path"
        log_error "  Sandbox: $resolved_sandbox"
        return 1
    fi
    
    # Additional checks for suspicious patterns
    if [[ "$path_to_check" == *".."* ]]; then
        log_error "Security violation: Path contains '..' sequence"
        return 1
    fi
    
    log_debug "Path validation passed: $path_to_check"
    return 0
}

#===============================================================================
# VALIDATE: Remote base path is safe
# Prevents dangerous remote paths that could damage the remote system
#===============================================================================
validate_remote_base() {
    local remote_base="$1"
    local server_id="$2"

    # Check not empty
    if [[ -z "$remote_base" ]]; then
        log_error "Server '$server_id': remote_base cannot be empty"
        return 1
    fi

    # Must be absolute path
    if [[ "$remote_base" != /* ]]; then
        log_error "Server '$server_id': remote_base must be an absolute path (got: $remote_base)"
        return 1
    fi

    # Check for path traversal
    if [[ "$remote_base" == *".."* ]]; then
        log_error "Server '$server_id': remote_base cannot contain '..'"
        return 1
    fi

    # Block dangerous system paths
    local blocked_paths=(
        "/etc"
        "/bin"
        "/sbin"
        "/usr"
        "/lib"
        "/lib64"
        "/boot"
        "/dev"
        "/proc"
        "/sys"
        "/var"
        "/root"
        "/tmp"
    )

    for blocked in "${blocked_paths[@]}"; do
        if [[ "$remote_base" == "$blocked" || "$remote_base" == "$blocked"/* ]]; then
            log_error "Server '$server_id': remote_base cannot be in system directory: $blocked"
            return 1
        fi
    done

    # Warn if not in a home directory (but allow it)
    if [[ "$remote_base" != /home/* && "$remote_base" != /Users/* ]]; then
        log_warn "Server '$server_id': remote_base is not in a home directory: $remote_base"
    fi

    log_debug "Remote base validation passed: $remote_base"
    return 0
}

#===============================================================================
# VALIDATE: Server ID format
#===============================================================================
validate_server_id() {
    local server_id="$1"
    
    # Check length (3-32 characters)
    if [[ ${#server_id} -lt 3 || ${#server_id} -gt 32 ]]; then
        log_error "Server ID must be 3-32 characters: $server_id"
        return 1
    fi
    
    # Check format (lowercase alphanumeric and dashes only)
    if [[ ! "$server_id" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ && ! "$server_id" =~ ^[a-z0-9]{3,}$ ]]; then
        log_error "Server ID must be lowercase alphanumeric with optional dashes: $server_id"
        return 1
    fi
    
    # No consecutive dashes
    if [[ "$server_id" == *"--"* ]]; then
        log_error "Server ID cannot contain consecutive dashes: $server_id"
        return 1
    fi
    
    return 0
}

#===============================================================================
# VALIDATE: Source path exists and is readable
#===============================================================================
validate_source_path() {
    local source_path="$1"
    
    if [[ ! -e "$source_path" ]]; then
        log_error "Source path does not exist: $source_path"
        return 1
    fi
    
    if [[ ! -r "$source_path" ]]; then
        log_error "Source path is not readable: $source_path"
        return 1
    fi
    
    # If it's a symlink, resolve and check
    if [[ -L "$source_path" ]]; then
        local resolved
        resolved=$(readlink -f "$source_path")
        if [[ ! -e "$resolved" ]]; then
            log_error "Source symlink points to non-existent path: $resolved"
            return 1
        fi
        log_debug "Source is symlink, resolved to: $resolved"
    fi
    
    return 0
}

#===============================================================================
# CHECK: File collision (existing file at destination)
#===============================================================================
check_file_collision() {
    local dest_path="$1"
    local source_path="${2:-}"
    
    if [[ ! -e "$dest_path" ]]; then
        log_debug "No collision: destination does not exist"
        return 0
    fi
    
    log_debug "Collision detected: $dest_path exists"
    
    if [[ "${FORCE:-false}" != "true" ]]; then
        log_warn "File already exists: $dest_path"
        log_warn "Use --force to overwrite (will prompt for confirmation)"
        return 1
    fi
    
    # Force mode: prompt for confirmation
    if [[ -t 0 ]]; then
        echo ""
        echo -e "${YELLOW}WARNING:${RESET} File already exists:"
        echo "  Destination: $dest_path"
        if [[ -n "$source_path" ]]; then
            echo "  Source:      $source_path"
        fi
        echo ""
        
        # Show file comparison
        if [[ -f "$dest_path" ]]; then
            local dest_size dest_mod
            dest_size=$(stat -c %s "$dest_path" 2>/dev/null || stat -f %z "$dest_path" 2>/dev/null)
            dest_mod=$(stat -c %y "$dest_path" 2>/dev/null || stat -f %Sm "$dest_path" 2>/dev/null)
            echo "  Existing file: $dest_size bytes, modified $dest_mod"
        fi
        
        if [[ -n "$source_path" && -f "$source_path" ]]; then
            local src_size src_mod
            src_size=$(stat -c %s "$source_path" 2>/dev/null || stat -f %z "$source_path" 2>/dev/null)
            src_mod=$(stat -c %y "$source_path" 2>/dev/null || stat -f %Sm "$source_path" 2>/dev/null)
            echo "  New file:      $src_size bytes, modified $src_mod"
        fi
        
        echo ""
        read -rp "Overwrite? (existing file will be archived) [y/N]: " confirm
        
        if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
            log_info "User cancelled overwrite"
            return 1
        fi
        
        # Archive the existing file
        archive_file "$dest_path"
    else
        # Non-interactive mode with --force: archive and continue
        log_warn "Non-interactive mode with --force: archiving existing file"
        archive_file "$dest_path"
    fi
    
    return 0
}

#===============================================================================
# ARCHIVE: Backup file before overwrite
#===============================================================================
archive_file() {
    local file_path="$1"
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    
    local archive_subdir="${ARCHIVE_DIR}/${timestamp}"
    local relative_path="${file_path#$SYNC_BASE_DIR/}"
    local archive_path="${archive_subdir}/${relative_path}"
    
    # Create archive directory structure
    mkdir -p "$(dirname "$archive_path")"
    
    # Copy file to archive (preserving attributes)
    if cp -p "$file_path" "$archive_path" 2>/dev/null; then
        log_info "Archived to: ${archive_path#$SYNC_BASE_DIR/}"
    else
        log_error "Failed to archive file: $file_path"
        return 1
    fi
    
    return 0
}

#===============================================================================
# VALIDATE: Transfer size
#===============================================================================
validate_transfer_size() {
    local path="$1"
    local max_size="${MAX_TRANSFER_SIZE:-10G}"
    
    # Convert max size to bytes
    local max_bytes
    case "${max_size: -1}" in
        G|g) max_bytes=$(( ${max_size%?} * 1024 * 1024 * 1024 )) ;;
        M|m) max_bytes=$(( ${max_size%?} * 1024 * 1024 )) ;;
        K|k) max_bytes=$(( ${max_size%?} * 1024 )) ;;
        *)   max_bytes=$max_size ;;
    esac
    
    # Calculate actual size
    local actual_size
    if [[ -d "$path" ]]; then
        actual_size=$(du -sb "$path" 2>/dev/null | cut -f1)
    else
        actual_size=$(stat -c %s "$path" 2>/dev/null || stat -f %z "$path" 2>/dev/null)
    fi
    
    if [[ -z "$actual_size" ]]; then
        log_warn "Could not determine size of: $path"
        return 0
    fi
    
    if [[ $actual_size -gt $max_bytes ]]; then
        local human_size
        human_size=$(numfmt --to=iec "$actual_size" 2>/dev/null || echo "$actual_size bytes")
        log_error "Transfer size ($human_size) exceeds maximum ($max_size)"
        return 1
    fi
    
    log_debug "Transfer size OK: $(numfmt --to=iec "$actual_size" 2>/dev/null || echo "$actual_size") / $max_size"
    return 0
}

#===============================================================================
# VALIDATE: SSH connectivity to server
#===============================================================================
validate_ssh_connection() {
    local host="$1"
    local port="${2:-22}"
    local user="$3"
    local timeout=5
    
    log_debug "Testing SSH connection to $user@$host:$port"
    
    if ssh -o ConnectTimeout="$timeout" \
           -o BatchMode=yes \
           -o StrictHostKeyChecking=accept-new \
           -p "$port" \
           "${user}@${host}" \
           "echo OK" &>/dev/null; then
        log_debug "SSH connection successful"
        return 0
    else
        log_error "Cannot connect to $user@$host:$port"
        log_error "Ensure SSH key authentication is set up"
        return 1
    fi
}

#===============================================================================
# PREFLIGHT: Push operation checks
#===============================================================================
preflight_push() {
    local source="$1"
    local dest="$2"
    
    log_debug "Running preflight checks for push..."
    
    # Validate source
    if ! validate_source_path "$source"; then
        exit 5
    fi
    
    # Validate destination is within sandbox
    if ! validate_path_within_sandbox "$dest"; then
        exit 4
    fi
    
    # Check transfer size
    if ! validate_transfer_size "$source"; then
        exit 5
    fi
    
    log_debug "Preflight checks passed"
    return 0
}

#===============================================================================
# PREFLIGHT: Pull operation checks
#===============================================================================
preflight_pull() {
    local dest="$1"
    
    log_debug "Running preflight checks for pull..."
    
    # Validate destination is within sandbox
    if ! validate_path_within_sandbox "$dest"; then
        exit 4
    fi
    
    log_debug "Preflight checks passed"
    return 0
}
