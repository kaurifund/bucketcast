#!/usr/bin/env bash
# =============================================================================
# apply_rename.sh - Apply sync-shuttle -> bucketcast rename
# =============================================================================
# Auditable, idempotent rename script. Safe to run multiple times.
# Run from the project root directory.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

printf "Project root: %s\n" "$PROJECT_ROOT"

# ---------------------------------------------------------------------------
# Phase 1: Content replacements (most-specific patterns first)
# ---------------------------------------------------------------------------
printf "\n=== Phase 1: Content Replacements ===\n"

FILES=(
  .gitignore
  README.md
  SPECIFICATION.md
  install.sh
  sync-shuttle.sh
  lib/core.sh
  lib/logging.sh
  lib/s3.sh
  lib/transfer.sh
  lib/validation.sh
  lib/config_parser.py
  config/sync-shuttle.conf.example
  config/.syncshuttlerc.example
  config/servers.toml.example
  tui/sync_tui.py
  tui/requirements.txt
  tests/run_tests.sh
  tests/helpers/test_helpers.sh
  tests/helpers/fixtures.sh
  tests/e2e/test_scenarios.sh
  tests/integration/test_config.sh
  tests/integration/test_transfer.sh
  tests/fixtures/sample_config.conf
  tests/fixtures/sample_servers.conf
  _other/AUDIT_REPORT.md
  _other/llm.txt
  _other/llm-v1.0.txt
  tickets/BUG_RSYNC_FOLDER_STRUCTURE.md
  tickets/BUG_STAGING_ACCUMULATION.md
)

# Order matters: longest / most-specific patterns first to avoid partial matches.
PATTERNS=(
  's/SyncShuttleTUI/BucketcastTUI/g'        # 1. PascalCase class (longest compound)
  's/SYNC_SHUTTLE/BUCKETCAST/g'              # 2. UPPER_SNAKE env vars
  's/SYNC-SHUTTLE/BUCKETCAST/g'              # 3. UPPER-KEBAB headers
  's/SYNC SHUTTLE/BUCKETCAST/g'              # 4. UPPER SPACE banners
  's/Sync Shuttle/Bucketcast/g'              # 5. Title Case prose
  's/sync-shuttle/bucketcast/g'              # 6. kebab-case (most common)
  's/sync_shuttle/bucketcast/g'              # 7. snake_case variables
  's/\.syncshuttlerc/.bucketcastrc/g'        # 8. rc filename (before generic no-sep)
  's/syncshuttle/bucketcast/g'              # 9. no-separator residuals
  's/sync_tui/bucketcast_tui/g'              # 10. TUI module name
)

for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    printf "  SKIP (not found, maybe already renamed): %s\n" "$f"
    continue
  fi
  for pat in "${PATTERNS[@]}"; do
    sed -i "$pat" "$f"
  done
  printf "  OK: %s\n" "$f"
done

printf "Phase 1 complete.\n"

# ---------------------------------------------------------------------------
# Phase 2: File renames (git mv)
# ---------------------------------------------------------------------------
printf "\n=== Phase 2: File Renames ===\n"

rename_file() {
  local old="$1"
  local new="$2"
  if [ -f "$old" ]; then
    git mv "$old" "$new"
    printf "  RENAMED: %s -> %s\n" "$old" "$new"
  elif [ -f "$new" ]; then
    printf "  SKIP (already renamed): %s\n" "$new"
  else
    printf "  ERROR: neither %s nor %s found\n" "$old" "$new"
  fi
}

rename_file "sync-shuttle.sh"                    "bucketcast.sh"
rename_file "config/sync-shuttle.conf.example"   "config/bucketcast.conf.example"
rename_file "config/.syncshuttlerc.example"      "config/.bucketcastrc.example"
rename_file "tui/sync_tui.py"                    "tui/bucketcast_tui.py"

printf "Phase 2 complete.\n"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
printf "\n=== apply_rename.sh complete ===\n"
printf "Run test.sh to verify results.\n"
