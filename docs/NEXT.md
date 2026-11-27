# Where to pick up

The target app's window and server both reach the end of `mrun --check`
with no missing required imports. The window has 80 unbound weak imports.
It draws onboarding, the workspace and settings through SwiftUI and AppKit.
The next milestone is a shell prompt you can see and type into on the
first launch with an empty home directory.

## What stands in the way

1. **Show the frame Metal already drew.** On the host, the software device
   produces a terminal frame with the prompt, input, output and cursor.
   `CAMetalLayer` puts that image in its `contents` and marks the layer
   dirty. In `frameworks/AppKit/AppKitDrawing.m`, a view draws its
   background, calls `drawRect:`, then draws sublayers and its border; it
   skips its own backing layer's image. Draw the contents and request a
   window redraw on present. Check the pixels in the *window*, not just
   in the drawable.
2. **Make shader compilation work in Docker.** The test image builds
   `mrun` in `/out` but leaves `tools/metal-compile.py` in `/src/tools`,
   outside the compiler search path in `src/frameworks/metal/metal.c`.
   The runtime image ships neither the helper and its C runtime nor clang.
   Check `tests/metal/render.m` in the test stage and a cold shader cache
   in the final image; a successful host render doesn't test either.
3. **Get through onboarding with an empty home.** The update check sends
   `+dataWithBytesNoCopy:length:freeWhenDone:`, which Objective-C
   `NSData` lacks. Skipping onboarding takes a separate path: the Swift
   runtime cannot cast an unlabeled tuple to its labeled counterpart.
   Retest both paths with fresh preferences; a relaunch can skip the
   failing step because the app has already recorded it.
4. **Find why the CLI helper exits with status 1 on first launch.** The
   server runs and subsequent CLI calls work. Test the helper started
   by the window on a fresh home and check that the first session opens.
   A successful standalone CLI command is not the same test.

Once a block attaches, keyboard input reaches the shell even while the
terminal pane is white. Measure first-launch and block-attach delays
separately from drawing; keys sent before attachment can be lost.

## How to build, test and check

```
make -j                                  # mrun, frameworks, standard library and overlays
make check                               # Mach-O tests
make SWIFT_FLAGS=-Onone BUILD=build-onone check
build/mrun --check "<app>/Contents/MacOS/<executable>"
docker build --target test .
docker build -t bitten .
APP_DMG=/path/App.dmg APPCLI=appcli tests/e2e/target-app.sh
```

Substitute the actual CLI name for `appcli`. The end-to-end check drives
the bundled server and CLI through bitten's viewer, not the app's own GUI.
For the latter, launch the window with a separate `HOME`, `XDG_RUNTIME_DIR`
and `TMPDIR`; use a separate `BITTEN_DISPLAY_PORT` for the browser page.

Build the full tree with gcc, make, clang, `ld64.lld` and the Linux Swift
toolchain (on `PATH` or in `/opt/swift/usr/bin`). Go tests also need Go.
`tests/swift/` exercises the runtime without a standard library;
`tests/swiftlib/` compiles against bitten's `Swift.swiftmodule`.
A companion `NAME.lib.swift` builds as a separate resilient module and
`NAME.flags` supplies test-specific compiler flags.

- Use a branch and PR for each small step; add an entry to `docs/LOG.md`.
  Leave the merge to the maintainer.
- Run `make check` and the `-Onone` build for Swift work. Unoptimised
  code exercises runtime paths the optimiser can remove.
- For loader, path or image changes, run the container end-to-end check
  and the Docker test stage.
- Keep app binaries, extracted resources and captures outside the repo.
  See [DECISIONS.md](DECISIONS.md) for how interfaces are implemented.

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
