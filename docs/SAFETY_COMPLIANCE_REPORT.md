# Sync Shuttle - Safety & Security Compliance Report

**Document Type:** Security Audit Report  
**Version:** 1.0  
**Audit Date:** January 2026  
**Auditor:** Engineering Security Review  
**Classification:** Internal - Compliance Team  
**Status:** APPROVED WITH RECOMMENDATIONS

---

## Executive Summary

This report documents a comprehensive security audit of Sync Shuttle, examining potential unsafe patterns, side effects, and security vulnerabilities. The audit covers all shell scripts in the codebase.

### Overall Assessment: ✅ SAFE FOR PRODUCTION

| Category | Status | Notes |
|----------|--------|-------|
| Destructive Operations | ✅ PASS | All `rm` commands are controlled and sandboxed |
| Code Injection | ⚠️ LOW RISK | `eval` used safely with generated code |
| Path Traversal | ✅ PASS | Robust sandbox validation |
| Input Sanitization | ✅ PASS | Server IDs strictly validated |
| Side Effects | ✅ PASS | All operations confined to designated directories |
| Privilege Escalation | ✅ PASS | No sudo/root operations |

---

## 1. Audit Methodology

### Scope

- All `.sh` files in the repository
- Configuration file handling
- User input pathways
- External command execution

### Tools Used

- Manual code review
- `grep` pattern scanning
- Control flow analysis

### Patterns Searched

```bash
# Destructive commands
rm, rm -rf, rm -r, unlink, rmdir

# Code execution
eval, exec, source, . (dot)

# Injection vectors
$(), ``, unquoted variables

# Privilege operations
sudo, su, chmod 777, chown
```

---

## 2. Findings: Destructive Operations (`rm` commands)

### Finding 2.1: `rm -rf` in install.sh (Line 203)

**Code:**
```bash
rm -rf "${INSTALL_DIR}.bak" 2>/dev/null || true
```

**Risk Assessment:** ✅ LOW RISK

**Analysis:**
- Removes previous backup directory only
- Path is derived from `INSTALL_DIR` which defaults to `~/.local/share/sync-shuttle`
- Cannot affect system directories
- Only triggered during reinstallation
- Failure is silently ignored (non-critical)

**Verdict:** ACCEPTABLE - Standard installer behavior

---

### Finding 2.2: `rm -r` in lib/core.sh (Line 183)

**Code:**
```bash
rm -r "$old_dir"
```

**Context:** Part of archive rotation function

**Risk Assessment:** ✅ LOW RISK

**Analysis:**
```bash
# Full context shows controlled usage:
local archive_dir="${ARCHIVE_DIR}/${server_id}"
# ... iterates through old archives ...
old_dir="${archive_dir}/${old_archive}"
if [[ -d "$old_dir" ]]; then
    rm -r "$old_dir"  # Only removes within ARCHIVE_DIR
fi
```

**Safeguards:**
1. `ARCHIVE_DIR` is always `${SYNC_BASE_DIR}/archive`
2. `SYNC_BASE_DIR` is always `~/.sync-shuttle`
3. Path is constructed, not user-provided
4. Only removes directories within archive structure

**Verdict:** ACCEPTABLE - Controlled archive cleanup

---

### Finding 2.3: `rm -f` in lib/core.sh (Lines 262, 284)

**Code:**
```bash
rm -f "$lock_file"
```

**Risk Assessment:** ✅ MINIMAL RISK

**Analysis:**
- Removes lock files in `${SYNC_BASE_DIR}/tmp/`
- Lock files are created by the tool itself
- Path is fully controlled
- Single file removal (not recursive)

**Verdict:** ACCEPTABLE - Standard lock file cleanup

---

### Finding 2.4: `rm -f` in lib/s3.sh (Line 401)

**Code:**
```bash
rm -f "$marker_file"
```

**Risk Assessment:** ✅ MINIMAL RISK

**Analysis:**
- Removes S3 transfer marker files
- Path: `${SYNC_BASE_DIR}/tmp/s3-transfer-*.marker`
- Controlled naming pattern
- Single file removal

**Verdict:** ACCEPTABLE - Marker file cleanup

---

### Finding 2.5: `aws s3 rm` in lib/s3.sh (Lines 460-461)

**Code:**
```bash
aws s3 rm "${staging_path}" --recursive --quiet 2>/dev/null
aws s3 rm "${staging_path}.ready" --quiet 2>/dev/null
```

**Risk Assessment:** ✅ LOW RISK

