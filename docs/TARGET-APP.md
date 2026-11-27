# The target app: what runs

The yardstick is a terminal app distributed as a disk image. `App.dmg`,
`App` and `appcli` below stand for the image, the window executable and the
bundled server/CLI. bitten loads their x86-64 slices. Nothing from the
image is distributed here.

| Program | Missing required imports | Unbound weak imports | What works |
| --- | ---: | ---: | --- |
| `appcli` (Go, cgo, SQLite) | 0 | 0 | Starts the server, creates terminal sessions and sends and captures shell input and output |
| `App` (SwiftUI, AppKit, Metal) | 0 | 80 | Opens onboarding, the workspace and settings; installs and starts the server as a LaunchAgent and connects to it |

These are `mrun --check` counts for the two executables, not counts of
working features. The loader can leave a weak import unbound. An
Objective-C method sent by name, a Swift cast and a window that never
draws an image don't show up as missing imports.

## The server and CLI

The server uses a Unix socket and keeps session state in SQLite. The CLI
can start a session, send a command and read its output with
`appcli capture`. The shell runs on a pty. In the container, bitten's
`/usr/bin/login` handles the macOS login invocation.

[The terminal viewer](../examples/mac-terminal/terminal.py) uses the same
unmodified CLI: it polls capture for the screen and sends keystrokes with
`appcli send`. This is a way to use the terminal engine without starting
the GUI. The viewer on port 7680 is separate from the browser display on
port 7681, which shows the app's own windows.

The local server path does not need certificate trust evaluation.
`SecTrustEvaluateWithError` does not verify certificate chains yet, so
external connections that depend on it fail with the default settings.
The [container end-to-end check](../tests/e2e/target-app.sh) exercises a
local session, not remote login or every CLI subcommand.

## The app's own window

SwiftUI draws the workspace and its controls through AppKit. After a
terminal session attaches, keyboard input reaches the shell. Capturing the
session through the CLI shows the command and its output.

On the host, the software Metal device compiles the app's shaders and
produces frames with the prompt, text and cursor. The window stays white
where the terminal should be: the drawable becomes the backing layer's
`contents`, but AppKit draws only the layer background, sublayers and
border around the view's own drawing. Changing from the browser display
to X11 doesn't change that draw path. The Docker runtime has a separate
limit: it lacks the tools to compile the shaders in the first place.

A first run can also fail before there is a session to draw. The update
check uses a missing no-copy `NSData` method; skipping onboarding hits
a Swift tuple cast; and the GUI-launched CLI helper can exit with status 1
on a fresh home. See [NEXT.md](NEXT.md) for the checks that distinguish
these failures from a server that cannot run.
