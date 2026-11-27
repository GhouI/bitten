#!/bin/sh
# mrun in a build tree with no source tree beside it (the Docker image's
# /out/mrun) still compiles Metal libraries: the shader compiler is staged
# in $BUILD/tools, next to mrun. Runs the render test that way on a cold
# shader cache.
set -eu
cd "$(dirname "$0")/../.."
B=$(cd "${BUILD:-build}" && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/out" "$t/home"
cp "$B/mrun" "$t/out/mrun"
ln -s "$B/root" "$t/out/root"
cp -R "$B/tools" "$t/out/tools"
[ ! -e "$t/tools" ] || { echo "FAIL $t/tools exists"; exit 1; }
if ! out=$(env -u BITTEN_METAL_COMPILER HOME="$t/home" timeout 120 "$t/out/mrun" "$B/tests/metal/render" 2>&1); then
    echo "FAIL tests/metal/staged.sh"; echo "$out" | sed 's/^/     /' | tail -20; exit 1
fi
echo "$out" | grep -q '^render ok' || { echo "FAIL tests/metal/staged.sh: $out"; exit 1; }
ls "$t"/home/Library/Caches/bitten/metal/*/shaders.so >/dev/null || { echo "FAIL tests/metal/staged.sh: no shaders.so in the cache"; exit 1; }
echo "ok   tests/metal/staged.sh"
