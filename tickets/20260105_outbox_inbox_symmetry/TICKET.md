# Ticket: Inbox/Outbox Symmetry and Per-Server Structure

**Type:** Design Issue / Feature Request
**Priority:** High
**Status:** In Analysis
**Created:** 2026-01-05
**Related:** Feature PR on advanced discoverability

---

## Executive Summary

The inbox and outbox directories have an **asymmetric design** that creates confusion and limits functionality. Inbox is per-server, but outbox is flat. This needs to be aligned for consistency and to support the "push = share with that user" mental model.

---

## Current State

### Directory Structure (Live)

```
~/.sync-shuttle/local/
├── inbox/
│   └── <server_id>/        # PER-SERVER (files received from each server)
│       └── files...
└── outbox/
    └── files...            # FLAT (global, not per-server)
```

### Current Behavior

| Operation | Source | Destination |
|-----------|--------|-------------|
| **PUSH** | User-specified file | Remote's `inbox/<your_hostname>/` |
| **PULL** | Remote's `outbox/` (flat) | Your `inbox/<server_id>/` |

### Code References

**Push destination** (sync-shuttle.sh:967, lib/transfer.sh:157):
```bash
local remote_dest="${server_user}@${server_host}:${server_remote_base}/local/inbox/${HOSTNAME:-$(hostname)}/"
```

**Pull source** (lib/transfer.sh:236):
```bash
local remote_src="${server_user}@${server_host}:${server_remote_base}/local/outbox/"
```

**Pull destination** (sync-shuttle.sh:1031):
```bash
local dest_dir="${INBOX_DIR}/${SERVER_ID}"
```

**Outbox definition** (sync-shuttle.sh:688):
```bash
OUTBOX_DIR="${LOCAL_DIR}/outbox"
```

---

## The Problem

### 1. Asymmetric Design

- **Inbox**: Per-server (`inbox/<server_id>/`) - you know WHO sent each file
- **Outbox**: Flat (`outbox/`) - everyone pulls the same files, no control

### 2. No "Share with Specific User" Capability

When you push to server A, you're essentially sharing with that user. But:
- Push goes to THEIR inbox (good)
- Your outbox doesn't reflect WHO you shared with
- They can't re-pull files you previously pushed

### 3. Mental Model Mismatch

Users expect symmetry:
- "Files I received from server A" → `inbox/serverA/` ✓
- "Files I'm sharing with server A" → `outbox/serverA/` ✗ (doesn't exist)

### 4. Production Readiness

The current design doesn't match patterns used in production auth/cookie-cutter systems where per-user/per-tenant isolation is standard.

---

## Desired State

### Directory Structure (Target)

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

### Reserved Namespaces

- `global` - cannot be used as a server ID

### Target Behavior

| Operation | Source | Destination |
|-----------|--------|-------------|
| **PUSH** | User-specified file | Remote's `inbox/<your_hostname>/` |
| **SHARE** | User-specified file | Your `outbox/global/` or `outbox/<server_id>/` |
| **PULL** | Remote's `outbox/global/` + `outbox/<your_hostname>/` | Your `inbox/<server_id>/` |

### The Mental Model

```
YOUR MACHINE                              REMOTE SERVER
────────────────────────────────────────────────────────

outbox/<server>/  ──── they pull ────►  (server-specific share)
outbox/global/    ──── they pull ────►  (global share)

inbox/<server>/   ◄──── pull ──────────  their outbox/global/ + outbox/<you>/
```

---

## Affected Files

| File | Lines | What Changes |
|------|-------|--------------|
| `sync-shuttle.sh` | 688 | OUTBOX_DIR definition |
| `sync-shuttle.sh` | 1031 | Pull destination logic |
| `lib/transfer.sh` | 236 | Pull source (needs to check per-server outbox) |
| `lib/transfer.sh` | 157-171 | Push destination (optionally copy to local outbox record) |
| `tests/integration/test_config.sh` | 21, 26, 183, 191 | Test assertions for outbox structure |
| `tests/helpers/fixtures.sh` | 170 | Directory creation |
| `SPECIFICATION.md` | 40, 82, 170 | Documentation |
| `README.md` | 70 | Documentation |

---

## Principles Applied

1. **Pure Functional** - Changes are isolated, no side effects on unrelated code
2. **Pipeline Architecture** - Data flow remains linear (push → stage → sync → record)
3. **Explicit Contracts** - Directory structure is explicit, documented
4. **Idempotent** - Re-running push/pull produces same result
5. **No Magic** - Behavior is clear, no hidden transformations
6. **Debuggability** - Per-server directories make it easy to see what's shared with whom

---

## Open Questions

1. **Should push auto-populate outbox/<server>/?**
   - Pro: Creates record of what you shared
   - Con: Duplicates data (file exists in source + outbox)

2. **Should pull check both outbox/ and outbox/<your_id>/?**
   - Pro: Server-specific + global shares
   - Con: More complex logic

3. **Backward compatibility?**
   - Existing flat outbox/ files should still work

---

## Related Context

### Grep: All Outbox References

```
sync-shuttle.sh:55:   #   │   └── outbox/              # Files staged for sending
sync-shuttle.sh:204:  #   # Stage files in outbox
sync-shuttle.sh:205:  #   cp -r ~/projects/myapp ~/.sync-shuttle/local/outbox/
sync-shuttle.sh:688:      OUTBOX_DIR="${LOCAL_DIR}/outbox"
sync-shuttle.sh:1041:     log_info "[DRY-RUN] Would pull from: ...local/outbox/"
sync-shuttle.sh:1044:     log_info "Pulling from: ...local/outbox/"
sync-shuttle.sh:1222-1224: outbox_count=$(find "$OUTBOX_DIR" -type f ...)
lib/transfer.sh:236:  local remote_src="...local/outbox/"
SPECIFICATION.md:40:  - Local staging: ~/.sync-shuttle/local/outbox/
SPECIFICATION.md:82:  │   └── outbox/                # Files staged for sending
SPECIFICATION.md:170: 4. Check pending outbox → List local/outbox/
```

### Grep: All Inbox References

```
sync-shuttle.sh:54:   #   │   ├── inbox/               # Files received from remotes
sync-shuttle.sh:221:  #   ls ~/.sync-shuttle/local/inbox/prod-web-01/
sync-shuttle.sh:687:      INBOX_DIR="${LOCAL_DIR}/inbox"
sync-shuttle.sh:967:      remote_dest="...local/inbox/${HOSTNAME}/"
lib/transfer.sh:157:  remote_dest="...local/inbox/${HOSTNAME}/"
lib/transfer.sh:171:  mkdir -p '...local/inbox/${HOSTNAME}'
SPECIFICATION.md:41:  - Incoming files: ~/.sync-shuttle/local/inbox/
SPECIFICATION.md:81:  │   ├── inbox/                 # Files received from remotes
```

---

## Next Steps

See IMPLEMENTATION_PLAN.md for detailed tasks.
