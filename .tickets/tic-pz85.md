---
id: tic-pz85
status: open
deps: []
links: []
created: 2026-03-20T16:50:01Z
type: task
priority: 2
assignee: Michael Jakl
parent: tic-0y5i
---
# Add tree command for parent/child hierarchy views

Add a `tree` command similar to `ls`, but organized by parent relationships.

Requirements:
- If a ticket ID is given, show only the hierarchy containing that ticket
- If no ticket ID is given, show all tickets in a hierarchy-aware tree view
- Tickets without parent relationships should still appear sensibly

Need to define output format and how to present mixed rooted/unrooted tickets clearly.

