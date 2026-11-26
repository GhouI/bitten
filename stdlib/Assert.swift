// Assertions, preconditions and the failure entry points the compiler and
// inlined standard-library code call. Messages go to stderr in the form
// macOS prints them ("<file>:<line>: Fatal error: <message>"), then the
// process traps.
//
// The forms that take a String message (fatalError, precondition, assert,
// assertionFailure, preconditionFailure and their _assertionFailure entry
// points) come with String.

// ---- branch hints ----------------------------------------------------------------

@_transparent public func _fastPath(_ x: Bool) -> Bool {
  return Bool(Builtin.int_expect_Int1(x._value, true._value))
}
@_transparent public func _slowPath(_ x: Bool) -> Bool {
  return Bool(Builtin.int_expect_Int1(x._value, false._value))
}

// ---- build configuration (decided in the client after inlining) ------------------

@_transparent public func _isDebugAssertConfiguration() -> Bool {
  return Int32(Builtin.assert_configuration()) == 0
}
@_transparent public func _isReleaseAssertConfiguration() -> Bool {
  return Int32(Builtin.assert_configuration()) == 1
}
@_transparent public func _isFastAssertConfiguration() -> Bool {
  return Int32(Builtin.assert_configuration()) == 2
}

// ---- writing the report ------------------------------------------------------------

@_silgen_name("write")
internal func _bitten_write(_ fd: Int32, _ buffer: Builtin.RawPointer, _ count: Int) -> Int
@_silgen_name("malloc")
internal func _bitten_malloc(_ size: Int) -> Builtin.RawPointer
@_silgen_name("memcpy")
internal func _bitten_memcpy(_ dst: Builtin.RawPointer, _ src: Builtin.RawPointer, _ n: Int) -> Builtin.RawPointer

/// A fixed buffer that a failure report is assembled in, then written to
/// stderr with a single write.
internal struct _ReportBuffer {
  internal var base: Builtin.RawPointer
  internal var count: Int
  internal let capacity: Int

  internal init(capacity: Int) {
    self.capacity = capacity
    base = _bitten_malloc(capacity)
    count = 0
  }
  internal var _end: Builtin.RawPointer {
    return Builtin.gepRaw_Word(base, count._builtinWordValue)
  }
  internal mutating func append(byte: UInt8) {
    if count == capacity { return }
    Builtin.initialize(byte, _end)
    count += 1
  }
  internal mutating func append(bytes: Builtin.RawPointer, count n: Int) {
    let room = capacity - count
    let k = n < room ? n : room
    _ = _bitten_memcpy(_end, bytes, k)
    count += k
  }
  internal mutating func append(scalar s: UInt32) {
    // UTF-8 encoding of one scalar.
    if s < 0x80 {
      append(byte: _byte(s))
    } else if s < 0x800 {
      append(byte: 0xC0 | _byte(s &>> 6))
      append(byte: 0x80 | _byte(s & 0x3F))
    } else if s < 0x10000 {
      append(byte: 0xE0 | _byte(s &>> 12))
      append(byte: 0x80 | _byte((s &>> 6) & 0x3F))
      append(byte: 0x80 | _byte(s & 0x3F))
    } else {
      append(byte: 0xF0 | _byte(s &>> 18))
      append(byte: 0x80 | _byte((s &>> 12) & 0x3F))
      append(byte: 0x80 | _byte((s &>> 6) & 0x3F))
      append(byte: 0x80 | _byte(s & 0x3F))
    }
  }
  internal mutating func append(_ s: StaticString) {
    if s.hasPointerRepresentation {
      append(bytes: s.unsafeRawPointer, count: Int(s._utf8CodeUnitCount))
    } else {
      append(scalar: UInt32(Builtin.truncOrBitCast_Word_Int32(s._startPtrOrData)))
    }
  }
  internal mutating func append(decimal v: UInt) {
    if v >= 10 { append(decimal: v / 10) }
    append(byte: 0x30 + UInt8(Builtin.truncOrBitCast_Int64_Int8(((v % 10) as UInt)._value)))
  }
  internal func writeToStderr() {
    _ = _bitten_write(2, base, count)
  }
}

@inline(__always)
internal func _byte(_ v: UInt32) -> UInt8 {
  return UInt8(Builtin.trunc_Int32_Int8(v._value))
}

@inline(__always)
internal func _int(_ v: Int32) -> Int { return Int(Builtin.sext_Int32_Int64(v._value)) }

