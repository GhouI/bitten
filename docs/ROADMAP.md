# Roadmap

bitten runs x86-64 macOS programs as Linux processes, including inside
Docker. [ARCHITECTURE.md](ARCHITECTURE.md) explains how the layers fit
together; [NEXT.md](NEXT.md) is the handoff for the next change.

## Yardstick: beyond binding imports

At `b034ee1`, `mrun --check` found **zero missing required imports**
for both the window executable and its server/CLI. The window had 80
unbound weak imports and the server/CLI had none. In the GUI run, the server ran,
AppKit and SwiftUI opened interactive windows, and keyboard input reached
the shell after attachment. The terminal still appeared blank: Metal had
produced the pixels, but AppKit had not drawn them into the window. These
are measured paths, not a claim that all macOS APIs work.

## Next milestones

The following gaps are relative to main at `b034ee1`; proposed and
in-flight fixes are not counted as shipped.

1. **Show a presented drawable in its window.** Draw the backing layer's
   own contents and invalidate the owning view on presentation. Check the
   window bitmap after presenting, not just the texture before presentation.
2. **Compile shaders in the container on a cold cache.** The runtime image
   ships bitten's Swift libraries but not its Metal compiler helper,
   companion C source or clang. In the Docker test stage the tools are
   under `/src/tools`, outside the search paths for `/out/mrun`. Verify a
   shader actually compiles and draws in the image.
3. **Make a fresh session reliable.** Exercise first-run helper startup,
   Foundation's no-copy data selectors and Swift tuple casts during
   onboarding. A warm home directory can hide all three failures.
4. **Reduce the wait for an interactive terminal and check drawing
   fidelity.** Profile the wait for the shell to attach separately from
   painting its first frame. All settings pages opened in the later
   `b034ee1` check ([LOG.md](LOG.md)); verify that their controls, previews
   and labels actually draw and respond, not just that the page opens.

## Layers on main

| Layer | What works | Boundary |
| --- | --- | --- |
| Loader and libSystem | Mach-O loading and binding; translated file, process, socket, kqueue and raw BSD calls run C and Go programs | x86-64 slices and implemented Darwin calls only |
| Blocks, Objective-C and C++ | Block copy/dispose, class registration, message dispatch, ARC, forwarding targets; C++ allocation operators | No full C++ standard library or Mach-O exception unwinder; no full Objective-C invocation forwarding |
| Dispatch, compression and CommonCrypto | Queues, groups, semaphores, sources; zlib, LZFSE/LZVN, hashes and AES | Selected APIs, not the entire system libraries |
| CoreFoundation and Foundation | Bridged collections, files, bundles, plists, defaults, run loops, timers, KVC/KVO, invocation, tasks and pipes; URLSession uses host libcurl | A class being present does not imply it implements every selector |
| Security and services | Certificate and policy objects; anonymous in-process XPC; a per-user job table behind `launchctl` | No system keychain, Security trust evaluation, Mach bootstrap service or named XPC services |
| Swift | Native metadata, generics, casts and async runtime; bitten's Swift standard library, collections, Foundation and concurrency overlays | Compatibility depends on frozen layouts, witnesses and runtime behavior as well as exported names |
| CoreGraphics, CoreText, ImageIO and asset catalogs | CPU bitmap drawing, paths, gradients, TrueType glyphs, PNG and baseline JPEG; named bitmap and atlas renditions from `Assets.car` | No full text shaping or PDF/SVG catalog rendering |
| QuartzCore and AppKit | Layer trees, window bitmaps, controls, text, menus, panels and Auto Layout; browser or X11 display and input | Drawing a sublayer works; compositing a view's own backing-layer contents is a separate gap |
| Metal | Memory-backed buffers and textures, supported AIR vertex/fragment shaders, triangle rasterisation, blending and drawable presentation | Software only; no compute encoder. Off-screen rendering and visible presentation are separate milestones |
| SwiftUI, Combine and Observation | A hosted view graph, layout, controls, state and environment drive real AppKit windows | View coverage, layout fidelity and runtime stability remain incomplete |
| Other app frameworks | Network connections/listeners over sockets, CryptoKit hashing and keys, Swift Charts marks, AppIntents declarations | Frameworks differ in scope: for example, no Secure Enclave or system service to invoke intents |

The in-tree tests use synthetic Mach-O programs. In particular,
`tests/metal/render.m` checks texture pixels, `tests/appkit/layers.m`
checks a view's layer decoration, and `tests/appkit/deepmap2.m` exercises
catalog bitmap decoding. None of these alone proves that an app's Metal
frame reached the user's window.

## Longer-term work

- Extend disk-image input beyond HFS+/HFSX (APFS, encrypted or segmented
  images), and consider package installers or zipped app bundles.
- Consider transparent Mach-O execution in a reusable base image, rather
  than requiring an explicit `mrun` invocation.
- arm64-only binaries remain out of scope without a CPU translator.

Each small change gets a branch, a pull request and an entry in
[LOG.md](LOG.md). Move a support claim when a test or an observed run
demonstrates it. Nothing proprietary enters the repository.