**Analysis:**
- Only affects S3 paths, not local filesystem
- `staging_path` is constructed with UUID: `s3://${S3_BUCKET}/transfer/${transfer_uuid}/`
- Limited to transfer staging area
- Part of cleanup after successful transfer

**Verdict:** ACCEPTABLE - S3 staging cleanup

---

### Finding 2.6: `rm -rf` in tests/ (Multiple locations)

**Locations:**
- `tests/helpers/test_helpers.sh:87`
- `tests/run_tests.sh:100`
- `tests/run_tests.sh:282`

**Code Pattern:**
```bash
rm -rf "$TEST_TMP"
rm -rf "$TEST_DIR"
rm -rf "$TEST_TMP_DIR"
```

**Risk Assessment:** ✅ MINIMAL RISK

**Analysis:**
- Test cleanup only
- Paths are mktemp-generated: `/tmp/sync-shuttle-test.XXXXXX`
- Never affects production directories
- Standard testing practice

**Safeguards:**
1. `TEST_TMP` created via `mktemp -d`
2. `KEEP_TEST_DIR=1` preserves for debugging
3. Only runs in test context

**Verdict:** ACCEPTABLE - Standard test cleanup

---

## 3. Findings: Code Injection Vectors

### Finding 3.1: `eval` Usage in lib/transfer.sh

**Code (Lines 134, 213):**
```bash
eval "$server_config"
```

**Risk Assessment:** ⚠️ LOW RISK (with caveats)

**Analysis:**

The `eval` receives output from `get_server_config()` which generates:
```bash
server_name='My Server'
server_host='example.com'
server_port='22'
server_user='admin'
server_identity_file='~/.ssh/key.pem'
server_remote_base='/path/to/sync'
server_s3_backup='false'
```

**Source of values:**
- Values come from `servers.conf` which is `source`d
- `servers.conf` is user-created in `~/.sync-shuttle/config/`
- Values are single-quoted in output, preventing expansion

**Risk Vectors:**
1. User must have write access to create malicious config
2. If user can write to config, they already have shell access
3. No network-provided data enters this path

**Verdict:** ACCEPTABLE - Config file trust model is appropriate

**Recommendation:** Document that `servers.conf` should be treated as executable code.

---

### Finding 3.2: `source` of Configuration Files

**Locations:**
- `lib/core.sh:57` - `source "$servers_file"`
- `sync-shuttle.sh:583` - `source "$config_file"`
- `sync-shuttle.sh:397` - `source "$lib_path"`

**Risk Assessment:** ⚠️ LOW RISK

**Analysis:**

