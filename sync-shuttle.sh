#!/usr/bin/env bash
#===============================================================================
#
#   ███████╗██╗   ██╗███╗   ██╗ ██████╗    ███████╗██╗  ██╗██╗   ██╗████████╗████████╗██╗     ███████╗
#   ██╔════╝╚██╗ ██╔╝████╗  ██║██╔════╝    ██╔════╝██║  ██║██║   ██║╚══██╔══╝╚══██╔══╝██║     ██╔════╝
#   ███████╗ ╚████╔╝ ██╔██╗ ██║██║         ███████╗███████║██║   ██║   ██║      ██║   ██║     █████╗  
#   ╚════██║  ╚██╔╝  ██║╚██╗██║██║         ╚════██║██╔══██║██║   ██║   ██║      ██║   ██║     ██╔══╝  
#   ███████║   ██║   ██║ ╚████║╚██████╗    ███████║██║  ██║╚██████╔╝   ██║      ██║   ███████╗███████╗
#   ╚══════╝   ╚═╝   ╚═╝  ╚═══╝ ╚═════╝    ╚══════╝╚═╝  ╚═╝ ╚═════╝    ╚═╝      ╚═╝   ╚══════╝╚══════╝
#
#===============================================================================
# SYNC SHUTTLE - Safe, Idempotent File Synchronization Tool
#===============================================================================
# Version:     1.0.0
# Author:      Sync Shuttle Contributors
# License:     MIT
# Repository:  https://github.com/kaurifund/bucketcast
#===============================================================================
#
# DESCRIPTION:
#   Sync Shuttle is a safe, manual file synchronization tool for transferring
#   files between a home computer and remote servers. It prioritizes safety
#   and auditability over speed, ensuring files are never accidentally deleted
#   or overwritten.
#
#-------------------------------------------------------------------------------
# ARCHITECTURE OVERVIEW:
#-------------------------------------------------------------------------------
#
#   ┌─────────────────────────────────────────────────────────────────────────┐
#   │                           SYNC SHUTTLE FLOW                             │
#   └─────────────────────────────────────────────────────────────────────────┘
#
#   [CLI Input] ──► [Validation] ──► [Path Resolution] ──► [Safety Checks]
#                                                                │
#                                                                ▼
#   [Logging] ◄── [Result] ◄── [Transfer Engine] ◄── [Pre-flight Checks]
#                                    │
#                                    ▼
#                           [Optional S3 Archive]
#
#-------------------------------------------------------------------------------
# DIRECTORY STRUCTURE (RUNTIME):
#-------------------------------------------------------------------------------
#
#   ~/.sync-shuttle/
#   ├── config/
#   │   ├── sync-shuttle.conf    # Main configuration (sourced)
#   │   └── servers.toml         # Server definitions (sourced)
#   ├── remote/
#   │   └── <server_id>/
#   │       └── files/           # Files synced from/to this server
#   ├── local/
#   │   ├── inbox/               # Files received from remotes
#   │   └── outbox/              # Files staged for sending
#   ├── logs/
#   │   ├── sync.log             # Human-readable log
#   │   └── sync.jsonl           # Machine-readable JSON Lines log
#   ├── archive/                 # Versioned backups
#   └── tmp/                     # Temporary transfer staging
#
#-------------------------------------------------------------------------------
# MAIN FUNCTIONS:
#-------------------------------------------------------------------------------
#
#   main()
#   │   Entry point. Parses arguments, validates environment, dispatches.
#   │
#   ├── parse_arguments()
#   │       Parses CLI flags into global variables.
#   │       Inputs:  $@ (all CLI arguments)
#   │       Outputs: Sets ACTION, SERVER_ID, DRY_RUN, FORCE, VERBOSE, etc.
#   │
#   ├── validate_environment()
#   │       Ensures all required tools exist and paths are valid.
#   │       Inputs:  None (uses globals)
#   │       Outputs: Exit 1 on failure, or continue
#   │
#   ├── load_configuration()
#   │       Sources config files, validates server definitions.
#   │       Inputs:  CONFIG_DIR path
#   │       Outputs: Populates SERVERS associative array
#   │
#   ├── dispatch_action()
#   │       Routes to appropriate handler based on ACTION.
#   │       Inputs:  ACTION variable
#   │       Outputs: Calls action_* functions
#   │
#   ├── action_push()
#   │       Transfers files TO a remote server.
#   │       Flow: validate_source ──► preflight_checks ──► rsync_push ──► log
#   │
#   ├── action_pull()
#   │       Transfers files FROM a remote server.
#   │       Flow: validate_remote ──► preflight_checks ──► rsync_pull ──► log
#   │
#   ├── action_list()
#   │       Lists configured servers or files in a server's directory.
#   │
#   ├── action_status()
#   │       Shows current sync status and recent operations.
#   │
#   └── action_init()
#           Initializes the ~/.sync-shuttle directory structure.
#
#-------------------------------------------------------------------------------
# SAFETY FUNCTIONS:
#-------------------------------------------------------------------------------
#
#   validate_path_within_sandbox()
#   │   Ensures a path is within SYNC_BASE_DIR. Prevents path traversal.
#   │   Input:  $1 = path to validate
#   │   Output: 0 if safe, 1 if unsafe (with error message)
#   │
#   check_file_collision()
#   │   Checks if destination file exists. Behavior depends on --force.
#   │   Input:  $1 = destination path
#   │   Output: 0 = ok to write, 1 = collision (skip or prompt)
#   │
#   archive_before_overwrite()
#   │   Creates a timestamped backup before any overwrite operation.
#   │   Input:  $1 = file to archive
#   │   Output: Copies to archive/<timestamp>/<filename>
#   │
#   generate_operation_uuid()
#       Generates a UUIDv4 for operation tracking.
#       Output: Echoes UUID string
#
#-------------------------------------------------------------------------------
# TRANSFER FUNCTIONS:
#-------------------------------------------------------------------------------
#
#   rsync_push()
#   │   Executes rsync to push files to remote.
#   │   Uses: --archive --compress --partial --progress
#   │   Respects: DRY_RUN, VERBOSE flags
#   │
#   rsync_pull()
#   │   Executes rsync to pull files from remote.
#   │   Same flags as push, opposite direction.
#   │
#   scp_fallback()
#       Falls back to scp if rsync unavailable on remote.
#       Used only when rsync fails with specific error codes.
#
#-------------------------------------------------------------------------------
# LOGGING FUNCTIONS:
#-------------------------------------------------------------------------------
#
#   log_info() / log_warn() / log_error() / log_debug()
#   │   Level-specific logging to stdout and file.
#   │
#   log_operation()
#   │   Writes structured JSON log entry for operation tracking.
#   │   Fields: uuid, timestamp, operation, paths, status, bytes, etc.
#   │
#   log_to_file()
#       Appends to both sync.log (human) and sync.jsonl (machine).
#
#-------------------------------------------------------------------------------
# USAGE EXAMPLES:
#-------------------------------------------------------------------------------
#
#   # Initialize sync-shuttle (first time setup)
#   ./sync-shuttle.sh init
#
#   # List all configured servers
#   ./sync-shuttle.sh list servers
#
#   # Push a file to a server (dry-run first!)
#   ./sync-shuttle.sh push --server myserver --source ~/file.txt --dry-run
#   ./sync-shuttle.sh push --server myserver --source ~/file.txt
#
#   # Push a directory
#   ./sync-shuttle.sh push --server myserver --source ~/myproject/ --dry-run
#
#   # Pull files from a server
#   ./sync-shuttle.sh pull --server myserver --dry-run
#   ./sync-shuttle.sh pull --server myserver
#
#   # Pull with force (allow overwrites, will prompt)
#   ./sync-shuttle.sh pull --server myserver --force
#
#   # View sync status and recent operations
#   ./sync-shuttle.sh status
#
#   # View files on a specific server's local mirror
#   ./sync-shuttle.sh list files --server myserver
#
#   # Launch interactive TUI (requires Python)
#   ./sync-shuttle.sh tui
#
#   # Verbose mode for debugging
#   ./sync-shuttle.sh push --server myserver --source ~/file.txt --verbose
#
#-------------------------------------------------------------------------------
# USE CASE PATTERNS:
#-------------------------------------------------------------------------------
#
#   PATTERN 1: Daily Development Sync
#   ─────────────────────────────────
#   Scenario: Push code changes to remote dev server daily
#   
#   # Stage files in outbox
#   cp -r ~/projects/myapp ~/.sync-shuttle/local/outbox/
#   
#   # Dry-run to verify
#   ./sync-shuttle.sh push --server devbox --dry-run
#   
#   # Execute
#   ./sync-shuttle.sh push --server devbox
#
#   PATTERN 2: Backup Pull from Production
#   ───────────────────────────────────────
#   Scenario: Pull config files from production for backup
#   
#   # Pull configs (they land in inbox)
#   ./sync-shuttle.sh pull --server prod-web-01
#   
#   # Files available at:
#   ls ~/.sync-shuttle/local/inbox/prod-web-01/
#
#   PATTERN 3: Multi-Server Distribution
#   ─────────────────────────────────────
#   Scenario: Push same files to multiple servers
#   
#   for server in web-01 web-02 web-03; do
#       ./sync-shuttle.sh push --server "$server" --source ~/deploy/
#   done
#
#   PATTERN 4: S3 Archive After Sync (if enabled)
#   ──────────────────────────────────────────────
#   Scenario: Archive to S3 after successful sync
#   
#   ./sync-shuttle.sh push --server myserver --source ~/data/ --s3-archive
#
#   PATTERN 5: Collision Handling
#   ─────────────────────────────
#   Scenario: File exists at destination
#   
#   # Without --force: skips existing files, logs as SKIPPED
#   ./sync-shuttle.sh pull --server myserver
#   
#   # With --force: prompts for confirmation, archives old version
#   ./sync-shuttle.sh pull --server myserver --force
#
#-------------------------------------------------------------------------------
# CONFIGURATION REFERENCE:
#-------------------------------------------------------------------------------
#
#   sync-shuttle.conf variables:
#   ┌─────────────────────┬────────────────────────────────────────────────┐
#   │ Variable            │ Description                                    │
#   ├─────────────────────┼────────────────────────────────────────────────┤
#   │ SYNC_BASE_DIR       │ Base directory (default: ~/.sync-shuttle)     │
#   │ DEFAULT_SSH_PORT    │ Default SSH port (default: 22)                │
#   │ RSYNC_OPTIONS       │ Additional rsync flags                        │
#   │ LOG_LEVEL           │ Logging verbosity (DEBUG|INFO|WARN|ERROR)     │
#   │ S3_ENABLED          │ Enable S3 integration (true|false)            │
#   │ S3_BUCKET           │ S3 bucket name for archives                   │
#   │ S3_PREFIX           │ S3 key prefix                                 │
#   │ ARCHIVE_RETENTION   │ Days to keep local archives (default: 30)     │
#   │ MAX_TRANSFER_SIZE   │ Max single transfer size (e.g., 10G)          │
#   └─────────────────────┴────────────────────────────────────────────────┘
#
#   servers.toml format (one server per block):
#   ┌──────────────────────────────────────────────────────────────────────┐
#   │ [myserver]                                                          │
#   │ name="My Development Server"                                        │
#   │ host=192.168.1.100                                                  │
#   │ port=22                                                             │
#   │ user=deploy                                                         │
#   │ remote_base=/home/deploy/.sync-shuttle                              │
#   │ enabled=true                                                        │
#   │ s3_backup=false                                                     │
#   └──────────────────────────────────────────────────────────────────────┘
#
#-------------------------------------------------------------------------------
# EXIT CODES:
#-------------------------------------------------------------------------------
#
#   0   Success
#   1   General error
#   2   Invalid arguments
#   3   Configuration error
#   4   Path validation failed (security)
#   5   Transfer failed
#   6   Collision detected (no --force)
#   7   User cancelled
#   8   Required tool missing
#
#-------------------------------------------------------------------------------
# DEPENDENCIES:
#-------------------------------------------------------------------------------
#
#   Required:
#     - bash 4.0+     (associative arrays, modern syntax)
#     - rsync 3.0+    (primary transfer engine)
#     - ssh           (remote connectivity)
#     - uuidgen       (operation tracking)
#     - date          (GNU date for ISO 8601)
#
#   Optional:
#     - aws-cli       (S3 integration)
#     - python3       (TUI interface)
#     - jq            (JSON log parsing)
#
#===============================================================================
# END OF DOCUMENTATION HEADER
#===============================================================================

