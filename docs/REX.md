# Rex: what it needs and how far bitten gets

Target: `Rex.dmg`, Rex Beta 0.1.0 build 1996. A UDIF image, GPT, one HFS+
volume, LZMA-compressed chunks, 125 files. Both programs in the bundle are
universal x86-64/arm64 Mach-O files built with the macOS 27 SDK for macOS 15.0
or newer. bitten uses the x86-64 slices.

Nothing from the disk image is in this repository. The numbers below come
from running `mrun --check` and `llvm-nm -u` on a local copy.

## The two programs

| | `rex` (server and CLI) | `Rex` (the window) |
| --- | --- | --- |
| Path in the bundle | `Contents/Helpers/Rex Server.rex/Contents/MacOS/rex` | `Contents/MacOS/Rex` |
| Size (universal) | 91 MB | 73 MB |
| Language | Go 1.26 with cgo, SQLite compiled in | Swift |
| Libraries linked | libSystem, CoreFoundation, Security, libresolv, libobjc | 63, including AppKit, SwiftUI, Metal, QuartzCore, Network, CryptoKit and 31 Swift runtime libraries |
| Imported symbols | 291 | 5,688 |
| Implemented by bitten | 291 | 311 (most of them libSystem, the rest optional weak imports) |
| Objective-C classes referenced | 0 | 172 |
| Fixup format | classic dyld info | chained fixups |
| Status | **runs** | **loads and binds, cannot start** |

## `rex`: runs

What was verified with the unmodified binary, in the container:

| Feature | Result |
| --- | --- |
| `rex version`, `rex --help` | works |
| `rex server run` / `start` / `status` / `stop` | works; the server re-executes itself in the background through the loader |
| Client to server over the unix socket | works, including peer-credential checks |
| SQLite state database | works |
| `rex new` (create a session with a terminal) | works; the shell is a Linux `zsh` started through `login -fpl` on a pty |
| `rex send`, `rex send-key` | works |
| `rex capture` in text, HTML and VT formats | works, about 25 ms per call |
| `rex ls`, `rex api list`, `rex whoami` | works |

Getting there took, in order: the Darwin-style `argv/envp/apple` vector, the
libSystem core, sockets and kqueue for Go's network poller, real
`malloc_zone_t` tables for SQLite, `LOCAL_PEERCRED`, raw Darwin `ioctl`
system calls for the pty (served through syscall user dispatch), libproc and
`sysctl` process queries, CoreFoundation basics, and a macOS-style
`/usr/bin/login` in the container.

Known gaps for `rex`:

- **TLS to the outside world.** Go on macOS verifies certificates through
  Security.framework. bitten has no X.509 chain verification, so
  `SecTrustEvaluateWithError` fails and outbound HTTPS from `rex` (updates,
  login server, Tailscale) will be refused. Setting `BITTEN_INSECURE_TRUST=1`
  accepts every certificate and is for experiments only.
- **Built-in Tailscale** is untested and needs route sockets, which are not
  implemented.
- **`net.Interfaces()`** needs `AF_ROUTE` or `sysctl` route dumps: not
  implemented.
- Not every subcommand has been exercised: splits, floating layers, port
  forwarding and Lua actions are untested.

### Seeing the terminal

`rex` has no interactive attach mode of its own; the window is the GUI app.
`examples/rex/terminal.py` fills the gap with the CLI's own commands: it
polls `rex capture --format=html` (or `vt` for `--tty`) and sends keys with
`rex send`. It is a viewer written for this project, about 220 lines of
standard-library Python, and it is not Rex's interface: no tabs, splits,
palettes or settings, a fixed 80x24 terminal, and a cursor drawn at the end
of the text rather than at its true position.

## `Rex`: does not run

`mrun --check` maps the 73 MB image, loads the two bundled Mach-O libraries
(Sparkle and `libswiftCompatibilitySpan`), applies chained fixups, and
reports what it could not bind:

| Library | Imports | Implemented or optional |
| --- | ---: | ---: |
| SwiftUI | 1,788 | 45 |
| Swift runtime and standard library (31 `libswift*` libraries) | 1,778 | 55 |
| Foundation | 672 | 3 |
| Network | 215 | 0 |
| libSystem | 212 | 181 |
| AppKit | 211 | 5 |
| AppIntents | 182 | 9 |
| CryptoKit | 146 | 0 |
| CoreGraphics | 141 | 0 |
| CoreText | 74 | 0 |
| QuartzCore | 49 | 1 |
| CoreFoundation | 36 | 6 |
| Combine | 30 | 0 |
| libobjc | 25 | 1 |
| Charts | 24 | 0 |
| 18 others (Carbon, IOKit, Metal, WebKit, ...) | 105 | 7 |
| **Total** | **5,688** | **311** |

"Optional" means a weak import that the program is prepared to find
missing. Symbol counts understate the work: each of the 172 Objective-C
classes brings its whole method set through `objc_msgSend`, and each SwiftUI
symbol is a generic entry point into a large closed-source framework.

The program cannot begin to start: its first initialisers call into the
Swift runtime.

### What a running window would require

In dependency order, with a frank size estimate for each:

1. **Objective-C runtime** (`libobjc`): classes, selectors, message
   dispatch, categories, protocols, associated objects, autorelease pools,
   ARC entry points, blocks. Well documented and self-contained. Weeks.
2. **Swift runtime and standard library**: metadata, generics, witness
   tables, reference counting, concurrency, `String`, collections. The
   standard library is tens of thousands of functions written in Swift
   itself. It cannot be rewritten by hand in any reasonable time; the only
   practical source is Apple's open-source Swift, built for this layer.
   That is third-party code, which this project has so far chosen to avoid,
   so it is a decision for the owner.
3. **Foundation**: 672 symbols here, plus the Objective-C classes behind
   them (`NSString`, `NSData`, `NSURL`, `NSFileManager`, run loops,
   notifications, `NSUserDefaults`, key-value coding, JSON, formatters).
   Many person-months.
4. **CoreGraphics, CoreText, QuartzCore**: 2D drawing, text shaping and
   layout, layer compositing. Many person-months each done from nothing.
5. **AppKit**: windows, views, events, menus, responder chain, drawn to X11
   or Wayland. Person-years.
6. **SwiftUI**: 1,788 entry points into a closed framework whose behaviour
   is defined by its implementation: the attribute graph, layout, state
   management, view modifiers, the AppKit bridge. No complete independent
   implementation exists anywhere. Person-years, with no upper bound known.
7. **Metal**: the terminal grid is drawn with Metal shaders
   (`default.metallib` in the bundle); needs a Metal implementation over
   Vulkan or OpenGL, including a shader translator.
8. Smaller frameworks: Network (215), CryptoKit (146), AppIntents (182),
   Combine, Charts, Sparkle's needs.

Steps 1 and the C parts of 3 and 4 are tractable from scratch. Steps 2 and 6
are not, on any timescale this project can promise, without importing
existing code (open-source Swift for 2; nothing suitable exists for 6).

### The realistic routes to "the Rex window"

- **Keep building the layer.** Objective-C runtime next, then decide about
  the Swift runtime. Even with both, SwiftUI stands in the way.
- **A native front end over the real server.** The Rex server runs here and
  speaks a documented control API (`rex api list` shows it) plus a terminal
  data stream. A Linux window that talks to that server gives the full Rex
  feature set of the engine with a different shell around it. That is a
  different program from `Rex.app`, so it would be presented as such.

Neither is a quiet substitute for the original GUI, and this document will
say plainly which one any future milestone is.