internal func _isEmpty(_ s: StaticString) -> Bool {
  return s.hasPointerRepresentation && Int(s._utf8CodeUnitCount) == 0
}

/// "<file>:<line>: <prefix>: <message>\n" (", file" and ": message" are left
/// out when absent), written to stderr.
@inline(never)
internal func _reportFatalError(_ prefix: StaticString, _ message: StaticString,
                                file: StaticString, line: UInt, hasFile: Bool = true) {
  var b = _ReportBuffer(capacity: 4096)
  if hasFile {
    b.append(file)
    b.append(byte: 0x3A)  // ':'
    b.append(decimal: line)
    b.append(byte: 0x3A); b.append(byte: 0x20)
  }
  b.append(prefix)
  if !_isEmpty(message) {
    b.append(byte: 0x3A); b.append(byte: 0x20)
    b.append(message)
  }
  b.append(byte: 0x0A)
  b.writeToStderr()
}

// ---- entry points --------------------------------------------------------------------

@usableFromInline @inline(never) @_semantics("programtermination_point")
internal func _assertionFailure(_ prefix: StaticString, _ message: StaticString,
                                file: StaticString, line: UInt, flags: UInt32) -> Never {
  _reportFatalError(prefix, message, file: file, line: line)
  Builtin.int_trap()
}

@usableFromInline @inline(never) @_semantics("programtermination_point")
internal func _fatalErrorMessage(_ prefix: StaticString, _ message: StaticString,
                                 file: StaticString, line: UInt, flags: UInt32) -> Never {
  _reportFatalError(prefix, message, file: file, line: line)
  Builtin.int_trap()
}

@_transparent
public func _precondition(_ condition: @autoclosure () -> Bool,
                            _ message: StaticString = StaticString(),
                            file: StaticString = #file, line: UInt = #line) {
  if _isDebugAssertConfiguration() {
    if !_fastPath(condition()) {
      _assertionFailure("Fatal error", message, file: file, line: line, flags: 0)
    }
  } else if _isReleaseAssertConfiguration() {
    if !_fastPath(condition()) { Builtin.int_trap() }
  }
}

@_transparent
public func _preconditionFailure(_ message: StaticString = StaticString(),
                                   file: StaticString = #file, line: UInt = #line) -> Never {
  _precondition(false, message, file: file, line: line)
  Builtin.unreachable()
}

@_transparent
public func _debugPrecondition(_ condition: @autoclosure () -> Bool,
                                 _ message: StaticString = StaticString(),
                                 file: StaticString = #file, line: UInt = #line) {
  if _slowPath(_isDebugAssertConfiguration()) {
    if !_fastPath(condition()) {
      _fatalErrorMessage("Fatal error", message, file: file, line: line, flags: 0)
    }
  }
}

@usableFromInline @_transparent
internal func _debugPreconditionFailure(_ message: StaticString = StaticString(),
                                        file: StaticString = #file, line: UInt = #line) -> Never {
  if _slowPath(_isDebugAssertConfiguration()) {
    _precondition(false, message, file: file, line: line)
  }
  Builtin.int_trap()
}

@usableFromInline @_transparent
internal func _internalInvariant(_ condition: @autoclosure () -> Bool,
                                 _ message: StaticString = StaticString(),
                                 file: StaticString = #file, line: UInt = #line) {
  // Checked only when the standard library itself is built for debugging.
}

@_transparent
public func _overflowChecked<T>(_ args: (T, Bool), file: StaticString = #file,
                                line: UInt = #line) -> T {
  let (result, overflow) = args
  if _isDebugAssertConfiguration() {
    if _slowPath(overflow) {
      _fatalErrorMessage("Fatal error", "Overflow/underflow", file: file, line: line, flags: 0)
    }
  } else {
    if _slowPath(overflow) { Builtin.int_trap() }
  }
  return result
}

// The compiler emits calls to this when a force-unwrap finds nil.
@_transparent
public func _diagnoseUnexpectedNilOptional(_filenameStart: Builtin.RawPointer,
                                           _filenameLength: Builtin.Word,
                                           _filenameIsASCII: Builtin.Int1,
                                           _line: Builtin.Word,
                                           _isImplicitUnwrap: Builtin.Int1) {
  if _isDebugAssertConfiguration() {
    let file = StaticString(_start: _filenameStart, utf8CodeUnitCount: _filenameLength,
                            isASCII: _filenameIsASCII)
    if Bool(_isImplicitUnwrap) {
      _fatalErrorMessage("Fatal error",
        "Unexpectedly found nil while implicitly unwrapping an Optional value",
        file: file, line: UInt(_line), flags: 0)
    } else {
      _fatalErrorMessage("Fatal error",
        "Unexpectedly found nil while unwrapping an Optional value",
        file: file, line: UInt(_line), flags: 0)
    }
  }
  Builtin.int_trap()
}