set -o errexit   # Exit on error
set -o nounset   # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

#===============================================================================
# SCRIPT METADATA
#===============================================================================
readonly SCRIPT_NAME="sync-shuttle"
readonly SCRIPT_VERSION="1.2.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#===============================================================================
# DEFAULT CONFIGURATION (can be overridden by config file)
#===============================================================================
SYNC_BASE_DIR="${SYNC_BASE_DIR:-$HOME/.sync-shuttle}"
DEFAULT_SSH_PORT=22
RSYNC_OPTIONS="-avz --partial --progress"
LOG_LEVEL="INFO"
S3_ENABLED="false"
S3_BUCKET=""
S3_PREFIX="sync-shuttle-archive"
ARCHIVE_RETENTION_DAYS=30
MAX_TRANSFER_SIZE="10G"

#===============================================================================
# RUNTIME VARIABLES (set by argument parsing)
#===============================================================================
ACTION=""
SERVER_ID=""
SOURCE_PATH=""
DRY_RUN="false"
FORCE="false"
VERBOSE="false"
QUIET="false"
S3_ARCHIVE="false"
OPERATION_UUID=""
CONFIG_ARGS=()
SEARCH_QUERY=""
SHOW_REMOTE="false"
OUTPUT_FORMAT="default"

#===============================================================================
# DERIVED PATHS (computed after config load)
#===============================================================================
CONFIG_DIR=""
REMOTE_DIR=""
LOCAL_DIR=""
INBOX_DIR=""
OUTBOX_DIR=""
LOGS_DIR=""
ARCHIVE_DIR=""
TMP_DIR=""
LOG_FILE=""
LOG_JSON_FILE=""

#===============================================================================
# COLOR DEFINITIONS (for terminal output)
#===============================================================================
if [[ -t 1 ]]; then
    readonly RED=$'\033[0;31m'
    readonly GREEN=$'\033[0;32m'
    readonly YELLOW=$'\033[0;33m'
    readonly BLUE=$'\033[0;34m'
    readonly MAGENTA=$'\033[0;35m'
    readonly CYAN=$'\033[0;36m'
    readonly WHITE=$'\033[0;37m'
    readonly BOLD=$'\033[1m'
    readonly DIM=$'\033[2m'
    readonly RESET=$'\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly MAGENTA=''
    readonly CYAN=''
    readonly WHITE=''
    readonly BOLD=''
    readonly DIM=''
    readonly RESET=''
