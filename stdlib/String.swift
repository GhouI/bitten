// String: construction, literals, concatenation, comparison and hashing.
// The representation is in StringObject.swift.


// The types the compiler gives text literals with no other context.
public typealias UnicodeScalarType = String
public typealias ExtendedGraphemeClusterType = String
public typealias StringLiteralType = String

@frozen
public struct String {
  public var _guts: _StringGuts

  @inlinable @inline(__always)
  internal init(_ _guts: _StringGuts) { self._guts = _guts }

  @inlinable @inline(__always) @_semantics("string.init_empty")
  public init() { self.init(_StringGuts()) }
}

extension String: Sendable {}

// ---- literals ----------------------------------------------------------------

extension String: _ExpressibleByBuiltinUnicodeScalarLiteral, _ExpressibleByBuiltinExtendedGraphemeClusterLiteral,
                  _ExpressibleByBuiltinStringLiteral, ExpressibleByStringLiteral {
  @inlinable @inline(__always) @_effects(readonly)
  public init(_builtinUnicodeScalarLiteral value: Builtin.Int32) {
    self.init(Unicode.Scalar(_value: UInt32(value)))
  }

  @inlinable @inline(__always) @_effects(readonly) @_semantics("string.makeUTF8")
  public init(_builtinExtendedGraphemeClusterLiteral start: Builtin.RawPointer,
              utf8CodeUnitCount: Builtin.Word, isASCII: Builtin.Int1) {
    self.init(_builtinStringLiteral: start, utf8CodeUnitCount: utf8CodeUnitCount, isASCII: isASCII)
  }

  /// Literals of up to 15 bytes become small strings (the optimizer folds
  /// the byte loads into constants); longer ones point at the constant bytes.
  @inlinable @inline(__always) @_effects(readonly) @_semantics("string.makeUTF8")
  public init(_builtinStringLiteral start: Builtin.RawPointer,
              utf8CodeUnitCount: Builtin.Word, isASCII: Builtin.Int1) {
    let n = Int(utf8CodeUnitCount)
    let p = UnsafePointer<UInt8>(start)
    if n <= 15 {
      self.init(_StringGuts(_small: p, count: n, isASCII: Bool(isASCII)))
    } else {
      self.init(_StringGuts(_immortal: p, count: n, isASCII: Bool(isASCII)))
    }
  }

  @inlinable @inline(__always)
  public init(stringLiteral value: String) { self = value }

  public typealias StringLiteralType = String
  public typealias ExtendedGraphemeClusterLiteralType = String
  public typealias UnicodeScalarLiteralType = String
}

extension String {
  @inlinable @inline(__always)
  public init(_ scalar: Unicode.Scalar) {
    self.init(_scalar: scalar.value)
  }

  @inlinable @inline(__always)
  public var isEmpty: Bool { return _guts.isEmpty }

  @inlinable
  internal var _utf8Count: Int { return _guts.count }

  /// Identity of representation, not equality.
  @_alwaysEmitIntoClient
  public func _isIdentical(to other: String) -> Bool {
    return _guts.rawBits.0 == other._guts.rawBits.0 && _guts.rawBits.1 == other._guts.rawBits.1
  }

  @_alwaysEmitIntoClient
  public var isContiguousUTF8: Bool { return _guts.isFastUTF8 }

  @_alwaysEmitIntoClient
  public mutating func makeContiguousUTF8() {}

  @_alwaysEmitIntoClient
  public mutating func withUTF8<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
    return try _guts.withFastUTF8(body)
  }

  @_alwaysEmitIntoClient @inline(__always)
  internal static func _createEmpty(withInitialCapacity: Int) -> String {
    return String(_StringGuts(_initialCapacity: withInitialCapacity))
  }
}

// ---- C strings ------------------------------------------------------------------

extension String {
  public init(cString nullTerminatedUTF8: UnsafePointer<CChar>) {
    let n = _bitten_strlen(nullTerminatedUTF8._rawValue)
    self = String._fromUTF8Repairing(UnsafeBufferPointer(start: UnsafePointer<UInt8>(nullTerminatedUTF8._rawValue), count: n)).result
  }

