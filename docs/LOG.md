# Work log

## 2026-11-24: scaffold

- Mach-O loader (`src/loader`): fat slices, segment mapping, classic
  rebase/bind opcodes, chained fixups, export tries, thread-local variables,
  initialisers, unimplemented-import stubs, `--check` import report.
- Darwin thread layer: per-thread `%gs` block, pthread objects layered on the
  host's, ulock on futex.
- First libSystem slice (stdio, strings, memory, locale, dyld API).
- A Mach-O test built with clang + ld64.lld (no Apple SDK) runs: chained
  fixups, a constructor and a thread-local variable.

## 2026-11-24: libSystem core (PR: libsystem-core)

- Files (`fs.c`): Darwin `stat`/`statfs`/`dirent` layouts, open/fcntl/at-flag
  translation, xattrs, `sendfile`.
- Processes (`proc.c`): ids, passwd/group, rlimits, wait-status translation,
  `fork`, `exec*` (Mach-O targets re-enter the loader, ELF and scripts run
  natively), a complete `posix_spawn` with file actions and attributes.
- Signals (`signal.c`): number mapping, 32-bit signal sets, and handlers that
  receive a Darwin `siginfo`/`ucontext`/`mcontext64` and can edit registers.
- Terminals (`tty.c`): Darwin `termios`, tty/pty ioctl request codes, ptys.
- VM/time/sysctl (`sys.c`): mmap/madvise flags, Mach time, `mach_vm_region`,
  clock ids, `sysctl`/`sysctlbyname`, `sysconf`, `uname`.
- Loader: Darwin-style contiguous `argv/envp/apple` vector (the Go runtime
  walks past `envp` to find `executable_path=`); `--argv0`.
- The Go runtime inside the unmodified `appcli` helper now starts: scheduler,
  threads, signals and memory all come up, and it runs until the first
  unimplemented import. 87 of its 291 imports remain (sockets, kqueue,
  libproc, CoreFoundation, Security, resolver).
- Tests: `files`, `threads` (TSD destructors, static-initialised mutex/cond,
  TLV per thread, `SA_SIGINFO` delivery).

## 2026-11-24: sockets, kqueue, Go binaries (PR: net-kqueue)

- `net.c`: BSD `sockaddr` (length byte, `AF_INET6` = 30), socket-option and
  `MSG_*` numbering, `msghdr`/control-message repacking (fd passing),
  `getaddrinfo`/`getnameinfo` with Darwin's `addrinfo` layout and EAI codes,
  `poll`, `select`.
- `kqueue.c`: kqueue emulated on epoll. Read/write filters (level, `EV_CLEAR`,
  `EV_ONESHOT`, `EV_DISPATCH`, `EV_EOF`), `EVFILT_USER` on an eventfd,
  `EVFILT_TIMER` on timerfds, `EVFILT_PROC` exit on pidfds, `EVFILT_VNODE` on
  inotify, `kevent64`.
- Loader: `LC_UNIXTHREAD` entry. Go's own linker emits it for pure-Go macOS
  executables and expects the kernel's start-of-process stack, so the loader
  builds that stack and jumps instead of calling.
- `sysctl`: name-to-MIB lookups (`sysctlnametomib` and the `{0,3}` request).
- Tests: three Go programs cross-compiled to darwin/amd64 (`hello`: scheduler,
  GC, signal-based preemption; `netio`: TCP/UDP/unix sockets, deadlines,
  `net/http`; `procs`: `os/exec` of Linux and Mach-O children, signals,
  files) plus C tests for kqueue filters and ptys. 8/8 pass.

Dead end worth recording: the first attempt treated `LC_UNIXTHREAD` as
"static binary, unsupported". Go binaries are dynamically linked against
libSystem but still use that load command.

## 2026-11-24: DMG extractor (PR: dmgx)

- `tools/dmgx`: our own disk-image reader in standard-library Python: UDIF
  (zlib, bzip2, LZMA, LZFSE/LZVN, ADC, raw, zero chunks), GPT and Apple
  partition maps, HFS+/HFSX with extents overflow, hard links, symlinks and
  decmpfs transparent compression. `info`, `list`, `extract`, `find-apps`.
- Checked against an independent extraction of a real 72 MB HFS+/LZMA image:
  125 of 125 files byte-identical. Unit tests use synthetic images only.
- Not supported yet: APFS volumes (clear error), encrypted or segmented
  images. See `docs/DMG-FORMAT.md`.
- Written by a delegated Codex agent to a spec, then reviewed and verified.

## 2026-11-24: raw Darwin syscalls, malloc zones, peer credentials (PR: app-helper)

Driven by running the real target: the `appcli` helper bundled in App.dmg (an
unmodified universal Mach-O Go binary with cgo and an embedded SQLite).

- `appcli version` works. `appcli server run` reaches "the Mac app server ready"; the CLI
  talks to the server over its unix socket; a persistent server starts,
  reports status and stops.
- **Raw syscalls** (`src/loader/rawsys.c`): the helper opens its pty with
  `syscall` instructions carrying Darwin numbers (`0x2000036` = ioctl), which
  Linux answers with ENOSYS. Fixed with Linux Syscall User Dispatch: Mach-O
  images are kept below `0x400000000000`, host code above, and a syscall
  instruction below the line raises SIGSYS, which is decoded and served by
  the same implementations libSystem calls use (carry flag + Darwin errno
  on failure). Armed per thread and re-armed after fork. Genuine SIGSYS
  signals still reach the program's own handler.
- **malloc zones** are real `malloc_zone_t` tables: SQLite calls
  `zone->size()` directly instead of `malloc_size()`.
- **`LOCAL_PEERCRED` / `LOCAL_PEERPID`** on unix sockets (the server
  authorises clients by peer uid), mapped to `SO_PEERCRED`.
- Fixed a race: `pthread_join`/`pthread_kill` on a thread that had not started
  yet read an unset host handle.
- New test `rawsyscall` (results in rax/rdx, carry flag, errors, per-thread
  arming). 9/9 pass.

Dead ends: first read the pty failure as a missing `TIOCPTYGNAME` ioctl
(the libSystem path was fine; the binary never called it), then as a missing
working directory. `strace` showing `syscall_0x2000036` settled it.

## 2026-11-24: CoreFoundation, Security, libproc, resolver (PR: frameworks)

- `src/frameworks/corefoundation`: reference-counted object model with
  strings (UTF-8 inside, UTF-16 lengths outside), data, arrays, dictionaries,
  sets, numbers, booleans, dates, errors, locales, UUIDs and basic URLs.
- `src/frameworks/security`: certificate, policy and trust objects. Trust
  evaluation is **not implemented** and says so: `SecTrustEvaluateWithError`
  returns false with `errSecNotTrusted` unless `BITTEN_INSECURE_TRUST=1`.
  Keychain queries report "item not found".
- `src/libsystem/libproc.c`: `proc_listpids`, `proc_pidinfo` (BSD info, task
  info, cwd, descriptors), `proc_pidpath`, `proc_pidfdinfo`,
  `proc_regionfilename`, and the `KERN_PROC` / `KERN_PROCARGS2` sysctls, all
  read from `/proc`, with Darwin structure sizes asserted at compile time.
- `src/libsystem/resolv.c`: `res_9_*` over glibc's resolver, keeping the host
  state behind the caller's Darwin-sized buffer.
- `src/frameworks/objc`: placeholder. `objc_msgSend` reports that there is no
  Objective-C runtime; selectors are interned strings.
- With these, every one of the 291 imports of the Mac app helper is implemented,
  and the end-to-end flow works: `appcli server start`, `appcli new`, a shell in a
  The Mac app terminal, `appcli send`, `appcli capture` printing the shell's output.
- Tests `cf` and `libproc`. Suite: 11/11 in a clean Debian container
  (`docker build --target test .`), which also caught two portability bugs
  (a missing `<linux/sockios.h>` and the versioned path of `ld64.lld`).
- This batch was written by a delegated Codex agent to a written spec and
  reviewed, built and run against the real target before merging.

## 2026-11-24: container, the Mac app example, documentation (PR: docker)

- `Dockerfile`: multi-stage. Build stage compiles `mrun`; an optional `test`
  stage runs the whole suite; the runtime image is Debian slim with `mrun`,
  `dmgx`, the entrypoint, zsh, the directories macOS programs expect and a
  macOS-style `/usr/bin/login`. Runs as an unprivileged user with Docker's
  default seccomp profile.
- `docker/bitten` entrypoint: finds the mounted `.dmg`, unpacks it, picks the
  app, and offers `info`, `run`, `exec`, `shell`, `check`. Generic: nothing
  in it knows about the Mac app.
- `compose.yaml` (any image) and `examples/mac-terminal/compose.yaml`.
- `examples/mac-terminal/terminal.py`: a browser and `--tty` view of a Mac app terminal,
  driven only through the real CLI (`appcli capture`, `appcli send`). Found on the
  way: The Mac app starts shells with `login -fpl user ...` (macOS option letters),
  hence the login shim.
- Verified from a clean state with the real disk image:
  `docker run ... bitten info` (2 s including unpacking), `exec appcli version`,
  and `docker compose -f examples/mac-terminal/compose.yaml up` serving a zsh login
  shell inside a Mac app terminal on `http://localhost:7680`.
- Docs: README rewritten with a support matrix; `ARCHITECTURE.md`,
  `TARGET-APP.md` (import coverage: helper 291/291, GUI 311/5,688) and
  `DECISIONS.md`.
- CI: a GitHub Actions workflow is written but not active. It sits in
  `ci/github-actions.yml` because the token used here lacks the `workflow`
  scope; copying it to `.github/workflows/ci.yml` enables it. Until then the
  suite is run locally with `docker build --target test .` before each merge.

Where it stops: the Mac app window itself (`Contents/MacOS/App`) cannot start.
It needs an Objective-C runtime, a Swift runtime and standard library,
Foundation, AppKit, SwiftUI and Metal. `TARGET-APP.md` sizes each.

## 2026-11-24: provenance note (PR: provenance-note)

The delegated agent's final report for the frameworks batch arrived after the
merge and matched the merged files (209 exports: CoreFoundation 149,
Security 33, resolver 10, libproc 9, Objective-C 8). It disclosed reading
Apple's open-source libproc wrapper for return-value conventions, so the
README's licensing section now lists the open-source references that were
consulted instead of claiming documentation alone.

## 2026-11-24: Objective-C runtime and Blocks (PR: objc-runtime)

Direction from the owner: keep building every missing library in-house, with
The Mac app as the yardstick, for developers who want Mac containers in Docker.
`docs/ROADMAP.md` lays out the layers.

- `src/frameworks/objc/runtime.c`: selectors, lazy class realisation from
  compiler metadata (big and relative method lists, non-fragile ivar
  sliding), categories, protocols, `+load` and `+initialize`, method caches,
  dynamic resolution, forwarding targets, class pairs created at run time,
  and about 90 functions of the public runtime API.
- `msgsend.S`: `objc_msgSend`, `_stret`, `_fpret`, `_fp2ret`, `Super`,
  `Super2` and their struct-return forms, `method_invoke`.
- `arc.c`: side-table reference counts, weak references, associated objects,
  autorelease pools, property helpers, `@synchronized`, the ARC entry
  points, and `NSObject`.
- `blocks.c`: the Blocks runtime.
- Loader: `dx_image_section`, and hooks that give the runtime each image
  after fixups and run `+load` before initialisers.
- Tests: `tests/objc/runtime.m` (one program exercising all of the above
  under ARC) and `tests/objc/threads.m` (8 threads hammering dispatch,
  retain/release and weak loads while caches grow). Suite: 13/13.
- The Mac app window imports still unimplemented: 5,377 -> 5,352.

Found while testing: without the autoreleased-return handshake an object
returned from a weak property getter stays in the enclosing pool, which
changes when `dealloc` runs compared with macOS. The handshake is now
implemented by recognising the caller's instructions, as the real runtime
does on x86-64.

Not done: Objective-C exceptions (`objc_exception_throw` aborts with the
class name), `NSInvocation`-based forwarding, tagged pointers.

## 2026-11-24: toll-free bridging and the first of Foundation (PR: cf-bridging)

- CoreFoundation objects now start with an isa pointer. `bridge.c` creates
  the public classes (`NSString`, `NSArray`, `NSDictionary`, `NSNumber`,
  `NSData`, ...) and the CF-backed concrete classes inside `mrun`, with
  retain/release/hash/isEqual wired to CF. Constant strings emitted by the
  compiler are recognised and mapped to CF strings; CF functions accept
  foreign Objective-C objects; the shared empty collections `__NSArray0__`
  and `__NSDictionary0__` exist.
- `sdk/include`: bitten's own headers (C subset, `objc/runtime.h`,
  `CoreFoundation/CoreFoundation.h`, `Foundation/Foundation.h`).
- `frameworks/Foundation`: written in Objective-C under ARC and built as a
  Mach-O framework that `mrun` loads from its framework root. First slice:
  `NSString`/`NSMutableString` (creation, formatting with `%@`, UTF-16
  semantics, searching, splitting, case, numeric values, paths), `NSNumber`,
  `NSArray`/`NSMutableArray`, `NSDictionary`/`NSMutableDictionary` (literals,
  subscripts, fast enumeration, blocks, sorting, descriptions), `NSNull`,
  `NSLog`, `NSAutoreleasePool`, `NSStringFromClass` and friends.
- `tests/foundation/basics.m` compiles against the SDK headers and passes.
  Suite: 14/14. The Mac app window imports unimplemented: 5,352 -> 5,340.
- Docker: the build stage now needs clang and lld; the image carries the
  framework root at `/usr/local/lib/bitten/root`.

Bugs found on the way: a scripted edit that made CF string functions accept
constant strings skipped a one-line function (`CFStringGetLength`), so
non-ASCII literals reported length 0; caught by the test. Also noted for
later: CFDictionary is a linear list, which is correct but slow for large
tables.

## 2026-11-24: CommonCrypto, zlib, libcompression, iconv (PR: crypto-zlib)

Written by a delegated Codex agent from the public specifications (FIPS
180-4, 197, 198-1; RFC 1321, 1950-1952, 2898; SP 800-38A/D), reviewed and
re-run here. No host libz or libcrypto is linked.

- CommonCrypto: MD5, SHA-1/224/256/384/512 (one-shot and streaming with
  Apple's context sizes), HMAC, AES-128/192/256 in ECB/CBC/CTR/GCM with
  PKCS7, PBKDF2, `CCRandomGenerateBytes`, `SecRandomCopyBytes`.
- zlib: our own inflate (stored, fixed, dynamic Huffman; zlib, gzip and raw
  wrappers; streaming) and deflate (stored and fixed-Huffman blocks with
  LZ77), checksums, `compress`/`uncompress`, the `gz*` file API.
- libcompression: raw DEFLATE, LZ4 and LZ4_RAW through the buffer API,
  streaming for DEFLATE.
- iconv forwarded to the C library with macOS encoding names mapped.
- Tests `crypto`, `zlib`, `iconv` use published vectors. The delegate also
  checked 12 emitted streams and 120 random cases against reference zlib and
  LZ4 outside the suite. Suite: 17/17.

Limits: deflate never emits dynamic-Huffman blocks, so output is larger than
real zlib's (it is valid and interoperable). AES uses table lookups and is
not constant-time. DES/3DES/RC4/Blowfish, MD2/MD4, LZFSE and LZMA in
libcompression are not implemented and say so through their documented
failure values.

## 2026-11-24: libdispatch (PR: libdispatch)

Grand Central Dispatch, written by a delegated Codex agent from the public
API documentation and the Blocks ABI, reviewed and stress-run here.

- Queues: serial, concurrent, global and main; `dispatch_async/sync`,
  barriers, `dispatch_apply`, `dispatch_after`, `dispatch_once`, target
  queues, suspend/resume, queue-specific data, `dispatch_block_*`,
  `dispatch_main`. A worker pool that grows on demand; workers are created
  through the Darwin pthread layer so app code running on them has its
  `%gs` thread block.
- Groups, semaphores, sources (timer, read, write, signal, process exit,
  data add/or, best-effort vnode) driven by one epoll manager thread,
  `dispatch_data`, `dispatch_read`/`dispatch_write`.
- Dispatch objects are Objective-C objects through `dx_os_object_class`, so
  ARC code can hold them in strong variables and ivars.
- Hooks for the future run loop: an eventfd that is readable while the main
  queue has work, and a drain function.
- Tests: `tests/c/dispatch.c`, `tests/c/dispatch_sources.c` (30 consecutive
  passes by the author, 15 more here) and `tests/objc/dispatch_arc.m`
  (queues in ARC ivars, 1,064 captured objects released exactly once).
  Suite: 20/20. The Mac app window imports unimplemented: 5,327.

Limits: `dispatch_io_*` is absent; QoS is recorded but does not change
scheduling; timer leeway is ignored; a signal source observes a signal only
until the program installs its own handler for it afterwards.

## 2026-11-24: path redirection regression (PR: fix-path-redirect)

Giving `mrun` a default framework root (for Foundation) switched on the
path redirection that had only ever run with `BITTEN_ROOT` set. It
redirected any not-yet-existing path under `/Users`, `/Library`, `/private`
and others into the framework root, so the Mac app server could not create its
socket in the container. The unit suite did not see it; the container smoke
test did, after the merge.

- Redirection now applies only to `/System/Library/` and `/usr/lib/swift/`,
  and only when the file exists in the framework root.
- `tests/c/paths.c` pins both halves: framework files resolve, new files and
  sockets are created where asked.
- `tests/e2e/target-app.sh` automates the container check with a real App.dmg
  (`info`, `appcli version`, a command typed into a Mac app terminal). It is run
  before merging anything that touches the loader, paths or the image.
  Suite: 21/21, e2e ok.

## 2026-11-24: Foundation, second slice; CFDictionary hash index (PR: foundation-2)

From here on all work is done in one thread, at the owner's request (no
delegated agents).

- CoreFoundation: dictionaries and sets keep their compact entry array and
  gain an open-addressing index once they pass eight entries. 20,000
  inserts, lookups, removals and reinserts with string keys now take
  milliseconds (`tests/c/cfdict.c`).
- Foundation, written in Objective-C:
  `NSData`/`NSMutableData` (files, Base64), `NSDate`, `NSError` and the
  Cocoa/POSIX error constants, `NSSet`/`NSMutableSet`, `NSEnumerator`,
  `NSValue`, `NSCharacterSet`/`NSMutableCharacterSet` with string trimming
  and splitting, `NSException` (raising terminates with the macOS message),
  `NSProcessInfo`, `NSUUID`, `NSFileManager` (existence, listing, recursive
  create/copy/move/remove, attributes, symlinks), string file I/O and path
  standardisation, `NSURL` (parsing, file URLs, path edits),
  `NSJSONSerialization` (reader and writer), `NSNotificationCenter`,
  `NSLock`/`NSRecursiveLock`/`NSCondition`, `NSThread`,
  `NSHomeDirectory`/`NSTemporaryDirectory`/`NSUserName`.
- SDK headers gained `sys/stat.h`, `dirent.h`, `fcntl.h`, `pthread.h`,
  `pwd.h` with Darwin layouts.
- `tests/foundation/more.m`: about 90 assertions across all of the above.
  Suite: 23/23; container end-to-end check passes. The Mac app window imports
  unimplemented: 5,327 -> 5,307.

Bug found by the test: URL components were held in a struct of unretained
pointers. With the autoreleased-return handshake working as on macOS, the
substrings were released immediately instead of lingering in a pool, and the
getters returned garbage. They are held strongly now.

Approximations to know about: character-set membership outside Latin-1 is
by block, not by the Unicode character database; case mapping covers ASCII
and Latin-1; `NSDate` descriptions are always UTC.

## 2026-11-24: pause point (PR: resume-notes)

Ran the Mac app window binary under `mrun` after PR #13. It now loads, registers
its Objective-C metadata, runs `+load` and its initialisers, and stops at
its first Swift runtime call, `swift_getSingletonMetadata`. Classified its
5,307 missing imports by library and kind; 1,723 are Swift runtime and
standard-library symbols, of which 149 are C-ABI runtime functions.
`docs/NEXT.md` records the state, the checks to run, and the order of work
for the Swift layer and for the smaller independent items.

## 2026-11-25: Swift runtime groundwork (PR: swift-base)

- Tests can now be real Swift compiler output. The open-source Swift
  toolchain for Linux (swift.org, 6.3.1 here) compiles for
  `x86_64-apple-macos11` with `-parse-stdlib`: no standard library and no
  Apple files are involved, and the objects import only Swift runtime entry
  points. `tests/swift/NAME.swift` + a C driver `tests/swift/NAME.c` build when
  `swiftc` is on `PATH` (or in `/opt/swift/usr/bin`). This settles the open
  question in `NEXT.md` without Apple's toolchain package.
