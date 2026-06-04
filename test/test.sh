#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TK="$ROOT_DIR/tk"

PASS_COUNT=0
FAIL_COUNT=0
LAST_STATUS=0
LAST_OUTPUT=""

fail() {
    echo "FAIL: $1" >&2
    if [[ -n "$LAST_OUTPUT" ]]; then
        echo "--- output ---" >&2
        printf '%s\n' "$LAST_OUTPUT" >&2
        echo "-------------" >&2
    fi
    exit 1
}

run_in_dir() {
    local dir="$1"
    shift

    local output_file
    output_file=$(mktemp)
    if (cd "$dir" && "$@") >"$output_file" 2>&1; then
        LAST_STATUS=0
    else
        LAST_STATUS=$?
    fi
    LAST_OUTPUT=$(<"$output_file")
    rm -f "$output_file"
}

assert_status() {
    local expected="$1"
    [[ "$LAST_STATUS" -eq "$expected" ]] || fail "expected exit status $expected, got $LAST_STATUS"
}

assert_contains() {
    local needle="$1"
    [[ "$LAST_OUTPUT" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
    local needle="$1"
    [[ "$LAST_OUTPUT" != *"$needle"* ]] || fail "expected output to not contain: $needle"
}

assert_equals() {
    local expected="$1"
    [[ "$LAST_OUTPUT" == "$expected" ]] || fail "expected output '$expected', got '$LAST_OUTPUT'"
}

new_workspace() {
    mktemp -d
}

first_ticket_id() {
    local dir="$1"
    local files=("$dir"/.tickets/*.md)
    [[ -e "${files[0]}" ]] || fail "no ticket files found in $dir/.tickets"
    basename "${files[0]}" .md
}

write_ticket_file() {
    local dir="$1"
    local id="$2"
    local status="$3"
    local title="$4"
    local deps="${5:-[]}"
    local priority="${6:-2}"
    local parent="${7:-}"

    mkdir -p "$dir/.tickets"
    {
        echo "---"
        echo "id: $id"
        echo "status: $status"
        echo "deps: $deps"
        echo "created: 2026-03-20T00:00:00Z"
        echo "priority: $priority"
        [[ -n "$parent" ]] && echo "parent: $parent"
        echo "---"
        echo "# $title"
    } > "$dir/.tickets/$id.md"
}

test_frontmatter_parser_ignores_body_hr() {
    local dir
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" create "Parser regression"
    assert_status 0
    local id="$LAST_OUTPUT"
    local file="$dir/.tickets/$id.md"

    cat >> "$file" <<'EOF'
## Notes

---
status: closed
EOF

    run_in_dir "$dir" "$TK" ls
    assert_status 0
    assert_contains "$id"
    assert_contains "[open] - Parser regression"

    run_in_dir "$dir" "$TK" ready
    assert_status 0
    assert_contains "$id"
    assert_contains "[P2][open] - Parser regression"

    run_in_dir "$dir" "$TK" closed
    assert_status 0
    assert_not_contains "$id"

    run_in_dir "$dir" "$TK" show "$id"
    assert_status 0
    assert_contains "status: open"

    rm -rf "$dir"
}

test_titles_with_pipe_render_in_ready_and_blocked() {
    local dir
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" create "A | B"
    assert_status 0
    local ready_id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" ready
    assert_status 0
    assert_contains "$ready_id"
    assert_contains "[P2][open] - A | B"

    run_in_dir "$dir" "$TK" create "Blocker"
    assert_status 0
    local blocker_id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" create "Needs | Blocker"
    assert_status 0
    local blocked_id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" dep "$blocked_id" "$blocker_id"
    assert_status 0

    run_in_dir "$dir" "$TK" blocked
    assert_status 0
    assert_contains "$blocked_id"
    assert_contains "[P2][open] - Needs | Blocker <- [$blocker_id]"

    rm -rf "$dir"
}

test_closed_works_in_paths_with_spaces() {
    local base dir
    base=$(new_workspace)
    dir="$base/space dir"
    mkdir -p "$dir"

    run_in_dir "$dir" "$TK" create "Closed ticket"
    assert_status 0
    local id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" close "$id"
    assert_status 0

    run_in_dir "$dir" "$TK" closed
    assert_status 0
    assert_contains "$id"
    assert_contains "[closed] - Closed ticket"

    rm -rf "$base"
}

test_create_reports_missing_option_values() {
    local dir
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" create "Missing description" -d
    assert_status 1
    assert_contains "Error: -d requires a value"

    run_in_dir "$dir" "$TK" create "Missing priority" -p
    assert_status 1
    assert_contains "Error: -p requires a value"

    run_in_dir "$dir" "$TK" create "Missing parent" --parent
    assert_status 1
    assert_contains "Error: --parent requires a value"

    rm -rf "$dir"
}

test_create_validates_priority_range() {
    local dir
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" create "Priority zero" -p 0
    assert_status 0

    run_in_dir "$dir" "$TK" create "Priority four" -p 4
    assert_status 0

    run_in_dir "$dir" "$TK" create "Priority five" -p 5
    assert_status 1
    assert_contains "Error: invalid priority '5'. Must be an integer from 0 to 4"

    run_in_dir "$dir" "$TK" create "Priority z" -p z
    assert_status 1
    assert_contains "Error: invalid priority 'z'. Must be an integer from 0 to 4"

    rm -rf "$dir"
}

test_create_retries_on_id_collision() {
    local dir fake_bin state_file
    dir=$(new_workspace)
    fake_bin="$dir/fake-bin"
    state_file="$dir/tr-state"
    mkdir -p "$dir/.tickets" "$fake_bin"

    cat > "$dir/.tickets/abc123.md" <<'EOF'
---
id: abc123
status: open
deps: []
created: 2026-03-20T00:00:00Z
priority: 2
---
# Existing
EOF

    cat > "$fake_bin/tr" <<EOF
#!/usr/bin/env bash
state_file="$state_file"
if [[ ! -f "\$state_file" ]]; then
    echo 1 > "\$state_file"
    printf 'abc123'
else
    printf 'def456'
fi
EOF
    chmod +x "$fake_bin/tr"

    run_in_dir "$dir" env PATH="$fake_bin:$PATH" "$TK" create "Collision retry"
    assert_status 0
    assert_equals "def456"

    [[ -f "$dir/.tickets/abc123.md" ]] || fail "expected original ticket to remain"
    [[ -f "$dir/.tickets/def456.md" ]] || fail "expected retried ticket to be created"

    run_in_dir "$dir" "$TK" show abc123
    assert_status 0
    assert_contains "# Existing"

    run_in_dir "$dir" "$TK" show def456
    assert_status 0
    assert_contains "# Collision retry"

    rm -rf "$dir"
}

test_parser_errors_are_not_suppressed() {
    local dir fake_bin
    dir=$(new_workspace)
    fake_bin="$dir/fake-bin"
    mkdir -p "$fake_bin"

    run_in_dir "$dir" "$TK" create "Visible error"
    assert_status 0

    cat > "$fake_bin/awk" <<'EOF'
#!/usr/bin/env bash
echo "awk exploded" >&2
exit 23
EOF
    chmod +x "$fake_bin/awk"

    run_in_dir "$dir" env PATH="$fake_bin:$PATH" "$TK" ls
    assert_status 23
    assert_contains "awk exploded"

    rm -rf "$dir"
}

test_subcommand_help_does_not_need_ticket_store() {
    local dir
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" create --help
    assert_status 0
    assert_contains "create [title] [options]"

    run_in_dir "$dir" "$TK" help create
    assert_status 0
    assert_contains "create [title] [options]"

    rm -rf "$dir"
}

test_init_creates_store_and_gitignore() {
    local dir count tracked_dir
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" init
    assert_status 0
    assert_contains "Initialized .tickets"
    assert_contains "Ignored .tickets/"
    [[ -d "$dir/.tickets" ]] || fail "expected .tickets directory"
    grep -Eq '^\.tickets/$' "$dir/.gitignore" || fail "expected .tickets/ in .gitignore"

    run_in_dir "$dir" "$TK" init
    assert_status 0
    assert_contains ".tickets/ already ignored"
    count=$(grep -Ec '^\.tickets/$' "$dir/.gitignore")
    [[ "$count" -eq 1 ]] || fail "expected one .tickets/ entry, got $count"

    tracked_dir=$(new_workspace)
    run_in_dir "$tracked_dir" "$TK" init --tracked
    assert_status 0
    assert_contains "Leaving tickets trackable by git"
    [[ -d "$tracked_dir/.tickets" ]] || fail "expected tracked .tickets directory"
    [[ ! -f "$tracked_dir/.gitignore" ]] || fail "did not expect .gitignore for tracked init"

    rm -rf "$dir" "$tracked_dir"
}

test_create_reads_description_from_stdin() {
    local dir id
    dir=$(new_workspace)

    run_in_dir "$dir" bash -c 'printf "%s\n" "Line one" "\`literal selector\`" "\$VALUE stays literal" | "$1" create "Stdin description" -d -' _ "$TK"
    assert_status 0
    id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" show "$id"
    assert_status 0
    assert_contains "# Stdin description"
    assert_contains "Line one"
    assert_contains '`literal selector`'
    assert_contains '$VALUE stays literal'

    rm -rf "$dir"
}

test_create_show_and_status_flow() {
    local dir id
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" create "Core flow" -d "Initial body"
    assert_status 0
    id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" show "$id"
    assert_status 0
    assert_contains "status: open"
    assert_contains "# Core flow"
    assert_contains "Initial body"

    run_in_dir "$dir" "$TK" start "$id"
    assert_status 0

    run_in_dir "$dir" "$TK" show "$id"
    assert_status 0
    assert_contains "status: in_progress"

    run_in_dir "$dir" "$TK" close "$id"
    assert_status 0

    run_in_dir "$dir" "$TK" show "$id"
    assert_status 0
    assert_contains "status: closed"

    rm -rf "$dir"
}

test_dep_and_undep_flow() {
    local dir blocker_id task_id
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" create "Blocker"
    assert_status 0
    blocker_id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" create "Task"
    assert_status 0
    task_id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" dep "$task_id" "$blocker_id"
    assert_status 0

    run_in_dir "$dir" "$TK" show "$task_id"
    assert_status 0
    assert_contains "deps: [$blocker_id]"

    run_in_dir "$dir" "$TK" undep "$task_id" "$blocker_id"
    assert_status 0

    run_in_dir "$dir" "$TK" show "$task_id"
    assert_status 0
    assert_contains "deps: []"

    rm -rf "$dir"
}

test_partial_id_resolution_and_ambiguity() {
    local dir
    dir=$(new_workspace)

    write_ticket_file "$dir" abc111 open "Alpha one"
    write_ticket_file "$dir" abc222 open "Alpha two"
    write_ticket_file "$dir" def333 open "Delta"

    run_in_dir "$dir" "$TK" show def
    assert_status 0
    assert_contains "# Delta"

    run_in_dir "$dir" "$TK" show abc
    assert_status 1
    assert_contains "Error: ambiguous ID 'abc' matches multiple tickets"

    rm -rf "$dir"
}

test_delete_refuses_referenced_tickets() {
    local dir blocker_id task_id
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" create "Blocker"
    assert_status 0
    blocker_id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" create "Task"
    assert_status 0
    task_id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" dep "$task_id" "$blocker_id"
    assert_status 0

    run_in_dir "$dir" "$TK" delete "$blocker_id"
    assert_status 1
    assert_contains "Error: cannot delete $blocker_id"
    assert_contains "dependency of $task_id"

    rm -rf "$dir"
}

test_prune_keeps_reachable_closed_tickets() {
    local dir blocker_id active_id orphan_id
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" create "Retained blocker"
    assert_status 0
    blocker_id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" create "Active task"
    assert_status 0
    active_id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" dep "$active_id" "$blocker_id"
    assert_status 0

    run_in_dir "$dir" "$TK" close "$blocker_id"
    assert_status 0

    run_in_dir "$dir" "$TK" create "Orphan closed"
    assert_status 0
    orphan_id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" close "$orphan_id"
    assert_status 0

    run_in_dir "$dir" "$TK" prune
    assert_status 0
    assert_contains "Retained $blocker_id"
    assert_contains "Pruned $orphan_id"

    [[ -f "$dir/.tickets/$blocker_id.md" ]] || fail "expected reachable closed ticket to be retained"
    [[ ! -f "$dir/.tickets/$orphan_id.md" ]] || fail "expected orphan closed ticket to be pruned"

    rm -rf "$dir"
}

test_done_reports_completion_via_exit_status() {
    local dir open_id progress_id
    dir=$(new_workspace)
    mkdir -p "$dir/.tickets"

    run_in_dir "$dir" "$TK" done
    assert_status 0
    assert_contains "All tickets are closed"

    run_in_dir "$dir" "$TK" create "Still open"
    assert_status 0
    open_id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" create "In progress"
    assert_status 0
    progress_id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" start "$progress_id"
    assert_status 0

    run_in_dir "$dir" "$TK" done
    assert_status 1
    assert_contains "Unfinished tickets remain:"
    assert_contains "$open_id"
    assert_contains "[open] - Still open"
    assert_contains "$progress_id"
    assert_contains "[in_progress] - In progress"

    run_in_dir "$dir" "$TK" close "$open_id"
    assert_status 0

    run_in_dir "$dir" "$TK" close "$progress_id"
    assert_status 0

    run_in_dir "$dir" "$TK" done
    assert_status 0
    assert_contains "All tickets are closed"

    rm -rf "$dir"
}

run_test() {
    local name="$1"
    echo "==> $name"
    "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
}

main() {
    run_test test_frontmatter_parser_ignores_body_hr
    run_test test_titles_with_pipe_render_in_ready_and_blocked
    run_test test_closed_works_in_paths_with_spaces
    run_test test_create_reports_missing_option_values
    run_test test_create_validates_priority_range
    run_test test_create_retries_on_id_collision
    run_test test_parser_errors_are_not_suppressed
    run_test test_subcommand_help_does_not_need_ticket_store
    run_test test_init_creates_store_and_gitignore
    run_test test_create_reads_description_from_stdin
    run_test test_create_show_and_status_flow
    run_test test_dep_and_undep_flow
    run_test test_partial_id_resolution_and_ambiguity
    run_test test_delete_refuses_referenced_tickets
    run_test test_prune_keeps_reachable_closed_tickets
    run_test test_done_reports_completion_via_exit_status
    echo
    echo "Passed: $PASS_COUNT"
}

main "$@"