  public init(cString nullTerminatedUTF8: UnsafePointer<UInt8>) {
    let n = _bitten_strlen(nullTerminatedUTF8._rawValue)
    self = String._fromUTF8Repairing(UnsafeBufferPointer(start: nullTerminatedUTF8, count: n)).result
  }

  public init?(validatingCString nullTerminatedUTF8: UnsafePointer<CChar>) {
    let n = _bitten_strlen(nullTerminatedUTF8._rawValue)
    guard let s = String._tryFromUTF8(UnsafeBufferPointer(start: UnsafePointer<UInt8>(nullTerminatedUTF8._rawValue), count: n))
    else { return nil }
    self = s
  }

  @_alwaysEmitIntoClient
  public init?(validatingUTF8 cString: UnsafePointer<CChar>) {
    self.init(validatingCString: cString)
  }

  /// Calls `body` with a NUL-terminated copy of the string (native strings
  /// and literals are already NUL-terminated and are not copied).
  @inlinable
  public func withCString<Result>(_ body: (UnsafePointer<Int8>) throws -> Result) rethrows -> Result {
    if !_guts.isSmall && _guts.isFastUTF8 {
      return try body(UnsafePointer(_guts._object.largeFastUTF8Start._rawValue))
    }
    return try _withCStringSlow(body)
  }

  @usableFromInline
  internal func _withCStringSlow<Result>(_ body: (UnsafePointer<Int8>) throws -> Result) rethrows -> Result {
    // Small strings: 15 bytes and a NUL fit in two words on the stack.
    var raw: (UInt64, UInt64) = (0, 0)
    let n = _guts.count
    return try withUnsafeMutablePointer(to: &raw) { rp in
      let p = UnsafeMutableRawPointer(rp).assumingMemoryBound(to: UInt8.self)
      _guts.withFastUTF8 { p.update(from: $0.baseAddress._unsafelyUnwrappedUnchecked, count: n) }
      p[n] = 0
      return try body(UnsafePointer(p._rawValue))
    }
  }

  /// The owner and address of a NUL-terminated UTF-8 copy, for the
  /// compiler's String-to-pointer argument conversion.
  @usableFromInline
  internal func _cStringOwner() -> (AnyObject?, Builtin.RawPointer) {
    if !_guts.isSmall && _guts.isFastUTF8 {
      let owner: AnyObject? = _guts.hasNativeStorage ? _guts._object.nativeStorage : nil
      return (owner, _guts._object.largeFastUTF8Start._rawValue)
    }
    let n = _guts.count
    let s = __StringStorage.create(capacity: n, count: n, isASCII: _guts.isASCII)
    _guts.withFastUTF8 { if n > 0 { s.start.update(from: $0.baseAddress._unsafelyUnwrappedUnchecked, count: n) } }
    return (s, s.start._rawValue)
  }
}

@_transparent
public func _convertConstStringToUTF8PointerArgument<ToPointer: _Pointer>(_ str: String) -> (AnyObject?, ToPointer) {
  let (owner, p) = str._cStringOwner()
  return (owner, ToPointer(p))
}

// ---- building ------------------------------------------------------------------------

extension String {
  public init(unsafeUninitializedCapacity capacity: Int,
              initializingUTF8With initializer: (_ buffer: UnsafeMutableBufferPointer<UInt8>) throws -> Int) rethrows {
    let s = __StringStorage.create(capacity: capacity, count: 0, isASCII: true)
    let n = try initializer(UnsafeMutableBufferPointer(start: s.start, count: capacity))
    _precondition(n >= 0 && n <= capacity, "Initialized count must be in 0...capacity")
    self = String._fromUTF8Repairing(UnsafeBufferPointer(start: UnsafePointer(s.start), count: n)).result
  }

  public init(repeating repeatedValue: String, count: Int) {
    _precondition(count >= 0, "Negative count not allowed")
    let n = repeatedValue._guts.count
    if count == 0 || n == 0 { self = ""; return }
    let total = n * count
    var g = _StringGuts(_initialCapacity: total)
    let ascii = repeatedValue._guts.isASCII
    repeatedValue._guts.withFastUTF8 { b in
      var i = 0
      while i < count { g.append(utf8: b, isASCII: ascii); i += 1 }
    }
    self.init(g)
  }

  @_semantics("string.append")
  public mutating func append(_ other: String) {
    _guts.append(other._guts)
  }