// A switch over a non-frozen enum that met a case it does not know.
@usableFromInline @inline(never)
internal func _diagnoseUnexpectedEnumCaseValue<SwitchedValue, RawValue>(
  type: SwitchedValue.Type, rawValue: RawValue
) -> Never {
  _reportUnexpectedEnumCase(Builtin.reinterpretCast(type) as Builtin.RawPointer)
}
@usableFromInline @inline(never)
internal func _diagnoseUnexpectedEnumCase<SwitchedValue>(type: SwitchedValue.Type) -> Never {
  _reportUnexpectedEnumCase(Builtin.reinterpretCast(type) as Builtin.RawPointer)
}

@_silgen_name("swift_getTypeName")
internal func _bitten_getTypeName(_ type: Builtin.RawPointer, _ qualified: Bool) -> (Builtin.RawPointer, Int)

internal func _reportUnexpectedEnumCase(_ type: Builtin.RawPointer) -> Never {
  let (name, length) = _bitten_getTypeName(type, true)
  var b = _ReportBuffer(capacity: 1024)
  b.append("Fatal error: unexpected enum case while switching on value of type '")
  b.append(bytes: name, count: length)
  b.append(byte: 0x27); b.append(byte: 0x0A)
  b.writeToStderr()
  Builtin.int_trap()
}

@usableFromInline @inline(never) @_semantics("unavailable_code_reached")
internal func _diagnoseUnavailableCodeReached() -> Never {
  _reportFatalError("Fatal error", "Unavailable code reached", file: "", line: 0, hasFile: false)
  Builtin.int_trap()
}

// An `init` a subclass inherits but does not implement (the compiler emits
// this body for it). The two reporting functions are C entry points of
// libswiftCore that the inlined code calls. They are written in Swift with
// the C symbol names: for these integer and pointer arguments the Swift and
// C calling conventions place every argument in the same register or slot.
@_transparent
public func _unimplementedInitializer(className: StaticString,
                                      initName: StaticString = #function,
                                      file: StaticString = #file,
                                      line: UInt = #line,
                                      column: UInt = #column) -> Never {
  if _isDebugAssertConfiguration() {
    _bitten_reportUnimplementedInitializerInFile(
      className.unsafeRawPointer, Int32(Builtin.truncOrBitCast_Word_Int32(className._utf8CodeUnitCount)),
      initName.unsafeRawPointer, Int32(Builtin.truncOrBitCast_Word_Int32(initName._utf8CodeUnitCount)),
      file.unsafeRawPointer, Int32(Builtin.truncOrBitCast_Word_Int32(file._utf8CodeUnitCount)),
      UInt32(Builtin.truncOrBitCast_Word_Int32(line._builtinWordValue)),
      UInt32(Builtin.truncOrBitCast_Word_Int32(column._builtinWordValue)), 0)
  } else {
    _bitten_reportUnimplementedInitializer(
      className.unsafeRawPointer, Int32(Builtin.truncOrBitCast_Word_Int32(className._utf8CodeUnitCount)),
      initName.unsafeRawPointer, Int32(Builtin.truncOrBitCast_Word_Int32(initName._utf8CodeUnitCount)),
      0)
  }
  Builtin.int_trap()
}

@usableFromInline @_silgen_name("_swift_stdlib_reportUnimplementedInitializerInFile")
internal func _bitten_reportUnimplementedInitializerInFile(
  _ className: Builtin.RawPointer, _ classNameLength: Int32,
  _ initName: Builtin.RawPointer, _ initNameLength: Int32,
  _ file: Builtin.RawPointer, _ fileLength: Int32,
  _ line: UInt32, _ column: UInt32, _ flags: UInt32) {
  var b = _ReportBuffer(capacity: 1024)
  b.append(bytes: file, count: _int(fileLength))
  b.append(byte: 0x3A)
  b.append(decimal: UInt(Builtin.zext_Int32_Int64(line._value)))
  b.append(byte: 0x3A)
  b.append(decimal: UInt(Builtin.zext_Int32_Int64(column._value)))
  b.append(": Fatal error: Use of unimplemented initializer '")
  b.append(bytes: initName, count: _int(initNameLength))
  b.append("' for class '")
  b.append(bytes: className, count: _int(classNameLength))
  b.append(byte: 0x27); b.append(byte: 0x0A)
  b.writeToStderr()
}