fi

#===============================================================================
# SOURCE LIBRARY FILES
#===============================================================================
source_library() {
    local lib_file="$1"
    local lib_path="${SCRIPT_DIR}/lib/${lib_file}"
    
    if [[ -f "$lib_path" ]]; then
        # shellcheck source=/dev/null
        source "$lib_path"
    else
        echo "ERROR: Required library not found: $lib_path" >&2
        exit 1
    fi
}

# Source all library files
source_library "logging.sh"
source_library "validation.sh"
source_library "core.sh"
source_library "transfer.sh"
source_library "s3.sh"

#===============================================================================
# USAGE AND HELP
#===============================================================================
show_usage() {
    cat << EOF
${BOLD}SYNC SHUTTLE${RESET} - Safe, Idempotent File Synchronization

${BOLD}USAGE:${RESET}
    $SCRIPT_NAME <command> [options]

${BOLD}COMMANDS:${RESET}
    init                    Initialize sync-shuttle directory structure
    push                    Push files TO a remote server
    pull                    Pull files FROM a remote server
    files                   List all files (inbox/outbox/remote)
    tree                    Tree view of all files
    list <servers|files>    List servers or files in a server's directory
    status                  Show sync status and recent operations
    config <subcommand>     Manage server configuration
    tui                     Launch interactive terminal UI

${BOLD}CONFIG SUBCOMMANDS:${RESET}
    config get <server> <field>         Get a config value
    config set <server> <field> <val>   Set a config value
    config add <server>                 Add a new server
    config remove <server>              Remove a server

${BOLD}OPTIONS:${RESET}
    -s, --server <id>       Target server ID (required for push/pull)
    -S, --source <path>     Source file or directory to push
    -n, --dry-run           Preview operations without executing
    -f, --force             Allow overwrites (prompts for confirmation)
    -v, --verbose           Verbose output
    -q, --quiet             Minimal output
    --search <pattern>      Filter files by glob pattern (e.g. "*.txt")
    --remote                Include remote server files (requires SSH)
    --json                  Output in JSON format
    --s3-archive            Archive to S3 after successful sync
    -h, --help              Show this help message
    -V, --version           Show version

${BOLD}EXAMPLES:${RESET}
    # First time setup
    $SCRIPT_NAME init

    # List configured servers
    $SCRIPT_NAME list servers

    # Push a file (always dry-run first!)
    $SCRIPT_NAME push -s myserver -S ~/file.txt --dry-run
    $SCRIPT_NAME push -s myserver -S ~/file.txt

    # Pull from a server
    $SCRIPT_NAME pull -s myserver --dry-run
    $SCRIPT_NAME pull -s myserver

    # Browse files
    $SCRIPT_NAME files                    # List local inbox/outbox
    $SCRIPT_NAME files --remote           # Include remote server files
    $SCRIPT_NAME files --search "*.pdf"   # Search for PDFs
    $SCRIPT_NAME tree                     # Tree view
    $SCRIPT_NAME tree -s myserver --remote

${BOLD}SAFETY:${RESET}
    • All operations are sandboxed to ~/.sync-shuttle/
    • Files are NEVER deleted by this tool
    • Existing files are NEVER overwritten without --force
    • Use --dry-run to preview any operation

For detailed documentation, see: ${SCRIPT_DIR}/SPECIFICATION.md
EOF
}

show_version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}

#===============================================================================
# ARGUMENT PARSING
#===============================================================================
parse_arguments() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 0
    fi

    # First argument should be the command
    case "${1:-}" in
        init|push|pull|list|status|config|tui|files|tree|help|--help|-h)
            ACTION="${1}"
            shift
            ;;
        --version|-V)
            show_version
            exit 0
            ;;
        *)
            log_error "Unknown command: ${1}"
            echo "Use '$SCRIPT_NAME --help' for usage information."
            exit 2
            ;;
    esac

    # For config command, capture all remaining args
    if [[ "$ACTION" == "config" ]]; then
        CONFIG_ARGS=("$@")
        return 0
    fi

    # Handle help specially
    if [[ "$ACTION" == "help" || "$ACTION" == "--help" || "$ACTION" == "-h" ]]; then
        show_usage
        exit 0
    fi

    # Parse remaining options
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -s|--server)
                SERVER_ID="${2:-}"
                if [[ -z "$SERVER_ID" ]]; then
                    log_error "--server requires an argument"
                    exit 2
                fi
                shift 2
                ;;
            -S|--source)
                SOURCE_PATH="${2:-}"
                if [[ -z "$SOURCE_PATH" ]]; then
                    log_error "--source requires an argument"
                    exit 2
                fi
                # Strip trailing slashes to preserve folder names in rsync
                SOURCE_PATH="${SOURCE_PATH%/}"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -f|--force)
                FORCE="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                LOG_LEVEL="DEBUG"
                shift
                ;;
            -q|--quiet)
                QUIET="true"
                LOG_LEVEL="ERROR"
                shift
                ;;
            --s3-archive)
                S3_ARCHIVE="true"
                shift
                ;;
            --search|--find)
                SEARCH_QUERY="${2:-}"
                if [[ -z "$SEARCH_QUERY" ]]; then
                    log_error "--search requires a pattern"
                    exit 2
                fi
                shift 2
                ;;
            --remote)
                SHOW_REMOTE="true"
                shift
                ;;
            --json)
                OUTPUT_FORMAT="json"
                shift
                ;;
            servers|files)
                # Subcommand for list
                if [[ "$ACTION" == "list" ]]; then
                    LIST_SUBCOMMAND="${1}"
                fi
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: ${1}"
                exit 2
                ;;
        esac
    done
}

#===============================================================================
# MIGRATIONS
#===============================================================================
# Version comparison: returns 0 if $1 < $2
version_lt() {
    [[ "$1" != "$2" ]] && [[ "$(printf '%s\n%s' "$1" "$2" | sort -V | head -n1)" == "$1" ]]
}

# Get installed version (0.0.0 if no version file)
get_installed_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        # Get latest version from last line (format: "TIMESTAMP VERSION")
        tail -n1 "$VERSION_FILE" | awk '{print $2}'
    else
        echo "0.0.0"
    fi
}

# Append version entry with timestamp
update_version_file() {
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "${timestamp} ${SCRIPT_VERSION}" >> "$VERSION_FILE"
}

