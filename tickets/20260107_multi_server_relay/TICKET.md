# Ticket: Multi-Server Relay / File Forwarding

**Type:** Feature Request
**Priority:** High
**Status:** Planning
**Created:** 2026-01-07
**Related:** 20260105_outbox_inbox_symmetry (builds on global/per-server outbox structure)

---

## Executive Summary

Currently, transferring files between two servers (A and B) that don't know about each other requires multiple manual commands through a local intermediary. Users must:

1. On Server A: `sync-shuttle share --global -S file1 -S file2 ...`
2. On Local: `sync-shuttle pull -s a`
3. On Local: `sync-shuttle push -s b -S file1 -S file2 ...`

This is tedious and error-prone. We need a **relay** command that simplifies multi-server file forwarding while maintaining the principle that servers A and B don't need to know about each other.

---

## Current State

### Architecture Overview

Sync Shuttle operates on a **hub-and-spoke model** where:
- Local machine is the **hub** (intermediary)
- Remote servers are **spokes** (endpoints)
- Files flow: `Server A → Local → Server B`

### Current Commands

| Command | Purpose | Implementation Location |
|---------|---------|------------------------|
| `push` | Push files TO remote's inbox | `sync-shuttle.sh:985-1068`, `lib/transfer.sh:122-194` |
| `pull` | Pull files FROM remote's outbox | `sync-shuttle.sh:1073-1127`, `lib/transfer.sh:199-307` |
| `share` | Stage files in local outbox | `sync-shuttle.sh:1133-1262` |

### Data Flow Diagram

```
SERVER A                    LOCAL                      SERVER B
─────────────────────────────────────────────────────────────────

outbox/global/     ──pull──►  inbox/a/
outbox/<local>/                   │
                                  │   (manual copy currently)
                                  ▼
                              outbox/b/  ──push──►  inbox/<local>/
                              outbox/global/
```

### Current Workflow (Tedious)

```bash
# On Server A: Share files for local to pull
sync-shuttle share --global -S /path/to/file1.txt
sync-shuttle share --global -S /path/to/file2.txt
sync-shuttle share --global -S /path/to/file3.txt

# On Local: Pull from A
sync-shuttle pull -s a

# On Local: Push each file to B (must specify each one!)
sync-shuttle push -s b -S ~/.sync-shuttle/local/inbox/a/file1.txt
sync-shuttle push -s b -S ~/.sync-shuttle/local/inbox/a/file2.txt
sync-shuttle push -s b -S ~/.sync-shuttle/local/inbox/a/file3.txt
```

**Problems:**
1. Multiple commands per file
2. Must remember exact inbox paths
3. No single command to "relay files from A to B"
4. Error-prone when dealing with many files

---

## The Problem

### 1. No Unified Relay Operation

There's no command that combines `pull from A` + `push to B` into a single operation.

### 2. File Path Friction

After pulling from server A, files land in `~/.sync-shuttle/local/inbox/a/`. User must:
- Know this path
- Reference each file individually for push
- No wildcard or "push all from this server" capability

### 3. Mental Model Mismatch

Users think: "Move files from A to B via local"
Current reality: "Pull from A, remember where files land, push each to B"

### 4. Production Pattern Mismatch

The user mentioned this should "work the same way as auth" - referring to cookie-cutter production patterns where multi-hop operations are abstracted into single commands.

---

## Desired State

### New Command: `relay`

```bash
# Relay all files from A to B (via local)
sync-shuttle relay --from a --to b

# Relay specific files
sync-shuttle relay --from a --to b -S file1.txt -S file2.txt

# Dry run first
sync-shuttle relay --from a --to b --dry-run

# Relay everything in A's outbox destined for global
sync-shuttle relay --from a --to b --global
```

### Data Flow with Relay

```
SERVER A                    LOCAL                      SERVER B
─────────────────────────────────────────────────────────────────

outbox/global/     ◄────────────────────────────────────────┐
outbox/<local>/             │                               │
       │                    │                               │
       └────── pull ───────►│                               │
                            │                               │
                    inbox/a/file.txt                        │
                            │                               │
                            └────── relay ─────► push ──────┘
                                                            │
                                              inbox/<local>/file.txt
```

### Alternative: Tagged Routing

Files can be tagged with their intended destination at the source:

```bash
# On Server A: Tag files for B
sync-shuttle share --dest b -S file1.txt
sync-shuttle share --dest b -S file2.txt

# On Local: Process all routes automatically
sync-shuttle relay --auto
```

This creates files in `outbox/route-to-b/` which local then auto-forwards.

---

## Affected Files

### Primary Changes

| File | Lines | Change Description |
|------|-------|-------------------|
| `sync-shuttle.sh` | 503-517 | Add `relay` to command parser |
| `sync-shuttle.sh` | 418-486 | Update `show_usage()` with relay docs |
| `sync-shuttle.sh` | 778-811 | Add relay to `dispatch_action()` |
| `sync-shuttle.sh` | NEW | Implement `action_relay()` (~80-120 lines) |
| `sync-shuttle.sh` | 339-351 | Add `FROM_SERVER`, `TO_SERVER` runtime vars |
| `lib/transfer.sh` | NEW | Add `perform_relay()` helper function |

### Secondary Changes

| File | Lines | Change Description |
|------|-------|-------------------|
| `lib/validation.sh` | NEW | Add `preflight_relay()` function |
| `lib/validation.sh` | NEW | Add `validate_relay_params()` function |
| `lib/logging.sh` | 142-167 | Update `log_operation()` for relay ops |
| `SPECIFICATION.md` | 29-36 | Add relay to Core Features |
| `README.md` | 95-104 | Add relay to Commands table |
| `README.md` | 121-153 | Add relay examples |

