#!/usr/bin/env python3
"""Generates stdlib/UnicodeData.swift from the Unicode Character Database.

    tools/gen-unicode.py --fetch DIR      # download the UCD files into DIR
    tools/gen-unicode.py DIR > stdlib/UnicodeData.swift

The UCD is published by the Unicode Consortium under the Unicode License
(https://www.unicode.org/license.txt). Only data derived from it is
emitted: property ranges and mappings, packed into string literals that
stdlib/UnicodeTables.swift decodes on first use.

Packing: a table is a sequence of unsigned integers, each written in
big-endian groups of 5 bits, one character per group, as 0x30 + group, with
0x20 added on every group but the last. Newlines are ignored.
"""
import os
import sys
import urllib.request

VERSION = "16.0.0"
FILES = {
    "UnicodeData.txt": "UnicodeData.txt",
    "GraphemeBreakProperty.txt": "auxiliary/GraphemeBreakProperty.txt",
    "emoji-data.txt": "emoji/emoji-data.txt",
    "DerivedCoreProperties.txt": "DerivedCoreProperties.txt",
    "DerivedNormalizationProps.txt": "DerivedNormalizationProps.txt",
    "SpecialCasing.txt": "SpecialCasing.txt",
    "PropList.txt": "PropList.txt",
    "DerivedNumericType.txt": "extracted/DerivedNumericType.txt",
}


def fetch(d):
    os.makedirs(d, exist_ok=True)
    for name, path in FILES.items():
        url = "https://www.unicode.org/Public/%s/ucd/%s" % (VERSION, path)
        with urllib.request.urlopen(url) as r, open(os.path.join(d, name), "wb") as f:
            f.write(r.read())


