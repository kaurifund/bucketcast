#!/usr/bin/env bash
#===============================================================================
# migrate.sh - Migrate sync-shuttle installation to bucketcast
#===============================================================================
#
# Safe, idempotent migration for users who installed under the old
# "sync-shuttle" name. Moves data, renames configs, and updates paths.
#
# Usage:
#   bash migrate.sh              # interactive (prompts before changes)
#   bash migrate.sh --yes        # non-interactive (skip prompts)
#   bash migrate.sh --dry-run    # preview what would change
#
# What it does:
#   1. Moves ~/.sync-shuttle/ -> ~/.bucketcast/        (user data)
#   2. Moves ~/.local/share/sync-shuttle/ -> .../bucketcast/  (install dir)
#   3. Renames config/sync-shuttle.conf -> config/bucketcast.conf
#   4. Updates SYNC_BASE_DIR references inside the config
#   5. Updates remote_base paths in servers.toml
#   6. Updates shell RC (PATH entry) if present
#   7. Updates ~/.local/bin/ wrapper script if present
#
# What it does NOT do:
#   - Delete anything (moves only, originals are gone after mv)
#   - Touch remote servers (prints a reminder instead)
#   - Modify file contents beyond path string replacements
#   - Run if there is nothing to migrate
#
# Idempotent: safe to run multiple times. Skips steps already done.
#
#===============================================================================

OLD_DATA_DIR="$HOME/.sync-shuttle"
NEW_DATA_DIR="$HOME/.bucketcast"

OLD_INSTALL_DIR="$HOME/.local/share/sync-shuttle"
NEW_INSTALL_DIR="$HOME/.local/share/bucketcast"

OLD_BIN="$HOME/.local/bin/sync-shuttle"
NEW_BIN="$HOME/.local/bin/bucketcast"

DRY_RUN=false
AUTO_YES=false
CHANGES=0
WARNINGS=0

#===============================================================================
# OUTPUT HELPERS
#===============================================================================
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
else
    RED="" GREEN="" YELLOW="" BOLD="" RESET=""
fi

info()    { printf "%s[INFO]%s %s\n" "$BOLD" "$RESET" "$1"; }
ok()      { printf "%s[OK]%s %s\n" "$GREEN" "$RESET" "$1"; }
warn()    { printf "%s[WARN]%s %s\n" "$YELLOW" "$RESET" "$1"; WARNINGS=$((WARNINGS + 1)); }
err()     { printf "%s[ERROR]%s %s\n" "$RED" "$RESET" "$1"; }
skip()    { printf "%s[SKIP]%s %s\n" "$BOLD" "$RESET" "$1"; }
dry()     { printf "%s[DRY-RUN]%s Would: %s\n" "$YELLOW" "$RESET" "$1"; }
changed() { CHANGES=$((CHANGES + 1)); }

confirm() {
    if $AUTO_YES; then return 0; fi
    if $DRY_RUN; then return 0; fi
    printf "\n%s%s%s [y/N] " "$BOLD" "$1" "$RESET"
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

#===============================================================================
# PARSE ARGS
#===============================================================================
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --yes|-y)  AUTO_YES=true ;;
        --help|-h)
            printf "Usage: bash migrate.sh [--dry-run] [--yes] [--help]\n"
            printf "  --dry-run  Preview changes without applying them\n"
            printf "  --yes      Skip confirmation prompts\n"
            exit 0
            ;;
        *)
            err "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

#===============================================================================
# PRE-FLIGHT: Is there anything to migrate?
#===============================================================================
printf "\n%s════════════════════════════════════════════════════════════%s\n" "$BOLD" "$RESET"
printf "%s  Bucketcast Migration (sync-shuttle -> bucketcast)%s\n" "$BOLD" "$RESET"
printf "%s════════════════════════════════════════════════════════════%s\n\n" "$BOLD" "$RESET"

HAS_WORK=false

if [[ -d "$OLD_DATA_DIR" ]]; then
    info "Found old data directory: $OLD_DATA_DIR"
    HAS_WORK=true
fi
if [[ -d "$OLD_INSTALL_DIR" ]]; then
    info "Found old install directory: $OLD_INSTALL_DIR"
    HAS_WORK=true
fi
if [[ -f "$OLD_BIN" ]]; then
    info "Found old binary: $OLD_BIN"
    HAS_WORK=true
fi
# Check for old references in configs that already live at new location
if [[ -d "$NEW_DATA_DIR" ]]; then
    if [[ -f "$NEW_DATA_DIR/config/sync-shuttle.conf" ]]; then
        info "Found old config name at new location"
        HAS_WORK=true
    fi
    if [[ -f "$NEW_DATA_DIR/config/servers.toml" ]] && grep -q '\.sync-shuttle' "$NEW_DATA_DIR/config/servers.toml" 2>/dev/null; then
        info "Found old path references in servers.toml"
        HAS_WORK=true
    fi
fi

if ! $HAS_WORK; then
    ok "Nothing to migrate. Already using bucketcast or fresh install."
    exit 0
fi

