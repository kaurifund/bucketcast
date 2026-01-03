#!/usr/bin/env bash
#===============================================================================
# SYNC SHUTTLE - INSTALLER
#===============================================================================
# Install sync-shuttle with: curl -fsSL https://raw.githubusercontent.com/USER/sync-shuttle/main/install.sh | bash
#
# Options (via environment variables):
#   SYNC_SHUTTLE_DIR    Installation directory (default: ~/.local/share/sync-shuttle)
#   SYNC_SHUTTLE_BRANCH Git branch to install (default: main)
#   SYNC_SHUTTLE_NO_RC  Skip shell RC file modification (default: false)
#
# Examples:
#   curl -fsSL URL/install.sh | bash
#   curl -fsSL URL/install.sh | SYNC_SHUTTLE_DIR=/opt/sync-shuttle bash
#   curl -fsSL URL/install.sh | SYNC_SHUTTLE_NO_RC=1 bash
#===============================================================================

set -o errexit
set -o nounset
set -o pipefail

#===============================================================================
# CONFIGURATION
#===============================================================================
readonly REPO_URL="${SYNC_SHUTTLE_REPO:-https://github.com/kaurifund/bucketcast}"
readonly BRANCH="${SYNC_SHUTTLE_BRANCH:-main}"
readonly INSTALL_DIR="${SYNC_SHUTTLE_DIR:-$HOME/.local/share/sync-shuttle}"
readonly BIN_DIR="${HOME}/.local/bin"
readonly NO_RC="${SYNC_SHUTTLE_NO_RC:-false}"

# Colors
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' RESET=''
fi

#===============================================================================
# FUNCTIONS
#===============================================================================
info()    { echo -e "${BLUE}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

check_dependencies() {
    local missing=()
    
    for cmd in bash rsync ssh; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required dependencies: ${missing[*]}"
    fi
    
    # Check bash version
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        die "Bash 4.0+ required (found: ${BASH_VERSION})"
    fi
}

detect_shell_rc() {
    local shell_name
    shell_name=$(basename "${SHELL:-/bin/bash}")
    
    case "$shell_name" in
        zsh)  echo "${HOME}/.zshrc" ;;
        fish) echo "${HOME}/.config/fish/config.fish" ;;
        *)    echo "${HOME}/.bashrc" ;;
    esac
}

download_release() {
    local dest="$1"
    
    info "Downloading sync-shuttle..."
    
    if command -v git &>/dev/null; then
        git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$dest" 2>/dev/null || \
            die "Failed to clone repository"
    elif command -v curl &>/dev/null; then
        local archive_url="${REPO_URL}/archive/refs/heads/${BRANCH}.tar.gz"
        mkdir -p "$dest"
        curl -fsSL "$archive_url" | tar -xz -C "$dest" --strip-components=1 || \
            die "Failed to download release"
    elif command -v wget &>/dev/null; then
        local archive_url="${REPO_URL}/archive/refs/heads/${BRANCH}.tar.gz"
        mkdir -p "$dest"
        wget -qO- "$archive_url" | tar -xz -C "$dest" --strip-components=1 || \
            die "Failed to download release"
    else
        die "No download tool available (need git, curl, or wget)"
    fi
}

install_binary() {
    info "Installing to ${BIN_DIR}..."
    
    mkdir -p "$BIN_DIR"
    
    # Create wrapper script
    cat > "${BIN_DIR}/sync-shuttle" << EOF
#!/usr/bin/env bash
exec "${INSTALL_DIR}/sync-shuttle.sh" "\$@"
EOF
    
    chmod +x "${BIN_DIR}/sync-shuttle"
    chmod +x "${INSTALL_DIR}/sync-shuttle.sh"
    
    success "Installed sync-shuttle to ${BIN_DIR}/sync-shuttle"
}

