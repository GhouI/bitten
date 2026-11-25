// String.Index, shared by String, Substring and all their views.
//
// Apple's @frozen layout, one UInt64:
//   b63-b16  encoded offset (a UTF-8 offset for every string made here)
//   b15-b14  transcoded offset (1 on the trailing surrogate of a UTF-16 pair)
//   b13-b8   cached character stride (0 when unknown)
//   b3       valid in UTF-16 strings, b2 valid in UTF-8 strings
//   b1       character aligned, b0 scalar aligned
// Compiled code builds `startIndex` as 0xF and `endIndex` as
// count << 16 | 0x7 (count << 16 | 0xB for UTF-16 foreign strings).
// Equality and order use the position and transcoded offset (b63-b14).

extension String {
  @frozen
  public struct Index: Sendable {
    @usableFromInline internal var _rawBits: UInt64

    @inlinable @inline(__always)
    internal init(_ raw: UInt64) { _rawBits = raw }
  }

  public typealias UnicodeScalarIndex = String.Index
}

extension String.Index {
  @inlinable @inline(__always)
  internal var orderingValue: UInt64 { return _rawBits &>> 14 }

  @inlinable @inline(__always)
  internal var _encodedOffset: Int { return Int(truncatingIfNeeded: _rawBits &>> 16) }

  @inlinable @inline(__always)
  internal var transcodedOffset: Int { return Int(truncatingIfNeeded: (_rawBits &>> 14) & 3) }

  @inlinable @inline(__always)
  internal init(_encodedOffset offset: Int) {
    self.init(UInt64(truncatingIfNeeded: offset) &<< 16)
  }

  @inlinable
  public var encodedOffset: Int { return _encodedOffset }

  @inlinable
  public init(encodedOffset offset: Int) { self.init(_encodedOffset: offset) }

  internal var characterStride: Int? {
    let s = Int(truncatingIfNeeded: (_rawBits &>> 8) & 0x3F)
    return s == 0 ? nil : s
  }

  internal var _isScalarAligned: Bool { return _rawBits & 1 != 0 }
  internal var _isCharacterAligned: Bool { return _rawBits & 2 != 0 }

  /// A UTF-8 index at a scalar boundary.
  @usableFromInline
  internal init(_scalarAt offset: Int) {
    self.init((UInt64(truncatingIfNeeded: offset) &<< 16) | 0x5)
  }

  /// A UTF-8 index at a character boundary, with the stride to the next
  /// one when it fits the cache.
  @usableFromInline
  internal init(_characterAt offset: Int, stride: Int) {
    let s: UInt64 = stride > 0 && stride < 64 ? UInt64(truncatingIfNeeded: stride) &<< 8 : 0
    self.init((UInt64(truncatingIfNeeded: offset) &<< 16) | s | 0x7)
  }

  /// A UTF-8 index at any byte.
  @usableFromInline
  internal init(_byteAt offset: Int) {
    self.init((UInt64(truncatingIfNeeded: offset) &<< 16) | 0x4)
  }

  /// The trailing surrogate of the scalar at `offset`.
  @usableFromInline
  internal init(_trailingSurrogateAt offset: Int) {
    self.init((UInt64(truncatingIfNeeded: offset) &<< 16) | (1 &<< 14) | 0x4)
  }
}

extension String.Index: Equatable {
  @inlinable @inline(__always)
  public static func == (lhs: String.Index, rhs: String.Index) -> Bool {
    return lhs.orderingValue == rhs.orderingValue
  }
}

extension String.Index: Comparable {
  @inlinable @inline(__always)
  public static func < (lhs: String.Index, rhs: String.Index) -> Bool {
    return lhs.orderingValue < rhs.orderingValue
  }
}

extension String.Index: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(orderingValue)
  }
}

// ---- navigation on the UTF-8 bytes --------------------------------------------------

extension _StringGuts {
  @inlinable @inline(__always)
  internal var startIndex: String.Index { return String.Index(0xF) }

