#!/usr/bin/env python3
"""Pack LLVM IR modules into a minimal .metallib, for tests.

    metal-pack.py OUT.metallib CLANG MODULE.ll...

Each module becomes bitcode in a bitcode wrapper, after an 'MTLB' header;
that is all of the container tools/metal-compile.py reads."""
import struct
import subprocess
import sys

out, clang, mods = sys.argv[1], sys.argv[2], sys.argv[3:]
blob = bytearray(b'MTLB' + b'\0' * 60)
for m in mods:
    bc = subprocess.run([clang, '-c', '-emit-llvm', '-x', 'ir', m, '-o', '-', '-Wno-override-module'],
                        check=True, capture_output=True).stdout
    blob += struct.pack('<IIIII', 0x0B17C0DE, 0, 20, len(bc), 0) + bc
open(out, 'wb').write(bytes(blob))
