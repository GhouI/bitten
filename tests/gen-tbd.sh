#!/bin/sh
# gen-tbd.sh must fail when mrun cannot list its exports, and make must not
# leave a partial libSystem.tbd behind that a later build takes as current.
set -u
cd "$(dirname "$0")/.."
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
printf '#!/bin/sh\nexit 1\n' > "$d/mrun"
chmod +x "$d/mrun"
fail=0
if tools/gen-tbd.sh "$d/mrun" > "$d/out" 2>/dev/null; then
    echo "FAIL gen-tbd.sh exits 0 when mrun --list-exports fails"; fail=1
fi
if make -s BUILD="$d" -o "$d/mrun" "$d/sdk/libSystem.tbd" > /dev/null 2>&1; then
    echo "FAIL make succeeds when mrun --list-exports fails"; fail=1
fi
if [ -e "$d/sdk/libSystem.tbd" ]; then
    echo "FAIL make leaves libSystem.tbd after a failed generation"; fail=1
fi
[ "$fail" -eq 0 ] && echo "ok   tests/gen-tbd.sh"
exit "$fail"
