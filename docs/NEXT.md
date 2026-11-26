# Where to pick up

Rewritten on 2026-11-25 during the Swift push (PRs #15-#36). Read this first
when resuming; `docs/ROADMAP.md` has the long view and `docs/LOG.md` the
history, one entry per PR.

## State in one paragraph (2026-11-26)

Two sessions split the work (ownership is in docs/LOG.md entries and PR
titles): one owns the standard library, Foundation (ObjC and Swift
overlay), the Swift/ObjC runtimes and loader, `_Concurrency`,
Synchronization, os, AppKit and SwiftUI; the other owns CoreGraphics,
CoreText, the display server (`src/frameworks/display`, browser canvas),
Network, CryptoKit, Dispatch's Swift overlay, Carbon, SystemConfiguration,
UserNotifications, QuartzCore/Metal and the smaller frameworks. The target
app window launches through Foundation, concurrency, AppKit (NSWorkspace,
appearance) and stops at the first **SwiftUI** metadata
(`KeyEquivalent`): 1,668 of its 2,526 missing imports are SwiftUI. AppKit
windows already draw through CoreGraphics into the browser and receive
mouse/keyboard events (#83).

## Next: SwiftUI to Apple's shape

The app's own View/ViewModifier/Shape/Layout/Commands/ToolbarContent
conformances reference SwiftUI's *default implementations* of the
view-graph requirements by symbol, e.g.
`(extension in SwiftUI):View._makeView(view: _GraphValue<A>, inputs:
_ViewInputs) -> _ViewOutputs`. So:

1. Give `View`, `ViewModifier`, `Shape`, `ShapeStyle`, `Animatable`,
   `Layout`, `Scene`, `App`, `Commands`, `ToolbarContent`,
   `NSViewRepresentable`, `NSViewControllerRepresentable`, `Gesture`...
   Apple's exact requirement lists (names, labels, order, associated
   types) and default implementations in extensions with the same
   signatures (the missing list in `build/mrun --check` shows each one).
2. `_GraphValue`, `_ViewInputs`, `_ViewOutputs`, `_ViewListInputs`, ... are
   ours (resilient): make `_makeView` build our own retained render tree
   (a node per view: layout + draw into a CGContext), with `body`
   evaluated by the default implementation. `NSHostingView` owns the tree,
   lays it out and draws it through AppKit (AppKitDrawing.m).
3. Then the leaf types (Text via CoreText from the other session, Image,
   Color, shapes, stacks, frames/padding, Button...) and the modifiers,
   each returning `some View` with Apple's signature so the opaque type
   descriptors the app references exist.

## How to build, test and check

```
make -j                                  # mrun, Foundation, libswiftCore, overlays
make check                               # every Mach-O test: C, ObjC, Foundation, Swift
make SWIFT_FLAGS=-Onone BUILD=build-onone check   # Swift tests again at -Onone
APP_DMG=/path/App.dmg tests/e2e/target-app.sh   # container end-to-end check (needs Docker)
build/mrun --check "<app>/Contents/MacOS/App" | grep -c '^MISSING'   # the yardstick
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
  image, run `tests/e2e/target-app.sh` and `docker build --target test .` where
  Docker exists.
- Nothing from App.dmg goes into the repository. Declarations are matched
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

After those, in rough order of what the Mac app needs:

1. **Foundation's Swift surface** (642 imports): the Swift overlay over our
   Objective-C Foundation (`Data`, `URL`, `Date`, `UUID`, bridging of
   String/Array/Dictionary to NSString/NSArray/NSDictionary, `JSONDecoder`,
   Codable in the stdlib first).
2. **SwiftUI** (1,746 imports) together with **AppKit** (209) and the
   drawing stack (CoreGraphics, CoreText, QuartzCore, Metal): the Mac app
   window. A decision is needed on how windows appear (X11/Wayland or a
   browser canvas).
3. Smaller overlays the Mac app binds to: Observation, Combine, Network,
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
