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

file_mtime() {
    local file="$1"
    if stat -c %Y "$file" >/dev/null 2>&1; then
        stat -c %Y "$file"
    else
        stat -f %m "$file"
    fi
}

file_mode() {
    local file="$1"
    if stat -c %a "$file" >/dev/null 2>&1; then
        stat -c %a "$file"
    else
        stat -f %Lp "$file"
    fi
}

process_token() {
    local pid="$1" started
    started=$(LC_ALL=C ps -p "$pid" -o lstart=)
    read -r started <<< "$started"
    printf '%s:%s\n' "$pid" "$started"
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

test_create_does_not_follow_dangling_symlink() {
    local dir fake_bin state_file
    dir=$(new_workspace)
    fake_bin="$dir/fake-bin"
    state_file="$dir/tr-state"
    mkdir -p "$dir/.tickets" "$fake_bin"
    ln -s ../outside-created.md "$dir/.tickets/abc123.md"

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

    run_in_dir "$dir" env PATH="$fake_bin:$PATH" "$TK" create "Safe collision"
    assert_status 0
    assert_equals "def456"
    [[ ! -e "$dir/outside-created.md" ]] || fail "create followed a dangling symlink"
    [[ -L "$dir/.tickets/abc123.md" ]] || fail "expected dangling symlink to remain"
    [[ -f "$dir/.tickets/def456.md" ]] || fail "expected create to retry with a safe ID"

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
    assert_contains "Usage: tk create [title] [options]"
    assert_contains "--priority <0-4>"
    assert_not_contains "closed [--limit N]"

    run_in_dir "$dir" "$TK" help create
    assert_status 0
    assert_contains "Usage: tk create [title] [options]"
    assert_not_contains "closed [--limit N]"

    run_in_dir "$dir" "$TK" help create --help
    assert_status 0
    assert_contains "Usage: tk create [title] [options]"

    run_in_dir "$dir" "$TK" create "Ignored title" --help
    assert_status 0
    assert_contains "Usage: tk create [title] [options]"
    [[ ! -d "$dir/.tickets" ]] || fail "help should not initialize a ticket store"

    run_in_dir "$dir" "$TK" dep tree missing --help
    assert_status 0
    assert_contains "Usage: tk dep tree [--full] [id]"
    [[ ! -d "$dir/.tickets" ]] || fail "nested help should not initialize a ticket store"

    run_in_dir "$dir" "$TK" dep tree --help
    assert_status 0
    assert_contains "Usage: tk dep tree [--full] [id]"
    assert_contains "--full"
    assert_not_contains "no .tickets directory found"

    run_in_dir "$dir" "$TK" help dep tree
    assert_status 0
    assert_contains "Usage: tk dep tree [--full] [id]"

    run_in_dir "$dir" "$TK" ready --help
    assert_status 0
    assert_contains "Usage: tk ready"
    assert_not_contains "create [title] [options]"

    run_in_dir "$dir" "$TK" help dep-tree
    assert_status 1
    assert_contains "Unknown help topic: dep-tree"

    run_in_dir "$dir" "$TK" unknown-command
    assert_status 1
    assert_contains "Unknown command: unknown-command"
    assert_not_contains "no .tickets directory found"

    run_in_dir "$dir" "$TK" unknown-command --help
    assert_status 1
    assert_contains "Unknown command: unknown-command"
    assert_not_contains "Unknown help topic"

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

test_read_commands_allow_missing_store() {
    local dir cmd
    dir=$(new_workspace)

    for cmd in list ready blocked tree closed; do
        run_in_dir "$dir" "$TK" "$cmd"
        assert_status 0
        assert_equals ""
    done

    run_in_dir "$dir" "$TK" dep tree
    assert_status 0
    assert_equals ""

    run_in_dir "$dir" "$TK" done
    assert_status 0
    assert_contains "All tickets are closed"

    run_in_dir "$dir" "$TK" show missing
    assert_status 1
    assert_contains "Error: no .tickets directory found"

    rm -rf "$dir"
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

    run_in_dir "$dir" "$TK" create "Dash description" "--description=-n"
    assert_status 0
    id="$LAST_OUTPUT"
    run_in_dir "$dir" "$TK" show "$id"
    assert_status 0
    grep -Fx -- '-n' "$dir/.tickets/$id.md" >/dev/null || fail "expected literal -n description"

    run_in_dir "$dir" "$TK" create -- "-n"
    assert_status 0
    id="$LAST_OUTPUT"
    run_in_dir "$dir" "$TK" show "$id"
    assert_status 0
    assert_contains "# -n"

    rm -rf "$dir"
}

test_list_and_closed_option_parsing() {
    local dir line_count
    dir=$(new_workspace)

    write_ticket_file "$dir" open01 open "Open ticket"
    write_ticket_file "$dir" prog01 in_progress "Progress ticket"
    write_ticket_file "$dir" shut01 closed "Closed ticket"
    write_ticket_file "$dir" shut02 closed "Second closed ticket"

    run_in_dir "$dir" "$TK" list --status open
    assert_status 0
    assert_contains "open01"
    assert_not_contains "prog01"
    assert_not_contains "shut01"

    run_in_dir "$dir" "$TK" list --status open --status in_progress
    assert_status 0
    assert_contains "open01"
    assert_contains "prog01"
    assert_not_contains "shut01"

    run_in_dir "$dir" "$TK" list --status=closed
    assert_status 0
    assert_contains "shut01"
    assert_contains "shut02"
    assert_not_contains "open01"

    run_in_dir "$dir" "$TK" list --format json
    assert_status 1
    assert_contains "Unknown option: --format"

    run_in_dir "$dir" "$TK" list --status bogus
    assert_status 1
    assert_contains "Error: invalid status 'bogus'"

    run_in_dir "$dir" "$TK" closed --limit 1
    assert_status 0
    line_count=$(printf '%s\n' "$LAST_OUTPUT" | sed '/^$/d' | wc -l)
    [[ "$line_count" -eq 1 ]] || fail "expected one closed ticket, got $line_count"

    run_in_dir "$dir" "$TK" closed --limit=1
    assert_status 0
    line_count=$(printf '%s\n' "$LAST_OUTPUT" | sed '/^$/d' | wc -l)
    [[ "$line_count" -eq 1 ]] || fail "expected one closed ticket, got $line_count"

    run_in_dir "$dir" "$TK" closed --all
    assert_status 1
    assert_contains "Unknown option: --all"

    rm -rf "$dir"
}

test_closed_filters_before_applying_limit() {
    local dir id line_count
    dir=$(new_workspace)

    write_ticket_file "$dir" old001 closed "Old closed ticket"
    touch -t 202001010000 "$dir/.tickets/old001.md"

    for i in $(seq 1 101); do
        printf -v id 'o%05d' "$i"
        write_ticket_file "$dir" "$id" open "Open $i"
    done

    run_in_dir "$dir" "$TK" closed
    assert_status 0
    assert_contains "old001"

    for i in $(seq 1 105); do
        printf -v id 'c%05d' "$i"
        write_ticket_file "$dir" "$id" closed "Closed $i"
    done

    run_in_dir "$dir" "$TK" closed --limit 150
    assert_status 0
    line_count=$(printf '%s\n' "$LAST_OUTPUT" | sed '/^$/d' | wc -l)
    [[ "$line_count" -eq 106 ]] || fail "expected all 106 closed tickets, got $line_count"

    run_in_dir "$dir" "$TK" closed --limit 2
    assert_status 0
    line_count=$(printf '%s\n' "$LAST_OUTPUT" | sed '/^$/d' | wc -l)
    [[ "$line_count" -eq 2 ]] || fail "expected closed limit to apply after filtering"

    rm -rf "$dir"
}

test_commands_reject_unexpected_arguments() {
    local dir invalid_dir id other_id
    invalid_dir=$(new_workspace)

    run_in_dir "$invalid_dir" "$TK" create "First" "Second"
    assert_status 1
    assert_contains "Unexpected argument: Second"
    assert_contains "Usage: tk create [title] [options]"
    [[ ! -d "$invalid_dir/.tickets" ]] || fail "invalid create should not initialize a ticket store"

    run_in_dir "$invalid_dir" "$TK" create -d --bogus
    assert_status 1
    assert_contains "Error: -d requires a value"
    [[ ! -d "$invalid_dir/.tickets" ]] || fail "invalid description option should not initialize a ticket store"

    run_in_dir "$invalid_dir" "$TK" create "Child" --parent missing
    assert_status 1
    assert_contains "Error: ticket 'missing' not found"
    [[ ! -d "$invalid_dir/.tickets" ]] || fail "invalid parent should not initialize a ticket store"
    rm -rf "$invalid_dir"

    dir=$(new_workspace)
    run_in_dir "$dir" "$TK" create "Primary"
    assert_status 0
    id="$LAST_OUTPUT"
    run_in_dir "$dir" "$TK" create "Other"
    assert_status 0
    other_id="$LAST_OUTPUT"

    run_in_dir "$dir" "$TK" start "$id" extra
    assert_status 1
    assert_contains "Usage: tk start <id>"
    run_in_dir "$dir" "$TK" close "$id" extra
    assert_status 1
    assert_contains "Usage: tk close <id>"
    run_in_dir "$dir" "$TK" reopen "$id" extra
    assert_status 1
    assert_contains "Usage: tk reopen <id>"
    run_in_dir "$dir" "$TK" status "$id" closed extra
    assert_status 1
    assert_contains "Usage: tk status <id> <status>"

    run_in_dir "$dir" "$TK" show "$id"
    assert_status 0
    assert_contains "status: open"

    run_in_dir "$dir" "$TK" dep "$id" "$other_id" extra
    assert_status 1
    assert_contains "Usage: tk dep <id> <dependency-id>"
    run_in_dir "$dir" "$TK" show "$id"
    assert_status 0
    assert_contains "deps: []"

    run_in_dir "$dir" "$TK" dep "$id" "$other_id"
    assert_status 0
    run_in_dir "$dir" "$TK" undep "$id" "$other_id" extra
    assert_status 1
    assert_contains "Usage: tk undep <id> <dependency-id>"
    run_in_dir "$dir" "$TK" show "$id"
    assert_status 0
    assert_contains "deps: [$other_id]"

    run_in_dir "$dir" "$TK" dep tree --bogus
    assert_status 1
    assert_contains "Unknown option: --bogus"
    assert_contains "Usage: tk dep tree [--full] [id]"
    run_in_dir "$dir" "$TK" tree --bogus
    assert_status 1
    assert_contains "Unknown option: --bogus"
    run_in_dir "$dir" "$TK" ready extra
    assert_status 1
    assert_contains "Unexpected argument: extra"
    run_in_dir "$dir" "$TK" blocked --bogus
    assert_status 1
    assert_contains "Unknown option: --bogus"

    run_in_dir "$dir" "$TK" delete "$id" extra
    assert_status 1
    assert_contains "Usage: tk delete <id>"
    [[ -f "$dir/.tickets/$id.md" ]] || fail "invalid delete should not remove the ticket"
    run_in_dir "$dir" "$TK" show "$id" extra
    assert_status 1
    assert_contains "Usage: tk show <id>"

    cp "$dir/.tickets/$id.md" "$dir/ticket-before-option.md"
    run_in_dir "$dir" "$TK" add-note "$id" ""
    assert_status 1
    assert_contains "Error: no note provided"
    cmp -s "$dir/.tickets/$id.md" "$dir/ticket-before-option.md" || fail "empty note should not change the ticket"

    run_in_dir "$dir" bash -c ': | "$1" add-note "$2"' _ "$TK" "$id"
    assert_status 1
    assert_contains "Error: no note provided"
    cmp -s "$dir/.tickets/$id.md" "$dir/ticket-before-option.md" || fail "empty stdin note should not change the ticket"

    run_in_dir "$dir" "$TK" add-note "$id" --bogus
    assert_status 1
    assert_contains "Unknown option: --bogus"
    cmp -s "$dir/.tickets/$id.md" "$dir/ticket-before-option.md" || fail "unknown add-note option should not change the ticket"

    run_in_dir "$dir" "$TK" add-note "$id" -- "--help is literal text"
    assert_status 0
    run_in_dir "$dir" "$TK" show "$id"
    assert_status 0
    assert_contains "--help is literal text"

    cp "$dir/.tickets/$id.md" "$dir/ticket-before-help.md"
    run_in_dir "$dir" "$TK" add-note "$id" --help
    assert_status 0
    assert_contains "Usage: tk add-note <id> [note text]"
    cmp -s "$dir/.tickets/$id.md" "$dir/ticket-before-help.md" || fail "help should not append a note"

    rm -rf "$dir"
}

test_writer_lock_waits_and_recovers() {
    local dir id holder
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" create "Locked ticket"
    assert_status 0
    id="$LAST_OUTPUT"

    (
        process_token "$BASHPID" > "$dir/.tickets/.lock"
        sleep 0.3
        rm -f "$dir/.tickets/.lock"
    ) &
    holder=$!
    while [[ ! -s "$dir/.tickets/.lock" ]]; do sleep 0.01; done
    run_in_dir "$dir" "$TK" close "$id"
    assert_status 0
    wait "$holder"

    printf '%s\n' '99999999:stale process' > "$dir/.tickets/.lock"
    run_in_dir "$dir" "$TK" reopen "$id"
    assert_status 0
    [[ ! -e "$dir/.tickets/.lock" ]] || fail "expected stale lock recovery"

    : > "$dir/.tickets/.lock"
    run_in_dir "$dir" "$TK" status "$id" open
    assert_status 0
    [[ ! -e "$dir/.tickets/.lock" ]] || fail "expected incomplete lock recovery"

    printf '%s\n' '99999999:stale process' > "$dir/.tickets/.lock"
    mkdir "$dir/.tickets/.lock.reaper"
    run_in_dir "$dir" "$TK" status "$id" open
    assert_status 1
    assert_contains "ticket store is busy"
    rmdir "$dir/.tickets/.lock.reaper"
    run_in_dir "$dir" "$TK" status "$id" open
    assert_status 0
    [[ ! -e "$dir/.tickets/.lock" ]] || fail "expected stale lock recovery after removing orphaned reaper"

    mkdir "$dir/.tickets/.lock"
    run_in_dir "$dir" "$TK" close "$id"
    assert_status 1
    assert_contains "invalid ticket-store lock"
    rmdir "$dir/.tickets/.lock"

    (
        process_token "$BASHPID" > "$dir/.tickets/.lock"
        sleep 5
    ) &
    holder=$!
    while [[ ! -s "$dir/.tickets/.lock" ]]; do sleep 0.01; done
    run_in_dir "$dir" "$TK" close "$id"
    assert_status 1
    assert_contains "ticket store is busy"
    kill "$holder" 2>/dev/null || true
    wait "$holder" 2>/dev/null || true
    rm -f "$dir/.tickets/.lock"

    run_in_dir "$dir" "$TK" show "$id"
    assert_status 0
    assert_contains "status: open"

    rm -rf "$dir"
}

test_concurrent_writers_are_serialized() {
    local dir task dep_one dep_two p1 p2 s1 s2
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" create "Task"
    assert_status 0
    task="$LAST_OUTPUT"
    run_in_dir "$dir" "$TK" create "Dependency one"
    assert_status 0
    dep_one="$LAST_OUTPUT"
    run_in_dir "$dir" "$TK" create "Dependency two"
    assert_status 0
    dep_two="$LAST_OUTPUT"

    (cd "$dir" && "$TK" dep "$task" "$dep_one" >dep-one.out 2>&1) & p1=$!
    (cd "$dir" && "$TK" dep "$task" "$dep_two" >dep-two.out 2>&1) & p2=$!
    if wait "$p1"; then s1=0; else s1=$?; fi
    if wait "$p2"; then s2=0; else s2=$?; fi
    [[ $s1 -eq 0 && $s2 -eq 0 ]] || fail "expected concurrent dependency updates to succeed"

    run_in_dir "$dir" "$TK" show "$task"
    assert_status 0
    assert_contains "$dep_one"
    assert_contains "$dep_two"

    (cd "$dir" && "$TK" add-note "$task" "Concurrent note one" >note-one.out 2>&1) & p1=$!
    (cd "$dir" && "$TK" add-note "$task" "Concurrent note two" >note-two.out 2>&1) & p2=$!
    if wait "$p1"; then s1=0; else s1=$?; fi
    if wait "$p2"; then s2=0; else s2=$?; fi
    [[ $s1 -eq 0 && $s2 -eq 0 ]] || fail "expected concurrent notes to succeed"

    run_in_dir "$dir" "$TK" show "$task"
    assert_status 0
    assert_contains "Concurrent note one"
    assert_contains "Concurrent note two"

    rm -rf "$dir"
}

test_atomic_updates_preserve_permissions() {
    local dir task dep file
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" create "Private ticket"
    assert_status 0
    task="$LAST_OUTPUT"
    run_in_dir "$dir" "$TK" create "Dependency"
    assert_status 0
    dep="$LAST_OUTPUT"
    file="$dir/.tickets/$task.md"
    chmod 600 "$file"

    run_in_dir "$dir" "$TK" start "$task"
    assert_status 0
    [[ "$(file_mode "$file")" == "600" ]] || fail "status update changed ticket permissions"
    run_in_dir "$dir" "$TK" dep "$task" "$dep"
    assert_status 0
    [[ "$(file_mode "$file")" == "600" ]] || fail "dependency update changed ticket permissions"
    run_in_dir "$dir" "$TK" undep "$task" "$dep"
    assert_status 0
    [[ "$(file_mode "$file")" == "600" ]] || fail "dependency removal changed ticket permissions"
    run_in_dir "$dir" "$TK" add-note "$task" "Private note"
    assert_status 0
    [[ "$(file_mode "$file")" == "600" ]] || fail "note update changed ticket permissions"

    chmod 444 "$file"
    run_in_dir "$dir" "$TK" close "$task"
    assert_status 0
    [[ "$(file_mode "$file")" == "444" ]] || fail "read-only status update changed ticket permissions"
    run_in_dir "$dir" "$TK" add-note "$task" "Read-only note"
    assert_status 0
    [[ "$(file_mode "$file")" == "444" ]] || fail "read-only note update changed ticket permissions"

    run_in_dir "$dir" bash -c 'umask 0777; "$1" add-note "$2" "Restrictive umask note"' _ "$TK" "$task"
    assert_status 0
    [[ "$(file_mode "$file")" == "444" ]] || fail "restrictive umask changed ticket permissions"

    [[ ! -e "$dir/.tickets/.lock" && ! -L "$dir/.tickets/.lock" ]] || fail "writer lock was not cleaned up"
    [[ ! -d "$dir/.tickets/.lock.reaper" ]] || fail "lock reaper was not cleaned up"
    shopt -s nullglob
    local temps=("$dir"/.tickets/.tk.tmp.*)
    shopt -u nullglob
    [[ ${#temps[@]} -eq 0 ]] || fail "temporary ticket files were not cleaned up"

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

test_status_updates_are_true_noops() {
    local dir id file before after
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" create "Stable status"
    assert_status 0
    id="$LAST_OUTPUT"
    file="$dir/.tickets/$id.md"

    touch -t 202001010000 "$file"
    before=$(file_mtime "$file")
    run_in_dir "$dir" "$TK" status "$id" open
    assert_status 0
    assert_contains "Ticket $id is already open"
    after=$(file_mtime "$file")
    [[ "$after" == "$before" ]] || fail "expected no-op status to preserve mtime"

    run_in_dir "$dir" "$TK" reopen "$id"
    assert_status 0
    assert_contains "Ticket $id is already open"
    after=$(file_mtime "$file")
    [[ "$after" == "$before" ]] || fail "expected no-op reopen to preserve mtime"

    run_in_dir "$dir" "$TK" start "$id"
    assert_status 0
    touch -t 202001010000 "$file"
    before=$(file_mtime "$file")
    run_in_dir "$dir" "$TK" start "$id"
    assert_status 0
    assert_contains "Ticket $id is already in_progress"
    after=$(file_mtime "$file")
    [[ "$after" == "$before" ]] || fail "expected no-op start to preserve mtime"

    run_in_dir "$dir" "$TK" close "$id"
    assert_status 0
    touch -t 202001010000 "$file"
    before=$(file_mtime "$file")
    run_in_dir "$dir" "$TK" close "$id"
    assert_status 0
    assert_contains "Ticket $id is already closed"
    after=$(file_mtime "$file")
    [[ "$after" == "$before" ]] || fail "expected no-op close to preserve mtime"

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

    run_in_dir "$dir" "$TK" undep "$task_id" "$blocker_id"
    assert_status 0
    assert_contains "Dependency not found"

    rm -rf "$dir"
}

test_undep_repairs_dangling_dependency() {
    local dir
    dir=$(new_workspace)

    write_ticket_file "$dir" task01 open "Task" "[abc111]"
    write_ticket_file "$dir" abc222 open "Unrelated live ticket"

    run_in_dir "$dir" "$TK" undep task01 abc
    assert_status 0
    assert_contains "Removed dependency: task01 -/-> abc111"
    run_in_dir "$dir" "$TK" show task01
    assert_status 0
    assert_contains "deps: []"

    write_ticket_file "$dir" task01 open "Task" "[abc111, abc333]"
    run_in_dir "$dir" "$TK" undep task01 abc
    assert_status 1
    assert_contains "matches multiple stored dependencies"

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

    run_in_dir "$dir" "$TK" show abc111
    assert_status 0
    assert_contains "# Alpha one"

    run_in_dir "$dir" "$TK" show abc
    assert_status 1
    assert_contains "Error: ambiguous ID 'abc' matches multiple tickets"

    rm -rf "$dir"
}

test_ticket_lookup_stays_inside_store() {
    local dir id
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" create "Safe ticket"
    assert_status 0
    id="$LAST_OUTPUT"
    printf '%s\n' "outside" > "$dir/victim.md"
    cp "$dir/victim.md" "$dir/victim.before"

    local invalid
    for invalid in '../victim' '*' '?' '[' 'abc/def' ''; do
        run_in_dir "$dir" "$TK" delete "$invalid"
        assert_status 1
        assert_contains "invalid ticket ID"
    done
    [[ -f "$dir/victim.md" ]] || fail "ticket lookup escaped the store"
    cmp -s "$dir/victim.md" "$dir/victim.before" || fail "outside file changed"
    [[ -f "$dir/.tickets/$id.md" ]] || fail "invalid lookup deleted a real ticket"

    ln -s ../victim.md "$dir/.tickets/link01.md"
    run_in_dir "$dir" "$TK" list
    assert_status 0
    assert_not_contains "link01"
    run_in_dir "$dir" "$TK" show link01
    assert_status 1
    assert_contains "is a symbolic link"
    run_in_dir "$dir" "$TK" add-note link01 "unsafe"
    assert_status 1
    assert_contains "is a symbolic link"
    assert_equals "Error: ticket 'link01' is a symbolic link"
    cmp -s "$dir/victim.md" "$dir/victim.before" || fail "symlink target changed"

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

test_prune_all_closed_returns_success() {
    local dir id
    dir=$(new_workspace)

    run_in_dir "$dir" "$TK" create "Prune me"
    assert_status 0
    id="$LAST_OUTPUT"
    run_in_dir "$dir" "$TK" close "$id"
    assert_status 0
    run_in_dir "$dir" "$TK" prune
    assert_status 0
    assert_contains "Pruned 1 ticket(s)"
    [[ ! -f "$dir/.tickets/$id.md" ]] || fail "expected closed ticket to be pruned"

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
    run_test test_create_does_not_follow_dangling_symlink
    run_test test_parser_errors_are_not_suppressed
    run_test test_subcommand_help_does_not_need_ticket_store
    run_test test_init_creates_store_and_gitignore
    run_test test_read_commands_allow_missing_store
    run_test test_create_reads_description_from_stdin
    run_test test_list_and_closed_option_parsing
    run_test test_closed_filters_before_applying_limit
    run_test test_commands_reject_unexpected_arguments
    run_test test_writer_lock_waits_and_recovers
    run_test test_concurrent_writers_are_serialized
    run_test test_atomic_updates_preserve_permissions
    run_test test_create_show_and_status_flow
    run_test test_status_updates_are_true_noops
    run_test test_dep_and_undep_flow
    run_test test_undep_repairs_dangling_dependency
    run_test test_partial_id_resolution_and_ambiguity
    run_test test_ticket_lookup_stays_inside_store
    run_test test_delete_refuses_referenced_tickets
    run_test test_prune_keeps_reachable_closed_tickets
    run_test test_prune_all_closed_returns_success
    run_test test_done_reports_completion_via_exit_status
    echo
    echo "Passed: $PASS_COUNT"
}

main "$@"