# Migration: pre-1.0.0 to 1.0.0 (servers.conf → servers.toml)
migrate_to_1_0_0() {
    local old_conf="${CONFIG_DIR}/servers.conf"
    local new_toml="${CONFIG_DIR}/servers.toml"

    # Skip if old config doesn't exist or new one already does
    [[ ! -f "$old_conf" ]] && return 0
    [[ -f "$new_toml" ]] && return 0

    echo -e "${YELLOW}[MIGRATE]${RESET} Converting servers.conf to servers.toml..."

    # Parse bash declare -A arrays and convert to TOML
    local python_script='
import sys
import re

content = sys.stdin.read()
pattern = r"declare\s+-A\s+server_(\w+)=\(\s*([^)]+)\)"
matches = re.findall(pattern, content, re.DOTALL)

print("# Sync Shuttle - Server Configuration")
print("# Migrated from servers.conf")
print("")

for server_id, props_str in matches:
    print(f"[servers.{server_id}]")
    # Parse [key]="value" pairs
    prop_pattern = r"\[(\w+)\]=\"([^\"]*)\""
    for key, value in re.findall(prop_pattern, props_str):
        if value.lower() in ("true", "false"):
            print(f"{key} = {value.lower()}")
        elif value.isdigit():
            print(f"{key} = {value}")
        else:
            print(f"{key} = \"{value}\"")
    print("")
'

    local python
    python=$(get_config_python 2>/dev/null) || python="python3"

    if "$python" -c "print('ok')" &>/dev/null; then
        if "$python" -c "$python_script" < "$old_conf" > "$new_toml" 2>/dev/null; then
            mv "$old_conf" "${old_conf}.backup"
            echo -e "${GREEN}[MIGRATE]${RESET} Converted to servers.toml (backup: servers.conf.backup)"
            return 0
        fi
    fi

    echo -e "${YELLOW}[MIGRATE]${RESET} Auto-migration failed. Please manually convert servers.conf to servers.toml"
    return 1
}

# Run all necessary migrations based on version
check_and_run_migrations() {
    # Skip if sync-shuttle directory doesn't exist (fresh install)
    [[ ! -d "$SYNC_BASE_DIR" ]] && return 0

    local installed_version
    installed_version=$(get_installed_version)

    # Skip if already up to date
    [[ "$installed_version" == "$SCRIPT_VERSION" ]] && return 0

    # Run migrations in order
    if version_lt "$installed_version" "1.0.0"; then
        migrate_to_1_0_0 || true
    fi

    # Future migrations go here:
    # if version_lt "$installed_version" "2.0.0"; then
    #     migrate_to_2_0_0 || true
    # fi

    # Update version file
    update_version_file
}

#===============================================================================
# INITIALIZATION
#===============================================================================
initialize_paths() {
    CONFIG_DIR="${SYNC_BASE_DIR}/config"
    REMOTE_DIR="${SYNC_BASE_DIR}/remote"
    LOCAL_DIR="${SYNC_BASE_DIR}/local"
    INBOX_DIR="${LOCAL_DIR}/inbox"
    OUTBOX_DIR="${LOCAL_DIR}/outbox"
    LOGS_DIR="${SYNC_BASE_DIR}/logs"
    ARCHIVE_DIR="${SYNC_BASE_DIR}/archive"
    TMP_DIR="${SYNC_BASE_DIR}/tmp"
    LOG_FILE="${LOGS_DIR}/sync.log"
    LOG_JSON_FILE="${LOGS_DIR}/sync.jsonl"
    VERSION_FILE="${SYNC_BASE_DIR}/.version"
}

load_configuration() {
    local config_file="${CONFIG_DIR}/sync-shuttle.conf"
    
    if [[ -f "$config_file" ]]; then
        log_debug "Loading configuration from: $config_file"
        # shellcheck source=/dev/null
        source "$config_file"
    else
        log_debug "No configuration file found, using defaults"
    fi
    
    # Re-initialize paths in case SYNC_BASE_DIR was changed by config
    initialize_paths
}

#===============================================================================
# ACTION DISPATCH
#===============================================================================
dispatch_action() {
    case "$ACTION" in
        init)
            action_init
            ;;
        push)
            validate_server_required
            action_push
            ;;
        pull)
            validate_server_required
            action_pull
            ;;
        list)
            action_list
            ;;
        status)
            action_status
            ;;
        files)
            action_files
            ;;
        tree)
            action_tree
            ;;
        config)
            action_config
            ;;
        tui)
            action_tui
            ;;
        *)
            log_error "Unknown action: $ACTION"
            exit 2
            ;;
    esac
}

validate_server_required() {
    if [[ -z "$SERVER_ID" ]]; then
        log_error "Server ID is required for this operation"
        echo "Use: $SCRIPT_NAME $ACTION --server <server_id>"
        exit 2
    fi
}

