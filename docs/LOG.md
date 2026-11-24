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
