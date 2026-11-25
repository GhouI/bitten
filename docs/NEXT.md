# Where to pick up

Written at the end of the session of 2026-11-24, after PR #13. Read this
first when resuming; `docs/ROADMAP.md` has the long view and `docs/LOG.md`
the history.

## State in one paragraph

`mrun` runs unmodified x86-64 macOS programs written in C, Go and
Objective-C (with the parts of Foundation listed in the README). The Rex
server and CLI from Rex.dmg run fully in an unprivileged container, and a
Rex terminal is usable through `examples/rex`. The Rex window
(`Contents/MacOS/Rex`) now loads, registers its Objective-C classes, runs
`+load`, enters its own initialisers and stops at its first call into the
**Swift runtime**: `swift_getSingletonMetadata`. 5,307 of its 5,688 imports
are still unimplemented.

## How to build, test and check

```
make -j                       # build/mrun + build/root (Foundation); needs gcc, clang, lld
make check                    # 23 Mach-O test programs (Go tests need a Go toolchain)
docker build --target test .  # the same, in a clean container, with Go
docker build -t bitten .      # runtime image
REX_DMG=/path/Rex.dmg tests/e2e/rex.sh   # container end-to-end check with a real Rex.dmg
build/mrun --check "<app>/Contents/MacOS/Rex" | grep -c '^MISSING'   # the yardstick
```

Rules that have earned their place:

- Branch, PR, merge for every change; update `docs/LOG.md` in the PR.
- Before merging anything that touches the loader, path handling or the
  image, run `tests/e2e/rex.sh` and `docker build --target test .`. The unit
  suite alone once missed a regression that broke Rex in the container.
- Nothing from Rex.dmg goes into the repository.

## The next layer: Swift

Rex is a Swift program. What its window binary still needs, by library and
kind (from `mrun --check`, classified by mangling suffix):

| Library | Missing | Largest kinds |
| --- | ---: | --- |
| SwiftUI | 1,743 | 776 functions/accessors, 275 type descriptors, 163 metadata accessors, 140 conformance descriptors, 104 opaque type descriptors |
| Swift runtime, standard library and overlays (`libswift*`) | 1,723 | 690 functions/accessors, 149 runtime functions with a C ABI, 143 method descriptors, 116 conformance descriptors, 110 type descriptors, 108 dispatch thunks, 90 metadata accessors, 61 witness tables |
| Foundation (mostly its Swift surface) | 642 | 361 functions/accessors, 62 metadata accessors, 61 conformance descriptors, 36 Objective-C classes |
| Network | 215 | 98 functions |
| AppKit | 206 | 109 C functions/data, 80 Objective-C classes |
| AppIntents | 173 | |
| CryptoKit | 146 | |
| CoreGraphics | 141 | 120 C functions/data |

Of the 1,318 symbols from `libswiftCore` itself, 124 are `swift_*` runtime
functions with an ordinary C calling convention. Those are the place to
start, because every other Swift symbol depends on them.

### Step 1: Swift runtime, object model (C, inside `mrun`)

Status (PRs #16-#18): items 1-3 below and `swift_once`/exclusivity are done
in `src/frameworks/swift/heap.c` and `objc.c`, tested with real swiftc
output (`tests/swift/heap`, `weak`, `objc`). Left from this step:
`swift_arrayInitWithCopy` and friends, `swift_getObjectType` (with the
metadata work), and `@objc` methods on Swift classes (needs Foundation's
`NSObject` subclassing and is untested).

New directory `src/swift/`. Suggested order, each with C tests that build
the structures the Swift compiler would emit:

1. **Heap objects**: `swift_allocObject`, `swift_retain/release` (and `_n`),
   `swift_deallocObject`, `swift_deallocClassInstance`, `swift_slowAlloc`,
   `swift_slowDealloc`, `swift_initStackObject`, `swift_initStaticObject`,
   `swift_setDeallocating`, `swift_isUniquelyReferenced*`, boxes
   (`swift_allocBox`, `swift_projectBox`, `swift_deallocBox`,
   `swift_makeBoxUnique`). A Swift object is `{metadata, refcount word}`;
   the refcount encoding is ours to define because compiled code never
   inlines it on this platform.
2. **Objective-C interop**: the root class `SwiftObject`
   (`_OBJC_CLASS_$__TtCs12_SwiftObject`) whose `-retain`/`-release` use the
   Swift count; `swift_unknownObject*` and `swift_bridgeObject*` choosing
   between the two worlds by class; `swift_getObjCClassMetadata`,
   `swift_getObjCClassFromMetadata`, `swift_dynamicCastObjCClass*`.
3. **Weak and unowned references**: `swift_weak*`, `swift_unknownObjectWeak*`,
   `swift_unknownObjectUnowned*` (the Objective-C weak table in
   `src/frameworks/objc/arc.c` can serve both).
4. **`swift_once`**, exclusivity (`swift_beginAccess`/`swift_endAccess`),
   `swift_arrayInitWithCopy`/`TakeFrontToBack`/`TakeBackToFront`/`Destroy`
   (need value witnesses, see step 2).

### Step 2: metadata

The compiler emits type metadata and reads its fields directly, so layouts
must match the documented Swift ABI exactly (type metadata, value witness
tables, nominal type descriptors with relative pointers).

1. Metadata kinds and value witness tables; `swift_getSingletonMetadata`
   (the call Rex stops at), `swift_checkMetadataState`,
   `swift_initClassMetadata2`, `swift_updateClassMetadata2` (a Swift class
   is also an Objective-C class: it must be registered with our runtime).
2. `swift_initStructMetadata`, `swift_initEnumMetadataSinglePayload`,
   `swift_initEnumMetadataMultiPayload` and the enum tag helpers: the layout
   algorithm.
3. `swift_getGenericMetadata`, `swift_allocateGenericValueMetadata`,
   `swift_allocateGenericClassMetadata`: instantiation cache keyed by the
   generic arguments.
4. Tuple, function, metatype and existential metadata.
5. `swift_getTypeByMangledNameInContext*`: a demangler for the symbolic
   mangling used in metadata, producing types.
6. `swift_conformsToProtocol*` and `swift_getWitnessTable`: scan each
   image's `__swift5_proto` section (add a loader hook like the Objective-C
   one), cache results.
