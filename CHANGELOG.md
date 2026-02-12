# Changelog

All notable changes to Sync Shuttle will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Multi-Server Relay**: New `relay` command to transfer files between two servers via local machine as hub
  - `sync-shuttle relay --from serverA --to serverB`
  - Supports `--dry-run` for previewing operations
  - Supports `-S` flag for selecting specific files (multiple flags allowed)
  - Supports `--global` flag to relay only files from global outbox
  - Three-phase workflow: Pull from source → Identify files → Push to destination
- New CLI options for relay: `-F/--from`, `-T/--to`, `-g/--global`
- Comprehensive relay validation and preflight checks
- README section explaining when and why to use relay

### Fixed
- **Critical**: `list servers` only showed first configured server due to errexit bug with post-increment
  - `((var++))` returns 0 when var=0, causing script termination with `set -o errexit`
  - Fixed by using pre-increment `((++var))` which returns 1

## [1.0.0] - 2025-01-06

### Added
- Initial release
- Push files to remote servers
- Pull files from remote servers
- Server configuration via TOML
- Dry-run mode for all operations
- Force mode with archival of existing files
- JSON and human-readable logging
- Operation UUID tracking
- S3 archival integration (optional)
- Interactive TUI (optional)
- Comprehensive preflight validation
- SSH key-based authentication support

### Security
- Sandboxed operations in `~/.sync-shuttle/`
- No automatic file deletion
- No overwrites without explicit consent
- Validation of all paths and server configurations
