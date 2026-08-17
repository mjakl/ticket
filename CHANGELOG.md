# Changelog

## [Unreleased]

### Added
- `done` command for automation-friendly completion checks; exits `0` when all tickets are closed and `1` while any ticket remains unfinished
- Subcommands now provide focused `--help`/`-h` output without requiring an existing ticket store
- `create -d -`/`create --description -` can read descriptions from stdin for safer multiline ticket text
- `init` command to create `.tickets/` and ignore it by default, with `--tracked` for committed ticket stores
- Queue-summary commands such as `list`, `ready`, `blocked`, `tree`, `closed`, and `done` now behave like an empty queue when no ticket store exists
- `list --status X` and `closed --limit N` space-separated option values are now accepted

### Fixed
- Ticket lookup now accepts only literal alphanumeric ID fragments and cannot traverse outside the store or follow ticket symlinks
- `closed` now filters all closed tickets before sorting and applying `--limit`, without a hidden 100-file ceiling
- `prune` now exits successfully after pruning all eligible tickets
- `undep` can repair dangling stored dependencies after their target file is gone
- User-provided titles and descriptions are written literally, including leading dashes and backslashes
- Unknown commands are reported before ticket-store discovery, help flags compose consistently, and empty notes are rejected
- Commands now reject unexpected arguments and unknown options before changing ticket state
- Repeated status changes are true no-ops and preserve ticket modification times
- `list` and `closed` now reject unknown options instead of silently ignoring them
- `undep` is now idempotent when the dependency is already absent

## [0.5.0] - 2026-03-20

### Added
- `prune` command to delete closed tickets
- `delete <id>` command to remove one unreferenced ticket
- `tree` command to show tickets in parent/child hierarchy, optionally focused on one ticket
- `dep tree` now works without an ID and shows a global dependency hierarchy; repeated dependencies are marked as shared unless `--full` is used
- End-to-end regression test suite for core CLI flows and known edge cases

### Changed
- Repositioned this repository as a customized, simplified fork focused on the single `ticket` bash script
- Moved `ls`/`list` back into the core script
- Simplified ticket creation and listing by removing assignee and external reference handling
- Simplified ticket IDs so they are random and no longer derive prefixes from the current directory
- Rewrote the README to match the reduced command surface and repository scope

### Removed
- Plugin dispatch and the `super` command
- Beads migration support and related README content
- JSON query support from the documented command surface
- Link tracking (`link`/`unlink`, `links` metadata, and linked-ticket output)
- Dependency cycle detection (`dep cycle`)
- Ticket type metadata and the `--type` creation flag
- Tags, tag filters, and tag metadata
- `--design` and `--acceptance` creation flags
- Obsolete dead code and unused compatibility paths such as `_sed_i` and `done` status handling
- Packaging, CI, plugin, and test repository artifacts from this fork

### Fixed
- YAML field updates now modify frontmatter only
- Dependency and link removal now match exact ticket IDs instead of substrings
- Commands that scan tickets now handle empty `.tickets/` directories without failing
- `dep` now rejects self-dependencies
- `prune` now skips closed tickets that are still referenced by another ticket
- `prune` now removes entire closed-only dependency/parent chains in one pass instead of leaving newly unreferenced leftovers behind
- Frontmatter scanners now ignore `---` lines in ticket bodies instead of misparsing them as YAML
- `ready` and `blocked` now render titles containing `|` correctly
- `closed` now works when repository or ticket paths contain spaces
- `create` now reports missing option values with helpful errors instead of crashing
- `create` now validates priorities against the documented `0..4` range
- `create` now retries on generated ID collisions instead of overwriting an existing ticket
- Parser and runtime failures now surface instead of being broadly hidden by `2>/dev/null`

## [0.3.2] - 2026-02-03

### Fixed
- Ticket ID lookup now trims leading/trailing whitespace (fixes issue with AI agents passing extra spaces)

## [0.3.1] - 2026-01-28

### Added
- `list` command alias for `ls`
- `TICKET_PAGER` environment variable for `show` command (only when stdout is a TTY; falls back to `PAGER`)

### Changed
- Walk parent directories to find `.tickets/` directory, enabling commands from any subdirectory
- Ticket ID suffix now uses full alphanumeric (a-z0-9) instead of hex for increased entropy

### Fixed
- `dep` command now resolves partial IDs for the dependency argument
- `undep` command now resolves partial IDs and validates dependency exists
- `unlink` command now resolves partial IDs for both arguments
- `create --parent` now validates and resolves parent ticket ID
- `generate_id` now uses 3-char prefix for single-segment directory names (e.g., "plan" → "pla" instead of "p")

## [0.3.0] - 2026-01-18

### Added
- Support `TICKETS_DIR` environment variable for custom tickets directory location
- `dep cycle` command to detect dependency cycles in open tickets
- `add-note` command for appending timestamped notes to tickets
- `-a, --assignee` filter flag for `ls`, `ready`, `blocked`, and `closed` commands
- `--tags` flag for `create` command to add comma-separated tags
- `-T, --tag` filter flag for `ls`, `ready`, `blocked`, and `closed` commands

## [0.2.0] - 2026-01-04

### Added
- `--parent` flag for `create` command to set parent ticket
- `link`/`unlink` commands for symmetric ticket relationships
- `show` command displays parent title and linked tickets
- `migrate-beads` now imports parent-child and related dependencies

## [0.1.1] - 2026-01-02

### Fixed
- `edit` command no longer hangs when run in non-TTY environments

## [0.1.0] - 2026-01-02

Initial release.
