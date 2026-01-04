#!/usr/bin/env bash
#===============================================================================
# SYNC SHUTTLE - TRANSFER LIBRARY
#===============================================================================
# Provides file transfer functions using rsync and scp.
#
# Functions:
#   perform_rsync_push()   - Push files to local staging area
#   perform_rsync_pull()   - Pull files from remote
#   sync_to_remote()       - Sync local staging to remote server
#   sync_from_remote()     - Sync from remote server
#===============================================================================

#===============================================================================
# RSYNC: Base options (always applied)
#===============================================================================
readonly RSYNC_BASE_OPTIONS=(
    "--archive"           # Archive mode (preserves permissions, timestamps, etc.)
    "--compress"          # Compress during transfer
    "--partial"           # Keep partial files (for resume)
    "--human-readable"    # Human-readable output
    "--itemize-changes"   # Show what's changing
)

#===============================================================================
# RSYNC: Build command options
#===============================================================================
build_rsync_options() {
    local extra_options="${1:-}"
    
    local options=("${RSYNC_BASE_OPTIONS[@]}")
    
    # Add progress if verbose or not quiet
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        options+=("--verbose" "--progress")
    elif [[ "${QUIET:-false}" != "true" ]]; then
        options+=("--progress")
    fi
    
    # Add dry-run if specified
    if [[ "$extra_options" == *"--dry-run"* ]]; then
        options+=("--dry-run")
    fi
    
    # Add user-configured options
    if [[ -n "${RSYNC_OPTIONS:-}" ]]; then
        # Parse space-separated options
        read -ra user_opts <<< "$RSYNC_OPTIONS"
        options+=("${user_opts[@]}")
    fi
    
    # Never delete (safety)
    options+=("--ignore-existing" "--backup" "--backup-dir=.sync-shuttle-backup")
    
    printf '%s\n' "${options[@]}"
}

#===============================================================================
# RSYNC: Push files to local staging (before remote sync)
#===============================================================================
perform_rsync_push() {
    local source="$1"
    local dest="$2"
    local extra_options="${3:-}"
    
    log_debug "rsync push: $source -> $dest"
    
    # Build rsync command
    local -a rsync_opts
    mapfile -t rsync_opts < <(build_rsync_options "$extra_options")
    
    # Ensure destination exists
    if [[ "$extra_options" != *"--dry-run"* ]]; then
        ensure_directory "$dest"
    fi
    
    # Show dry-run notice
    if [[ "$extra_options" == *"--dry-run"* ]]; then
        log_dry_run_notice
    fi
    
    # Execute rsync
    log_info "Running rsync..."
    log_separator
    
    local rsync_exit_code
    if rsync "${rsync_opts[@]}" "$source" "$dest/"; then
        rsync_exit_code=0
    else
        rsync_exit_code=$?
    fi
    
    log_separator
    
    if [[ $rsync_exit_code -ne 0 ]]; then
        log_error "rsync failed with exit code: $rsync_exit_code"
        case $rsync_exit_code in
            1)  log_error "Syntax or usage error" ;;
            2)  log_error "Protocol incompatibility" ;;
            3)  log_error "Errors selecting input/output files" ;;
            10) log_error "Error in socket I/O" ;;
            11) log_error "Error in file I/O" ;;
            12) log_error "Error in rsync protocol data stream" ;;
            23) log_error "Partial transfer due to errors" ;;
            24) log_warn "Partial transfer due to vanished files (may be OK)" ;;
            *)  log_error "Unknown rsync error" ;;
        esac
        
        # Exit code 24 (vanished files) is often acceptable
        if [[ $rsync_exit_code -ne 24 ]]; then
            return $rsync_exit_code
        fi
    fi
    
    log_info "Local staging complete"
    return 0
}

