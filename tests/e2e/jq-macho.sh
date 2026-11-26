#!/bin/sh
# Exercise the upstream Intel macOS jq 1.8.1 release, without rebuilding it.
# JQ_MACOS=/path/to/jq-macos-amd64 tests/e2e/jq-macho.sh [path/to/mrun]
set -eu
: "${JQ_MACOS:?set JQ_MACOS to the official Intel macOS jq 1.8.1 binary}"
mrun=${1:-build/mrun}
tmp=$(mktemp -d)
trap 'rm -f "$tmp/input.json"; rmdir "$tmp"' EXIT

check() {
    expected=$1
    actual=$2
    if [ "$actual" != "$expected" ]; then
        printf 'Expected %s, got %s\n' "$expected" "$actual" >&2
        exit 1
    fi
}

imports=$("$mrun" --check "$JQ_MACOS")
check "$(printf 'SUMMARY\tmissing=0')" "$(printf '%s\n' "$imports" | tail -1)"
json='{"items":[2,4,6],"name":"bitten-42"}'
filter='{total:(.items|add),id:(.name|capture("-(?<id>[0-9]+)$").id|tonumber)}'
result=$(printf '%s\n' "$json" | "$mrun" "$JQ_MACOS" -ce "$filter")
check '{"total":12,"id":42}' "$result"
result=$("$mrun" "$JQ_MACOS" -nce '[(5|tgamma),(0|erfc),nextafter(1;2),scalbln(1;3)]')
check '[24,1,1.0000000000000002,8]' "$result"
printf '%s\n' '{"n":42}' > "$tmp/input.json"
result=$("$mrun" "$JQ_MACOS" -e '.n' "$tmp/input.json")
check 42 "$result"
echo 'upstream jq Mach-O ok'
