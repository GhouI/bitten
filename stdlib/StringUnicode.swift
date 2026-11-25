// Unicode-aware parts of String that need character data: canonical
// equivalence, case mapping and character boundaries.
//
// First version: canonical equivalence is approximated by comparing the
// UTF-8 bytes as they are (correct for text already in NFC, which is nearly
// all text); case mapping covers ASCII and Latin-1. Tables generated from
// the Unicode Character Database replace these.

internal func _stringCompareNormalized(_ lhs: _StringGuts, _ lhsRange: Range<Int>,
                                       _ rhs: _StringGuts, _ rhsRange: Range<Int>) -> Int {
  return lhs.withFastUTF8(range: lhsRange) { a in
    rhs.withFastUTF8(range: rhsRange) { b in _compareBytes(a, b) }
  }
}

extension _StringGuts {
  internal func _withNormalizedUTF8<R>(range: Range<Int>, _ body: (UnsafeBufferPointer<UInt8>) -> R) -> R {
    return withFastUTF8(range: range, body)
  }
}

extension String {
  internal func _isCharacterBoundary(utf8Offset i: Int) -> Bool {
    if i == 0 || i == _guts.count { return true }
    // Inside a scalar is never a boundary.
    return !_utf8IsContinuation(_guts.utf8Byte(at: i))
  }

  internal func _hasPrefixNormalized(_ prefix: String) -> Bool {
    let n = prefix._guts.count
    return _guts.withFastUTF8(range: 0..<n) { a in
      prefix._guts.withFastUTF8 { b in _compareBytes(a, b) == 0 }
    } && _isCharacterBoundary(utf8Offset: n)
  }

  internal func _hasSuffixNormalized(_ suffix: String) -> Bool {
    let n = suffix._guts.count, m = _guts.count
    return _guts.withFastUTF8(range: (m - n)..<m) { a in
      suffix._guts.withFastUTF8 { b in _compareBytes(a, b) == 0 }
    } && _isCharacterBoundary(utf8Offset: m - n)
  }
}

internal func _appendCaseMapped(_ s: UInt32, upper: Bool, to result: inout String) {
  var m = s
  if upper {
    if s >= 0x61 && s <= 0x7A { m = s - 0x20 }
    else if s == 0xB5 { m = 0x39C }
    else if s == 0xDF { result._appendScalar(0x53); m = 0x53 }
    else if s >= 0xE0 && s <= 0xFE && s != 0xF7 { m = s - 0x20 }
    else if s == 0xFF { m = 0x178 }
  } else {
    if s >= 0x41 && s <= 0x5A { m = s + 0x20 }
    else if s >= 0xC0 && s <= 0xDE && s != 0xD7 { m = s + 0x20 }
  }
  result._appendScalar(m)
}
