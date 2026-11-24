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