#===============================================================================
# ACTION: INIT
#===============================================================================
action_init() {
    log_info "Initializing Sync Shuttle directory structure..."
    
    # Create all directories
    local dirs=(
        "$CONFIG_DIR"
        "$REMOTE_DIR"
        "$INBOX_DIR"
        "$OUTBOX_DIR"
        "$LOGS_DIR"
        "$ARCHIVE_DIR"
        "$TMP_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_info "Created: $dir"
        else
            log_debug "Already exists: $dir"
        fi
    done

    # Set secure permissions on base directory (owner only)
    chmod 700 "$SYNC_BASE_DIR"
    chmod 700 "$CONFIG_DIR"
    log_debug "Set secure permissions on config directory"
    
    # Create default config if not exists
    local config_file="${CONFIG_DIR}/sync-shuttle.conf"
    if [[ ! -f "$config_file" ]]; then
        create_default_config "$config_file"
        log_info "Created default configuration: $config_file"
    fi
    
    # Create servers config if not exists
    local servers_file="${CONFIG_DIR}/servers.toml"
    if [[ ! -f "$servers_file" ]]; then
        create_default_servers_config "$servers_file"
        log_info "Created servers configuration: $servers_file"
    fi

    # Set secure permissions on config files (owner read/write only)
    chmod 600 "$config_file" 2>/dev/null || true
    chmod 600 "$servers_file" 2>/dev/null || true
    log_debug "Set secure permissions on config files"

    # Create log files with secure permissions
    touch "$LOG_FILE" "$LOG_JSON_FILE"
    chmod 600 "$LOG_FILE" "$LOG_JSON_FILE" 2>/dev/null || true

    # Write version file (append with timestamp)
    update_version_file

    log_success "Sync Shuttle initialized successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Edit ${CONFIG_DIR}/servers.toml to add your servers"
    echo "  2. Run '$SCRIPT_NAME list servers' to verify"
    echo "  3. Use '$SCRIPT_NAME push --server <id> --source <path> --dry-run' to test"
}

create_default_config() {
    local config_file="$1"
    
    cat > "$config_file" << 'DEFAULTCONFIG'
#===============================================================================
# SYNC SHUTTLE CONFIGURATION
#===============================================================================
# This file is sourced by sync-shuttle.sh
# Edit values below to customize behavior

#-------------------------------------------------------------------------------
# Base Paths
#-------------------------------------------------------------------------------
# Base directory for all sync-shuttle data (default: ~/.sync-shuttle)
# SYNC_BASE_DIR="$HOME/.sync-shuttle"

#-------------------------------------------------------------------------------
# SSH Settings
#-------------------------------------------------------------------------------
# Default SSH port if not specified per-server
DEFAULT_SSH_PORT=22

#-------------------------------------------------------------------------------
# Rsync Settings
#-------------------------------------------------------------------------------
# Additional rsync options (base options are always applied)
# RSYNC_OPTIONS="-avz --partial --progress"

#-------------------------------------------------------------------------------
# Logging
#-------------------------------------------------------------------------------
# Log level: DEBUG, INFO, WARN, ERROR
LOG_LEVEL="INFO"

#-------------------------------------------------------------------------------
# S3 Integration (Optional)
#-------------------------------------------------------------------------------
# Enable S3 archival
S3_ENABLED="false"

# S3 bucket name (required if S3_ENABLED=true)
# S3_BUCKET="my-sync-shuttle-bucket"

# S3 key prefix for archived files
S3_PREFIX="sync-shuttle-archive"

#-------------------------------------------------------------------------------
# Archive Settings
#-------------------------------------------------------------------------------
# Days to retain local archives (0 = forever)
ARCHIVE_RETENTION_DAYS=30

#-------------------------------------------------------------------------------
# Transfer Limits
#-------------------------------------------------------------------------------
# Maximum single transfer size (e.g., 1G, 10G, 100M)
MAX_TRANSFER_SIZE="10G"
DEFAULTCONFIG
}

create_default_servers_config() {
    local servers_file="$1"

    cat > "$servers_file" << 'DEFAULTSERVERS'
# Sync Shuttle - Server Configuration
# ====================================
# Each [servers.ID] section defines a server.
# ID must be lowercase alphanumeric with dashes (3-32 chars).
#
# Required fields: host, user, remote_base
# Optional fields: port (default 22), identity_file, s3_backup
#
# Example with SSH key (.pem):
#   [servers.aws-prod]
#   name = "AWS Production"
#   host = "ec2-xx-xx-xx-xx.compute-1.amazonaws.com"
#   port = 22
#   user = "ec2-user"
#   identity_file = "~/.ssh/my-key.pem"
#   remote_base = "/home/ec2-user/.sync-shuttle"
#   enabled = true
#   s3_backup = true

[servers.example]
name = "Example Server"
host = "192.168.1.100"
port = 22
user = "myuser"
remote_base = "/home/myuser/.sync-shuttle"
enabled = false
s3_backup = false

# Add your servers below
DEFAULTSERVERS
}

#===============================================================================
# ACTION: PUSH
#===============================================================================
action_push() {
    OPERATION_UUID=$(generate_uuid)
    local timestamp_start
    timestamp_start=$(get_iso_timestamp)
    
    log_info "Starting PUSH operation [${OPERATION_UUID}]"
    log_info "Server: ${SERVER_ID}"
    
    # Validate source path exists
    if [[ -z "$SOURCE_PATH" ]]; then
        log_error "Source path is required for push operation"
        echo "Use: $SCRIPT_NAME push --server $SERVER_ID --source <path>"
        exit 2
    fi
    
    if [[ ! -e "$SOURCE_PATH" ]]; then
        log_error "Source path does not exist: $SOURCE_PATH"
        exit 5
    fi
    
    # Load server configuration
    local server_config
    if ! server_config=$(get_server_config "$SERVER_ID"); then
        log_error "Server not found or disabled: $SERVER_ID"
        exit 3
    fi
    
    # Parse server config
    eval "$server_config"

    # Validate remote_base path is safe
    if ! validate_remote_base "$server_remote_base" "$SERVER_ID"; then
        exit 4
    fi

    # Create operation-specific staging directory under server's remote dir
    # Uses UUID for isolation - each push gets its own staging, cleaned after sync
    local staging_dir="${REMOTE_DIR}/${SERVER_ID}/push-${OPERATION_UUID}"
    if ! validate_path_within_sandbox "$staging_dir"; then
        log_error "Staging path validation failed (security check)"
        exit 4
    fi
    mkdir -p "$staging_dir"

    # Perform pre-flight checks
    preflight_push "$SOURCE_PATH" "$staging_dir"

    # Build remote destination for display
    local remote_dest="${server_user}@${server_host}:${server_remote_base}/local/inbox/${HOSTNAME:-$(hostname)}/"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would transfer:"
        log_info "  Source:       $SOURCE_PATH"
        log_info "  Local stage:  $staging_dir"
        log_info "  Remote dest:  $remote_dest"
        perform_rsync_push "$SOURCE_PATH" "$staging_dir" "--dry-run"
        # Clean up dry-run staging
        rm -rf "$staging_dir"
    else
        log_info "Transferring: $SOURCE_PATH -> $staging_dir"
        perform_rsync_push "$SOURCE_PATH" "$staging_dir" ""

        # Remote sync
        sync_to_remote "$SERVER_ID" "$staging_dir"

        # S3 archive if requested
        if [[ "$S3_ARCHIVE" == "true" && "$S3_ENABLED" == "true" ]]; then
            archive_to_s3 "$staging_dir" "$SERVER_ID"
        fi

        # Clean up staging after successful sync
        rm -rf "$staging_dir"
        log_debug "Cleaned up staging directory: $staging_dir"
    fi

    local timestamp_end
    timestamp_end=$(get_iso_timestamp)

    # Log the operation
    log_operation "$OPERATION_UUID" "push" "$SERVER_ID" "$SOURCE_PATH" "$staging_dir" \
        "$timestamp_start" "$timestamp_end" "SUCCESS"

    log_success "Push operation completed [${OPERATION_UUID}]"
}

#===============================================================================
# ACTION: PULL
#===============================================================================
action_pull() {
    OPERATION_UUID=$(generate_uuid)
    local timestamp_start
    timestamp_start=$(get_iso_timestamp)
    
    log_info "Starting PULL operation [${OPERATION_UUID}]"
    log_info "Server: ${SERVER_ID}"
    
    # Load server configuration
    local server_config
    if ! server_config=$(get_server_config "$SERVER_ID"); then
        log_error "Server not found or disabled: $SERVER_ID"
        exit 3
    fi
    
    # Parse server config
    eval "$server_config"

    # Validate remote_base path is safe
    if ! validate_remote_base "$server_remote_base" "$SERVER_ID"; then
        exit 4
    fi

    # Validate destination is within sandbox
    local dest_dir="${INBOX_DIR}/${SERVER_ID}"
    if ! validate_path_within_sandbox "$dest_dir"; then
        log_error "Destination path validation failed (security check)"
        exit 4
    fi

    # Ensure destination directory exists
    mkdir -p "$dest_dir"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would pull from: ${server_user}@${server_host}:${server_remote_base}/local/outbox/"
        perform_rsync_pull "$SERVER_ID" "$dest_dir" "--dry-run"
    else
        log_info "Pulling from: ${server_user}@${server_host}:${server_remote_base}/local/outbox/"
        perform_rsync_pull "$SERVER_ID" "$dest_dir" ""
        
        # S3 archive if requested
        if [[ "$S3_ARCHIVE" == "true" && "$S3_ENABLED" == "true" ]]; then
            archive_to_s3 "$dest_dir" "$SERVER_ID"
        fi
    fi
    
    local timestamp_end
    timestamp_end=$(get_iso_timestamp)
    
    # Log the operation
    log_operation "$OPERATION_UUID" "pull" "$SERVER_ID" "remote" "$dest_dir" \
        "$timestamp_start" "$timestamp_end" "SUCCESS"
    
    log_success "Pull operation completed [${OPERATION_UUID}]"
}

#===============================================================================
# ACTION: LIST
#===============================================================================
action_list() {
    local subcommand="${LIST_SUBCOMMAND:-servers}"
    
    case "$subcommand" in
        servers)
            list_servers
            ;;
        files)
            if [[ -z "$SERVER_ID" ]]; then
                log_error "Server ID required to list files"
                echo "Use: $SCRIPT_NAME list files --server <server_id>"
                exit 2
            fi
            list_server_files "$SERVER_ID"
            ;;
        *)
            log_error "Unknown list subcommand: $subcommand"
            echo "Use: $SCRIPT_NAME list <servers|files>"
            exit 2
            ;;
    esac
}

