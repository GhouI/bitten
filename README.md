# bitten

Run macOS apps from a `.dmg` inside an ordinary Docker container on Linux.
No virtual machine, no macOS install, no third-party compatibility layer:
bitten is its own Mach-O loader and Darwin compatibility layer, written from
scratch.

**Status: early.** See [docs/LOG.md](docs/LOG.md) for what works today.

## How it works

`mrun` is a normal Linux program. It maps an x86-64 Mach-O executable into its
own address space, applies the fixups dyld would apply, and binds every
imported macOS symbol to an implementation that lives inside `mrun` and speaks
Darwin's ABI on top of Linux.

```
make            # builds build/mrun
make check      # builds Mach-O test programs (clang + ld64.lld) and runs them
build/mrun path/to/macho-binary args...
```

No Apple code or SDK is used or distributed. You supply your own `.dmg`.
