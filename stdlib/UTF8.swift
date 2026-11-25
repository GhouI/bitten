// UTF-8 validation, decoding and repair, used by String's initializers and
// views. Validity is RFC 3629: no overlong forms, no surrogates, nothing
// past U+10FFFF. Repair replaces each maximal invalid subpart with U+FFFD
// (Unicode's recommended practice, which is also what Apple's String does).

@inline(__always)
internal func _utf8IsContinuation(_ b: UInt8) -> Bool { return b & 0xC0 == 0x80 }

/// The length of the valid sequence at `i`, or 0 with `invalidLength` set to
/// the length of the maximal subpart to replace.
internal func _utf8SequenceLength(_ p: UnsafePointer<UInt8>, _ i: Int, _ end: Int) -> (valid: Int, invalid: Int) {
  let b0 = p[i]
  if b0 < 0x80 { return (1, 0) }
  var need = 0
  var lo: UInt8 = 0x80, hi: UInt8 = 0xBF
  switch b0 {
  case 0xC2...0xDF: need = 1
  case 0xE0: need = 2; lo = 0xA0
  case 0xE1...0xEC, 0xEE...0xEF: need = 2
  case 0xED: need = 2; hi = 0x9F
  case 0xF0: need = 3; lo = 0x90
  case 0xF1...0xF3: need = 3
  case 0xF4: need = 3; hi = 0x8F
  default: return (0, 1)
  }
  var k = 1
  while k <= need {
    if i + k >= end { return (0, k) }
    let b = p[i + k]
    if k == 1 {
      if b < lo || b > hi { return (0, 1) }
    } else if !_utf8IsContinuation(b) {
      return (0, k)
    }
    k += 1
  }
  return (need + 1, 0)
}

/// Whether the bytes are valid UTF-8, and whether they are all ASCII.
internal func _validateUTF8(_ b: UnsafeBufferPointer<UInt8>) -> (isValid: Bool, isASCII: Bool) {
  let n = b.count
  if n == 0 { return (true, true) }
  let p = b.baseAddress._unsafelyUnwrappedUnchecked
  var ascii = true
  var i = 0
  while i < n {
    if p[i] < 0x80 { i += 1; continue }
    ascii = false
    let (v, _) = _utf8SequenceLength(p, i, n)
    if v == 0 { return (false, false) }
    i += v
  }
  return (true, ascii)
}

/// Decodes the scalar starting at `i` of valid UTF-8.
@inline(__always)
internal func _decodeUTF8Scalar(_ p: UnsafePointer<UInt8>, _ i: Int) -> (scalar: UInt32, length: Int) {
  let b0 = UInt32(p[i])
  if b0 < 0x80 { return (b0, 1) }
  if b0 < 0xE0 {
    return (((b0 & 0x1F) &<< 6) | (UInt32(p[i + 1]) & 0x3F), 2)
  }
  if b0 < 0xF0 {
    return (((b0 & 0x0F) &<< 12) | ((UInt32(p[i + 1]) & 0x3F) &<< 6) | (UInt32(p[i + 2]) & 0x3F), 3)
  }
  return (((b0 & 0x07) &<< 18) | ((UInt32(p[i + 1]) & 0x3F) &<< 12)
          | ((UInt32(p[i + 2]) & 0x3F) &<< 6) | (UInt32(p[i + 3]) & 0x3F), 4)
}

/// Decodes the scalar ending just before `i` of valid UTF-8.
internal func _decodeUTF8ScalarBefore(_ p: UnsafePointer<UInt8>, _ i: Int) -> (scalar: UInt32, length: Int) {
  var j = i - 1
  while _utf8IsContinuation(p[j]) { j -= 1 }
  return (_decodeUTF8Scalar(p, j).scalar, i - j)
}

@inline(__always)
internal func _utf8Length(_ s: UInt32) -> Int {
  return s < 0x80 ? 1 : s < 0x800 ? 2 : s < 0x10000 ? 3 : 4
}

