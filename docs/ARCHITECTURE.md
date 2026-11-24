# Architecture

bitten is one Linux executable, `mrun`, that plays three roles a macOS
program expects from its system: the dynamic loader (dyld), the system
libraries (libSystem and a few frameworks), and, for the calls that bypass
those libraries, the kernel's system-call interface.

Docker containers share the host's Linux kernel, so macOS code cannot run
"natively" in one. The CPU instructions are the same on an x86-64 host; what
differs is everything a program asks its operating system for. bitten answers
those requests in user space.

```
            Mach-O program (unmodified, x86-64)
                 |  calls imported symbols            |  raw `syscall` instruction
                 v                                    v
   +-----------------------------+        +--------------------------+
   |  Darwin-ABI implementations |<-------|  SIGSYS handler          |
   |  (libSystem, frameworks)    |        |  (syscall user dispatch) |
   +-----------------------------+        +--------------------------+
                 |  ordinary Linux calls
                 v
          glibc and the Linux kernel
```

## The loader (`src/loader`)

`loader.c` does what dyld does for a process:

1. **Picks the x86-64 slice** of a universal ("fat") file.
2. **Maps the segments.** The main executable goes at its linked address
   (`0x100000000`) so addresses match static disassembly; libraries are
   placed just above it. Segments are mapped from the file copy-on-write when
   offsets are page-aligned.
3. **Applies fixups**, in both formats in use: the classic rebase/bind/lazy
   bind/weak bind opcode streams (`LC_DYLD_INFO`), and chained fixups
   (`LC_DYLD_CHAINED_FIXUPS`). Lazy binds are resolved eagerly.
4. **Resolves imports.** A Mach-O dependency that exists as a file (a
   framework bundled inside the app, found through `@rpath`,
   `@loader_path`, `@executable_path`) is loaded as Mach-O and searched
   through its export trie. Everything else, meaning the system libraries,
   comes from the *registry* described below. The two-level namespace is
   deliberately relaxed for registry symbols: one table serves every system
   library.
5. **Sets up thread-local variables.** Each TLV descriptor gets a thunk
   (`tlv.S`) that returns the variable's address and preserves every other
   register, allocating the thread's copy on first use.
6. **Runs initialisers** in dependency order (`__mod_init_func`,
   `__init_offsets`).
7. **Enters the program.** `LC_MAIN` entries are called as
   `main(argc, argv, envp, apple)`. `LC_UNIXTHREAD` entries (emitted by Go's
   own linker) expect the kernel's start-of-process stack and are jumped to.
   In both cases argv, envp and the "apple" strings are laid out contiguously
   because programs walk from one to the next.

An import nobody implements is bound to a small stub that reports the
symbol's name if it is ever called. `mrun --check` lists all of them without
running the program.

### The registry

Each implementation registers itself under its Mach-O symbol name:

```c
static int d_open(const char *path, int flags, int mode) { ... }
DX_FN(open);                          /* exports _open */
DX_EXPORT("_open$NOCANCEL", d_open);  /* variants share an implementation */
DX_PASS(strlen);                      /* identical ABI: use the host's */
```

The entries land in a linker section and are hashed at start-up. This is the
only coupling between the loader and the hundreds of functions: adding a
macOS API means writing a function and one macro line.

## The Darwin layer (`src/libsystem`, `src/frameworks`)

macOS and Linux both use the System V x86-64 calling convention, so a
function with the same types on both sides needs no wrapper at all. The work
is in the places where the systems differ:

| Area | Difference bridged |
| --- | --- |
| `errno` | Different numbering above 34; a per-thread Darwin errno returned by `__error()` |
| Files | `struct stat`, `statfs`, `dirent` layouts; `open`, `fcntl`, `*at` flag values; `F_GETPATH`, `F_FULLFSYNC` |
| Threads | Darwin pthread objects are larger and begin with a signature set by static initialisers; each wraps a host object. Thread-specific data lives in a per-thread block addressed through `%gs`, because compiled code reads slots directly (Go keeps its `g` pointer at `%gs:0x30`). glibc keeps `%fs` |
| Signals | Different numbers and `sigaction` layout, a 32-bit signal set, and handlers that expect Darwin's `siginfo`, `ucontext` and `mcontext64`. Handlers may edit the saved registers, and the edits are copied back |
| Processes | `posix_spawn` with file actions and attributes, wait-status and rlimit translation. `exec` of a Mach-O file re-enters `mrun`; ELF programs and scripts run natively, so a macOS program can start an ordinary Linux shell |
| Sockets | `sockaddr` with a length byte and different `AF_INET6`; option, `MSG_*` and `EAI_*` numbers; `msghdr` and control messages; peer credentials |
| kqueue | Emulated on epoll, with eventfd, timerfd, pidfd and inotify behind the user, timer, process and vnode filters |
| Terminals | `termios` layout and flag bits, tty/pty ioctl request codes |
| System info | `sysctl` by name and by MIB, `uname`, `sysconf` constants; the system reports itself as macOS 15.0 |
| Mach | Only what ordinary programs touch: time, task self, `vm_allocate`, `mach_vm_region` |
| libproc | Process listings and details from `/proc` |
| CoreFoundation | A small reference-counted object model: strings, data, arrays, dictionaries, numbers, dates, errors, locales |
| Security | Object plumbing only. Trust evaluation and the keychain report failure honestly |

