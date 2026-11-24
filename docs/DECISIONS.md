# Decisions and dead ends

## Decisions

### No virtual machine
Running macOS in QEMU inside a container works but boots a whole operating
system: gigabytes of disk, minutes to start, and a licence question. The
project owner ruled it out. Everything here runs macOS programs as ordinary
Linux processes.

### Our own layer, not Darling
[Darling](https://github.com/darlinghq/darling) is the established
open-source macOS compatibility layer for Linux. Building on it (from
source) was the recommended starting point, because a macOS userland is an
enormous surface. The owner chose a from-scratch implementation with no
third-party compatibility code. The consequences are accepted knowingly:

- Small, readable, MIT-licensed, and every line is understood.
- Command-line and server programs are reachable quickly (the Mac app server ran
  within the first day).
- Graphical apps are far away: Objective-C, Swift, Foundation, AppKit and
  SwiftUI all have to be supplied (see [TARGET-APP.md](TARGET-APP.md)).

No Darling code, headers or binaries were used.

### What counts as "third party"
The line drawn: bitten may depend on the host's C library (glibc, libm,
libresolv), a C compiler, and Python's standard library. It does not vendor
or call other compatibility layers, disk-image tools, or Apple binaries.
Tests additionally use clang, LLVM's `ld64.lld` and the Go toolchain to
*produce* Mach-O test programs; none of that ships in the runtime image.

### Implement macOS libraries natively, not by running Apple's
The alternative design keeps Apple's own userland (`libSystem.dylib`,
Foundation, ...) and emulates only the kernel beneath it. That needs Apple's
binaries, which cannot be distributed and are not in a `.dmg` anyway. So
bitten implements the library interfaces themselves, in C, on Linux.

### One flat symbol table for system libraries
Mach-O binds each import to a specific library. bitten ignores which system
library was named and looks the symbol up in a single registry. It keeps the
code small and tolerates Apple moving symbols between libraries across OS
releases. Bundled Mach-O libraries keep proper two-level lookup.

### Layer on glibc rather than on raw Linux syscalls
Using glibc gives a tested `malloc`, stdio, resolver, locale and pthreads
for free. The cost is two thread-pointer registers in play (`%fs` for glibc,
`%gs` for Darwin code), which x86-64 Linux allows.

### Raw syscalls through syscall user dispatch
Options considered for `syscall` instructions inside Mach-O code: rewriting
the instructions at load time (fragile, misses generated code), seccomp
filters with `SIGSYS` (cannot tell host callers from Mach-O callers without
an address filter and cannot be changed later), and ptrace (slow, needs a
supervisor process). Syscall user dispatch is the kernel feature built for
exactly this and costs nothing on the normal path. It requires Linux 5.11.

### Real directories instead of path rewriting
A path-translation hook exists (`dx_path`, `BITTEN_ROOT`) but the container
simply has `/Applications`, `/Users`, `/private/tmp` and friends. Fewer
surprises than rewriting strings inside every call.

### Fail honestly
- An unimplemented import is bound to a stub that names the symbol when
  called. Nothing returns made-up success by default (`BITTEN_STUBS=zero`
  exists for exploration).
- Certificate trust evaluation is not implemented, so it answers "not
  trusted". The override that accepts everything is opt-in and logs a
  warning.
- The Mac app viewer is described everywhere as bitten's viewer, not the Mac app's GUI.

### The disk-image reader is Python
`dmgx` runs once per container start, is I/O-bound, and benefits from the
standard library's zlib, bz2 and lzma. The loader and the layer are C
because they define binary interfaces.

### Test with real Mach-O programs
Tests are compiled to Mach-O and run under `mrun`, rather than unit-testing
translation functions on the host. A test that passes has gone through the
loader, the fixups and the ABI for real. Go programs are part of the suite
because the Go runtime is a demanding client: it uses signals to rewrite
register state, its own thread-local slot, kqueue, and `LC_UNIXTHREAD`.

### Delegated work
Three self-contained pieces were written by a second coding agent (Codex) to
written specifications and then reviewed, built and verified here: the
disk-image reader, and the CoreFoundation / Security / libproc / resolver
batch. The pull requests say so.

## Dead ends and corrections

- **`LC_UNIXTHREAD` means "static binary".** Wrong. Go's linker emits it for
  dynamically linked macOS executables and expects the kernel's initial
  stack layout. First treated as unsupported; now implemented.
- **argv from the host stack.** Passing Linux's `argv` straight through
  crashed Go at start: it walks past `envp` looking for
  `executable_path=`, and found the ELF auxiliary vector instead.
- **The pty failure.** `open : no such file or directory` when the Mac app created
  a terminal was first blamed on the `TIOCPTYGNAME` ioctl (implemented and
  fine), then on a missing working directory. `strace` showed
  `syscall_0x2000036`: the binary issues the ioctl as a raw Darwin system
  call. That finding produced the syscall-dispatch design.
- **Fake malloc zone.** `malloc_default_zone()` returned an opaque token;
  SQLite called through its function table and jumped to address 0.
- **`sysctl` integer width.** Returning 8 bytes for `hw.pagesize` into a
  4-byte buffer made Go abort with "failed to get system page size".
- **`SOL_LOCAL` is level 0, the same number as `IPPROTO_IP`.** Peer
  credential options were being read as IP options; they are now told apart
  by socket family.
- **A thread handle race.** `pthread_join` on a thread that had not started
  running read an unset host thread id. It showed only outside the
  debugger.
- **Project names.** The repository was created as `dmgbox` and renamed by
  the owner to `scion`, `galapagos` and then `bitten` during the first day.
  Environment variables are `BITTEN_*`.
