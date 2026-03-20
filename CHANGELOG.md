# Changelog

## [Unreleased]

### Added
- `prune` command to delete all closed tickets
- `tree` command to show tickets in parent/child hierarchy, optionally focused on one ticket
- `dep tree` now works without an ID and shows a global dependency hierarchy; repeated dependencies are marked as shared unless `--full` is used

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
