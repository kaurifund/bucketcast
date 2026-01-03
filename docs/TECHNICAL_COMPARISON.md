# Technical Comparison: rsync, scp, s3fs, and Alternatives

**Document Type:** Technical Reference  
**Audience:** Engineers, Technical Evaluators  
**Version:** 1.0

---

## Overview

This document provides a deep technical comparison of file transfer and synchronization tools, explaining why Sync Shuttle makes the architectural choices it does.

---

## 1. rsync vs scp: Why We Use rsync

### TL;DR

| Aspect | rsync | scp |
|--------|-------|-----|
| Primary Use | Sync Shuttle's main engine | Fallback only |
| Efficiency | Delta transfer (changes only) | Full file transfer |
| Resume | ✅ Yes | ❌ No |
| Best For | Repeated syncs | One-off copies |

### How rsync Works

rsync uses a **rolling checksum algorithm** to identify which parts of a file have changed:

```
┌─────────────────────────────────────────────────────────────┐
│                    RSYNC PROTOCOL                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  SOURCE                           DESTINATION                │
│  ──────                           ───────────                │
│                                                              │
│  1. Generate file list ──────────▶ Receive file list        │
│                                                              │
│  2. Wait for checksums ◀────────── Calculate checksums      │
│                        (rolling checksum per block)          │
│                                                              │
│  3. Calculate deltas                                         │
│     (only changed blocks)                                    │
│                                                              │
│  4. Send delta data ─────────────▶ Reconstruct file         │
│                                                              │
│  5. Verify checksum ◀────────────▶ Verify checksum          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### How scp Works

scp uses a simple **full-file transfer**:

```
┌─────────────────────────────────────────────────────────────┐
│                    SCP PROTOCOL                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  SOURCE                           DESTINATION                │
│  ──────                           ───────────                │
│                                                              │
│  1. Send file size ──────────────▶ Prepare to receive       │
│                                                              │
│  2. Send entire file ────────────▶ Write to disk            │
│                                                              │
│  3. Done                           Done                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Efficiency Comparison

**Scenario:** Syncing a 1GB project directory where 10MB has changed

| Metric | rsync | scp |
|--------|-------|-----|
| Data transferred | ~10MB | ~1GB |
| Time (100 Mbps) | ~1 second | ~80 seconds |
| CPU usage | Higher (checksums) | Lower |
| Network efficiency | 99% better | Baseline |

**Scenario:** First-time sync (no existing files)

| Metric | rsync | scp |
|--------|-------|-----|
| Data transferred | ~1GB | ~1GB |
| Time | Slightly slower | Slightly faster |
| Overhead | File list + checksums | None |

**Conclusion:** rsync is dramatically better for the common case (incremental updates), with minimal penalty for initial transfers.

### Resume Capability

**rsync with --partial:**
```bash
# Transfer interrupted at 50%
# Resume picks up where it left off

rsync --partial source dest
# Transfer: 500MB / 1GB
# [INTERRUPT]

rsync --partial source dest  
# Transfer: 500MB more
# Complete: 1GB
```

**scp (no resume):**
```bash
scp source dest
# Transfer: 500MB / 1GB
# [INTERRUPT]

scp source dest
# Transfer: 1GB (starts over)
```

### When We Fall Back to scp

Sync Shuttle uses scp as a fallback when:
1. rsync is not installed on the remote server
2. rsync protocol fails with specific error codes
3. User explicitly requests scp mode (future feature)

---

## 2. S3 Tools Comparison: s3fs, goofys, rclone, AWS CLI

### Architecture Comparison

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        S3 ACCESS PATTERNS                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  FUSE-BASED (s3fs, goofys)              COMMAND-BASED (rclone, aws cli) │
│  ─────────────────────────              ──────────────────────────────── │
│                                                                          │
│  ┌──────────┐                           ┌──────────┐                    │
│  │ App      │ read("/mnt/s3/file")      │ App      │ aws s3 cp ...      │
│  └────┬─────┘                           └────┬─────┘                    │
│       │                                      │                          │
│       ▼                                      │                          │
│  ┌──────────┐                                │                          │
│  │ FUSE     │ (kernel module)                │                          │
│  └────┬─────┘                                │                          │
│       │                                      │                          │
│       ▼                                      ▼                          │
│  ┌──────────┐                           ┌──────────┐                    │
│  │ s3fs     │ GetObject API             │ aws cli  │ GetObject API      │
│  └────┬─────┘                           └────┬─────┘                    │
│       │                                      │                          │
│       ▼                                      ▼                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                          AWS S3                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Every read() = HTTP request             Batch operations possible      │
│  High latency per operation              Efficient for bulk transfers   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Tool-by-Tool Analysis

#### s3fs

**What it does:** Mounts an S3 bucket as a local filesystem via FUSE.

