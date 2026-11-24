# Disk image extraction

`tools/dmgx` is an executable Python 3 script that reads images directly with the standard library. Run it on Linux with one of these commands.

```text
tools/dmgx info IMAGE
tools/dmgx list IMAGE [--no-metadata]
tools/dmgx extract IMAGE OUTDIR [--no-metadata]
tools/dmgx find-apps IMAGE
```

`info` prints the container, UDIF chunk types and counts, partition scheme, partition bounds, and selected volume. `list` and `find-apps` report paths relative to the volume root. `find-apps` reads binary or XML `Contents/Info.plist` files and prints the path, `CFBundleExecutable`, and `CFBundleIdentifier` as tab-separated fields. Shallower bundles appear first. Missing string values produce empty fields. Backslashes, tabs, newlines, and carriage returns in fields are escaped.

## Supported formats

- UDIF images with a `koly` trailer and a property-list `blkx` map. The reader handles raw, zero-fill, ignore, ADC, zlib, bzip2, LZFSE, and LZMA/XZ chunks, along with comment and terminator records. The Python LZFSE decoder handles `bvx-`, `bvx1`, `bvx2`, `bvxn`, and `bvx$`. [Apple's LZFSE reference implementation](https://github.com/lzfse/lzfse)
- Bare volumes, GPT disks with 512-byte or 4 KiB sectors, and Apple Partition Map disks. The extractor selects the first HFS+ or HFSX partition and can read HFS+ embedded in an HFS wrapper.
- HFS+ and HFSX catalog leaf chains, data and resource fork extent chains, and attributes B-trees. Transparent compression supports decmpfs types 3 and 4 (zlib), 7 and 8 (LZVN), and 11 and 12 (LZFSE), including the resource-fork forms. [Apple's HFS Plus volume format](https://developer.apple.com/library/archive/technotes/tn/tn1150.html), [decmpfs resource-fork layouts](https://github.com/sgan81/apfs-fuse/blob/master/ApfsLib/Decmpfs.cpp)

UDIF access uses an indexed chunk map and caches up to eight decompressed chunks totaling at most 32 MiB. Larger compressed chunks are decoded to an anonymous temporary file with bounded output buffers. Raw and zero-filled ranges are read in place. Catalog and extent metadata are held in memory, and regular data forks and resource-fork compression blocks are copied incrementally.

Extraction restores file and directory permissions, content modification times, symlink targets, and regular-file hard links. HFS+ private directories are skipped, with indirect `iNode` files used to resolve hard links. Other entries are kept by default. `--no-metadata` skips `.DS_Store`, AppleDouble `._*` entries, `__MACOSX`, and Spotlight, trash, and related housekeeping directories. An on-disk slash in an HFS name is rendered as a POSIX colon. Destination entries are created relative to directory file descriptors, with symlink traversal and overwrites refused. Symlink targets are stored verbatim, including absolute and parent-relative targets.

## Verification

Run `python3 -m unittest discover -s tests/dmgx` for synthetic coverage. Set `DMGX_TEST_IMAGE` to exercise all four commands on a real image. The synthetic tests cover ADC and all LZFSE stream block types, UDIF chunk reads and temporary-file spooling, both partition maps, HFSX extraction and fork fragmentation, all six supported decmpfs types, hard links, and path traversal checks.

A proprietary GPT/HFS+ UDIF image with LZMA/XZ chunks was extracted outside the repository and compared with an independent extraction.

| Item | Compared | Mismatches |
| --- | ---: | ---: |
| Regular-file SHA-256 | 125 | 0 |
| Regular-file executable bits | 125 | 0 |
| Symlink targets | 7 | 1 |
| Shared directory permissions (executable bits) | 89 | 0 |

Regular-file and symlink paths matched in both trees. The one differing symlink target matched the bytes stored in the image. The reference also contained two empty HFS+ private directories, which `dmgx` skipped.

## Known gaps

- An APFS-only image exits nonzero with `APFS images are not supported yet`.
- Encrypted or segmented UDIF, legacy resource-fork-only UDIF maps, other partition schemes, and plain HFS are unsupported. UDIF and GPT checksums are currently unchecked. The reader uses the filesystem state on disk without journal replay.
- HFS+ directory hard links, BSD special files, and an extents overflow tree that needs its own overflow extents return an error. Extraction restores ordinary permission bits. Ownership, special permission bits, ACLs, Finder metadata, ordinary resource forks, and general extended attributes are outside the extraction scope.
- A destination collision or invalid image can leave entries that were extracted earlier in the run.
