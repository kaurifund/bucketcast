# Testing Instructions: Multi-Server Relay Feature

## Install Feature Branch

```bash
curl -fsSL https://raw.githubusercontent.com/kaurifund/bucketcast/feature/multi-server-relay/install.sh | SYNC_SHUTTLE_BRANCH=feature/multi-server-relay bash
```

Then reload your shell:
```bash
source ~/.bashrc
```

---

## Prerequisites

You need at least two configured servers in `~/.sync-shuttle/config/servers.toml`. Example:

```toml
[servers.server-a]
name = "Server A"
host = "192.168.1.10"
user = "myuser"
remote_base = "/home/myuser/.sync-shuttle"
enabled = true

[servers.server-b]
name = "Server B"
host = "192.168.1.20"
user = "myuser"
remote_base = "/home/myuser/.sync-shuttle"
enabled = true
```

Make sure SSH key auth works for both servers:
```bash
ssh server-a "echo 'Server A OK'"
ssh server-b "echo 'Server B OK'"
```

---

## Test 1: Verify Help Output

**What you're testing:** The relay command shows up in help with all new options.

```bash
sync-shuttle --help
```

**Expected:** You should see:
- `relay` in the COMMANDS section
- `-F, --from <id>` and `-T, --to <id>` in OPTIONS
- `-g, --global` option documented
- Relay examples showing `--global` and multiple `-S` flags

---

## Test 2: Basic Relay Dry-Run

**What you're testing:** Dry-run shows what would happen without transferring files.

First, on server-a, put a test file in the outbox:
```bash
ssh server-a "mkdir -p ~/.sync-shuttle/local/outbox/global && echo 'hello from A' > ~/.sync-shuttle/local/outbox/global/test-file.txt"
```

Then run the relay dry-run:
```bash
sync-shuttle relay --from server-a --to server-b --dry-run
```

**Expected:**
- Phase 1: Shows rsync preview of files that WOULD be pulled
- Phase 2: Shows `[DRY-RUN] File list shown above from rsync preview`
- Phase 3: Shows `[DRY-RUN] Would relay: test-file.txt -> server-b`
- No actual files transferred

---

## Test 3: Actual Relay Transfer

**What you're testing:** Files actually move from server-a to server-b.

```bash
sync-shuttle relay --from server-a --to server-b
```

**Expected:**
- Phase 1: Files pulled to local inbox
- Phase 2: Shows `Found 1 file(s) to relay`
- Phase 3: Shows `Staging: test-file.txt` then `Syncing 1 file(s) to server-b...`
- Summary shows `Relayed: 1`

Verify the file arrived on server-b:
```bash
ssh server-b "cat ~/.sync-shuttle/local/inbox/*/test-file.txt"
```

---

## Test 4: Multiple -S Flags

**What you're testing:** Selecting specific files with multiple -S arguments.

First, add more files on server-a:
```bash
ssh server-a "echo 'file one' > ~/.sync-shuttle/local/outbox/global/one.txt"
ssh server-a "echo 'file two' > ~/.sync-shuttle/local/outbox/global/two.txt"
ssh server-a "echo 'file three' > ~/.sync-shuttle/local/outbox/global/three.txt"
```

Relay only two of them:
```bash
sync-shuttle relay --from server-a --to server-b -S one.txt -S three.txt --dry-run
```

**Expected:**
- `[DRY-RUN] Filter: only specified files would be relayed:`
- `[DRY-RUN]   - one.txt`
- `[DRY-RUN]   - three.txt`
- `two.txt` should NOT appear in the relay list

---

## Test 5: --global Flag

**What you're testing:** The --global flag limits relay to only files from the global outbox.

First, put a file in a targeted outbox (not global):
```bash
ssh server-a "mkdir -p ~/.sync-shuttle/local/outbox/$(hostname) && echo 'targeted file' > ~/.sync-shuttle/local/outbox/$(hostname)/targeted.txt"
```

Run relay with --global:
```bash
sync-shuttle relay --from server-a --to server-b --global --dry-run
```

**Expected:**
- Shows `Mode: GLOBAL (only files from global outbox)`
- `[DRY-RUN] Filter: only global outbox files`
- Should NOT include `targeted.txt` (it's in hostname-specific outbox)

Run relay without --global:
```bash
sync-shuttle relay --from server-a --to server-b --dry-run
```

**Expected:**
- Should include BOTH global files AND `targeted.txt`

---

## Test 6: Error Handling

**What you're testing:** Proper error messages for invalid usage.

Missing --from:
```bash
sync-shuttle relay --to server-b
```
**Expected:** Error message asking for `--from`

Missing --to:
```bash
sync-shuttle relay --from server-a
```
**Expected:** Error message asking for `--to`

Same server for both:
```bash
sync-shuttle relay --from server-a --to server-a
```
**Expected:** Error about source and destination being the same

Non-existent server:
```bash
sync-shuttle relay --from fake-server --to server-b
```
**Expected:** Error about server not found in config

---

## Test 7: Empty Outbox

**What you're testing:** Graceful handling when source has no files.

Clear the outbox on server-a:
```bash
ssh server-a "rm -rf ~/.sync-shuttle/local/outbox/*"
```

Run relay:
```bash
sync-shuttle relay --from server-a --to server-b
```

**Expected:**
- `No files to relay from server-a`
- Hint message about checking outbox paths
- Exits cleanly (no error)

---

## Cleanup

Remove test files from both servers:
```bash
ssh server-a "rm -rf ~/.sync-shuttle/local/outbox/*"
ssh server-b "rm -rf ~/.sync-shuttle/local/inbox/*"
```

---

## Reporting Issues

If any test fails, please include:
1. The exact command you ran
2. The full output
3. Your `servers.toml` config (redact sensitive info)
4. Output of `sync-shuttle --version`