list_servers() {
    echo ""
    echo "${BOLD}Configured Servers${RESET}"
    echo "─────────────────────────────────────────────────────────"

    local servers_file="${CONFIG_DIR}/servers.toml"
    local parser="${SCRIPT_DIR}/lib/config_parser.py"

    if [[ ! -f "$servers_file" ]]; then
        log_warn "No servers configured. Run '$SCRIPT_NAME init' first."
        return
    fi

    # Get Python interpreter
    local python
    python=$(get_config_python) || return 1

    # Get server list from Python parser
    local found_servers=0
    while IFS='|' read -r status server_id user host port name; do
        if [[ "$status" == "NO_SERVERS" ]]; then
            break
        fi

        local status_icon="${GREEN}●${RESET}"
        if [[ "$status" != "enabled" ]]; then
            status_icon="${RED}○${RESET}"
        fi

        printf "  %b %-15s %s@%s:%s\n" \
            "$status_icon" \
            "$server_id" \
            "$user" \
            "$host" \
            "$port"
        printf "    └─ %s\n" "$name"

        ((found_servers++))
    done < <("$python" "$parser" "$servers_file" list-detail)

    if [[ $found_servers -eq 0 ]]; then
        echo "  No servers configured."
        echo "  Edit: ${CONFIG_DIR}/servers.toml"
    fi

    echo ""
    echo "Legend: ${GREEN}●${RESET} enabled  ${RED}○${RESET} disabled"
    echo ""
}

list_server_files() {
    local server_id="$1"
    local server_dir="${REMOTE_DIR}/${server_id}/files"
    
    echo ""
    echo "${BOLD}Files for server: ${server_id}${RESET}"
    echo "─────────────────────────────────────────────────────────"
    echo "Path: ${server_dir}"
    echo ""
    
    if [[ ! -d "$server_dir" ]]; then
        echo "  No files synced yet."
        return
    fi
    
    # List files with details
    if command -v tree &> /dev/null; then
        tree -L 2 --noreport "$server_dir"
    else
        find "$server_dir" -maxdepth 2 -type f | while read -r file; do
            local relative="${file#$server_dir/}"
            local size
            size=$(du -h "$file" 2>/dev/null | cut -f1)
            printf "  %-40s %8s\n" "$relative" "$size"
        done
    fi
    
    echo ""
}

#===============================================================================
# ACTION: STATUS
#===============================================================================
action_status() {
    echo ""
    echo "${BOLD}Sync Shuttle Status${RESET}"
    echo "═════════════════════════════════════════════════════════"
    echo ""
    
    # Directory status
    echo "${BOLD}Directory Structure${RESET}"
    echo "─────────────────────────────────────────────────────────"
    for dir in "$CONFIG_DIR" "$REMOTE_DIR" "$INBOX_DIR" "$OUTBOX_DIR" "$LOGS_DIR"; do
        if [[ -d "$dir" ]]; then
            local count
            count=$(find "$dir" -type f 2>/dev/null | wc -l)
            printf "  ${GREEN}✓${RESET} %-30s (%d files)\n" "${dir/#$HOME/~}" "$count"
        else
            printf "  ${RED}✗${RESET} %-30s (missing)\n" "${dir/#$HOME/~}"
        fi
    done
    echo ""
    
    # Recent operations
    echo "${BOLD}Recent Operations${RESET} (last 5)"
    echo "─────────────────────────────────────────────────────────"
    
    if [[ -f "$LOG_JSON_FILE" && -s "$LOG_JSON_FILE" ]]; then
        tail -5 "$LOG_JSON_FILE" | while read -r line; do
            if command -v jq &> /dev/null; then
                local op ts status server
                op=$(echo "$line" | jq -r '.operation // "?"')
                ts=$(echo "$line" | jq -r '.timestamp_start // "?"')
                status=$(echo "$line" | jq -r '.status // "?"')
                server=$(echo "$line" | jq -r '.server_id // "?"')
                
                local status_icon="${GREEN}✓${RESET}"
                [[ "$status" != "SUCCESS" ]] && status_icon="${RED}✗${RESET}"
                
                printf "  %b %-6s %-12s %s\n" "$status_icon" "$op" "$server" "$ts"
            else
                echo "  $line"
            fi
        done
    else
        echo "  No operations logged yet."
    fi
    echo ""
    
    # Outbox status
    echo "${BOLD}Outbox${RESET} (files ready to push)"
    echo "─────────────────────────────────────────────────────────"
    if [[ -d "$OUTBOX_DIR" ]]; then
        local outbox_count
        outbox_count=$(find "$OUTBOX_DIR" -type f 2>/dev/null | wc -l)
        if [[ $outbox_count -gt 0 ]]; then
            find "$OUTBOX_DIR" -type f -print0 2>/dev/null | head -c 500 | \
                xargs -0 -I{} sh -c 'echo "  - ${1#'"$OUTBOX_DIR"'/}"' _ {}
        else
            echo "  (empty)"
        fi
    else
        echo "  (not initialized)"
    fi
    echo ""
}

