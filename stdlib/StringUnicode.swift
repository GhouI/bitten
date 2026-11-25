// The Unicode-aware parts of String's comparison, hashing and prefix
// tests: strings compare and hash by their NFC form (canonical
// equivalence), and prefixes must end on a character boundary.

extension StaticString {
  @_transparent
  public var utf8Start: UnsafePointer<UInt8> {
    _precondition(hasPointerRepresentation, "StaticString should have pointer representation")
    return UnsafePointer(unsafeRawPointer)
  }
}

internal func _stringCompareNormalized(_ lhs: _StringGuts, _ lhsRange: Range<Int>,
                                       _ rhs: _StringGuts, _ rhsRange: Range<Int>) -> Int {
  return lhs._withNormalizedUTF8(range: lhsRange) { a in
    rhs._withNormalizedUTF8(range: rhsRange) { b in _compareBytes(a, b) }
  }
}

extension _StringGuts {
  internal func _withNormalizedUTF8<R>(range: Range<Int>, _ body: (UnsafeBufferPointer<UInt8>) -> R) -> R {
    if isNFC { return withFastUTF8(range: range, body) }
    return withFastUTF8(range: range) { _withNFC($0, body) }
  }

  /// Whether a character boundary falls at byte `i` (which must be on a
  /// scalar boundary for a true answer).
  internal func isCharacterBoundary(_ i: Int, start: Int = 0, end: Int? = nil) -> Bool {
    let e = end ?? count
    if i <= start || i >= e { return true }
    return withFastUTF8 { b in
      let p = b.baseAddress._unsafelyUnwrappedUnchecked
      if _utf8IsContinuation(p[i]) { return false }
      return _nextGraphemeBoundary(p, _previousGraphemeBoundary(p, i, start, e), e) == i
    }
  }
}

extension String {
  internal func _isCharacterBoundary(utf8Offset i: Int) -> Bool {
    return _guts.isCharacterBoundary(i)
  }

  /// Prefix tests on the canonical forms: the prefix's NFC must be a
  /// prefix of ours that ends on a character boundary.
  internal func _hasPrefixNormalized(_ prefix: String) -> Bool {
    return _guts._withNormalizedUTF8(range: 0..<_guts.count) { a in
      prefix._guts._withNormalizedUTF8(range: 0..<prefix._guts.count) { b in
        if b.count > a.count { return false }
        if _compareBytes(UnsafeBufferPointer(start: a.baseAddress, count: b.count), b) != 0 { return false }
        if b.count == a.count { return true }
        let p = a.baseAddress._unsafelyUnwrappedUnchecked
        return _nextGraphemeBoundary(p, _previousGraphemeBoundary(p, b.count, 0, a.count), a.count) == b.count
      }
    }
  }

  internal func _hasSuffixNormalized(_ suffix: String) -> Bool {
    return _guts._withNormalizedUTF8(range: 0..<_guts.count) { a in
      suffix._guts._withNormalizedUTF8(range: 0..<suffix._guts.count) { b in
        if b.count > a.count { return false }
        let k = a.count - b.count
        if _compareBytes(UnsafeBufferPointer(start: a.baseAddress._unsafelyUnwrappedUnchecked + k, count: b.count), b) != 0 {
          return false
        }
        if k == 0 { return true }
        let p = a.baseAddress._unsafelyUnwrappedUnchecked
        if _utf8IsContinuation(p[k]) { return false }
        return _nextGraphemeBoundary(p, _previousGraphemeBoundary(p, k, 0, a.count), a.count) == k
      }
    }
  }
}
