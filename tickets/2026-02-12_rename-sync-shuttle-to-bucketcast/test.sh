#!/usr/bin/env bash
# =============================================================================
# test.sh - Verify sync-shuttle -> bucketcast rename
# =============================================================================
# Idempotent verification script. Safe to run multiple times.
# Returns 0 if all checks pass, 1 if any fail.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TICKET_DIR="$SCRIPT_DIR"

PASS=0
FAIL=0
TOTAL=0

pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    printf "  PASS: %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    printf "  FAIL: %s\n" "$1"
}

# ---------------------------------------------------------------------------
# Section 1: No old name references remain
# ---------------------------------------------------------------------------
printf "\n=== Section 1: Old name references must be gone ===\n"

# Helper: grep for old pattern, excluding ticket folder and .git
check_no_old_refs() {
    local pattern="$1"
    local label="$2"
    local count
    count=$(grep -ri "$pattern" "$PROJECT_ROOT" \
        --include='*.sh' --include='*.py' --include='*.md' \
        --include='*.toml' --include='*.conf' --include='*.txt' \
        --include='*.example' --include='.gitignore' \
        -l 2>/dev/null \
        | grep -v "$TICKET_DIR" \
        | grep -v ".git/" \
        | wc -l)
    if [ "$count" -eq 0 ]; then
        pass "No files contain '$pattern' (excluding ticket folder)"
    else
        fail "Found $count file(s) still containing '$pattern'"
        grep -ri "$pattern" "$PROJECT_ROOT" \
            --include='*.sh' --include='*.py' --include='*.md' \
            --include='*.toml' --include='*.conf' --include='*.txt' \
            --include='*.example' --include='.gitignore' \
            -l 2>/dev/null \
            | grep -v "$TICKET_DIR" \
            | grep -v ".git/" \
            | while read -r f; do printf "    -> %s\n" "$f"; done
    fi
}

check_no_old_refs "sync-shuttle" "kebab-case"
check_no_old_refs "sync_shuttle" "snake_case"
check_no_old_refs "Sync Shuttle" "Title Case"
check_no_old_refs "SYNC SHUTTLE" "UPPER CASE"
check_no_old_refs "SYNC_SHUTTLE" "UPPER_SNAKE"
check_no_old_refs "SYNC-SHUTTLE" "UPPER-KEBAB"
check_no_old_refs "SyncShuttle" "PascalCase"
check_no_old_refs "syncshuttle" "no-separator"
check_no_old_refs "sync_tui" "TUI module old name"

# ---------------------------------------------------------------------------
# Section 2: Renamed files exist
# ---------------------------------------------------------------------------
printf "\n=== Section 2: Renamed files must exist ===\n"

check_file_exists() {
    local filepath="$1"
    if [ -f "$PROJECT_ROOT/$filepath" ]; then
        pass "File exists: $filepath"
    else
        fail "File missing: $filepath"
    fi
}

check_file_exists "bucketcast.sh"
check_file_exists "config/bucketcast.conf.example"
check_file_exists "config/.bucketcastrc.example"
check_file_exists "tui/bucketcast_tui.py"

# ---------------------------------------------------------------------------
# Section 3: Old filenames must be gone
# ---------------------------------------------------------------------------
printf "\n=== Section 3: Old filenames must be gone ===\n"

check_file_gone() {
    local filepath="$1"
    if [ -f "$PROJECT_ROOT/$filepath" ]; then
        fail "Old file still exists: $filepath"
    else
        pass "Old file removed: $filepath"
    fi
}

check_file_gone "sync-shuttle.sh"
check_file_gone "config/sync-shuttle.conf.example"
check_file_gone "config/.syncshuttlerc.example"
check_file_gone "tui/sync_tui.py"

# ---------------------------------------------------------------------------
# Section 4: New name appears in key locations
# ---------------------------------------------------------------------------
printf "\n=== Section 4: New name present in key locations ===\n"

check_contains() {
    local filepath="$1"
    local pattern="$2"
    local label="$3"
    if [ ! -f "$PROJECT_ROOT/$filepath" ]; then
        fail "$label - file not found: $filepath"
        return
    fi
    if grep -q "$pattern" "$PROJECT_ROOT/$filepath" 2>/dev/null; then
        pass "$label"
    else
        fail "$label - '$pattern' not found in $filepath"
    fi
}

check_contains "README.md" "Bucketcast" "README.md contains 'Bucketcast'"
check_contains "README.md" "bucketcast" "README.md contains 'bucketcast'"
check_contains "bucketcast.sh" "BUCKETCAST" "bucketcast.sh contains 'BUCKETCAST'"
check_contains "bucketcast.sh" "bucketcast" "bucketcast.sh contains 'bucketcast'"
check_contains "install.sh" "BUCKETCAST" "install.sh contains 'BUCKETCAST' env vars"
check_contains "install.sh" "bucketcast" "install.sh contains 'bucketcast' paths"
check_contains ".gitignore" "BUCKETCAST" "gitignore contains 'BUCKETCAST'"
check_contains ".gitignore" "bucketcast" "gitignore contains 'bucketcast'"
check_contains "tui/bucketcast_tui.py" "BucketcastTUI" "TUI has BucketcastTUI class"
check_contains "tui/bucketcast_tui.py" "Bucketcast" "TUI references Bucketcast"
check_contains "config/bucketcast.conf.example" "BUCKETCAST" "Config example has BUCKETCAST header"
check_contains "config/.bucketcastrc.example" "BUCKETCAST" "RC example has BUCKETCAST header"
check_contains "SPECIFICATION.md" "Bucketcast" "Spec references Bucketcast"
check_contains "tests/run_tests.sh" "BUCKETCAST" "Test runner references BUCKETCAST"
check_contains "tests/helpers/test_helpers.sh" "bucketcast" "Test helpers reference bucketcast"
check_contains "tests/e2e/test_scenarios.sh" "bucketcast" "E2E tests reference bucketcast"
check_contains "lib/core.sh" "BUCKETCAST" "Core lib has BUCKETCAST header"
check_contains "lib/validation.sh" "Bucketcast" "Validation lib references Bucketcast"

# ---------------------------------------------------------------------------
# Section 5: Cross-references are consistent
# ---------------------------------------------------------------------------
printf "\n=== Section 5: Cross-references are consistent ===\n"

# Main script references TUI with new name
check_contains "bucketcast.sh" "bucketcast_tui.py" "Main script references bucketcast_tui.py"

# Tests reference the new main script name
check_contains "tests/helpers/test_helpers.sh" "bucketcast.sh" "Test helpers reference bucketcast.sh"
check_contains "tests/e2e/test_scenarios.sh" "bucketcast.sh" "E2E tests reference bucketcast.sh"

# Config references use new name
check_contains "config/servers.toml.example" "bucketcast" "Servers config uses bucketcast paths"

# Fixture files use new names
check_contains "tests/fixtures/sample_config.conf" "bucketcast" "Sample config uses bucketcast"
check_contains "tests/fixtures/sample_servers.conf" "bucketcast" "Sample servers uses bucketcast"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf "\n=== Summary ===\n"
printf "  Total: %d | Pass: %d | Fail: %d\n\n" "$TOTAL" "$PASS" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
    printf "RESULT: FAILED (%d failures)\n\n" "$FAIL"
    exit 1
else
    printf "RESULT: ALL CHECKS PASSED\n\n"
    exit 0
fi