### Test Files

| File | Change Description |
|------|-------------------|
| `tests/unit/test_validation.sh` | Add relay validation tests |
| `tests/integration/test_transfer.sh` | Add relay integration tests |
| `tests/e2e/test_scenarios.sh` | Add relay E2E scenario |

---

## Code References (Grep Results)

### All Push/Pull Related Functions

```
sync-shuttle.sh:985:  action_push()
sync-shuttle.sh:1073: action_pull()
sync-shuttle.sh:1133: action_share()
lib/transfer.sh:61:   perform_rsync_push()
lib/transfer.sh:122:  sync_to_remote()
lib/transfer.sh:199:  perform_rsync_pull()
```

### Argument Parsing Pattern

```
sync-shuttle.sh:503-517:
    case "${1:-}" in
        init|push|pull|list|status|config|share|tui|help|--help|-h)
            ACTION="${1}"
            shift
            ;;
```

### Server Configuration Loading

```
sync-shuttle.sh:1006-1013:
    local server_config
    if ! server_config=$(get_server_config "$SERVER_ID"); then
        log_error "Server not found or disabled: $SERVER_ID"
        exit 3
    fi
    eval "$server_config"
```

### Operation UUID and Logging Pattern

```
sync-shuttle.sh:986-988:
    OPERATION_UUID=$(generate_uuid)
    local timestamp_start
    timestamp_start=$(get_iso_timestamp)
```

### Preflight Check Pattern

```
lib/validation.sh:423-446: preflight_push()
lib/validation.sh:451-463: preflight_pull()
```

### Global Mode Handling

```
sync-shuttle.sh:347:   GLOBAL_MODE="false"
sync-shuttle.sh:574-577:
    --global)
        GLOBAL_MODE="true"
        shift
        ;;
sync-shuttle.sh:1165-1167:
    elif [[ "${GLOBAL_MODE:-false}" == "true" ]]; then
        share_dir="${OUTBOX_DIR}/global"
```

---

## Principles Applied

1. **Pure Functional** - `action_relay()` composes existing `pull` and `push` operations
2. **Pipeline Architecture** - Data flows: pull → inbox → push → remote inbox
3. **Explicit Contracts** - Clear `--from` and `--to` parameters
4. **Idempotent** - Re-running relay produces same result safely
5. **No Magic** - Behavior is explicit, files go through local inbox
6. **Debuggability** - Each phase (pull, push) logged with same UUID
7. **Async-First** - Operations are sequential but could be parallelized later
8. **No Classes** - Pure bash functions, no OOP
9. **Testability** - Each phase testable independently
10. **Idempotent Side Effects** - Files either transferred or skipped, never duplicated unsafely

---

## Implementation Approach

### Option A: Sequential Pull-Then-Push (Recommended)

```bash
action_relay() {
    # 1. Pull from source server
    action_pull_internal "$FROM_SERVER"

    # 2. Find pulled files
    local inbox_dir="${INBOX_DIR}/${FROM_SERVER}"

    # 3. Push each file to destination
    for file in "$inbox_dir"/*; do
        action_push_internal "$TO_SERVER" "$file"
    done
}
```

**Pros:** Simple, reuses existing code, easy to debug
**Cons:** Two-step process, files remain in inbox

### Option B: Direct Server-to-Server (If Both Have rsync)

```bash
action_relay() {
    # Direct rsync from A to B (local as SSH jump host)
    ssh server_a "rsync ... server_b:path"
}
```

**Pros:** Single operation, faster for large files
**Cons:** Requires A to have access to B, breaks hub-spoke model

### Recommendation

**Option A** - Maintains the principle that servers don't know about each other. Local remains the trusted intermediary.

---

## Open Questions

1. **Should relay files remain in inbox after forwarding?**
   - Pro: Audit trail, can re-relay if needed
   - Con: Uses disk space, potential confusion

2. **Should there be a `--clean` flag to remove after relay?**
   - Pro: Explicit cleanup
   - Con: Goes against "never delete" philosophy

3. **Should relay support wildcards for file selection?**
   - E.g., `sync-shuttle relay --from a --to b -S "*.pdf"`

4. **Should there be tagged routing (`--dest b` at source)?**
   - Pro: Source declares intent
   - Con: More complexity, needs outbox/route-to-<server>/ structure

---

## Related Context

### Existing Ticket: Outbox/Inbox Symmetry

The `20260105_outbox_inbox_symmetry` ticket established:
- `outbox/global/` for all-server shares
- `outbox/<server_id>/` for server-specific shares
- Pull checks both `global/` and `<hostname>/` on remote

This relay feature builds on that structure.

### Reserved Namespaces

From `lib/validation.sh:33-37`:
```bash
readonly RESERVED_NAMESPACES=(
    "global"
)
```

If we add tagged routing, we may need to reserve `route-to-*` patterns.

---

## Success Criteria

1. `sync-shuttle relay --from a --to b` works in single command
2. Dry-run support for preview
3. Operation logged with single UUID
4. Clear output showing: "Pulled X files from A, pushed X files to B"
5. Works with `--global` flag for global shares only
6. Works with `-S` for specific file selection
7. Follows all existing safety patterns (sandbox, no delete, force for overwrite)
8. Tests pass for all scenarios

---

## Next Steps

See `IMPLEMENTATION_PLAN.md` for detailed tasks.
