# Implementation Plan: Inbox/Outbox Symmetry

**Ticket:** 20260105_outbox_inbox_symmetry
**Status:** Draft - Awaiting Approval

---

## Git Strategy

### Current Open PRs

| PR | Branch | Description | Files Touched |
|----|--------|-------------|---------------|
| #2 | feature/file-discovery | File discovery commands | sync-shuttle.sh, tui/, docs/ |
| #3 | feature/push-positional-args | Positional args for push | sync-shuttle.sh, lib/transfer.sh |

PR #3 is stacked on PR #2.

### Overlap Analysis

This ticket touches:
- `sync-shuttle.sh` - new share command, argument parsing (**OVERLAPS with PR #2, #3**)
- `lib/transfer.sh` - pull logic changes (**OVERLAPS with PR #3**)
- `tests/` - new test cases

### Recommended Approach

**Option A (Recommended): Wait for PRs to merge, then branch from main**
- Safest, cleanest history
- No complex stacking or conflict resolution
- Delay: depends on PR review/merge timeline

**Option B: Stack on PR #3 (create PR #4)**
- Can start immediately
- Risk: if PR #2 or #3 changes, need to rebase
- More complex git management

**Option C: Branch from main, merge later**
- Independent work
- Will have merge conflicts with PR #2/#3
- More work during integration

### Decision

**Option C Selected:** Branch from main, resolve conflicts later.

Rationale:
- Independent work, not blocked by PR #2/#3 review timeline
- Conflicts will be resolved during integration
- Allows parallel progress

**Branch:** `feature/outbox-inbox-symmetry`

---

## Directory Structure (Updated)

### Reserved Namespaces

The following names are **reserved** and cannot be used as server IDs:
- `global` - used for global shares

### Target Structure

```
~/.sync-shuttle/local/
├── inbox/
│   └── <server_id>/           # Files received FROM this server
│       └── files...
└── outbox/
    ├── global/                # Global share (all servers can pull)
    │   └── files...
    └── <server_id>/           # Server-specific share
        └── files...
```

**Note:** No files at `outbox/` root level. Everything is namespaced.

### Pull Logic

When pulling from remote, check in order:
1. `remote:local/outbox/global/` (global shares)
2. `remote:local/outbox/<your_hostname>/` (server-specific shares)

This prevents accidentally syncing someone else's per-server outbox.

---

## Task Overview

| # | Task | Status | Complexity |
|---|------|--------|------------|
| 0 | Add reserved namespace validation ("global" cannot be server ID) | [ ] | Low |
| 1 | Update pull to check global/ and per-server outbox on remote | [ ] | Medium |
| 2 | Update directory initialization for new outbox structure | [ ] | Low |
| 3 | Add optional auto-population of local outbox/<server>/ on push | [ ] | Medium |
| 4 | Update documentation (SPECIFICATION.md, README.md) | [ ] | Low |
| 5 | Update tests to reflect new structure | [ ] | Medium |
| 6 | Add `share` command for managing outbox | [ ] | Medium |
| 7 | Migrate existing outbox/ files to outbox/global/ | [ ] | Low |

---

$---

## Task 0: Add Reserved Namespace Validation

### Description
Prevent "global" (and potentially other reserved words) from being used as server IDs.

### Current Code
Server ID validation exists in `lib/validation.sh` or during config parsing.

### Proposed Change
```bash
# Reserved namespaces that cannot be used as server IDs
readonly RESERVED_NAMESPACES=("global")

validate_server_id() {
    local server_id="$1"

    # Check reserved namespaces
    for reserved in "${RESERVED_NAMESPACES[@]}"; do
        if [[ "$server_id" == "$reserved" ]]; then
            log_error "Server ID '$server_id' is reserved and cannot be used"
            return 1
        fi
    done

    # ... existing validation ...
}
```

### Files Affected
- `lib/validation.sh` or `sync-shuttle.sh` (server config parsing)

### Verification Steps
1. Try to add a server with ID "global" - should fail
2. Existing servers should still work
3. Error message is clear

### Rollback
Remove reserved namespace check.

$---

## Task 1: Update Pull to Check Global and Per-Server Outbox on Remote

### Description
When pulling from a remote server, check both:
1. `remote:local/outbox/global/` (global share - available to all)
2. `remote:local/outbox/<your_hostname>/` (server-specific share - just for you)

### Current Code (lib/transfer.sh:236)
```bash
local remote_src="${server_user}@${server_host}:${server_remote_base}/local/outbox/"
```

### Proposed Change
```bash
# Pull from both global and per-server outbox
local remote_global="${server_user}@${server_host}:${server_remote_base}/local/outbox/global/"
local remote_specific="${server_user}@${server_host}:${server_remote_base}/local/outbox/${HOSTNAME:-$(hostname)}/"

# Pull global first, then server-specific (server-specific can override)
rsync ... "$remote_global" "$local_dest/"      # Global shares
rsync ... "$remote_specific" "$local_dest/"    # Server-specific (only if exists)
```

### Why This Order?
- Global first, then specific - allows server-specific to override global
- Only pulls from `global/` and `<hostname>/` - never pulls other server's folders

### Files Affected
- `lib/transfer.sh` (lines 230-260)

### Verification Steps
1. Create test file in remote's `outbox/` (global)
2. Create test file in remote's `outbox/<hostname>/` (specific)
3. Run pull, verify both files arrive
4. Verify no errors if specific directory doesn't exist

### Rollback
Revert to single remote_src if issues arise.

$---

## Task 2: Update Directory Initialization

### Description
When initializing sync-shuttle, create the per-server outbox structure capability.

### Current Code (sync-shuttle.sh:1181)
```bash
for dir in "$CONFIG_DIR" "$REMOTE_DIR" "$INBOX_DIR" "$OUTBOX_DIR" "$LOGS_DIR"; do
```

### Proposed Change
No change to init - directories are created on-demand when needed. The structure supports:
```
local/outbox/           # Global (already exists)
local/outbox/<server>/  # Created when sharing with specific server
```

### Files Affected
- Potentially `action_init()` if we want to pre-create structure
- Or no change - create on demand

### Verification Steps
1. Run `sync-shuttle init` on fresh install
2. Verify `local/outbox/` exists
3. Verify per-server dirs created on-demand during push/share

### Rollback
N/A - minimal change

$---

## Task 3: Auto-Populate Local Outbox on Push (Optional Feature)

### Description
When pushing files to a server, optionally copy them to `local/outbox/<server>/` as a record of what was shared.

### Current Flow
```
User file → staging → remote inbox
```

### Proposed Flow
```
User file → staging → remote inbox
                   ↘ local outbox/<server>/ (record)
```

### Implementation Options

**Option A: Always copy to outbox (automatic record)**
```bash
# After successful push to remote
cp -r "$SOURCE_PATH" "${OUTBOX_DIR}/${SERVER_ID}/"
```

**Option B: Flag to enable (--share)**
```bash
sync-shuttle push -s server file.txt --share
# Pushes AND adds to outbox/<server>/
```

**Option C: Separate command**
```bash
sync-shuttle push -s server file.txt   # Just push
sync-shuttle share -s server file.txt  # Add to outbox/<server>/
```

### Recommendation
Option C - keeps push simple, share is explicit action.

### Files Affected
- `sync-shuttle.sh` (new `action_share()` function)
- Argument parsing for new command

### Verification Steps
1. Run share command
2. Verify file appears in `outbox/<server>/`
3. From remote, pull and verify file arrives

### Rollback
Remove share command, outbox/<server>/ directories.

$---

## Task 4: Update Documentation

### Description
Update SPECIFICATION.md and README.md to reflect new directory structure.

### Files Affected

**SPECIFICATION.md** (lines 40, 80-82, 170):
```markdown
# Before
│   └── outbox/                # Files staged for sending

# After
│   └── outbox/                # Files shared with remotes
│       ├── <server_id>/       # Server-specific shares
│       └── (global files)     # Available to all servers
```

**README.md** (line 70):
```markdown
# Before
│   └── outbox/              # Files staged for sending

# After
│   └── outbox/              # Files shared with remotes (per-server + global)
```

### Verification Steps
1. Read updated docs
2. Verify examples are accurate
3. Verify no broken references

### Rollback
Revert markdown changes.

$---

## Task 5: Update Tests

### Description
Update test fixtures and assertions to handle new outbox structure.

### Files Affected
- `tests/integration/test_config.sh` (lines 21, 26, 183, 191)
- `tests/helpers/fixtures.sh` (line 170)
- `tests/e2e/test_scenarios.sh` (line 39)

### Changes Needed
1. Update directory creation to optionally include per-server outbox
2. Add tests for pull from per-server outbox
3. Add tests for share command (if implemented)

### Verification Steps
1. Run full test suite: `./tests/run_tests.sh`
2. Verify all tests pass
3. Verify new functionality is covered

### Rollback
Revert test changes.

$---

## Task 6: Add Share Command

### Description
New command to add files to outbox for a specific server.

### CLI Design
```bash
# Add file to server-specific outbox
sync-shuttle share -s server file.txt
# → goes to outbox/<server>/

# Add file to global outbox (all servers)
sync-shuttle share --global file.txt
# → goes to outbox/global/

# List what's shared
sync-shuttle share --list
sync-shuttle share -s server --list
sync-shuttle share --global --list

# Remove from share
sync-shuttle share -s server --remove file.txt
sync-shuttle share --global --remove file.txt
```

### Implementation

**New function in sync-shuttle.sh:**
```bash
action_share() {
    local share_dir

    if [[ -n "$SERVER_ID" ]]; then
        share_dir="${OUTBOX_DIR}/${SERVER_ID}"
    elif [[ "$GLOBAL_MODE" == "true" ]]; then
        share_dir="${OUTBOX_DIR}/global"
    else
        log_error "Must specify -s <server> or --global"
        exit 2
    fi

    mkdir -p "$share_dir"

    if [[ "$LIST_MODE" == "true" ]]; then
        find "$share_dir" -type f
    elif [[ "$REMOVE_MODE" == "true" ]]; then
        rm -f "${share_dir}/$(basename "$SOURCE_PATH")"
    else
        cp -r "$SOURCE_PATH" "$share_dir/"
    fi
}
```

**Argument parsing additions:**
- New action: `share`
- New flags: `--list`, `--remove`, `--global`

### Verification Steps
1. `share -s server file.txt` - verify file in `outbox/<server>/`
2. `share --global file.txt` - verify file in `outbox/global/`
3. `share --list` - verify lists files
4. `share --remove file.txt` - verify removes file
5. Remote pull - verify shared files arrive

### Rollback
Remove action_share function and argument parsing.

$---

## Task 7: Migrate Existing Outbox Files

### Description
Move any existing files from `outbox/` root to `outbox/global/` for backward compatibility.

### Migration Logic
```bash
# One-time migration during init or upgrade
migrate_outbox() {
    local outbox_dir="${LOCAL_DIR}/outbox"
    local global_dir="${outbox_dir}/global"

    # Find files at root level (not in subdirs)
    local root_files
    root_files=$(find "$outbox_dir" -maxdepth 1 -type f 2>/dev/null)

    if [[ -n "$root_files" ]]; then
        mkdir -p "$global_dir"
        # Move files to global/
        find "$outbox_dir" -maxdepth 1 -type f -exec mv {} "$global_dir/" \;
        log_info "Migrated outbox files to outbox/global/"
    fi
}
```

### When to Run
- During `sync-shuttle init` if existing installation detected
- Or as a one-time migration command: `sync-shuttle migrate`

### Verification Steps
1. Create test files in `outbox/` root
2. Run migration
3. Verify files moved to `outbox/global/`
4. Verify no data loss

### Rollback
Move files back from `outbox/global/` to `outbox/`.

$---

## Execution Order

**Phase 1: Foundation (Tasks 1, 2)**
- Update pull logic
- Verify backward compatible

**Phase 2: Core Feature (Tasks 3, 6)**
- Add share command
- Optional auto-populate on push

**Phase 3: Polish (Tasks 4, 5)**
- Documentation
- Tests

---

## Work Log

Track completed tasks in `work_log.md` in this directory.