  @inlinable @inline(__always)
  internal var endIndex: String.Index {
    return String.Index((UInt64(truncatingIfNeeded: count) &<< 16) | 0x7)
  }

  /// The start of the scalar containing byte `i`.
  internal func scalarAlign(_ i: Int) -> Int {
    var k = i
    if k >= count { return count }
    while k > 0 && _utf8IsContinuation(utf8Byte(at: k)) { k -= 1 }
    return k
  }

  @usableFromInline
  internal func fastUTF8ScalarLength(startingAt i: Int) -> Int {
    let b = utf8Byte(at: i)
    return b < 0x80 ? 1 : b < 0xE0 ? 2 : b < 0xF0 ? 3 : 4
  }

  internal func fastUTF8ScalarLength(endingAt i: Int) -> Int {
    var k = i - 1
    while _utf8IsContinuation(utf8Byte(at: k)) { k -= 1 }
    return i - k
  }

  internal func scalar(at i: Int) -> (scalar: UInt32, length: Int) {
    return withFastUTF8 { _decodeUTF8Scalar($0.baseAddress._unsafelyUnwrappedUnchecked, i) }
  }

  internal func scalar(endingAt i: Int) -> (scalar: UInt32, length: Int) {
    return withFastUTF8 { _decodeUTF8ScalarBefore($0.baseAddress._unsafelyUnwrappedUnchecked, i) }
  }

  /// The end of the character starting at `i`, within `i..<end`.
  internal func nextCharacterBoundary(_ i: Int, end: Int) -> Int {
    return withFastUTF8 { _nextGraphemeBoundary($0.baseAddress._unsafelyUnwrappedUnchecked, i, end) }
  }

  /// The start of the character ending at `i`, within `start..<end`.
  internal func previousCharacterBoundary(_ i: Int, start: Int, end: Int) -> Int {
    return withFastUTF8 { _previousGraphemeBoundary($0.baseAddress._unsafelyUnwrappedUnchecked, i, start, end) }
  }

  /// The character boundary at or before `i`, within `start..<end`.
  internal func characterAlign(_ i: Int, start: Int, end: Int) -> Int {
    if i <= start { return start }
    if i >= end { return end }
    let s = scalarAlign(i)
    if isASCII || s == start { return s }
    let prev = previousCharacterBoundary(s, start: start, end: end)
    let next = nextCharacterBoundary(prev, end: end)
    return next <= s ? next : prev
  }

  // ---- UTF-16 ----

  /// The number of UTF-16 code units in the bytes `start..<end` (on scalar
  /// boundaries).
  internal func utf16Count(_ start: Int, _ end: Int) -> Int {
    if isASCII { return end - start }
    return withFastUTF8 { b in
      let p = b.baseAddress._unsafelyUnwrappedUnchecked
      var n = 0, i = start
      while i < end {
        let x = p[i]
        if x < 0x80 { n += 1; i += 1 }
        else if x < 0xE0 { n += 1; i += 2 }
        else if x < 0xF0 { n += 1; i += 3 }
        else { n += 2; i += 4 }
      }
      return n
    }
  }

  /// The UTF-16 offset of an index.
  internal func utf16Offset(of i: String.Index) -> Int {
    return utf16Count(0, i._encodedOffset) + i.transcodedOffset
  }

  /// The index of a UTF-16 offset.
  internal func index(utf16Offset target: Int) -> String.Index {
    if isASCII { return String.Index(_scalarAt: target) }
    return withFastUTF8 { b in
      let p = b.baseAddress._unsafelyUnwrappedUnchecked
      var n = 0, i = 0
      let end = b.count
      while i < end && n < target {
        let x = p[i]
        if x < 0xF0 {
          n += 1
          i += x < 0x80 ? 1 : x < 0xE0 ? 2 : 3
        } else {
          if n + 1 == target { return String.Index(_trailingSurrogateAt: i) }
          n += 2
          i += 4
        }
      }
      return String.Index(_scalarAt: i)
    }
  }
}
