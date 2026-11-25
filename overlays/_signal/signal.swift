// The Swift overlay of the _signal module (libswift_signal.dylib): the
// signal handler constants, which are casts in C and so cannot be imported.
// Current macOS moved them here from Darwin, keeping their mangled module
// name, so they are declared as originally defined in Darwin.
@_exported import _signal

/// The default action for a signal.
@available(macOS 10.9, *)
@_originallyDefinedIn(module: "Darwin", macOS 14.0)
public var SIG_DFL: sig_t? { return nil }

/// Ignore the signal.
@available(macOS 10.9, *)
@_originallyDefinedIn(module: "Darwin", macOS 14.0)
public var SIG_IGN: sig_t { return unsafeBitCast(1, to: sig_t.self) }

/// Hold the signal.
@available(macOS 10.9, *)
@_originallyDefinedIn(module: "Darwin", macOS 14.0)
public var SIG_HOLD: sig_t { return unsafeBitCast(5, to: sig_t.self) }

/// What signal() returns on failure.
@available(macOS 10.9, *)
@_originallyDefinedIn(module: "Darwin", macOS 14.0)
public var SIG_ERR: sig_t { return unsafeBitCast(-1, to: sig_t.self) }
