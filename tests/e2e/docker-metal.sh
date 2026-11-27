#!/bin/sh
# The runtime image compiles Metal shaders: runs the render test (built on
# the host by `make check`) in the image as its default user, on a cold
# shader cache.
#   tests/e2e/docker-metal.sh [image]
set -eu
cd "$(dirname "$0")/../.."
B=$(cd "${BUILD:-build}" && pwd)
image=${1:-bitten}
[ -x "$B/tests/metal/render" ] || { echo "FAIL: build $B/tests/metal/render first (make check)" >&2; exit 1; }
out=$(docker run --rm -v "$B/tests/metal:/t:ro" --entrypoint /bin/sh "$image" -c \
    'export HOME=$(mktemp -d) && mrun /t/render && ls "$HOME"/Library/Caches/bitten/metal/*/shaders.so' 2>&1) ||
    { echo "FAIL: $out" >&2; exit 1; }
echo "$out" | grep -qx 'render ok' || { echo "FAIL: $out" >&2; exit 1; }
echo "docker metal ok"
