#!/usr/bin/env bash
#===============================================================================
# SYNC SHUTTLE - S3 LIBRARY
#===============================================================================
# Provides optional S3 integration for archival and intermediate storage.
#
# Features:
#   - Archive completed transfers to S3
#   - Use S3 as intermediate storage layer
#   - Configurable retention policies
#
# Requirements:
#   - AWS CLI installed and configured
#   - S3_ENABLED=true in config
#   - S3_BUCKET set in config
#
# Functions:
#   check_s3_available()   - Verify S3 is configured and accessible
#   archive_to_s3()        - Upload files to S3 archive
#   sync_from_s3()         - Download files from S3
#   list_s3_archives()     - List archived transfers
#===============================================================================

#===============================================================================
# CHECK: S3 availability
#===============================================================================
check_s3_available() {
    # Check if S3 is enabled
    if [[ "${S3_ENABLED:-false}" != "true" ]]; then
        log_debug "S3 integration is disabled"
        return 1
    fi
    
    # Check for AWS CLI
    if ! command -v aws &> /dev/null; then
        log_warn "AWS CLI not found - S3 features unavailable"
        return 1
    fi
    
    # Check bucket is configured
    if [[ -z "${S3_BUCKET:-}" ]]; then
        log_error "S3_BUCKET not configured"
        return 1
    fi
    
    # Test S3 access
    if ! aws s3 ls "s3://${S3_BUCKET}" &>/dev/null; then
        log_error "Cannot access S3 bucket: ${S3_BUCKET}"
        log_error "Ensure AWS credentials are configured and bucket exists"
        return 1
    fi
    
    log_debug "S3 integration available: s3://${S3_BUCKET}"
    return 0
}

#===============================================================================
# ARCHIVE: Upload to S3
#===============================================================================
archive_to_s3() {
    local local_path="$1"
    local server_id="$2"
    local operation_uuid="${OPERATION_UUID:-$(generate_uuid)}"
    
    if ! check_s3_available; then
        log_warn "S3 archival skipped - not available"
        return 0
    fi
    
    local timestamp
    timestamp=$(date +"%Y/%m/%d")
    
    # Build S3 path
    local s3_path="s3://${S3_BUCKET}/${S3_PREFIX}/${server_id}/${timestamp}/${operation_uuid}/"
    
    log_info "Archiving to S3: $s3_path"
    
    # Build sync command
    local -a aws_opts=("s3" "sync")
    
    if [[ "${VERBOSE:-false}" != "true" ]]; then
        aws_opts+=("--quiet")
    fi
    
    # Add dry-run if applicable
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        aws_opts+=("--dryrun")
        log_info "[DRY-RUN] Would archive to S3"
    fi
    
    # Execute sync
    if aws "${aws_opts[@]}" "$local_path" "$s3_path"; then
        log_success "S3 archive complete"
        
        # Log the S3 archive
        log_s3_archive "$operation_uuid" "$local_path" "$s3_path" "SUCCESS"
        
        return 0
    else
        log_error "S3 archive failed"
        log_s3_archive "$operation_uuid" "$local_path" "$s3_path" "FAILED"
        return 1
    fi
}

#===============================================================================
# SYNC: Download from S3
#===============================================================================
sync_from_s3() {
    local s3_path="$1"
    local local_path="$2"
    
    if ! check_s3_available; then
        log_error "S3 is not available"
        return 1
    fi
    
    # Validate local path is within sandbox
    if ! validate_path_within_sandbox "$local_path"; then
        log_error "Destination path outside sandbox"
        return 1
    fi
    
    log_info "Downloading from S3: $s3_path"
    
    # Ensure local directory exists
    ensure_directory "$local_path"
    
    # Build sync command
    local -a aws_opts=("s3" "sync")
    
    if [[ "${VERBOSE:-false}" != "true" ]]; then
        aws_opts+=("--quiet")
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        aws_opts+=("--dryrun")
        log_info "[DRY-RUN] Would download from S3"
    fi
    
    # Execute sync
    if aws "${aws_opts[@]}" "$s3_path" "$local_path"; then
        log_success "S3 download complete"
        return 0
    else
        log_error "S3 download failed"
        return 1
    fi
}