**Pros:**
- Transparent to applications (looks like local files)
- No code changes needed
- Familiar filesystem semantics

**Cons:**
- High latency (every operation = HTTP request)
- Poor reliability (network issues = I/O errors)
- No true filesystem semantics (eventual consistency)
- Memory-intensive caching
- Kernel module dependency

**Best for:**
- Legacy applications that can't be modified
- Light read workloads with caching
- Development/testing environments

**Not suitable for:**
- Heavy I/O workloads
- Production systems requiring reliability
- Write-heavy applications

#### goofys

**What it does:** Faster alternative to s3fs, also FUSE-based.

**Differences from s3fs:**
- 10x+ faster for many operations
- Less POSIX-compliant (trades correctness for speed)
- Better caching strategies

**Still has:**
- FUSE overhead
- Network dependency
- Eventual consistency issues

#### rclone

**What it does:** Command-line tool for syncing to 40+ cloud providers.

**Pros:**
- Multi-cloud support (S3, GCS, Azure, Dropbox, etc.)
- Powerful sync options
- Mount capability (via FUSE)
- Encryption support

**Cons:**
- Complex configuration
- Steep learning curve
- Cloud-centric (SSH support limited)

**Best for:**
- Multi-cloud environments
- Cloud-to-cloud transfers
- Users comfortable with complexity

#### AWS CLI

**What it does:** Official Amazon tool for S3 operations.

**Pros:**
- Full feature support
- Official/maintained
- Reliable

**Cons:**
- AWS-only
- Verbose commands
- No sync intelligence (simple cp/sync)

### Why Sync Shuttle Uses Direct API (Not FUSE)

| Factor | FUSE (s3fs) | Direct API (Sync Shuttle) |
|--------|-------------|---------------------------|
| Latency | High (per syscall) | Low (batch operations) |
| Reliability | Poor (network = I/O errors) | Good (retry logic) |
| Offline support | ❌ None | ✅ Local copies |
| Transparency | ✅ Looks like files | ❌ Explicit commands |
| Control | ❌ Automatic | ✅ Manual |
| Debugging | Hard | Easy |

**Sync Shuttle's approach:** S3 as an archival/intermediate layer, not primary storage.

```bash
# Archive to S3 after successful transfer
sync-shuttle push -s myserver -S ~/data/ --s3-archive

# S3 as intermediate (when direct SSH not possible)
sync-shuttle s3-push -s myserver -S ~/data/      # Push via S3
# On receiving end:
sync-shuttle s3-pull --transfer-id <uuid>        # Pull from S3
```

---

## 3. Real-time vs Manual Sync

### Syncthing/Dropbox Model

```
┌─────────────────────────────────────────────────────────────┐
│               CONTINUOUS SYNC MODEL                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                  DAEMON (always running)             │    │
│  ├─────────────────────────────────────────────────────┤    │
│  │                                                      │    │
│  │  1. Monitor filesystem (inotify)                     │    │
│  │  2. Detect changes                                   │    │
│  │  3. Queue sync operations                            │    │
│  │  4. Execute transfers                                │    │
│  │  5. Resolve conflicts                                │    │
│  │  6. Repeat forever                                   │    │
│  │                                                      │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  Pros:                    Cons:                              │
│  • Automatic              • Resource usage                   │
│  • Real-time              • Unexpected changes               │
│  • No user action         • Complex conflict resolution      │
│                           • Background failures              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Sync Shuttle Model

```
┌─────────────────────────────────────────────────────────────┐
│               MANUAL EXECUTION MODEL                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                  USER ACTION                         │    │
│  ├─────────────────────────────────────────────────────┤    │
│  │                                                      │    │
│  │  $ sync-shuttle push -s server -S ~/files/          │    │
│  │                                                      │    │
│  │  1. Validate paths (sandbox check)                   │    │
│  │  2. Check for collisions                             │    │
│  │  3. Execute transfer (rsync)                         │    │
│  │  4. Log result                                       │    │
│  │  5. Exit (zero resource usage)                       │    │
│  │                                                      │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  Pros:                    Cons:                              │
│  • Full control           • Manual effort                    │
│  • Zero idle resources    • Not real-time                    │
│  • Clear outcomes         • User must remember               │
│  • Simple debugging                                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### When to Use Each

| Use Case | Continuous Sync | Manual Sync |
|----------|-----------------|-------------|
| Real-time collaboration | ✅ | ❌ |
| Backup on schedule | ⚠️ | ✅ |
| Deployment | ❌ | ✅ |
| Development sync | ⚠️ | ✅ |
| Photo backup | ⚠️ | ✅ |
| Config management | ❌ | ✅ |

**Sync Shuttle's philosophy:** Explicit is better than implicit. When files move, you should know about it.

---

