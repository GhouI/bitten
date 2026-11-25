// Character: one extended grapheme cluster, stored as a String (@frozen,
// as in Apple's layout).

@frozen
public struct Character: Sendable {
  @usableFromInline internal var _str: String

  @inlinable @inline(__always)
  internal init(unchecked str: String) { _str = str }
}

extension Character {
  @inlinable @inline(__always)
  public init(_ content: Unicode.Scalar) {
    self.init(unchecked: String(content))
  }

  /// A character from a string holding exactly one grapheme cluster.
  @inlinable @inline(__always)
  public init(_ s: String) {
    _precondition(!s.isEmpty, "Can't form a Character from an empty String")
    _debugPrecondition(s._isSingleGrapheme, "Can't form a Character from a String containing more than one extended grapheme cluster")
    self.init(unchecked: s)
  }

  public typealias UTF8View = String.UTF8View
  public typealias UTF16View = String.UTF16View
  public typealias UnicodeScalarView = String.UnicodeScalarView

  @inlinable public var utf8: UTF8View { return _str.utf8 }
  @inlinable public var utf16: UTF16View { return _str.utf16 }
  @inlinable public var unicodeScalars: UnicodeScalarView { return _str.unicodeScalars }

  @inlinable public var isASCII: Bool { return asciiValue != nil }

  /// The ASCII value, with CR-LF counting as LF (as on macOS).
  @inlinable public var asciiValue: UInt8? {
    if _slowPath(_str == "\r\n") { return 0x0A }
    if _str._guts.count == 1 && _str._guts.isASCII { return _str._guts.utf8Byte(at: 0) }
    return nil
  }

  public func lowercased() -> String { return _str.lowercased() }
  public func uppercased() -> String { return _str.uppercased() }

  /// Whether this is a single Unicode scalar.
  @usableFromInline
  internal var _isSingleScalar: Bool {
    let g = _str._guts
    return g.count != 0 && g.fastUTF8ScalarLength(startingAt: 0) == g.count
  }

  @inlinable
  public var description: String { return _str }
}

extension String {
  @usableFromInline
  internal var _isSingleGrapheme: Bool {
    let n = _guts.count
    return n > 0 && _guts.nextCharacterBoundary(0, end: n) == n
  }

  @inlinable @inline(__always)
  public init(_ c: Character) { self = c._str }
}

extension Character: _ExpressibleByBuiltinExtendedGraphemeClusterLiteral, ExpressibleByExtendedGraphemeClusterLiteral {
  @inlinable @inline(__always) @_effects(readonly)
  public init(_builtinUnicodeScalarLiteral value: Builtin.Int32) {
    self.init(unchecked: String(_builtinUnicodeScalarLiteral: value))
  }

  @inlinable @inline(__always) @_effects(readonly)
  public init(_builtinExtendedGraphemeClusterLiteral start: Builtin.RawPointer,
              utf8CodeUnitCount: Builtin.Word, isASCII: Builtin.Int1) {
    self.init(unchecked: String(_builtinExtendedGraphemeClusterLiteral: start,
                                utf8CodeUnitCount: utf8CodeUnitCount, isASCII: isASCII))
  }

  @inlinable @inline(__always)
  public init(extendedGraphemeClusterLiteral value: Character) { self = value }

  public typealias ExtendedGraphemeClusterLiteralType = Character
  public typealias UnicodeScalarLiteralType = Character
}

extension Character: Equatable {
  @inlinable @inline(__always) @_effects(readonly)
  public static func == (lhs: Character, rhs: Character) -> Bool { return lhs._str == rhs._str }
}

extension Character: Comparable {
  @inlinable @inline(__always) @_effects(readonly)
  public static func < (lhs: Character, rhs: Character) -> Bool { return lhs._str < rhs._str }
}

extension Character: Hashable {
  @_effects(releasenone)
  public func hash(into hasher: inout Hasher) { _str.hash(into: &hasher) }
}

extension Character: TextOutputStreamable {
  public func write<Target: TextOutputStream>(to target: inout Target) {
    target.write(_str)
  }
}

extension Character: CustomStringConvertible {}
