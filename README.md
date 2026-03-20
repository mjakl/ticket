# ticket (tk)

`tk` allows your agent to manage tasks in a structured way on disk. It stores tickets as simple files and lets you link them either as subtasks or as dependencies. That gives your agent enough information to determine a good next ticket to work on, while keeping a clear place to collect and organize tasks. You can track the tickets in git or keep them out of version control - that's up to you (I prefer not to track them).

[beads](https://github.com/steveyegge/beads), [beans](https://github.com/hmans/beans), and [the original `ticket` project](https://github.com/wedow/ticket) are onto something: letting agents manage tasks in a structured way has real merits. I just found those tools to be more than I needed for my own workflow.

## Installation

Installation is just putting `tk` somewhere on your `PATH`.

`tk` requires `bash`, so Linux, macOS, and Windows with WSL should be fine.

## Usage

```bash
tk - minimal ticket system with dependency tracking

Usage: tk <command> [args]

Commands:
  create [title] [options] Create ticket, prints ID
    -d, --description      Description text
    -p, --priority         Priority 0-4, 0=highest [default: 2]
    --parent               Parent ticket ID
  start <id>               Set status to in_progress
  close <id>               Set status to closed
  reopen <id>              Set status to open
  status <id> <status>     Update status (open|in_progress|closed)
  dep <id> <dep-id>        Add dependency (id depends on dep-id)
  dep tree [--full] [id]   Show dependency tree, optionally for one ticket
  undep <id> <dep-id>      Remove dependency
  ls|list [--status=X]     List tickets
  tree [id]                Show tickets in parent/child hierarchy
  ready                    List open/in-progress tickets with deps resolved
  blocked                  List open/in-progress tickets with unresolved deps
  closed [--limit=N]       List recently closed tickets (default 20, by mtime)
  prune                    Delete closed tickets not reachable from non-closed tickets
  delete <id>              Delete one unreferenced ticket
  show <id>                Display ticket
  add-note <id> [text]     Append timestamped note (or pipe via stdin)

Create work with 'tk create "Title"' and optionally group it under a larger task with '--parent <id>' to model a subtask. Use 'tk dep <id> <dep-id>' when one ticket is blocked by another ticket and cannot be completed first. In other words, A -> B means ticket A depends on B. Use parent/child links to describe breakdown of work, and dependency links to describe execution order or blocking relationships.

Examples:
  tk create "Ship release notes"
  tk create "Draft changelog" --parent abc123
  tk create "Publish GitHub release" --parent abc123
  tk dep publish-id changelog-id   # publish is blocked by changelog
```

## Testing

Run the regression suite from the repository root:

```bash
./test/test.sh
```

The tests use temporary workspaces and exercise the CLI end-to-end, including ticket creation, status updates, dependencies, pruning, partial ID resolution, and the known regression cases.

## Notes

- Tickets are stored as Markdown files in `.tickets/`
- Set `TICKETS_DIR` to use a different ticket directory
- The script walks parent directories to find `.tickets/` when `TICKETS_DIR` is not set
- Supports partial ID matching (e.g. `tk show 1a2` matches `1a2b3c`)
- `dep tree` marks repeated dependencies as `(shared)` unless you use `--full`
- `prune` removes closed-only dependency/parent chains in one pass, but still retains closed tickets that are reachable from non-closed tickets
- `delete` refuses to remove tickets that are still referenced via `deps` or `parent`
- `show` uses `TICKET_PAGER` first, then `PAGER`, when stdout is a TTY

## Upstream

This is a customized, simplified fork of the [original `ticket` project](https://github.com/wedow/ticket). It is tailored to my own workflow and may or may not be useful to others.

## License

MIT
