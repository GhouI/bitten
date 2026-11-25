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