7. `swift_dynamicCast*`, errors (`swift_allocError`, `swift_errorRetain`,
   `swift_willThrow`), key paths last.

### Step 3: the standard library

About 1,200 symbols for Rex: metadata, descriptors and witness tables for
`Int`, `String`, `Array`, `Dictionary`, `Optional` and friends, plus their
functions. The layouts of the `@frozen` types are ABI (programs inline
against them), so `String`'s 16-byte representation, array buffers and
dictionary storage must be reproduced, not redesigned. Functions use the
Swift calling convention (self in `r13`, error in `r12`): write them in C
compiled by clang with `__attribute__((swiftcall))`, which means
`src/swift/` is built with clang rather than gcc.

Open problem to decide early: **there is no Swift compiler in the tool
chain**, so there are no small Swift test programs; tests are C programs
imitating compiler output, and Rex itself. A Swift toolchain could produce
real tests the way clang and Go do for C and Go, but compiling for macOS
needs the macOS standard-library interface files, which come from Apple's
toolchain package. That is a call for the project owner.

### After that

SwiftUI, AppKit, CoreGraphics/CoreText, Metal: see `docs/ROADMAP.md`. None
of them can be exercised by Rex until its Swift initialisers run.

## Smaller items that are ready to be picked up

Useful to other software regardless of Rex, each a self-contained PR:

- **Run loops**: `CFRunLoop`, `NSRunLoop`, `NSTimer`, and draining the main
  dispatch queue from it (`src/frameworks/dispatch/dx_dispatch.h` already
  exposes the eventfd and drain function).
- **`NSTask`, `NSPipe`, `NSFileHandle`** on `posix_spawn`.
- **Property lists** (XML and binary), then `NSBundle` and
  `NSUserDefaults`.
- **Key-value coding and observing**, `NSInvocation` and full message
  forwarding, `NSPredicate`/`NSSortDescriptor`.
- **`NSDateFormatter`, `NSCalendar`, `NSLocale`, `NSScanner`,
  `NSRegularExpression`.**
- **Exceptions**: an unwinder for Mach-O `__unwind_info`/`__eh_frame`, then
  `objc_exception_throw` and C++ `throw`. Until then every raise terminates.
- **C++ runtime** (`libc++`, `libc++abi`): nothing exists yet; C++ programs
  do not run.
- **X.509 verification** behind `SecTrustEvaluateWithError`: outbound HTTPS
  from macOS programs (including `rex`) is refused today.
- **Deflate with dynamic Huffman blocks**; DES/3DES/RC4; LZFSE in
  libcompression.
- **APFS disk images** in `tools/dmgx`.
- **`dispatch_io`**, QoS-aware scheduling.
- **CI**: copy `ci/github-actions.yml` to `.github/workflows/ci.yml` with a
  token that has the `workflow` scope.

## Known weak spots

- Character sets and case mapping are approximate outside Latin-1.
- AES is table-based (not constant-time).
- `CFString` stores UTF-8 and computes UTF-16 indexes by scanning, so
  `characterAtIndex:` in a loop over a long non-ASCII string is quadratic.
- Reference counts for Objective-C objects live in side tables behind
  mutexes: correct, not fast.
- The Rex terminal viewer in `examples/rex` is this project's page, fixed at
  80x24, with a cursor drawn at the end of the text.