@usableFromInline @_silgen_name("_swift_stdlib_reportUnimplementedInitializer")
internal func _bitten_reportUnimplementedInitializer(
  _ className: Builtin.RawPointer, _ classNameLength: Int32,
  _ initName: Builtin.RawPointer, _ initNameLength: Int32, _ flags: UInt32) {
  var b = _ReportBuffer(capacity: 1024)
  b.append("Fatal error: Use of unimplemented initializer '")
  b.append(bytes: initName, count: _int(initNameLength))
  b.append("' for class '")
  b.append(bytes: className, count: _int(classNameLength))
  b.append(byte: 0x27); b.append(byte: 0x0A)
  b.writeToStderr()
}

// ---- the forms with a String message ----------------------------------------------

extension _ReportBuffer {
  internal mutating func appendString(_ s: String) {
    s._guts.withFastUTF8 { b in
      if b.count > 0 { append(bytes: b.baseAddress._unsafelyUnwrappedUnchecked._rawValue, count: b.count) }
    }
  }
}

internal func _reportFatalErrorString(_ prefix: StaticString, _ message: String,
                                file: StaticString, line: UInt, hasFile: Bool) {
  var b = _ReportBuffer(capacity: 4096 + message._guts.count)
  if hasFile {
    b.append(file)
    b.append(byte: 0x3A)
    b.append(decimal: line)
    b.append(byte: 0x3A); b.append(byte: 0x20)
  }
  b.append(prefix)
  if !message.isEmpty {
    b.append(byte: 0x3A); b.append(byte: 0x20)
    b.appendString(message)
  }
  b.append(byte: 0x0A)
  b.writeToStderr()
}

@usableFromInline @inline(never) @_semantics("programtermination_point")
internal func _assertionFailure(_ prefix: StaticString, _ message: String,
                                file: StaticString, line: UInt, flags: UInt32) -> Never {
  _reportFatalErrorString(prefix, message, file: file, line: line, hasFile: true)
  Builtin.int_trap()
}

@usableFromInline @inline(never) @_semantics("programtermination_point")
internal func _assertionFailure(_ prefix: StaticString, _ message: String, flags: UInt32) -> Never {
  _reportFatalErrorString(prefix, message, file: "", line: 0, hasFile: false)
  Builtin.int_trap()
}

/// Always reports, in every build configuration.
@_transparent
public func fatalError(_ message: @autoclosure () -> String = String(),
                       file: StaticString = #file, line: UInt = #line) -> Never {
  _assertionFailure("Fatal error", message(), file: file, line: line, flags: 0)
}

/// Checked in debug and release builds; reports only in debug builds.
@_transparent
public func precondition(_ condition: @autoclosure () -> Bool,
                         _ message: @autoclosure () -> String = String(),
                         file: StaticString = #file, line: UInt = #line) {
  if _isDebugAssertConfiguration() {
    if !_fastPath(condition()) {
      _assertionFailure("Precondition failed", message(), file: file, line: line, flags: 0)
    }
  } else if _isReleaseAssertConfiguration() {
    if !_fastPath(condition()) { Builtin.int_trap() }
  }
}

@_transparent
public func preconditionFailure(_ message: @autoclosure () -> String = String(),
                                file: StaticString = #file, line: UInt = #line) -> Never {
  if _isDebugAssertConfiguration() {
    _assertionFailure("Fatal error", message(), file: file, line: line, flags: 0)
  }
  Builtin.int_trap()
}

/// Checked in debug builds only.
@_transparent
public func assert(_ condition: @autoclosure () -> Bool,
                   _ message: @autoclosure () -> String = String(),
                   file: StaticString = #file, line: UInt = #line) {
  if _isDebugAssertConfiguration() {
    if !_fastPath(condition()) {
      _assertionFailure("Assertion failed", message(), file: file, line: line, flags: 0)
    }
  }
}

@inlinable @inline(__always)
public func assertionFailure(_ message: @autoclosure () -> String = String(),
                             file: StaticString = #file, line: UInt = #line) {
  if _isDebugAssertConfiguration() {
    _assertionFailure("Fatal error", message(), file: file, line: line, flags: 0)
  }
}
