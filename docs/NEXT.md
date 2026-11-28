# Where to pick up

The target Mac application runs end to end on Linux. Its window shows the
workspace with live terminal panes (Metal, drawn into the window), tabs,
splits, pane zoom, the command palette, menus and context menus, Settings
with every page, search and sub-pages, and window resize, zoom and
minimise in the browser display. Typing, shortcuts (menu, view and SwiftUI
button shortcuts), copy and paste, and dark mode work. Opening and closing
windows no longer leaks.

## What stands in the way

1. **Speed.** With a viewer connected the target app idles at about 4%
   CPU, mostly the terminal's Metal fragment path (`cell_bg_fragment`).
   Settings page switches mostly rebuild SwiftUI trees (each rebuild
   builds the whole tree; hidden page hosts now wait until shown).
   `BITTEN_PERF_MAP=1` writes /tmp/perf-<pid>.map with the Mach-O
   images' symbols for naming `perf script` addresses.
   With Settings open it idles at about 5% and sends no frames. Launch
   reaches an interactive terminal in about 4.6 s on a loaded machine.
   Page switches mostly cost CoreGraphics blending now (`cg_blend_pixel`,
   `mask_row`, `scan`, transparency layers). A state change rebuilds
   only its own host. `BITTEN_DISPLAY_DEBUG` logs who asked for each full
   redraw and each presented window's number. Wait 8 s or more before
   judging that an animated change didn't happen.
2. **The Terminal settings typography row.** With the window at the
   app's 740-point default, the first column gets about 40 points: the
   three fixed-size columns and 12-point gaps take the rest. Real
   macOS fonts may give it a little more. The window can now be widened
   to 900, and the column grows with it (up to 180).
3. **Paste timing.** A paste once arrived in bash as literal `[200~…~`.
   That is consistent with the escape byte reaching readline more than its
   key-sequence timeout before the rest. It pastes correctly now that
   frames are faster; watch for it under load.

Settled since the last update: switching to dark mode while the app
runs (enums now print their case, and the app's style caches are keyed by
such descriptions); the lines left after resizing the main
window were partial repaints with fractional dirty rects (now whole
pixels). The window's backdrop fills it (several views in one background
are layered). Settings pages are freed when Settings closes. Sheets are windows (Add Remote Host, the
theme editor). Settings ▸ Themes ▸ New no longer crashes. That crash was
GridRow's stored fields: a frozen type's field list matters, not just
its bytes, because programs read field offsets from metadata. Grids span
and align cells. In a text field in a sheet, the first Escape reverts the
field (the app's delegate does this) and the second closes the sheet, as
on macOS.

## Finding problems

- `BITTEN_EVENT_DEBUG` routes, `BITTEN_HIT_DEBUG` SwiftUI hits,
  `BITTEN_VIEW_TREE` / `BITTEN_SWIFTUI_TREE` trees, `BITTEN_DRAW_PROFILE`
  paint time, `BITTEN_METHODS=Class` a class's methods and ivars.
- `BITTEN_ALLOC_STATS=N` live instances per class every N seconds (leaks),
  `BITTEN_MONITOR_DEBUG` event monitors, `BITTEN_WINDOW_DEBUG` window
  frames, creation and freeing, `BITTEN_SYMBOL_DEBUG` symbol images.
- `BITTEN_CRASH_REPORT=stderr` gives a backtrace on a fatal error.
- Memory: the SIGUSR1 report also gives malloc's bytes in use and held.
  In use growing means something leaks; only held growing is the
  allocator keeping freed memory. Under `LD_PRELOAD=build/redzone.so`
  the report adds live malloc bytes by allocation site, so diff two of
  them. `BITTEN_FIND_REFS` takes object or block addresses (`0x…`,
  comma separated), or `BITTEN_FIND_REFS_FILE` names a file of them read
  at each signal. `BITTEN_IMAGE_DEBUG` logs NSImages rendered to
  bitmaps; `BITTEN_CACHE_DEBUG` logs NSCache lookups with their keys.
- `BITTEN_ALLOC_STATS=N` also prints at once on `kill -USR1 <mrun pid>`:
  take one report, repeat an action a few times, take another, and diff
  them.
- Leaks: `BITTEN_FIND_REFS=Class` then `kill -USR2 <mrun pid>` lists what
  points at each live instance (object class and offset, or the mapping),
  a few levels up (`BITTEN_FIND_REFS_DEPTH`, 3), for the first
  `BITTEN_FIND_REFS_MAX` instances (40); `(weak)` marks `__weak` slots. Under
  `LD_PRELOAD=build/redzone.so` (built with `-fno-omit-frame-pointer`),
  malloc blocks are named by their call sites and freed memory is
  skipped. A cycle shows as holders inside the object's own tree (a
  closure in a node capturing the host). When nothing outside holds an
  object with a retain count above one, `BITTEN_TRACE_RETAINS=Class` with
  the same signal prints the call stacks whose retains and releases don't
  balance. `BITTEN_HEAP_QUARANTINE=3` makes a retain of a freed
  Objective-C object stop and name its class.
- Heap corruption ("corrupted size vs. prev_size" and friends):
  `cc -O1 -g -shared -fPIC -o build/redzone.so tools/redzone.c -ldl`, then
  run with `LD_PRELOAD=build/redzone.so`. It names the overrun block, its
  size and who allocated and freed it (`REDZONE_SCAN=N` checks every live
  block each N frees). Valgrind doesn't get far with the target app.
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
