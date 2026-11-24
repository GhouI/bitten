# bitten

Run macOS programs from a `.dmg` inside an ordinary Docker container on Linux.

No virtual machine, no macOS installation and no borrowed compatibility
layer: bitten is its own Mach-O loader and its own implementation of the
macOS system interfaces, written from scratch on top of Linux.

```
docker build -t bitten .
docker run --rm -it -v /path/to/App.dmg:/dmg/app.dmg:ro bitten
```

That prints what is inside the image and how much of what each program needs
is implemented. You bring the `.dmg`; nothing from Apple or from any app is
in this repository or in the image.

## What works today

| Kind of program | Status |
| --- | --- |
| Command-line tools written in C against libSystem | Runs, within the implemented calls (about 1,000 symbols) |
| Go programs for macOS, with or without cgo | Runs: scheduler, GC, signals, network poller, `os/exec`, ptys |
| Programs that execute raw `syscall` instructions | Runs for the BSD calls listed in `src/loader/rawsys.c` |
| Programs needing CoreFoundation basics, libproc, the resolver | Runs for the implemented subset |
| TLS certificate checks through Security.framework | Not implemented: verification reports "not trusted" rather than pretend |
| Objective-C programs | Not yet: there is no Objective-C runtime |
| Swift programs | Not yet: there is no Swift runtime |
| AppKit / SwiftUI / Metal apps (windows) | Not yet |
| arm64-only binaries | No: x86-64 slices only (universal binaries are fine) |
| APFS-formatted disk images | Not yet: HFS+ images only |

The honest summary: bitten runs real macOS command-line and server programs
today, and does not run graphical macOS apps yet.

### The Mac app

The project's first target is the Mac app terminal (`App.dmg`, the Mac app Beta 0.1.0
build 1996). Its two programs stand like this:

| Program in the bundle | What it is | Status |
| --- | --- | --- |
| `Contents/Helpers/Server.app/Contents/MacOS/app-server` | The Mac app server and CLI (Go, cgo, SQLite) | **Runs unmodified.** Server, sessions, terminals, shells, `send`, `capture`, the control API |
| `Contents/MacOS/App` | The window: SwiftUI + AppKit + Metal | **Does not run.** It loads and binds, with 5,377 of its 5,688 imports unimplemented |

So the Mac app terminal *engine* from the disk image runs in the container, and
you can use a Mac app terminal through it:

```
APP_DMG=/path/to/App.dmg docker compose -f examples/mac-terminal/compose.yaml up
# open http://localhost:7680
```

The page is a small viewer that belongs to bitten, not the Mac app's own window: it
shows the screen with `appcli capture` and types with `appcli send`, both served by
the unmodified macOS binary. The Mac app's real window needs a Swift runtime,
Foundation, AppKit, SwiftUI and a Metal renderer, none of which exist here
yet. [docs/TARGET-APP.md](docs/TARGET-APP.md) has the numbers and what it would take.

## Using it

```
docker run --rm -it -v /path/App.dmg:/dmg/app.dmg:ro bitten [COMMAND]

  info                 what is in the image and what state each program is in (default)
  run [ARGS...]        run the app's main program
  exec NAME [ARGS...]  run another program from the bundle, such as a helper tool
  shell                a shell with every program in the bundle on PATH
  check NAME           list every import of NAME that is not implemented
```

With Compose, from this directory:

```
DMG=/path/App.dmg docker compose run --rm app            # info
DMG=/path/App.dmg docker compose run --rm app exec appcli version
```

The container needs no extra privileges. It uses `prctl` for syscall user
dispatch (Linux 5.11 or newer) and `arch_prctl`, both allowed by Docker's
default seccomp profile.

Without Docker:

```
make                      # builds build/mrun (needs gcc and make)
build/mrun path/to/macho-program args...
build/mrun --check path/to/macho-program     # what is missing
tools/dmgx extract App.dmg outdir            # unpack a disk image
```

## How it works

`mrun` is a normal Linux program. It maps the x86-64 slice of a Mach-O
executable into its own address space, applies the fixups dyld would apply,
and binds each imported macOS symbol to an implementation inside `mrun` that
speaks Darwin's ABI and is built on Linux and glibc. Where the two systems
disagree, bitten translates: structure layouts, flag and errno numbers,
signals and their saved contexts, thread-local storage through `%gs`,
kqueue on epoll, and raw Darwin system calls caught with syscall user
dispatch. A program that asks for something bitten lacks is told exactly
which symbol.

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains each piece.

## Repository layout

```
src/loader/      Mach-O loader, export registry, raw-syscall dispatch, entry point
src/libsystem/   libSystem: files, processes, threads, signals, sockets, kqueue, ttys, sysctl
src/frameworks/  CoreFoundation, Security and Objective-C surface
src/include/     shared headers (Mach-O format, Darwin ABI layouts)
tools/dmgx       .dmg extractor (UDIF, GPT/APM, HFS+), standard-library Python
docker/          container entrypoint and macOS-style login
ci/              GitHub Actions workflow, not yet enabled
examples/mac-terminal/    Compose file and terminal viewer for the Mac app
tests/c/         C tests, compiled to real Mach-O with clang + ld64.lld
tests/go/        Go tests, cross-compiled for darwin/amd64
docs/            architecture, the Mac app analysis, decisions, work log
```

## Tests

```
make check        # needs clang and lld; Go tests run when a Go toolchain is installed
make check-dmgx   # disk-image reader
docker build --target test .   # everything, in a clean container
```

A GitHub Actions workflow that runs the last command is in
`ci/github-actions.yml`; copy it to `.github/workflows/ci.yml` to switch it
on.

The tests are real Mach-O programs. C tests are compiled for
`x86_64-apple-macos` against hand-written declarations and linked with LLVM's
`ld64.lld` against a stub libSystem generated from bitten's own symbol list,
so no Apple SDK is involved. Go tests come from the Go toolchain's own macOS
linker.

## Scope and limits

- Linux x86-64 hosts and x86-64 Mach-O code only. There is no CPU emulation.
- The macOS version reported to programs is 15.0.
- Programs are not sandboxed from the container: a Mach-O program can do
  whatever a Linux program in the same container could.
- You are responsible for having the right to run the software you mount.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): design of the loader and the layer
- [docs/TARGET-APP.md](docs/TARGET-APP.md): what the Mac app imports, what is covered, what remains
- [docs/DECISIONS.md](docs/DECISIONS.md): choices made, and approaches that were dropped
- [docs/DMG-FORMAT.md](docs/DMG-FORMAT.md): disk-image support
- [docs/LOG.md](docs/LOG.md): running work log

## License

MIT, see [LICENSE](LICENSE). bitten contains no Apple code. Format and
interface knowledge comes from public documentation and from observing
programs run. In a few places published open-source material was read as a
reference for behaviour, not copied: Apple's open-source libproc wrapper for
return-value conventions, the LZFSE reference implementation, and the HFS+
technical note and decmpfs layouts cited in
[docs/DMG-FORMAT.md](docs/DMG-FORMAT.md).
