// StaticString and Unicode.Scalar.
//
// StaticString is @frozen: a start word (a pointer to UTF-8 bytes, or the
// value of a single Unicode scalar), a UTF-8 code unit count and a flags
// byte (bit 0: scalar representation, bit 1: ASCII). Programs build it
// inline from literals and #file, so the layout is the ABI.

@frozen public enum Unicode {}

extension Unicode {
  @frozen public struct Scalar: Sendable {
    @usableFromInline internal var _value: UInt32
    @inlinable internal init(_value: UInt32) { self._value = _value }
  }
}

extension Unicode.Scalar: _ExpressibleByBuiltinUnicodeScalarLiteral, ExpressibleByUnicodeScalarLiteral {
  @inlinable public var value: UInt32 { get { return _value } }
  @_transparent public init(_builtinUnicodeScalarLiteral value: Builtin.Int32) {
    self._value = UInt32(value)
  }
  @_transparent public init(unicodeScalarLiteral value: Unicode.Scalar) { self = value }
  @inlinable public init?(_ v: UInt32) {
    // Surrogates and values past U+10FFFF are not scalars.
    if v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF) { return nil }
    self._value = v
  }
  @inlinable public init?(_ v: UInt16) {
    self.init(UInt32(Builtin.zext_Int16_Int32(v._value)))
  }
  @inlinable public init(_ v: UInt8) {
    self._value = UInt32(Builtin.zext_Int8_Int32(v._value))
  }
  @inlinable public init?(_ v: Int) {
    if v < 0 || v > 0x10FFFF { return nil }
    self.init(UInt32(truncatingIfNeeded: v))
  }
  @inlinable public init(_ v: Unicode.Scalar) { self = v }
  @inlinable public var isASCII: Bool { get { return _value < 0x80 } }
  public typealias UnicodeScalarLiteralType = Unicode.Scalar
}
extension Unicode.Scalar: Equatable {
  @inlinable public static func == (lhs: Unicode.Scalar, rhs: Unicode.Scalar) -> Bool {
    return lhs._value == rhs._value
  }
}
extension Unicode.Scalar: Comparable {
  @inlinable public static func < (lhs: Unicode.Scalar, rhs: Unicode.Scalar) -> Bool {
    return lhs._value < rhs._value
  }
}
extension UInt32 {
  @inlinable public init(_ v: Unicode.Scalar) { self = v._value }
}
extension UInt64 {
  @inlinable public init(_ v: Unicode.Scalar) {
    self.init(Builtin.zext_Int32_Int64(v._value._value))
  }
}
extension UInt8 {
  @inlinable public init(ascii v: Unicode.Scalar) {
    _precondition(v._value < 128, "Code point value does not fit into ASCII")
    self.init(Builtin.trunc_Int32_Int8(v._value._value))
  }
}

// ---- StaticString -------------------------------------------------------------

@frozen public struct StaticString: Sendable {
  @usableFromInline internal var _startPtrOrData: Builtin.Word
  @usableFromInline internal var _utf8CodeUnitCount: Builtin.Word
  @usableFromInline internal var _flags: Builtin.Int8

  @_transparent public init() { self = "" }

  @usableFromInline @_transparent
  internal init(_start: Builtin.RawPointer, utf8CodeUnitCount: Builtin.Word, isASCII: Builtin.Int1) {
    _startPtrOrData = Builtin.ptrtoint_Word(_start)
    _utf8CodeUnitCount = utf8CodeUnitCount
    _flags = Bool(isASCII) ? (2 as UInt8)._value : (0 as UInt8)._value
  }

  @usableFromInline @_transparent
  internal init(unicodeScalar: Builtin.Int32) {
    _startPtrOrData = Builtin.zextOrBitCast_Int32_Word(unicodeScalar)
    _utf8CodeUnitCount = Builtin.zextOrBitCast_Int32_Word(Builtin.zeroInitializer())
    _flags = UInt32(unicodeScalar) < 0x80 ? (3 as UInt8)._value : (1 as UInt8)._value
  }

  @_transparent public var hasPointerRepresentation: Bool {
    @_transparent get { return UInt8(_flags) & 1 == 0 }
  }
  @_transparent public var isASCII: Bool {
    @_transparent get { return UInt8(_flags) & 2 != 0 }
  }
  @_transparent public var utf8CodeUnitCount: Int {
    @_transparent get {
      _precondition(hasPointerRepresentation,
                    "StaticString should have pointer representation")
      return Int(_utf8CodeUnitCount)
    }
  }
  @_transparent public var unicodeScalar: Unicode.Scalar {
    @_transparent get {
      _precondition(!hasPointerRepresentation,
                    "StaticString should have Unicode scalar representation")
      return Unicode.Scalar(_value: UInt32(Builtin.truncOrBitCast_Word_Int32(_startPtrOrData)))
    }
  }
  @_alwaysEmitIntoClient @_transparent
  internal var unsafeRawPointer: Builtin.RawPointer {
    @_transparent get { return Builtin.inttoptr_Word(_startPtrOrData) }
  }
}

extension StaticString: _ExpressibleByBuiltinUnicodeScalarLiteral {
  @_effects(readonly) @_transparent
  public init(_builtinUnicodeScalarLiteral value: Builtin.Int32) {
    self = StaticString(unicodeScalar: value)
  }
}
extension StaticString: ExpressibleByUnicodeScalarLiteral {
  @_effects(readonly) @_transparent
  public init(unicodeScalarLiteral value: StaticString) { self = value }
  public typealias UnicodeScalarLiteralType = StaticString
}
extension StaticString: _ExpressibleByBuiltinExtendedGraphemeClusterLiteral {
  @_effects(readonly) @_transparent
  public init(_builtinExtendedGraphemeClusterLiteral start: Builtin.RawPointer,
              utf8CodeUnitCount: Builtin.Word, isASCII: Builtin.Int1) {
    self = StaticString(_start: start, utf8CodeUnitCount: utf8CodeUnitCount, isASCII: isASCII)
  }
}
extension StaticString: ExpressibleByExtendedGraphemeClusterLiteral {
  @_effects(readonly) @_transparent
  public init(extendedGraphemeClusterLiteral value: StaticString) { self = value }
  public typealias ExtendedGraphemeClusterLiteralType = StaticString
}
extension StaticString: _ExpressibleByBuiltinStringLiteral {
  @_effects(readonly) @_transparent
  public init(_builtinStringLiteral start: Builtin.RawPointer,
              utf8CodeUnitCount: Builtin.Word, isASCII: Builtin.Int1) {
    self = StaticString(_start: start, utf8CodeUnitCount: utf8CodeUnitCount, isASCII: isASCII)
  }
}
extension StaticString: ExpressibleByStringLiteral {
  @_effects(readonly) @_transparent
  public init(stringLiteral value: StaticString) { self = value }
  public typealias StringLiteralType = StaticString
}