- `src/frameworks/swift/`: `swift_abi.h` (compiler-fixed layouts: metadata,
  value witnesses, context descriptors, generic patterns, conformances),
  `swift_internal.h` (the contract between the runtime's files), `images.c`
  (records every image's `__swift5_*` sections through a new loader hook,
  `dx_swift_image_added`).
- `tests/swift/layout`: struct metadata, its descriptor, field offsets and
  value witness table read through those layouts.
- Measured here: the Mac app window has 5,360 unimplemented imports with this
  build (`NEXT.md` recorded 5,307 on the previous machine; the difference is
  being looked into, the deltas below are against 5,360).

## 2026-11-25: Swift heap objects (PR: swift-heap)

- `src/frameworks/swift/heap.c`: `swift_allocObject`, strong retain/release
  (`_n`, nonatomic), `swift_tryRetain`, unowned counts, native weak
  references, deallocation (class instances, partial and uninitialised
  objects), stack and static objects, uniqueness checks, boxes
  (`swift_allocBox`, `swift_projectBox`, `swift_makeBoxUnique`, the shared
  empty box), `swift_once`, `swift_beginAccess`/`endAccess`, and the value
  witness tables of `Builtin.NativeObject`/`UnknownObject`/`BridgeObject`
  and of closures (`$sBoWV`, `$sBOWV`, `$sBbWV`, `$syycWV`).
- Facts taken from compiler output rather than assumed: a static object is
  emitted with a zero refcount word and an 8-byte once-token right before
  it, and `swift_initStaticObject` must fill the header in (we make it
  immortal); `swift_once` predicates are tested inline against ~0; a
  heap object's destroyer (`metadata[-2]`) and a class's ivar destroyer
  take the object in r13 (Swift `self`), so the runtime calls them through
  a small assembly thunk (`callconv.S`); pointer extra inhabitants are the
  even values below 4 GiB; the x86-64 spare-bit mask is
  0xFF00000000000007.
- The refcount word is ours (strong count, unowned count, deiniting, a
  has-weak bit). Native weak references are bitwise-takable, so they point
  at a shared per-object record instead of being registered by address.
  Exclusivity checks are accepted without tracking (documented in heap.c).
- `src/frameworks/swift/objc.c`: the root class `_TtCs12_SwiftObject`,
  whose `-retain`/`-release`/`-autorelease`/`-retainCount`/`-dealloc` use
  Swift counting (`objc_retain` on a Swift object reaches it by message),
  `swift_unknownObject*` and `swift_bridgeObject*` retain/release.
  `arc.c` exposes `dx_objc_object_destroyed` so a Swift object's `__weak`
  variables and associated objects are cleared when it is freed.
- `tests/swift/heap`: deinit order, counts, unowned, closures and their
  contexts, static objects, lazy globals, stack-promoted objects, boxes and
  value witnesses; passes at `-O` and `-Onone`. Suite: 22/22 (no Go
  toolchain on this machine); `tests/e2e/target-app.sh` not run (no Docker here).
- The Mac app window imports unimplemented: 5,484 -> 5,434 (5,484 is what
  `fdecc90` gives on this machine, not the 5,360 recorded in the previous
  entry).

## 2026-11-25: Swift weak and unowned references to any object (PR: swift-weak)

- `swift_unknownObjectWeak*` and `swift_unknownObjectUnowned*` (references
  through `AnyObject` and class-bound protocols), in
  `src/frameworks/swift/objc.c`. Unlike native weak references, these are
  not bitwise-takable, so they use the Objective-C `__weak` table for both
  kinds of object; an unowned reference to a Swift object holds its unowned
  count instead.
- `arc.c`: a class with its own reference counting now decides whether a
  weak reference may be formed or loaded, through `-allowsWeakReference` and
  `-retainWeakReference` as on macOS. Swift's root class answers from the
  Swift counts, so `objc_loadWeak*` returns nil once a Swift object's deinit
  has started. The weak functions are reachable from C through `dx_objc.h`.
- Tests can be compiled as the module `Swift` (first line
  `// module: Swift`): the compiler finds `Optional`, needed for `weak`, in
  the standard library by name, so `tests/swift/weak.swift` declares it.
  The test covers native weak references becoming nil, copies of structs
  holding weak references, `AnyObject` weak and unowned references to Swift
  and Objective-C objects. Passes at `-O` and `-Onone`; suite 23/23.
- The Mac app window imports unimplemented: 5,434 -> 5,423.

## 2026-11-25: Swift objects in Objective-C; class metadata and casts (PR: swift-objc)

- `src/frameworks/swift/objc.c`: `swift_getObjCClassMetadata` (a Swift
  class is its own metadata; a plain Objective-C class gets a cached
  ObjCClassWrapper), `swift_getObjCClassFromMetadata` (+`Conditional`),
  `swift_getObjCClassFromObject`, `swift_getInitializedObjCClass`,
  `swift_dynamicCastObjCClass{,Unconditional}`,
  `swift_dynamicCastObjCClassMetatype{,Unconditional}`, the foreign-class
  (CoreFoundation) casts, and `swift_isaMask`.
- `tests/swift/objc`: a swiftc-compiled class seen from Objective-C: its
  class is registered under its mangled name with SwiftObject as superclass,
  answers the NSObject-protocol basics, and `-retain`/`objc_retain`,
  autorelease pools and `__weak` variables all use Swift counts;
  `+alloc` from Objective-C makes a Swift-counted object whose last release
  runs the Swift deinit; unknown-object and bridge-object counting (spare
  bits stripped, tagged and immortal values untouched); casts and wrapper
  metadata. Passes at `-O` and `-Onone`; suite 24/24.
- The Mac app window imports unimplemented: 5,423 -> 5,418.

## 2026-11-25: Swift mangled type names and protocol conformances (PR: swift-demangle)

- `src/frameworks/swift/demangle.c`: the type grammar of the Swift
  mangling, parsed postfix onto a stack the way the grammar is defined,
  with symbolic references (direct/indirect context descriptors, accessor
  functions, Objective-C protocols), word and node back references,
  standard-library substitutions (`Si`, `Sg`, `Sa`, `SD`, `Sc*`...), bound
  generics with per-level argument lists, tuples, functions (conventions,
  `async`/`throws`/`@Sendable`/global actors, `inout` and other parameter
  flags), metatypes, existentials, generic parameters and associated type
  paths, builtins, opaque result types, extensions and private names.
  Resolution to metadata runs against a generic environment (a context
  descriptor's signature plus key arguments, or a GenericEnvironment), and
  checks the requirements of generic types before instantiating them.
  Types named rather than referenced are found by qualified name in an
  index of every image's `__swift5_types`/`__swift5_protos`. Standard
  library, builtin and structural metadata are reached through their
  exported symbols, so `Optional`, `Int` and friends resolve as soon as a
  standard library exports `$sSqMn`, `$sSiN`...; until then the lookup
  returns NULL and `BITTEN_DEBUG=1` says what was asked and why it failed.
  Entry points: `swift_getTypeByMangledNameInContext{,2}`,
  `...InMetadataState{,2}`, `...InEnvironment{,InMetadataState}{,2}`,
  `swift_getOpaqueTypeMetadata{,2}`, `swift_getOpaqueTypeConformance{,2}`,
  `swift_getTypeName` and `swift_demangle` (types only). The printer matches
  `swift-demangle` exactly on all 1,099 type symbols of the Mac app window and
  on 8,255 of the 8,482 in the Swift toolchain's own libraries (the rest are
  local types and other forms runtime names never use).
- `src/frameworks/swift/protocols.c`: `__swift5_proto` of every image,
  current and future, indexed by type descriptor (by name for non-unique
  imported descriptors, by name or class for Objective-C classes);
  `swift_conformsToProtocol{,2,Common}` walk superclasses, check conditional
  requirements and cache per (type, protocol), negative answers until the
  next image with conformances. `swift_getWitnessTable` instantiates
  generic and resilient witness tables (defaults, resilient witnesses,
  conditional conformances in the private area, instantiator);
  `swift_getAssociatedTypeWitness` and
  `swift_getAssociatedConformanceWitness` resolve the tagged mangled names
  and accessor references in witness tables.
- Loader fix: `dx_image_section` only looked in `__DATA*` segments, so
  every `__swift5_*` section (they are in `__TEXT`) was invisible to the
  Swift runtime.
- `tests/swift/demangle`: printer cases, symbolic references from field
  descriptors and built in place, lookups by name, conformances including
  inherited ones, an associated type and an associated conformance
  requested by compiled generic code, an opaque result type. Generic types
  wait for `metadata.c`. Passes at `-O` and `-Onone`; suite 25/25. No
  Docker here: `tests/e2e/target-app.sh` not run.
- The Mac app window imports unimplemented: 5,418 -> 5,406.

## 2026-11-25: Swift metadata, part 1: builtins, structs, singletons, generics (PR: swift-metadata)

- `src/frameworks/swift/metadata.c`: value witness tables and metadata of
  the plain builtin types (`$sBi{1,7,8,16,32,63,64,128,256,512}_`, `Bw`,
  `Bp`, `$sBf{16,32,64,80,128}_`, `WV` and `N`) and of the empty tuple
  (`$sytWV`, `$sytN`). The `N` symbols name the full metadata
  `{witnesses, kind}`, as compiled code expects (it adds one word); the
  demangler now does the same. Extra inhabitants measured against swiftc:
  `Int1` has 254 (values 2...255), `RawPointer` only null; metatypes and
  function pointers have 2^31-1 (values below 4 GiB, metatypes with the low
  bit clear).
- Metadata states: entries for every metadata the runtime builds, one
  recursive lock, completion functions retried after their dependencies are
  completed; `swift_checkMetadataState`. `swift_getSingletonMetadata`
  publishes the type's cache (which compiled accessors read directly) once
  complete. `swift_initStructMetadata`: field layout, size/stride/alignment,
  POD, bitwise-takable and inline flags, extra inhabitants of the richest
  field; the compiler's constant VWT pattern is copied unless the flags say
  it is writable.
- `generic.c`: `swift_getGenericMetadata` with an instantiation cache keyed
  by descriptor and key arguments (entries inserted before completion so
  recursive requests see them), `swift_allocateGenericValueMetadata` (extra
  data pattern, VWT pattern, generic arguments).
- `tuple.c`: `swift_getTupleTypeMetadata{,2,3}` (uniqued by elements and
  labels, with runtime value witnesses that run each element's),
  `swift_getTupleTypeLayout{,2,3}`, `swift_getMetatypeMetadata`. Helpers
  for the demangler and casts: `sw_get_tuple_metadata`,
  `sw_get_metatype_metadata`, `sw_get_generic_metadata`,
  `sw_generic_key_argument_count`, `sw_descriptor_name`,
  `sw_descriptor_qualified_name`.
- `enum.c` (start): `swift_{get,store}EnumTagSinglePayloadGeneric`, the
  single-payload tag encoding compiled witnesses call.
- `swift_abi.h`: tuple element offsets are 32-bit (compiled code loads an
  i32; the field was a `size_t`).
- Tests: `tests/swift/NAME.lib.swift` is built as a separate resilient
  module the test imports (that is what makes swiftc emit singleton
  initialisation), `NAME.flags` adds swiftc flags. `tests/swift/metadata`:
  generic structs at several types and nested, tuples, metatypes, a C-defined
  non-POD type with counted copies/destroys and its extra inhabitants seen
  through compiled and runtime witnesses, generic code calling the runtime.
  `tests/swift/singleton`: structs holding resilient fields, nested and
  generic. Suite 27/27 at `-O` and at `-Onone`. No Docker here:
  `tests/e2e/target-app.sh` not run.
- The Mac app window imports unimplemented: 5,453 -> 5,382. `mrun` on it now gets
  through `swift_getSingletonMetadata` for `TargetMacOSApp` and stops at
  `$s7SwiftUI28NSApplicationDelegateAdaptorVMa`, a SwiftUI metadata accessor.

## 2026-11-25: Swift metadata, part 2: enums (PR: swift-enums)

- `src/frameworks/swift/enum.c`: `swift_initEnumMetadataSingleCase`,
  `swift_initEnumMetadataSinglePayload` (extra inhabitants first, then 1, 2
  or 4 tag bytes after the payload with the case index spread over the
  payload's first four bytes), `swift_initEnumMetadataMultiPayload` (payload
  area as large as the largest payload, stored in the metadata at the
  descriptor's payload-size offset; tag bytes after it; no spare bits),
  `swift_getEnumCaseMultiPayload`, `swift_storeEnumTagMultiPayload`.
- Multi-payload enums' `getEnumTagSinglePayload`/`storeEnumTagSinglePayload`
  witnesses are the runtime's: the compiler's own witnesses for generic
  multi-payload enums call back through the VWT, so the runtime must
  install them. Their extra inhabitants are the unused tag values counted
  down from all ones (inhabitant i is tag ~i), as swiftc does for fixed
  multi-payload layouts.
- `demangle.c`: names are looked up in loaded images before the registry
  (as dyld would), so a Mach-O image that defines standard-library types
  itself (a test compiled as the module Swift) resolves `Sq` and friends.
- `tests/swift/enums`: Optional, single-payload with and without enough
  extra inhabitants, multi-payload with 8- and 1-byte payloads, 300 empty
  cases over two tags, nested Optionals and Optional of a multi-payload
  enum. Each generic construction (runtime layout) is compared byte for
  byte with the compiler's fixed layout of the same type. Suite 28/28 at
  `-O` and `-Onone`. No Docker here: `tests/e2e/target-app.sh` not run.
- The Mac app window imports unimplemented: 5,382 -> 5,378. `mrun` still stops at
  `$s7SwiftUI28NSApplicationDelegateAdaptorVMa`.

## 2026-11-25: Swift dynamic casts and errors (PR: swift-casts)

- `src/frameworks/swift/casts.c`: `swift_dynamicCast` opens the source
  (opaque, class, error and metatype existentials; Optionals) and casts by
  target kind: same type, Optional (payload cast, nil kept), existentials
  (conformance to every protocol, class and superclass constraints, then
  the container: inline buffer or `swift_allocBox` box, class reference,
  error box, metatype, with the witness tables in the existential's order),
  classes (by the object's real class), metatypes. Take/destroy flags are
  honoured by destroying the source; unconditional failures print the
  macOS message ("Could not cast value of type 'A' (0x...) to 'B' (0x...)")
  and abort. Also `swift_dynamicCastClass{,Unconditional}`,
  `swift_dynamicCastMetatype{,Unconditional}`,
  `swift_dynamicCastObjCProtocol{Conditional,Unconditional}` and
  `swift_dynamicCastTypeToObjCProtocol{Conditional,Unconditional}`.
- `src/frameworks/swift/errors.c`: error boxes (heap objects of kind
  ErrorObject holding type, Error conformance and value):
  `swift_allocError`, `swift_deallocError`, `swift_getErrorValue` (also for
  Objective-C objects thrown as errors), `swift_errorRetain/Release`,
  `swift_willThrow` (an assembly entry that keeps r12/r13 and logs the error
  at `BITTEN_DEBUG=2`), `swift_willThrowTypedImpl`, `swift_errorInMain` and
  `swift_unexpectedError` (the macOS messages, with the enum case name read
  from the field descriptor, then abort).
- `tests/swift/casts`, compiled as the module `Swift` so it can declare
  `Error`: class, metatype and Objective-C protocol casts, values into and
  out of `any P` (inline and boxed, then called through by compiled code),
  class-bound existentials with inherited conformances, `any P.Type`, an
  error boxed by a cast and one thrown and caught by compiled code.
  Existential metadata is built by hand until `metadata.c` makes it.
  The `sw_get_*_metadata` helpers are now linked directly. Passes at `-O` and `-Onone`; suite 29/29. No Docker here:
  `tests/e2e/target-app.sh` not run.
- The Mac app window imports unimplemented: 5,378 -> 5,366.

## 2026-11-25: Swift generic type names, conformances and witness tables tested (PR: swift-generic-names)

- With `metadata.c` merged, `tests/swift/demangle` now covers generic
  types: `Pair<S, QQ>` named by symbolic references built in C and by name
  resolves to the same uniqued metadata compiled code gets; field types in
  the environment of a type's key arguments (`x`, `q_`, `T.A` through the
  witness table among the key arguments, a tuple, `Pair<T.B, T>`); generic
  requirements checked (`Box<QQ>` is refused); the conditional conformance
  `Pair: P where T: P` instantiates a generic witness table holding the
  `S: P` table in its private area, whose associated type (`T.A`) and
  associated conformance (`T.B: Q`) compiled generic code resolves. Box's
  metadata completion itself calls `swift_getTypeByMangledNameInContext`
  for its field types.
- `swift_getTypeName` prints nested generic types with each level's own
  arguments (`demangle.Outer<demangle.S>.Inner<demangle.QQ>`); unqualified
  names are the innermost type with its arguments.
- Suite 29/29 at `-O` and `-Onone`. The Mac app window imports unimplemented:
  5,366 (unchanged; tests and printing only). The Mac app still stops at
  `$s7SwiftUI28NSApplicationDelegateAdaptorVMa`.

## 2026-11-25: Swift metadata, part 3: functions, existentials, foreign types (PR: swift-structural)

- `tuple.c`: `swift_getFunctionTypeMetadata{,0,1,2,3}`,
  `...Differentiable`, `...GlobalActor` and
  `swift_getExtendedFunctionTypeMetadata`, uniqued by every field. Layout:
  kind, flags word, result, parameters, then 32-bit parameter flags
  (padded), differentiability kind, global actor, extended flags, thrown
  error type. Witnesses by convention: escaping Swift closures `$syycWV`
  (heap.c), non-escaping ones a POD pair, thin and C function pointers a
  POD word (extra inhabitants: values below 4 GiB), blocks the unknown-object
  table.
- `existential.c`: `swift_getExistentialTypeMetadata`,
  `swift_getExistentialMetatypeMetadata`, and the static `Any` and
  `AnyObject` metadata the compiler refers to by symbol (`$sypN`/`$sypWV`,
  `$syXlN`/`$syXlWV`). Opaque existentials (3-word buffer, type, witness
  tables; values boxed when not inline), class-bound ones (unknown-object
  reference, witness tables), `any Error` (one reference), existential
  metatypes (POD). Extra inhabitants measured against swiftc: the type word
  of an opaque existential and the reference of a class-bound one, value
  i << 1, 2^31-1 of them.
- `metadata.c`: `swift_getForeignTypeMetadata` (imported C types: the first
  candidate registered under a name wins; foreign completion run if any).
- `sw_utable.h`: the uniquing table shared by the structural metadata.
- `tests/swift/weak.c`: the abort-on-call stand-ins for the generic
  metadata entry points are gone (the runtime has them now).
- `tests/swift/structural`: function types (conventions, throws, parameter
  flags), Any/AnyObject/compositions/class-bound protocols and their
  metatypes, extra inhabitants through generic Optional against the
  compiler's fixed layouts, opaque existential witnesses, a closure passed
  through generic code. Suite 30/30 at `-O` and `-Onone`. No Docker here:
  `tests/e2e/target-app.sh` not run.
- The Mac app window imports unimplemented (total `^MISSING` lines, with
  Foundation built): 5,366 -> 5,361. The "before" figures in the two
  previous metadata entries were measured without `build/root` (Foundation)
  and are too high; with it, main measured 5,366 before this PR. `mrun`
  still stops at `$s7SwiftUI28NSApplicationDelegateAdaptorVMa`.
## 2026-11-25: the standard library begins (PR: swift-stdlib-proto)

- `libswiftCore.dylib` is now built from Swift source of our own
  (`stdlib/`), compiled as the module `Swift` with `-parse-stdlib` and
  library evolution, and linked as a Mach-O dylib into
  `build/root/usr/lib/swift/`. Declaring the same public API as Apple's
  standard library makes the compiler emit the same symbol names (`$sSiN`,
  `$sSiSQsWP`, `$sSqMn`...), so programs bind to it; Apple's protocols are
  resilient, so their requirements are reached through dispatch thunks and
  descriptors and need not be in the same order. `@frozen` types must keep
  Apple's layout and are declared accordingly. The C runtime stays in
  `mrun`; the loader falls back to the registry for anything the dylib does
  not export.
- First slice: precedence groups and operators, `Bool`, the ten fixed-width
  integer types (generated by `tools/gen-integers.py`), `Optional`,
  `Equatable`, `Comparable`, the literal protocols, `Never`, `Sendable`.
- The build also emits `build/swift/Swift.swiftmodule` (and an empty
  `SwiftOnoneSupport`), so tests can now be **ordinary Swift**:
  `tests/swiftlib/NAME.swift` + a C driver, compiled against our module.
  `tests/swiftlib/basics`: arithmetic, comparisons, Bool logic, nested
  Optionals, at -O and -Onone.
- The Mac app window (total `^MISSING`): 5,366 -> 5,304.

## 2026-11-25: integer protocol tower (PR: stdlib-numeric)

- `AdditiveArithmetic`, `Numeric`, `SignedNumeric`, `Strideable`,
  `BinaryInteger`, `FixedWidthInteger`, `SignedInteger`, `UnsignedInteger`,
  with all ten integer types conforming: checked/clamping/truncating generic
  conversions, overflow-reporting arithmetic, smart shifts, bit counts, byte
  swapping, strides. Requirements that need types we do not have yet
  (Hashable, String, floating point, `words`) come later.
- One declared difference from Apple: `FixedWidthInteger` requires
  `Stride: SignedInteger` but not also `Stride: FixedWidthInteger`. With
  both, this compiler's requirement machine does not terminate on our
  declarations; no program we have looked at binds to the descriptor the
  dropped half produces.
- `tests/swiftlib/numerics`: the tower used generically; at -Onone this goes
  through the runtime's witness tables and generic metadata.
- The Mac app window (total `^MISSING`): 5239.

## 2026-11-25: Swift metadata, part 4: classes (PR: swift-classes)

- `src/frameworks/swift/class.c`: `swift_allocateGenericClassMetadata`
  (metadata bounds from the descriptor, or computed and stored for classes
  with a resilient superclass; extra data pattern with the metaclass and
  both class_ro, immediate-members pattern, header, generic arguments),
  `swift_initClassMetadata2` (superclass from its mangled name, SwiftObject
  for root classes; ancestors' generic arguments, field offsets and vtables
  copied; own vtable and override table unless the vtable is static; field
  layout after the superclass's instance size), `swift_updateClassMetadata2`
  (layout only), and the pre-5.4 `swift_initClassMetadata` /
  `swift_updateClassMetadata`.
- Objective-C side: class_ro gets the instance start and size, generic
  instantiations a name (their Swift type name, unique per instantiation),
  an ivar list copied with offsets pointing into the field offset vector
  (field offset globals updated only when wrong: they are read-only when
  the compiler knew the offset), the metaclass's superclass, then the class
  is realised and registered by name.
- `swift_abi.h`: the generic class metadata pattern was wrong. After
  {destroy, ivar destroyer, class flags} come four 16-bit word offsets into
  the extra data (class_ro, metaclass object, metaclass class_ro,
  reserved), not relative pointers; added the vtable, method, override and
  stored-bounds layouts. `swift_getSingletonMetadata` now stops with a clear
  message for a class with a resilient superclass (metadata relocation is
  not implemented).
- `tests/swift/classes` (+ `classes.lib.swift`): generic classes three
  levels deep at two argument types, a non-generic subclass of a generic
  class (singleton initialisation, static vtable), a class with a resilient
  stored property (`swift_updateClassMetadata2`); field offsets, instance
  sizes, superclass and metaclass chains, Objective-C names, lookup by name,
  ivar offsets, objects allocated by compiled code, dynamic dispatch through
  the runtime-built vtables. Suite 34/34 at `-O` and `-Onone`. No Docker
  here: `tests/e2e/target-app.sh` not run.
- The Mac app window imports unimplemented: 5,239 -> 5,236. `mrun` still stops at
  `$s7SwiftUI28NSApplicationDelegateAdaptorVMa`.

## 2026-11-25: standard library: StaticString, text literal protocols, failure reports (PR: stdlib-staticstring)

- `stdlib/StaticString.swift`: `StaticString` (@frozen: start word, UTF-8
  count, flags byte; pointer or single-scalar representation) with all the
  literal conformances, `Unicode` and `Unicode.Scalar` (@frozen `UInt32`,
  validating initializers, Equatable/Comparable, `UInt8(ascii:)`).
- `stdlib/Core.swift`: the unicode-scalar, grapheme-cluster and string
  literal protocols (builtin and public), with their default initializers.
- `stdlib/Assert.swift`: `_fastPath`/`_slowPath`, the assert-configuration
  queries, `_precondition`, `_preconditionFailure`, `_debugPrecondition`,
  `_overflowChecked`, and the entry points compiled code calls:
  `_fatalErrorMessage`, `_assertionFailure` (StaticString form),
  `_diagnoseUnexpectedNilOptional` (now reports instead of only trapping),
  `_diagnoseUnexpectedEnumCase{,Value}` (type name from the runtime),
  `_diagnoseUnavailableCodeReached`, `_unimplementedInitializer` and the C
  entry points `_swift_stdlib_reportUnimplementedInitializer{,InFile}`.
  Reports are written to stderr in one write, in today's macOS format
  `<file>:<line>: Fatal error: <message>`, then the process traps. As on
  macOS, a force-unwrap of nil reports only in debug (`-Onone`) builds.
- Not yet: `fatalError`, `precondition`, `assert` and the other forms with a
  `String` message, and the output protocols (`TextOutputStream`,
  `CustomStringConvertible`...) whose requirements are written in `String`;
  they come with String.
- `tools/gen-integers.py`: `Int`/`UInt` from and to `Builtin.Word`.
- `tests/swiftlib/failures`: literals, scalars, and each failure in a forked
  child (report text and death by signal), at -O and -Onone. Suite 34/34 at
  both. No Docker here: `tests/e2e/target-app.sh` not run.
- The Mac app window (total `^MISSING`): 5,236 -> 5,217.

## 2026-11-25: standard library: Hashable and Hasher (PR: stdlib-hashable)

- `stdlib/Hashing.swift`: `Hashable` (with the default `_rawHashValue(seed:)`
  and `_hashValue(for:)`, which synthesized conformances call), and
  `Hasher`: SipHash-1-3 written here, in Apple's @frozen layout (a tail
  buffer word and eight state words, 72 bytes, as `MemoryLayout` reports on
  the Linux toolchain). The seed is per process, from `arc4random`, chosen
  on first use; `SWIFT_DETERMINISTIC_HASHING=1` (or true/yes) makes it zero.
  With it, our hashes are bit-for-bit the ones Apple's standard library
  gives (checked against values printed by the swift.org toolchain).
  All the entry points programs bind to: `init()`, `init(_seed:)`,
  `init(_rawSeed:)`, `combine`, `_combine` for every width and
  `(bytes:count:)`, `_finalize`, `finalize`, the static `_hash` forms. Not
  yet: `combine(bytes: UnsafeRawBufferPointer)` (no pointer types).
- Conformances: the ten integer types (generated; `BinaryInteger` now
  inherits `Hashable`), `Bool`, `Optional where Wrapped: Hashable`, `Never`
  (also Equatable/Comparable), `Unicode.Scalar`; `ObjectIdentifier`
  (@frozen raw pointer; Equatable, Comparable, Hashable, `UInt/Int(bitPattern:)`),
  `===` and `!==`, and the Dictionary/Set "violates Hashable" reports.
- `tests/swiftlib/hashing`: deterministic hashes equal Apple's, random seeds
  differ between processes, and hashValue / `_rawHashValue` / `Hasher`
  agree for integers, Optional, ObjectIdentifier and a struct whose
  conformance the compiler synthesizes. Suite 35/35 at -O and -Onone. No
  Docker here: `tests/e2e/target-app.sh` not run.
- The Mac app window (total `^MISSING`): 5,217 -> 5,181.

## 2026-11-25: fixes found by the standard library's collections (PR: swift-runtime-fixes)

- Loader: libraries were placed at their linked address whenever the
  header lacked `MH_PIE`, but that flag only exists on executables. A dylib
  linked at 0 (as `ld64.lld` links them) therefore landed on page zero when
  the kernel allowed it (running as root), so NULL dereferences would read
  the library. Libraries now always slide, as with dyld.
- Witness tables of resilient conformances: base-protocol entries arrive as
  tagged references to an accessor (`\xFF\x07` + offset), like associated
  conformances, but compiled code reads `wt[n]` directly as the base
  protocol's table. They are now resolved while the table is instantiated.
  Found by a generic `MutableCollection.sort()` from our stdlib on a
  conformance in another module, at -Onone.
- `swift_coroFrameAlloc`: frames of `modify`/`read` coroutines that do not
  fit the caller's buffer (plain malloc; the compiler frees them).

## 2026-11-25: the collection protocols (PR: stdlib-collections)

- `IteratorProtocol`, `Sequence`, `Collection`, `BidirectionalCollection`,
  `RandomAccessCollection`, `MutableCollection`,
  `RangeReplaceableCollection`, `RangeExpression`, with their default
  implementations (counting, indexing, `first`/`last`, `firstIndex`,
  `prefix`/`suffix`/`dropFirst`, range subscripts, `reduce`, `contains`,
  `allSatisfy`, `elementsEqual`, `partition`, an in-place `sort`,
  `reverse`, `swapAt`, `removeAll(where:)`...).
- Types: `Range`, `ClosedRange`, the partial ranges and `UnboundedRange`,
  `Slice`, `DefaultIndices`, `IndexingIterator`, `EnumeratedSequence`,
  `Zip2Sequence`/`zip`, `PrefixSequence`, `IteratorSequence`,
  `CollectionOfOne`, `EmptyCollection`, `Repeated`, and the generic
  `~=`, `min`, `max`.
- Left for the pointer and Array work: the `Sequence` requirements that
  mention buffer pointers or `ContiguousArray`, and everything returning an
  array (`map`, `filter`, `sorted`, `compactMap`...).
- `tests/swiftlib/collections`: a user-defined mutable random-access
  collection and a forward-only sequence driven through the defaults.
- The Mac app window (total `^MISSING`): 5,181 -> 4,983.

## 2026-11-25: standard library: AnyHashable (PR: stdlib-anyhashable)

- `stdlib/AnyHashable.swift`: `AnyHashable` in Apple's @frozen layout (one
  existential of the internal box protocol, 40 bytes), `base`, `==`,
  `hash(into:)`, `hashValue`, `_rawHashValue(seed:)`, `_convertToAnyHashable`
  (the compiler's implicit conversion), and `_HasCustomAnyHashableRepresentation`
  (AnyHashable of an AnyHashable is itself). Equality unboxes the other side
  with a dynamic cast and tries both directions, so a subclass instance and
  a base-class instance compare through the base class's `==`. As on macOS,
  an Optional holding a value is that value (`AnyHashable(Optional(5)) ==
  AnyHashable(5)`, same hash and base), found through an internal
  conformance of Optional checked with a metatype cast.
- Not yet: the numeric canonicalization (`AnyHashable(1 as UInt8) ==
  AnyHashable(1)` on macOS) and `description` (String).
- Found on the way, already fixed on main by #30: base-protocol entries of
  instantiated witness tables were left as tagged mangled names (Hashable's
  `Equatable` slot crashed `==` through the box).
- `tests/swiftlib/anyhashable`: ints, a synthesized struct, nesting, classes
  from both sides, Optionals, implicit conversion. Suite 37/37 at -O and
  -Onone. No Docker here: `tests/e2e/target-app.sh` not run.
- The Mac app window (total `^MISSING`): 4,983 -> 4,972.

## 2026-11-25: floating point (PR: stdlib-float)

- `FloatingPoint` and `BinaryFloatingPoint`, `FloatingPointSign`,
  `FloatingPointClassification`, `FloatingPointRoundingRule`, and `Float`,
  `Double`, `Float80` (`@frozen` around `Builtin.FPIEEE32/64/80`, generated
  by `tools/gen-floats.py`): IEEE arithmetic and comparisons (NaN unordered),
  rounding by every rule, `squareRoot`, fused multiply-add, IEEE `remainder`,
  the bit-level view (`bitPattern`, sign/exponent/significand fields,
  `ulp`, `nextUp`, `binade`, `significandWidth`, NaN payloads), `.pi`
  (rounded toward zero, as documented), literals, `Strideable` with
  `Stride == Self`.
- Conversions both ways: concrete `IntN(Double)`/`init?(exactly:)` for every
  integer and float type, and the generic ones (`BinaryInteger`'s
  `init<T: BinaryFloatingPoint>` requirements, `BinaryFloatingPoint`'s
  integer and cross-format inits). Generic conversions go through `Float80`,
  which holds any Float or Double, and any integer up to 64 bits, exactly,
  so they round once.
- Runtime: `swift_intToFloat32/64` (integer literals wider than 64 bits,
  reached through the literal witness at run time). libSystem: `fma`,
  `fmaf`, `remainderf`, `nearbyintf` and the `long double` functions the
  compiler calls for `Float80` (`floorl`, `fmodl`, `sqrtl`...).
- `Hashable` (equal values hash alike: both zeros as +0), and for the three
  enums. Left out until their protocols exist: `description`/
  `TextOutputStreamable`, `CVarArg`, Codable, the `RawRepresentable`
  conformance of `FloatingPointSign` (its `rawValue`/`init?(rawValue:)` are
  there). `Float16` does not exist on
  x86-64 macOS and the Mac app does not use it.
- `CGFloat` is not a libswiftCore symbol: The Mac app imports it (4 symbols, mangled
  in module `CoreGraphics`) from `libswiftCoreFoundation.dylib`.
- `tests/swiftlib/floats`: IEEE corner cases, rounding, bit-level
  properties, conversions (exactness, ranges, NaN), Float80, at -O and
  -Onone; values checked from C in xmm registers. No Docker here:
  `tests/e2e/target-app.sh` not run.
- The Mac app window (total `^MISSING`): 4,972 -> 4,964 (`Double`/`Float` metadata
  and descriptors, `Double: Equatable` and `BinaryFloatingPoint`
  conformances, `Double.hash(into:)`,
  `Double(sign:exponentBitPattern:significandBitPattern:)`).

## 2026-11-25: pointers (PR: stdlib-pointers)

- `MemoryLayout`, the `_Pointer` protocol, `UnsafePointer`,
  `UnsafeMutablePointer`, `UnsafeRawPointer`, `UnsafeMutableRawPointer`,
  `OpaquePointer`, `AutoreleasingUnsafeMutablePointer`, the four buffer
  pointers (random-access collections; the mutable ones mutable
  collections), `withUnsafe(Mutable)Pointer`, `withUnsafe(Mutable)Bytes`,
  `Optional.map`/`flatMap`, integer `init(bitPattern:)`, and the
  `Sequence`/`MutableCollection` requirements that mention buffer pointers.
- Typed pointers are declared as plain generics: Apple's are
  `Pointee: ~Copyable` but keep their pre-Swift-6 mangling, which plain
  generics reproduce.
- The compiler allows implicit pointer conversions (`&x`, mutable to
  immutable) only when all pointer types and five conversion intrinsics
  exist (`ASTContext::hasPointerArgumentIntrinsics`). The array and string
  ones are placeholders until Array and String land.
- Runtime: `swift_arrayInitWithCopy`, `...TakeNoAlias/FrontToBack/
  BackToFront`, `swift_arrayAssignWithCopy*`, `swift_arrayAssignWithTake`,
  `swift_arrayDestroy` (new `src/frameworks/swift/array.c`), which the
  compiler emits for bulk pointer operations on non-trivial types.
- `tests/swiftlib/pointers`: copies, overlapping moves and destruction of
  class references checked through deinit counts; buffer sorting and
  slicing; raw loads and stores.
- The Mac app window (total `^MISSING`): 4,964 -> 4,913.

## 2026-11-25: C type names (PR: stdlib-ctypes)

- `CInt`, `CLong`, `CChar`, `CBool`, `CDouble` and the rest of the C type
  aliases. The compiler maps C types to Swift through them, both when
  importing headers and when it needs a C signature (`@_cdecl` functions,
  calls into imported C functions); without them IRGen crashed.
- With them, Swift code compiled for macOS imports our own SDK headers as
  Clang modules and calls into them (tried with CoreFoundation from a
  scratch SDK layout); that is the base for the Swift overlays.
- `tests/swiftlib/cdecl`: `@_cdecl` functions called from C.

## 2026-11-25: our own SDK and the Swift overlays (PR: swift-overlays)

- `build/MacOSX.sdk`: bitten's SDK headers (`sdk/include`) with a Clang
  module map (`sdk/include/module.modulemap`, CoreFoundation for now), so
  Swift code compiled for macOS imports our C and Objective-C modules.
  Swift compilations get a resource directory of our own
  (`build/swift-res`: only the Clang builtin headers and shims), because
  the toolchain's Linux CoreFoundation/Dispatch modules would shadow ours.
- Swift overlays: each `overlays/NAME/*.swift` is built against the SDK
  into `build/root/usr/lib/swift/libswiftNAME.dylib` with its module in
  `build/swift`. First one: CoreFoundation (`_CFObject` through CFHash and
  CFEqual, and `CGFloat`, which keeps its original mangled module
  `CoreGraphics` through `@_originallyDefinedIn`).
- Standard library: `unsafeBitCast`, `unsafeDowncast`, `numericCast`,
  `withExtendedLifetime`, `_fixLifetime`.
- The Mac app window: 8 of its 9 imports from libswiftCoreFoundation now resolve
  (the last, `CGFloat: CVarArg`, needs Array). Total `^MISSING`:
  4,913 -> 4,905.

## 2026-11-25: resume notes rewritten (PR: next-notes)

`docs/NEXT.md` now describes the Swift state (runtime done, standard
library in progress, overlays and our own SDK), the three kinds of Swift
tests, how the standard library is matched to Apple's by declaration, the
work in flight, and what comes after it (Foundation's Swift surface, then
SwiftUI with AppKit and the drawing stack).

## 2026-11-25: String, part 1: the representation (PR: stdlib-string)

- `stdlib/StringObject.swift`: `_StringObject` (count-and-flags word plus a
  `Builtin.BridgeObject`), `_StringGuts`, and the native storage class
  `__StringStorage` (header, real capacity, count and flags, UTF-8 at
  offset 32 followed by a NUL). The bit layout is Apple's x86-64 one, read
  off compiled code: small strings inline up to 15 bytes with discriminator
  `0xE0|n` (ASCII) or `0xA0|n` in the top byte, empty is
  `(0, 0xE000_0000_0000_0000)`; literals are `(0xD000_0000_0000_0000|n,
  0x8000_0000_0000_0000|(address-32))` (`0x1000...|n` when not ASCII);
  native strings `(0xF000...|n` or `0x3000...|n, storage pointer)`.
  Verified both ways: The Mac app's code builds literals with exactly these
  constants (`0xD000000000000011` with a pointer 32 bytes before the bytes,
  `0xE000000000000000` for "", `0xE4...` for 4-byte literals), and our -O
  test code folds its literals into the same constants.
- `stdlib/String.swift`: literals (small or immortal, inlinable so the
  optimizer constant-folds them), `+`, `+=`, `append`, `reserveCapacity`
  with copy on write (`swift_isUniquelyReferenced_nonNull_native` on the
  storage), `==`/`<` through Apple's entry points
  `_stringCompareWithSmolCheck` / `_stringCompareInternal`, hashing (UTF-8
  then 0xFF), `init(cString:)` (both), `init?(validatingCString:)`,
  `withCString` (literals and native strings are already NUL-terminated),
  `String(repeating:count:)`, `init(unsafeUninitializedCapacity:...)`,
  `hasPrefix`/`hasSuffix`, `lowercased`/`uppercased` (ASCII and Latin-1 for
  now), and the internal entry points the Mac app imports (`_StringGuts.grow`,
  `_uncheckedFromUTF8`, `_fromUTF8Repairing`, `_StringObject.sharedUTF8`).
  `stdlib/UTF8.swift`: validation (RFC 3629) and repair with U+FFFD per
  maximal subpart.
- `_convertConstStringToUTF8PointerArgument` is real: it passes the bytes
  of literals and native strings directly and copies small ones.
- Output protocols (`TextOutputStream`, `TextOutputStreamable`,
  `CustomStringConvertible`, `CustomDebugStringConvertible`,
  `LosslessStringConvertible`) with String's conformances; `fatalError`,
  `precondition`, `preconditionFailure`, `assert`, `assertionFailure` and the
  two `_assertionFailure` entry points with a String message.
- Approximations, to be replaced by tables generated from the UCD: strings
  that are not known NFC (non-ASCII ones) compare and hash by their bytes
  rather than by canonical equivalence. Shared and foreign (bridged)
  representations trap.
- `tests/swiftlib/strings`: the layout word by word, literals small, large
  and non-ASCII, copy on write, comparison, hashing, C strings both ways.
  Suite 41/41 at -O and -Onone. No Docker here: `tests/e2e/target-app.sh` not run.
- The Mac app window (total `^MISSING`): 4,905 -> 4,866.

## 2026-11-25: standard library: Array, ContiguousArray, ArraySlice (PR: stdlib-array)

- Apple's representation on Darwin, checked against the code swiftc inlines
  into our tests and against the Mac app's own inlined array code: `Array` is one
  `Builtin.BridgeObject` (`_ArrayBuffer` / `_BridgeStorage<__ContiguousArrayStorageBase>`):
  native storage, bit 62 for an NSArray, bit 1 for native storage whose
  elements still need a type check (both sides test `0xC000000000000003`
  for "native and type-checked", mask the pointer with
  `0x00FFFFFFFFFFFFF8`). `ContiguousArray` is one storage reference;
  `ArraySlice` is {owner, subscript base address, startIndex,
  endIndex << 1 | native}. Storage is a tail-allocated `@_fixed_layout`
  class: count at +16, capacity << 1 | bridgedVerbatim at +24, elements at
  +32. The empty array is the runtime's immortal `_swiftEmptyArrayStorage`
  (array.c), whose isa is set to the stdlib's `__EmptyArrayStorage` when
  libswiftCore loads; Swift takes its address as a thin function value
  with that symbol name. `__StaticArrayStorage` exists for constant arrays.
- The mutation entry points programs inline and call keep Apple's names
  and meanings (`_makeUniqueAndReserveCapacityIfNotUnique`,
  `_reserveCapacityAssumingUniqueBuffer`, `_appendElementAssumeUniqueAndCapacity`,
  `_createNewBuffer`, `_consumeAndCreateNew`, `_getElementSlowPath`,
  `_typeCheckSlowPath`, `_adoptStorage`, `_allocateUninitialized`...),
  with the `AnyObject` pre-specializations (`@_specialize(exported:)`,
  `...yXl_Ts5`) the Mac app binds to.
- Array literals (`_allocateUninitializedArray`, `_finalizeUninitializedArray`,
  `_deallocateUninitializedArray`), `ExpressibleByArrayLiteral`, the real
  array-to-pointer conversions, `Sequence._copyToContiguousArray` (new
  requirement), `Array(seq)`, append/insert/remove/replaceSubrange/
  reserveCapacity/removeAll with copy on write, `withUnsafe(Mutable)BufferPointer`,
  the collection conformances, conditional Equatable/Hashable,
  `isKnownUniquelyReferenced`, `swap`. NSArray bridging traps
  (`_CocoaArrayWrapper`); the representation leaves room for it.
- Build: the stdlib is compiled with `-enforce-exclusivity=unchecked`, as
  Apple's is; otherwise every inlined access to array storage called
  `swift_beginAccess`.
- Runtime: generic value metadata patterns reference their value witness
  table through an indirectable pointer (a builtin type's table in another
  image: `[Int]`'s is `$sBbWV`), which was read as direct; new
  `swift_getObjectType`, `swift_lookUpClassMethod` (resilient classes'
  `CMu`), `swift_bufferAllocate`, `swift_isClassType`,
  `_swift_isClassOrObjCExistentialType`.
- `tests/swiftlib/arrays`: layout word by word, literals, mutation, COW,
  slices, class elements with deinit counts, generic structs, C pointer
  arguments, generic use at -Onone. No Docker here: `tests/e2e/target-app.sh` not
  run.
- The Mac app window (total `^MISSING`): 4,866 -> 4,776.
## 2026-11-25: Dictionary and Set, part 1: storage, hash table, core API (PR: stdlib-dictionary)

- Apple's Darwin representation: `Dictionary`/`Set` are one word, a
  `_BridgeStorage` (new, with the Builtin.BridgeObject helpers, `_isUnique`,
  `swap`) of native storage or a bridged NS collection. Native storage is
  `__RawDictionaryStorage`/`_DictionaryStorage<K,V>` (and the Set pair):
  count +16, capacity +24, scale +32, reservedScale +33, extra +34, age +36,
  seed +40, keys/elements +48, values +56, then the bitmap (+64 / +56), keys,
  values, all tail-allocated. Offsets checked against the Mac app's inlined lookups
  (`movb 0x20(%r14)`, bitmap at `0x40(%r14,...)`, keys `0x30`) and from C in
  the test, which walks storage and probes exactly like inlined code.
- `_HashTable` (+`_UnsafeBitset`): open addressing, linear probing,
  backward-shift deletion (no tombstones); in tables under 64 buckets the
  bitmap bits past the end stay set, which ends inlined iteration and hole
  searches. Max load 3/4; per-storage seed from the storage address
  (scale under deterministic hashing).
- `_swiftEmptyDictionarySingleton` / `_swiftEmptySetSingleton`: immortal C
  objects in `stdlib/GlobalObjects.c` (now linked into libswiftCore) whose
  isa is the Swift class `__EmptyDictionarySingleton` / `__EmptySetSingleton`.
- `_NativeDictionary`/`_NativeSet` with every entry point the Mac app imports
  (`_insert`, `_delete`, `mutatingFind`, `ensureUnique`, `uncheckedRemove`,
  `_unsafeInsertNew`, storage `allocate`/`copy`/`resize`...). Cocoa halves
  (`__CocoaDictionary`, `__CocoaSet` with Index/Iterator) are declared with
  Apple's shapes and trap until bridging exists.
- API: subscripts (incl. `default:`), `updateValue`, `removeValue`,
  `index(forKey:)`, `remove(at:)`, `popFirst`, `keys`/`values` views,
  iteration, `init(uniqueKeysWithValues:)`, `init(_:uniquingKeysWith:)`,
  `merge`/`merging`, `mapValues`, `compactMapValues`, `filter`,
  `reserveCapacity`, `removeAll`, Equatable/Hashable; Set insert/update/
  remove/contains, `Set(seq)`, union/intersection/subtracting/
  symmetricDifference and the subset/superset/disjoint tests;
  `_DictionaryBuilder`/`_SetBuilder`. Copy-on-write throughout.
- Waiting for Array: literals, `SetAlgebra` (refines
  ExpressibleByArrayLiteral), `init(grouping:by:)`; for Error: `_MergeError`;
  for printing: `description`.
- Runtime fixes found on the way: `swift_lookUpClassMethod` (method lookup
  functions of classes in resilient modules); metadata for
  `Builtin.NativeObject/UnknownObject/BridgeObject` (`$sBoN`, `$sBON`,
  `$sBbN`); the value-witness pointer of a generic value metadata pattern is
  indirectable (`$sBbWV` from another image came through the GOT and was used
  as the table itself). `_assumeNonNegative` for the signed integers.
- `tests/swiftlib/dictionaries`: trivial, colliding and class keys/values
  with exact deinit counts, 2000-element insert/remove rounds, churn at
  constant size, COW, iteration order stability, the views, set algebra.
  No Docker here: `tests/e2e/target-app.sh` not run.
- The Mac app window (total `^MISSING`): 4,866 -> 4,738. Left from this area:
  literals, SetAlgebra, Codable, `description`.
## 2026-11-25: Swift Concurrency, part 1: the async runtime and _Concurrency (PR: conc-runtime)

- `src/frameworks/concurrency/` (C, built with clang: functions with the
  `swiftasync` convention, async context in r14, error/self in r13 and
  guaranteed tail calls, cannot be written for gcc; the Makefile has a clang
  rule for this directory):
  - `task.c`: `swift_task_create` (async function pointer, option records
    for the initial executor, task groups and async let; priority, child,
    copy-task-locals, enqueue and discarding flags), one allocation holding
    the task, its result and its initial context; the per-task LIFO slab
    allocator (`swift_task_alloc/dealloc`, `_dealloc_through`,
    `swift_job_allocate`); futures (`swift_task_future_wait`,
    `_throwing`, direct-continuation convention); cancellation with
    handler records and child propagation; continuations
    (`swift_continuation_init/await/resume/throwingResume*`);
    `swift_task_switch`; task-local values; current task/priorities.
  - `executor.c`: the generic executor on our libdispatch's global queues,
    the main executor on the main queue (`swift_task_asyncMainDrainQueue` is
    `dispatch_main`), default actors (a FIFO in the actor's 12 private words,
    drained on the global queues in batches), custom `SerialExecutor`s through
    a Swift helper found by name, `swift_job_run`, delayed and deadline
    enqueues, clocks, `isCurrentExecutor`/`checkIsolated`/unexpected-executor
    reports (warn and continue, as macOS does in Swift 5 mode).
  - `group.c`: task groups (`swift_taskGroup_*`, `wait_next_throwing`,
    `waitAll`) and async let (`swift_asyncLet_begin/get/get_throwing/finish`).
- ABI checked against swiftc 6.3 output: Job is 64 bytes (run function at
  56), the task's resume context at 64 (compiled code reads it to store a
  continuation's result), continuation contexts `{parent, resume, flags,
  await state, error, result pointer, executor}`, `swift_continuation_await`
  takes its context in rdi (not r14), non-throwing task closures reach the
  completion with r13 zeroed by their thunk, the special waiting functions
  get (caller context, ..., resume function, 40-byte scratch context).
  `swift_async_extendedFramePointerFlags` is weak-imported and left
  unresolved so it binds to 0.
- `overlays/_Concurrency/` (our own Swift, module `_Concurrency`, which
  mangles as `Swift`): `Actor`, `Executor`, `SerialExecutor`,
  `TaskExecutor`, `UnownedSerialExecutor`, `UnownedJob`/`Job`/`ExecutorJob`,
  `JobPriority`, `GlobalActor`, `MainActor`, `Task` (init/detached, value,
  result, cancel, yield, isCancelled, checkCancellation, priorities),
  `TaskPriority`, `CancellationError`, `withTaskCancellationHandler`,
  `UnsafeCurrentTask`, `UnsafeContinuation`, `CheckedContinuation` (a cell
  in the runtime catches double resumes and leaks; the `function: String`
  initializer is still to come), `withUnsafe/CheckedContinuation`
  (+throwing). `swift_task_getCurrent` returns +0: Swift callers retain.
- Swift tests now import `_Concurrency` implicitly; `tests/swiftlib/async`
  starts a task from C and runs the main queue: futures, typed errors,
  continuations resumed from dispatch threads, 100 tasks racing on an actor,
  `@MainActor` state from detached tasks, cancellation.
- Also needed: `stdlib/Error.swift` (`Error`, `Result`, the `try!`/error-in-main
  entry points), `swift_getObjectType`, `swift_lookUpClassMethod`.
- No Docker here: `tests/e2e/target-app.sh` not run.
- The Mac app window (total `^MISSING`): BEFORE -> AFTER.

## 2026-11-25: key paths (PR: stdlib-keypaths)

- `AnyKeyPath` (Hashable), `PartialKeyPath`, `KeyPath`, `WritableKeyPath`,
  `ReferenceWritableKeyPath` in `stdlib/KeyPath.swift`, with `appending(path:)`
  (every overload), `rootType`/`valueType`, and the projection entry points
  the compiler calls for `root[keyPath:]`: `swift_getAtKeyPath`,
  `swift_setAt(Reference)WritableKeyPath`, `swift_getAt(Partial|Any)KeyPath`.
- Runtime (`src/frameworks/swift/keypath.c`): `swift_getKeyPath` instantiates
  the compiler's patterns into a key path object (the library class plus a
  private buffer of components): stored struct/class/tuple fields (inline,
  out of line, unresolved through metadata or a field offset global),
  computed properties and subscripts with captured arguments (layout,
  initializer and copy/destroy/equals/hash witnesses), optional
  chain/force/wrap, generic environments, external property descriptors, and
  the once-cache (immortal object). The yield-once coroutines
  `swift_readAtKeyPath` and `swift_modify*AtKeyPath` and the Swift entry
  points share one projection engine: steps up to the last one through a
  reference are only read, computed steps after it are written back in
  reverse. `swift_copyKeyPathTrivialIndices`. Getters return indirectly in
  rax, so `callconv.S` gained `sw_call_indirect`.
- `type(of:)` and `_openExistential` declared (resolved by the type checker,
  but they must exist).
- Fix: a generic subclass copied each ancestor's vtable from that ancestor's
  own metadata, losing intermediate overrides (WritableKeyPath lost
  KeyPath's override of `_rootAndValueType`); everything now comes from the
  immediate superclass.
- `tests/swiftlib/keypaths`: structs, tuples, classes and inherited fields,
  nested paths, optional chaining and force, identity, key paths as
  functions, computed properties, subscripts with trivial and class
  arguments (released with the key path), nonmutating setters, generic
  contexts, an external generic descriptor (`UnsafeMutablePointer.pointee`),
  equality/hash, kinds, appending; at -O and -Onone. No Docker here:
  `tests/e2e/target-app.sh` not run.
- The Mac app window (total `^MISSING`): 4,561 -> 4,548 (every libswiftCore key path
  symbol it imports).

## 2026-11-25: String, part 2: Unicode, Characters, views, Substring (PR: stdlib-string-2)

- `tools/gen-unicode.py` generates `stdlib/UnicodeData.swift` from the
  Unicode 16.0 UCD (grapheme break, extended pictographic, canonical
  decomposition/composition, combining classes, case mappings incl.
  SpecialCasing), packed into string literals that
  `stdlib/UnicodeTables.swift` decodes on first use.
- Strings now compare and hash by canonical equivalence (NFC), replacing
  part 1's byte comparison for non-ASCII strings; `lowercased`/`uppercased`
  use the full tables (ß, Greek, ligatures).
- `Character` and the character view: extended grapheme clusters (UAX #29,
  incl. emoji ZWJ sequences, regional-indicator pairs, Indic conjuncts),
  `String.Index` with Apple's bit layout (encoded offset, transcoded offset,
  cached character stride), bidirectional indexing, `RangeReplaceableCollection`
  (insert, remove, removeSubrange, append of Characters).
- Views: `utf8`, `utf16` (with surrogate positions), `unicodeScalars`
  (mutable), each a `BidirectionalCollection` sharing `String.Index`.
- `Substring` with its views, hashing equal to the String's, conversions.
- `tests/swiftlib/strings`: canonical equivalence, cluster counts, indices
  both ways, the three views, substrings, mutation, case beyond Latin-1.
  Suite 45/45 at -O and -Onone. No Docker here: `tests/e2e/target-app.sh` not run.
- The Mac app window (total `^MISSING`): 4,548 -> 4,468.

## 2026-11-25: SDK headers for the C library, the Darwin and ObjectiveC overlays (PR: sdk-darwin-objc)

- `sdk/include`: the C library headers Swift code imports (stdio, stdlib,
  string, unistd, fcntl, sys/*, signal, pthread, netdb, netinet, termios,
  locale, math, dlfcn, spawn, poll, ...) with Apple's declarations, and a
  `module.modulemap` splitting them into Apple's modules: `Darwin` with its
  submodules, `_errno`, `_signal`, `ObjectiveC`. Variadic calls get
  fixed-argument inline helpers (`__bitten_open`, `__bitten_fcntl`, ...).
- Overlays: `Darwin` (file mode constants as `mode_t`, the variadic `open`,
  `openat`, `fcntl`, `ioctl` forms, `stdin`/`stdout`/`stderr`,
  `DarwinBoolean`); `_errno` (`errno`, `POSIXErrorCode`) and `_signal`
  (`SIG_DFL`, `SIG_IGN`, `SIG_HOLD`, `SIG_ERR`), declared
  `@_originallyDefinedIn(module: "Darwin", macOS 14.0)` as Apple does, so
  they keep Darwin's mangling; `ObjectiveC` (`ObjCBool`, `Selector`,
  `NSZone`, NSObject's Equatable/Hashable through `-isEqual:`/`-hash`).
  The Makefile builds overlays in dependency order (`OVERLAY_DEPS_NAME`).
- `RawRepresentable` in the stdlib (raw-value enums and imported C enums).
- Pitfall: `@_originallyDefinedIn(..., macOS 9999)` makes swift-frontend
  emit an `$ld$hide$os<v>$` directive for every version up to 9999 and run
  out of memory (it took the machine down); use the real version.
- Those `$ld$hide` directives hide the moved symbols from targets below
  macOS 14, so a swiftlib test can name a deployment target
  (`SWLIB_MACOS_NAME`); `tests/swiftlib/darwin` uses 14.0. The Mac app targets 14+
  and binds to `libswift_errno`/`libswift_signal` directly.
- `objc/objc.h`: `sel_registerName` and friends gained Apple's
  nullability (without it `SEL` imports as `Selector?`).
- `tests/swiftlib/darwin`: getpid/strlen, errno and POSIXErrorCode, open
  with mode, fcntl, write/fstat, signal with SIG_IGN, DarwinBoolean,
  ObjCBool, Selector equality/hash/name. Suite 46/46 at -O and -Onone. No
  Docker here: `tests/e2e/target-app.sh` not run.
- The Mac app window (total `^MISSING`): 4,468 -> 4,432.

## 2026-11-25: String, part 3: printing, interpolation, descriptions (PR: stdlib-string-3)

- `stdlib/Print.swift`: `print`/`debugPrint` (to stdout and to any
  `TextOutputStream`), `_print_unlocked`/`_debugPrint_unlocked` (Optionals
  through their debugDescription, then TextOutputStreamable, description,
  debugDescription), `String(describing:)`, `String(reflecting:)`,
  `String(_: LosslessStringConvertible)`, `_typeName`.
- `stdlib/StringInterpolation.swift`: `StringInterpolationProtocol`,
  `ExpressibleByStringInterpolation`, `DefaultStringInterpolation` (Apple's
  one-String layout; programs inline it), String and Substring literals.
- `stdlib/Descriptions.swift`: `BinaryInteger.description` and
  `String(_:radix:uppercase:)`, `FixedWidthInteger.init?(_: String)`;
  Float/Double/Float80 description, debugDescription, `write(to:)`,
  `init?(_: String)` and `init?(_: Substring)`; Bool; Optional's
  debugDescription; Array, ContiguousArray, ArraySlice, Set, Dictionary
  ("[k: v]", "[:]"); Range/ClosedRange; String, Substring, Character and
  Unicode.Scalar debug text (`escaped(asASCII:)`); StaticString; AnyHashable.
- `stdlib/StringProtocol.swift`: `StringProtocol` (the requirements used so
  far; the protocol is resilient) with String and Substring, `joined(separator:)`
  over StringProtocol sequences and over String bidirectional collections.
- `ExpressibleByDictionaryLiteral` and Dictionary's literal init;
  `_OptionalNilComparisonType` (`x == nil` for non-Equatable wrapped types
  did not compile before). BinaryInteger now refines CustomStringConvertible
  and FixedWidthInteger LosslessStringConvertible, as Apple's do.
- Runtime: `src/frameworks/swift/format.c` with Apple's entry points
  `swift_float{32,64,80}ToString` (shortest round-trip digits, Swift's
  decimal/exponential switch at 1e-4 and 2^24/2^53/2^64, "inf", "nan",
  debug NaN payloads), `swift_{u,}int64ToString`,
  `_swift_stdlib_strto{f,d,ld}_clocale`; `swift_getDynamicType` in casts.c.
- Approximation until Mirror exists: a value with no description protocol
  prints its type name (qualified for classes), not Apple's
  "Point(x: 1, y: 2)" or enum case name.
- `tests/swiftlib/printing`: integers (all widths, radix, parsing), floats
  (shortest digits, both notations, specials, parsing), Optional,
  collections, ranges, escaping, interpolation, print to a string and to
  stdout. Suite 47/47 at -O and -Onone. No Docker here: `tests/e2e/target-app.sh`
  not run.
- The Mac app window (total `^MISSING`): 4,432 -> 4,392.

## 2026-11-25: SetAlgebra and OptionSet (PR: stdlib-setalgebra)

- `stdlib/SetAlgebra.swift`: `SetAlgebra` with Apple's requirements
  (including which arguments are `__owned`: that is in the method
  descriptors programs bind to) and its default implementations;
  `OptionSet` with the defaults for `Element == Self` and for
  FixedWidthInteger raw values (what NS_OPTIONS types and Swift option sets
  use); Set conforms to SetAlgebra (the four same-type operations it lacked
  were added).
- `tests/swiftlib/optionsets`: a Swift option set (literals, insert, remove,
  update, the algebra), generic SetAlgebra code over an option set and over
  Set. Suite 48/48 at -O and -Onone. No Docker here: `tests/e2e/target-app.sh` not
  run.
- The Mac app window (total `^MISSING`): 4,392 -> 4,358.

## 2026-11-25: AppKit, first part; CoreGraphics geometry; dispatch header (PR: appkit-skeleton)

- `frameworks/AppKit`: AppKit as an Objective-C Mach-O framework like
  Foundation. Every class the Mac app links against exists in its place in the
  hierarchy (the table in `tools/gen-appkit.py` generates the skeleton and
  `sdk/include/AppKit/AppKitClasses.h`), with every exported constant at
  its documented value. Hand-written: NSResponder (responder chain),
  NSView (hierarchy, frames/bounds, display pass, coordinate conversion,
  hit testing), NSControl, NSWindow (content view, title bar geometry,
  ordering, key window, resize notifications), NSApplication (delegate
  life cycle, activation, `run` handing the main thread to the main
  dispatch queue, terminate), NSEvent, NSColor, NSFont, NSScreen
  (`BITTEN_SCREEN=WxH`), NSGraphicsContext, NSMenu/NSMenuItem.
- CoreGraphics geometry in `mrun` (`src/frameworks/coregraphics`): CGRect
  arithmetic with null/infinite rectangles, affine transforms; headers in
  `sdk/include/CoreGraphics`. Foundation's header now takes CGFloat and the
  NS geometry types from there.
- SDK: `NS_ENUM`/`NS_OPTIONS`/`NS_SWIFT_NAME` with the attributes the Swift
  importer reads; `dispatch/dispatch.h` (C interface); Clang modules for
  CoreGraphics, Foundation and AppKit, so Swift code can `import AppKit`.
- `tests/appkit/basics`: application and delegate, windows, view
  hierarchy, hit testing, conversion, display passes.
- The Mac app window (total `^MISSING`): 4,358 -> 4,099; every Objective-C AppKit
  import resolves (the rest are AppKit's Swift extensions).

## 2026-11-25: Combine, Observation, the CoreGraphics overlay; Swift frameworks (PR: combine-observation)

- Frameworks written in Swift: `frameworks/NAME/*.swift` builds into
  `NAME.framework/Versions/A/NAME` (module in `build/swift`), against the
  SDK, every overlay, Foundation and AppKit; `SWIFT_FW_DEPS_NAME` orders
  and links frameworks that import each other.
- Combine (`frameworks/Combine`): Publisher/Subscriber/Subscription,
  demand, `Sink`, `AnyCancellable`, subjects, `AnyPublisher`, `Just`,
  `Map`/`Drop`/`ReceiveOn`/`MergeMany`/`Autoconnect`, schedulers,
  `ObservableObject` with its per-object `objectWillChange` publisher, and
  `@Published` (with the enclosing-instance subscript the compiler uses
  for class properties). Synchronous delivery.
- Observation (`overlays/Observation`, libswiftObservation):
  `ObservationRegistrar` and `withObservationTracking`: reads are recorded
  per (object, key path) while tracking; the first write to any of them
  calls `onChange` once.
- CoreGraphics overlay: the importer maps the C `CGFloat` typedef to the
  Swift `CGFloat` it finds in a Swift module named CoreGraphics; this
  overlay re-exports the C module and the CoreFoundation overlay's
  `CGFloat`, so `CGSize.width` and friends are CGFloat in Swift.
- The Mac app window (total `^MISSING`): 4,099 -> 4,060 (all Combine and
  Observation imports resolve).

## 2026-11-25: Codable; map/filter/sorted; string switches (PR: stdlib-codable)

- Codable (generated by `tools/gen-codable.py`): `Encodable`, `Decodable`,
  `CodingKey`, `CodingUserInfoKey`, `Encoder`/`Decoder`, the keyed,
  unkeyed and single-value container protocols with every per-type
  overload, the type-erasing `KeyedEncodingContainer` and
  `KeyedDecodingContainer`, `EncodingError`/`DecodingError`, and the
  conformances of the primitives, Optional, Array, ContiguousArray, Set,
  Dictionary (String/Int keys keyed, others as pairs) and RawRepresentable
  (generic and the concrete raw types programs bind to).
- The array-returning sequence operations were missing (the Array work's
  second part was lost in an interrupted session): `map`, `filter`,
  `compactMap`, `flatMap`, `sorted`, `reversed`, `split`, `joined`, with
  the `rethrows` forms programs bind to.
- Metatype equality (`T.self == Int.self`), substring `contains` and
  `range(of:)`, and the string-switch intrinsics `_findStringSwitchCase`
  (+WithCache) that `switch` over strings and String-backed enums need
  (without them the compiler crashed).
- `tests/swiftlib/codable`: synthesized conformances round-tripped through
  a tree encoder/decoder written in the test.
- The Mac app window (total `^MISSING`): 4,060 -> 3,927.

## 2026-11-25: progress chart (PR: progress-chart)

- `tools/progress.py`: counts the Mac app window's imports (Contents/MacOS/App
  and Sparkle, with `llvm-nm -m -u`) per area, takes what is still missing
  from `mrun --check`, reads the layer states from `docs/ROADMAP.md`, and
  draws `progress.svg` (light and dark) with the history in `history.csv`.
  `backfill` seeds the history from the "the Mac app window" lines of this log,
  one point per merged change.
- `tools/progress-update.sh`: for cron on a machine with App.dmg. When
  `main` moves it builds a clean checkout (`nice`, `make -j2`, skipped
  when memory is short), measures, and pushes the chart to the `progress`
  branch, which the README shows. Nothing from the image is published.
- ROADMAP: layers 13, 14 and 16 are in progress (CoreGraphics geometry,
  AppKit, Combine and Observation), no longer "not started".
- The Mac app window (total `^MISSING`): 3,927 (unchanged).
## 2026-11-25: SwiftUI begins; Foundation's Swift overlay; os logging (PR: swiftui-start)

Driven by running the Mac app; it now gets through its app struct's metadata, the
delegate adaptor, its LazyState/StateObject properties, clocks and logging
and stops at Foundation's `URL` (3,724 unimplemented imports, from 3,927).

- SwiftUI (`frameworks/SwiftUI`): `View`/`Scene`/`App`, the result builders,
  `TupleView`, `_ConditionalContent`, `EmptyView`, `AnyView`, the property
  wrappers with Apple's frozen layouts where programs initialise them inline
  (`State`, `Binding`, `StateObject`, `ObservedObject`) and `LazyState`,
  `NSApplicationDelegateAdaptor`, `WindowGroup`/`Window`/`Settings`/
  `_TupleScene`, and `App.main()` driving NSApplication through a host that
  walks scene tuples via tuple metadata. Rendering comes with CoreGraphics.
- Foundation's Swift overlay, linked into Foundation.framework as on macOS
  (`frameworks/Foundation/swift`): String/Substring/Array/Dictionary/Set/
  Int/Double/Bool bridging. The stdlib gains `_ObjectiveCBridgeable` and the
  compiler's bridging entry points; Foundation's header marks NSString,
  NSArray, NSDictionary, NSSet with `swift_bridge("Swift.T")` (what Apple's
  API notes do) and uses assume-nonnull regions, so imported APIs read as
  Swift types with Apple's optionality.
- AppKit header fixes for faithful import: assume-nonnull, class properties
  (`NSApplication.shared`), `NS_OPTIONS` style masks.
- CGFloat is now a full `BinaryFloatingPoint` forwarding to Double, with the
  conversions both ways (the compiler's implicit CGFloat/Double conversion
  needs them).
- Standard library: `Duration`, `DurationProtocol`, `InstantProtocol`,
  `Unmanaged`, `CVarArg`/`CVaListPointer`, `multipliedFullWidth`.
- `_Concurrency`: `Clock`, `ContinuousClock`, `SuspendingClock`, their
  Instants, `Task.sleep(for:/until:/nanoseconds:)`.
- os: headers with the OS-object model Swift expects (os_log_t is the class
  OS_os_log, `OSLog` in Swift), `os_log_create`, `_os_log_impl` (formats
  Apple's argument buffer; errors/faults to stderr, all levels with
  `BITTEN_LOG=1`), signposts; the `os` overlay (`Logger`, `OSSignposter`,
  `OSSignpostID`, log type constants). The OS_os_log class lives in exported
  storage (`dx_os_object_class_in`) because Swift refers to it by symbol.
- Runtime/loader: `swift_dynamicCastUnknownClass(Unconditional)`;
  `___chkstk_darwin` (stack probe, assembly); unimplemented-import stubs
  now build an aligned frame (tail-called stubs crashed inside the error
  report).

## 2026-11-25: the target app, unnamed

- The project no longer names its yardstick app anywhere: it is "the target
  app" (a terminal app shipped as `App.dmg`). History was rewritten to
  match; `docs/TARGET-APP.md`, `examples/mac-terminal` and
  `tests/e2e/target-app.sh` are the renamed files.
- `examples/mac-terminal` and the e2e test take the app's command-line
  program from `APPCLI` instead of a built-in name.
- `tools/progress.py` finds the app's main executable from its
  `Info.plist` (`CFBundleExecutable`) and counts the frameworks it bundles,
  so it works for any `.app`; `progress-update.sh` takes `TARGET_APP`.

## 2026-11-25: bundles, user defaults, property lists

- Foundation: `NSPropertyListSerialization` (XML and binary `bplist00`
  reading, XML writing), `NSBundle` (main bundle from the executable's
  `.app`; `Contents/` and flat layouts, so SwiftPM resource bundles work;
  Info.plist, resources, `.strings` tables in text or plist form),
  `NSUserDefaults` (argument, app, suite, global and registration domains,
  saved under `~/Library/Preferences`; no KVO yet), standard directories
  (`NSSearchPathForDirectoriesInDomains`, `URLsForDirectory:inDomains:`,
  `URLForDirectory:...`) and URL forms of the file operations.
- Foundation Swift overlay: `URL`, `UUID`; re-exports Darwin.
- stdlib: `Unicode.UTF8/UTF16/UTF32`, `String(decoding:as:)`,
  `FixedWidthInteger.init?(_:radix:)`, `Collection.split`, generic `+`
  for range-replaceable collections.
- `@[]` and `@{}` were the `__NSCFArray`/`__NSCFDictionary` class objects:
  clang loads `___NSArray0__` as an `id` variable, so the symbol now points
  at the empty collection instead of being it.
- Loader: a symbol a system library lacks is looked up in the other loaded
  system images (apps bind `NSUserDefaults` to CoreFoundation); classes
  nobody provides get a placeholder class whose messages report "class X is
  not implemented in bitten yet" instead of crashing in a stub.
- Target app window (total `^MISSING`): 3,724 -> 3,658. It now runs past
  user defaults, bundles and UUIDs and stops at `Synchronization.Mutex`.

## 2026-11-25: progress chart, simplified (PR: progress-simple)

- The README chart is now one simple picture: the share of the target
  app's imports implemented, and one bar per area. The history is still
  recorded in `history.csv` on the `progress` branch but no longer drawn.

## 2026-11-25: progress chart as a ring (PR: progress-ring)

- The README chart is a single progress ring: the share of the target
  app's imports implemented, with the counts beside it. Light and dark.

## 2026-11-25: progress ring by area (PR: progress-ring-areas)

- The ring's filled arc is split into one coloured segment per area (its
  implemented imports as a share of all of them), with a legend of each
  area's own progress beside it. No grey: open work is a pale blue.

## 2026-11-25: Synchronization, CharacterSet, String's Foundation API

- New overlay `Synchronization`: `Mutex`, `_MutexHandle`, `_Cell` and
  `Atomic` with Apple's raw layouts (programs inline their operations, so
  only metadata comes from the library). `os/lock.h` (`os_unfair_lock`) in
  the SDK; runtime gains `swift_copyPOD` and
  `swift_runtimeSupportsNoncopyableTypes`; stdlib gains `BitwiseCopyable`.
- Foundation's Swift overlay: `CharacterSet` (sorted scalar ranges;
  predefined sets from NSCharacterSet; SetAlgebra), `Locale` (identifier,
  current from the environment), `String.Encoding`, `String(format:)`,
  `String.CompareOptions`/`ComparisonResult`, and StringProtocol's
  Foundation methods: `components(separatedBy:)`, `trimmingCharacters`,
  `replacingOccurrences`, `range(of:options:range:locale:)`, the compare
  family (numeric and case-insensitive), percent encoding, `capitalized`.
  NSObject, String and Substring are `CVarArg` (as objects for `%@`).
- stdlib: `withVaList`/`getVaList` build an x86-64 va_list.
- Headers: `NSStringCompareOptions` and `NSComparisonResult` are proper
  NS_OPTIONS/NS_ENUM types with Apple's Swift names.
- Tests: `tests/swiftlib/foundation` (swiftlib tests can now link
  frameworks via `SWLIB_LIBS_<name>`).
- Target app window (total `^MISSING`): 3,658 -> 3,613. It now stops at
  `JSONEncoder`.

## 2026-11-25: progress ring, "working on now" and an estimate (PR: progress-now)

- The area the most recent change moved is "working on now": its ring
  segment, legend row and a band under the ring get a soft glow, with the
  imports it gained in the last 24 hours.
- A rough estimate of the time left, from the pace of the last three days
  of history; it says so when there is too little history.

## 2026-11-25: progress ring, compact "now" marker (PR: progress-now-compact)

- The "working on now" band is gone: the current area gets a glowing dot
  and a small NOW tag in the legend, its last-day gain and the estimate
  are one line each under the legend, and the glow is 40% brighter.

## 2026-11-25: progress ring colours (PR: progress-colors)

- Warmer palette, the same hue for an area in light and dark; no NOW tag
  or glowing ring segment any more: the current area only has a soft glow
  behind its dot, and the line under the legend names it.

## 2026-11-25: progress ring footer (PR: progress-timestamp)

- No estimate any more; the update time is a plain timestamp in the
  bottom-left corner.

## 2026-11-25: progress ring, no "now" marker (PR: progress-no-now)

- The current-area marker and its line are gone; the card is the ring,
  the legend and a timestamp.

## 2026-11-25: progress ring, glow back (PR: progress-glow-back)

- The soft glow behind the current area's legend dot is back; only the
  "now" line of text stays removed.

## 2026-11-25: Data

- Foundation's Swift overlay: `Data`, written to Apple's declared shape
  because programs inline it: @frozen, 16 bytes, a @frozen
  `_Representation` (`empty`, `inline` of 14 bytes, `slice` with Int32
  bounds, `large` with a boxed range) over `__DataStorage`, whose fields
  inlined code reaches only through accessors. Mutation, slicing (indices
  kept), the 32-byte-block `Iterator`, base64, files (atomic writes),
  search, Codable, NSData bridging. `DataProtocol`, `MutableDataProtocol`
  and `ContiguousBytes` with Apple's requirement order, and the standard
  library's buffers and arrays conforming.
- `String`/`StringProtocol`: `data(using:)`, `init?(data:encoding:)`,
  `init?(bytes:encoding:)`, `init(contentsOf:encoding:)`, `write(to:...)`.
- Errors: `NSError: Error`, and the compiler's `_convertErrorToNSError` /
  `_convertNSErrorToError` (for `as NSError`).
- Headers: the NSData option types are NS_OPTIONS with Apple's Swift names.
- stdlib: `Unsafe(Mutable)(Raw)BufferPointer(rebasing:)`.
- Target app window (total `^MISSING`): 3,613 -> 3,522. It still stops at
  `JSONEncoder` (next).

## 2026-11-26: CryptoKit (PR: cryptokit)

- `frameworks/CryptoKit`: CryptoKit as a Swift framework. Hashing (`Digest`,
  `HashFunction`, SHA256/384/512, `Insecure.SHA1`/`MD5`) over CommonCrypto's
  digests, `SymmetricKey`, `SharedSecret`, AES-GCM (`seal`/`open`, `Nonce`,
  `SealedBox` with its combined form) over CommonCrypto's GCM, and the
  public-key types: P256, P384 and P521 (`Signing` with ECDSA,
  `KeyAgreement` with ECDH; raw, x9.63 and PEM representations, compact key
  generation) and Curve25519 (Ed25519 `Signing`, X25519 `KeyAgreement`).
  `SecureEnclave` exists with `isAvailable == false`; its initialisers take
  Security and LocalAuthentication types and are not provided.
  `tools/gen-cryptokit.py` writes the three NIST curves from one template.
- `src/frameworks/cryptokit/ec.c`: the arithmetic, written from the
  standards: Montgomery multiplication over 32-bit limbs, Jacobian
  coordinates for the NIST curves (parameters self-checked at first use:
  G on the curve, n*G = infinity), the X25519 ladder, Ed25519 in extended
  coordinates with its constants derived at first use. Not constant-time.
  Checked against RFC 7748 and RFC 8032 vectors, and ECDSA against an
  independent implementation both ways on all three curves.
- `tests/swiftlib/cryptokit`: SHA-2 and AES-GCM vectors, RFC 8032 and RFC
  7748 through the Swift API, round trips on every curve, PEM, tampering.
- Target app window (total `^MISSING`): 3,522 -> 3,378 (144 of its 146
  CryptoKit imports; the other two are the Secure Enclave initialisers).

## 2026-11-26: Date, JSON, Decimal; collection ABI; missing-descriptor reports

- Foundation's Swift overlay: `Date` (seconds since 2001; Codable as
  Apple's, NSDate bridging), `JSONEncoder`/`JSONDecoder` (own writer and
  parser; output formatting, date/data/key/float strategies, snake case,
  pretty printing, exact integers), `Decimal` (the C struct NSDecimal;
  128-bit mantissa arithmetic, parsing, description, rounding via
  `NSDecimalRound`, Codable).
- Foundation (ObjC): `NSDistributedNotificationCenter` (delivers within the
  process; nothing else listens in the container).
- stdlib ABI: `Collection.subscript(position:)` is `@_borrowed` (a `_read`
  requirement) and Bidirectional/RandomAccessCollection declare
  `index(_:offsetBy:)`, `index(_:offsetBy:limitedBy:)` and
  `distance(from:to:)` as `@_nonoverride` requirements, as Apple's do;
  programs send resilient witnesses keyed by those requirements. New:
  `Identifiable`, `CaseIterable`, `_stdlib_isOSVersionAtLeast` (#available,
  answered as macOS 15.0).
- Loader/runtime: `dx_stub_name` recognises unimplemented-import stubs;
  `swift_getWitnessTable` now reports a missing conformance or protocol
  descriptor by name instead of crashing on the stub's code bytes.
- Target app window (total `^MISSING`): 3,378 -> 3,304. It now stops at
  `NSOperationQueue`.

## 2026-11-26: operation queues; object constants; stubs that say what they are

- Foundation: `NSOperation`, `NSBlockOperation`, `NSOperationQueue` over
  dispatch (dependencies, max concurrency, priorities, suspension,
  cancellation, completion blocks, `currentQueue`/`mainQueue`, barriers).
  Without key-value observing, operations that finish asynchronously are
  noticed by polling `isFinished`. Test: `tests/foundation/operations`.
- Loader: unimplemented imports shaped like Apple's string constants
  (`NS...Key`, `...Notification`, `...Domain`, `k...Attribute`,
  `k...Notify...`) are bound to a slot holding an immortal string of their
  name, the value most such constants have, instead of to code.
- Stubs now begin with a jump over their name pointer, so a stub read as
  data decodes to its name (`dx_stub_value_name`); messaging one reports
  "object constant X is not implemented" instead of a bogus tagged pointer.
- libSystem: `__sincos_stret`, `__sincosf_stret` and the `pi` variants.
- Target app window (total `^MISSING`): 3,304 -> 3,301. It now runs into
  AppKit: `-[NSApplication effectiveAppearance]`.

## 2026-11-26: the Dispatch overlay (PR: dispatch-overlay)

- `overlays/Dispatch` (libswiftDispatch): `DispatchQueue` (`main`,
  `global(qos:)`, the labelled initializer with attributes, QoS,
  autorelease frequency and target; `async`/`asyncAfter`/`sync` with
  results and errors, barriers, `concurrentPerform`, queue-specific
  values), `DispatchGroup`, `DispatchSemaphore`, sources (`makeTimerSource`,
  read/write, file-system, signal and user-data sources, with
  `DispatchSourceProtocol`'s handlers and `DispatchSourceTimer.schedule`),
  `DispatchTime`/`DispatchWallTime`/`DispatchTimeInterval` and their
  arithmetic, `DispatchQoS`, `DispatchWorkItemFlags`, `DispatchPredicate`
  and `dispatchPrecondition`, `DispatchSpecificKey`, and `DispatchData`
  (holding its bytes directly). It calls libdispatch by symbol.
- `sdk/include/dispatch/swift.h` and a `Dispatch` Clang module: the
  dispatch objects as Objective-C classes (`OS_dispatch_queue`...), the
  source protocols, and the factory initializers Swift calls
  (`DispatchQueue(__label:attr:queue:)`, `DispatchGroup()`,
  `DispatchSemaphore(value:)`, `enter`/`leave`), bound to the C symbols by
  asm labels so they never meet `<dispatch/dispatch.h>`, which C and
  Objective-C code keeps using unchanged.
- `src/frameworks/dispatch/swift_classes.c`: exported storage for
  `_OBJC_CLASS_$_OS_dispatch_{object,queue,group,semaphore,source,data}`.
  `dispatch_object_class()` builds those classes in it (a four-line hook)
  through the new `dx_os_object_class_in_super` in the Objective-C runtime,
  so dispatch objects and Swift code share one class each.
- `tests/swiftlib/dispatch`: queues, groups, semaphores and timeouts,
  timers, user-data sources, times, specific values, data.
- Target app window (total `^MISSING`): 3,301 -> 3,215 (all 84 Dispatch
  overlay imports and the two dispatch classes it binds from libSystem).

## 2026-11-26: Network.framework (PR: network)

- `frameworks/Network`: `NWConnection` and `NWListener` over BSD sockets
  (TCP, UDP and Unix-domain; getaddrinfo, both address families, the
  state machine with `preparing`/`ready`/`failed`/`cancelled`, `send` with
  final-message half-close, `receive` with minimum and maximum lengths,
  establishment and data-transfer reports), `NWEndpoint` with `Host` and
  `Port`, `IPv4Address`/`IPv6Address`, `NWInterface`, `NWError`,
  `NWPath` and `NWPathMonitor` (interfaces by index), `NWParameters` with
  its protocol stack, and the TCP, UDP, IP and TLS protocol classes. Each
  connection does its blocking work on two private serial queues and
  reports on the queue it was started on. There is no TLS: a connection
  or listener that asks for it fails with `NWError.tls`.
- `sdk/include/Security/SecProtocolObject.h` and a `Security` Clang module:
  the TLS protocol object types (`sec_protocol_options_t`,
  `sec_protocol_metadata_t`) Network's API names.
- Makefile: `SWIFT_FW_MACOS_NAME` gives a Swift framework a later
  deployment target, as `SWLIB_MACOS_NAME` does for tests. Network uses
  14.0, because `NWError.posix` carries `POSIXErrorCode`, which lives in
  the _errno overlay from macOS 14 and is hidden from older targets.
- `tests/swiftlib/network`: addresses and endpoints, a loopback listener
  and client exchanging data with a half-close, refused, DNS and TLS
  failures, the path monitor.
- Target app window (total `^MISSING`): 3,215 -> 2,999 (all 216 Network
  imports).

## 2026-11-26: Carbon keyboard input sources and events; Launch Services bits (PR: carbon)

- `src/frameworks/carbon/carbon.c`: Text Input Sources with one source,
  the US keyboard layout, as a CF dictionary of its properties
  (`TISCopyCurrentKeyboardLayoutInputSource` and friends,
  `TISGetInputSourceProperty`, `TISCreateInputSourceList`), the `kTIS...`
  keys and types, `LMGetKbdType`, and `UCKeyTranslate` over the layout data
  it hands out (a table of bitten's own: the ANSI key codes with Shift,
  Caps Lock and Control, return/tab/escape/arrows and function keys; not
  Apple's 'uchr' format). Carbon event handlers and hot keys are accepted
  and kept but never called, as no window server delivers events;
  `GetEventParameter` reports no parameter. `LSRegisterURL` succeeds and
  the `kLSQuarantine...` keys exist.
- `tests/c/carbon`: the input source and its properties, key translation
  with modifiers, handlers and hot keys.
- Target app window (total `^MISSING`): 2,999 -> 2,976 (all 18 Carbon and
  5 CoreServices imports). On main the run stops before it gets here, at
  `Unicode.Scalar.Properties` (standard library, in progress elsewhere).

## 2026-11-26: Unicode properties, ManagedBuffer, hash/map tables, appearance

- stdlib: `Unicode.Scalar.Properties` (general category, alphabetic, case,
  white space, emoji, math, numeric type and value), `Unicode.GeneralCategory`,
  `Unicode.NumericType`, and Character's `isLetter`, `isNumber`,
  `isWhitespace`, `isUppercase`, `wholeNumberValue`, `hexDigitValue` and
  friends, from three new tables `tools/gen-unicode.py` derives from the UCD
  (General_Category; a byte of binary properties; numeric type and value).
  `ManagedBuffer` (Apple's fixed layout), `Unicode.Scalar(Int)`, public
  `_precondition`/`_preconditionFailure`/`_debugPrecondition`,
  `withoutActuallyEscaping`.
- Foundation: `NSHashTable`, `NSMapTable`, `NSPointerFunctions` (strong or
  weak members, equality or identity).
- AppKit: `NSAppearance` (light; `BITTEN_APPEARANCE=dark` for dark), and
  `appearance`/`effectiveAppearance` on NSApplication, NSWindow and NSView.
- Runtime: a symbolic type reference to a stubbed descriptor now names the
  missing descriptor instead of returning nil to the program.
- Target app window (total `^MISSING`): 2,976 -> 2,935. It runs past Carbon
  and Unicode to Foundation's `NSObject.KeyValueObservingPublisher`.

## 2026-11-26: run loops, timers, Foundation's Combine publishers

- Foundation: `NSRunLoop` (the main loop waits on and drains the main
  dispatch queue through `_dispatch_get_main_queue_port_4CF` /
  `_dispatch_main_queue_callback_4CF`; other threads get a queue each) and
  `NSTimer` (dispatch timer sources). `-[NSNotification initWithName:...]`.
- Foundation's Swift overlay now imports Combine (built below Foundation):
  `NotificationCenter.Publisher`, `NSObject.KeyValueObservingPublisher`
  (initial value only; no KVO yet), `Timer.publish`/`TimerPublisher`,
  `RunLoop: Scheduler`, and the `Notification` value type.
- Headers match Apple's Swift view: NS_TYPED_EXTENSIBLE_ENUM and friends
  (`NSNotification.Name`, `RunLoop.Mode` are newtype structs); NSData,
  NSDate and NSNotification bridge to Data, Date and Notification; Swift
  names without the NS prefix (`RunLoop`, `Timer`, `Bundle`, `UserDefaults`,
  `FileManager`, `OperationQueue`, ...); `NSObject.h` is nonnull by default.
- stdlib: `_SwiftNewtypeWrapper` (hashing, AnyHashable and bridging for
  those newtypes; without it their witness tables had holes).
  Foundation: `AnyHashable: _ObjectiveCBridgeable` (needed to lower
  `[AnyHashable: Any]` signatures; the compiler crashed without it).
- Combine: `Scheduler` convenience overloads; `autoconnect()` keeps its
  connection alive through the downstream subscription.
- ObjC runtime: a class that declares no protocols conforms to one whose
  required methods it implements (runtime-made classes such as
  `__NSCFString` now pass `as NSCopying`).
- Target app window (total `^MISSING`): 2,935 -> 2,906. It now stops at the
  standard library's sort helper `_minimumMergeRunLength`.

## 2026-11-26: dispatch classes built at start-up (PR: dispatch-eager)

- The six dispatch classes Swift code names by symbol
  (`swift_classes.c`) were built lazily, with the first object of their
  kind; a program that messaged `OS_dispatch_source` (or read its metadata)
  before creating a source read zeroed storage and crashed. They are now
  built in a constructor (priority 110), after the Objective-C runtime and
  dispatch's root classes, before any image loads.
- `tests/swiftlib/dispatch` asks for the class names before any source or
  data object exists.

## 2026-11-26: CoreGraphics, the C core (PR: coregraphics)

- A software rasterizer and the CG object types, in mrun
  (`src/frameworks/coregraphics`): color spaces (device and named RGB and
  gray), colors and gradients; paths (every construction call, arcs,
  rounded rects, bounding boxes, hit testing, apply, stroked copies);
  data providers and images (any 8-bit RGB, gray or alpha-only layout in
  either byte order, masks, sub-images); bitmap contexts over the same
  layouts; the graphics state stack, CTM, colors, line style and dashes;
  fill, even-odd fill, stroke (caps, joins, miter limit), clear, clipping
  to paths, rects and image masks; images (bilinear or nearest, tiled);
  linear and radial gradients; transparency layers. Text state is kept
  for CoreText. Window lists are empty and CGEvents hold values (no window
  server).
- The rasterizer: polygons scanned row by row at four sample heights with
  exact horizontal coverage, the nonzero or even-odd rule, a coverage clip
  mask, premultiplied blending (normal, copy, clear; other blend modes and
  shadows are not drawn yet). Strokes are outlined in user space (so a
  scaled CTM scales the pen) and filled.
- CG types are CF objects (new CF type ids, bridged as `__NSCFCG...`).
- `sdk/include/CoreGraphics`: CGBase, CGColorSpace (with CGColor and
  CGGradient), CGPath, CGImage, CGContext, CGWindow, for Objective-C and
  Swift.
- `tests/c/cg`: pixels after fills, antialiased edges, blending, clips,
  strokes, dashes, even-odd, ellipses, the CTM, gradients, images and
  their round trip, transparency layers, BGRA and gray contexts, paths.
- Target app window (total `^MISSING`): 2,906 -> 2,814 (92 of 113
  CoreGraphics imports; the rest are Swift overlay methods).

## 2026-11-26: Mirror, lazy sequences, random numbers, errors, KVO

- stdlib: `Mirror` (stored properties of structs, classes and tuples
  through new runtime reflection entry points in reflection.c;
  CustomReflectable; collections describe themselves), `AnyCollection`,
  `AnyIndex`, `AnyIterator`, `KeyValuePairs`; lazy sequences
  (`LazySequence`, `LazyMapSequence`, `LazyFilterSequence`),
  `FlattenSequence` (`joined()`), `ReversedCollection` (`reversed()`), all
  with Apple's frozen layouts; `RandomNumberGenerator`,
  `SystemRandomNumberGenerator`, `random(in:)`, `shuffle`,
  `randomElement`; the collection cast intrinsics (`_arrayForceCast`,
  `_dictionaryUpCast`, ...; the compiler crashed without them);
  `ManagedBufferPointer`; `_HasContiguousBytes`; `Error` with Apple's four
  requirements (`_domain`, `_getEmbeddedNSError`); `utf8CString`,
  `String.Index(utf16Offset:in:)`, `Hasher.combine(bytes:)`; sort's
  `_minimumMergeRunLength`; printing shows structs as `Point(x: 1, y: 2)`
  and metatypes as the type they name.
- Runtime: casts to and from `AnyHashable` and from Objective-C objects to
  bridged Swift values; `any Error` conforms to Error (self-conformance);
  NSError's Error conformance for Objective-C errors;
  `_swiftImmortalRefCount`, `_swift_stdlib_bridgeErrorToNSError`,
  `_swift_stdlib_operatingSystemVersion`.
- Foundation: `LocalizedError`, `CustomNSError`, `RecoverableError`,
  `CocoaError`, `POSIXError`, `URLError` and `Error.localizedDescription`
  (Foundation is now built for macOS 14, as POSIXErrorCode needs); key-value
  coding and observing (manual will/didChange, KVC setters, NSUserDefaults
  announces its keys); NSComparisonMethods; lossy `dataUsingEncoding:`.
- Tests: `tests/swiftlib/reflection`, KVO in `tests/foundation/operations`.
- Target app window (total `^MISSING`): 2,814 -> 2692. It now stops at
  SystemConfiguration's `SCDynamicStoreCopyComputerName`.

## 2026-11-26: SystemConfiguration names (PR: sysconfig)

- `src/frameworks/systemconfiguration`: `SCDynamicStoreCopyComputerName`
  (the host's name), `SCDynamicStoreCopyLocalHostName` (up to the first
  dot) and `SCDynamicStoreCopyConsoleUser` (the user the program runs as).
  The target app's run stopped at the first of these; it now goes on to
  `URLResourceValues` (Foundation).
- `tests/c/sysconfig`.
- Target app window (total `^MISSING`): 2,692 -> 2,690.

## 2026-11-26: the display: windows in a browser (PR: display)

- `src/frameworks/display`: a window server in mrun with no window system
  underneath. AppKit presents each window's bitmap
  (`bitten_display_present(id, pixels, width, height, row_bytes,
  bitmap_info, x, y, title)`, any 8-bit RGB layout a bitmap context uses)
  and closes it (`bitten_display_close`); a small HTTP server serves a
  page that draws the windows on canvases over a WebSocket (handshake
  with CommonCrypto's SHA-1) and sends input back, which AppKit takes with
  `bitten_display_next_event` (mouse down/up/moved/dragged, scroll, key
  down/up with Mac virtual key codes, characters and
  NSEventModifierFlags, close and resize requests) or waits for on
  `bitten_display_event_fd`. Port `BITTEN_DISPLAY_PORT` (7681; 0 picks
  one), loopback only unless `BITTEN_DISPLAY_PUBLIC`.
  `bitten_display_listen(port)` starts it explicitly.
- `page.html` is the page; `tools/gen-display-page.py` turns it into
  `page.h`.
- DECISIONS: windows are shown in a browser.
- `tests/c/display`: a window drawn with CoreGraphics and presented, the
  page fetched, the WebSocket handshake (RFC 6455's sample key), the
  frame's header and pixels, an input event with non-ASCII characters
  coming back, and the close message.

## 2026-11-26: URLComponents, resource values, NSError round trips

- Foundation: `URLComponents` (own RFC 3986 parser; decoded and
  percent-encoded parts, query items, assembly), `URLQueryItem`,
  `URLResourceValues` with `URL.resourceValues(forKeys:)` /
  `setResourceValues` (stat(2): kinds, sizes, dates, permissions, packages,
  volume capacity), and the `URLResourceKey` constants.
- Runtime: an NSError cast to a Swift error type that bridges from it
  (`error as? CocoaError`, `catch CocoaError.fileReadNoSuchFile`) goes
  through `_ObjectiveCBridgeableError.init?(_bridgedNSError:)`; the compiler
  stores a thrown CocoaError as its NSError, so this is how it comes back.
- Target app window (total `^MISSING`): 2,690 -> 2,632. It now stops at
  `AsyncStream` in `_Concurrency`.

## 2026-11-26: async sequences, streams, task groups

- `_Concurrency`: `AsyncSequence` and `AsyncIteratorProtocol` with Apple's
  requirements (typed-throws `next(isolation:)`, `Failure`), `contains`,
  `first(where:)`, `reduce`, `allSatisfy`, `dropFirst`
  (`AsyncDropFirstSequence`); `AsyncStream` and `AsyncThrowingStream`
  (buffering policies, termination handlers, cancellation, `makeStream`,
  `unfolding:`); `TaskGroup`, `ThrowingTaskGroup`, `DiscardingTaskGroup`
  (frozen over the runtime's group) and `withTaskGroup`,
  `withThrowingTaskGroup`, `withDiscardingTaskGroup`; `Clock.continuous` /
  `.suspending`; `CheckedContinuation(continuation:function:)`.
- Runtime: a child added with "add pending unconditionally" now counts as
  pending (task groups saw no children before).
- Foundation: `NSHost` (`Host`).
- Tests: streams and groups in `tests/swiftlib/async`.
- Target app window (total `^MISSING`): 2,632 -> 2,537. It now stops at
  UserNotifications' `UNNotificationCategory`.

## 2026-11-26: UserNotifications (PR: usernotifications)

- `frameworks/UserNotifications` (Objective-C over Foundation, built like
  AppKit) and `sdk/include/UserNotifications`: the notification center
  (`currentNotificationCenter`, authorization, settings, categories,
  adding, listing and removing pending and delivered notifications, badge
  count, the delegate), content and mutable content, sounds, attachments,
  requests, time-interval, calendar and push triggers, actions,
  categories, settings, responses. There is no notification server:
  authorization is granted, a delivered notification is written to
  standard error and kept, time-interval triggers fire, the delegate hears
  of each delivery on the main queue.
- `tests/usernotifications` (new test directory, run by `make check`).
- The target app's run stopped at `+[UNNotificationCategory self]`; it now
  goes on to `+[NSWorkspace sharedWorkspace]` (AppKit).
- Target app window (total `^MISSING`): 2,536 -> 2,526.

## 2026-11-26: windows on the display, events in

- AppKit draws: `NSGraphicsContext` over a CGContext (current per thread,
  flipped or not), `NSColor` `set`/`setFill`/`setStroke`/`CGColor`,
  `NSRectFill`, `NSFrameRect`, `NSEraseRect`, and `NSBezierPath` over
  CGPath (rects, ovals, rounded rects, arcs, curves, fill, stroke, clip).
- A window draws its view tree into a bitmap CGContext (frames, bounds,
  clipping, flipped views inside unflipped ones and the reverse) and hands
  it to the display (`bitten_display_present`, from #79), which shows it in
  the browser; `setNeedsDisplay:` redraws on the next turn of the main
  queue; ordering out and closing remove it.
- Events: the display's events become NSEvents (mouse, drag, scroll, keys,
  click counts, modifier flags) delivered as AppKit does: the window
  hit-tests a mouse-down, keeps the view for the drags and mouse-up, makes
  it first responder; keys go to the first responder; close and resize
  requests act like the title bar's controls (`performClose:`,
  `windowShouldClose:`).
- Test: `tests/appkit/drawing` (pixels of a drawn window; event routing).
- Target app window (total `^MISSING`): 2,526 (unchanged; this is behaviour,
  not imports). It stops at `+[NSWorkspace sharedWorkspace]`.

## 2026-11-26: NSWorkspace

- AppKit: `NSWorkspace` (its own notification centre; opening URLs and
  files is reported on stderr and handed to `$BITTEN_OPEN` when set; the
  app itself as the frontmost and only running application; packages;
  recycling into ~/.Trash; accessibility display settings) and
  `NSRunningApplication` (`currentApplication` from the main bundle).
- Target app window (total `^MISSING`): 2,526 (unchanged). It now gets to
  SwiftUI (`KeyEquivalent`): 1,668 of its remaining imports are SwiftUI.

## 2026-11-26: SwiftUI view graph and layout

- SwiftUI now has Apple's protocol shapes for `View` (`_makeView`,
  `_makeViewList`, `_viewListCount` before `body`) and `ViewModifier`, with
  the default implementations programs reference by symbol. `_GraphValue`,
  `_ViewInputs`, `_ViewOutputs` and the rest carry our engine: each view
  becomes a render node (size for a proposal, place, draw into a CGContext,
  hit testing), and state lives in storage keyed by structural position.
- Layout (`Layout.swift`): alignments (`AlignmentID`, `Alignment`,
  Horizontal/VerticalAlignment), edges and insets, `ModifiedContent`,
  `_VariadicView.Tree` with Apple's frozen `_VStackLayout`, `_HStackLayout`
  and `_ZStackLayout`, `VStack`/`HStack`/`ZStack`, `Spacer`, padding
  (`_PaddingLayout`) and frames (`_FrameLayout`, `_FlexFrameLayout`).
- `Environment` (frozen, as Apple's), `EnvironmentValues`,
  `ProposedViewSize`, `Animatable` and its data.
- `@State`, `@StateObject`, `@ObservedObject` and lazy state find their
  storage when the view joins the graph; observed objects and
  `@Observable` reads rebuild the host.
- `NSHostingView` builds, lays out and draws the tree, and routes clicks to
  tappable nodes; `NSHostingController` loads one.
- AppKit: `NSViewController` (view loading, appearance callbacks, child
  controllers), `NSWindowController`, `NSWindow.contentViewController`;
  responder event methods get their Swift names (`mouseDown(with:)`).
- Foundation: `-indexOfObjectIdenticalTo:`, `-removeObjectIdenticalTo:`.
- SwiftUI builds for macOS 14 (CGFloat lives in the CoreFoundation overlay
  there).
- Target app window (total `^MISSING`): 2,526 -> 2,395.

## 2026-11-26: CoreText and CFAttributedString (PR: coretext)

- `src/frameworks/coretext`: a TrueType reader (head, hhea, maxp, hmtx,
  cmap 4 and 12, loca, glyf with composite glyphs, OS/2, post, name;
  collections; not CFF), the installed fonts (`BITTEN_FONT_PATH`, or
  /usr/share/fonts, /usr/local/share/fonts, ~/.fonts, plus files
  registered with CTFontManager) with Apple's names mapped to open
  families (the system font, Helvetica, SF -> Noto Sans or DejaVu Sans;
  Menlo, Monaco, SF Mono -> DejaVu Sans Mono; Times, New York -> DejaVu
  Serif; weights and slants from the name), CTFont (metrics, traits,
  names, glyphs, advances, bounding rects, outlines as CGPaths,
  CTFontDrawGlyphs, symbolic-trait and attribute copies, fonts for
  strings, cascade lists, tables), CTFontDescriptor, CTFontCollection,
  CTFontManager, CTLine and CTRun (runs by font and color with fallback
  faces for missing characters, typographic and glyph bounds, hit
  testing, drawing through the context's text matrix and position), and
  the attribute keys. NSFont and NSColor values work too (by -fontName,
  -pointSize and -CGColor). No shaping beyond one glyph per character:
  no ligatures, kerning tables or bidirectional text yet.
- `src/frameworks/corefoundation/attributed.c`: CFAttributedString and
  its mutable form.
- `sdk/include/CoreText` and a `CoreText` Clang module; CFAttributedString
  in the CoreFoundation header.
- Dockerfile: fonts-dejavu-core (test image), fonts-dejavu-core and
  fonts-noto-core (runtime image).
- `tests/c/coretext`: metrics, traits, glyphs, advances, outlines, lines,
  runs, positions, hit testing, fallback, a glyph drawn and checked
  pixel by pixel, attributed-string ranges and editing.
- Target app window (total `^MISSING`): 2,395 -> 2,318 (all 74 CoreText
  imports and 3 CFAttributedString ones).

## 2026-11-26: SwiftUI shapes, colours, text, images, buttons

- Shapes (`Shapes.swift`): `Path` (Apple's frozen storage; over CGPath),
  `Shape` and `ShapeStyle` with Apple's requirement lists, `_ShapeView`,
  `Rectangle`, `RoundedRectangle`, `UnevenRoundedRectangle`, `Circle`,
  `Ellipse`, `Capsule`, `AnyShape`, fills and strokes; the foreground,
  background, tint, hierarchical, opacity and type-erased styles; `Angle`,
  `UnitPoint`, `FillStyle`, `StrokeStyle`.
- Views (`Views.swift`): `Color` (frozen; RGB, HSB, NSColor, named and
  dynamic colours, `Resolved`, mixing), `Gradient`, `Font` (text styles at
  macOS sizes, weights, designs), `Text` (Apple's frozen storage and
  modifiers, localized keys with interpolation, concatenation), measured
  and drawn with CoreText, word-wrapped; `Image` (CGImage drawing; symbol
  placeholders), `KeyEquivalent`, `EventModifiers`, `KeyboardShortcut`,
  `Button` with the button styles.
- Environment modifiers with Apple's frozen types
  (`_EnvironmentKeyWritingModifier`, `_ForegroundStyleModifier`,
  `_BackgroundModifier`, `_OverlayModifier`, ...): `environment`, `font`,
  `foregroundStyle`, `tint`, `background`, `overlay`, `disabled`, ...
- `NSHostingView` centres the root view at the size it asks for.
- Runtime: opaque result types (`some View`) resolve from names that give
  only the outer generic arguments (the descriptor's signature has a level
  of its own for the opaque types).
- stdlib: `stride(from:to:by:)`, `stride(from:through:by:)`.
- `_Concurrency`: `MainActor.assumeIsolated`. AppKit: `NSColor.cgColor`
  and `colorWithCGColor:` in the header.
- Build: Swift objects are touched after compiling (swiftc leaves an
  unchanged object as it was, which made make rebuild everything each run).
- Test: `tests/swiftlib/swiftui` (stacks, spacers, padding, frames, shapes,
  backgrounds and text drawn into a bitmap; @State through a click).
- Target app window (total `^MISSING`): 2,318 -> 1,950.

## 2026-11-26: QuartzCore (PR: quartzcore)

- `QuartzCore.framework` (Objective-C over Foundation, CoreGraphics and
  CoreText): `CALayer` with geometry (frame, bounds, position, anchor point,
  transforms), the sublayer tree, coordinate conversion and hit testing,
  layout and display passes that ask the delegate. `-renderInContext:`
  draws a tree: background with corner radius, image contents with
  gravity, the layer's own drawing, sublayers by `zPosition` under
  `masksToBounds`, border, opacity as a transparency layer.
- `CAShapeLayer` (fill rule, stroke, caps, joins, dashes), `CAGradientLayer`
  (axial and radial), `CATextLayer` (one line through CoreText),
  `CAMetalLayer` (no device, no drawables: there is no GPU).
- Animations: `CABasicAnimation`, `CAKeyframeAnimation`,
  `CASpringAnimation` (perceptual duration, bounce, settling time),
  `CATransition`, `CAAnimationGroup`, `CAMediaTimingFunction`. Nothing is
  interpolated: an added animation reports its start and, after its
  duration, a finished stop to its delegate.
- `CATransaction` nests per thread; the outermost commit runs the
  completion block on the main queue. `CADisplayLink` ticks at 60 Hz (or
  its preferred rate) on the run loop it is added to; AppKit can hand one
  out with `+_bn_displayLinkWithTarget:selector:`.
- `CATransform3D` functions, `CAFrameRateRange`, `CACurrentMediaTime`, the
  `kCA*` constants with Apple's values; `NSValue` holds a transform.
- `libswiftQuartzCore`: `CAFrameRateRange(minimum:maximum:preferred:)` and
  its optional `preferred`, `CATransform3D` bridging to `NSValue`. Built
  after Foundation's Swift module, so not in `overlays/`.
- Test: `tests/quartzcore/layers`.
- Target app window (total `^MISSING`): 1,950 -> 1,899.

## 2026-11-26: Metal (PR: metal)

- `Metal.framework` (Objective-C over Foundation). There is no GPU:
  `MTLCreateSystemDefaultDevice` returns nil and `MTLCopyAllDevices` an
  empty array, so programs take their software path.
- The descriptors hold their values and copy deeply:
  `MTLTextureDescriptor` (with `texture2DDescriptorWithPixelFormat:...`,
  which counts mipmap levels), `MTLRenderPassDescriptor` (colour, depth
  and stencil attachments), `MTLRenderPipelineDescriptor` (colour
  attachments with blending, `-reset`), `MTLFunctionConstantValues`.
- Test: `tests/metal/descriptors`.
- Target app window (total `^MISSING`): 1,899 -> 1,894.

## 2026-11-26: CoreGraphics' Swift API (PR: cg-overlay)

- The CoreGraphics overlay grows Apple's Swift API: `CGPathFillRule`;
  `Equatable` for `CGPoint`, `CGSize`, `CGRect`, `CGAffineTransform`;
  `init?(dictionaryRepresentation:)` and `dictionaryRepresentation` for
  points, sizes and rectangles; `CGMutablePath`'s `move(to:)`, `addLine`,
  `addCurve`, `addQuadCurve`, `addRect`, `addRoundedRect`, `addEllipse`,
  both `addArc`s and `addPath` (each with `transform:`); `CGPath.union`
  (both outlines in one path: no path boolean operations yet);
  `CGContext`'s `fillPath(using:)`, `clip(using:)`, `draw(_:in:byTiling:)`,
  `setLineDash(phase:lengths:)` and `textPosition`.
- The overlay builds for macOS 14 (`OVERLAY_MACOS_<name>` in the
  Makefile): it uses `CGFloat`, which older targets see in CoreGraphics.
- `CoreGraphics.framework` now exists as an image: empty, re-exporting
  the overlay, because current macOS keeps the Swift API in the framework
  and programs bind it there. The C API stays in the loader's registry.
- C: `CGRect/CGPoint/CGSize` `CreateDictionaryRepresentation` and
  `MakeWithDictionaryRepresentation`.
- Test: `tests/swiftlib/coregraphics`.
- Target app window (total `^MISSING`): 1,894 -> 1,873.

## 2026-11-26: UniformTypeIdentifiers (PR: uttype)

- `libswiftUniformTypeIdentifiers`: `UTType` over a table of about ninety
  system types (identifier, supertypes, filename extensions, MIME types):
  `conforms(to:)`, `isSubtype`/`isSupertype`, `supertypes`, `tags`,
  lookup by identifier, extension or MIME type, dynamic types for unknown
  tags (conforming to the type asked for), `exportedAs`/`importedAs`
  declarations, `Codable`, the static types (`.png`, `.folder`,
  `.applicationBundle`, `.osaScript`...). `URLResourceValues.contentType`
  and `URL.appendingPathComponent(_:conformingTo:)`.
- Build: Swift libraries that need Foundation's Swift API (QuartzCore's
  overlay, this one) share one rule, `LATE_SWIFT`, built after Foundation.
- Not yet: `NSItemProvider.loadFileRepresentation(for:...)` (Foundation has
  no `NSItemProvider`).
- Test: `tests/swiftlib/uttype`.
- Target app window (total `^MISSING`): 1,873 -> 1,852.
## 2026-11-26: SwiftUI protocols; Foundation literals, IndexSet, KVO, run loop observers; AppKit windows

- SwiftUI (`Protocols.swift`), with Apple's requirement lists and default
  implementations: `PreferenceKey` (preferences flow up the node tree;
  `preference`, `onPreferenceChange`), `Layout` (custom layouts, `AnyLayout`,
  the stack layouts as layouts), `NSViewRepresentable` and
  `NSViewControllerRepresentable` (the AppKit view kept across rebuilds and
  placed as a subview of the hosting view), `Commands` (`CommandGroup`,
  `CommandMenu`, placements; menus built from the content's buttons),
  `ToolbarContent` (`ToolbarItem`, `ToolbarItemGroup`, the builder), the
  label, labeled-content and progress styles, `FocusedValueKey`; `Divider`.
- Foundation: literals for `NSString`, `NSNumber`, `NSArray`, `NSSet`,
  `NSDictionary`; `NSFastEnumerationIterator` (NSArray, NSSet and
  NSDictionary as sequences); `NSNumber(value:)`; `IndexSet`; Swift KVO
  (`observe(_:options:changeHandler:)`, `NSKeyValueObservation`); delayed
  and main-thread performs, `cancelPreviousPerformRequests`;
  NSGeometry (zero constants, rectangle and range arithmetic, string forms,
  NSValue geometry); URL reachability checks; more NSError keys.
- CoreFoundation: run loops over the main queue (`CFRunLoopGetMain`,
  observers that see each turn; NSApplication now runs the main run loop),
  bundle keys, and the constant literal objects newer clang emits
  (`NSConstantArray`, `NSConstantDictionary`, `NSConstant*Number`), resolved
  to CF objects on first use like constant strings.
- AppKit: the rest of NSWindow's state (tabbing, titlebar, level,
  collection behaviour, size limits, frame autosave, sheets, child windows,
  zoom and miniaturize, screen conversions), `charactersByApplyingModifiers:`
  on the US layout.
- stdlib: `AnyKeyPath._kvcKeyPathString`; `AutoreleasingUnsafeMutablePointer`
  subscript and conversions.
- The target app now starts through Sparkle's updater setup and reaches
  SwiftUI's scenes (`Scene.commands`).
- Target app window (total `^MISSING`): 1,873 -> 1,650.

## 2026-11-26: IOKit; Security's code signing, authorization, transforms (PR: iokit-security)

- IOKit (`src/frameworks/iokit`): a registry of one service,
  `IOPlatformExpertDevice`, whose `IOPlatformUUID` comes from
  /etc/machine-id; matching by class or name, iterators, `FromPath`,
  properties. Power sources from /sys/class/power_supply (each battery
  with capacity and charging state; AC or battery power), power
  assertions that are counted and prevent nothing.
- Security (`security/codesign.c`): static code objects (unsigned: empty
  signing information, no designated requirement), authorizations whose
  rights are all denied, transform groups that build but fail closed on
  execute (`errSecUnimplemented`, as `SecItemImport` does), access control
  objects, the transform, digest, code-info and accessibility constants.
- CoreFoundation: room for 40 CF types (three new Security ones).
- Test: `tests/c/iokit_security`.
- Target app window (total `^MISSING`): 1,629 -> 1,595.

## 2026-11-26: ImageIO (PNG), Accelerate, ServiceManagement (PR: smallfw)

- PNG decoding (`coregraphics/png.c`): every colour type and bit depth,
  palettes, tRNS, the five filters, Adam7; to premultiplied RGBA.
- ImageIO (`coregraphics/imagesource.c`): `CGImageSource` from data, a
  data provider or a URL; type by signature (PNG, JPEG, GIF, TIFF, BMP,
  ICO, ICNS, WebP, HEIC), count, status, images, thumbnails (the full
  image), pixel-size properties. Only PNG decodes. Also
  `CGImageCreateWithPNGDataProvider`.
- Accelerate (`src/frameworks/accelerate`): vDSP's FFT setup and real
  FFT (`vDSP_fft_zrip`, Apple's packing and 2x / 2N scaling),
  `ctoz`/`ztoc`, `vsmul`, `vadd`, `vmul`, `zvabs`, `zvmags`, `maxv`,
  `meanv`, `rmsqv`; vImage's RGB888 to RGBA8888 and (un)premultiply.
- ServiceManagement: there is no launchd; `SMJobSubmit`, `SMJobRemove`,
  `SMJobBless` and `SMLoginItemSetEnabled` fail with errors saying so.
- Test: `tests/c/imageio_accelerate`.
- Target app window (total `^MISSING`): 1,595 -> 1,582.

## 2026-11-26: LocalizedStringResource and String.LocalizationValue (PR: localized)

- Foundation (`swift/LocalizedStringResource.swift`, agreed with the
  Foundation side): `String.LocalizationValue` with its interpolation
  (strings, `_FormatSpecifiable` numbers with or without a specifier,
  placeholders, objects); keys are the literal with format specifiers,
  as Apple builds them, so they match a program's .strings tables.
  `LocalizedStringResource` (key, default, table, locale, bundle as
  main, a class's or a URL's), `CustomLocalizedStringResourceConvertible`,
  `String(localized:)` in its three forms. Resolving looks the key up in
  the table and puts the arguments into the localized format, positional
  ones ("%2$lld") included.
- `_FormatSpecifiable` and its conformances move from SwiftUI to
  Foundation, where Apple keeps them (the app binds them there).
- Not yet: `AttributedString(localized:)` and the `AttributedString`
  interpolation (Foundation has no AttributedString).
- Test: `tests/swiftlib/localized`.
- Target app window (total `^MISSING`): 1,582 -> 1,557.

## 2026-11-26: AppIntents (PR: appintents-fw)

- `AppIntents.framework` (Swift, macOS 14, over Foundation and
  UniformTypeIdentifiers) with Apple's shapes, so the program's intents,
  entities, queries and shortcuts bind: `AppIntent` (title, description,
  `openAppWhenRun`, `isDiscoverable`, `authenticationPolicy`, parameter
  summary, `perform()`), `AppEntity`/`AppValue`, `EntityQuery`,
  `EnumerableEntityQuery`, `EntityStringQuery`, `DynamicOptionsProvider`
  with the defaults Apple supplies; `@Parameter` (`IntentParameter`, with
  Bool, String, file and entity initialisers) and `@Property`
  (`EntityProperty`) holding values; display and type representations,
  descriptions, dialogs; results (`.result()`, `.result(value:)`);
  parameter summaries with key paths and `When` conditions; app shortcuts,
  phrases and their builders; String, Bool, Int, Double, Date, URL,
  Optional, Array and `IntentFile` as intent values.
- Nothing runs intents: there is no Shortcuts or intent service here.
- Build: a Swift framework can link the late Swift libraries
  (`SWIFT_FW_EXTRA_<name>`).
- Test: `tests/swiftlib/appintents` (an entity and its queries, an intent
  with defaults and a summary, performed; shortcuts).
- Target app window (total `^MISSING`): 1,557 -> 1,384.

## 2026-11-26: SwiftUI scenes, modifiers, environment; runtime fixes that get the target app into its views

- SwiftUI scenes: `commands`, `defaultSize`, `windowResizability`,
  `windowStyle` and the other scene modifiers, applied when the host opens
  windows; `openWindow`, `dismissWindow`, `openSettings`; window groups for
  presented values; the main menu built from the app's commands (standard
  menus with the command groups placed in them, `CommandMenu`s before
  Window).
- SwiftUI modifiers with Apple's frozen modifier types (`Effects.swift`):
  offset, opacity, scale, rotation, shadow, blur, clip, fixed size, aspect
  ratio, position, alignment guides, hit testing, appear/disappear (tracked
  per rebuild), tasks, traits (layout priority, z index, tags), `id`,
  `onChange`, animation and transaction (changes land at once), transitions,
  insettable shapes, trim and stroke shapes.
- Environment: `@Observable` objects (`.environment(object)`,
  `@Environment(Model.self)`), and the values programs read (control size,
  locale, layout direction, display scale, dismiss, openURL, undo manager,
  ...). `LazyState` and `LocalizedStringKey` keep Apple's frozen layouts
  (programs write `LazyState`'s storage and receive the key in registers);
  `TupleToolbarContent`/`TupleCommandContent` under Apple's names.
- AppKit: menus with key equivalents (`performKeyEquivalent:`, command
  shortcuts through the main menu), `sendAction:to:from:` along the
  responder chain, the rest of NSApplication (hide/unhide, modal sessions,
  presentation options, about panel to stderr), Swift names for the window
  and application enums (`NSWindow.StyleMask`, ...), `MIN`/`MAX`.
- Foundation: `NSUndoManager` (groups, undo/redo, target and block
  registration) and `UndoManager.registerUndo(withTarget:handler:)`;
  modal and event-tracking run loop modes; Foundation re-exports Dispatch.
- Runtime: the `A_` substitution (number 26) in mangled names; witness
  tables always hold every requirement of the protocol (the app's patterns
  can be empty: the table was a zero-byte allocation); a demangle dump of
  failing names (`BITTEN_DEMANGLE_DUMP`).
- `_Concurrency`: clock instants are resilient, as Apple's (programs pass
  them indirectly; a frozen one overflowed `Duration` arithmetic).
- The target app now starts, builds its scenes and gets into its views
  (`FocusState`).
- Target app window (total `^MISSING`): 1,384 -> 1,068.

## 2026-11-26: CoreImage, AVFAudio, ScreenCaptureKit, CoreAudio, Accessibility, SecureEnclave (PR: media-fw)

- `CoreImage.framework`: CIImage (CGImage pixels at an extent, or an
  infinite solid colour; crop, transform, filters, compositing), CIColor,
  CIContext (`createCGImage:fromRect:`, drawing into a CGContext), and
  CIFilter with CIColorMonochrome, CIColorInvert, CISepiaTone,
  CIColorControls, CISourceOverCompositing, CIConstantColorGenerator (other
  names give nil). CPU only.
- `AVFAudio.framework`: formats (standard deinterleaved float32 and the
  common ones), PCM buffers with their buffer lists, nodes, and an engine
  that, without an audio device, pulls its source nodes every 10 ms in
  real time and drops the samples.
- `ScreenCaptureKit.framework`: no shareable windows, displays or
  applications; screenshots fail with SCStreamErrorUserDeclined.
- `libswiftCoreAudio` with the CoreAudio types: `UnsafeMutableAudioBufferListPointer`.
- `Accessibility.framework`: notifications whose `post()` reaches no
  assistive technology.
- CryptoKit: SecureEnclave's initialisers, which throw (no enclave); the
  stub moves to its own file. SDK: `SecAccessControlRef`, `LAContext`.
- Build: `OBJC_FWS`, one rule for small Objective-C frameworks.
- Tests: `tests/media/media`, `tests/swiftlib/smallswift`.
- Target app window (total `^MISSING`): 1,068 -> 1,040.

## 2026-11-26: WebKit (PR: webkit)

- `WebKit.framework` without a browser engine, for Sparkle's release
  notes: `WKWebView` and the legacy `WebView` (AppKit views) take HTML and
  show its text (scripts, styles and the head dropped; blocks on their own
  lines; list items bulleted; entities decoded), drawn with CoreText, then
  tell their navigation or frame-load delegates the load finished. File
  URLs load; other URLs fail (NSURLErrorUnsupportedURL). User scripts and
  content rule lists (compiled from their JSON) are kept and do nothing;
  `evaluateJavaScript` fails. Configurations, preferences,
  `WebPreferences`, `WKContentRuleListStore`.
- Build: an `OBJC_FWS` framework can link more (`OBJC_FW_EXTRA_<name>`).
- Test: `tests/media/webkit`.
- Target app window (total `^MISSING`): 1,040 -> 1,033.

## 2026-11-26: libSystem odds, CoreFoundation over Foundation, Symbols, QuickLookUI (PR: odds)

- libSystem (`src/libsystem/extras.c`): `getifaddrs`/`freeifaddrs` in
  Darwin's layout (BSD sockaddrs, IFF_ bits, AF_LINK entries with the
  hardware address), `waitid` with Darwin's siginfo, `renamex_np` and
  `renameatx_np` (swap, exclusive), `mkpath_np`, `memset_s`, `errx`,
  `verrx`, `warnx`, `qos_class_main`, `notify_register_dispatch` (nothing
  is posted here), `__fpclassifyd`/`f` with Darwin's classes, `__exp10`.
- CoreFoundation (`corefoundation/bundle.c`): bundle info dictionaries
  (through NSPropertyListSerialization), executable architectures from
  Mach-O headers (thin and fat), `CFPreferences` app values (NSUserDefaults,
  suites for other ids), `CFCharacterSetCreateWithCharactersInRange`,
  IANA charset names and NSStringEncoding conversions.
- `Symbols.framework`: SymbolEffect and its kinds, variable colour and
  replace effects with their options, SymbolEffectOptions.
- `QuickLookUI.framework`: QLPreviewPanel, an empty NSPanel titled with
  the current item (there are no QuickLook generators).
- Tests: `tests/c/odds`, `tests/media/cfbridge`, `tests/swiftlib/smallswift`.
- Target app window (total `^MISSING`): 1,033 -> 1,005.
## 2026-11-26: SwiftUI containers and controls

- `Controls.swift`: `ForEach`, `Group` and `Section` (frozen, as Apple's),
  `List`, `ScrollView` (wheel scrolling, offsets kept across rebuilds),
  `ScrollViewReader`, `LazyVStack`/`LazyHStack`, `LazyVGrid` with
  `GridItem`s, `Grid`/`GridRow` (frozen trees) and the grid cell modifiers,
  `Label` and label styles, `LabeledContent`, `GroupBox`, `Form`,
  `ControlGroup`, `ContentUnavailableView`, `Toggle` (checkbox/switch),
  `Slider` (click and drag), `Stepper`, `Picker` (menu and segmented, by
  tag), `Menu`, `TextField` (keyboard input to the focused field, submit),
  `FocusState` and `focused`, `ProgressView`, `NavigationSplitView`,
  `GeometryReader`/`GeometryProxy`, `onGeometryChange`, `TimelineView`
  (periodic rebuilds), `Bindable`, `AppStorage` (user defaults),
  `Namespace`, `EquatableView`, `onReceive` (`SubscriptionView`).
- NSHostingView passes drags, the scroll wheel and keys to the tree.
- The app delegate of `NSApplicationDelegateAdaptor` is made at launch,
  not while the App value is initialized.
- ABI fixes found in the target app's code: `KeyEquivalent` is resilient
  (passed indirectly).
- Foundation: `UserDefaults.set(_:forKey:)`/`url(forKey:)` names; stdlib
  `abs`; NSResponder's `acceptsFirstResponder` is a property.
- Runtime: tuple elements are completed before their layout is taken.
- Target app window (total `^MISSING`): 1,033 -> 779.

## 2026-11-26: Regex: _StringProcessing and RegexBuilder (PR: regex)

- `libswift_StringProcessing`: Swift's `Regex` over a parsed tree and a
  backtracking matcher on Characters. Literals (the compiler's
  `Regex(_regexString:version:)`, delimiters stripped), `Regex(String)`
  (AnyRegexOutput) and `Regex(_:as:)`; escapes, `.`, classes with ranges,
  negation and POSIX names, `\d \w \s \h \v \b \B` and capitals, anchors,
  capturing, non-capturing and named groups, `(?i)`, alternation, greedy,
  lazy and possessive quantifiers. Matches build the compiler's Output
  (Substring, or the tuple of the match and its captures, optional ones
  nil when they did not take part); `@dynamicMemberLookup` for names.
  `firstMatch`, `wholeMatch`, `prefixMatch`, `ignoresCase`; collections'
  `contains`, `matches(of:)`, `ranges(of:)`, `split`, `replacing`;
  `CharacterClass`; `_RegexFactory` for RegexBuilder's inlined code.
- `libswiftRegexBuilder`: the builder, `Capture`, `One`, `OneOrMore`,
  `ZeroOrMore`, `Optionally`, `Repeat`, `makeFactory()`, and
  `split(separator: String)`.
- Test: `tests/swiftlib/regex`.
- Target app window (total `^MISSING`): 751 -> 727.

## 2026-11-26: Swift Charts (PR: charts)

- `Charts.framework` over SwiftUI: chart content (LineMark, PointMark,
  BarMark, AreaMark, RuleMark, ForEach, AnyChartContent, the builder with
  its parameter-pack BuilderTuple, conditionals) collects marks; `Chart`
  scales them linearly (numbers; categories in order; y from zero when
  the data allow) and draws them with SwiftUI shapes, one line per
  series, series coloured by `foregroundStyle(by:)` in Apple's order.
  `Plottable` for Double, Float, Int, String, Date; `PlottableValue`;
  `AnnotationPosition`; `chartXAxis`/`chartYAxis` (no axis lines are
  drawn) and axis labels beside the plot.
- SwiftUI gets `ForEach.init(_chartData:id:content:)` (in
  `frameworks/SwiftUI/ChartsSupport.swift`, announced): Charts builds
  ForEach with chart content, which the View inits do not allow.
- Not yet: the runtime does not instantiate generic types with parameter
  packs, so content with several marks in one builder (BuilderTuple) stops
  there; single-mark and ForEach charts draw.
- Test: `tests/swiftlib/charts` (a line chart and a styled series drawn
  into a bitmap, an axis label).
- Target app window (total `^MISSING`): 727 -> 703.

## 2026-11-26: C++ operator new and delete; CGFloat as a C vararg (PR: cxx-new)

- C++ runtime (`src/frameworks/cxx/new.c`): libc++abi's operator new and
  delete in their Darwin names, plain, array, sized, nothrow and aligned,
  over malloc; a failed allocation aborts (no C++ exceptions here).
- CoreFoundation overlay: `CGFloat: CVarArg` (passed as a Double), in a
  file of its own, under CoreGraphics' mangling like CGFloat's other
  conformances.
- Tests: `tests/c/odds` (operator new/delete), `tests/swiftlib/localized`
  (`String(format:)` with a CGFloat).
- Target app window (total `^MISSING`): 703 -> 700.

## 2026-11-26: SwiftUI presentations, gestures, toolbars; NSImage; ABI fixes from the target app

- `Presentation.swift`: alerts and confirmation dialogs (any button closes
  them), sheets and popovers (`dismiss` closes them), inspectors, file
  importers (`$BITTEN_PICK` stands in for the panel), tap/drag gestures
  (`onTapGesture`, `gesture`, `DragGesture.onChanged/onEnded`), key
  handlers (`onKeyPress`, `onExitCommand`, `onMoveCommand`), toolbars
  drawn above the content, `safeAreaInset`, accessibility modifiers
  (accepted, unused), and the hint modifiers (scrolling, list style,
  symbols, pointer, help) that keep the content as it is.
- AppKit: `NSImage` (from data, files and bundles through ImageIO; drawing
  handlers; lockFocus; SF Symbol placeholders), `NSImageRep`,
  `NSBitmapImageRep`, `NSImageSymbolConfiguration`.
- ABI, from the app's code: `Binding` is frozen (passed in registers),
  `Bindable` resilient; the App value's dynamic properties are installed
  once and kept; `swift_readAtKeyPath` is called without the value type,
  which now comes from the key path.
- Target app window (total `^MISSING`): 700 -> 454.

## 2026-11-26: JPEG (PR: jpeg)

- Baseline and extended sequential JPEG (`coregraphics/jpeg.c`): Huffman
  DCT, 8-bit grey or YCbCr with any chroma subsampling, restart
  intervals, Adobe RGB; to opaque RGBA. Image sources decode it after
  PNG; `CGImageCreateWithJPEGDataProvider`. Progressive, arithmetic and
  lossless files are recognised as JPEG but not decoded.
- Test: `tests/c/jpeg` (samples made with PIL: 4:4:4, 4:2:0, grey at
  odd sizes, a progressive file).
- Target app window (total `^MISSING`): 454 -> 454 (images the program
  loads at run time; no import changes).

## 2026-11-26: Parameter packs in the runtime (PR: packs)

- Swift runtime (`swift/packs.c`, taken over from the runtime side for
  this): generic contexts with packs (their pack shape header and
  descriptors; pack lengths at the start of the key arguments), metadata
  and witness-table packs moved to the heap and uniqued (tagged in the low
  bit, the length before the elements) before they key the metadata cache,
  `swift_allocateMetadataPack` and `swift_allocateWitnessTablePack`.
  `swift_getGenericMetadata` no longer stops on packs.
- Conformances: conditional requirements over packs (`where repeat each T:
  P`) are checked element by element and give a witness-table pack;
  conformance descriptors' conditional pack shape descriptors (flags bits
  24-31) are skipped, so their witness tables are found.
- Demangling: `QP` packs in mangled names (`Group<Pack{Int, String}>`),
  printing them; parameter lookup past the pack lengths.
- Charts: builders with several marks (BuilderTuple) now draw.
- Tests: `tests/swiftlib/packs`, `tests/swiftlib/charts` (three marks in
  one builder).
- Target app window (total `^MISSING`): 454 -> 454 (run-time support; the
  app now gets past the renderer error to NSPasteboard).

## 2026-11-26: FormatStyle and TimeZone (PR: formatstyle)

- Foundation (`swift/FormatStyle.swift`, taken over from the Foundation
  side): `FormatStyle`, `ParseStrategy`, `ParseableFormatStyle`; number
  styles (`IntegerFormatStyle`, `FloatingPointFormatStyle` and their
  `Percent`) with `NumberFormatStyleConfiguration`'s precision
  (fraction length, significant digits, integer length) and grouping, the
  locale's decimal and grouping separators (a table of common locales),
  parsing (`Double(_:format:lenient:)`), and as a regex component giving
  the value (`.localizedDouble(locale:)`); `ListFormatStyle` ("a, b, and
  c", or, narrow); `Date.FormatStyle`'s date and time styles in the local
  zone (en_US patterns); `Date.ISO8601FormatStyle` with every separator
  choice, fractional seconds and zones, formatting and parsing;
  `formatted()` on integers, floating point, dates and sequences.
- `swift/TimeZone.swift` (minimal, agreed): fixed-offset and named zones,
  the latter's transitions read from /usr/share/zoneinfo (TZif); current
  from TZ or /etc/localtime; offsets, DST, abbreviations.
- `_StringProcessing`: `Regex(_bittenPattern:transform:)`, a regex whose
  Output is made from the match.
- Not yet: NSListFormatter, NSISO8601DateFormatter, TimeZone bridging
  (Foundation's Objective-C side).
- Test: `tests/swiftlib/formatstyle`.
- Target app window (total `^MISSING`): 454 -> 394.
## Pasteboard, item providers, Canvas, and ABI fixes from the target app's code

- AppKit: NSPasteboard and NSPasteboardItem (typed pasteboard-type
  constants; the general pasteboard's text syncs with `$BITTEN_CLIPBOARD`).
  Foundation: NSItemProvider.
- SwiftUI: GraphicsContext and Canvas (fill, stroke, clip, text, layers,
  transforms, gradients, shadows), LinearGradient, Material, ScaledMetric,
  ImageRenderer, `Transaction.animation`, PreferredColorSchemeKey, more
  confirmation dialogs, spring and timing-curve animations.
- ABI, from the app's disassembly: `Animation` and `AnyTransition` are one
  reference wide (boxes); `GraphicsContext` is frozen around one storage
  reference, with resilient `Shading`/`Filter` and a frozen Int32 BlendMode;
  `BlendMode` and `RoundedCornerStyle` are resilient enums;
  `_IdentifiedViewTree` is an enum; LocalizedStringKey stays frozen.
- Mangling: Slider `label:` inits, NavigationSplitView and FocusState
  inits with method-level where clauses, unconstrained LabeledContent,
  distinct ButtonStyleConfiguration.Label and CurrentValueLabel.
- Runtime: accessor-function references inside an opaque type's underlying
  type get their generic arguments laid out from the flat list (they were
  called with NULL). `_availability_version_check` answers for macOS 15
  instead of "everything is available", which sent the app down
  `#available` branches into NULL weak imports.
- Target app window (total `^MISSING`): 394 -> 313.

## 2026-11-26: SIMD; Collection.popFirst (PR: simd)

- Standard library (`tools/gen-simd.py`, taken over from the stdlib side):
  `SIMDStorage`, `SIMDScalar`, `SIMD`, `SIMD2`...`SIMD64` and `SIMDMask`
  with Apple's frozen layouts: each scalar's `SIMDnStorage` is a
  `Builtin.Vec<n>x<T>` with Apple's alignment (the vector's size, at most
  16), SIMD3 stores in SIMD4's storage. So SIMD2<Float> is 8 bytes,
  aligned 8, and passes in registers as Apple's does. Element access,
  x/y/z/w, halves, arithmetic for floating point and integers, masks from
  `.==` `.<`..., `any`/`all`, sums, minimum and maximum, Codable,
  Hashable, descriptions.
- `Collection.popFirst()` where the collection is its own slice: the
  Codable code the compiler derives for payload-less enums calls it.
- Test: `tests/swiftlib/simd`.
- Target app window (total `^MISSING`): 313 -> 310.

## 2026-11-26: PhotosUI (PR: photosui)

- `PhotosUI.framework`, Objective-C and Swift in one framework like
  Foundation: `PHPickerViewController` (an AppKit view controller) with
  its Swift initialiser and delegate, `PHPickerConfiguration` (filter,
  selection limit, representation mode, selection), `PHPickerFilter`,
  `PHPickerResult` over NSItemProvider, `PHPickerViewControllerDelegate`.
  There is no photo library here: a picker that appears finishes once
  with no results, as when the user cancels.
- Test: `tests/swiftlib/photosui`.
- Target app window (total `^MISSING`): 310 -> 293.

## Colour spaces, dynamic colours, layers, animation contexts, NSView state, NSProgress

- AppKit: NSColorSpace (sRGB, extended sRGB, Display P3 with real
  P3/sRGB conversion, gray spaces) and NSColor's colour-space methods;
  dynamic colours (`colorWithName:dynamicProvider:`, resolved against the
  current drawing appearance on each read) and the system colours built
  on them; NSView backing layers (CALayer looked up at run time, so AppKit
  does not link QuartzCore) and layer policies; NSVisualEffectView;
  NSAnimationContext groups (changes apply at once, completions run on the
  next main-loop turn) and animator proxies; NSView alpha, tooltips,
  tracking areas, safe area, layout requests, rect and backing
  conversion; NSShadow; NSTrackingArea.
- Foundation: NSProgress (unit counts, children reporting to parents,
  cancel/pause/resume handlers); NSItemProvider loaders return one.
- SwiftUI: `Text(LocalizedStringResource)`, `Text(_:format:)` on the new
  FormatStyle, NSHostingSizingOptions and the hosting `sizingOptions`,
  `safeAreaRegions`, `sizeThatFits(in:)`; MeshGradient (SIMD2 now exists).
- Target app window (total `^MISSING`): 310 -> 274.

## 2026-11-26: AttributedString (PR: attributed)

- Foundation (`swift/AttributedString.swift`, taken over from the
  Foundation side): `AttributedString` as a String with runs of attributes
  (adjacent equal runs merge); `AttributedStringKey`, `AttributeScope`,
  `AttributeScopes` with `FoundationAttributes` (link, inline presentation
  intent, language, alternate description); attributes by key, by dynamic
  member and by scope (`s.swiftUI.foregroundColor` once SwiftUI declares
  its scope), over the whole string or a range (`AttributedSubstring`);
  `AttributeContainer`, `ScopedAttributeContainer`; concatenation,
  replacing, inserting, `range(of:)`; `Index` and String index conversion;
  the character view; localized initialisers and the attributed-string
  interpolation of `String.LocalizationValue`.
- Not yet: NSAttributedString and its bridging (Foundation's Objective-C
  side), the runs view beyond `_bnRuns`.
- Test: `tests/swiftlib/attributed`.
- Target app window (total `^MISSING`): 274 -> 230.

## 2026-11-26: UTType for item providers (PR: uttype-load)

- `NSItemProvider.loadFileRepresentation(for:openInPlace:completionHandler:)`
  and `registeredContentTypes`, on Foundation's NSItemProvider and
  NSProgress.
- Test: `tests/swiftlib/uttype` (a file loaded by type).
- Target app window (total `^MISSING`): 230 -> 229.

## Scroll views, text fields, string drawing, attributed strings, accessibility

- Foundation: NSAttributedString and NSMutableAttributedString,
  toll-free bridged to CFAttributedString (the CF type's class now
  subclasses NSMutableAttributedString): attributes and effective/longest
  ranges, substrings, enumeration, editing, equality.
  `-rangeOfString:options:range:`.
- AppKit: NSScrollView, NSClipView and NSScroller (the clip view's bounds
  origin is the scroll position; wheel scrolling, constraining, scroller
  knob values, live-scroll and bounds notifications, `scrollRectToVisible:`);
  string drawing through CoreText (`drawAtPoint:withAttributes:`,
  `sizeWithAttributes:`, attributed `size`/`drawInRect:`, wrapping);
  NSTextField labels and fields (fonts, colours, alignment, wrapping,
  line limits, placeholders, intrinsic size); NSControl text state; content
  hugging and compression priorities; the NSAccessibility properties on
  responders, menus and menu items.
- Test: tests/foundation/attributed.m (attributed strings, NSProgress).
- Target app window (total `^MISSING`): 229 -> 225.

## 2026-11-26: NSTimeZone, NSISO8601DateFormatter, NSListFormatter (PR: nsformatters)

- Foundation (`NSFormatters.m`, handed over): NSTimeZone (fixed offsets,
  TZif zones with their transitions, system/default/local zones,
  abbreviations, DST), NSFormatter, NSISO8601DateFormatter (every format
  option, formatting and parsing), NSListFormatter ("a, b, and c", with an
  item formatter); `TimeZone` bridges to NSTimeZone.
- Test: `tests/media/formatters`, `tests/swiftlib/formatstyle` (bridging).
- Target app window (total `^MISSING`): 225 -> 222.

## 2026-11-26: AttributedString and NSAttributedString (PR: attr-bridge)

- `NSAttributedString(_: AttributedString)` and
  `AttributedString(_: NSAttributedString)`: text and runs both ways (run
  lengths converted between characters and UTF-16), attribute values as
  their objects.
- Foundation's own keys: `NSPresentationIntentAttributeName`,
  `NSInlinePresentationIntentAttributeName`, the alternate description and
  language identifier keys.
- Test: `tests/swiftlib/attributed` (a round trip).
- Target app window (total `^MISSING`): 222 -> 221.

## 2026-11-26: Display: windows kept on the page (PR: display-fit)

- An AppKit program's window, drawn by NSView/CoreGraphics/CoreText,
  reaches the browser end to end (checked with a window and text,
  screenshot through headless Chromium).
- The page keeps a window inside the viewport where it is placed: AppKit
  places windows on a 900-point-high screen, so on a shorter page they
  landed below the fold.
- Build: display.o depends on page.h (edits to page.html did not reach
  mrun).
- Target app window (total `^MISSING`): 221 -> 221.

## Controls and value classes, constrained existentials, subview ordering

- Runtime: extended existentials (`any P<T>`, `any Sequence<Int>`): the
  `Xj` mangling with unique and non-unique shape references, and
  `swift_getExtendedExistentialTypeMetadata` (+ `_unique`) and
  `swift_getExtendedExistentialTypeShape`. Values are laid out like plain
  existentials of the shape's kind, with only the non-generalization key
  arguments stored after the value. Test: tests/swiftlib/xexistential.
- AppKit: NSImageView, NSButton (push, check, radio, image buttons, states,
  key equivalents, drawing, intrinsic size), NSProgressIndicator (bar and
  spinner), NSSegmentedControl, NSCursor, NSParagraphStyle and
  NSMutableParagraphStyle, NSGradient, NSSound (silent), haptic feedback,
  NSAccessibilityCustomAction, NSGestureRecognizer with click and press
  recognizers; symbol configuration constructors; NSView
  `addSubview:positioned:relativeTo:`, `replaceSubview:with:`,
  `setSubviews:`, `sortSubviewsUsingFunction:context:`,
  `ancestorSharedWithView:`.
- Target app window (total `^MISSING`): 221 -> 221 (run-time gaps only;
  the app now stops at Auto Layout, `-[NSView widthAnchor]`).

## Toolbars, popovers, alerts, the status bar

- AppKit: NSToolbar built from its delegate (default identifiers, items
  made by the delegate, standard space items, insert/remove with the
  will-add/did-remove notifications, validation, centering), NSToolbarItem,
  NSToolbarItemGroup, NSMenuToolbarItem; NSTitlebarAccessoryViewController;
  NSPopover as a borderless child window beside its anchor (show/close,
  delegate, notifications); NSAlert laid out in a panel (message,
  informative text, accessory, suppression button, buttons right to left
  with return/escape) run modally or as a sheet; NSStatusBar, NSStatusItem,
  NSStatusBarButton. NSLayoutAttribute, toolbar identifiers and
  notifications.
- Test: tests/appkit/controls.m (buttons, segments, text fields, scroll
  views, toolbars, alerts, popovers, status items, colour spaces, dynamic
  colours, string sizing).
- Target app window (total `^MISSING`): 221 -> 221 (run-time classes only).
## Auto Layout

- AppKit: NSLayoutConstraint (item/attribute constructor, activate and
  deactivate, constant, priority, identifier, items, attributes and
  anchors), NSLayoutAnchor with its X-axis, Y-axis and dimension kinds
  (every equal, at-least and at-most form, multipliers, system spacing,
  offset anchors), NSLayoutGuide and `addLayoutGuide:`, NSView's anchors,
  `constraints`, add and remove, safe-area and margins guides, baseline
  offsets and `updateConstraints`. NSStackView: horizontal and vertical,
  spacing and custom spacing, edge insets, alignments, fill, fill-equally
  and gravity distributions, hidden views detached.
- A Cassowary solver in C (AppKitSolver.m, after Kiwi's algorithm) solves
  each view tree in `layoutSubtreeIfNeeded`, which a window now runs
  before it draws. Views that translate their autoresizing mask keep their
  frames as their masks say; the rest get hugging and compression
  resistance from their intrinsic sizes and have their frames set. A
  required constraint that cannot be met is dropped. Test: tests/appkit/layout.
- Target app window (total `^MISSING`): 221 -> 219. The app now runs past
  Auto Layout, to `-[NSTextField setAllowsWritingTools:]`.

## Split views

- AppKit: NSSplitView. Panes sit side by side or stacked, in a flipped
  view, with thick, thin or pane-splitter dividers. It supports
  `arrangesAllSubviews` and arranged subviews, holding priorities (the
  pane that holds least takes a resize), `adjustSubviews`, and
  `setPosition:ofDividerAtIndex:` with the minimum and maximum possible
  positions. All the delegate's methods are used: min and max coordinates,
  split position, `canCollapseSubview:`, double-click collapse, resizing
  subviews, adjust size, hiding dividers, effective rects, and will and did
  resize. Dividers can be dragged with the mouse, collapsing a pane that
  may collapse when dragged past half its minimum. Autosave uses AppKit's
  "NSSplitView Subview Frames" defaults key.
- NSSplitViewItem: default, sidebar, content-list and inspector behaviors,
  collapsing (no animation), `canCollapse`, minimum and maximum
  thickness, preferred thickness fraction and holding priority.
  NSSplitViewController is its split view's delegate, applies the items'
  limits, hides dividers next to collapsed edge items, and supports
  `toggleSidebar:` and `toggleInspector:`.
- The Auto Layout pass solves again when a split view moves its panes, so
  constraints inside panes follow. Test: tests/appkit/split.
- Target app window (total `^MISSING`): 219 -> 219 (NSSplitViewController
  and NSSplitViewItem were stubs).
## The text system, fonts as CTFonts, AppKit's Swift part, two lifetime fixes

- AppKit: key interpretation (`interpretKeyEvents:` into insertText: and
  the standard command selectors, with shift/option/command/control
  bindings); NSTextInputContext (handleEvent: drives an NSTextInputClient
  view's insertText:replacementRange: and doCommandBySelector:; views
  conforming to the protocol get one from `inputContext`); NSText and
  NSTextView (editing, caret and selection, line movement, deletion,
  copy/cut/paste, marked text, resizing to its text, delegate hooks);
  NSTextContainer, NSLayoutManager, NSTextAttachment, NSTextRange; Writing
  Tools settings; NSControl cell classes.
- Fonts: NSFont and NSFontDescriptor are toll-free bridged to CTFont and
  CTFontDescriptor as on macOS (CoreText's classes are re-parented under
  them at load through a new `class_setSuperclass`); the UI font family,
  metrics, traits, descriptors; NSFontManager.
- AppKit's Swift part (frameworks/AppKit/swift, built into the framework
  like Foundation's): CGRect fill/clip, NSGradient(colorsAndLocations:),
  NSSound.beep, NSMenuItem.sectionHeader, the resize-direction cursors;
  NSRectClip, NSBeep. NSCursorFrameResizePosition is an option set.
- Runtime: weak references to objects with their own reference counts
  (toll-free CF objects) retained through ARC's side table on load, so
  the balancing release freed them, and were never cleared; they now
  retain through objc_retain and CFRelease clears them before the object
  dies. `swift_deallocPartialClassInstance` releases Objective-C-rooted
  objects (the placeholder Swift allocates before calling a factory method
  imported as an initializer) the Objective-C way instead of tearing them
  down as native Swift objects.
- Foundation: composed character sequences, line and paragraph ranges;
  CFGetRetainCount declared.
- Tests: tests/appkit/text.m, tests/foundation/weakcf.m.
- Target app window (total `^MISSING`): 219 -> 202.

## Drag and drop

- AppKit: NSDraggingSession, NSDraggingItem, NSDraggingImageComponent,
  the NSDraggingSource, NSDraggingDestination and NSDraggingInfo
  protocols, `-[NSView beginDraggingSessionWithItems:event:source:]`, and
  `-[NSWindow registerForDraggedTypes:]`. A session writes its items to
  the drag pasteboard. Until the mouse goes up, the window hands its mouse
  events to the session. The session finds the innermost view under the
  pointer registered for one of the pasteboard's types (or a registered
  window, or that window's delegate), in any of the app's windows. It then
  runs entered, updated and exited, and on a drop runs prepare, perform
  and conclude with the operation the source's mask allows, then the
  source's ended and the destination's `draggingEnded:`. Destinations can
  enumerate the dragged items by class. NSString and NSURL conform to
  NSPasteboardWriting and NSPasteboardReading. Test: tests/appkit/dragging.
- Target app window (total `^MISSING`): 202 -> 202 (NSDraggingItem was a
  stub).

## SwiftUI's inlined types, tables, keyframes; flipped view geometry

- SwiftUI: the types Apple's inlinable code builds in apps, laid out as
  that code expects (_HoverRegionModifier, _InsetViewModifier,
  _MaskAlignmentEffect, _MatchedGeometryEffect, _PreferenceTransformModifier,
  HierarchicalShapeStyleModifier, _IndefiniteSymbolEffectModifier,
  StrokeShapeView, StrokeBorderShapeView, LimitedAvailabilityToolbarContent
  as one reference, GridLayout); Table, TableColumn, TableColumnBuilder,
  TupleTableColumnContent, TableForEachContent and the row/column content
  protocols; Keyframes and KeyframeTrackContent with their builders
  (buildExpression/buildPartialBlock/buildFinalResult); SwiftUI's
  attribute scope; ContentUnavailableView.search; `EnvironmentKey._valuesEqual`;
  Double and CGFloat Animatable; MutableCollection.move(fromOffsets:toOffset:);
  `Log.runtimeIssuesLog`; shader arguments and libraries; pointer styles;
  scroll positions; Anchor sources for CGRect and CGPoint; and more.
- Mangling: members of View whose closures are `@Sendable` are
  `nonisolated` (View is `@preconcurrency`, which drops `@Sendable` from
  its members' mangled names otherwise); keyframeAnimator's generic order;
  OpenURLAction's handler is not `@Sendable`. SwiftUI links Symbols.
- Foundation: SortComparator, SortOrder, KeyPathComparator, and
  sorting with comparators.
- AppKit: point and rect conversion and hit testing follow flipped views
  (y runs from the other edge of a frame when a view's flippedness differs
  from its superview's), as drawing already did. Test: tests/appkit/geometry.
- Target app window (total `^MISSING`): 202 -> 113.
## Open and save panels

- AppKit: NSPanel (floating, becomes-key-only-if-needed, works-when-modal),
  NSSavePanel and NSOpenPanel, as real panels that browse the file system.
  - **Listing:** a directory list (folders first, hidden files only on
    request, packages as files unless `treatsFilePackagesAsDirectories`),
    back and Up buttons, the path, the message, a name field when saving,
    the accessory view, New Folder, Cancel and the prompt button.
  - **Choosing:** entries the panel can't choose are dimmed: by
    `allowedContentTypes` (UTType objects or identifiers, matched by
    extension), `allowedFileTypes`, `canChooseFiles` and
    `canChooseDirectories`, or the delegate's `shouldEnableURL`.
    Command-click and shift-click select several when allowed. Clicking an
    existing file while saving takes its name.
  - **Navigating:** double-click goes into a folder or chooses a file.
    Arrows, Return and Escape work from the keyboard. With nothing
    selected and directories allowed, the folder shown is chosen.
  - **Saving:** the allowed type's extension is added to a typed name.
  - **Delegate:** validate, did-change-directory, user-entered-filename
    and selection-did-change.
  - **Running:** `runModal`, `beginSheetModalForWindow:completionHandler:`
    and `beginWithCompletionHandler:`. Test: tests/appkit/panels.
- Fix: `-[BNDynamicColor CGColor]` returned the CGColor of a colour ARC had
  already freed, which crashed text drawn in, for example,
  `disabledControlTextColor`. The resolved colour is now kept until the
  next call.
- Target app window (total `^MISSING`): 113 -> 113 (NSPanel, NSSavePanel
  and NSOpenPanel were stubs).

## The first window: environment in representables, event monitors, notification sequences

- SwiftUI: NSViewRepresentable and NSViewControllerRepresentable values get
  their dynamic properties (`@Environment`, `@State`...) installed before
  makeNSView/updateNSView, so `@Environment(Model.self)` in one works; a
  hierarchical style (`.secondary`) whose foreground is itself
  hierarchical levels the primary colour instead of recursing.
- AppKit: NSEvent local and global monitors (local ones see events before
  NSApplication sends them and may replace or swallow them) and the full
  NSEventMask set; NSDockTile; services provider; the application icon from
  the bundle; `orderedWindows`; `isFullKeyboardAccessEnabled`.
- Foundation: `NotificationCenter.notifications(named:object:)`, an
  AsyncSequence of notifications.
- The target application now opens its first window on the display
  server, then stops at NSAppleEventManager.
- Target app window (total `^MISSING`): 113 -> 108.

## Calendar, property-list coders, ranges, bridging, smaller Foundation classes

- Foundation (Swift): Calendar (Gregorian and ISO 8601 civil-date
  arithmetic in a time zone: components, dates from components, adding
  with month-end clamping, differences, start of day, ranges, intervals,
  comparisons at a granularity, next matching date), DateComponents,
  DateInterval; PropertyListEncoder/Decoder over PropertyListSerialization;
  NSRange's Hashable conformance and conversions to and from integer and
  String-index ranges; AffineTransform; bridging of CGFloat, Float,
  CGPoint, CGSize, CGRect and Locale; `NSNotFound`;
  FileManager.replaceItemAt; `String.data(using:)` declared on String (as
  the app links it) and the `.custom` decoding strategies and Data's
  custom deallocator without `@Sendable`, as in Apple's mangling.
- Foundation (Objective-C): NSLocale, NSCache (count and cost limits,
  oldest first eviction, delegate), NSAssertionHandler, the value
  transformer names, NSUserActivity, NSAffineTransform, NSDecimalNumber
  (double precision), NSFullUserName, NSHomeDirectoryForUser, socket and
  device file types. Property list formats have their Swift names.
- Test: tests/swiftlib/calendar (calendar arithmetic, plist round trips,
  UTF-16 ranges).
- Target app window (total `^MISSING`): 108 -> 62.
## Apple events and Cocoa scripting

- Foundation: NSAppleEventDescriptor.
  - **Values:** text (UTF-16), integers, doubles, booleans, type and enum
    codes, dates (seconds since 1904) and file URLs, with coercions
    between them.
  - **Containers:** one-based lists, keyword records, and Apple events
    with parameters and attributes (class, ID, return and transaction
    IDs, target).
  - **Sending:** `sendEventWithOptions:timeout:error:` to this process.
- NSAppleEventManager: `setEventHandler:andSelector:forEventClass:andEventID:`
  (wildcards included), removing handlers, the current event and reply,
  and suspension.
- Cocoa scripting:
  - **Classes:** NSScriptCommand (arguments, direct parameter, receivers,
    evaluation, `executeCommand` calling the receivers' handler method or
    `performDefaultImplementation`, script errors, suspension),
    NSScriptCommandDescription, NSClassDescription and
    NSScriptClassDescription.
  - **Standard commands:** count, exists, get, set, quit, close, delete,
    make, move and duplicate.
  - **Object specifiers:** property, index, name and unique-ID, converted
    to and from 'obj ' descriptors and evaluated by key-value coding.
  - **sdef dispatch:** an event with no handler goes to the command its
    sdef (`OSAScriptingDefinition`) declares. The sdef is read on first
    use, the command class is created and given its parameters by code,
    and its result or error becomes the reply.
  - **Tested** against the target app's own sdef (count, its own
    commands, and an unknown event, which gets -1708).
- There is no transport between processes: only events sent within the
  process arrive. Test: tests/foundation/appleevents.
- Target app window (total `^MISSING`): 62 -> 55. The app now gets past
  `+[NSAppleEventManager sharedAppleEventManager]`, to
  `-[NSWindow occlusionState]`.

## Core Apple events, menus, asset-catalog images, runtime aliases

- AppKit: the core Apple-event handlers installed as the application
  finishes launching (open, reopen, open documents, get URL, quit, show
  preferences, forwarded to the delegate); NSWindow.occlusionState;
  NSMenu delegates (asked to fill and update a menu before it is shown),
  fonts, widths, sizes, pop-up and context menus, item views, represented
  objects, subtitles and parent items; `NSImage(named:)` answers with an
  empty icon-sized image for names in the bundle's compiled asset catalog
  (Assets.car is not decoded yet).
- Runtime and overlays: the `__objc_autoreleasePoolPush/Pop` and
  `__swiftImmortalRefCount` spellings; `swift_stdlib_random`; `_ArrayProtocol`;
  `Selector(_:)`; AsyncThrowingStream's initializers and makeStream and
  AsyncStream's `yield()` with method-level where clauses (as mangled);
  os's `checkForErrorAndConsumeState` returning a value.
- Mangling: `Never: SortComparator` lives in Foundation (not a retroactive
  conformance in SwiftUI); the symbol-effect kind protocols do not refine
  SymbolEffect, so `T: ContentTransitionSymbolEffect, T: SymbolEffect`
  keeps both requirements.
- The target application now runs until NSXPCConnection.
- Target app window (total `^MISSING`): 62 -> 41.

## Keyed archiving, streams, Objective-C protocols in mangled names

- Foundation: NSCoder, NSCoding/NSSecureCoding, NSKeyedArchiver and
  NSKeyedUnarchiver in the NSKeyedArchiver format ($objects/$top with UIDs;
  collections, dates, URLs, data, custom NSCoding classes, shared and
  cyclic references, delegates, secure class checks), NSStream,
  NSInputStream and NSOutputStream over memory, buffers and files.
  Test: tests/foundation/archive.m.
- Runtime: an Objective-C protocol in a mangled name (symbolic reference
  0x0c) points at the image's protocol record, not at a reference slot;
  it was dereferenced, giving existentials like `any NSObjectProtocol` a
  garbage protocol. It now resolves to the runtime's protocol of that
  name.
- Target app window (total `^MISSING`): 41 -> 38.

## NSInvocation

- Foundation: NSMethodSignature (Objective-C type encodings split into
  arguments and return, each classified the System V x86-64 way: integer,
  SSE, mixed eightbytes for structs up to 16 bytes, memory above) and
  NSInvocation (arguments stored by value, retained on request, invoked
  through `dx_objc_invoke`, with `objc_msgSend_stret` for memory-class
  returns); `-methodSignatureForSelector:` from method type encodings.
- Runtime: `dx_objc_invoke` (src/frameworks/objc/invoke.S), a generic
  System V call loading six integer and eight vector registers and any
  stack words.
- Test: tests/foundation/invocation.m (integers, doubles and floats,
  NSRect in memory, a 32-byte struct return, stack-spilled arguments,
  object and point arguments).
- Target app window (total `^MISSING`): 38 -> 37.
## Processes, pipes, file handles, XPC

- Foundation: NSTask (Process).
  - **Launching:** posix_spawn, which runs Mach-O programs under mrun and
    Linux ones directly. Supports the executable URL or launch path,
    arguments, environment and working directory.
  - **Streams:** standard input, output and error from pipes or file
    handles; the parent closes its copies of the child's pipe ends.
  - **Ending:** termination status and reason (exit or uncaught signal),
    the termination handler, NSTaskDidTerminateNotification,
    `waitUntilExit`, and interrupt, terminate, suspend and resume.
- NSPipe. NSFileHandle:
  - **Opening:** descriptors, paths and URLs, plus standard input, output
    and error and the null device.
  - **I/O:** reads, writes, seeks, truncation, sync and close, in both
    the old and the throwing forms, plus the Swift `read(upToCount:)`,
    `readToEnd()`, `write(contentsOf:)`, `offset()` and `seekToEnd()`.
  - **Background:** readability and writeability handlers on dispatch
    sources, and the read-in-background notifications.
  - `DISPATCH_SOURCE_TYPE_WRITE` is now declared in the SDK.
- NSXPCConnection, NSXPCListener, NSXPCInterface and
  NSXPCListenerEndpoint.
  - **Named services:** a connection to a service never connects (there
    are none here). Messages through its proxies reach their error
    handlers (NSXPCConnectionInvalid), and the connection is invalidated.
  - **Anonymous listeners:** a connection to one in this process asks the
    delegate to accept, then each side's proxies send straight to the
    other side's exported object.
  - **Proxies** conform to the remote protocol, so Swift casts work, and
    forward through `forwardingTargetForSelector:`.
  Test: tests/foundation/process.
- Fix: `CFBundleCopyExecutableArchitecturesForURL` reads only a file's
  header, so executables over 64 MB (the target app's 92 MB server
  helper) are no longer reported as unreadable.
- Target app window (total `^MISSING`): 37 -> 30. The app now gets past
  `+[NSXPCConnection alloc]` and its helper check.

## Isolated deinit, Objective-C protocols in mangled names

- Concurrency: `swift_task_deinitOnExecutor`, used by isolated deinits
  (`@MainActor` classes on current OS versions). The deinit runs now when
  already on the actor's executor, and is enqueued there otherwise. The
  target app imports it weakly, so it was bound to NULL and its
  Workspace.Model deinit jumped to address 0.
- Swift runtime: symbolic references to Objective-C protocols (kind 0x0c)
  can point at a relative pointer to the image's `__objc_protorefs` slot
  instead of at the protocol_t. Both forms are now followed. Type names
  fall back to the protocol_t's own name when the runtime has not
  registered the protocol.
- A heap object whose metadata has no destroyer is reported and leaked
  instead of called through a null pointer.
- Target app window: it now runs past its first window and the model
  teardown, to `+[NSMutableURLRequest requestWithURL:]` (networking, next).

## Unbound weak imports, os_release, file comparison

- Loader: `--check` now also lists system weak imports left unbound
  (`WEAK` lines, not counted as missing). Nearly all are macOS 26 APIs
  behind availability checks; a weakly imported `swift_task_deinitOnExecutor`
  was the app's jump to address 0, and this makes the next one visible.
- libSystem: `os_retain`, `os_release` (OS objects are Objective-C objects
  here) and `voucher_adopt`.
- Foundation: `-[NSFileManager contentsEqualAtPath:andPath:]` (bytes,
  link destinations, directories recursively); test
  tests/foundation/filecompare.m.
- The target application now stays up and draws its own SwiftUI window
  (its server start fails next: it runs `/bin/launchctl`).
- Target app window (total `^MISSING`): 30 -> 30.

## Networking: URLSession, URLRequest, WebSockets

- Foundation: NSURLRequest and NSMutableURLRequest (headers matched
  without regard to case, `addValue` folding), NSURLResponse,
  NSHTTPURLResponse (MIME type, charset, length, suggested filename,
  `localizedStringForStatusCode:`), NSCachedURLResponse, NSURLCache
  (in memory), NSHTTPCookie (Set-Cookie parsing, `Expires` and `Max-Age`,
  matching by domain, path and `secure`), NSHTTPCookieStorage,
  NSURLCredential, NSURLProtectionSpace, and NSURLSessionConfiguration
  (default, ephemeral, background).
- NSURLSession with data, upload, download and WebSocket tasks, by
  completion handler or by delegate (response disposition, data, redirects,
  sent body data, download progress and location, metrics, completion,
  invalidation). Everything the app sees runs on the delegate queue, in
  order.
  - **Transfers:** HTTP, HTTPS, file: and FTP go through the host's
    libcurl, loaded at run time (src/frameworks/urlsession/http.c). That
    gives HTTP/2, TLS through OpenSSL, proxies from the environment, and
    compressed bodies decoded.
  - **Redirects:** followed here, one hop at a time: 303, and 301/302
    after POST, become GET. The delegate may change or refuse each one,
    and there are at most 16 hops.
  - **Requests:** cookies are sent and stored; there is a default user
    agent; `data:` URLs are decoded here.
  - **Errors** are NSURLErrorDomain codes, with the failing URL.
  - **Metrics:** per transaction, with timings, addresses, ports, the
    protocol name, and the negotiated TLS version and cipher suite.
  - **WebSockets:** libcurl connects (and does TLS for wss); the opening
    handshake (with Sec-WebSocket-Accept checked) and RFC 6455 framing are
    here. That covers subprotocols, fragmented messages, pings and pongs,
    close codes and reasons, the maximum message size, and a reader that
    queues messages for `receive`.
- Swift:
  - **URLRequest:** a copy-on-write value bridged to NSURLRequest.
  - **WebSockets:** `URLSessionWebSocketTask.Message` with
    `send(_:completionHandler:)` and `receive(completionHandler:)`, plus
    async versions.
  - **Metrics:** `URLSessionTaskTransactionMetrics.negotiatedTLSProtocolVersion`
    (Security's `tls_protocol_version_t`, new in the SDK), cipher suite
    and ports.
  - **Async:** URLSession's `data`, `upload` and `download` methods, with
    task cancellation.
- Tests:
  - tests/foundation/urlsession runs against a local Python server
    (tests/foundation/urlserver.py) for HTTP and WebSockets.
  - tests/swiftlib/urlrequest covers the Swift side.
- Target app window (total `^MISSING`): 30 -> 11. The app now gets past
  `+[NSMutableURLRequest requestWithURL:]` and stays up (no crash in 40
  seconds).

## Drawing order: layers, representables, hierarchical styles

- AppKit: layer-backed views draw their backing layer: its background
  (rounded by `cornerRadius`, which also clips the content when
  `masksToBounds`), its border, its opacity (as a group) and sublayers the
  program added. The window background is filled through its `CGColor`
  (dynamic and catalog colours have no RGB components). `BITTEN_VIEW_TREE=1`
  prints each window's view hierarchy as it draws.
- SwiftUI: representables' AppKit views draw inline with the SwiftUI
  content, in SwiftUI's order: a background's view below the content, an
  overlay's above, content above the views before it. They were all drawn
  after the hosting view's own content, so the target app's window
  backdrop and surface cards covered its text. Their subview order follows
  the same order.
- SwiftUI: `.secondary` and the other levels apply once to the primary
  colour under a hierarchical foreground instead of compounding (0.5 x 0.5
  drew secondary text at a quarter); wrapped text lines up by
  `multilineTextAlignment`; `.opacity` multiplies into the enclosing alpha
  (`CGContextGetAlpha`, CoreGraphics SPI); `overlay(_:alignment:)` with a
  view.
- Tests: tests/appkit/layers.m; tests/swiftlib/swiftui.swift (`order`:
  representable z-order, centred text through a cross-module key path).
- Target app window (total `^MISSING`): 11 -> 11. Its window now shows its
  surface card with crisp text above it.

## System symbols drawn from their names

- AppKit: frameworks/AppKit/AppKitSymbols.m draws system symbol images
  (`NSImage(systemSymbolName:)`, SwiftUI's `Image(systemName:)`) from their
  names, since Apple's artwork is not ours to ship: a base glyph (arrow,
  chevron, xmark, plus, checkmark, ellipsis, magnifyingglass, gearshape,
  trash, doc, folder, terminal, sidebar, exclamationmark, questionmark,
  info, clock, globe, lock, bolt, person, and others) with its direction,
  inside a circle or square when the name says so, the glyph knocked out
  of the fill for `.fill`. Unknown names draw a small outlined square.
  Both NSImage and SwiftUI images use it (`bn_draw_symbol`), in the
  image's colour.
- Test: tests/appkit/symbols.m (every listed name draws, filled variants
  are knocked out; `SYMBOLS_PPM=path` writes the grid).
- Target app window (total `^MISSING`): 11 -> 11. Its status title shows
  its warning triangle instead of a grey block.
## launchctl without launchd

- There is no launchd. Running `/bin/launchctl` or `/usr/bin/launchctl`
  (through exec, posix_spawn or a PATH search, or after stat or access)
  runs mrun's own launchctl (src/loader/launchctl.c); the path maps to
  mrun when the host has no such file. Supported subcommands:
  - **Jobs:** bootstrap, bootout, kickstart [-k] [-p], print and list,
    plus the legacy load, unload, start, stop and remove.
  - **Accepted, no effect:** enable, disable, setenv and config.
  - **Information:** version, managerpid, manageruid and managername.
- Jobs live in a table under `$HOME/Library/bitten/launchd`, holding a
  copy of each job's plist (launchd keeps its own; callers delete theirs)
  and the job's pid.
  - **Starting:** bootstrapping starts the program if RunAtLoad or
    KeepAlive is set, detached in its own session. It gets the plist's
    arguments, environment, working directory and standard paths; Mach-O
    programs run under mrun.
  - **Stopping:** bootout sends TERM, then KILL if needed.
  - **Exit codes** follow launchctl's: 3 when there is nothing to boot
    out, 5 when bootstrapping a job that is already running, 113 when a
    service is unknown.
- Plists are XML (a small reader here); binary plists are refused.
  Test: tests/foundation/launchctl.
- Target app: its server helper now boots out, bootstraps and kickstarts
  its server as a LaunchAgent. The server stays up and answers
  `rex server status`.

## Custom button styles

- SwiftUI: a program's own `ButtonStyle` now builds the button (it was
  ignored and the label drawn plain): its `makeBody` wraps the label and
  the button keeps handling taps. A program's own `PrimitiveButtonStyle`
  makes the whole button, with `Button(configuration)` (added) for the
  usual body. The configuration's label is built where the style places
  it, so the style's foreground and font reach it. Built-in styles set
  further in clear a program's style.
- Test: tests/swiftlib/swiftui.swift (`styles`).
- Target app window (total `^MISSING`): 11 -> 11. Its "Start Again" and
  "Open Diagnostics" buttons draw in its own capsule styles.

## Views lay out when their size changes

- AppKit: a view now gets `layout` when its size or its subviews changed
  since it last laid out, the first time included, as well as when
  `needsLayout` is set. AppKit marks views as needing layout when their
  frames change; here nothing did. So views that place their subviews in
  their own `layout` (most of the target app's chrome: the tab bar and its
  surface stacks, the sidebar footer, the toolbar capsules) left them at
  0x0. The app sets only six constraints; the rest of its chrome is laid
  out by code.
- `BITTEN_LAYOUT_DEBUG=1` prints each constraint pass's counts and the
  constraints it skips or drops as unsatisfiable.
- Test: tests/appkit/layout (a view laid out by code, at first display
  and after a resize).

## Data's iterator, resilient superclasses, cells, frame setters

- Foundation: `Data.Iterator` is no longer `@frozen` (Apple's is not).
  Frozen, `_copyContents(initializing:)` returned its `(Iterator, Int)`
  whole through the indirect result, while programs take the iterator
  indirectly and the count in a register; the target app compared a
  pointer with the byte count and trapped about 20 seconds in.
- Swift runtime: classes whose superclass is in another resilient module
  (`BackingStorage` in the target app) get their metadata from the
  descriptor's pattern: `swift_relocateClassMetadata` allocates it at the
  size the superclass's bounds give, and the completion function fills it
  in as for any class.
- AppKit: NSCell, NSActionCell, NSButtonCell and NSTextFieldCell keep the
  state programs set through them (values, font, alignment, wrapping,
  state, target and action) and draw it; `NSControl.cell` is made from the
  class's `+cellClass` (a program's subclass included). Test
  tests/appkit/cells.m.
- AppKit: NSView `setFrameOrigin:`, `setFrameSize:`, `setBoundsOrigin:`,
  `setBoundsSize:`; `setFrame:` goes through the first two, as AppKit's
  does, so subclasses' overrides run.
- Target app window (total `^MISSING`): 11 -> 11. It runs past the trap,
  `BackingStorage`, `-[NSTextFieldCell initTextCell:]` and
  `-[NSView setFrameSize:]`.
## LZFSE and LZVN

- libcompression: COMPRESSION_LZFSE (0x801) and COMPRESSION_LZVN (0x900)
  in `compression_decode_buffer` and `compression_encode_buffer`
  (src/frameworks/compression/lzfse.c).
  - **Blocks:** the container's stored (`bvx-`), LZFSE (`bvx1`, and
    `bvx2` with its packed header and frequency tables), LZVN (`bvxn`) and
    end (`bvx$`) blocks, plus bare LZVN streams.
  - **LZFSE:** FSE decoding of the four interleaved literal streams and
    the L/M/D value streams, read backwards, with distances repeated and
    matches reaching into earlier blocks.
  - **LZVN:** its whole opcode set.
  - **Short buffers:** a buffer too small gets the beginning, as with the
    other algorithms.
  - **Encoding** writes stored blocks, which any LZFSE or LZVN decoder
    reads.
- Checked against every LZFSE and LZVN stream in the target app's three
  Assets.car catalogs: 980 streams, 666 MB, each block decoding to exactly
  its declared size. Among them is an SVG that decodes to valid XML, which
  is now a test vector. Test: tests/c/zlib.

## Font descriptors from files carry their names and traits

- CoreText: the descriptors `CTFontManagerCreateFontDescriptorsFromURL`
  returns now carry the style name, display name and traits as well as
  the PostScript name, family and URL, as CoreText's do.
- Checked against the target app's bundled Symbols Nerd Font: it
  registers, and it is found by PostScript name (`SymbolsNF`), by family,
  by descriptor, through matching, and through a collection.
- The app's "Could not find the bundled Symbols Nerd Font for titles"
  remains. It comes from the Ghostty renderer's resource preparation,
  which needs a Metal device (`MTLCreateSystemDefaultDevice` returns nil
  here), not from font lookup.

## Conformances in mangled names, the missing-selector sweep, NSCache keys

- Swift runtime: mangled names may carry protocol conformances
  (`HC`/`HP`/`Hr`/`HD`/`HI`/`HA`/`HO`, retroactive `g`), as the target
  app's opaque `onChange` results do. They are parsed and dropped (types
  resolve their conformances by lookup). A demangling failure names the
  operator it stopped at.
- AppKit (AppKitCompat.m): the AppKit selectors the target app references
  that nothing implemented. View alignment rects, `autoresizesSubviews`,
  key-view and live-resize hooks, `menuForEvent:`; responder forwarding
  for `mouseEntered:`/`mouseExited:`/`otherMouse*`/`cursorUpdate:` and
  `undoManager` (a window keeps its own); window saved-frame strings,
  `windowNumberAtPoint:belowWindowWithWindowNumber:`, `inLiveResize`,
  `isOnActiveSpace`; NSEvent `pressure`, `phase`, `momentumPhase`,
  `pressedMouseButtons`, `doubleClickInterval`; view controllers presented
  as sheets; `+[NSWindow standardWindowButton:forStyleMask:]`;
  `displayLinkWithTarget:selector:` on views, windows and screens
  (QuartzCore's CADisplayLink); NSImage drawing with `respectFlipped:`,
  `-[NSBundle imageForResource:]`, NSGradient from C locations, string
  drawing variants; NSBezierPath winding rules and
  `appendBezierPathWithArcFromPoint:toPoint:radius:`. Selectors listed by
  running the app's selector references against every method our
  classes have.
- QuartzCore: `-[CALayer convertTime:fromLayer:]`/`toLayer:` through the
  layers' begin times, speeds and offsets.
- Foundation: NSCache retains its keys instead of copying them (the app
  keys one with a plain Swift class); NSError recovery suggestion and
  options; NSFileManager `setAttributes:ofItemAtPath:error:` and
  `displayNameAtPath:`; `+[NSString pathWithComponents:]`. Test
  tests/foundation/cachekeys.m.
- SwiftUI: a hosting view's tree is not rebuilt or re-placed while it is
  being placed (AppKit views laid out during placement asked for it
  again), and GeometryReader keeps its old content alive while placing
  the new.
- Target app window (total `^MISSING`): 11 -> 11.

## SwiftUI: no rebuild under a tree being placed

- SwiftUI: an invalidation that arrives while a hosting view's tree is
  being placed (program code run during placement sets state or the root
  view) is deferred until placement ends, instead of dropping the tree
  under the nodes still running. `BITTEN_SWIFTUI_DEBUG` output goes to
  stderr unbuffered (it often comes just before a crash) and names each
  modifier's body type and each GeometryReader's content.
- Investigation notes for the next crash: under valgrind the target app
  shows an over-released bridged object (64 bytes, allocated by the app
  in a concurrency job, freed by one app release and retained again by
  another). The CoreUI deepmap2 bitmaps (compression 11, which hold
  almost all of the catalog's images) decode with LZFSE to about 7 bytes
  per ARGB pixel: an alpha plane first, then predicted residual planes,
  still to be worked out.
- Target app window (total `^MISSING`): 11 -> 11.

## Return conventions of frozen SwiftUI types, thread-safe Observation

- SwiftUI: `GeometryReader`, `ScrollViewReader`, `ScrollPhase` and
  `GestureMask` are `@frozen`, as in Apple's SwiftUI. Programs take a
  frozen value's result in registers (a GeometryReader in rax:rdx) and
  pass a frozen enum's self by value; ours returned them through an
  indirect result, so the target app stored two unrelated registers as its
  GeometryReader and later called a heap address. Found by auditing each
  imported SwiftUI function's call site in the app (indirect-result
  pointer set up before the call, or the result read from rax/rdx after)
  against our implementation's prologue.
- Observation: the registrar's tables are shared by every thread (the
  app mutates observable models from background tasks while views track
  them on the main thread); they are now used under a lock, tracking is
  per thread, and change callbacks run outside the lock.
- Runtime: when the Objective-C side slides a Swift class's ivars past
  its compiled start (our NSView is larger than the one programs were
  built against), the Swift metadata's instance size follows, and Swift
  subclasses lay out their fields from the larger of the two.
- Test: tests/swiftlib/handoff.swift (decoded values handed from
  background tasks to the main actor by every route, key paths over
  them, Observation from many threads; clean under valgrind).
- Target app window (total `^MISSING`): 11 -> 11. It now runs past the
  GeometryReader crash; the next one is a TupleView inside a mask
  modifier whose value the app lays out differently from our metadata.

## _MaskAlignmentEffect field order: the app runs

- SwiftUI: `_MaskAlignmentEffect` stores its alignment first and its mask
  second, as Apple's does. Programs build it inline (`mask(alignment:_:)`
  is inlinable): the target app wrote the alignment at offset 0 and built
  the mask at the second field's offset, which in our order overlapped
  both. Found by reading the app's body code for the modifier.
- The target application now stays up: its server runs, its window shows
  the onboarding page ("Get Started", Continue / Skip) with its tab bar
  and toolbar.
- Target app window (total `^MISSING`): 11 -> 11.

## Flipped layer geometry, compositing operations

- AppKit: a flipped view's backing layer has flipped geometry (as in
  AppKit), so text layers and contents in its sublayers draw upright; the
  target app's pane title was upside down.
- CoreGraphics: blend modes beyond normal, clear and copy: the
  Porter-Duff ones (source in/out/atop, destination over/in/out/atop,
  xor, plus lighter) and multiply, screen, darken, lighten. AppKit maps
  every NSCompositingOperation onto them for `NSRectFillUsingOperation`
  and NSImage drawing, so template tinting (draw the image, fill
  source-atop) colours the glyph instead of its whole square.
- Test: tests/appkit/compositing.m.
- Target app window (total `^MISSING`): 11 -> 11.

## A software Metal device

- Metal: `MTLCreateSystemDefaultDevice` returns a device now
  (frameworks/Metal/MetalDevice.m).
  - **Resources:** buffers (including no-copy), textures in R8, RG8,
    RGBA8, BGRA8 (and their sRGB forms), RGBA16F and RGBA32F, with
    replace/get bytes and views; samplers.
  - **Libraries** from files, URLs, data or a bundle's default.metallib.
  - **Pipelines,** with blending and write masks.
  - **Commands:** queues and command buffers (presenting, scheduled and
    completed handlers, waits), render encoders (buffers, bytes, textures,
    samplers, viewport, scissor, blend colour, plain, instanced and
    indexed draws of triangles and strips) and blit encoders.
  - **Drawables** come from CAMetalLayer's `nextDrawable`. Presenting one
    makes its pixels the layer's contents.
- Shaders are the program's own. A metallib holds one AIR module per
  function, and AIR is LLVM bitcode, so tools/metal-compile.py compiles it
  to x86-64 with clang.
  - **Intrinsics:** the AIR intrinsics a module calls are defined in LLVM
    IR (math, conversions); texture reads and sampling are in C
    (tools/metal-runtime.c), with AIR's constexpr sampler encoding read
    for filters and pixel or normalised coordinates.
  - **Calling them:** each function gets a plain C wrapper,
    `bn_call_<name>(args, out)`, taking 16-byte argument and result
    slots.
  - **Manifest:** a manifest records each argument (vertex or instance
    id, buffer, texture or sampler index, position, fragment input by
    name) and each output.
  - **Caching:** mrun compiles and caches the result under
    `~/Library/Caches/bitten/metal/<hash>`, then `dlopen`s it
    (src/frameworks/metal/metal.c). That needs python3 and a clang that
    reads current AIR (`BITTEN_CLANG`, else the Swift toolchain's or the
    system's).
- The rasteriser shades each vertex and instance, rasterises triangles at
  pixel centres with perspective-correct interpolation of vertex outputs
  into the fragment inputs of the same name (integer outputs flat), runs
  the fragment shader per pixel, and blends.
- The target app's renderer library compiles whole: all 12 of its
  functions (cell backgrounds, text with its glyph atlases, images, rects,
  row strips, overlays and transitions).
- Test: tests/metal/render, with hand-written AIR (tests/metal/shaders)
  packed by tools/metal-pack.py. It covers a cleared target, instanced
  triangles with interpolated colours, a texture read, alpha blending,
  blits and completion.
- Target app: its renderer still stops before asking for a device, with
  `Renderer.Error` 1, which is probably `fontUnavailable`; its font
  checks are next.

## More frozen SwiftUI types, hit testing in SwiftUI order, async let

- SwiftUI: `ContentMode`, `TextAlignment`, `Visibility`,
  `Image.Orientation` and `ScrollIndicatorVisibility` are `@frozen`, as in
  Apple's SwiftUI: programs pass them by value (the target app passed
  `aspectRatio`'s content mode in edi; ours read it through a pointer and
  crashed some runs). Found by checking which enums the app uses without
  importing their enum-case descriptors (resilient enums need them), then
  confirming at a call site.
- SwiftUI: hosting views hit-test in SwiftUI's order: a representable's
  AppKit view takes a click only where nothing SwiftUI draws above it
  does (the app's onboarding page has a key-handling view as a
  background); where SwiftUI has nothing, AppKit views the program added
  itself are tested. Controls and gestures inside a tap-gesture container
  take clicks first. The target app's Continue button now fires.
  `BITTEN_EVENT_DEBUG=1` logs what a click hits.
- _Concurrency: the `async let` entry points the compiler looks up
  (`_asyncLetStart`, `_asyncLet_get`, `_asyncLet_get_throwing`,
  `_asyncLet_finish`); compiling `async let` against our module crashed
  the compiler.
- Tests: tests/swiftlib/swiftui.swift (`hits`), handoff.swift (async let,
  actors, cancellation handlers, throwing streams and groups),
  multipayload.swift (generic multi-payload enums built by compiled code,
  taken apart through runtime layouts). All clean under valgrind.
- Target app window (total `^MISSING`): 11 -> 11.

## Gestures take clicks where their content draws

- SwiftUI: a gesture (onTapGesture and the like) takes a click only where
  its content draws something or has a content shape, as in SwiftUI, and
  controls inside it go first; `contentShape` makes a node of its own for
  this. Text, images, dividers, canvases, opaque shapes and AppKit views
  count as content; `allowsHitTesting(false)` content does not.
- The target app's onboarding now advances: Continue (a button whose
  style taps through a gesture) moves to the appearance page (colour
  scheme, toolbar layout).
- Target app window (total `^MISSING`): 11 -> 11.

## Compiled asset catalogs: images from Assets.car

- AppKit (AppKitAssets.m): `NSImage(named:)` reads the bundle's
  Assets.car. The BOM store's FACETKEYS give each name's attributes,
  KEYFORMAT the attributes of rendition keys, RENDITIONS the CSI
  renditions; the best rendition (light appearance, sRGB, highest scale)
  is drawn. Links (layout 1003) crop their rectangle out of the packed
  atlas their KLNI record names (rectangles measured from the atlas's
  bottom). Bitmaps are LZFSE/LZVN pixels or deepmap2 (compression 11):
  per band, an alpha plane, a predictor per row (none, left/up selector,
  left, up, mean), and 16-bit sign-magnitude YCoCg residuals, high bytes
  then low; also the raw, lossless and palette methods and KCBC bands.
  The format is as described by the public carfile-go reader (no Apple
  code), and was checked against the target app's catalog. Vector
  renditions (PDF, SVG) still get an empty stand-in.
- SwiftUI: `Image("name")` and `Image(nsImage:)` draw the AppKit image
  (templates in the foreground colour); `Image(nsImage:)` was a
  placeholder.
- Test: tests/appkit/deepmap2.m (a hand-made blob).
- Target app window (total `^MISSING`): 11 -> 11. Its onboarding shows
  its artwork and previews.

## Apple font names; font matching that can say no; validated 0x0c references

- CoreText (font.c): a font asked for by an Apple name (.AppleSystemUIFont,
  .SFNS, SF Mono, Menlo, Monaco, Helvetica, Courier, Times, Lucida Grande,
  Geneva, Andale Mono, ...) reports that font's family, PostScript and full
  names (`Menlo`, `Menlo-Regular`) rather than the stand-in's, so programs
  that compare names see what a Mac shows. Book/Roman styles report Regular.
  `BITTEN_CT_DEBUG=1` traces lookups.
- `CTFontDescriptorCreateMatchingFontDescriptors` returns NULL for a family
  or name that is neither installed nor an Apple font, as on a Mac. It used
  to match everything, so programs that probe for an optional bundled font
  believed they had it. Matches carry the reported name and family.
- Swift runtime (demangle.c): symbolic reference kind 0x0c is either a
  protocol descriptor or a relative pointer to an `__objc_protorefs` slot;
  the target is now checked to be mapped (mincore) and to name an
  identifier before either reading is taken.
- Test: tests/c/coretext.c checks the reported names and matching.
- Target app (total `^MISSING`): 11 -> 11. Its renderer now creates the
  Metal device, compiles its 12-function library and builds all 5
  pipelines.

## SwiftUI: frozen MatchedGeometryProperties and Anchor.Source (heap corruption)

- The intermittent crash (about 1 run in 4: bad key paths in
  `Environment._install`, or glibc "unaligned tcache chunk") was heap
  corruption. `MatchedGeometryProperties` and `Anchor<Value>.Source` are
  `@frozen` in Apple's SDK, and ours were not. Their static getters
  (`.frame`, `.position`, `.bounds`) therefore returned through an indirect
  buffer at whatever address was in rax, while the app reads the value from
  eax/rax. One call site has a hash value in rax, so 4 bytes landed at a
  random heap address. Both are now frozen.
- The valgrind use-after-free reports chased earlier were an artifact.
  Valgrind puts the heap below 4 GiB, and x86-64 macOS Swift treats
  pointers below that as extra inhabitants (so an Optional holding one
  reads as nil and is copied without a retain). Run valgrind with
  `--aspace-minaddr=0x200000000 --main-stacksize=268435456`.
- Check for this class of bug: an SDK struct or enum that the app imports
  functions for but whose metadata accessor (`Ma`/`Mn`) it never imports is
  frozen in Apple's SDK.
- Target app (total `^MISSING`): 11 -> 11. 0 crashes in 8 runs (was about 1 in 4).

## SwiftUI: scroll content at its ideal size; node tree dump

- Stacks placed at exactly their ideal length (as scroll views place their
  content) now give every child its ideal size. Before, a section with a
  `maxWidth: .infinity` header inside a horizontal ScrollView swallowed the
  extra width. The content overflowed and was centred, so the target app's
  theme carousel showed only empty space.
- Flexible stack children now get their shares one at a time, largest first
  and spacers last, each from what the others left. A child that cannot
  shrink to its share no longer pushes the stack past its bounds.
- `BITTEN_SWIFTUI_TREE=1` prints every laid-out SwiftUI node: its class,
  the chain of view types that built it, and its frame.
- Test: tests/swiftlib/swiftui.swift `scrollstack`.
- Target app (total `^MISSING`): 11 -> 11. The appearance page now shows the
  "Default theme" and "Built-in themes" cards.

## Casts to CoreFoundation types; crash reports

- Swift runtime (casts.c): a cast to a CoreFoundation type (a foreign
  class: CTFontDescriptor, CGColor, ...) from any object succeeds, as in
  Apple's runtime, where the compiler warns that such casts always do.
  `as? [CTFontDescriptor]` on a CFArray used to fail element by element,
  so the target app believed its bundled Symbols Nerd Font was missing
  ("Could not find the bundled Symbols Nerd Font for titles" is gone).
- Crash reports (signal.c): a fault the program does not handle (SIGSEGV,
  SIGBUS, SIGILL, SIGFPE, SIGTRAP) writes the signal, faulting address,
  registers and a frame-pointer backtrace, each address placed in its
  Mach-O image and nearest symbol (or in bitten itself via dladdr), to
  ~/Library/Logs/DiagnosticReports/<program>-<pid>.crash, then dies as
  before. Nothing goes to stderr, as on a Mac; BITTEN_CRASH_REPORT=stderr
  prints there instead, =0 turns it off. The main thread gets an alternate
  signal stack so stack overflows report too.
- CoreText: BITTEN_CT_DEBUG also traces fonts read from files.
- Test: tests/swiftlib/coretext (descriptors from a font file, cast to
  [CTFontDescriptor], their attributes and type).
- Target app (total `^MISSING`): 11 -> 11. The intermittent crash is now
  readable: swift_getAtKeyPath on a corrupt key path under SwiftUI's
  Environment._install during view graph building.

## SwiftUI: aspectRatio with one proposed dimension

- `.aspectRatio(_:contentMode:)` offered only a width (or only a height)
  now takes it and derives the other dimension from the ratio, as SwiftUI
  does. It used to fill the missing dimension with the child's ideal size (a
  shape's 10 points), so the target app's color-scheme previews were 10-point
  dots.
- Test: tests/swiftlib/swiftui.swift `aspect`.
- Target app (total `^MISSING`): 11 -> 11. Color-scheme cards show their
  previews. With #157 and the other session's crash reports: no crashes in
  5 runs of 30 s.

## AppKit: autoresizing masks; views draw outside their bounds

- `setFrameSize:` now calls `resizeSubviewsWithOldSize:`, and each subview's
  `resizeWithOldSuperviewSize:` applies its autoresizing mask. The size
  change is shared among the flexible margins and length in proportion to
  their lengths (equally when all are zero). Views laid out by constraints
  are skipped, and `autoresizesSubviews = NO` turns it off. Masks used to
  be stored and ignored, so the target app's preview overlays, created at
  zero size and sized by their masks, stayed 0x0. NSSplitView no longer
  resizes its panes a second time from its own `setFrame:`.
- Views clip their drawing only when `clipsToBounds` is set, their layer
  masks to bounds, or they are clip views. The default is NO for programs
  built with the macOS 14 SDK or later, as on a Mac.
- SwiftUI lays out AppKit views it places while drawing (after the
  window's layout pass), as AppKit would before drawing them at that size.
- `BITTEN_VIEW_TREE` also prints Auto Layout use, constraint counts and
  layer geometry.
- Test: tests/appkit/autoresize.m.
- Target app (total `^MISSING`): 11 -> 11. The appearance page's color-scheme
  and toolbar-layout previews show their miniature windows.
## Formatters and regular expressions

- Foundation (NSDateFormatter.m): NSDateFormatter with Unicode TR35
  patterns (eras, years, quarters, months, weeks, days, weekdays, periods,
  hours, minutes, seconds, fractions, zones as z/Z/O/X/x/V) both ways;
  parsing needs the whole string, narrows adjacent numeric fields to their
  width, reads zones as Z, offsets, GMT forms or abbreviations, and pivots
  two-digit years on twoDigitStartDate. The en_US date and time styles
  (with U+202F before AM/PM, as current macOS), relative "Today"/"Yesterday",
  dateFormatFromTemplate:, symbol arrays. NSByteCountFormatter (file and
  memory styles, adaptive digits, unit sets, "Zero KB", actual byte counts),
  NSDateComponentsFormatter (positional, abbreviated, short, full,
  spelled-out and brief; zero dropping and padding; maximum unit count;
  "About"/"remaining" phrases), NSRelativeDateTimeFormatter (numeric and
  named, four unit styles).
- Foundation (NSRegularExpression.m): NSRegularExpression on a backtracking
  engine over UTF-16 written here for ICU's syntax: sets with ranges,
  nesting and [:posix:] classes, \d \w \s \h \R \p{..}, anchors and word
  boundaries, captures named and numbered, back references, look-ahead and
  look-behind, atomic groups, lazy and possessive quantifiers, inline flags,
  \Q..\E, and the pattern options; a per-position step budget stops
  catastrophic backtracking. Enumeration, matches, first match,
  replacement templates ($n, ${name}, escapes), escaping.
  NSTextCheckingResult; NSDataDetector finds links (URLs, www. hosts,
  e-mail addresses as mailto:) and phone numbers.
- SDK: these classes and their option types under Apple's Swift names
  (DateFormatter.Style, NSRegularExpression.Options, ...); Formatter,
  ISO8601DateFormatter and ListFormatter named too. NSLocale and NSTimeZone
  bridge to Locale and TimeZone.
- Tests: tests/foundation/regex.m, tests/foundation/formatters.m,
  tests/swiftlib/formatters.
- Target app (total `^MISSING`): 11 -> 2 (NSXMLParser, NSXMLDocument).

## AppKit: .icns images and the application icon; SwiftUI button styles get their environment

- `NSImage initWithData:` reads icon files (.icns). Each PNG entry becomes a
  bitmap representation sized in points (ic11-ic14 and ic10 are @2x),
  largest first. The image takes the largest point size.
- `NSApp.applicationIconImage` returns the bundle's icon. A leftover
  property stub (always nil) had replaced the real getter, and the target
  app force-unwraps the icon on its last onboarding page, so it trapped.
- SwiftUI installs a button style's dynamic properties (`@Environment`,
  `@State`) before calling its `makeBody`, as it does for views. The app's
  styles read `controlSize`, `isEnabled` and theme values; Apple's inlined
  `Environment.wrappedValue` logged a runtime-issue fault for every read
  of an uninstalled one (about 2400 per run).
- Test: tests/appkit/icns.m.
- Target app (total `^MISSING`): 2 -> 2. All four onboarding pages render
  and Continue goes through to "You're all set".

## Foundation: NSThread lifecycle; _Concurrency: custom executors reachable

- NSThread now has a full lifecycle: `init`, `initWithBlock:`,
  `initWithTarget:selector:object:`, `start`, an overridable `main`,
  `cancel`, `isExecuting`, `isFinished`, `qualityOfService`,
  `threadPriority`, `stackSize`, `+exit` and `+isMultiThreaded`, plus the
  will-exit and will-become-multithreaded notifications. It used to offer
  only detached blocks. The target app subclasses NSThread for a worker
  and sets its QoS.
- `_swift_task_enqueueOnExecutor` and the `checkIsolated` /
  `isSameExclusiveExecutionContext` helpers are exported from
  `_Concurrency` (they were local symbols). The runtime looks them up by
  name to reach executors written in Swift. Actors with custom executors
  stopped with "not found" the first time a job was enqueued.
- Tests: tests/foundation/threads.m, tests/swiftlib/executors.swift.
- Target app (total `^MISSING`): 2 -> 2. "Start Using" now opens the main
  workspace window with a shell pane, whose process exits at once (next).

## libsystem: macOS login(1) for starting shells

- Exec'ing `/usr/bin/login` with macOS's non-interactive form,
  `login [-pq] [-h host] [-l] [-f] user [prog [args]]`, now does what
  macOS's login does: become the user (if needed and allowed), set HOME,
  USER, LOGNAME and SHELL (keeping the rest of the environment with -p),
  and exec the program or the user's shell. Unless -l is given it is a
  login session: argv[0] is "-name" and it starts in the home directory.
  Linux's login cannot run a program, so it exited with status 1.
  Interactive use still goes to the real login.
- Found with strace on the target app's server, which starts each terminal
  pane's shell through `login -flp`. The panes showed "Exited".
- Test: tests/c/login.c.
- Target app (total `^MISSING`): 2 -> 2. The workspace's shell pane now
  runs bash.

## XML: NSXMLParser, NSXMLDocument and XPath; NSError bridges to Error

- Foundation (NSXML.m): one XML 1.0 reader (the declaration and its
  encoding, UTF-8/UTF-16 BOMs and Latin-1, comments, processing
  instructions, CDATA, DOCTYPE with internal entity declarations, character
  and entity references, namespaces, line-end and attribute-value
  normalization) feeding NSXMLParser and the node tree. NSXMLParser calls
  its delegate as documented (namespace processing on or off, prefix
  mappings, CDATA, comments, abort) and reports well-formedness errors in
  NSXMLParserErrorDomain with libxml2's codes and the line and column.
  NSXMLNode, NSXMLElement, NSXMLDocument and NSXMLDTD: building, walking,
  attributes and namespaces, prefix resolution, string values, XMLString
  and XMLData (escaping, compact or expanded empty elements, pretty
  printing), XPath paths for nodes, whitespace-only text dropped unless
  NSXMLNodePreserveWhitespace. nodesForXPath: evaluates XPath 1.0 location
  paths with the main axes, node tests, predicates, comparisons, and/or/not
  and the common functions; prefixes resolve as declared in the document.
- SDK: XMLParser, XMLParserDelegate, XMLNode (Kind, Options), XMLElement,
  XMLDocument under Apple's Swift names. NSError now bridges to Error in
  Swift (as Apple's API notes make it), so delegate methods written with
  `Error` parameters match their protocols. CGRect's geometry functions
  are CGRect members in Swift (minX, maxY, width, insetBy, intersects,
  applying, ...), as in Apple's SDK.
- Tests: tests/foundation/xml.m, tests/swiftlib/xml, more of
  tests/swiftlib/coregraphics.
- Target app (total `^MISSING`): 2 -> 0. Every import resolves.

## AppKit: key events carry Mac characters for special keys

- Keys that type no text of their own now carry the characters a Mac
  reports. Return is "\r", Tab "\t", Delete 0x7F, Escape 0x1B, and keypad
  Enter 0x03. The arrows, Home/End, Page Up/Down, forward delete and
  F1-F12 use the function-key range (NSUpArrowFunctionKey...). With Control
  held, a letter (or @[\]^_) gives its control character in `characters`,
  while `charactersIgnoringModifiers` keeps the key's own. Before, Return
  arrived with no characters, so terminal views never sent a newline.
- `BITTEN_EVENT_DEBUG` logs each key down and the responder it goes to.
  `BITTEN_VIEW_TREE` marks flipped views.
- Checked in the target app: typing `touch <file>` and Return into its
  terminal pane creates the file (keys reach the shell through the
  terminal view, its server and the pty).
- Target app (total `^MISSING`): 2 -> 2.

## Windows stay upright: NSGraphicsContext saves the current context; drawing cannot leak states

- AppKit: +[NSGraphicsContext saveGraphicsState] and +restoreGraphicsState
  save and restore which context is current (per thread), as documented.
  Drawing that saved, switched to a bitmap context and restored used to
  restore the bitmap's state and leave one saved on the window's context;
  with the target app's terminal pane live, that left a flipped view's
  transform behind and the whole window came out upside down.
- AppKit and QuartzCore: a view's drawRect: and a layer's drawing are
  followed by dropping back to the graphics-state depth they started at
  (bitten_cg_gstate_depth / bitten_cg_restore_to_depth in CoreGraphics),
  so drawing that saves more than it restores cannot shift the views drawn
  after it; BITTEN_DEBUG names such views. A window whose context still
  starts a frame transformed gets a fresh one.
- Test: tests/appkit/drawing.m (a view leaving states saved inside a
  flipped view; offscreen drawing between save and restore).
- Target app (total `^MISSING`): 0 -> 0.

## AppKit: modifier keys are flags-changed events; window alpha; SwiftUI watches builder reads

- Modifier keys pressed alone (key codes 54-63) arrive as
  NSEventTypeFlagsChanged, as on a Mac. Before, they were key-downs with
  no characters, which terminal views handle as typing.
- A window whose `alphaValue` is 0 is not shown, and is shown again when
  its alpha rises (panels kept ordered in but faded out).
- SwiftUI also watches @Observable reads made while building outside any
  view body (container builder closures, styles), and while laying out.
  A change to one of those rebuilds the host, as for body reads.
- Debugging: `BITTEN_EVENT_DEBUG` logs where Command keys go (a local
  monitor, the main menu, the window), windows ordered front and alpha
  changes. `BITTEN_SWIFTUI_TREE` logs observed changes.
- Found while trying the target app's shortcuts. ⌘↩ adds a pane. ⇧⌘P is
  taken by the app's local monitor, and its CommandPalettePanel, a
  separate window ordered in at launch, is stacked under the main window
  by the display (next: window styles and levels on the display).
- Target app (total `^MISSING`): 0 -> 0.

## The display page: borderless and transparent windows, window levels, order-front

- Display (display.c, page.html): bitten_display_set_style(window, flags,
  level) gives a window its look and stacking: flags 1 borderless (no
  title bar or frame), 2 transparent (the page shows through where alpha
  is below 1); level is the NSWindow level and orders windows before focus
  does (pop-ups and floating panels above normal windows). It may come
  before the window's first frame; a window is not shown until it has one.
  bitten_display_order_front(window) raises a window within its level
  without focusing it. Window messages carry flags, level and front order
  after the size (the title now starts at byte 35). Borderless windows do
  not take focus or the page title on arrival.
- Test: tests/c/display.c.
- Target app (total `^MISSING`): 0 -> 0.

## SwiftUI: FocusState.Binding and Section layouts; AppKit: the rest of NSTextView's text API

- `FocusState.Binding` holds the whole focus state, as in Apple's SDK.
  For a Bool state that is three scalars the app passes in registers.
  Ours was a single box pointer, so `.focused($flag)` read the flag as a
  pointer and crashed.
- `Section` has Apple's fourth stored property, `isExpanded:
  Binding<Bool>?`. The app's inlined initializers build (header, content,
  footer, isExpanded) and bit-cast it to the Section type, after checking
  the sizes match, and trapped. Added the collapsible-section initializers
  (`Section(isExpanded:content:header:)` and the titled forms). A collapsed
  section shows only its header.
- NSTextView now has alignment, base writing direction and default
  paragraph style (applied to the text and the typing attributes), plus
  `setAlignment:range:` / `setBaseWritingDirection:range:` (whole
  paragraphs) and the align actions. Also: marked/selected/link text
  attributes, the ruler and inspector-bar flags, the automatic-substitution
  getters (the setters now remember), inline prediction,
  `replaceCharactersInRange:withString:`, `setFont:range:`,
  `setTextColor:range:`, `delete:`, `undo:`/`redo:`, `attributedString`,
  `performValidatedReplacementInRange:withAttributedString:`.
- Found by opening the target app's Settings window (⌘,), which now opens
  without stopping.
- Test: tests/appkit/text.m (NSTextView settings).
- Target app (total `^MISSING`): 0 -> 0.

## AppKit: window styles and stacking on the display

- Windows tell the display how to show them, through the other session's
  `bitten_display_set_style` (#173), sent before a present when it changes:
  - borderless when the style mask has no title bar,
  - transparent when not opaque or the background colour has alpha,
  - stacked by `level` (floating panels above normal windows).
- Ordering a window front (`orderFront:`, `makeKeyAndOrderFront:`,
  `orderFrontRegardless`) raises it on the display with
  `bitten_display_order_front`.
- The target app's ⇧⌘P command palette (a borderless floating panel) now
  appears above the workspace with its commands and shortcuts. Its
  Settings window (⌘,) opens in front of the workspace.
- Target app (total `^MISSING`): 0 -> 0.

## SwiftUI: safeAreaInset returns Apple's ModifiedContent

- `safeAreaInset(edge:alignment:spacing:content:)` is `@inlinable` in
  Apple's SDK, so programs see through its opaque result to
  `ModifiedContent<Self, _InsetViewModifier<V>>` and lay that type out
  themselves. Ours returned a different view type under the same opaque
  signature, so the app read garbage as the inset modifier (its settings
  sidebar's search field landed beside the list, half-width). It now
  returns exactly that ModifiedContent. Added the leading/trailing
  (`HorizontalEdge`) overload.
- To check: an app's type names (`BITTEN_SWIFTUI_DEBUG` modifier bodies)
  that contain our internal types, like `_InsetViewModifier`, come from
  functions that are inlinable in Apple's SDK. Ours must build the same
  types.
- `BITTEN_SWIFTUI_BODY=Name` prints the body type of views whose type name
  starts with Name.
- Test: tests/swiftlib/swiftui.swift `inset`.
- Target app (total `^MISSING`): 0 -> 0. Its Settings sidebar shows the
  search field above full-width sections.

## stdlib: `optional ?? optional`

- Added the `??<T>(T?, @autoclosure () -> T?) -> T?` overload. Without it,
  `a ?? b` on two Optionals picked the plain overload with T = U?. A nil
  left side became `.some(nil)` and was returned, so `b` was never
  consulted. Our frameworks are built against this stdlib and use the
  pattern. SwiftUI's overlays never passed hit tests to their content
  (`layer.hit ?? content.hit`), so buttons under any `.overlay` ignored
  clicks; the target app's settings sidebar was one. The app's own code
  inlines Apple's `??` and was not affected.
- `BITTEN_HIT_DEBUG` logs SwiftUI hosting views' hit tests.
- Test: tests/swiftlib/basics.swift `coalesce`.
- Target app (total `^MISSING`): 0 -> 0. Its settings sidebar items now
  respond to clicks.

## AppKit: segmented-control distribution; valgrind-friendly stack probes; object tracing

- NSSegmentedControl gains `segmentDistribution`, used when laying out and
  hit-testing segments. Fit uses content widths. Fill shares the extra width
  among segments without a set width. Fill-equally gives every segment the
  same width; fill-proportionally scales content widths. Also: per-segment
  menu indicators, alignment and image scaling, and spring loading. The
  target app's settings window sets the distribution.
- `___chkstk_darwin` lowers %rsp to each page before touching it. Probing
  below the stack pointer made valgrind kill the app with a "stack
  overflow" a few hundred KB into the main stack. The app now runs under
  valgrind (`--aspace-minaddr=0x200000000`) to its windows.
- Debugging: `BITTEN_TRACE_OBJ=Name` logs the allocation, destruction and
  freeing of Swift objects whose class name contains Name.
  `BITTEN_TRACE_BOX=Name` does the same for boxes of matching value types.
  Both print raw return addresses, newest first.
- Open: closing or rebuilding the app's Interface settings page crashes
  while list-row trait values (`listRowInsets` / `listRowBackground`) are
  destroyed. A box or AnyView storage they hold has already been freed
  (use after free). Isolated tests of the same patterns are clean.
- Target app (total `^MISSING`): 0 -> 0. Its Settings window opens, the
  sidebar responds, and the Interface page renders.

## SwiftUI: labelsHidden and grouped forms

- `labelsHidden()` now hides the labels of Toggle, Picker, Stepper and
  LabeledContent (it was a no-op). The target app's settings rows show
  their own text and hide the controls' labels, so each toggle repeated it.
- `formStyle(.grouped)` lays menu pickers out as label, space, control, as
  macOS settings rows do. They used to sit centred.
- Test: tests/swiftlib/swiftui.swift `labels`.
- Target app (total `^MISSING`): 0 -> 0.

## SwiftUI: VerticalEdge.Set is frozen (the settings use-after-free)

- Fixed the crash when the target app's settings pages are torn down.
  `VerticalEdge.Set` is `@frozen` in Apple's SDK, and ours was not, so our
  `VerticalEdge.Set.all` getter returned through an indirect buffer at
  whatever rax held. The app reads the result from eax. Its call comes
  right after `AnyView.init`, so rax was the new AnyView's storage object,
  and the getter wrote 3 into the low byte of that object's metadata
  pointer (from `listRowSeparator(_:edges: .all)`). The object crashed
  later when freed. This is the same class of bug as #157.
- Found with a hardware watchpoint. `BITTEN_WATCH_OBJ=Name` arms a
  `perf_event_open` write breakpoint (sigtrap) on the metadata word of each
  new object whose class name contains Name (the four newest). A write
  stops the writer with SIGTRAP and a crash report naming it.
- `BITTEN_HEAP_QUARANTINE=1|2|3` keeps freed memory poisoned (0xdd) instead
  of reusing it: 1 for Swift objects, 2 also raw `swift_slowDealloc`
  buffers, 3 also ObjC objects. Retains and releases of quarantined Swift
  objects are reported with backtraces.
- Dynamic-property installation refuses fields that would lie outside the
  value.
- Nested types are now in the frozen check: a nested type the app uses
  without importing its metadata accessor is frozen in Apple's SDK.
  `VerticalEdge.Set` was the only one left.
- Target app (total `^MISSING`): 0 -> 0. Settings pages (Interface, Themes,
  Terminal) open and switch without crashing.

## FocusState's real layout; availability checks see exactly macOS 15.0.0

- `FocusState<Value>` is {value, location, resetValue}, and
  `FocusState.Binding` wraps a SwiftUI `Binding<Value>` (transaction,
  location, value), as in Apple's SDK. Programs copy focus states, read the
  binding's words and release its references themselves. #174 had made the
  binding wrap the whole state, so the app released a Bool as a reference
  when opening the Shortcuts settings page. The focus box is now an
  `AnyLocation`.
- `__isOSVersionAtLeast`, `__isPlatformVersionAtLeast` and
  `_availability_version_check` compare the full version against 15.0.0.
  They compared only the major number, so `#available(macOS 15.4, *)`
  succeeded and programs called their weak imports of API added after
  15.0. The target app hit a null opaque-type descriptor
  (`_TagTraitWritingModifier`, `ForEach.create` and others).
- Test: tests/c/osversion.c.
- Target app (total `^MISSING`): 0 -> 0. Every settings page opens
  without crashing.

## Documentation: from import coverage to a visible terminal

- Refreshed the target-app and framework status. The server and window
  bind all required imports. The software Metal device produces terminal
  frames; drawing those frames into the AppKit window is a separate step.
- Documented how to choose the browser or X11 display, and separated the
  Docker shader-compiler gap and first-launch failures from missing imports.

## SwiftUI: Form scrolls and fills, rows from the top

- `Form` is a vertical scroll view filling its space, with its rows from
  the top and as wide as the form, as on macOS. It was a padded stack, so a
  short settings page (the target app's Developer page) sat vertically
  centred.
- Debugging: `BITTEN_SWIFTUI_TREE` shows text nodes' strings and logs host
  invalidations. `BITTEN_DISPLAY_DEBUG` logs each window display with its
  title.
- Target app (total `^MISSING`): 0 -> 0.

## Swift: dynamic casts between tuple types

- `swift_dynamicCast` now casts a tuple to another tuple type, as Apple's
  runtime does (`tryCastToTuple`). The element counts must match, and so
  must every label that both sides have, so `(Int, String)` casts to
  `(x: Int, y: String)` and back, `(x:, y:)` does not cast to `(a:, b:)`,
  and a partly labeled tuple matches on the labels it has. Each element is
  cast into the target's offset with the general cast, so `(Any, Any)` casts
  to `(Int, String)`. When an element fails, the elements already cast are
  destroyed.
- Fixes the target app's crash on "Skip for now" in onboarding: it casts
  an unlabeled `(TabID, BlockID)` to `(tabID:, blockID:)`.
- Test: tests/swiftlib/tuplecasts.swift (labels, element-wise casts,
  failure cleanup).
- Target app (total `^MISSING`): 0 -> 0. "Skip for now" goes to the
  workspace.

## AppKit: layer contents in windows; a Metal present redraws the window

- Layer-backed views now draw their backing layer's `contents` image,
  after the background and before `drawRect:`, placed by
  `contentsGravity` and `contentsScale` and upright in flipped views.
  Until now only sublayers that were not views drew their contents, so a
  view whose layer was a CAMetalLayer showed nothing. CALayer's own
  rendering and AppKit share one helper, `-_bn_drawContents:inRect:flipped:`.
- Presenting a CAMetalLayer drawable marks the nearest view up the layer
  tree as needing display, so the window redraws at the rate the program
  presents. Before, it only set the layer's own needs-display flag, which
  nothing read.
- Test: tests/appkit/contents.m (stretched, flipped and bottom-left
  scale-2 contents; a CAMetalLayer-backed view that presents a cleared
  drawable and shows up with no display call from the test).
- Open: `contentsRect` and IOSurface contents are not drawn. A custom
  `makeBackingLayer` layer gets no bounds from its view, so
  `nextDrawable` needs `drawableSize` set (the target app sets it).
- Target app (total `^MISSING`): 0 -> 0. Its terminal surface now shows
  the frames its Metal renderer presents: the prompt, typed commands and
  their output, and the cursor.

## Foundation: NSData no-copy initialisers and rangeOfData (the update-check crash)

- Fixed the target app dying about 10 s after its first launch. Its
  update check calls `+[NSData dataWithBytesNoCopy:length:freeWhenDone:]`,
  which NSData did not have, and right after that
  `-[NSData rangeOfData:options:range:]`, which it did not have either.
- `dataWithBytesNoCopy:length:`, `…freeWhenDone:`, and
  `initWithBytesNoCopy:length:`, `…freeWhenDone:` and `…deallocator:`. NSData
  borrows the caller's buffer and gives it back exactly once when the data
  is destroyed: `free()` for freeWhenDone, the deallocator block, or nothing.
  NSMutableData copies the bytes, so it can grow, and gives the buffer back
  straight away.
- CoreFoundation gains `CFDataCreateWithBytesNoCopy` (kCFAllocatorNull
  borrows, any other deallocator frees) and the private
  `bitten_cf_data_create_no_copy`, which takes a release callback for the
  block case. `kCFAllocatorMalloc` and `kCFAllocatorNull` are in the SDK
  header now.
- `rangeOfData:options:range:` handles backwards and anchored searches.
- Tests: tests/foundation/nocopy.m, tests/foundation/datasearch.m.
- Target app (total `^MISSING`): 0 -> 0.

## Docker: the Metal shader compiler in the test stage and the runtime image

- `docker build --target test .` failed `tests/metal/render` ("tools/metal-compile.py
  not found"). `find_tool()` looks for the compiler next to mrun
  (`<mrun dir>/../tools` or `<mrun dir>/tools`) or in
  `/usr/local/lib/bitten/tools`. In the image mrun is `/out/mrun` and the
  sources are in `/src`, so none of those existed.
- `make` now stages `tools/metal-compile.py` and `tools/metal-runtime.c` in
  `$(BUILD)/tools`, next to mrun as `root/` already is. Any build tree
  compiles Metal libraries, including one away from the sources.
- The runtime image copies `/out/tools` to `/usr/local/lib/bitten/tools` and
  installs Debian's clang, libc6-dev and binutils. clang reads Apple's AIR
  and links the shaders' shared object. Without them an app's renderer
  could not compile its shaders in the shipped container. The apt layer
  grows to about 524 MB (the image is 835 MB on disk).
- The "not found" error names where it looked and `BITTEN_METAL_COMPILER`.
- Tests: `tests/metal/staged.sh` (in `make check`) runs the render test
  with a copy of mrun and `$(BUILD)/tools` in a directory with no source
  tree beside it, on a cold shader cache. `tests/e2e/docker-metal.sh
  [image]` runs the same render test in the runtime image as its user.
- Target app (total `^MISSING`): 0 -> 0. In `docker run` its renderer
  compiles its `default.metallib` and builds its 5 pipelines.

## Foundation: the rest of what the update framework calls

- The target app survives its first launch on a fresh HOME. Its update
  framework went on from the no-copy NSData call (#188) to
  `-[NSString enumerateLinesUsingBlock:]` and died there. This time every
  selector the framework references was checked against the classes bitten
  registers, and the Foundation ones were filled in together.
- NSString: `enumerateSubstringsInRange:options:usingBlock:` (lines,
  paragraphs, composed characters, words, sentences; reverse;
  substring-not-required), `enumerateLinesUsingBlock:`,
  `stringByAddingPercentEncodingWithAllowedCharacters:`,
  `stringByRemovingPercentEncoding`, and reading and writing through URLs.
- NSCharacterSet: the six `URL…AllowedCharacterSet` sets.
- NSURL: `URLWithString:relativeToURL:` (RFC 3986 resolution, returned as
  an absolute URL), `URLByAppendingPathComponent:isDirectory:`,
  `URLByAppendingPathExtension:`, `URLByDeletingPathExtension`,
  `URLByStandardizingPath`, `URLByResolvingSymlinksInPath`,
  `fileSystemRepresentation`, `getFileSystemRepresentation:maxLength:`,
  `initFileURLWithFileSystemRepresentation:isDirectory:relativeToURL:`, and
  `getResourceValue:forKey:error:` / `resourceValuesForKeys:error:` (names,
  kinds, sizes, dates, access and package flags, from lstat/stat).
- NSFileManager: `enumeratorAtPath:` and
  `enumeratorAtURL:includingPropertiesForKeys:options:errorHandler:`, with a
  lazy NSDirectoryEnumerator (`skipDescendants`, `level`, file attributes).
- NSData: `dataWithContentsOfFile:options:error:`, the `…ContentsOfURL:`
  forms, `writeToURL:atomically:`, `writeToFile:options:error:` and
  `writeToURL:options:error:`.
- Smaller ones: `arrayByAddingObjectsFromArray:`,
  `dictionaryWithObjects:forKeys:`, NSNumber `shortValue` and
  `unsignedShortValue`, NSBundle `preferredLocalizationsFromArray:` and
  `URLForAuxiliaryExecutable:`, NSProcessInfo `isMacCatalystApp` and
  `isiOSAppOnMac`.
- AppKit settings the update alert sets: NSWindow
  `autorecalculatesKeyViewLoop` and `allowsToolTipsWhenApplicationIsInactive`,
  NSWindowController `shouldCascadeWindows`, NSTextView
  `usesAdaptiveColorMappingForDarkAppearance`.
- Test: tests/foundation/sparkle.m.

## AppKit: the session picker popup stays open; full-size content windows

- `NSApp.currentEvent` is the event being dispatched; it was always nil.
  The target app's click-outside monitor reads it when it shows its session
  picker, to skip the mouse-up of the click that opened it. Without it, that
  mouse-up dismissed the popup at once.
- Windows with `NSWindowStyleMaskFullSizeContentView` tell the display
  (style flag 4) to lay the title bar over the content's top instead of
  above it, and flag 8 hides the title text (`titleVisibility`). The display
  had pushed such content 28 points below where AppKit placed it, so clicks
  and screen-coordinate checks were off by the title bar's height. The target
  app's tabs now sit beside the window buttons, as on macOS.
- `NSGraphicsContext` keeps its drawing state (compositing operation as
  the CG blend mode, image interpolation, antialiasing, pattern phase,
  rendering intent). A closed window's display style is sent again when it
  comes back.
- Debugging: `BITTEN_EVENT_DEBUG` logs display mouse events with window and
  screen points, plus the callers that make a window key or change its alpha.
  `BITTEN_DISPLAY_DEBUG` counts each presented frame's non-transparent
  pixels. `BITTEN_NOTIFICATION_DEBUG` logs every posted notification.

- Target app (total `^MISSING`): 0 -> 0.

## Target app: the CLI helper's exit status 1, and a test for reading its output

- On a fresh HOME the target app logs "Rex CLI helper exited unexpectedly
  ... status=1". That is its first `server status --json` probe. The CLI
  answers "rex server is not running" with exit 1, which is correct when no
  server runs yet. The app then runs `server start`, and the server comes up
  through bitten's launchctl (bootout, bootstrap, kickstart, print). This
  happens on the host and in the container, where the socket is
  `~/Library/Application Support/rex/server.sock`. bitten does not cause the
  exit status.
- The app stopped right after this because of unimplemented methods it
  calls on the helper's output and endpoint. The NSData no-copy entry, the
  update-framework selectors entry and the tuple cast entry above added
  them, and that is what moves it past "Creating Session…".
- Test: tests/foundation/helperoutput.m covers that path without the app.
  It splits piped-output bytes into lines with `rangeOfData:options:range:`
  (forward, backwards, anchored, out of range) and with
  `enumerateLinesUsingBlock:` (\n, \r\n, stop, empty). It also resolves
  an endpoint with `URLWithString:relativeToURL:`, including every RFC 3986
  section 5.4 normal example.
- Target app (total `^MISSING`): 0 -> 0. Ran `docker run ... bitten run`
  (browser display) on main: onboarding appears, "Skip for now" opens a zsh
  terminal, and `echo hi` typed in the window prints `hi` in the window.

## Foundation/AppKit: struct values through key-value coding; layer geometry

- `setValue:forKey:` and `valueForKey:` now handle struct and other
  non-object values (CGRect, NSRange, short) through an invocation, boxed
  in `NSValue`. Before, a struct setter received the NSValue pointer as its
  bytes, and AppKit sets backing layers' bounds that way, so every layer had
  garbage bounds. Added `NSGetSizeAndAlignment` and `-[NSValue
  getValue:size:]`; NSValue sizes any struct encoding.
- A view's backing layer follows the view's bounds and frame (its position
  is now set too). The target app reads `layer.frame` to place its tab-bar
  selection surfaces. With garbage frames, a grey bar sat at the window's
  top-left; now the tab group's capsule and the selected tab's pill show as
  on macOS.
- `NSView.alphaValue` fades a view and its subviews when drawn, together
  with its layer's opacity.
- CALayer key paths into its structs, as Core Animation has them:
  `transform.scale` / `.rotation` / `.translation` (with `.x .y .z`), and
  geometry fields such as `position.x` and `bounds.size.width`.
- `-[NSWindow endEditingFor:]` (the activity popup called it on close).
- Debugging: `BITTEN_FRAME_DEBUG=ClassName` logs frame-origin and alpha
  changes of matching views, with callers.
- Target app (total `^MISSING`): 0 -> 0.

## AppKit: x86-64 text alignment values; text fields bezeled, not bordered

- `NSTextAlignment` uses the x86-64 macOS values (Right 1, Center 2). The
  iOS order (Center 1, Right 2) applies only on arm64. Centred labels in the
  target app, such as the activity popup's "No processes are reporting
  activity", were drawn right-aligned.
- A text field made in code is bezeled and not bordered, and setting either
  property clears the other, as in AppKit. The app's filter field turns off
  only the bezel and background, so it kept a border and its text was
  clipped by the border insets.
- `BITTEN_VIEW_TREE` shows text fields' strings, bezel, border, background
  and font.
- Target app (total `^MISSING`): 0 -> 0.

## AppKit: tracking areas deliver mouse entered, exited and moved

- As the mouse moves or drags over a window, tracking areas it enters or
  leaves tell their owners (`mouseEntered:` / `mouseExited:`, `cursorUpdate:`
  on entry), and areas with `NSTrackingMouseMoved` get `mouseMoved:`.
  `NSTrackingInVisibleRect` areas follow the view. Events carry their
  `trackingArea` and `userData`.
- Views get `updateTrackingAreas` when they join a window or change size,
  where most programs set up their areas.
- A plain mouse move goes to the first responder only when the window
  accepts mouse-moved events, as in AppKit. It used to go to the view under
  the mouse, on top of the tracking areas.
- In the target app, hover now works for pane headers, chrome buttons and
  tooltips, and the pane header's split button splits the pane into a
  second shell.
- Target app (total `^MISSING`): 0 -> 0.

## SwiftUI: onHover and onContinuousHover

- Hover regions report the pointer entering, moving in and leaving them.
  Covered: `onHover` (built by Apple's inlined code as
  `_HoverRegionModifier`) and `onContinuousHover` (with points local to the
  region). The hosting view keeps a tracking area over itself and matches
  regions by their place in the tree, which survives rebuilds. Both used to
  be no-ops.
- Debugging: `BITTEN_SWIFTUI_TREE` shows frame modifiers' min/ideal/max.
  The Terminal settings page's "Font style" column is squeezed because the
  other columns use the target app's fixed widths (a 45-point field, a
  19-point icon, a stepper), and the Settings window opens at its 720-point
  minimum.
- Target app (total `^MISSING`): 0 -> 0.

## AppKit: key-window changes, keys to the key window, Escape up the chain

- Key status changes as in AppKit. The window losing it gets
  `resignKeyWindow`, its delegate's `windowDidResignKey:` and
  `NSWindowDidResignKeyNotification`. The new key window gets the matching
  "become" messages. A key window that is ordered out or closed passes key
  status to the frontmost titled window. Before, other windows were just
  marked not key, with no notification, and making the key window key again
  re-posted. The target app's session picker now closes when another of its
  panels (the remote-host prompt) takes key status.
- Key events go to the key window, whichever window the display last
  focused. Typing into the app's popups (the session picker's filter, the
  activity filter) used to go to the main window.
- NSTextView no longer swallows `cancelOperation:`. Escape travels up the
  responder chain (after the delegate's `textView:doCommandBySelector:`),
  so the app's search fields clear on the first Escape and close their
  popup on the second.
- Debugging: `BITTEN_EVENT_DEBUG` logs key commands and the responders that
  handle them.
- Target app (total `^MISSING`): 0 -> 0.

## SwiftUI: switch knobs and checkmarks; centred unavailable-content text

- Toggles draw their marks as macOS does. A switch is a track with a white
  knob at the end it is set to (it had no knob, so on and off differed only
  in colour). A checkbox that is on shows a white check.
- `ContentUnavailableView` centres its title and description lines. A
  wrapped description, such as the target app's "No Remote Hosts" text, had
  its second line at the left.
- Target app (total `^MISSING`): 0 -> 0.

## CoreGraphics: fast paths for 8-bit colour; layer contents and actions in debug output

- The idle target app spent about 77% of a core on its main thread. Each
  terminal present (the cursor blink, about 1.7 a second) redraws the whole
  window in software, and every pixel went through double-precision
  `cg_read_pixel` / `cg_blend_pixel` / `cg_write_pixel`. Three exact fast
  paths for 4-byte colour surfaces bring that to about 64%:
  - source-over blends straight on the bytes;
  - opaque solid fills store fully covered pixels directly;
  - images made from 8-bit colour data reorder bytes (premultiplying straight
    alpha with the same rounding, ⌊(2ca + 255) / 510⌋) without floats.
- Still to do: redraw only what changed (the terminal view's rect on a
  present), and bound the rasterizer's scan by the clip. Most of the
  remaining time is translucent fills, clip intersection and transparency
  layers over the whole window.
- Debugging:
  - `BITTEN_VIEW_TREE` shows layer contents sizes and gravity.
  - `BITTEN_EVENT_DEBUG` logs `sendAction:to:from:` targets.
  - `BITTEN_VIEW_TREE` showed that an inactive terminal pane's dimmed
    background stops above the bottom padding. That is inside the
    renderer's frame (the contents image is full size), and was handed to
    the Metal/terminal owner.
- Target app (total `^MISSING`): 0 -> 0.

## Partial window redraws; CoreGraphics clip boxes; stable sorting

- A view whose layer shows a presented image (the terminal's Metal frames)
  compares each new image with the last. Only the pixels that changed are
  invalidated (none for an identical frame), and the window repaints just
  that rect over its previous frame. Every other invalidation still
  repaints everything. A cursor blink now repaints an 11×18 rect instead
  of the window. The idle target app went from about 64% of a core to 23%.
- CoreGraphics clip masks carry the box where they can be non-zero. Fills,
  images and gradients scan only rows and columns inside it, clip paths are
  rasterized within the current clip, intersections visit only the new
  mask's box, and transparency layers composite only the clip's box.
  Results are unchanged; work outside the clip is skipped.
- Foundation:
  - Array sorts are stable, as Apple's are; they used plain `qsort`.
  - Added `sortedArrayWithOptions:usingComparator:` and
    `sortWithOptions:usingComparator:`, with `NSSortOptions`.
  - Added NSDictionary's `keysSortedByValueUsingSelector:`,
    `keysSortedByValueUsingComparator:` and
    `keysSortedByValueWithOptions:usingComparator:`.
- Debugging:
  - `BITTEN_DRAW_PROFILE` prints the time each view class takes to paint.
  - `BITTEN_DISPLAY_DEBUG` logs partial frames.
  - `BITTEN_VIEW_TREE=2` adds layer background, corner, border, shadow and
    filters.
- What remains in the idle app is sending the whole frame to the display,
  and the terminal renderer redrawing its whole drawable.
- Target app (total `^MISSING`): 0 -> 0.

## AppKit: pop-up and context menus on screen

- Menus show in a window of their own at the pop-up menu level. Before,
  they had no window: a pop-up only told the delegate it opened and closed.
  - Each row shows its title, image, checkmark or mixed state, and key
    equivalent (⌃⌥⇧⌘ glyphs), or a submenu arrow. Separators are drawn and
    disabled items are greyed.
  - The row under the pointer highlights through a tracking area. Hovering
    a submenu row opens the submenu beside it.
  - The arrow keys move through enabled rows, Return or a click picks an
    item and sends its action, and Escape or a click outside closes the
    menu.
  - Items are enabled as AppKit's automatic validation decides: a target
    for the action, and `validateMenuItem:`.
- `popUpMenuPositioningItem:atLocation:inView:` and `popUpContextMenu:`
  show the menu and return at once (AppKit tracks it in a nested loop
  there). The chosen action and `menuDidClose:` come when the menu is used.
- NSView's `rightMouseDown:` shows `menuForEvent:` as AppKit does. The
  target app's terminal context menu (Copy, Paste, Split, Float, Zoom,
  Close Pane, Reset Terminal) opens and its items work.
- `NSMenuItem.menu` and `NSMenu.supermenu` are kept; they were always nil.
  Separators are the items made by `+separatorItem`; any untitled item
  without an action used to count as one.
- SDK: function-key characters (`NSUpArrowFunctionKey`…) and
  `menuForEvent:`.
- Target app (total `^MISSING`): 0 -> 0.

## Display: partial frames; Metal pass traces; the dimmed-pane strip explained

- `bitten_display_present_rect` presents only a changed rect of a window's
  bitmap. Only that part is converted, and viewers that missed only partial
  updates get a new message 3 (a frame's header, the rect, its pixels).
  - Each window keeps up to 16 changed rects since its last full frame, so
    a viewer gets their union.
  - A first frame, a new size, style changes and order-front still send
    the whole frame, as does a viewer that is further behind.
  - The page draws message 3 over the canvas.
- AppKit presents partial frames this way. The idle target app (cursor
  blink) went from about 23% of a core to 8%.
- `BITTEN_METAL_DEBUG` traces render passes (target, load action, clear
  colour), viewports, scissors and draws.
- The strip at the bottom of a dimmed terminal pane is the target app's
  doing.
  - Each pass clears to white, and `cell_bg_fragment` extends cell
    backgrounds into the padding only on the sides the app's uniforms ask
    for. Its padding-extend byte (0x30 or 0x31) never sets "down".
  - The bottom padding keeps the clear colour, as it would on macOS.
- Target app (total `^MISSING`): 0 -> 0.

## SwiftUI: menu items' action selector; fatal errors can trap

- SwiftUI's main-menu items targeted `#selector(_MenuActionTarget.perform(_:))`.
  NSObject's `-performSelector:` also imports to Swift as `perform(_:)`, and
  the selector was that one, so performing an item sent the menu item as
  a selector. The method is now `performMenuAction:`.
  - The target app performs its Settings item itself (`item.menu`,
    `update`, `performActionForItem(at:)`). Since `NSMenuItem.menu` stopped
    being nil (#201), ⌘, crashed with an unrecognized garbage selector.
    Settings opens again.
- `dx_fatal` traps when `BITTEN_CRASH_REPORT` is set, so a fatal error (an
  unrecognized selector) gets a crash report with a backtrace.
- Debugging:
  - `BITTEN_WINDOW_DEBUG` logs window creation and frame changes with
    callers.
  - `BITTEN_EVENT_DEBUG` logs menu items performed by index.
- Target app (total `^MISSING`): 0 -> 0.

## AppKit: view controllers hear their views appear and disappear

- `viewWillAppear`/`viewDidAppear` and `viewWillDisappear`/`viewDidDisappear`
  are called. A controller's view knows its controller. The callbacks fire
  when the view joins or leaves a visible window, and when that window is
  ordered in, out or closed, parents first and once each way. They were
  never called before.
- The target app's Settings window installs its initial page on
  appearance, so it used to open with an empty detail pane. It now opens on
  the Server page.
  - Settings still opens at its 720-point minimum, as it would on a Mac:
    the window is sized from its content before the page is added. The
    Terminal page's squeezed "Font style" column follows from that and the
    app's fixed field widths.
- Target app (total `^MISSING`): 0 -> 0.

## AppKit/SwiftUI: dark mode follows the appearance

- System colours that change with the appearance are dynamic:
  `labelColor`, `secondaryLabelColor`, `textColor`, `textBackgroundColor`,
  `windowBackgroundColor`, `controlBackgroundColor` and `separatorColor`.
  They were fixed light values, so window backgrounds and AppKit text
  stayed light.
- Each view draws with its effective appearance current, and the window
  background is filled in the window's. Dynamic colours used to resolve
  for the application's appearance everywhere.
- Setting the appearance of the application, a window or a view tells the
  affected views (`viewDidChangeEffectiveAppearance`), marks them for
  display and redraws. The application's appearance has a real setter.
- Views that want `updateLayer` get it, in their appearance, before their
  layer is painted. Appearance-dependent layer colours set there now
  refresh.
- SwiftUI hosting views take their `colorScheme` from their effective
  appearance and rebuild when it changes. It was always light, so
  `.primary` text stayed dark on dark backgrounds.
- Template images in image views and buttons draw in the tint colour, or
  the label colour of the appearance. They drew as they were (black).
- A window asked to display while it is drawing (a view setting the
  window's appearance as it draws) displays after the frame. It used to
  draw re-entrantly and free the context in use.
- The drawing appearance is retained per thread.
- In the target app, switching Settings → Interface between Light and Dark
  now changes the whole app live: windows, Settings, the toolbar icons.
- Target app (total `^MISSING`): 0 -> 0.

## SwiftUI: menu pickers pop up their options

- A `Picker` in the menu style shows its options as a pop-up menu (the
  AppKit menus of #201). The titles are the options' text, the current one
  is checked and placed over the picker, and choosing one sets the
  selection. Clicking used to cycle to the next option.
  - In the target app, Settings → Interface → Toolbar behavior offers
    Always show, Show on hover and Hidden. Choosing Hidden hides the tab
    bar.
- `NSMenu.popUpMenuPositioningItem:atLocation:inView:` has its Swift name,
  `popUp(positioning:at:in:)`.
- The light bezel on bordered buttons in dark mode was a colour-scheme
  problem, fixed by #205.
- Target app (total `^MISSING`): 0 -> 0.

## Display: a page that connects stacks windows as the program left them

- The page stacks windows in the order their first frames arrive, and the
  server sent them newest window first. A page that connected or
  reconnected put the newest window (Settings) behind older ones (the main
  window). Its clicks then went to the window underneath.
- A client's first sync now sends windows back to front, by their
  order-front count.
- Target app (total `^MISSING`): 0 -> 0.

## AppKit/SwiftUI: key equivalents reach views first; focus reaches platform views

- A command key goes to the key window's views (`performKeyEquivalent:`,
  offered to each visible subview) before the main menu, as in AppKit. A
  shortcut recorder or a button's key equivalent takes it first. NSView
  and NSWindow implement `performKeyEquivalent:`.
- A SwiftUI `.focused(...)` binding that is set makes the focused
  representable's AppKit view the window's first responder, or the first
  view inside it that accepts it.
- In the target app, Settings → Shortcuts records a shortcut once its
  field is clicked; ⌘N was recorded back for New Window.
- Debugging:
  - `BITTEN_EVENT_DEBUG` logs first-responder changes with callers.
  - `BITTEN_METHODS=ClassName` lists a matching view class's own methods
    when it joins a window.
- Target app (total `^MISSING`): 0 -> 0.

## Debugging: a view class's methods and stored properties

- `BITTEN_METHODS=ClassName` now prints the implementation address of each
  of the matching class's own methods. It also prints its ivars (Swift
  stored properties, with their runtime offsets and first byte) when the
  view joins a window and again a main-queue turn later.
- With it, and gdb breakpoints on the target app's code, the shortcut
  recorder in Settings → Shortcuts was checked. It begins recording on one
  click (it makes itself first responder from `viewDidMoveToWindow`, a turn
  later) and records ⌘N, now that command keys reach views first (#208).
  The Swift field offsets it reads were slid correctly by the runtime.
- Target app (total `^MISSING`): 0 -> 0.

## Window management: resize grip, zoom, minimise to a dock

- The display page gives resizable windows a grip at the bottom right.
  Dragging it sends `resize` (throttled to one per animation frame), and
  AppKit keeps the window's top left corner where it was. The yellow and
  green title-bar dots now send `miniaturize` and `zoom` (events 11 and
  12), and are grey when the window can't do either.
- `_bn_sendStyle` adds style flags 16 (resizable), 32 (miniaturizable),
  64 (zoomable) and 128 (miniaturized), taken from the style mask.
- `-[NSWindow miniaturize:]` hides the window but leaves it with the
  display, which shows it as a chip in a dock along the bottom of the page.
  Clicking the chip sends `deminiaturize` (event 13). Both directions pass
  key status on and post the will/did (de)miniaturize notifications, and
  `NSWindowWillMiniaturizeNotification` is now defined.
- Checked in the target app: the main window resizes from the grip, zooms,
  and minimises to a chip and comes back. Full redraws during a resize are
  slow, about 0.3–1 s each, and most of that time is CG compositing
  (`cg_blend_pixel`, `cg_read_pixel` in transparency layers).
- Target app (total `^MISSING`): 0 -> 0.

## CoreGraphics: CGRect members of a rectangle with negative extents

- The Swift CoreGraphics fixture checks `minX`, `midX`, `maxX`, `minY`,
  `midY` and `maxY` on a rectangle whose width and height are negative.
  They come from the standardized rectangle, as on macOS. Test only; the
  getters are the `swift_name` ones from #169. Salvaged from #164.

## Images drawn by a handler composite in their own buffer

- `-[NSImage drawInRect:]` now runs an image's drawing handler inside a
  transparency layer clipped to the image. Before, the handler drew
  straight into the destination. Apps tint a symbol by drawing it and then
  filling the image's rect source-atop, so that fill landed on whatever was
  behind the image. In the target app's command palette (⇧⌘P), each
  chevron and the search magnifier sat in a dark box, and the selected
  row's chevron was a solid white square. They now draw as plain glyphs.
  tests/appkit/compositing.m covers this.
- `BITTEN_SYMBOL_DEBUG=1` prints each system symbol name once as it is
  drawn (noting names drawn as a stand-in), and any SwiftUI named image
  that falls back to the placeholder.

- Target app (total `^MISSING`): 0 -> 0.

## The first responder leaving its window hands over to the window

- When a view that is its window's first responder leaves the window
  (removed, or inside a removed parent), the window becomes first
  responder, as on macOS. The view is asked to resign first and goes
  either way (`-[NSWindow _bn_dropFirstResponder]`).
- In the target app, switching back to an earlier tab with ⌃⇧Tab (or
  closing the current tab) used to show "Terminal Failed: The presented
  window does not contain block …". The removed tab's terminal stayed
  first responder, and the app looked its block up in the newly presented
  tab. Clicking a tab worked, because the click moved first responder
  first. Both keyboard paths now show the tab's panes.
  tests/appkit/basics.m covers this.
- Target app (total `^MISSING`): 0 -> 0.

## Split symbols: columns by rows

- `rectangle.split.CxR` symbols are drawn as C columns by R rows.
  `split.2x1` is side by side and `split.1x2` one above the other. Before,
  every split had a single vertical divider, so the target app's pane
  menu showed Split Down/Up with the same icon as Split Right/Left.
  tests/appkit/symbols.m covers both.
- Target app (total `^MISSING`): 0 -> 0.

## Observation: nested tracking reports to the tracking around it

- `withObservationTracking` merges what a nested tracking read into the
  enclosing tracking, as Swift's Observation does. A change to a property
  read only inside the inner closure now fires both onChange handlers.
  Before, only the inner one fired. tests/swiftlib/handoff.swift covers
  it. In the target app idle CPU is unchanged (16–17% with a viewer
  connected).
- Checked along the way: the target app's Zoom Pane / Restore Pane work.
  They just take several seconds while full redraws are slow.
- Target app (total `^MISSING`): 0 -> 0.

## Plain buttons offer their label the height they are offered

- A button that isn't bordered now proposes its label the height it is
  offered, as it already did for width. A label that takes all the room
  (`.frame(maxWidth: .infinity, maxHeight: .infinity)`) fills its share of
  a stack in both directions. Bordered buttons keep their bezel height.
- In the target app's Settings → Notifications, the Notification position
  picker (a 3×2 grid of capsule buttons in a 112×64 frame) had both rows
  squeezed together in the middle. The top row now sits at the top and
  the bottom row at the bottom. tests/swiftlib/swiftui.swift (`flexrows`)
  covers this.
- Target app (total `^MISSING`): 0 -> 0.

## SwiftUI: timelines stop when paused or gone

- A `TimelineView` with `.animation(paused: true)` runs no timer. A
  timeline that leaves the tree stops its timer; it used to keep firing,
  every 1/30 s for the life of the process.
- Each tick rebuilt the tree of every hosting view and redrew every
  window in software. In the target app, a timeline from its loading
  screen kept the main window redrawing 3–4 times a second after the
  screen was gone: 90–100% CPU while idle. Clicks that straddled one of
  those rebuilds were lost.
- Test: `tests/swiftlib/swiftui.swift` (timelines): a running timeline
  rebuilds, a paused one does not, and one removed from the tree stops.
- Target app (total `^MISSING`): 0 -> 0.

## SwiftUI: a write while the tree is rebuilt does not rebuild it again

- Observation registered by a tree that has since been rebuilt fires when
  a property it read changes, even after the tree is gone. A view that
  stores into a model while it is created (an initialiser storing what it
  was given) did that on every rebuild, so every rebuild asked for
  another, without end.
- A hosting view now counts its builds. A change seen by an earlier
  build's observation is ignored. Writes from outside the build, or to
  properties the current build has read, still rebuild.
- In the target app, the main window's content stored its presentation
  into its model on every rebuild, which kept the window rebuilding and
  redrawing at the rate it could draw.
- Debugging: `BITTEN_OBSERVATION_DEBUG` logs each write that fires a
  tracked change, with its key path.
- Test: `tests/swiftlib/swiftui.swift` (rebuildwrites).
- Target app (total `^MISSING`): 0 -> 0.

## SwiftUI: a click survives a rebuild between press and release

- The tree is rebuilt whenever state changes, and a release used to tap a
  control only if it found the same node the press found. A rebuild in
  between (state changing while the button was held, or a timer) lost the
  click. A release now taps the node at the same place in the new tree.
- In the target app, onboarding's "Skip for now" did nothing while the
  window kept rebuilding.
- Test: `tests/swiftlib/swiftui.swift` (pressrebuild).
- Target app (total `^MISSING`): 0 -> 0.

## Display: frames convert with integers

- Windows hand the display premultiplied 8-bit BGRA, and the page wants
  straight RGBA. Each pixel went through CoreGraphics' general reader as
  doubles. 8-bit colour with alpha now converts with integer arithmetic,
  with the same result: rounded colour / alpha.
- A 1087x700 frame: 65 ms -> 6.3 ms (`tests/c/display.c` reports it). In
  the target app this was about a quarter of the CPU spent redrawing a
  window.
- Test: `tests/c/display.c` checks the conversion over 16 alphas
  against the old formula.

## Clicks in text views, the standard Edit menu, validated key equivalents

- NSTextView now maps points to text:
  - `characterIndexForInsertionAtPoint:` is new.
  - `characterIndexForPoint:` was a stub; it now converts from the screen.
  - A click places the insertion point, shift-click extends the
    selection, a double click selects the word, and dragging selects.
  - In the target app, clicking Settings → Search Settings used to crash:
    its text view subclass calls `characterIndexForInsertionAtPoint:`
    from `mouseDown:`.
- SwiftUI's default Edit menu has the standard items, sent to the first
  responder: Undo/Redo, Cut/Copy/Paste, Paste and Match Style, Delete and
  Select All. ⌘A selects all in the settings search field, and ⌘C/⌘V
  copy from it and paste into a terminal pane.
- Menus validate an item before its key equivalent fires, as AppKit's
  auto-enabling does. The item must have a target (its own, or along the
  responder chain) that takes its action, and that target's
  `validateMenuItem:` / `validateUserInterfaceItem:` must agree. A
  shortcut nothing can perform passes on to the window instead of being
  swallowed.
- Tests: tests/appkit/text.m (points, clicks, word selection),
  tests/appkit/basics.m (validation).

- Target app (total `^MISSING`): 0 -> 0.

## Metal: no reference counting per pixel

- The rasteriser read the pipeline into a strong local for every
  fragment, so each pixel cost a retain and a release, both through the
  locked side table. It is unretained now (the encoder holds the
  pipeline).
- A 1024x640 blended pass: 206 ms -> 118 ms (`tests/metal/render.m`
  reports it). In the target app, the terminal's idle redraws (a cursor
  blink) cost 72% CPU before this and the SwiftUI fixes, and 23% after.
- Target app (total `^MISSING`): 0 -> 0.

## Foundation: bookmarks; NSString getFileSystemRepresentation:maxLength:

- `-[NSURL bookmarkDataWithOptions:includingResourceValuesForKeys:relativeToURL:error:]`,
  `+URLByResolvingBookmarkData:options:relativeToURL:bookmarkDataIsStale:error:`
  and its initialiser: a bookmark holds the file's URL, and resolves while
  the file exists. Security-scoped access always succeeds.
- `-[NSString getFileSystemRepresentation:maxLength:]`.
- The target app's update framework calls both after it downloads an
  update. Its first launch with an empty home died there, about 35 s in.
- Test: `tests/foundation/sparkle.m`.
- Target app (total `^MISSING`): 0 -> 0.

## Intel macOS jq: file queries and extended libm

- The upstream jq 1.8.1 Mach-O reported its version but aborted before
  evaluating even a basic expression, at the unimplemented `pathconf`.
  `pathconf` and `fpathconf` translate Darwin POSIX selector values,
  preserve guest errno for indeterminate results, and report unsupported
  Darwin-only selectors with EINVAL.
- `fdopen$DARWIN_EXTSN` shares the stdio implementation, with translated
  errno on failure. Additional x86-64 libm exports include the gamma,
  Bessel, error, inverse hyperbolic, and floating-point helper functions
  imported by jq.
- Tests: `tests/c/files.c`, `tests/c/libm_ext.c`, and opt-in
  `tests/e2e/jq-macho.sh` with the unmodified upstream executable.
  jq imports: 22 missing -> 0. JSON stdin, file input, regular expression
  captures, and extended math run without stubs. From #167.
- Target app: not rechecked; the change only adds exports.

## Thread-local destruction for Intel macOS ripgrep

- The upstream ripgrep 16.0.0 Intel Mac executable searched successfully
  with one worker but aborted on `_tlv_atexit` when given four workers.
  Register Mach-O thread-local callbacks with glibc so they run in
  reverse order while Bitten's TLV storage is still live.
- The Mach-O lifecycle test checks both worker return and process exit.
  The upstream ripgrep fixture checks recursion, ignore rules and no-match
  status; both one and four workers pass. Unused unwind imports remain
  unsupported. From #168.
- Target app: not rechecked; the change only adds an export.

## Build: a failed libSystem stub generation fails the build

- `tools/gen-tbd.sh` read `mrun --list-exports` through a pipeline, so a
  failing mrun still produced a stub with no exports and exit status 0.
  It now captures the list first and fails with it. The Makefile writes
  the stub to a temporary file and moves it into place only on success,
  so a failure leaves nothing a later `make` would take as current.
- Test: `tests/gen-tbd.sh`, run by `make check`, uses an mrun that fails.
  From #55.
- Target app (total `^MISSING`): unaffected; build tooling only.

## Keyboard shortcuts on buttons, and unhandled keys reaching the window

- SwiftUI performs a button's `keyboardShortcut`. The hosting view's
  `performKeyEquivalent(with:)` finds the enabled button whose shortcut
  matches the key: ⌘ shortcuts, Return for `.defaultAction` (Enter too),
  and Escape for `.cancelAction`. Before, shortcuts were only used for
  menu items.
- A key nothing along the responder chain takes ends at the window, which
  offers it as a key equivalent (`-[NSWindow keyDown:]`). So does an
  Escape or Return that a text view turns into `cancelOperation:` /
  `insertNewline:` when nothing takes the command. The SwiftUI host now
  passes keys its tree doesn't handle up the responder chain instead of
  dropping them. NSView's `performKeyEquivalent:` is declared, with
  Swift name `performKeyEquivalent(with:)`.
- In the target app, Escape now cancels Settings → Remote Hosts → Add
  Remote Host. Escape still closes the command palette, and typing still
  goes to the terminal.
- Tests: tests/appkit/basics.m (Escape to a Cancel button),
  tests/swiftlib/swiftui.swift (`shortcuts`).
- Target app (total `^MISSING`): 0 -> 0.


## Switches and checkboxes take clicks again

- A regression from #198: a toggle's switch or check box is drawn by a
  leaf node (`_ToggleMarkNode`), which didn't count as content where a
  click lands. The toggle's control node therefore took no clicks, and
  every switch and checkbox stopped responding.
- The mark now counts as content over its frame. In the target app,
  Settings → Developer → Developer Mode switches on (its developer
  settings appear) and back off. tests/swiftlib/swiftui.swift
  (`toggleclick`) clicks a switch and a checkbox.
- Target app (total `^MISSING`): 0 -> 0.

## Closed windows are freed: view ownership, observation, monitors

Each time the target app opened Settings it kept about 12 MB that never
came back (Settings opened and closed 20 times: 137 → 376 MB). There were
several causes:

- **Retain cycles in the view tree.** NSView's `_superview` and `_window`
  were strong under ARC, so every view tree was a retain cycle (subview ↔
  superview, content view ↔ window) and nothing in a dropped hierarchy was
  freed. They are now `__unsafe_unretained`, as AppKit doesn't own them
  either. A view's `-dealloc` clears its subviews' superview. A window's
  `-dealloc` drops its first responder and tells its views they left it
  (`viewWillMoveToWindow: nil`, `viewDidMoveToWindow`). The window is
  forgotten first, so nothing can reach it while it goes.
- **Backing bitmaps.** A window's backing bitmap was kept in an `NSValue`
  holding a raw pointer and was never released. A holder object now
  releases it with the window, or when a resize replaces it.
- **SwiftUI window list.** SwiftUI's window list kept every window it had
  shown. A window is now dropped from it when it closes.
- **Observation that never fired.** `withObservationTracking` registrations
  on properties that never change waited forever, and their onChange
  closures kept whole SwiftUI trees alive. Our Observation now gives
  SwiftUI a token (`_bitten_withObservationTracking`,
  `_bitten_cancelObservationTracking`). A host cancels its tree's
  observation when it rebuilds and when it goes, and the closures hold the
  render context weakly.
- **Dead NotificationCenter registrations.** Selector registrations whose
  observer has gone, and registrations for a sender that has gone, are
  pruned, as on macOS where observers needn't remove themselves.
- **Event monitors.** The app's shortcut recorder fields remove their event
  monitors when they leave their window. They now get told they left it,
  so the 200 monitors each visit to Settings → Shortcuts added are
  removed. Before, every event ran through all of them.
- **Keys after a window closes.** Keys the display sends to a window that
  has closed (the one the page last had focused) now go to the key window
  instead of being dropped. Before, after closing Settings from its
  Shortcuts page, ⌘, did nothing.

Result: opening and closing Settings 16 times went from +240 MB to about
+65 MB, mostly heap that isn't returned to the OS. Live objects stay flat;
the remainder is the app's own observation loops.

Tests: tests/appkit/basics.m. A released window is freed with its views,
which are told they left it, and a view kept after its superview goes has
no superview.

Debugging aids:
- `BITTEN_ALLOC_STATS=N` prints, every N seconds, the classes with the most
  live instances (Objective-C objects and Swift class instances) and how
  many were made since the last report.
- `BITTEN_MONITOR_DEBUG` logs event monitors added (with callers) and
  removed.
- `BITTEN_WINDOW_DEBUG` also logs windows being freed.

- Target app (total `^MISSING`): 0 -> 0.

## NEXT.md brought up to date

- docs/NEXT.md described an early state: showing Metal frames, getting
  through onboarding, the CLI helper's first-launch exit. It now
  describes where things stand. The app runs end to end, and what's left
  is speed (CG compositing and terminal Metal at idle), bracketed paste,
  Return in text fields, and the display page's focus after a window
  closes. It also lists the debugging switches that find problems.
## The display page refocuses when the focused window closes

- Display (page.html): when the focused window closes, the frontmost
  window still showing (not miniaturized, not a borderless panel) takes
  focus, or none; keys no longer go to a window that is gone.
- Target app (total `^MISSING`): 0 -> 0.

## Icon tints composite only over the icon

- A profile of a window resize showed drawing a template image costing
  about 4% of the main thread. A transparency layer covers the whole
  context, so every tinted icon composited the whole window back.
- Three places now clip to what they cover before opening the layer:
  AppKit's template tint (`_bn_drawTemplateInRect:color:`), SwiftUI's
  template images, and filled symbols' knockouts. They pass the rect
  (`CGContextBeginTransparencyLayerWithRect`), so a layer bounded by it
  can be smaller.
- In the target app, idle CPU with a viewer connected went from 16–17%
  to about 12%. Icons look the same (command palette, pane menu).
- Target app (total `^MISSING`): 0 -> 0.

## A window's background replaces what it repaints

- Each repaint filled the window's background colour over the backing with
  normal blending. For a transparent window (the target app's main window
  has a clear background), that was a full blending pass over every
  repainted pixel that changed nothing, and it never cleared what the
  last frame left there.
- Where the background isn't opaque, the repainted area of the bitmap is
  now cleared directly (`memset` of the rows), and the colour is filled
  only if it shows at all. Opaque backgrounds fill as before.
- Target app (total `^MISSING`): 0 -> 0.

## Transparency layers hold only what can be painted

- CoreGraphics (context.c, raster.c, cg.h): a transparency layer allocates
  only the target's pixels within the clip's box and, for
  CGContextBeginTransparencyLayerWithRect, the rectangle's device bounds
  (drawing outside the rectangle is discarded, as documented). It used to
  allocate and clear the whole target (3 MB for a 1087x700 window) on
  every call. The layer's surface is "bounded": its data is offset so
  pixels keep their full-surface coordinates, and pixel writes and span
  fills outside the box are dropped, even if drawing inside the layer pops
  its clip. Ending a layer composites only its box within the clip.
- Test: tests/c/cg.c (a rectangle under a translated CTM, a clip, a
  layer whose state is popped).
- Target app (total `^MISSING`): 0 -> 0.
