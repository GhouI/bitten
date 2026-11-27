#!/bin/sh
# RG_MACOS=/path/to/rg tests/e2e/rg-macho.sh [path/to/mrun]
# Uses the official Intel Mac ripgrep executable; no source rebuild.
set -eu
: "${RG_MACOS:?set RG_MACOS to the official Intel macOS ripgrep executable}"
mrun=$(realpath "${1:-build/mrun}")
rg=$(realpath "$RG_MACOS")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
mkdir -p src other ignored
printf 'ignored/\n' > fixture.ignore
printf 'header\nBITTEN_COMPAT_MARKER\n' > src/want.txt
printf 'BITTEN_COMPAT_MARKER\n' > ignored/skip.txt
i=0
while [ "$i" -lt 128 ]; do
    printf 'noise\n' > "other/$i.txt"
    i=$((i + 1))
done

for threads in 1 4; do
    result=$("$mrun" "$rg" --ignore-file fixture.ignore --color never --threads "$threads" -n BITTEN_COMPAT_MARKER .)
    if [ "$result" != './src/want.txt:2:BITTEN_COMPAT_MARKER' ]; then
        printf 'Unexpected result with %s threads: %s\n' "$threads" "$result" >&2
        exit 1
    fi
done
rc=0
result=$("$mrun" "$rg" --threads 4 ABSENT_BITTEN_MARKER .) || rc=$?
if [ "$rc" != 1 ] || [ -n "$result" ]; then
    printf 'Unexpected no-match result: exit %s, output %s\n' "$rc" "$result" >&2
    exit 1
fi
echo 'upstream ripgrep Mach-O ok'