Paths are not rewritten. The container simply provides the directories macOS
programs expect (`/Applications`, `/Users`, `/private/tmp`), and a
macOS-compatible `/usr/bin/login`.

## Objective-C and Blocks (`src/frameworks/objc`)

The Objective-C runtime is the gateway to every Cocoa and Swift program, so
it is implemented in full rather than stubbed:

- **Image registration.** After an image's fixups, the loader hands its
  `__objc_*` sections to the runtime: selector references are uniqued,
  protocols canonicalised, classes entered in the name table, categories
  queued. Classes are *realised* lazily on first use: a runtime record is
  attached, method lists are converted (including the relative "small"
  format), instance-variable offsets are slid when a superclass grew, and
  pending categories are attached. `+load` runs before C initialisers.
- **Dispatch.** `objc_msgSend` and its struct-return, floating-point and
  `super` variants are assembly (`msgsend.S`). The fast path probes a
  per-class cache without touching any argument register; the slow path
  saves them, asks the C runtime (which realises, runs `+initialize`,
  resolves dynamic methods, or follows a forwarding target) and jumps.
  Caches are replaced, never resized in place, so readers need no lock.
- **Lifetime.** Reference counts live in sharded side tables; weak
  references, associated objects, autorelease pools, `@synchronized` and the
  compiler's ARC entry points are all present, including the
  autoreleased-return handshake that keeps returned objects out of pools.
- **`NSObject`** lives here, as on macOS, along with the block classes and
  the `OS_object` base used by dispatch objects.
- **Blocks** (`blocks.c`): `_Block_copy`, `_Block_release`, `__block`
  variables and the copy/dispose helper protocol.

Not here yet: exceptions (needs an unwinder for Mach-O unwind tables),
full message forwarding through `NSInvocation`, and tagged pointers (never
created by this runtime, rejected if seen).

## Frameworks as Mach-O (`frameworks/`, `sdk/`)

Everything up to CoreFoundation is C compiled into `mrun`. Frameworks above
that line are Objective-C and are far more natural to write in Objective-C,
so they are: `frameworks/Foundation/*.m` is compiled by clang for the macOS
target and linked by `ld64.lld` into a real Mach-O library with the install
name `/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation`.
`mrun` finds it under its framework root (`BITTEN_ROOT`, or `root/` beside
the binary, or `/usr/local/lib/bitten/root`) and loads it with the same
loader as the application. Symbols a program expects from a framework but
that bitten implements in C still resolve through the registry.

**Toll-free bridging** ties the two halves together. Every CoreFoundation
object begins with an isa pointer to a class created inside `mrun`
(`__NSCFString`, `__NSCFArray`, ...), each inheriting from the public
abstract class (`NSString`, `NSArray`, ...), which `mrun` also creates and
exports. Foundation then adds the Objective-C methods as *categories* on
those classes, implemented by calling CoreFoundation. Compiler-emitted
constant strings (`@"..."`, `CFSTR`) carry the class
`__CFConstantStringClassReference` and are mapped to a CF string on first
use. CF's own functions accept foreign Objective-C objects too, so a
`CFArray` can hold any `NSObject`.

`sdk/include` holds bitten's own headers for all of this (a small C library
subset, `objc/runtime.h`, CoreFoundation, Foundation). They are what the
frameworks and the Foundation tests compile against, and they are the start
of an SDK for building macOS-style programs without Apple's.

## Raw system calls (`src/loader/rawsys.c`)

Some macOS code skips libSystem and executes `syscall` with a Darwin number
in `%rax` (`0x2000000 | n`). Linux would misread that. bitten uses **syscall
user dispatch**: the kernel is told that only the address range holding host
code (the loader, glibc, the vDSO, above `0x400000000000`) may make system
calls directly. Mach-O images are always mapped below that line, so a
`syscall` instruction inside one raises `SIGSYS`. The handler reads the
Darwin number and arguments from the saved registers, calls the same
implementation the libSystem symbol uses, and stores the result the way the
Darwin kernel would: carry flag clear and a value, or carry flag set and a
Darwin errno.

## Disk images (`tools/dmgx`)

A standard-library Python reader for the UDIF container, GPT and Apple
partition maps and HFS+ volumes, including LZFSE and LZMA chunks and HFS+
transparent compression. The container entrypoint uses it to unpack the
mounted image and to find the app bundle and its executables. See
[DMG-FORMAT.md](DMG-FORMAT.md).

## What is deliberately absent

- **CPU emulation.** x86-64 hosts run x86-64 slices. arm64-only apps would
  need a translator.
- **The Mach kernel.** Mach ports, messages and bootstrap services are not
  modelled. Programs that need XPC or launchd services will stop at the
  first such call.
- **Foundation, the Swift runtime and the GUI frameworks.** These are the
  bulk of what graphical apps need; see [ROADMAP.md](ROADMAP.md) for the
  order they will be built in and [TARGET-APP.md](TARGET-APP.md) for a measured example.