#===============================================================================
# SYNC: To remote server
#===============================================================================
sync_to_remote() {
    local server_id="$1"
    local local_dir="$2"
    
    # Get server config
    local server_config
    if ! server_config=$(get_server_config "$server_id"); then
        log_error "Failed to get server configuration"
        return 1
    fi
    
    # Parse server config
    eval "$server_config"
    
    # Build SSH options (including identity file if specified)
    local ssh_opts="-p ${server_port} -o StrictHostKeyChecking=accept-new -o ConnectTimeout=${SSH_CONNECT_TIMEOUT:-10}"
    log_debug "Identity file from config: '${server_identity_file:-}'"
    if [[ -n "${server_identity_file:-}" ]]; then
        # Expand ~ in path
        local expanded_key="${server_identity_file/#\~/$HOME}"
        if [[ -f "$expanded_key" ]]; then
            ssh_opts+=" -i ${expanded_key}"
            log_debug "Using SSH key: ${expanded_key}"
        else
            log_warn "SSH key not found: ${server_identity_file}"
        fi
    fi
    
    # Validate SSH connection
    if ! validate_ssh_connection "$server_host" "$server_port" "$server_user" "$ssh_opts"; then
        log_error "SSH connection failed - skipping remote sync"
        return 1
    fi
    
    # Build remote destination path
    local remote_dest="${server_user}@${server_host}:${server_remote_base}/local/inbox/${HOSTNAME:-$(hostname)}/"
    
    log_info "Syncing to remote: $remote_dest"
    
    # Build rsync command
    local -a rsync_opts
    mapfile -t rsync_opts < <(build_rsync_options)
    
    # Add SSH options
    rsync_opts+=("-e" "ssh ${ssh_opts}")
    
    # Create remote directory first
    log_debug "Creating remote directory..."
    ssh ${ssh_opts} "${server_user}@${server_host}" \
        "mkdir -p '${server_remote_base}/local/inbox/${HOSTNAME:-$(hostname)}'" || {
        log_error "Failed to create remote directory"
        return 1
    }
    
    # Execute rsync to remote
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        rsync_opts+=("--dry-run")
        log_info "[DRY-RUN] Would sync to remote"
    fi
    
    log_separator
    
    if rsync "${rsync_opts[@]}" "$local_dir/" "$remote_dest"; then
        log_separator
        log_success "Remote sync complete"
        return 0
    else
        local exit_code=$?
        log_separator
        log_error "Remote sync failed with exit code: $exit_code"
        return $exit_code
    fi
}

#===============================================================================
# RSYNC: Pull files from remote
#===============================================================================
perform_rsync_pull() {
    local server_id="$1"
    local local_dest="$2"
    local extra_options="${3:-}"
    
    log_debug "rsync pull from server: $server_id"
    
    # Get server config
    local server_config
    if ! server_config=$(get_server_config "$server_id"); then
        log_error "Failed to get server configuration"
        return 1
    fi
    
    # Parse server config
    eval "$server_config"

    # Build SSH options (including identity file if specified)
    local ssh_opts="-p ${server_port} -o StrictHostKeyChecking=accept-new -o ConnectTimeout=${SSH_CONNECT_TIMEOUT:-10}"
    log_debug "Identity file from config: '${server_identity_file:-}'"
    if [[ -n "${server_identity_file:-}" ]]; then
        local expanded_key="${server_identity_file/#\~/$HOME}"
        if [[ -f "$expanded_key" ]]; then
            ssh_opts+=" -i ${expanded_key}"
            log_debug "Using SSH key: ${expanded_key}"
        else
            log_warn "SSH key not found: ${server_identity_file}"
        fi
    fi

    # Validate SSH connection
    if ! validate_ssh_connection "$server_host" "$server_port" "$server_user" "$ssh_opts"; then
        log_error "SSH connection failed"
        return 1
    fi

    # Build remote source path
    local remote_src="${server_user}@${server_host}:${server_remote_base}/local/outbox/"

    # Build rsync command
    local -a rsync_opts
    mapfile -t rsync_opts < <(build_rsync_options "$extra_options")

    # Add SSH options
    rsync_opts+=("-e" "ssh ${ssh_opts}")
    
    # Ensure destination exists
    if [[ "$extra_options" != *"--dry-run"* ]]; then
        ensure_directory "$local_dest"
    fi
    
    # Show dry-run notice
    if [[ "$extra_options" == *"--dry-run"* ]]; then
        log_dry_run_notice
    fi
    
    log_info "Pulling from: $remote_src"
    log_separator
    
    local rsync_exit_code
    if rsync "${rsync_opts[@]}" "$remote_src" "$local_dest/"; then
        rsync_exit_code=0
    else
        rsync_exit_code=$?
    fi
    
    log_separator
    
    if [[ $rsync_exit_code -ne 0 && $rsync_exit_code -ne 24 ]]; then
        log_error "rsync failed with exit code: $rsync_exit_code"
        return $rsync_exit_code
    fi
    
    log_info "Pull complete"
    return 0
}

