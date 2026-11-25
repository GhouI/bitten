// The Swift overlay of the Darwin module (libswiftDarwin.dylib): the C
// library re-exported, with what C cannot express for Swift: the file mode
// constants with their C type, fixed-argument forms of the variadic calls,
// the standard streams, and DarwinBoolean.
@_exported import Darwin
@_exported import _errno
@_exported import _signal

// ---- file modes -------------------------------------------------------------
// Octal macros import as Int32; Swift code expects mode_t.

public var S_IFMT: mode_t { return mode_t(0o170000) }
public var S_IFIFO: mode_t { return mode_t(0o010000) }
public var S_IFCHR: mode_t { return mode_t(0o020000) }
public var S_IFDIR: mode_t { return mode_t(0o040000) }
public var S_IFBLK: mode_t { return mode_t(0o060000) }
public var S_IFREG: mode_t { return mode_t(0o100000) }
public var S_IFLNK: mode_t { return mode_t(0o120000) }
public var S_IFSOCK: mode_t { return mode_t(0o140000) }
public var S_IFWHT: mode_t { return mode_t(0o160000) }
public var S_IRWXU: mode_t { return mode_t(0o000700) }
public var S_IRUSR: mode_t { return mode_t(0o000400) }
public var S_IWUSR: mode_t { return mode_t(0o000200) }
public var S_IXUSR: mode_t { return mode_t(0o000100) }
public var S_IRWXG: mode_t { return mode_t(0o000070) }
public var S_IRGRP: mode_t { return mode_t(0o000040) }
public var S_IWGRP: mode_t { return mode_t(0o000020) }
public var S_IXGRP: mode_t { return mode_t(0o000010) }
public var S_IRWXO: mode_t { return mode_t(0o000007) }
public var S_IROTH: mode_t { return mode_t(0o000004) }
public var S_IWOTH: mode_t { return mode_t(0o000002) }
public var S_IXOTH: mode_t { return mode_t(0o000001) }
public var S_ISUID: mode_t { return mode_t(0o004000) }
public var S_ISGID: mode_t { return mode_t(0o002000) }
public var S_ISVTX: mode_t { return mode_t(0o001000) }

// ---- variadic calls ---------------------------------------------------------
// Swift cannot call C variadic functions; these go through the fixed-argument
// inline helpers in the SDK headers.

public func open(_ path: UnsafePointer<CChar>, _ oflag: Int32) -> Int32 {
  return __bitten_open(path, oflag, 0)
}

public func open(_ path: UnsafePointer<CChar>, _ oflag: Int32, _ mode: mode_t) -> Int32 {
  return __bitten_open(path, oflag, mode)
}

public func openat(_ fd: Int32, _ path: UnsafePointer<CChar>, _ oflag: Int32) -> Int32 {
  return __bitten_openat(fd, path, oflag, 0)
}

public func openat(_ fd: Int32, _ path: UnsafePointer<CChar>, _ oflag: Int32, _ mode: mode_t) -> Int32 {
  return __bitten_openat(fd, path, oflag, mode)
}

public func fcntl(_ fd: Int32, _ cmd: Int32) -> Int32 {
  return __bitten_fcntl(fd, cmd, 0)
}

public func fcntl(_ fd: Int32, _ cmd: Int32, _ value: Int32) -> Int32 {
  return __bitten_fcntl(fd, cmd, value)
}

public func fcntl(_ fd: Int32, _ cmd: Int32, _ ptr: UnsafeMutableRawPointer) -> Int32 {
  return __bitten_fcntl_ptr(fd, cmd, ptr)
}

public func ioctl(_ fd: CInt, _ request: UInt, _ value: CInt) -> CInt {
  return __bitten_ioctl_int(fd, request, value)
}

public func ioctl(_ fd: CInt, _ request: UInt, _ ptr: UnsafeMutableRawPointer) -> CInt {
  return __bitten_ioctl_ptr(fd, request, ptr)
}

public func ioctl(_ fd: CInt, _ request: UInt) -> CInt {
  return __bitten_ioctl(fd, request)
}

// ---- standard streams -------------------------------------------------------

public var stdin: UnsafeMutablePointer<FILE> {
  get { return __stdinp }
  set { __stdinp = newValue }
}

public var stdout: UnsafeMutablePointer<FILE> {
  get { return __stdoutp }
  set { __stdoutp = newValue }
}

public var stderr: UnsafeMutablePointer<FILE> {
  get { return __stderrp }
  set { __stderrp = newValue }
}

// ---- DarwinBoolean ----------------------------------------------------------
// The C type Boolean (an unsigned char) imports as this, and as Bool in
// function signatures through the two conversion functions the compiler
// calls by name.

@frozen
public struct DarwinBoolean: ExpressibleByBooleanLiteral, Sendable {
  @usableFromInline var _value: UInt8

  @_transparent
  public init(_ value: Bool) {
    self._value = value ? 1 : 0
  }

  public var boolValue: Bool {
    @_transparent get { return _value != 0 }
  }

  @_transparent
  public init(booleanLiteral value: Bool) {
    self.init(value)
  }
}

extension DarwinBoolean: Equatable {
  @_transparent
  public static func == (lhs: DarwinBoolean, rhs: DarwinBoolean) -> Bool {
    return lhs.boolValue == rhs.boolValue
  }
}

@_transparent
public func _convertBoolToDarwinBoolean(_ x: Bool) -> DarwinBoolean {
  return DarwinBoolean(x)
}

@_transparent
public func _convertDarwinBooleanToBool(_ x: DarwinBoolean) -> Bool {
  return x.boolValue
}
