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
- The Go runtime inside the unmodified `rex` helper now starts: scheduler,
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

## 2026-11-24: raw Darwin syscalls, malloc zones, peer credentials (PR: rex-helper)

Driven by running the real target: the `rex` helper bundled in Rex.dmg (an
unmodified universal Mach-O Go binary with cgo and an embedded SQLite).

- `rex version` works. `rex server run` reaches "Rex server ready"; the CLI
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
- With these, every one of the 291 imports of the Rex helper is implemented,
  and the end-to-end flow works: `rex server start`, `rex new`, a shell in a
  Rex terminal, `rex send`, `rex capture` printing the shell's output.
- Tests `cf` and `libproc`. Suite: 11/11 in a clean Debian container
  (`docker build --target test .`), which also caught two portability bugs
  (a missing `<linux/sockios.h>` and the versioned path of `ld64.lld`).
- This batch was written by a delegated Codex agent to a written spec and
  reviewed, built and run against the real target before merging.

## 2026-11-24: container, Rex example, documentation (PR: docker)

- `Dockerfile`: multi-stage. Build stage compiles `mrun`; an optional `test`
  stage runs the whole suite; the runtime image is Debian slim with `mrun`,
  `dmgx`, the entrypoint, zsh, the directories macOS programs expect and a
  macOS-style `/usr/bin/login`. Runs as an unprivileged user with Docker's
  default seccomp profile.
- `docker/bitten` entrypoint: finds the mounted `.dmg`, unpacks it, picks the
  app, and offers `info`, `run`, `exec`, `shell`, `check`. Generic: nothing
  in it knows about Rex.
- `compose.yaml` (any image) and `examples/rex/compose.yaml`.
- `examples/rex/terminal.py`: a browser and `--tty` view of a Rex terminal,
  driven only through the real CLI (`rex capture`, `rex send`). Found on the
  way: Rex starts shells with `login -fpl user ...` (macOS option letters),
  hence the login shim.
- Verified from a clean state with the real disk image:
  `docker run ... bitten info` (2 s including unpacking), `exec rex version`,
  and `docker compose -f examples/rex/compose.yaml up` serving a zsh login
  shell inside a Rex terminal on `http://localhost:7680`.
- Docs: README rewritten with a support matrix; `ARCHITECTURE.md`,
  `REX.md` (import coverage: helper 291/291, GUI 311/5,688) and
  `DECISIONS.md`.
- CI: a GitHub Actions workflow is written but not active. It sits in
  `ci/github-actions.yml` because the token used here lacks the `workflow`
  scope; copying it to `.github/workflows/ci.yml` enables it. Until then the
  suite is run locally with `docker build --target test .` before each merge.

Where it stops: the Rex window itself (`Contents/MacOS/Rex`) cannot start.
It needs an Objective-C runtime, a Swift runtime and standard library,
Foundation, AppKit, SwiftUI and Metal. `REX.md` sizes each.

## 2026-11-24: provenance note (PR: provenance-note)

The delegated agent's final report for the frameworks batch arrived after the
merge and matched the merged files (209 exports: CoreFoundation 149,
Security 33, resolver 10, libproc 9, Objective-C 8). It disclosed reading
Apple's open-source libproc wrapper for return-value conventions, so the
README's licensing section now lists the open-source references that were
consulted instead of claiming documentation alone.

## 2026-11-24: Objective-C runtime and Blocks (PR: objc-runtime)

Direction from the owner: keep building every missing library in-house, with
Rex as the yardstick, for developers who want Mac containers in Docker.
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
- Rex window imports still unimplemented: 5,377 -> 5,352.

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
  Suite: 14/14. Rex window imports unimplemented: 5,352 -> 5,340.
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
  Suite: 20/20. Rex window imports unimplemented: 5,327.

Limits: `dispatch_io_*` is absent; QoS is recorded but does not change
scheduling; timer leeway is ignored; a signal source observes a signal only
until the program installs its own handler for it afterwards.

## 2026-11-24: path redirection regression (PR: fix-path-redirect)

Giving `mrun` a default framework root (for Foundation) switched on the
path redirection that had only ever run with `BITTEN_ROOT` set. It
redirected any not-yet-existing path under `/Users`, `/Library`, `/private`
and others into the framework root, so the Rex server could not create its
socket in the container. The unit suite did not see it; the container smoke
test did, after the merge.

- Redirection now applies only to `/System/Library/` and `/usr/lib/swift/`,
  and only when the file exists in the framework root.
- `tests/c/paths.c` pins both halves: framework files resolve, new files and
  sockets are created where asked.
- `tests/e2e/rex.sh` automates the container check with a real Rex.dmg
  (`info`, `rex version`, a command typed into a Rex terminal). It is run
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
  Suite: 23/23; container end-to-end check passes. Rex window imports
  unimplemented: 5,327 -> 5,307.

Bug found by the test: URL components were held in a struct of unretained
pointers. With the autoreleased-return handshake working as on macOS, the
substrings were released immediately instead of lingering in a pool, and the
getters returned garbage. They are held strongly now.

Approximations to know about: character-set membership outside Latin-1 is
by block, not by the Unicode character database; case mapping covers ASCII
and Latin-1; `NSDate` descriptions are always UTC.

## 2026-11-24: pause point (PR: resume-notes)

Ran the Rex window binary under `mrun` after PR #13. It now loads, registers
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
- Measured here: the Rex window has 5,360 unimplemented imports with this
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
  toolchain on this machine); `tests/e2e/rex.sh` not run (no Docker here).
