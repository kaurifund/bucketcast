# Backlog Triage - 2026-02-12

**Date:** 2026-02-12
**Branch:** main (f0d9f67)
**Current Version:** 1.1.1

---

## BUGS

### BUG-1: Pushing a folder does not work

**Severity:** High
**Status:** Open

Pushing a directory as source fails or produces incorrect results. The core
`push` path expects a single file and doesn't handle directories properly
(rsync trailing slash behavior, directory creation on remote, etc.).

**Repro:** `bucketcast push -s myserver -S ~/some-folder/`

**Expected:** Folder and contents are transferred to remote inbox.

**Actual:** Fails or transfers incorrectly.

**Related PR:** #3 (push-positional-args) touches push logic but doesn't fix this.
**Related ticket:** `BUG_RSYNC_FOLDER_STRUCTURE.md` (existing, may overlap)

---

### BUG-2: Multi-file push does not work

**Severity:** High
**Status:** Open

Cannot push multiple files in a single command. The current main branch
only supports a single `-S` argument.

**Repro:** `bucketcast push -s myserver -S file1.txt -S file2.txt`

**Expected:** Both files transferred.

**Actual:** Only last `-S` is used, or errors out.

**Related PR:** #3 (push-positional-args) adds `SOURCE_PATHS` array and
`perform_rsync_push_multi()` but is not merged. PR #7 (relay) also adds
multi-S support for relay but not for regular push on main.

---

### BUG-3: Silent fail when file exists on host with different contents

**Severity:** Medium
**Status:** Open

When pushing a file that already exists on the remote with different contents,
there is no warning or diff notification. The `--ignore-existing` rsync flag
silently skips the file. The user has no idea their updated file was not
transferred.

**Expected:** A message like "file.txt exists on remote with different
contents. Use --force to overwrite." or at minimum a warning that the file
was skipped.

**Actual:** Complete silence. User thinks transfer succeeded.

**Related:** PR #6 (outbox-inbox-symmetry) has a ticket
`20260105_rsync_delta_transfer/TICKET.md` about `--ignore-existing` blocking
delta transfers. Same root cause.

---

### BUG-4: Init migration broken after rename (sync-shuttle -> bucketcast)

**Severity:** Critical
**Status:** Open

Existing users who installed under the old name have their data at
`~/.sync-shuttle/`. After the rename, the code defaults to
`~/.bucketcast/` (`SYNC_BASE_DIR="${SYNC_BASE_DIR:-$HOME/.bucketcast}"`).

Running `bucketcast init` will create a brand new `~/.bucketcast/` directory
and the user's existing configs, servers, logs, and transferred files in
`~/.sync-shuttle/` are orphaned. The migration system
(`check_and_run_migrations`) only handles internal version upgrades
(servers.conf -> servers.toml), NOT the directory rename.

**Impact:**
- Existing users lose access to their config, server list, and file history
- Remote servers still have `remote_base = "/home/user/.sync-shuttle"` in
  their config, creating a mismatch
- The install.sh hardcodes `~/.local/share/bucketcast` but old installs
  are at `~/.local/share/sync-shuttle`

**Fix needed:**
1. A `migrate_to_1_2_0()` (or whatever the next version is) that detects
   `~/.sync-shuttle/` and either renames or symlinks it to `~/.bucketcast/`
2. Update `install.sh` to detect and migrate old install location
3. Print a clear message about what happened
4. Handle `remote_base` in servers.toml pointing to old name

---

## FEATURES

### FEAT-1: Transfer ID / commit-style tracking for files

**Priority:** High
**Status:** Design needed

**Problem:** When files move through the system (dev machine -> global outbox ->
server -> host), there's no way to track where a file ended up. The user has to
manually SSH around and search to find files. There's no concept of a "transfer"
as a first-class object.

**Idea:** Something like a commit ID or transfer receipt:
- Each push/pull/share/relay operation generates a UUID (already happens for
  logging, see `OPERATION_ID` in the script)
- But this ID is only used in log filenames, not exposed to the user
- Need: a manifest or receipt that maps transfer-id -> list of files, source,
  destination, timestamp
- Then: `bucketcast status <transfer-id>` or `bucketcast find <filename>`
  tells you where a file is across all servers
- Could be a simple JSON/TOML manifest stored in `~/.bucketcast/manifests/`

**Related PR:** #2 (file-discovery) adds `files` and `tree` commands for
browsing what's in inbox/outbox. This is complementary - discovery shows what's
here, transfer-id tracks where things went.