def lines(d, name):
    with open(os.path.join(d, name), encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line:
                yield [x.strip() for x in line.split(";")]


def code_range(s):
    if ".." in s:
        a, b = s.split("..")
        return int(a, 16), int(b, 16)
    return int(s, 16), int(s, 16)


def property_ranges(d, name, wanted=None):
    """{value: [(lo, hi)]} for a 'range ; value' file."""
    out = {}
    for f in lines(d, name):
        if wanted is not None and f[1] not in wanted:
            continue
        lo, hi = code_range(f[0])
        key = f[1] if len(f) < 3 else (f[1], f[2])
        out.setdefault(key, []).append((lo, hi))
    return out


def unicode_data(d):
    """Per-code-point fields of UnicodeData.txt, with the ranges expanded."""
    rows = {}
    first = None
    for f in lines(d, "UnicodeData.txt"):
        cp = int(f[0], 16)
        if f[1].endswith(", First>"):
            first = cp
            continue
        if f[1].endswith(", Last>"):
            for c in range(first, cp + 1):
                rows[c] = f
            continue
        rows[cp] = f
    return rows


# ---- packing ----------------------------------------------------------------

def pack(values):
    out = []
    for v in values:
        assert v >= 0
        groups = []
        while True:
            groups.append(v & 31)
            v >>= 5
            if v == 0:
                break
        groups.reverse()
        for i, g in enumerate(groups):
            out.append(chr(0x30 + g + (0x20 if i < len(groups) - 1 else 0)))
    text = "".join(out)
    rows = [text[i:i + 100] for i in range(0, len(text), 100)]
    return "\n".join(r.replace("\\", "\\\\") for r in rows)


def partition(values_by_cp, default=0):
    """(start, value) pairs where the value changes, from 0 to 0x110000."""
    out = []
    prev = None
    for cp in range(0x110000):
        v = values_by_cp.get(cp, default)
        if v != prev:
            out.append((cp, v))
            prev = v
    return out


def pack_partition(parts):
    flat = [len(parts)]
    last = 0
    for start, v in parts:
        flat += [start - last, v]
        last = start
    return pack(flat)


def pack_mapping(mapping):
    """Sorted keys, each with a list of scalars."""
    flat = [len(mapping)]
    last = 0
    for k in sorted(mapping):
        vs = mapping[k]
        flat += [k - last, len(vs)] + vs
        last = k
    return pack(flat)


# ---- tables -------------------------------------------------------------------

GCB = ["Other", "CR", "LF", "Control", "Extend", "ZWJ", "Regional_Indicator",
       "Prepend", "SpacingMark", "L", "V", "T", "LV", "LVT"]
INCB = {"None": 0, "Linker": 1, "Consonant": 2, "Extend": 3}


def grapheme_table(d):
    v = {}
    for name, ranges in property_ranges(d, "GraphemeBreakProperty.txt").items():
        for lo, hi in ranges:
            for c in range(lo, hi + 1):
                v[c] = GCB.index(name)
    for lo, hi in property_ranges(d, "emoji-data.txt", {"Extended_Pictographic"}).get("Extended_Pictographic", []):
        for c in range(lo, hi + 1):
            v[c] = v.get(c, 0) | 16
    for f in lines(d, "DerivedCoreProperties.txt"):
        if f[1] == "InCB":
            lo, hi = code_range(f[0])
            for c in range(lo, hi + 1):
                v[c] = v.get(c, 0) | (INCB[f[2]] << 5)
    return pack_partition(partition(v))


def normalization_tables(d, ud):
    ccc = {cp: int(f[3]) for cp, f in ud.items() if int(f[3]) != 0}
    raw = {}
    for cp, f in ud.items():
        if f[5] and not f[5].startswith("<"):
            raw[cp] = [int(x, 16) for x in f[5].split()]

    def full(cp):
        if cp not in raw:
            return [cp]
        out = []
        for x in raw[cp]:
            out += full(x)
        return out

    decomp = {cp: full(cp) for cp in raw}
    exclusions = set()
    for lo, hi in property_ranges(d, "DerivedNormalizationProps.txt", {"Full_Composition_Exclusion"}).get("Full_Composition_Exclusion", []):
        exclusions.update(range(lo, hi + 1))
    comp = []
    for cp, m in raw.items():
        if len(m) == 2 and cp not in exclusions:
            comp.append((m[0], m[1], cp))
    comp.sort()
    flat = [len(comp)]
    last = 0
    for a, b, c in comp:
        flat += [a - last, b, c]
        last = a
    return pack_partition(partition(ccc)), pack_mapping(decomp), pack(flat)


def case_tables(d, ud):
    lower = {}
    upper = {}
    title = {}
    for cp, f in ud.items():
        if f[12]:
            upper[cp] = [int(f[12], 16)]
        if f[13]:
            lower[cp] = [int(f[13], 16)]
        if f[14]:
            title[cp] = [int(f[14], 16)]
    for f in lines(d, "SpecialCasing.txt"):
        if len(f) > 4 and f[4]:
            continue  # conditional (language or context): not applied
        cp = int(f[0], 16)
        for table, field in ((lower, 1), (title, 2), (upper, 3)):
            m = [int(x, 16) for x in f[field].split()]
            if m != [cp]:
                table[cp] = m
            else:
                table.pop(cp, None)
    return pack_mapping(lower), pack_mapping(upper), pack_mapping(title)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--fetch":
        fetch(sys.argv[2])
        return
    d = sys.argv[1]
    ud = unicode_data(d)
    grapheme = grapheme_table(d)
    ccc, decomp, comp = normalization_tables(d, ud)
    lower, upper, title = case_tables(d, ud)
    out = sys.stdout
    out.write("// Generated by tools/gen-unicode.py from the Unicode Character Database\n")
    out.write("// %s (https://www.unicode.org/license.txt). Do not edit.\n\n" % VERSION)
    for name, data, doc in (
        ("_ucdGrapheme", grapheme, "Grapheme_Cluster_Break (low 4 bits, in the order of _GraphemeBreak), "
                                   "Extended_Pictographic (16), InCB (bits 5-6: Linker 1, Consonant 2, Extend 3), "
                                   "as (start, value) runs"),
        ("_ucdCombiningClass", ccc, "Canonical_Combining_Class, as (start, value) runs"),
        ("_ucdDecomposition", decomp, "full canonical decompositions: key, count, scalars"),
        ("_ucdComposition", comp, "primary composites: first, second, composite (sorted)"),
        ("_ucdLowercase", lower, "full lowercase mappings (unconditional)"),
        ("_ucdUppercase", upper, "full uppercase mappings (unconditional)"),
        ("_ucdTitlecase", title, "full titlecase mappings (unconditional)"),
    ):
        out.write("/// %s.\n" % doc)
        out.write("internal var %s: StaticString {\n  return \"\"\"\n%s\n\"\"\"\n}\n\n" % (name, data))


if __name__ == "__main__":
    main()