if $DRY_RUN; then
    info "Dry-run mode: showing what would change"
    printf "\n"
fi

if ! $DRY_RUN && ! $AUTO_YES; then
    printf "\nThis will rename sync-shuttle paths to bucketcast.\n"
    printf "Your data, configs, and history will be preserved.\n"
    if ! confirm "Proceed with migration?"; then
        info "Aborted by user."
        exit 0
    fi
    printf "\n"
fi

#===============================================================================
# STEP 1: Move data directory ~/.sync-shuttle/ -> ~/.bucketcast/
#===============================================================================
info "Step 1: Data directory"

if [[ -d "$OLD_DATA_DIR" ]] && [[ ! -d "$NEW_DATA_DIR" ]]; then
    if $DRY_RUN; then
        dry "mv $OLD_DATA_DIR -> $NEW_DATA_DIR"
    else
        mv "$OLD_DATA_DIR" "$NEW_DATA_DIR"
        ok "Moved $OLD_DATA_DIR -> $NEW_DATA_DIR"
    fi
    changed
elif [[ -d "$OLD_DATA_DIR" ]] && [[ -d "$NEW_DATA_DIR" ]]; then
    warn "Both $OLD_DATA_DIR and $NEW_DATA_DIR exist"
    warn "Skipping move to avoid data loss. Merge manually if needed."
elif [[ ! -d "$OLD_DATA_DIR" ]]; then
    skip "No $OLD_DATA_DIR found"
fi

#===============================================================================
# STEP 2: Move install directory
#===============================================================================
info "Step 2: Install directory"

if [[ -d "$OLD_INSTALL_DIR" ]] && [[ ! -d "$NEW_INSTALL_DIR" ]]; then
    if $DRY_RUN; then
        dry "mv $OLD_INSTALL_DIR -> $NEW_INSTALL_DIR"
    else
        mv "$OLD_INSTALL_DIR" "$NEW_INSTALL_DIR"
        ok "Moved $OLD_INSTALL_DIR -> $NEW_INSTALL_DIR"
    fi
    changed
elif [[ -d "$OLD_INSTALL_DIR" ]] && [[ -d "$NEW_INSTALL_DIR" ]]; then
    warn "Both install dirs exist. Old: $OLD_INSTALL_DIR"
    warn "Skipping. Remove the old one manually if no longer needed."
elif [[ ! -d "$OLD_INSTALL_DIR" ]]; then
    skip "No $OLD_INSTALL_DIR found"
fi

#===============================================================================
# STEP 3: Rename config file sync-shuttle.conf -> bucketcast.conf
#===============================================================================
info "Step 3: Config file rename"

# Work with whichever data dir exists now
DATA_DIR="$NEW_DATA_DIR"
if [[ ! -d "$DATA_DIR" ]]; then
    DATA_DIR="$OLD_DATA_DIR"
fi

OLD_CONF="$DATA_DIR/config/sync-shuttle.conf"
NEW_CONF="$DATA_DIR/config/bucketcast.conf"

if [[ -f "$OLD_CONF" ]] && [[ ! -f "$NEW_CONF" ]]; then
    if $DRY_RUN; then
        dry "mv $OLD_CONF -> $NEW_CONF"
    else
        mv "$OLD_CONF" "$NEW_CONF"
        ok "Renamed sync-shuttle.conf -> bucketcast.conf"
    fi
    changed
elif [[ -f "$OLD_CONF" ]] && [[ -f "$NEW_CONF" ]]; then
    warn "Both config files exist. Old kept at: $OLD_CONF"
elif [[ ! -f "$OLD_CONF" ]]; then
    skip "No sync-shuttle.conf to rename"
fi

#===============================================================================
# STEP 4: Update SYNC_BASE_DIR inside config
#===============================================================================
info "Step 4: Update paths in config"

# Check both old and new name (old may still exist in dry-run or if rename was skipped)
CONF_FILE="$NEW_CONF"
if [[ ! -f "$CONF_FILE" ]]; then
    CONF_FILE="$OLD_CONF"
fi

if [[ -f "$CONF_FILE" ]] && grep -q '\.sync-shuttle' "$CONF_FILE" 2>/dev/null; then
    if $DRY_RUN; then
        dry "Replace .sync-shuttle with .bucketcast in $CONF_FILE"
        grep '\.sync-shuttle' "$CONF_FILE" | while read -r line; do
            printf "       %s\n" "$line"
        done
    else
        sed -i 's|\.sync-shuttle|.bucketcast|g' "$CONF_FILE"
        ok "Updated paths in $(basename "$CONF_FILE")"
    fi
    changed
else
    skip "No old paths in config"
fi

#===============================================================================
# STEP 5: Update remote_base in servers.toml
#===============================================================================
info "Step 5: Update remote_base in servers.toml"

SERVERS_FILE="$DATA_DIR/config/servers.toml"

