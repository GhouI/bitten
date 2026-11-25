// The SDK's Clang modules and the Darwin, ObjectiveC, _errno and _signal
// overlays, from ordinary Swift.
import Darwin
import ObjectiveC

@_silgen_name("swl_darwin_libc") public func libc() -> Int {
  var bad = 0
  // Plain C calls through the imported modules.
  if getpid() <= 0 { bad |= 1 }
  if strlen("hello") != 5 || abs(Int32(-3)) != 3 { bad |= 2 }
  // errno and POSIXErrorCode (the _errno overlay).
  errno = 0
  if open("/nonexistent/bitten", O_RDONLY) != -1 || errno != ENOENT { bad |= 4 }
  if POSIXErrorCode(rawValue: errno) != .ENOENT || POSIXErrorCode.EWOULDBLOCK != .EAGAIN { bad |= 8 }
  // The variadic open/fcntl forms and file modes.
  let path = "/tmp/bitten-swl-darwin"
  let fd = open(path, O_RDWR | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
  if fd < 0 { return bad | 16 }
  if fcntl(fd, F_GETFD) < 0 { bad |= 32 }
  let n = "abc".withCString { write(fd, $0, 3) }
  var st = stat()
  if n != 3 || fstat(fd, &st) != 0 || st.st_size != 3 || (st.st_mode & S_IFMT) != S_IFREG { bad |= 64 }
  close(fd)
  unlink(path)
  // Signal constants (the _signal overlay).
  let old = signal(SIGUSR1, SIG_IGN)
  if unsafeBitCast(old, to: Int.self) == unsafeBitCast(SIG_ERR, to: Int.self) { bad |= 128 }
  _ = signal(SIGUSR1, old)
  // DarwinBoolean.
  let t: DarwinBoolean = true
  if !t.boolValue || t == false { bad |= 256 }
  return bad
}

@_silgen_name("swl_darwin_objc") public func objc() -> Int {
  var bad = 0
  let y: ObjCBool = true
  if !y.boolValue || MemoryLayout<ObjCBool>.size != 1 { bad |= 1 }
  let a = Selector(_cString: "description"), b = sel_registerName("description")
  if a != b || a.hashValue != b.hashValue || a == sel_registerName("hash") { bad |= 2 }
  if String(cString: sel_getName(a)) != "description" { bad |= 4 }
  return bad
}