#===============================================================================
# SCP: Fallback single file transfer
#===============================================================================
scp_transfer() {
    local source="$1"
    local dest="$2"
    local direction="${3:-push}"  # push or pull
    
    log_debug "scp fallback: $source -> $dest"
    
    local scp_opts=()
    
    # Add quiet if not verbose
    if [[ "${VERBOSE:-false}" != "true" ]]; then
        scp_opts+=("-q")
    fi
    
    # Recursive if directory
    if [[ -d "$source" ]]; then
        scp_opts+=("-r")
    fi
    
    if scp "${scp_opts[@]}" "$source" "$dest"; then
        log_debug "scp transfer successful"
        return 0
    else
        log_error "scp transfer failed"
        return 1
    fi
}

#===============================================================================
# CALCULATE: Transfer statistics
#===============================================================================
calculate_transfer_stats() {
    local source_path="$1"
    
    local file_count=0
    local total_bytes=0
    
    if [[ -d "$source_path" ]]; then
        file_count=$(find "$source_path" -type f | wc -l)
        total_bytes=$(du -sb "$source_path" 2>/dev/null | cut -f1)
    elif [[ -f "$source_path" ]]; then
        file_count=1
        total_bytes=$(stat -c %s "$source_path" 2>/dev/null || stat -f %z "$source_path" 2>/dev/null)
    fi
    
    echo "FILES=$file_count"
    echo "BYTES=$total_bytes"
    echo "HUMAN=$(human_readable_size "$total_bytes")"
}

#===============================================================================
# SHOW: Transfer summary
#===============================================================================
show_transfer_summary() {
    local source="$1"
    local dest="$2"
    local operation="$3"
    local start_time="$4"
    local end_time="$5"
    
    local duration=$((end_time - start_time))
    
    echo ""
    echo "${BOLD}Transfer Summary${RESET}"
    log_separator
    echo "  Operation:   $operation"
    echo "  Source:      $source"
    echo "  Destination: $dest"
    echo "  Duration:    $(format_duration $duration)"
    
    # Calculate stats
    local stats
    stats=$(calculate_transfer_stats "$source")
    eval "$stats"
    
    echo "  Files:       $FILES"
    echo "  Size:        $HUMAN"
    
    if [[ $duration -gt 0 && $BYTES -gt 0 ]]; then
        local rate=$((BYTES / duration))
        echo "  Rate:        $(human_readable_size $rate)/s"
    fi
    
    log_separator
}

#===============================================================================
# VERIFY: Transfer integrity (optional)
#===============================================================================
verify_transfer() {
    local source="$1"
    local dest="$2"
    
    if [[ ! -f "$source" || ! -f "$dest" ]]; then
        log_debug "Skipping verification (not both files)"
        return 0
    fi
    
    log_debug "Verifying transfer integrity..."
    
    local source_checksum
    local dest_checksum
    
    source_checksum=$(get_file_checksum "$source")
    dest_checksum=$(get_file_checksum "$dest")
    
    if [[ -n "$source_checksum" && "$source_checksum" == "$dest_checksum" ]]; then
        log_debug "Checksum verified: $source_checksum"
        return 0
    else
        log_error "Checksum mismatch!"
        log_error "  Source: $source_checksum"
        log_error "  Dest:   $dest_checksum"
        return 1
    fi
}
