#!/bin/sh
# Emit a text-based stub (.tbd) for libSystem listing every Darwin symbol the
# given mrun binary implements, so test programs can be linked as Mach-O
# without an Apple SDK.
set -eu
mrun=$1
exports=$("$mrun" --list-exports)
printf -- '--- !tapi-tbd\ntbd-version: 4\ntargets: [ x86_64-macos ]\n'
# swift_async_extendedFramePointerFlags is a data symbol whose address
# compiled async code ORs into the frame pointer. It is weak-imported and
# deliberately left undefined at run time, so it binds to 0 (frames are not
# tagged); it is listed only so that libraries using it link.
printf -- "install-name: '/usr/lib/libSystem.B.dylib'\nexports:\n  - targets: [ x86_64-macos ]\n    symbols: [ dyld_stub_binder, '__tlv_bootstrap', '_swift_async_extendedFramePointerFlags'"
if [ -n "$exports" ]; then
    printf '%s\n' "$exports" | sort -u | while read -r s; do printf ", '%s'" "$s"; done
fi
printf ' ]\n...\n'