update_shell_rc() {
    if [[ "$NO_RC" == "true" || "$NO_RC" == "1" ]]; then
        warn "Skipping shell RC modification (SYNC_SHUTTLE_NO_RC=true)"
        return
    fi
    
    local rc_file
    rc_file=$(detect_shell_rc)
    local path_line='export PATH="$HOME/.local/bin:$PATH"'
    
    # Check if already in PATH
    if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
        info "~/.local/bin already in PATH"
        return
    fi
    
    # Check if line already exists in rc file
    if [[ -f "$rc_file" ]] && grep -qF '.local/bin' "$rc_file" 2>/dev/null; then
        info "PATH already configured in $rc_file"
        return
    fi
    
    # Add to rc file
    echo "" >> "$rc_file"
    echo "# Added by sync-shuttle installer" >> "$rc_file"
    echo "$path_line" >> "$rc_file"
    
    success "Added ~/.local/bin to PATH in $rc_file"
}

initialize_sync_shuttle() {
    info "Initializing sync-shuttle..."

    "${INSTALL_DIR}/sync-shuttle.sh" init || warn "Initialization skipped (may already exist)"
}

setup_python_venv() {
    # Check if Python 3 is available
    if ! command -v python3 &>/dev/null; then
        warn "Python 3 not found - TUI will not be available"
        warn "Install Python 3 and re-run installer to enable TUI"
        return 0
    fi

    local venv_dir="${INSTALL_DIR}/.venv"

    info "Setting up Python virtual environment for TUI..."

    # Create venv
    if ! python3 -m venv "$venv_dir" 2>/dev/null; then
        warn "Failed to create venv - TUI will not be available"
        warn "You may need to install python3-venv package"
        return 0
    fi

    # Install dependencies in venv
    if "${venv_dir}/bin/pip" install --quiet textual rich 2>/dev/null; then
        success "TUI dependencies installed in isolated venv"
    else
        warn "Failed to install TUI dependencies"
        warn "TUI may not work - run: ${venv_dir}/bin/pip install textual rich"
    fi
}

print_completion() {
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}Sync Shuttle installed successfully!${RESET}"
    echo -e "${BOLD}════════════════════════════════════════════════════════════${RESET}"
    echo ""
    echo "Installation directory: ${INSTALL_DIR}"
    echo "Binary location:        ${BIN_DIR}/sync-shuttle"
    echo "Data directory:         ~/.sync-shuttle/"
    echo ""
    echo -e "${BOLD}Quick Start:${RESET}"
    echo ""
    echo "  1. Restart your shell or run:"
    echo "     source $(detect_shell_rc)"
    echo ""
    echo "  2. Configure a server:"
    echo "     nano ~/.sync-shuttle/config/servers.toml"
    echo ""
    echo "  3. Test with dry-run:"
    echo "     sync-shuttle push -s myserver -S ~/file.txt --dry-run"
    echo ""
    echo "  4. (Optional) Launch the TUI:"
    echo "     sync-shuttle tui"
    echo ""
    echo -e "${BOLD}Documentation:${RESET} ${INSTALL_DIR}/README.md"
    echo ""
}

#===============================================================================
# MAIN
#===============================================================================
main() {
    echo ""
    echo -e "${BOLD}╔═══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║           SYNC SHUTTLE INSTALLER                          ║${RESET}"
    echo -e "${BOLD}╚═══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    
    # Pre-flight checks
    info "Checking dependencies..."
    check_dependencies
    success "All dependencies found"
    
    # Remove existing installation
    if [[ -d "$INSTALL_DIR" ]]; then
        warn "Existing installation found at $INSTALL_DIR"
        info "Backing up to ${INSTALL_DIR}.bak"
        rm -rf "${INSTALL_DIR}.bak" 2>/dev/null || true
        mv "$INSTALL_DIR" "${INSTALL_DIR}.bak"
    fi
    
    # Download
    download_release "$INSTALL_DIR"
    success "Downloaded to $INSTALL_DIR"
    
    # Install
    install_binary

    # Setup Python venv for TUI
    setup_python_venv

    # Update shell RC
    update_shell_rc

    # Initialize
    initialize_sync_shuttle

    # Done
    print_completion
}

main "$@"