  public mutating func append(contentsOf newElements: String) {
    append(newElements)
  }

  @inlinable @_effects(readonly) @_semantics("string.concat")
  public static func + (lhs: String, rhs: String) -> String {
    var result = lhs
    result.append(rhs)
    return result
  }

  @inlinable @_semantics("string.plusequals")
  public static func += (lhs: inout String, rhs: String) {
    lhs.append(rhs)
  }

  public mutating func reserveCapacity(_ n: Int) {
    _guts.reserveCapacity(n)
  }
}

// ---- comparison and hashing ------------------------------------------------------------

@frozen @usableFromInline
internal enum _StringComparisonResult {
  case equal
  case less
}

extension String: Equatable {
  @inlinable @inline(__always) @_effects(readonly) @_semantics("string.equals")
  public static func == (lhs: String, rhs: String) -> Bool {
    return _stringCompare(lhs._guts, rhs._guts, expecting: .equal)
  }
}

extension String: Comparable {
  @inlinable @inline(__always) @_effects(readonly)
  public static func < (lhs: String, rhs: String) -> Bool {
    return _stringCompare(lhs._guts, rhs._guts, expecting: .less)
  }
}

@inlinable @inline(__always) @_effects(readonly)
internal func _stringCompare(_ lhs: _StringGuts, _ rhs: _StringGuts, expecting: _StringComparisonResult) -> Bool {
  if lhs.rawBits.0 == rhs.rawBits.0 && lhs.rawBits.1 == rhs.rawBits.1 {
    return expecting == .equal
  }
  return _stringCompareWithSmolCheck(lhs, rhs, expecting: expecting)
}

/// Whether `lhs` compared to `rhs` gives `expecting`. Strings are ordered by
/// the Unicode scalar values of their canonical forms, which for UTF-8 is
/// the order of the bytes.
@usableFromInline @_effects(readonly)
internal func _stringCompareWithSmolCheck(_ lhs: _StringGuts, _ rhs: _StringGuts,
                                          expecting: _StringComparisonResult) -> Bool {
  return _stringCompareInternal(lhs, 0..<lhs.count, rhs, 0..<rhs.count, expecting: expecting)
}

@usableFromInline @_effects(readonly)
internal func _stringCompareInternal(_ lhs: _StringGuts, _ lhsRange: Range<Int>,
                                     _ rhs: _StringGuts, _ rhsRange: Range<Int>,
                                     expecting: _StringComparisonResult) -> Bool {
  let c = _stringCompareBytes(lhs, lhsRange, rhs, rhsRange)
  return expecting == .equal ? c == 0 : c < 0
}

/// -1, 0 or 1. Strings that are not both in NFC are compared in their
/// normalized form (see StringNormalization.swift).
internal func _stringCompareBytes(_ lhs: _StringGuts, _ lhsRange: Range<Int>,
                                  _ rhs: _StringGuts, _ rhsRange: Range<Int>) -> Int {
  if !(lhs.isNFC && rhs.isNFC) {
    return _stringCompareNormalized(lhs, lhsRange, rhs, rhsRange)
  }
  return lhs.withFastUTF8(range: lhsRange) { a in
    rhs.withFastUTF8(range: rhsRange) { b in _compareBytes(a, b) }
  }
}

internal func _compareBytes(_ a: UnsafeBufferPointer<UInt8>, _ b: UnsafeBufferPointer<UInt8>) -> Int {
  let n = a.count < b.count ? a.count : b.count
  if n > 0 {
    let c = _bitten_memcmp(a.baseAddress._unsafelyUnwrappedUnchecked._rawValue,
                           b.baseAddress._unsafelyUnwrappedUnchecked._rawValue, n)
    if c != 0 { return c < 0 ? -1 : 1 }
  }
  return a.count == b.count ? 0 : a.count < b.count ? -1 : 1
}

extension _StringComparisonResult {
  @inlinable @inline(__always)
  internal static func == (lhs: _StringComparisonResult, rhs: _StringComparisonResult) -> Bool {
    switch (lhs, rhs) {
    case (.equal, .equal), (.less, .less): return true
    default: return false
    }
  }
}