- Rex window imports unimplemented: 5,484 -> 5,434 (5,484 is what
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
- Rex window imports unimplemented: 5,434 -> 5,423.

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
- Rex window imports unimplemented: 5,423 -> 5,418.

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
  `swift-demangle` exactly on all 1,099 type symbols of the Rex window and
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
  Docker here: `tests/e2e/rex.sh` not run.
- Rex window imports unimplemented: 5,418 -> 5,406.

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
  `tests/e2e/rex.sh` not run.
- Rex window imports unimplemented: 5,453 -> 5,382. `mrun` on it now gets
  through `swift_getSingletonMetadata` for `RexMacOSApp` and stops at
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
  `-O` and `-Onone`. No Docker here: `tests/e2e/rex.sh` not run.
- Rex window imports unimplemented: 5,382 -> 5,378. `mrun` still stops at
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
  `tests/e2e/rex.sh` not run.
- Rex window imports unimplemented: 5,378 -> 5,366.

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
- Suite 29/29 at `-O` and `-Onone`. Rex window imports unimplemented:
  5,366 (unchanged; tests and printing only). Rex still stops at
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
  `tests/e2e/rex.sh` not run.
- Rex window imports unimplemented (total `^MISSING` lines, with
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
- Rex window (total `^MISSING`): 5,366 -> 5,304.

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
- Rex window (total `^MISSING`): 5239.

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
  here: `tests/e2e/rex.sh` not run.
- Rex window imports unimplemented: 5,239 -> 5,236. `mrun` still stops at
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
  both. No Docker here: `tests/e2e/rex.sh` not run.
- Rex window (total `^MISSING`): 5,236 -> 5,217.


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
  Docker here: `tests/e2e/rex.sh` not run.
- Rex window (total `^MISSING`): 5,217 -> 5,181.

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
- Rex window (total `^MISSING`): 5,181 -> 4,983.

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
  -Onone. No Docker here: `tests/e2e/rex.sh` not run.
- Rex window (total `^MISSING`): 4,983 -> 4,972.

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
  x86-64 macOS and Rex does not use it.
- `CGFloat` is not a libswiftCore symbol: Rex imports it (4 symbols, mangled
  in module `CoreGraphics`) from `libswiftCoreFoundation.dylib`.
- `tests/swiftlib/floats`: IEEE corner cases, rounding, bit-level
  properties, conversions (exactness, ranges, NaN), Float80, at -O and
  -Onone; values checked from C in xmm registers. No Docker here:
  `tests/e2e/rex.sh` not run.
- Rex window (total `^MISSING`): 4,972 -> 4,964 (`Double`/`Float` metadata
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
- Rex window (total `^MISSING`): 4,964 -> 4,913.

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
- Rex window: 8 of its 9 imports from libswiftCoreFoundation now resolve
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
  Verified both ways: Rex's code builds literals with exactly these
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
  now), and the internal entry points Rex imports (`_StringGuts.grow`,
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
  Suite 41/41 at -O and -Onone. No Docker here: `tests/e2e/rex.sh` not run.
- Rex window (total `^MISSING`): 4,905 -> 4,866.

## 2026-11-25: standard library: Array, ContiguousArray, ArraySlice (PR: stdlib-array)

- Apple's representation on Darwin, checked against the code swiftc inlines
  into our tests and against Rex's own inlined array code: `Array` is one
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
  `...yXl_Ts5`) Rex binds to.
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
  arguments, generic use at -Onone. No Docker here: `tests/e2e/rex.sh` not
  run.
- Rex window (total `^MISSING`): 4,866 -> 4,776.
## 2026-11-25: Dictionary and Set, part 1: storage, hash table, core API (PR: stdlib-dictionary)

- Apple's Darwin representation: `Dictionary`/`Set` are one word, a
  `_BridgeStorage` (new, with the Builtin.BridgeObject helpers, `_isUnique`,
  `swap`) of native storage or a bridged NS collection. Native storage is
  `__RawDictionaryStorage`/`_DictionaryStorage<K,V>` (and the Set pair):
  count +16, capacity +24, scale +32, reservedScale +33, extra +34, age +36,
  seed +40, keys/elements +48, values +56, then the bitmap (+64 / +56), keys,
  values, all tail-allocated. Offsets checked against Rex's inlined lookups
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
- `_NativeDictionary`/`_NativeSet` with every entry point Rex imports
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
  No Docker here: `tests/e2e/rex.sh` not run.
- Rex window (total `^MISSING`): 4,866 -> 4,738. Left from this area:
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
- No Docker here: `tests/e2e/rex.sh` not run.
- Rex window (total `^MISSING`): BEFORE -> AFTER.

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
  `tests/e2e/rex.sh` not run.
- Rex window (total `^MISSING`): 4,561 -> 4,548 (every libswiftCore key path
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
  Suite 45/45 at -O and -Onone. No Docker here: `tests/e2e/rex.sh` not run.
- Rex window (total `^MISSING`): 4,548 -> 4,468.

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
  (`SWLIB_MACOS_NAME`); `tests/swiftlib/darwin` uses 14.0. Rex targets 14+
  and binds to `libswift_errno`/`libswift_signal` directly.
- `objc/objc.h`: `sel_registerName` and friends gained Apple's
  nullability (without it `SEL` imports as `Selector?`).
- `tests/swiftlib/darwin`: getpid/strlen, errno and POSIXErrorCode, open
  with mode, fcntl, write/fstat, signal with SIG_IGN, DarwinBoolean,
  ObjCBool, Selector equality/hash/name. Suite 46/46 at -O and -Onone. No
  Docker here: `tests/e2e/rex.sh` not run.
- Rex window (total `^MISSING`): 4,468 -> 4,432.
