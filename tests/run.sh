#!/bin/sh
# Run every built Mach-O test under mrun.
set -u
cd "$(dirname "$0")/.."
fail=0; n=0
for t in build/tests/c/* build/tests/go/*; do
    case "$t" in *.o|*'*') continue;; esac
    [ -x "$t" ] || continue
    n=$((n+1))
    if out=$(timeout 60 build/mrun "$t" 2>&1); then
        echo "ok   $t"
    else
        echo "FAIL $t (exit $?)"; echo "$out" | sed 's/^/     /' | tail -30
        fail=$((fail+1))
    fi
done
echo "$n tests, $fail failed"
[ "$fail" -eq 0 ]