#===============================================================================
# ACTION: FILES - List files across inbox/outbox/remote
#===============================================================================
action_files() {
    local found_any=false

    echo ""
    echo "${BOLD}Sync Shuttle Files${RESET}"
    echo "═════════════════════════════════════════════════════════"

    # Show outbox (files you're sharing)
    echo ""
    echo "${BOLD}📤 Your Outbox${RESET} (files others can pull from you)"
    echo "─────────────────────────────────────────────────────────"
    list_directory_files "$OUTBOX_DIR" "" "$SEARCH_QUERY"

    # Show inbox (files received)
    echo ""
    echo "${BOLD}📥 Your Inbox${RESET} (files you received)"
    echo "─────────────────────────────────────────────────────────"
    if [[ -d "$INBOX_DIR" ]]; then
        local has_inbox_files=false
        for sender_dir in "$INBOX_DIR"/*/; do
            [[ -d "$sender_dir" ]] || continue
            # Remove trailing slash
            sender_dir="${sender_dir%/}"
            local sender_name
            sender_name=$(basename "$sender_dir")

            # If server filter is set, skip non-matching
            if [[ -n "$SERVER_ID" && "$sender_name" != "$SERVER_ID" ]]; then
                continue
            fi

            local file_count
            file_count=$(find "$sender_dir" -type f 2>/dev/null | wc -l)
            [[ $file_count -eq 0 ]] && continue

            has_inbox_files=true
            echo "  From ${BOLD}${sender_name}${RESET}:"
            list_directory_files "$sender_dir" "    " "$SEARCH_QUERY"
        done
        [[ "$has_inbox_files" == "false" ]] && echo "  (empty)"
    else
        echo "  (not initialized)"
    fi

    # Show remote files if requested
    if [[ "$SHOW_REMOTE" == "true" ]]; then
        echo ""
        echo "${BOLD}📡 Remote Servers${RESET} (files available to pull)"
        echo "─────────────────────────────────────────────────────────"
        list_remote_files
    else
        echo ""
        echo "${DIM}Tip: Use --remote to scan remote server outboxes${RESET}"
    fi

    echo ""
}

#===============================================================================
# HELPER: List files in a directory
#===============================================================================
list_directory_files() {
    local dir="$1"
    local prefix="${2:-  }"
    local search="${3:-}"

    if [[ ! -d "$dir" ]]; then
        echo "${prefix}(not initialized)"
        return
    fi

    local files=()
    local total_size=0

    while IFS= read -r -d '' file; do
        local name="${file#$dir/}"
        # Apply search filter if set
        if [[ -n "$search" ]]; then
            # shellcheck disable=SC2053
            [[ "$name" == $search ]] || continue
        fi
        files+=("$file")
    done < <(find "$dir" -type f -print0 2>/dev/null | sort -z)

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "${prefix}(empty)"
        return
    fi

    for file in "${files[@]}"; do
        local name="${file#$dir/}"
        local size mod_time
        size=$(stat -c %s "$file" 2>/dev/null || echo 0)
        mod_time=$(stat -c %Y "$file" 2>/dev/null || echo 0)
        total_size=$((total_size + size))

        local age
        age=$(format_age "$mod_time")

        printf "%s%-40s %8s  %s\n" "$prefix" "$name" "$(human_readable_size $size)" "$age"
    done

    echo "${prefix}─────────────────────────────────────────────────"
    printf "%sTotal: %d files (%s)\n" "$prefix" "${#files[@]}" "$(human_readable_size $total_size)"
}

#===============================================================================
# HELPER: Format file age
#===============================================================================
format_age() {
    local mod_time="$1"
    local now
    now=$(date +%s)
    local diff=$((now - mod_time))

    if [[ $diff -lt 60 ]]; then
        echo "just now"
    elif [[ $diff -lt 3600 ]]; then
        echo "$((diff / 60)) min ago"
    elif [[ $diff -lt 86400 ]]; then
        echo "$((diff / 3600)) hours ago"
    elif [[ $diff -lt 604800 ]]; then
        echo "$((diff / 86400)) days ago"
    else
        date -d "@$mod_time" "+%Y-%m-%d"
    fi
}

#===============================================================================
# HELPER: List remote server files via SSH
#===============================================================================
list_remote_files() {
    local servers_file="${CONFIG_DIR}/servers.toml"
    local parser="${SCRIPT_DIR}/lib/config_parser.py"

    local python
    python=$(get_config_python) || return 1

    # Get enabled servers
    local server_ids=()
    while IFS= read -r sid; do
        [[ -n "$sid" ]] && server_ids+=("$sid")
    done < <("$python" "$parser" "$servers_file" list 2>/dev/null)

    if [[ ${#server_ids[@]} -eq 0 ]]; then
        echo "  No servers configured"
        return
    fi

    for sid in "${server_ids[@]}"; do
        # If server filter is set, skip non-matching
        if [[ -n "$SERVER_ID" && "$sid" != "$SERVER_ID" ]]; then
            continue
        fi

        # Get server config
        local server_config
        if ! server_config=$("$python" "$parser" "$servers_file" get "$sid" 2>/dev/null); then
            continue
        fi
        eval "$server_config"

        echo "  ${BOLD}${sid}${RESET} (${server_host}):"

        # Build SSH options
        local ssh_opts="-p ${server_port} -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes"
        if [[ -n "${server_identity_file:-}" ]]; then
            local expanded_key="${server_identity_file/#\~/$HOME}"
            [[ -f "$expanded_key" ]] && ssh_opts+=" -i ${expanded_key}"
        fi

        # Query remote outbox
        local remote_base="${server_remote_base}"
        local remote_output
        # shellcheck disable=SC2086
        if ! remote_output=$(ssh $ssh_opts "${server_user}@${server_host}" \
            "find '${remote_base}/local/outbox' -type f -printf '%s|%f|%T@\n' 2>/dev/null | head -20" 2>/dev/null); then
            echo "    ${RED}✗${RESET} Cannot connect"
            continue
        fi

        if [[ -z "$remote_output" ]]; then
            echo "    (empty)"
            continue
        fi

        local total_size=0 count=0
        while IFS='|' read -r size name mod_time; do
            [[ -z "$size" ]] && continue
            # Apply search filter if set
            if [[ -n "$SEARCH_QUERY" ]]; then
                # shellcheck disable=SC2053
                [[ "$name" == $SEARCH_QUERY ]] || continue
            fi
            total_size=$((total_size + size))
            ((count++)) || true
            local age
            age=$(format_age "${mod_time%.*}")
            printf "    %-40s %8s  %s\n" "$name" "$(human_readable_size $size)" "$age"
        done <<< "$remote_output"

        if [[ $count -gt 0 ]]; then
            echo "    ─────────────────────────────────────────────────"
            printf "    Total: %d files (%s)\n" "$count" "$(human_readable_size $total_size)"
        fi
    done
}

#===============================================================================
# ACTION: TREE - Hierarchical view of all files
#===============================================================================
action_tree() {
    echo ""

    local base_name
    base_name=$(basename "$SYNC_BASE_DIR")

    echo "${BOLD}${base_name}/${RESET}"

    # Outbox
    echo "├── 📤 outbox/"
    print_tree_dir "$OUTBOX_DIR" "│   "

    # Inbox
    echo "├── 📥 inbox/"
    if [[ -d "$INBOX_DIR" ]]; then
        local inbox_dirs=("$INBOX_DIR"/*/)
        local inbox_count=${#inbox_dirs[@]}
        local idx=0

        for sender_dir in "${inbox_dirs[@]}"; do
            [[ -d "$sender_dir" ]] || continue
            # Remove trailing slash
            sender_dir="${sender_dir%/}"
            ((idx++)) || true
            local sender_name
            sender_name=$(basename "$sender_dir")
            local connector="├──"
            local prefix="│   │   "
            [[ $idx -eq $inbox_count ]] && connector="└──" && prefix="│       "

            echo "│   ${connector} ${sender_name}/"
            print_tree_dir "$sender_dir" "$prefix"
        done

        [[ $idx -eq 0 ]] && echo "│   └── (empty)"
    else
        echo "│   └── (not initialized)"
    fi

    # Remote (if requested)
    if [[ "$SHOW_REMOTE" == "true" ]]; then
        echo "└── 📡 remote/"
        print_remote_tree
    else
        echo "└── 📡 remote/ ${DIM}(use --remote to fetch)${RESET}"
    fi

    echo ""
}