extension String: Hashable {
  /// The UTF-8 bytes of the canonical form, then 0xFF, as macOS does: so
  /// with deterministic hashing an NFC string hashes as it does there.
  public func hash(into hasher: inout Hasher) {
    _guts._hashNormalized(into: &hasher, range: 0..<_guts.count)
  }
}

extension _StringGuts {
  internal func _hashNormalized(into hasher: inout Hasher, range: Range<Int>) {
    if isNFC {
      withFastUTF8(range: range) { _hashBytes($0, into: &hasher) }
    } else {
      _withNormalizedUTF8(range: range) { _hashBytes($0, into: &hasher) }
    }
    hasher._combine(0xFF as UInt8)
  }
}

internal func _hashBytes(_ b: UnsafeBufferPointer<UInt8>, into hasher: inout Hasher) {
  let n = b.count
  if n == 0 { return }
  let p = b.baseAddress._unsafelyUnwrappedUnchecked
  var i = 0
  while i + 8 <= n {
    hasher._combine(UnsafeRawPointer(p + i).loadUnaligned(as: UInt64.self))
    i += 8
  }
  while i < n { hasher._combine(p[i]); i += 1 }
}

// ---- prefixes, suffixes, case --------------------------------------------------------

extension String {
  public func hasPrefix(_ prefix: String) -> Bool {
    let n = prefix._guts.count
    if n > _guts.count { return false }
    if n == 0 { return true }
    if _guts.isNFC && prefix._guts.isNFC {
      return _guts.withFastUTF8(range: 0..<n) { a in
        prefix._guts.withFastUTF8 { b in _compareBytes(a, b) == 0 }
      } && _isCharacterBoundary(utf8Offset: n)
    }
    return _hasPrefixNormalized(prefix)
  }

  public func hasSuffix(_ suffix: String) -> Bool {
    let n = suffix._guts.count, m = _guts.count
    if n > m { return false }
    if n == 0 { return true }
    if _guts.isNFC && suffix._guts.isNFC {
      return _guts.withFastUTF8(range: (m - n)..<m) { a in
        suffix._guts.withFastUTF8 { b in _compareBytes(a, b) == 0 }
      } && _isCharacterBoundary(utf8Offset: m - n)
    }
    return _hasSuffixNormalized(suffix)
  }

  @_effects(releasenone)
  public func lowercased() -> String { return _mapCase(upper: false) }

  @_effects(releasenone)
  public func uppercased() -> String { return _mapCase(upper: true) }

  internal func _mapCase(upper: Bool) -> String {
    if _guts.isASCII {
      let n = _guts.count
      return _guts.withFastUTF8 { src in
        var changed = false
        var i = 0
        while i < n {
          let b = src[i]
          if upper ? (b >= 0x61 && b <= 0x7A) : (b >= 0x41 && b <= 0x5A) { changed = true; break }
          i += 1
        }
        if !changed { return self }
        let s = __StringStorage.create(capacity: n, count: n, isASCII: true)
        i = 0
        while i < n {
          let b = src[i]
          if upper { s.start[i] = (b >= 0x61 && b <= 0x7A) ? b - 0x20 : b }
          else { s.start[i] = (b >= 0x41 && b <= 0x5A) ? b + 0x20 : b }
          i += 1
        }
        return String(_StringGuts(_copying: UnsafePointer(s.start), count: n, isASCII: true))
      }
    }
    var result = String._createEmpty(withInitialCapacity: _guts.count)
    _forEachScalar { s in
      _appendCaseMapped(s, upper: upper, to: &result)
    }
    return result
  }

  /// Calls `body` with each scalar value.
  internal func _forEachScalar(_ body: (UInt32) -> Void) {
    _guts.withFastUTF8 { b in
      let n = b.count
      if n == 0 { return }
      let p = b.baseAddress._unsafelyUnwrappedUnchecked
      var i = 0
      while i < n {
        let (s, l) = _decodeUTF8Scalar(p, i)
        body(s)
        i += l
      }
    }
  }

  internal mutating func _appendScalar(_ s: UInt32) {
    var (raw, n) = _utf8Packed(s)
    withUnsafeMutablePointer(to: &raw) {
      _guts.append(utf8: UnsafeBufferPointer(start: UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self), count: n),
                   isASCII: s < 0x80)
    }
  }
}