## 4. Bandwidth and Performance

### Compression Comparison

| Tool | Compression | When Used |
|------|-------------|-----------|
| rsync | Built-in (-z) | Always available |
| scp | OpenSSH compression | Must enable |
| rclone | Various algorithms | Configurable |
| s3fs | None (S3 handles) | N/A |

**Sync Shuttle default:** `rsync -z` (compression enabled)

### Bandwidth Limiting

```bash
# rsync bandwidth limit
rsync --bwlimit=1000 ...  # 1000 KB/s

# Sync Shuttle config
RSYNC_BWLIMIT=1000  # in sync-shuttle.conf

# Command line (future)
sync-shuttle push -s server -S ~/big-file.zip --bwlimit=5000
```

### Transfer Speed Expectations

| Network | Expected Speed | 1GB Transfer |
|---------|----------------|--------------|
| Gigabit LAN | 100+ MB/s | ~10 seconds |
| 100 Mbps | 10 MB/s | ~100 seconds |
| Home broadband (50 Mbps up) | 5 MB/s | ~200 seconds |
| Coffee shop WiFi (10 Mbps) | 1 MB/s | ~17 minutes |

---

## 5. Security Comparison

### Authentication Methods

| Tool | Auth Methods |
|------|--------------|
| rsync/scp | SSH keys, passwords, certificates |
| s3fs | AWS credentials (IAM, instance roles) |
| rclone | Provider-specific (OAuth, API keys) |
| Syncthing | Device IDs, TLS |

### Sync Shuttle Security

```
┌─────────────────────────────────────────────────────────────┐
│                  SECURITY MODEL                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  AUTHENTICATION                                              │
│  ──────────────                                              │
│  • SSH key-based (recommended)                               │
│  • Supports .pem files (AWS, etc.)                           │
│  • No credential storage                                     │
│                                                              │
│  AUTHORIZATION                                               │
│  ─────────────                                               │
│  • Server-defined in servers.conf                            │
│  • Per-server enable/disable                                 │
│  • Path sandboxing (local and remote)                        │
│                                                              │
│  ENCRYPTION                                                  │
│  ──────────                                                  │
│  • In-transit: SSH (AES-256)                                 │
│  • At-rest: Planned (GPG integration)                        │
│  • S3: AWS-managed or SSE-KMS                                │
│                                                              │
│  AUDIT                                                       │
│  ─────                                                       │
│  • All operations logged                                     │
│  • UUID tracking                                             │
│  • Append-only logs                                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. Decision Matrix: Which Tool to Use

### Quick Reference

| If you need... | Use... |
|----------------|--------|
| Safe file sync to SSH servers | **Sync Shuttle** |
| Maximum flexibility/power | rsync directly |
| One-time simple copy | scp |
| Real-time continuous sync | Syncthing |
| S3 as primary storage | rclone or aws cli |
| S3 as mounted filesystem | s3fs (with caution) |
| Multi-cloud support | rclone |

### Detailed Decision Tree

```
Do you need real-time sync?
├── YES → Use Syncthing or Dropbox
└── NO → Continue...

Is your destination SSH-accessible?
├── NO → Is it cloud storage?
│   ├── YES → Use rclone or provider CLI
│   └── NO → Evaluate other options
└── YES → Continue...

Do you need advanced rsync features?
├── YES (complex excludes, checksums, ACLs) → Use rsync directly
└── NO → Continue...

Do you value safety over flexibility?
├── YES → **Use Sync Shuttle**
└── NO → Use rsync with your own wrapper
```

---

## 7. Summary: Why Sync Shuttle Exists

### The Gap We Fill

```
COMPLEXITY ←────────────────────────────────────────────→ SIMPLICITY

            rsync     rclone                    scp
              │         │                        │
              ▼         ▼                        ▼
    ──────────●─────────●────────────────────────●──────────
              │                                  │
              │         ┌───────────────┐        │
              │         │ Sync Shuttle  │        │
              │         │               │        │
              │         │ • rsync power │        │
              └────────▶│ • scp safety  │◀───────┘
                        │ • audit trail │
                        │ • sandboxed   │
                        └───────────────┘

DANGEROUS ←────────────────────────────────────────────→ SAFE
```

### Our Niche

**Sync Shuttle is for users who:**
- Want rsync's efficiency
- Fear rsync's power (accidental deletions)
- Need audit trails
- Prefer manual control
- Use SSH-accessible servers

**We are NOT trying to replace:**
- rsync for power users
- Syncthing for real-time sync
- rclone for cloud storage
- s3fs for filesystem mounting

**We ARE trying to be:**
- "rsync with guardrails"
- Safe enough for beginners
- Powerful enough for daily use
- Auditable for compliance

---

*Document maintained by Engineering. Technical questions: engineering@sync-shuttle.dev*