---

## CHORE

### CHORE-1: PR Audit - Version and dependency map

**Priority:** High
**Status:** Documented below

There are 4 open PRs, each branched at different points and carrying different
feature sets. Here's the full map:

#### PR #2 - Feature/file discovery
- **Branch:** `feature/file-discovery`
- **Intent:** Add `files` and `tree` commands to discover/browse files across
  inbox, outbox, and remote servers. Adds TUI file browser with 3-panel layout.
- **Version:** Bumps to 1.2.0
- **Key changes:** Adds `files`, `tree`, `browse` commands to bucketcast.sh.
  Adds `docs/FILE_DISCOVERY_DESIGN.md`, `docs/ARCHITECTURE.md`,
  `tickets/FEATURE_IDEAS.md`. Rewrites TUI with browse screen.
- **Dependencies:** None (standalone feature)
- **Conflicts with:** PR #6 (both rewrite the TUI extensively)

#### PR #3 - Feature/push positional args
- **Branch:** `feature/push-positional-args`
- **Intent:** Change push syntax from `-S file` to positional args like
  `push -s server file1 file2 dir/`. Support multiple files, support `.` for
  current directory.
- **Version:** Inherits from #2 (1.2.0)
- **Key changes:** Adds `perform_rsync_push_multi()` in lib/transfer.sh.
  Adds `SOURCE_PATHS` array. Legacy `-S` flag kept for compat.
- **Dependencies:** Built on top of PR #2 (shares all its commits)
- **Conflicts with:** PR #6, PR #7 (all modify push/transfer logic)

#### PR #6 - feat: inbox/outbox symmetry
- **Branch:** `feature/outbox-inbox-symmetry`
- **Intent:** Fix asymmetry where inbox is per-server but outbox is flat.
  Adds `outbox/global/` and `outbox/<server>/` structure. Adds `share` command.
  Major TUI redesign with tabs.
- **Version:** Bumps to 1.2.0
- **Key changes:** Adds `share` command, updates `pull` to check global+per-server
  outbox, adds reserved namespace validation ("global" can't be server ID),
  adds outbox migration, complete TUI rewrite with tabbed navigation.
- **Dependencies:** None (branched from main independently)
- **Conflicts with:** PR #2 (TUI rewrite), PR #3 (push logic), PR #7 (needs
  rebase onto this for --global flag)

#### PR #7 - Add multi-server relay command
- **Branch:** `feature/multi-server-relay`
- **Intent:** Add `relay` command to transfer files between two remote servers
  via local machine as hub. Three-phase: pull from source, identify files,
  push to destination.
- **Version:** Not explicitly bumped (still 1.1.1)
- **Key changes:** Adds `action_relay()`, `validate_relay_params()`,
  `preflight_relay()`. Adds `--from`, `--to`, `--global` flags.
  Adds `tests/integration/test_relay.sh`, `CHANGELOG.md`.
- **Dependencies:** Has rebase notes for PR #6 (--global flag, GLOBAL_MODE var)
- **Conflicts with:** PR #6 (--global parsing, validation.sh)

#### Dependency / Merge Order

```
Recommended merge order:
  1. PR #6 (outbox-inbox-symmetry) - foundational structure change
  2. PR #7 (multi-server-relay)    - rebase onto #6, resolve --global conflicts
  3. PR #2 (file-discovery)        - rebase onto new main, resolve TUI conflicts
  4. PR #3 (push-positional-args)  - rebase onto #2 (already built on it)
```

**Version problem:** PRs #2, #3, and #6 all independently bump to 1.2.0 but
carry different features. After merge, version needs to be reconciled. Suggest:
- 1.2.0 = inbox/outbox symmetry + share command (PR #6)
- 1.3.0 = relay command (PR #7)
- 1.4.0 = file discovery + positional args (PR #2 + #3)

Or bump to 2.0.0 if all are merged together since it's a significant
feature set and the rename happened.

---

## SUMMARY TABLE

| ID | Type | Title | Severity | Blocked By |
|---|---|---|---|---|
| BUG-1 | Bug | Folder push broken | High | - |
| BUG-2 | Bug | Multi-file push broken | High | PR #3 has fix |
| BUG-3 | Bug | Silent fail on existing different file | Medium | - |
| BUG-4 | Bug | Init migration broken after rename | Critical | - |
| FEAT-1 | Feature | Transfer ID / commit-style tracking | High | Design needed |
| CHORE-1 | Chore | PR audit / version reconciliation | High | - |