/// Writes the UTF-8 form of a scalar; returns its length.
@inline(__always)
internal func _encodeUTF8(_ s: UInt32, into p: UnsafeMutablePointer<UInt8>) -> Int {
  if s < 0x80 { p[0] = UInt8(truncatingIfNeeded: s); return 1 }
  if s < 0x800 {
    p[0] = UInt8(truncatingIfNeeded: 0xC0 | (s &>> 6))
    p[1] = UInt8(truncatingIfNeeded: 0x80 | (s & 0x3F))
    return 2
  }
  if s < 0x10000 {
    p[0] = UInt8(truncatingIfNeeded: 0xE0 | (s &>> 12))
    p[1] = UInt8(truncatingIfNeeded: 0x80 | ((s &>> 6) & 0x3F))
    p[2] = UInt8(truncatingIfNeeded: 0x80 | (s & 0x3F))
    return 3
  }
  p[0] = UInt8(truncatingIfNeeded: 0xF0 | (s &>> 18))
  p[1] = UInt8(truncatingIfNeeded: 0x80 | ((s &>> 12) & 0x3F))
  p[2] = UInt8(truncatingIfNeeded: 0x80 | ((s &>> 6) & 0x3F))
  p[3] = UInt8(truncatingIfNeeded: 0x80 | (s & 0x3F))
  return 4
}

/// UTF-8 bytes of one scalar packed little-endian, with the length.
@inline(__always)
internal func _utf8Packed(_ s: UInt32) -> (bytes: UInt64, count: Int) {
  var raw: UInt64 = 0
  let n = withUnsafeMutablePointer(to: &raw) {
    _encodeUTF8(s, into: UnsafeMutableRawPointer($0).assumingMemoryBound(to: UInt8.self))
  }
  return (raw, n)
}

extension String {
  /// A string from bytes that may not be valid UTF-8, with each invalid
  /// sequence replaced by U+FFFD.
  @usableFromInline
  internal static func _fromUTF8Repairing(_ input: UnsafeBufferPointer<UInt8>) -> (result: String, repairsMade: Bool) {
    let (valid, ascii) = _validateUTF8(input)
    if valid {
      if input.count == 0 { return ("", false) }
      return (String(_StringGuts(_copying: input.baseAddress._unsafelyUnwrappedUnchecked,
                                 count: input.count, isASCII: ascii)), false)
    }
    var g = _StringGuts(_initialCapacity: input.count + 8)
    let p = input.baseAddress._unsafelyUnwrappedUnchecked
    let n = input.count
    var i = 0
    var runStart = 0
    var fffd: (UInt8, UInt8, UInt8) = (0xEF, 0xBF, 0xBD)
    while i < n {
      if p[i] < 0x80 { i += 1; continue }
      let (v, bad) = _utf8SequenceLength(p, i, n)
      if v > 0 { i += v; continue }
      g.append(utf8: UnsafeBufferPointer(start: p + runStart, count: i - runStart), isASCII: false)
      withUnsafeMutablePointer(to: &fffd) {
        g.append(utf8: UnsafeBufferPointer(start: UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self), count: 3),
                 isASCII: false)
      }
      i += bad
      runStart = i
    }
    g.append(utf8: UnsafeBufferPointer(start: p + runStart, count: n - runStart), isASCII: false)
    // The appends above were flagged non-ASCII; the result is not ASCII
    // anyway, since it contains U+FFFD.
    return (String(g), true)
  }

  /// A string from bytes known to be valid UTF-8.
  @usableFromInline
  internal static func _uncheckedFromUTF8(_ input: UnsafeBufferPointer<UInt8>) -> String {
    if input.count == 0 { return "" }
    return String(_StringGuts(_copying: input.baseAddress._unsafelyUnwrappedUnchecked,
                              count: input.count, isASCII: _allASCII(input)))
  }

  @usableFromInline
  internal static func _uncheckedFromUTF8(_ input: UnsafeBufferPointer<UInt8>, isASCII: Bool) -> String {
    if input.count == 0 { return "" }
    return String(_StringGuts(_copying: input.baseAddress._unsafelyUnwrappedUnchecked,
                              count: input.count, isASCII: isASCII))
  }

  /// Validates; nil when the bytes are not UTF-8.
  @usableFromInline
  internal static func _tryFromUTF8(_ input: UnsafeBufferPointer<UInt8>) -> String? {
    let (valid, ascii) = _validateUTF8(input)
    if !valid { return nil }
    return _uncheckedFromUTF8(input, isASCII: ascii)
  }

  /// One scalar as a string.
  @usableFromInline
  internal init(_scalar s: UInt32) {
    var (raw, n) = _utf8Packed(s)
    self = withUnsafeMutablePointer(to: &raw) {
      String(_StringGuts(_small: UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self), count: n, isASCII: n == 1))
    }
  }
}
