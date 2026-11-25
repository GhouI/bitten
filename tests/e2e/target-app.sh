#!/bin/sh
# End-to-end check with a real App.dmg, in a container:
#   APP_DMG=/path/to/App.dmg tests/e2e/target-app.sh [image]
# Runs the helper, starts the app's server with the terminal viewer, types a
# command into one of its terminals and checks its output. Not part of `make check`
# because the disk image is not redistributable.
set -eu
: "${APP_DMG:?set APP_DMG to the path of your App.dmg}"
: "${APPCLI:?set APPCLI to the name of the app's command-line program}"
image=${1:-bitten}
name="bitten-e2e-$$"
port=${PORT:-7699}
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

out=$(docker run --rm -v "$APP_DMG:/dmg/app.dmg:ro" "$image" info 2>&1)
echo "$out" | grep -q "$APPCLI .*ready" || fail "info does not report the helper as ready: $out"
out=$(docker run --rm -v "$APP_DMG:/dmg/app.dmg:ro" "$image" exec "$APPCLI" version 2>&1)
echo "$out" | grep -q "^$APPCLI " || fail "$APPCLI version: $out"

docker run -d --name "$name" -p "127.0.0.1:$port:7680" -e APPCLI="$APPCLI" -v "$APP_DMG:/dmg/app.dmg:ro" "$image" \
    shell -c 'exec python3 /usr/share/bitten/examples/mac-terminal/terminal.py' >/dev/null
i=0
until curl -fsS "http://127.0.0.1:$port/" >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -lt 60 ] || { docker logs "$name" 2>&1 | tail -5 >&2; fail "viewer did not come up"; }
    sleep 0.5
done
printf 'echo e2e-$((40+2))\r' | curl -fsS -X POST --data-binary @- "http://127.0.0.1:$port/input"
sleep 1
screen=$(curl -fsS "http://127.0.0.1:$port/screen" | sed 's/<[^>]*>//g')
echo "$screen" | grep -q '^e2e-42$' || fail "terminal output missing: $screen"
echo "target app e2e ok"
