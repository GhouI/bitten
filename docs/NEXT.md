# Where to pick up

Rewritten on 2026-11-25 during the Swift push (PRs #15-#36). Read this first
when resuming; `docs/ROADMAP.md` has the long view and `docs/LOG.md` the
history, one entry per PR.

## State in one paragraph

`mrun` runs unmodified x86-64 macOS programs written in C, Go, Objective-C
and now **Swift**: the Swift runtime (C, `src/frameworks/swift/`) covers heap
objects, reference counting, weak/unowned, type metadata for every kind
(structs, enums incl. multi-payload, classes incl. generic and resilient
ones registered with our Objective-C runtime, tuples, functions,
existentials), generic instantiation, mangled-name lookup, conformances and
witness tables, dynamic casts and errors. The **standard library** is our
own Swift source (`stdlib/`) compiled as module `Swift` into
`libswiftCore.dylib`; it has the core types, the numeric and collection
protocol hierarchies, ranges, pointers, floats, hashing, StaticString and
failure reports, while Array, String, Dictionary/Set are in progress.
**Swift overlays** (`overlays/NAME/`) are built against our own SDK
(`build/MacOSX.sdk`). The Rex window binary's unimplemented imports went
from 5,484 to about 4,900; it gets through its first struct's metadata and
stops at the first SwiftUI accessor, `NSApplicationDelegateAdaptor`.

## How to build, test and check

```
make -j                                  # mrun, Foundation, libswiftCore, overlays
make check                               # every Mach-O test: C, ObjC, Foundation, Swift
make SWIFT_FLAGS=-Onone BUILD=build-onone check   # Swift tests again at -Onone
REX_DMG=/path/Rex.dmg tests/e2e/rex.sh   # container end-to-end check (needs Docker)
build/mrun --check "<app>/Contents/MacOS/Rex" | grep -c '^MISSING'   # the yardstick
```

Tools needed: gcc, clang + `ld64.lld` (LLVM), and for the Swift parts the
open-source Swift toolchain for Linux (swift.org; found on `PATH` or in
`/opt/swift/usr/bin`). The Swift parts are skipped without it.

Three kinds of Swift tests:

- `tests/swift/NAME.swift` + `NAME.c`: `-parse-stdlib` code (Builtin types
  only), testing the runtime with no standard library at all.
- `tests/swiftlib/NAME.swift` + `NAME.c`: ordinary Swift compiled against
  our `Swift.swiftmodule`; the C driver calls `@_silgen_name`/`@_cdecl`
  entry points.
- A test with `NAME.lib.swift` gets that file built as a separate
  resilient module (singleton and resilient metadata paths); `NAME.flags`
  adds compiler flags.

Rules that have earned their place:

- Branch, PR, merge for every small step; update `docs/LOG.md` in the PR.
  Merging right away is the owner's standing instruction.
- Run `make check` **and** the `-Onone` build before merging Swift work:
  -Onone goes through the runtime far more (it found the base-protocol
  witness bug and the page-zero dylib placement).
- Before merging anything that touches the loader, path handling or the
  image, run `tests/e2e/rex.sh` and `docker build --target test .` where
  Docker exists.
- Nothing from Rex.dmg goes into the repository. Declarations are matched
  to Apple's (that is what makes symbol names match); implementations are
  written here. See `docs/DECISIONS.md`.

## How the standard library is made

Declaring the same public API as Apple's stdlib in a module named `Swift`
makes the compiler emit the same symbol names, so programs bind to it.
Points that are easy to get wrong:

- `@frozen` types and anything inlinable code touches must keep Apple's
  layout exactly (programs inline against it).
- Requirement order in protocols does not matter (Apple's protocols are
  resilient: programs use dispatch thunks and descriptors), so protocols
  can grow over several PRs.
- Members Apple declares over `~Copyable` generics but with
  `@_preInverseGenerics` keep their old mangling: declare those as plain
  generics (see `stdlib/Pointers.swift`).
- The compiler requires some declarations to exist before it accepts
  certain code: pointer conversions need every pointer type plus five
  `_convert...Argument` functions; C imports and `@_cdecl` need the C type
  aliases; array literals need the uninitialized-array intrinsics. The
  open-source compiler (`lib/AST/ASTContext.cpp`, `lib/Sema/`) says what.
- Find what a program needs with
  `mrun --check <bin> | awk -F'\t' '$1=="MISSING" && $3 ~ /libswiftCore\.dylib/ {print $4}'`
  and `swift-demangle`.

## Work in flight and next

Being worked on (2026-11-25), each by its own agent in its own branch:

- Array, ContiguousArray, ArraySlice, literals, map/filter/sorted.
- String (exact 16-byte representation), views, Character, printing,
  interpolation, number descriptions.
- Dictionary and Set (native hashed storage).
- Swift Concurrency: the async runtime and the `_Concurrency` module.
- SDK headers with Clang modules, and the Darwin, ObjectiveC, Dispatch and
  os overlays.

After those, in rough order of what Rex needs:

1. **Foundation's Swift surface** (642 imports): the Swift overlay over our
   Objective-C Foundation (`Data`, `URL`, `Date`, `UUID`, bridging of
   String/Array/Dictionary to NSString/NSArray/NSDictionary, `JSONDecoder`,
   Codable in the stdlib first).
2. **SwiftUI** (1,746 imports) together with **AppKit** (209) and the
   drawing stack (CoreGraphics, CoreText, QuartzCore, Metal): the Rex
   window. A decision is needed on how windows appear (X11/Wayland or a
   browser canvas).
3. Smaller overlays Rex binds to: Observation, Combine, Network,
   CryptoKit, UniformTypeIdentifiers, RegexBuilder, Synchronization.

## Smaller items that are ready to be picked up

- Run loops (`CFRunLoop`, `NSRunLoop`, timers) draining the main queue.
- `NSTask`/`NSPipe`/`NSFileHandle`; property lists, `NSBundle`,
  `NSUserDefaults`; KVC/KVO, `NSInvocation`.
- Exceptions: an unwinder for `__unwind_info`/`__eh_frame`, then
  `objc_exception_throw` and C++ `throw`; a C++ runtime.
- X.509 trust evaluation (outbound HTTPS from macOS programs).
- APFS disk images in `tools/dmgx`.
- CI: copy `ci/github-actions.yml` to `.github/workflows/ci.yml` with a
  token that has the `workflow` scope, and add the Swift toolchain to it.

## Known weak spots

- Metadata initialisation runs under one global recursive lock.
- Exclusivity checking (`swift_beginAccess`) is a no-op.
- `FixedWidthInteger` lacks Apple's `Stride: FixedWidthInteger`
  requirement (the compiler's requirement machine does not terminate on our
  declarations with it).
- Character sets and case mapping in Foundation are approximate outside
  Latin-1; AES is table-based; ObjC reference counts live in side tables.