#===============================================================================
# HELPER: Print tree for a directory
#===============================================================================
print_tree_dir() {
    local dir="$1"
    local prefix="$2"

    if [[ ! -d "$dir" ]]; then
        echo "${prefix}└── (empty)"
        return
    fi

    local files=()
    while IFS= read -r -d '' file; do
        # Apply search filter if set
        local name="${file#$dir/}"
        if [[ -n "$SEARCH_QUERY" ]]; then
            # shellcheck disable=SC2053
            [[ "$name" == $SEARCH_QUERY ]] || continue
        fi
        files+=("$file")
    done < <(find "$dir" -maxdepth 1 -type f -print0 2>/dev/null | sort -z)

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "${prefix}└── (empty)"
        return
    fi

    local count=${#files[@]}
    local idx=0
    for file in "${files[@]}"; do
        ((idx++)) || true
        local name
        name=$(basename "$file")
        local size
        size=$(stat -c %s "$file" 2>/dev/null || echo 0)
        local connector="├──"
        [[ $idx -eq $count ]] && connector="└──"

        printf "%s%s %s (%s)\n" "$prefix" "$connector" "$name" "$(human_readable_size $size)"
    done
}

#===============================================================================
# HELPER: Print remote tree via SSH
#===============================================================================
print_remote_tree() {
    local servers_file="${CONFIG_DIR}/servers.toml"
    local parser="${SCRIPT_DIR}/lib/config_parser.py"

    local python
    python=$(get_config_python) || return 1

    local server_ids=()
    while IFS= read -r sid; do
        [[ -n "$sid" ]] && server_ids+=("$sid")
    done < <("$python" "$parser" "$servers_file" list 2>/dev/null)

    if [[ ${#server_ids[@]} -eq 0 ]]; then
        echo "    └── (no servers)"
        return
    fi

    local server_count=${#server_ids[@]}
    local sidx=0

    for sid in "${server_ids[@]}"; do
        ((sidx++)) || true
        local connector="├──"
        local prefix="    │   "
        [[ $sidx -eq $server_count ]] && connector="└──" && prefix="        "

        # If server filter is set, skip non-matching
        if [[ -n "$SERVER_ID" && "$sid" != "$SERVER_ID" ]]; then
            continue
        fi

        # Get server config
        local server_config
        if ! server_config=$("$python" "$parser" "$servers_file" get "$sid" 2>/dev/null); then
            echo "    ${connector} ${sid}/ ${RED}(disabled)${RESET}"
            continue
        fi
        eval "$server_config"

        echo "    ${connector} ${sid}/"

        # Build SSH options
        local ssh_opts="-p ${server_port} -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes"
        if [[ -n "${server_identity_file:-}" ]]; then
            local expanded_key="${server_identity_file/#\~/$HOME}"
            [[ -f "$expanded_key" ]] && ssh_opts+=" -i ${expanded_key}"
        fi

        # Query remote
        local remote_base="${server_remote_base}"
        local remote_output
        # shellcheck disable=SC2086
        if ! remote_output=$(ssh $ssh_opts "${server_user}@${server_host}" \
            "find '${remote_base}/local/outbox' -maxdepth 1 -type f -printf '%s|%f\n' 2>/dev/null | head -10" 2>/dev/null); then
            echo "${prefix}└── ${RED}(cannot connect)${RESET}"
            continue
        fi

        if [[ -z "$remote_output" ]]; then
            echo "${prefix}└── (empty)"
            continue
        fi

        local files=()
        while IFS='|' read -r size name; do
            [[ -z "$name" ]] && continue
            if [[ -n "$SEARCH_QUERY" ]]; then
                # shellcheck disable=SC2053
                [[ "$name" == $SEARCH_QUERY ]] || continue
            fi
            files+=("$size|$name")
        done <<< "$remote_output"

        if [[ ${#files[@]} -eq 0 ]]; then
            echo "${prefix}└── (empty)"
            continue
        fi

        local fcount=${#files[@]}
        local fidx=0
        for entry in "${files[@]}"; do
            ((fidx++)) || true
            IFS='|' read -r size name <<< "$entry"
            local fconnector="├──"
            [[ $fidx -eq $fcount ]] && fconnector="└──"
            printf "%s%s %s (%s)\n" "$prefix" "$fconnector" "$name" "$(human_readable_size $size)"
        done
    done
}

#===============================================================================
# ACTION: CONFIG
#===============================================================================
action_config() {
    local servers_file="${CONFIG_DIR}/servers.toml"
    local parser="${SCRIPT_DIR}/lib/config_parser.py"

    # Get Python interpreter
    local python
    python=$(get_config_python) || exit 1

    if [[ ${#CONFIG_ARGS[@]} -eq 0 ]]; then
        echo "${BOLD}Config Commands:${RESET}"
        echo "  $SCRIPT_NAME config get <server> <field>"
        echo "  $SCRIPT_NAME config set <server> <field> <value>"
        echo "  $SCRIPT_NAME config add <server>"
        echo "  $SCRIPT_NAME config remove <server>"
        echo ""
        echo "Example:"
        echo "  $SCRIPT_NAME config add my-server"
        echo "  $SCRIPT_NAME config set my-server host 10.0.1.50"
        echo "  $SCRIPT_NAME config set my-server user admin"
        echo "  $SCRIPT_NAME config set my-server enabled true"
        exit 0
    fi

    local subcommand="${CONFIG_ARGS[0]}"

    case "$subcommand" in
        get)
            if [[ ${#CONFIG_ARGS[@]} -lt 3 ]]; then
                log_error "Usage: $SCRIPT_NAME config get <server> <field>"
                exit 2
            fi
            "$python" "$parser" "$servers_file" get-field "${CONFIG_ARGS[1]}" "${CONFIG_ARGS[2]}"
            ;;
        set)
            if [[ ${#CONFIG_ARGS[@]} -lt 4 ]]; then
                log_error "Usage: $SCRIPT_NAME config set <server> <field> <value>"
                exit 2
            fi
            "$python" "$parser" "$servers_file" set "${CONFIG_ARGS[1]}" "${CONFIG_ARGS[2]}" "${CONFIG_ARGS[3]}"
            ;;
        add)
            if [[ ${#CONFIG_ARGS[@]} -lt 2 ]]; then
                log_error "Usage: $SCRIPT_NAME config add <server>"
                exit 2
            fi
            "$python" "$parser" "$servers_file" add "${CONFIG_ARGS[1]}"
            ;;
        remove)
            if [[ ${#CONFIG_ARGS[@]} -lt 2 ]]; then
                log_error "Usage: $SCRIPT_NAME config remove <server>"
                exit 2
            fi
            "$python" "$parser" "$servers_file" remove "${CONFIG_ARGS[1]}"
            ;;
        *)
            log_error "Unknown config subcommand: $subcommand"
            echo "Use '$SCRIPT_NAME config' for usage."
            exit 2
            ;;
    esac
}

#===============================================================================
# ACTION: TUI
#===============================================================================
action_tui() {
    local tui_script="${SCRIPT_DIR}/tui/sync_tui.py"
    local venv_python="${SCRIPT_DIR}/.venv/bin/python"

    if [[ ! -f "$tui_script" ]]; then
        log_error "TUI script not found: $tui_script"
        exit 1
    fi

    if [[ ! -f "$venv_python" ]]; then
        log_error "Python venv not found: ${SCRIPT_DIR}/.venv"
        echo "Run the installer to set up the TUI environment:"
        echo "  curl -fsSL https://raw.githubusercontent.com/kaurifund/bucketcast/main/install.sh | bash"
        exit 8
    fi

    # Launch TUI using venv Python
    exec "$venv_python" "$tui_script" --base-dir "$SYNC_BASE_DIR" --config-dir "$CONFIG_DIR"
}

#===============================================================================
# MAIN ENTRY POINT
#===============================================================================
main() {
    # Initialize paths with defaults first
    initialize_paths

    # Parse command line arguments
    parse_arguments "$@"

    # Check for and run any needed migrations
    check_and_run_migrations

    # Load configuration (may override paths)
    load_configuration

    # Re-apply CLI log level flags (they take precedence over config)
    if [[ "$VERBOSE" == "true" ]]; then
        LOG_LEVEL="DEBUG"
        log_info "$SCRIPT_NAME v$SCRIPT_VERSION"
    elif [[ "$QUIET" == "true" ]]; then
        LOG_LEVEL="ERROR"
    fi

    # Validate environment for non-init actions
    if [[ "$ACTION" != "init" ]]; then
        validate_environment
    fi
    
    # Generate operation UUID for tracking
    if [[ -z "$OPERATION_UUID" ]]; then
        OPERATION_UUID=$(generate_uuid)
    fi
    
    # Dispatch to action handler
    dispatch_action
}

# Run main function
main "$@"
