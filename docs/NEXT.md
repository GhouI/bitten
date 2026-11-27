# Where to pick up

The target Mac application runs end to end on Linux. Its window shows the
workspace with live terminal panes (Metal, drawn into the window), tabs,
splits, pane zoom, the command palette, menus and context menus, Settings
with every page, search and sub-pages, and window resize, zoom and
minimise in the browser display. Typing, shortcuts (menu, view and SwiftUI
button shortcuts), copy and paste, and dark mode work. Opening and closing
windows no longer leaks.

## What stands in the way

1. **Speed.** With a viewer connected the target app idles at about 10%
   CPU, mostly the terminal's Metal fragment path (`cell_bg_fragment`).
   Launch reaches an interactive terminal in about 4.5 s (1.2 s before
   `main`). Full window redraws still take a few hundred milliseconds,
   almost all CoreGraphics blending (`cg_blend_pixel`, `mask_row`,
   `scan`), so resizes, pane zoom and page switches lag. The remaining
   full redraws come from the root SwiftUI host after rebuilds; it
   doesn't track which regions changed. `BITTEN_DISPLAY_DEBUG` logs who
   asked for each one. Wait 8 s or more before judging that an animated
   change didn't happen.
2. **Paste timing.** A paste once arrived in bash as literal `[200~…~`.
   That is consistent with the escape byte reaching readline more than its
   key-sequence timeout before the rest. It pastes correctly now that
   frames are faster; watch for it under load.

Settled since the last update: Return in the target app's text fields is
handled by the app's own delegate. The display page refocuses the
frontmost window when the focused one closes (#232), and AppKit sends keys
for a closed window to the key window anyway.

## Finding problems

- `BITTEN_EVENT_DEBUG` routes, `BITTEN_HIT_DEBUG` SwiftUI hits,
  `BITTEN_VIEW_TREE` / `BITTEN_SWIFTUI_TREE` trees, `BITTEN_DRAW_PROFILE`
  paint time, `BITTEN_METHODS=Class` a class's methods and ivars.
- `BITTEN_ALLOC_STATS=N` live instances per class every N seconds (leaks),
  `BITTEN_MONITOR_DEBUG` event monitors, `BITTEN_WINDOW_DEBUG` window
  frames, creation and freeing, `BITTEN_SYMBOL_DEBUG` symbol images.
- `BITTEN_CRASH_REPORT=stderr` gives a backtrace on a fatal error.
- Drive the browser display with Playwright (one connection per run).
  Before testing, check no stale `mrun` holds the display port.

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
