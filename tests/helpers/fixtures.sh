#!/usr/bin/env bash
#===============================================================================
# TEST HELPERS - FIXTURES
#===============================================================================
# Provides test fixture creation functions.
# All fixtures are created in isolated test directories.
#
# Functions:
#   create_test_file PATH [CONTENT]
#   create_test_dir PATH
#   create_test_config
#   create_test_server SERVER_ID
#   create_test_server_config
#   get_fixture_path NAME
#===============================================================================

readonly FIXTURES_DIR="${SCRIPT_DIR}/fixtures"

# Create a test file with optional content
create_test_file() {
    local path="$1"
    local content="${2:-test content $(date +%s)}"
    
    mkdir -p "$(dirname "$path")"
    echo "$content" > "$path"
    echo "$path"
}

# Create a test directory
create_test_dir() {
    local path="$1"
    mkdir -p "$path"
    echo "$path"
}

# Create a minimal test configuration
create_test_config() {
    local config_dir="${CONFIG_DIR:-$TEST_DIR/config}"
    mkdir -p "$config_dir"
    
    cat > "${config_dir}/sync-shuttle.conf" << 'EOF'
SYNC_BASE_DIR="${SYNC_BASE_DIR:-$HOME/.sync-shuttle}"
DEFAULT_SSH_PORT=22
LOG_LEVEL="ERROR"
S3_ENABLED="false"
ARCHIVE_RETENTION_DAYS=30
MAX_TRANSFER_SIZE="10G"
EOF
    
    echo "${config_dir}/sync-shuttle.conf"
}

# Create a test server configuration
create_test_server() {
    local server_id="${1:-testserver}"
    local config_dir="${CONFIG_DIR:-$TEST_DIR/config}"
    mkdir -p "$config_dir"
    
    cat > "${config_dir}/servers.conf" << EOF
declare -A server_${server_id}=(
    [name]="Test Server"
    [host]="localhost"
    [port]="22"
    [user]="testuser"
    [remote_base]="/tmp/sync-shuttle-test"
    [enabled]="true"
    [s3_backup]="false"
)
EOF
    
    echo "${config_dir}/servers.conf"
}

# Create disabled test server
create_disabled_server() {
    local server_id="${1:-disabled}"
    local config_dir="${CONFIG_DIR:-$TEST_DIR/config}"
    mkdir -p "$config_dir"
    
    cat >> "${config_dir}/servers.conf" << EOF

declare -A server_${server_id}=(
    [name]="Disabled Server"
    [host]="disabled.example.com"
    [port]="22"
    [user]="nobody"
    [remote_base]="/nonexistent"
    [enabled]="false"
    [s3_backup]="false"
)
EOF
}

# Create multiple test servers
create_test_server_config() {
    local config_dir="${CONFIG_DIR:-$TEST_DIR/config}"
    mkdir -p "$config_dir"
    
    cat > "${config_dir}/servers.conf" << 'EOF'
declare -A server_dev=(
    [name]="Development Server"
    [host]="dev.example.com"
    [port]="22"
    [user]="developer"
    [remote_base]="/home/developer/.sync-shuttle"
    [enabled]="true"
    [s3_backup]="false"
)

declare -A server_prod=(
    [name]="Production Server"
    [host]="prod.example.com"
    [port]="2222"
    [user]="deploy"
    [remote_base]="/var/sync-shuttle"
    [enabled]="true"
    [s3_backup]="true"
)

declare -A server_disabled=(
    [name]="Disabled Server"
    [host]="old.example.com"
    [port]="22"
    [user]="old"
    [remote_base]="/old"
    [enabled]="false"
    [s3_backup]="false"
)
EOF
    
    echo "${config_dir}/servers.conf"
}

# Get path to a static fixture file
get_fixture_path() {
    local name="$1"
    echo "${FIXTURES_DIR}/${name}"
}

# Create test file tree (for transfer tests)
create_test_file_tree() {
    local base_dir="${1:-$TEST_DIR/files}"
    
    mkdir -p "$base_dir"
    
    echo "file1 content" > "${base_dir}/file1.txt"
    echo "file2 content" > "${base_dir}/file2.txt"
    
    mkdir -p "${base_dir}/subdir"
    echo "nested content" > "${base_dir}/subdir/nested.txt"
    
    echo "$base_dir"
}

# Create test log files
create_test_logs() {
    local logs_dir="${LOGS_DIR:-$TEST_DIR/logs}"
    mkdir -p "$logs_dir"
    
    touch "${logs_dir}/sync.log"
    touch "${logs_dir}/sync.jsonl"
    
    echo "$logs_dir"
}

# Initialize complete test sync-shuttle directory
init_test_sync_shuttle() {
    local base="${SYNC_BASE_DIR:-$TEST_DIR/sync-shuttle}"
    
    mkdir -p "$base"/{config,remote,local/{inbox,outbox},logs,archive,tmp}
    
    create_test_config
    create_test_server_config
    
    touch "${base}/logs/sync.log"
    touch "${base}/logs/sync.jsonl"
    
    echo "$base"
}
