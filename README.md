# ticket

This is a customized, simplified fork of the original `ticket` project. It is tailored to my own workflow and probably has little or no value for other people.

`tk` is a small git-friendly issue tracker that stores tickets as Markdown files with YAML frontmatter in `.tickets/`.

## Usage

```bash
tk - minimal ticket system with dependency tracking

Usage: tk <command> [args]

Commands:
  create [title] [options] Create ticket, prints ID
    -d, --description      Description text
    --design               Design notes
    --acceptance           Acceptance criteria
    -t, --type             Type (bug|feature|task|epic|chore) [default: task]
    -p, --priority         Priority 0-4, 0=highest [default: 2]
    --parent               Parent ticket ID
    --tags                 Comma-separated tags (e.g., --tags ui,backend,urgent)
  start <id>               Set status to in_progress
  close <id>               Set status to closed
  reopen <id>              Set status to open
  status <id> <status>     Update status (open|in_progress|closed)
  dep <id> <dep-id>        Add dependency (id depends on dep-id)
  dep tree [--full] [id]   Show dependency tree, optionally for one ticket
  undep <id> <dep-id>      Remove dependency
  ls|list [--status=X] [-T X]   List tickets
  tree [id]                Show tickets in parent/child hierarchy
  ready [-T X]             List open/in-progress tickets with deps resolved
  blocked [-T X]           List open/in-progress tickets with unresolved deps
  closed [--limit=N] [-T X] List recently closed tickets (default 20, by mtime)
  prune                    Delete all closed tickets
  show <id>                Display ticket
  add-note <id> [text]     Append timestamped note (or pipe via stdin)

Searches parent directories for .tickets/ (override with TICKETS_DIR env var)
Supports partial ID matching (e.g., 'tk show 5c4' matches 'nw-5c46')
```

## Notes

- Tickets are stored as Markdown files in `.tickets/`
- The script walks parent directories to find `.tickets/`
- `dep tree` marks repeated dependencies as `(shared)` unless you use `--full`
- `show` uses `TICKET_PAGER` first, then `PAGER`, when stdout is a TTY

## License

MIT
