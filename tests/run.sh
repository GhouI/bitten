#!/bin/sh
# Run every built Mach-O test under mrun.
set -u
cd "$(dirname "$0")/.."
B=${BUILD:-build}
fail=0; n=0
for t in "$B"/tests/c/* "$B"/tests/objc/* "$B"/tests/foundation/* "$B"/tests/appkit/* "$B"/tests/usernotifications/* "$B"/tests/quartzcore/* "$B"/tests/go/* "$B"/tests/swift/* "$B"/tests/swiftlib/*; do
    case "$t" in *.o|*.lib|*'*') continue;; esac
    [ -x "$t" ] || continue
    n=$((n+1))
    if out=$(timeout 60 "$B"/mrun "$t" 2>&1); then
        echo "ok   $t"
    else
        echo "FAIL $t (exit $?)"; echo "$out" | sed 's/^/     /' | tail -30
        fail=$((fail+1))
    fi
done
echo "$n tests, $fail failed"
[ "$fail" -eq 0 ]
