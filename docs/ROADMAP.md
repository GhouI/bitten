# Roadmap

bitten aims to be a place where macOS software runs inside ordinary Linux
containers, for developers who want "Mac containers" in Docker. Every
library a program needs is built here, from scratch. There is no deadline;
the order below is dictated by dependencies.

**Yardstick:** Rex.dmg. A milestone counts when it moves a measured number
for Rex (imports implemented, initialisers run, first window) or makes a
whole class of other programs run. `mrun --check` on the Rex window reports
311 of 5,688 imports implemented at the start of this roadmap.

## Layers, bottom up

| # | Layer | State | Unlocks |
| --- | --- | --- | --- |
| 1 | Loader, libSystem core, sockets, kqueue, raw syscalls | done | C and Go command-line and server programs |
| 2 | CoreFoundation basics, libproc, resolver | done (subset) | the Rex server and CLI |
| 3 | Blocks runtime | done | any code using `^{ }` closures |
| 4 | Objective-C runtime (`libobjc`): classes, messaging, categories, protocols, ARC entry points, associated objects, `NSObject` | done, except exceptions and `NSInvocation` forwarding | every Objective-C and Swift/Cocoa program |
| 5 | **libdispatch** (GCD): queues, groups, semaphores, sources, `dispatch_once` | in progress | nearly all modern macOS code |
| 6 | **CommonCrypto, zlib, iconv, libcompression** | in progress | hashing/crypto/compression users, many CLI tools |
| 7 | C++ runtime (`libc++`, `libc++abi`) and Mach-O exception unwinding | not started | C++ programs, Objective-C exceptions |
| 8 | CoreFoundation, complete: run loops, bundles, property lists, preferences, URLs, toll-free bridging | bridging done; the rest not started | Foundation |
| 9 | **Foundation**: strings, collections, files, URLs, JSON, notifications, `NSRunLoop`, key-value coding and observing, `NSInvocation` | in progress: strings, numbers, arrays, dictionaries, formatting | Objective-C command-line tools |
| 10 | X.509 and TLS trust evaluation, keychain | not started | outbound HTTPS from macOS programs |
| 11 | Mach ports and messages, bootstrap, XPC, launchd services | not started | apps with helper services |
| 12 | Swift runtime and standard library | not started | all Swift programs |
| 13 | CoreGraphics, CoreText, ImageIO | not started | drawing and text |
| 14 | QuartzCore, AppKit | not started | windows (X11/Wayland or a browser canvas) |
| 15 | Metal | not started | GPU rendering, the Rex terminal grid |
| 16 | SwiftUI, Combine, Observation | not started | the Rex window |
| 17 | Network, CryptoKit, AppIntents, Charts and other app frameworks | not started | the rest of Rex's imports |

Sideways items that matter to people using the container:

- APFS disk images, encrypted and segmented images.
- `.pkg` installers and `.app.zip` archives as inputs alongside `.dmg`.
- A base image others can build `FROM`, with transparent execution of Mach-O
  files (`./tool` instead of `mrun ./tool`).
- arm64: not planned until there is an instruction translator, which is its
  own project.

## Honest notes on the big ones

- **Swift standard library (12).** It is tens of thousands of entry points
  whose ABI is fixed by Apple's compiler. Building it here means writing a
  compatible standard library, mostly in C/assembly or by bootstrapping a
  Swift compiler for this target. It is the largest single item and will be
  approached symbol-family by symbol-family, driven by what Rex and test
  programs import.
- **SwiftUI (16).** Closed source with behaviour defined by implementation.
  It will be built against observed behaviour of real programs, the way
  AppKit will be.
- These two decide when the Rex window appears. Everything above them in the
  table is useful to other software long before that.

## Working rules

- One branch and one pull request per milestone or meaningful change; tests
  are real Mach-O programs run under `mrun`.
- Each PR updates `docs/LOG.md`; support tables in the README move only when
  a test shows it.
- Nothing proprietary enters the repository.
