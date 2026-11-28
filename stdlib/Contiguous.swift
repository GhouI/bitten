// _HasContiguousBytes (types whose bytes can be borrowed directly), and
// small String and Hasher additions programs call.

@usableFromInline
internal protocol _HasContiguousBytes {
  func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R
  var _providesContiguousBytesNoCopy: Bool { get }
}

extension _HasContiguousBytes {
  @inlinable var _providesContiguousBytesNoCopy: Bool { return true }
}

extension UnsafeRawBufferPointer: _HasContiguousBytes {
  @inlinable func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { return try body(self) }
}
extension UnsafeMutableRawBufferPointer: _HasContiguousBytes {
  @inlinable func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    return try body(UnsafeRawBufferPointer(self))
  }
}
extension UnsafeBufferPointer: _HasContiguousBytes {
  @inlinable func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    return try body(UnsafeRawBufferPointer(self))
  }
}
extension Array: _HasContiguousBytes {
  @inlinable var _providesContiguousBytesNoCopy: Bool { return true }
}
extension ContiguousArray: _HasContiguousBytes {}
extension ArraySlice: _HasContiguousBytes {}
extension String: _HasContiguousBytes {
  @inlinable var _providesContiguousBytesNoCopy: Bool { return false }
  @inlinable func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    let bytes = Array(utf8)
    return try bytes.withUnsafeBytes(body)
  }
}

extension String {
  /// The UTF-8 code units as C characters, NUL-terminated.
  public var utf8CString: ContiguousArray<CChar> {
    var result = ContiguousArray<CChar>()
    result.reserveCapacity(utf8.count + 1)
    for b in utf8 { result.append(CChar(bitPattern: b)) }
    result.append(0)
    return result
  }
}

extension String.Index {
  /// The UTF-16 offset of this index from the start of `s`.
  public func utf16Offset<S: StringProtocol>(in s: S) -> Int {
    return s.utf16.distance(from: s.utf16.startIndex, to: self)
  }
  public init<S: StringProtocol>(utf16Offset offset: Int, in s: S) {
    let u = s.utf16
    self = u.index(u.startIndex, offsetBy: offset)
  }
}

extension Hasher {
  public mutating func combine(bytes: UnsafeRawBufferPointer) {
    for b in bytes { combine(b) }
  }
}

/// The start of the scalar containing byte `idx` of a UTF-8 buffer.
@usableFromInline
internal func _scalarAlign(_ utf8: UnsafeBufferPointer<UInt8>, _ idx: Int) -> Int {
  guard idx != utf8.count else { return idx }
  var i = idx
  while i > 0 && utf8[i] & 0xC0 == 0x80 { i -= 1 }
  return i
}
