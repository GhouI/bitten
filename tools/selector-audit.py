#!/usr/bin/env python3
"""Selectors a Mach-O program sends that no loaded class implements.

    tools/selector-audit.py PROGRAM DUMP [--all]

PROGRAM is a thin x86-64 Mach-O (the program's executable); DUMP is the
file BITTEN_SELECTOR_DUMP=path writes (with BITTEN_ALLOC_STATS set, on
SIGUSR1) while the program runs. Every name in the program's
__objc_selrefs that no class implements, as an instance or a class
method, is printed: a method our frameworks may be missing (an
"unrecognized selector" waiting to happen), or a delegate method the
program only sends after asking respondsToSelector:. Names the program
implements itself are in the dump too, so they never show.
"""
import struct
import sys


def segments_and_sections(d):
    magic, cputype, _, _, ncmds, _, _, _ = struct.unpack_from('<IiiIIIII', d, 0)
    if magic != 0xfeedfacf:
        sys.exit('not a thin 64-bit Mach-O (extract the x86_64 slice first)')
    off = 32
    segs, sects = [], []
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', d, off)
        if cmd == 0x19:  # LC_SEGMENT_64
            name = d[off + 8:off + 24].rstrip(b'\0').decode()
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', d, off + 24)
            nsects = struct.unpack_from('<I', d, off + 64)[0]
            segs.append((name, vmaddr, vmsize, fileoff))
            so = off + 72
            for _ in range(nsects):
                sname = d[so:so + 16].rstrip(b'\0').decode()
                addr, ssize, soff = struct.unpack_from('<QQI', d, so + 32)
                sects.append((name, sname, addr, ssize, soff))
                so += 80
        off += size
    return segs, sects


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    d = open(sys.argv[1], 'rb').read()
    segs, sects = segments_and_sections(d)
    base = next(v for n, v, _, _ in segs if n == '__TEXT')

    def file_offset(vm):
        for _, v, size, fo in segs:
            if v <= vm < v + size:
                return fo + vm - v
        return None

    def cstring(vm):
        fo = file_offset(vm)
        if fo is None:
            return None
        end = d.index(b'\0', fo)
        return d[fo:end].decode(errors='replace')

    sent = set()
    for seg, sect, addr, size, off in sects:
        if sect != '__objc_selrefs':
            continue
        for i in range(0, size, 8):
            v = struct.unpack_from('<Q', d, off + i)[0]
            # a chained-fixup rebase (target in the low 36 bits, an offset
            # from the image's base) or a plain pointer
            target = v & 0xFFFFFFFFF
            name = cstring(base + target if target < base else target)
            if name:
                sent.add(name)
    have = set()
    for line in open(sys.argv[2]):
        line = line.rstrip('\n')
        if len(line) > 1:
            have.add(line[1:])
    missing = sorted(sent - have)
    print(f'{len(sent)} selectors sent, {len(missing)} implemented by no class:', file=sys.stderr)
    for name in missing:
        print(name)


if __name__ == '__main__':
    main()
