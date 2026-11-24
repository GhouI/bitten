#!/bin/sh
# Emit a text-based stub (.tbd) for libSystem listing every Darwin symbol the
# given mrun binary implements, so test programs can be linked as Mach-O
# without an Apple SDK.
set -eu
mrun=$1
printf -- '--- !tapi-tbd\ntbd-version: 4\ntargets: [ x86_64-macos ]\n'
printf -- "install-name: '/usr/lib/libSystem.B.dylib'\nexports:\n  - targets: [ x86_64-macos ]\n    symbols: [ dyld_stub_binder, '__tlv_bootstrap'"
"$mrun" --list-exports | sort -u | while read -r s; do printf ", '%s'" "$s"; done
printf ' ]\n...\n'