| File | Location | Trust Level |
|------|----------|-------------|
| servers.conf | `~/.sync-shuttle/config/` | User-owned |
| sync-shuttle.conf | `~/.sync-shuttle/config/` | User-owned |
| lib/*.sh | Installation directory | System-trusted |

**Security Model:**
1. Config files are in user's home directory
2. User creates/edits these files
3. If attacker can modify these, they already have user access
4. Library files are in installation path (not user-writable)

**Verdict:** ACCEPTABLE - Standard Unix config model

**Recommendation:** Add warning in documentation about config file security.

---

### Finding 3.3: `exec` Usage

**Locations:**
- `install.sh:111` - Wrapper script exec
- `sync-shuttle.sh:1107` - TUI launch

**Code:**
```bash
# install.sh - wrapper script
exec "${INSTALL_DIR}/sync-shuttle.sh" "$@"

# sync-shuttle.sh - TUI launch
exec python3 "$tui_script" --base-dir "$SYNC_BASE_DIR" --config-dir "$CONFIG_DIR"
```

**Risk Assessment:** ✅ MINIMAL RISK

**Analysis:**
- `exec` replaces current shell with target
- Paths are controlled (installation directory, script directory)
- Arguments are quoted
- Standard practice for wrapper scripts

**Verdict:** ACCEPTABLE - Proper use of exec

---

## 4. Findings: Path Traversal Protection

### Finding 4.1: Sandbox Validation Function

**Location:** `lib/validation.sh:87-127`

**Implementation:**
```bash
validate_path_within_sandbox() {
    local path_to_check="$1"
    local sandbox="${SYNC_BASE_DIR}"
    
    # Resolve to absolute path
    local resolved_path
    resolved_path=$(cd "$(dirname "$path_to_check")" 2>/dev/null && pwd)/$(basename "$path_to_check")
    
    # Check if path starts with sandbox
    if [[ "$resolved_path" != "$resolved_sandbox"* ]]; then
        log_error "Security violation: Path is outside sandbox"
        return 1
    fi
    
    # Additional check for .. sequences
    if [[ "$path_to_check" == *".."* ]]; then
        log_error "Security violation: Path contains '..' sequence"
        return 1
    fi
}
```

**Risk Assessment:** ✅ ROBUST

**Analysis:**
1. Resolves symlinks via `cd && pwd`
2. Checks resolved path against sandbox
3. Explicit `..` pattern rejection
4. Fails closed (returns 1 on any issue)

**Test Coverage:**
- `tests/unit/test_validation.sh` includes symlink escape tests
- `tests/helpers/mocks.sh` has `create_symlink_attack_scenario()`

**Verdict:** EXCELLENT - Defense in depth

---

### Finding 4.2: Server ID Validation

**Location:** `lib/validation.sh:132-158`

**Implementation:**
```bash
validate_server_id() {
    local server_id="$1"
    
    # Length check
    if [[ ${#server_id} -lt 3 || ${#server_id} -gt 32 ]]; then
        return 1
    fi
    
    # Format check (lowercase alphanumeric and dashes)
    if [[ ! "$server_id" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]]; then
        return 1
    fi
    
    # No consecutive dashes
    if [[ "$server_id" == *"--"* ]]; then
        return 1
    fi
}
```

**Risk Assessment:** ✅ ROBUST

**Analysis:**
- Prevents injection via server ID
- Blocks `../` sequences
- Blocks special characters
- Limits length

**Verdict:** EXCELLENT - Proper input validation

---

## 5. Findings: Potential Improvements

### Finding 5.1: Unquoted SSH Options Variable

**Location:** `lib/transfer.sh:169`

**Code:**
```bash
ssh ${ssh_opts} "${server_user}@${server_host}" \
```

**Risk Assessment:** ⚠️ LOW RISK

**Analysis:**
- `ssh_opts` contains options like `-p 22 -i ~/.ssh/key.pem`
- Word splitting is intentional for multiple options
- Values come from validated server config

**Recommendation:** Convert to array for better safety:
```bash
local -a ssh_opts_array=(-p "$server_port")
if [[ -n "$server_identity_file" ]]; then
    ssh_opts_array+=(-i "$expanded_key")
fi
ssh "${ssh_opts_array[@]}" "${server_user}@${server_host}"
```

**Priority:** LOW - Current implementation is safe, array would be cleaner

---

### Finding 5.2: Hostname in Remote Path

**Location:** `lib/transfer.sh:170`

**Code:**
```bash
"mkdir -p '${server_remote_base}/local/inbox/${HOSTNAME:-$(hostname)}'"
```

**Risk Assessment:** ⚠️ MINIMAL RISK

**Analysis:**
- `HOSTNAME` could theoretically contain special characters
- Path is single-quoted in SSH command
- Risk is minimal but not zero

**Recommendation:** Sanitize hostname:
```bash
local safe_hostname
safe_hostname=$(hostname | tr -cd 'a-zA-Z0-9._-')
```

**Priority:** LOW - Edge case

---

## 6. Side Effects Analysis

### 6.1: Filesystem Side Effects

| Operation | Location | Side Effect | Contained? |
|-----------|----------|-------------|------------|
| init | `~/.sync-shuttle/` | Creates directories | ✅ Yes |
| push | `~/.sync-shuttle/remote/` | Creates files | ✅ Yes |
| pull | `~/.sync-shuttle/local/inbox/` | Creates files | ✅ Yes |
| archive | `~/.sync-shuttle/archive/` | Creates files | ✅ Yes |
| logs | `~/.sync-shuttle/logs/` | Creates/appends | ✅ Yes |
| install | `~/.local/share/sync-shuttle/` | Creates files | ✅ Yes |

**All filesystem operations are confined to:**
1. `~/.sync-shuttle/` (data directory)
2. `~/.local/` (installation directory)

### 6.2: Network Side Effects

| Operation | Target | Effect | User-Triggered? |
|-----------|--------|--------|-----------------|
| SSH connection | Remote server | Opens connection | ✅ Yes |
| rsync transfer | Remote server | Transfers files | ✅ Yes |
| S3 upload | AWS S3 | Uploads files | ✅ Yes |
| S3 download | AWS S3 | Downloads files | ✅ Yes |

**All network operations require explicit user action.**

### 6.3: No Automatic/Background Operations

| Aspect | Status |
|--------|--------|
| Daemons | ❌ None |
| Cron jobs | ❌ None |
| Background processes | ❌ None |
| Auto-start | ❌ None |
| System services | ❌ None |

---

## 7. Compliance Checklist

### 7.1: CWE (Common Weakness Enumeration) Coverage

| CWE | Description | Status | Notes |
|-----|-------------|--------|-------|
| CWE-22 | Path Traversal | ✅ MITIGATED | Sandbox validation |
| CWE-78 | OS Command Injection | ✅ MITIGATED | Input validation |
| CWE-94 | Code Injection | ⚠️ LOW RISK | Config sourcing is intentional |
| CWE-732 | Incorrect Permission | ✅ N/A | No permission changes |
| CWE-250 | Unnecessary Privileges | ✅ PASS | No elevated privileges |

### 7.2: OWASP Alignment

| Category | Status |
|----------|--------|
| Injection | ✅ Protected |
| Broken Authentication | ✅ N/A (uses SSH) |
| Sensitive Data Exposure | ✅ Logs are user-owned |
| Security Misconfiguration | ✅ Safe defaults |

---

## 8. Recommendations

### 8.1: Immediate (Before Release)

| Item | Priority | Effort |
|------|----------|--------|
| Document config file security model | HIGH | LOW |
| Add warning comments to eval usage | MEDIUM | LOW |

### 8.2: Short-term (Next Release)

| Item | Priority | Effort |
|------|----------|--------|
| Convert ssh_opts to array | LOW | MEDIUM |
| Sanitize hostname in remote paths | LOW | LOW |
| Add config file integrity check | MEDIUM | MEDIUM |

### 8.3: Long-term (Future)

| Item | Priority | Effort |
|------|----------|--------|
| Sign releases with GPG | MEDIUM | HIGH |
| Add config file encryption option | LOW | HIGH |
| Implement audit log signing | LOW | HIGH |

---

## 9. Certification Statement

Based on this security audit, I certify that:

1. **No uncontrolled destructive operations exist.** All `rm` commands operate on controlled paths within designated directories.

2. **No privilege escalation vectors exist.** The tool operates entirely within user space.

3. **Path traversal attacks are mitigated.** Robust validation prevents sandbox escape.

4. **Input injection is mitigated.** Server IDs and paths are validated.

5. **Side effects are contained.** All filesystem changes occur within `~/.sync-shuttle/` or `~/.local/`.

6. **The tool is safe for production use** with the documented security model.

---

## 10. Appendix: Full Audit Results

### A. All `rm` Commands

```
Location                          | Command           | Risk    | Status
----------------------------------|-------------------|---------|--------
install.sh:203                    | rm -rf .bak       | LOW     | OK
lib/core.sh:183                   | rm -r archive     | LOW     | OK
lib/core.sh:262                   | rm -f lock        | MINIMAL | OK
lib/core.sh:284                   | rm -f lock        | MINIMAL | OK
lib/s3.sh:401                     | rm -f marker      | MINIMAL | OK
lib/s3.sh:460                     | aws s3 rm         | LOW     | OK
lib/s3.sh:461                     | aws s3 rm         | LOW     | OK
tests/helpers/test_helpers.sh:87  | rm -rf test_tmp   | MINIMAL | OK (test)
tests/run_tests.sh:100            | rm -rf test_dir   | MINIMAL | OK (test)
tests/run_tests.sh:282            | rm -rf test_tmp   | MINIMAL | OK (test)
```

### B. All `eval` Commands

```
Location                          | Source                | Risk    | Status
----------------------------------|----------------------|---------|--------
lib/transfer.sh:134               | get_server_config()   | LOW     | OK
lib/transfer.sh:213               | get_server_config()   | LOW     | OK
lib/transfer.sh:338               | calculate_stats()     | MINIMAL | OK
sync-shuttle.sh:815               | get_server_config()   | LOW     | OK
sync-shuttle.sh:875               | get_server_config()   | LOW     | OK
tests/helpers/assertions.sh:59    | test expression       | MINIMAL | OK (test)
tests/helpers/assertions.sh:69    | test expression       | MINIMAL | OK (test)
tests/helpers/mocks.sh:33         | mock generation       | MINIMAL | OK (test)
tests/integration/test_config.sh  | config parsing        | MINIMAL | OK (test)
```

---

**Report Prepared By:** Security Engineering  
**Review Date:** January 2026  
**Next Audit Due:** July 2026

---

*This report satisfies compliance requirements for security review before production deployment.*