#===============================================================================
# LIST: S3 archives
#===============================================================================
list_s3_archives() {
    local server_id="${1:-}"
    local max_items="${2:-50}"
    
    if ! check_s3_available; then
        return 1
    fi
    
    local s3_path="s3://${S3_BUCKET}/${S3_PREFIX}/"
    
    if [[ -n "$server_id" ]]; then
        s3_path="${s3_path}${server_id}/"
    fi
    
    echo ""
    echo "${BOLD}S3 Archives${RESET}"
    log_separator
    echo "Bucket: s3://${S3_BUCKET}"
    echo "Prefix: ${S3_PREFIX}"
    echo ""
    
    # List archives
    aws s3 ls "$s3_path" --recursive 2>/dev/null | \
        sort -r | \
        head -n "$max_items" | \
        while read -r line; do
            # Parse the line: date time size path
            local date time size path
            read -r date time size path <<< "$line"
            
            # Format output
            printf "  %s %s  %10s  %s\n" "$date" "$time" "$size" "$path"
        done
    
    echo ""
}

#===============================================================================
# RESTORE: From S3 archive
#===============================================================================
restore_from_s3() {
    local archive_id="$1"  # UUID or path
    local server_id="${2:-}"
    
    if ! check_s3_available; then
        return 1
    fi
    
    # Find the archive
    local s3_path
    
    if [[ "$archive_id" =~ ^s3:// ]]; then
        # Full S3 path provided
        s3_path="$archive_id"
    else
        # Search for archive by UUID
        log_info "Searching for archive: $archive_id"
        
        local search_path="s3://${S3_BUCKET}/${S3_PREFIX}/"
        if [[ -n "$server_id" ]]; then
            search_path="${search_path}${server_id}/"
        fi
        
        s3_path=$(aws s3 ls "$search_path" --recursive 2>/dev/null | \
                  grep "$archive_id" | \
                  head -1 | \
                  awk '{print "s3://'${S3_BUCKET}'/" $NF}')
        
        if [[ -z "$s3_path" ]]; then
            log_error "Archive not found: $archive_id"
            return 1
        fi
    fi
    
    # Determine destination
    local restore_dir="${ARCHIVE_DIR}/restored/$(date +%Y%m%d_%H%M%S)"
    
    log_info "Restoring from: $s3_path"
    log_info "To: $restore_dir"
    
    if sync_from_s3 "$s3_path" "$restore_dir"; then
        log_success "Archive restored to: $restore_dir"
        return 0
    else
        return 1
    fi
}

#===============================================================================
# CLEANUP: Old S3 archives
#===============================================================================
cleanup_s3_archives() {
    local retention_days="${1:-${ARCHIVE_RETENTION_DAYS:-30}}"
    
    if ! check_s3_available; then
        return 1
    fi
    
    if [[ "$retention_days" -eq 0 ]]; then
        log_info "S3 archive cleanup disabled (retention = 0)"
        return 0
    fi
    
    log_info "Cleaning S3 archives older than $retention_days days"
    
    # Calculate cutoff date
    local cutoff_date
    cutoff_date=$(date -d "-${retention_days} days" +%Y-%m-%d 2>/dev/null || \
                  date -v-${retention_days}d +%Y-%m-%d 2>/dev/null)
    
    if [[ -z "$cutoff_date" ]]; then
        log_error "Cannot calculate cutoff date"
        return 1
    fi
    
    log_debug "Cutoff date: $cutoff_date"
    
    # Note: This is a preview/dry-run by default for safety
    local deleted_count=0
    
    aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" --recursive 2>/dev/null | \
    while read -r line; do
        local date path
        date=$(echo "$line" | awk '{print $1}')
        path=$(echo "$line" | awk '{print $4}')
        
        if [[ "$date" < "$cutoff_date" ]]; then
            log_debug "Would delete: $path (from $date)"
            ((deleted_count++))
        fi
    done
    
    log_info "Found $deleted_count archives eligible for deletion"
    
    if [[ "${FORCE:-false}" == "true" && "$deleted_count" -gt 0 ]]; then
        log_warn "FORCE mode: Actually deleting archives..."
        
        # This would actually delete - disabled for safety
        # aws s3 rm "s3://${S3_BUCKET}/${S3_PREFIX}/" --recursive \
        #     --exclude "*" --include "*" \
        #     --older-than "$retention_days days"
        
        log_warn "S3 deletion not implemented for safety"
        log_warn "Use AWS console or CLI directly to delete old archives"
    fi
    
    return 0
}

#===============================================================================
# LOG: S3 archive operation
#===============================================================================
log_s3_archive() {
    local uuid="$1"
    local local_path="$2"
    local s3_path="$3"
    local status="$4"
    
    if [[ -z "${LOG_JSON_FILE:-}" ]]; then
        return 0
    fi
    
    local timestamp
    timestamp=$(get_iso_timestamp)
    
    local json_entry
    json_entry=$(cat << JSONEOF
{"type":"s3_archive","uuid":"${uuid}","timestamp":"${timestamp}","local_path":"${local_path//\"/\\\"}","s3_path":"${s3_path}","status":"${status}","bucket":"${S3_BUCKET}"}
JSONEOF
)
    
    echo "$json_entry" >> "$LOG_JSON_FILE" 2>/dev/null || true
}

#===============================================================================
# INFO: S3 configuration summary
#===============================================================================
show_s3_status() {
    echo ""
    echo "${BOLD}S3 Integration Status${RESET}"
    log_separator
    
    if [[ "${S3_ENABLED:-false}" != "true" ]]; then
        echo "  Status:  ${RED}Disabled${RESET}"
        echo "  Enable in: ${CONFIG_DIR}/sync-shuttle.conf"
        echo ""
        return 0
    fi
    
    echo "  Status:  ${GREEN}Enabled${RESET}"
    echo "  Bucket:  ${S3_BUCKET:-not set}"
    echo "  Prefix:  ${S3_PREFIX:-sync-shuttle-archive}"
    
    if check_s3_available; then
        echo "  Access:  ${GREEN}OK${RESET}"
        
        # Get bucket size
        local bucket_size
        bucket_size=$(aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" --recursive --summarize 2>/dev/null | \
                      grep "Total Size" | awk '{print $3, $4}')
        
        if [[ -n "$bucket_size" ]]; then
            echo "  Size:    $bucket_size"
        fi
    else
        echo "  Access:  ${RED}FAILED${RESET}"
    fi
    
    echo ""
}

#===============================================================================
# INTERMEDIATE: Use S3 as transfer layer
# This enables server-to-server transfers via S3 without direct connectivity
#===============================================================================
s3_intermediate_push() {
    local source_path="$1"
    local server_id="$2"
    local transfer_id="${3:-$(generate_uuid)}"
    
    if ! check_s3_available; then
        log_error "S3 not available for intermediate transfer"
        return 1
    fi
    
    # Upload to S3 staging area
    local s3_staging="s3://${S3_BUCKET}/${S3_PREFIX}/staging/${server_id}/${transfer_id}/"
    
    log_info "Uploading to S3 staging: $s3_staging"
    
    local -a aws_opts=("s3" "sync")
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        aws_opts+=("--dryrun")
    fi
    
    if aws "${aws_opts[@]}" "$source_path" "$s3_staging"; then
        log_success "Staged to S3: $s3_staging"
        
        # Create marker file for remote to pick up
        local marker_file="${TMP_DIR}/transfer_${transfer_id}.marker"
        echo "server_id=$server_id" > "$marker_file"
        echo "transfer_id=$transfer_id" >> "$marker_file"
        echo "timestamp=$(get_iso_timestamp)" >> "$marker_file"
        echo "source=$source_path" >> "$marker_file"
        
        aws s3 cp "$marker_file" "${s3_staging}.ready" --quiet 2>/dev/null
        rm -f "$marker_file"
        
        log_info "Transfer marker created"
        echo ""
        echo "Transfer ID: $transfer_id"
        echo "Remote can pull with: sync-shuttle s3-pull --transfer-id $transfer_id"
        
        return 0
    else
        log_error "S3 staging failed"
        return 1
    fi
}

#===============================================================================
# INTERMEDIATE: Pull from S3 transfer
#===============================================================================
s3_intermediate_pull() {
    local transfer_id="$1"
    local server_id="${2:-}"
    
    if ! check_s3_available; then
        log_error "S3 not available"
        return 1
    fi
    
    # Find the staging area
    local search_path="s3://${S3_BUCKET}/${S3_PREFIX}/staging/"
    
    if [[ -n "$server_id" ]]; then
        search_path="${search_path}${server_id}/"
    fi
    
    # Check for transfer marker
    local staging_path
    staging_path=$(aws s3 ls "${search_path}" --recursive 2>/dev/null | \
                   grep "${transfer_id}" | \
                   grep ".ready" | \
                   head -1 | \
                   awk '{print "s3://'${S3_BUCKET}'/" $NF}' | \
                   sed 's/.ready$//')
    
    if [[ -z "$staging_path" ]]; then
        log_error "Transfer not found: $transfer_id"
        return 1
    fi
    
    # Pull to inbox
    local dest_dir="${INBOX_DIR}/s3-transfer-${transfer_id}"
    
    log_info "Pulling from S3: $staging_path"
    log_info "To: $dest_dir"
    
    if sync_from_s3 "$staging_path" "$dest_dir"; then
        log_success "S3 transfer complete"
        
        # Optionally clean up staging
        if [[ "${FORCE:-false}" == "true" ]]; then
            log_info "Cleaning up S3 staging..."
            aws s3 rm "${staging_path}" --recursive --quiet 2>/dev/null
            aws s3 rm "${staging_path}.ready" --quiet 2>/dev/null
        fi
        
        return 0
    else
        return 1
    fi
}
