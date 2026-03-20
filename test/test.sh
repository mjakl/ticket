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

run_test() {
    local name="$1"
    echo "==> $name"
    "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
}

main() {
    run_test test_frontmatter_parser_ignores_body_hr
    echo
    echo "Passed: $PASS_COUNT"
}

main "$@"
