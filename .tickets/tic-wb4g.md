---
id: tic-wb4g
status: closed
deps: []
links: []
created: 2026-03-20T16:50:01Z
type: task
priority: 2
assignee: Michael Jakl
parent: tic-0y5i
---
# Allow dep tree without an argument and design global dependency view

Extend `dep tree` so it also works without an ID argument.

Requirements:
- With an ID: keep the current behavior
- Without an ID: show all tickets organized by dependency hierarchy

Open design question:
- Multiple tickets may depend on the same ticket, so the visualization needs a clear strategy for shared dependencies, deduplication, repetition markers, or another readable representation. Capture and evaluate output ideas before implementing.