if [[ -f "$SERVERS_FILE" ]] && grep -q '\.sync-shuttle' "$SERVERS_FILE" 2>/dev/null; then
    if $DRY_RUN; then
        dry "Replace .sync-shuttle with .bucketcast in servers.toml"
        grep '\.sync-shuttle' "$SERVERS_FILE" | while read -r line; do
            printf "       %s\n" "$line"
        done
    else
        sed -i 's|\.sync-shuttle|.bucketcast|g' "$SERVERS_FILE"
        ok "Updated remote_base paths in servers.toml"
    fi
    changed
    warn "Remote servers still have ~/.sync-shuttle/ directories"
    warn "Run this script (or mv ~/.sync-shuttle ~/.bucketcast) on each remote host"
else
    skip "No old paths in servers.toml"
fi

#===============================================================================
# STEP 6: Update shell RC files
#===============================================================================
info "Step 6: Shell RC files"

RC_UPDATED=false
for rc_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/fish/config.fish" "$HOME/.profile" "$HOME/.bash_profile"; do
    if [[ -f "$rc_file" ]] && grep -q 'sync-shuttle' "$rc_file" 2>/dev/null; then
        if $DRY_RUN; then
            dry "Replace sync-shuttle references in $rc_file"
            grep 'sync-shuttle' "$rc_file" | while read -r line; do
                printf "       %s\n" "$line"
            done
        else
            sed -i 's|sync-shuttle|bucketcast|g' "$rc_file"
            ok "Updated $rc_file"
        fi
        RC_UPDATED=true
        changed
    fi
done

if ! $RC_UPDATED; then
    skip "No sync-shuttle references in shell RC files"
fi

#===============================================================================
# STEP 7: Update or replace bin wrapper
#===============================================================================
info "Step 7: Binary wrapper"

if [[ -f "$OLD_BIN" ]] && [[ ! -f "$NEW_BIN" ]]; then
    if $DRY_RUN; then
        dry "mv $OLD_BIN -> $NEW_BIN"
    else
        mv "$OLD_BIN" "$NEW_BIN"
        # Update the wrapper content to point to new install dir
        if grep -q 'sync-shuttle' "$NEW_BIN" 2>/dev/null; then
            sed -i 's|sync-shuttle|bucketcast|g' "$NEW_BIN"
        fi
        ok "Moved and updated bin wrapper"
    fi
    changed
elif [[ -f "$OLD_BIN" ]] && [[ -f "$NEW_BIN" ]]; then
    warn "Both $OLD_BIN and $NEW_BIN exist"
    warn "Remove $OLD_BIN manually if it is no longer needed"
elif [[ ! -f "$OLD_BIN" ]]; then
    skip "No old binary wrapper found"
fi

#===============================================================================
# STEP 8: Handle .syncshuttlerc -> .bucketcastrc
#===============================================================================
info "Step 8: User RC file"

OLD_RC="$HOME/.syncshuttlerc"
NEW_RC="$HOME/.bucketcastrc"

if [[ -f "$OLD_RC" ]] && [[ ! -f "$NEW_RC" ]]; then
    if $DRY_RUN; then
        dry "mv $OLD_RC -> $NEW_RC"
    else
        mv "$OLD_RC" "$NEW_RC"
        if grep -q 'sync-shuttle\|SYNC_SHUTTLE' "$NEW_RC" 2>/dev/null; then
            sed -i 's|sync-shuttle|bucketcast|g; s|SYNC_SHUTTLE|BUCKETCAST|g; s|sync_shuttle|bucketcast|g' "$NEW_RC"
        fi
        ok "Moved and updated .syncshuttlerc -> .bucketcastrc"
    fi
    changed
elif [[ -f "$OLD_RC" ]] && [[ -f "$NEW_RC" ]]; then
    warn "Both $OLD_RC and $NEW_RC exist. Old one left in place."
elif [[ ! -f "$OLD_RC" ]]; then
    skip "No .syncshuttlerc found"
fi

#===============================================================================
# SUMMARY
#===============================================================================
printf "\n%s════════════════════════════════════════════════════════════%s\n" "$BOLD" "$RESET"

if $DRY_RUN; then
    printf "%s  Dry-run complete: %d change(s) would be made%s\n" "$BOLD" "$CHANGES" "$RESET"
    printf "%s  Run without --dry-run to apply.%s\n" "$BOLD" "$RESET"
elif [[ "$CHANGES" -gt 0 ]]; then
    printf "%s%s  Migration complete: %d change(s) applied%s\n" "$BOLD" "$GREEN" "$CHANGES" "$RESET"
    if [[ "$WARNINGS" -gt 0 ]]; then
        printf "%s  %d warning(s) - review output above%s\n" "$YELLOW" "$WARNINGS" "$RESET"
    fi
    printf "\n  Next steps:\n"
    printf "    1. Restart your shell: exec \$SHELL\n"
    printf "    2. Verify: bucketcast --version\n"
    printf "    3. Check config: bucketcast list servers\n"
    if [[ "$WARNINGS" -gt 0 ]]; then
        printf "    4. Review warnings above\n"
    fi
else
    printf "%s  No changes needed%s\n" "$GREEN" "$RESET"
fi

printf "%s════════════════════════════════════════════════════════════%s\n\n" "$BOLD" "$RESET"

exit 0
