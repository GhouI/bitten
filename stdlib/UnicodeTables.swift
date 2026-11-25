// Character data from stdlib/UnicodeData.swift (generated from the Unicode
// Character Database by tools/gen-unicode.py), decoded into lookup tables
// on first use, and the algorithms built on it: grapheme cluster
// boundaries (UAX #29, extended clusters, including GB9c and GB11), the
// canonical composition (NFC, UAX #15) and full case mappings.

internal struct _PackedReader {
  internal var p: UnsafePointer<UInt8>

  internal init(_ s: StaticString) { p = s.utf8Start }

  internal mutating func next() -> Int {
    var v = 0
    while true {
      let b = Int(p.pointee)
      p += 1
      if b == 0x0A { continue }
      let d = b - 0x30
      v = (v &<< 5) | (d & 31)
      if d & 32 == 0 { return v }
    }
  }
}

/// A property as runs: the value of `c` is the value of the last run
/// starting at or before it.
internal struct _RunTable {
  internal let starts: UnsafeMutablePointer<UInt32>
  internal let values: UnsafeMutablePointer<UInt8>
  internal let count: Int

  internal init(_ s: StaticString) {
    var r = _PackedReader(s)
    count = r.next()
    starts = UnsafeMutablePointer<UInt32>.allocate(capacity: count)
    values = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
    var start = 0
    var i = 0
    while i < count {
      start += r.next()
      starts[i] = UInt32(truncatingIfNeeded: start)
      values[i] = UInt8(truncatingIfNeeded: r.next())
      i += 1
    }
  }

  internal func lookup(_ c: UInt32) -> UInt8 {
    var lo = 0, hi = count  // invariant: starts[lo] <= c < starts[hi]
    while hi - lo > 1 {
      let mid = (lo + hi) &>> 1
      if starts[mid] <= c { lo = mid } else { hi = mid }
    }
    return values[lo]
  }
}

/// Scalar to a short list of scalars.
internal struct _MapTable {
  internal let keys: UnsafeMutablePointer<UInt32>
  internal let offsets: UnsafeMutablePointer<Int32>
  internal let pool: UnsafeMutablePointer<UInt32>
  internal let count: Int

  internal init(_ s: StaticString) {
    var r = _PackedReader(s)
    count = r.next()
    keys = UnsafeMutablePointer<UInt32>.allocate(capacity: count)
    offsets = UnsafeMutablePointer<Int32>.allocate(capacity: count + 1)
    // Two passes would need the reader twice; the pool is at most four
    // scalars per entry.
    pool = UnsafeMutablePointer<UInt32>.allocate(capacity: count * 4 + 1)
    var key = 0, used = 0, i = 0
    while i < count {
      key += r.next()
      keys[i] = UInt32(truncatingIfNeeded: key)
      offsets[i] = Int32(truncatingIfNeeded: used)
      let n = r.next()
      var k = 0
      while k < n { pool[used] = UInt32(truncatingIfNeeded: r.next()); used += 1; k += 1 }
      i += 1
    }
    offsets[count] = Int32(truncatingIfNeeded: used)
  }

  internal func lookup(_ c: UInt32) -> (start: UnsafePointer<UInt32>, count: Int)? {
    var lo = 0, hi = count
    while lo < hi {
      let mid = (lo + hi) &>> 1
      let k = keys[mid]
      if k == c {
        let a = Int(offsets[mid]), b = Int(offsets[mid + 1])
        return (UnsafePointer(pool + a), b - a)
      }
      if k < c { lo = mid + 1 } else { hi = mid }
    }
    return nil
  }
}

/// (first, second) to composite.
internal struct _PairTable {
  internal let keys: UnsafeMutablePointer<UInt64>
  internal let values: UnsafeMutablePointer<UInt32>
  internal let count: Int

  internal init(_ s: StaticString) {
    var r = _PackedReader(s)
    count = r.next()
    keys = UnsafeMutablePointer<UInt64>.allocate(capacity: count)
    values = UnsafeMutablePointer<UInt32>.allocate(capacity: count)
    var first = 0, i = 0
    while i < count {
      first += r.next()
      let second = r.next()
      keys[i] = (UInt64(truncatingIfNeeded: first) &<< 21) | UInt64(truncatingIfNeeded: second)
      values[i] = UInt32(truncatingIfNeeded: r.next())
      i += 1
    }
  }

  internal func lookup(_ a: UInt32, _ b: UInt32) -> UInt32? {
    let key = (UInt64(a) &<< 21) | UInt64(b)
    var lo = 0, hi = count
    while lo < hi {
      let mid = (lo + hi) &>> 1
      let k = keys[mid]
      if k == key { return values[mid] }
      if k < key { lo = mid + 1 } else { hi = mid }
    }
    return nil
  }
}

internal final class _UnicodeTables {
  internal let grapheme = _RunTable(_ucdGrapheme)
  internal let combiningClass = _RunTable(_ucdCombiningClass)
  internal let decomposition = _MapTable(_ucdDecomposition)
  internal let composition = _PairTable(_ucdComposition)
  internal let lowercase = _MapTable(_ucdLowercase)
  internal let uppercase = _MapTable(_ucdUppercase)
  internal let titlecase = _MapTable(_ucdTitlecase)
  internal init() {}
}

internal let _unicodeTables = _UnicodeTables()

// ---- grapheme clusters ------------------------------------------------------------

internal enum _GraphemeBreak {
  static let other: UInt8 = 0, cr: UInt8 = 1, lf: UInt8 = 2, control: UInt8 = 3,
             extend: UInt8 = 4, zwj: UInt8 = 5, regionalIndicator: UInt8 = 6,
             prepend: UInt8 = 7, spacingMark: UInt8 = 8, l: UInt8 = 9, v: UInt8 = 10,
             t: UInt8 = 11, lv: UInt8 = 12, lvt: UInt8 = 13
  static let pictographic: UInt8 = 16
  static let incbLinker: UInt8 = 1, incbConsonant: UInt8 = 2, incbExtend: UInt8 = 3
}

/// The packed grapheme properties of a scalar (see UnicodeData.swift).
@inline(__always)
internal func _graphemeProperties(_ c: UInt32) -> UInt8 {
  if c < 0x7F {
    if c >= 0x20 { return 0 }
    return c == 0x0D ? _GraphemeBreak.cr : c == 0x0A ? _GraphemeBreak.lf : _GraphemeBreak.control
  }
  return _unicodeTables.grapheme.lookup(c)
}

/// Incremental state of the rules that look further back than one scalar.
internal struct _GraphemeState {
  internal var prev: UInt8          // properties of the previous scalar
  internal var pictState = 0        // GB11: 1 after ExtPict Extend*, 2 after that and ZWJ
  internal var incbState = 0        // GB9c: 1 after Consonant [Extend|Linker]*, 2 once a Linker was seen
  internal var riCount = 0          // GB12/13: regional indicators in a row

  internal init(first: UInt8) {
    prev = first
    note(first)
  }

  internal mutating func note(_ p: UInt8) {
    let gcb = p & 15, incb = (p &>> 5) & 3
    if p & _GraphemeBreak.pictographic != 0 { pictState = 1 }
    else if pictState == 1 && gcb == _GraphemeBreak.extend { pictState = 1 }
    else if pictState == 1 && gcb == _GraphemeBreak.zwj { pictState = 2 }
    else { pictState = 0 }
    if incb == _GraphemeBreak.incbConsonant { incbState = 1 }
    else if incbState != 0 && incb == _GraphemeBreak.incbLinker { incbState = 2 }
    else if incbState != 0 && incb == _GraphemeBreak.incbExtend { }
    else { incbState = 0 }
    riCount = gcb == _GraphemeBreak.regionalIndicator ? riCount + 1 : 0
    prev = p
  }

  /// Whether there is a boundary between the previous scalar and one with
  /// properties `p`.
  internal func breaks(before p: UInt8) -> Bool {
    let a = prev & 15, b = p & 15
    typealias G = _GraphemeBreak
    if a == G.cr && b == G.lf { return false }                                    // GB3
    if a == G.cr || a == G.lf || a == G.control { return true }                   // GB4
    if b == G.cr || b == G.lf || b == G.control { return true }                   // GB5
    if a == G.l && (b == G.l || b == G.v || b == G.lv || b == G.lvt) { return false }  // GB6
    if (a == G.lv || a == G.v) && (b == G.v || b == G.t) { return false }         // GB7
    if (a == G.lvt || a == G.t) && b == G.t { return false }                      // GB8
    if b == G.extend || b == G.zwj { return false }                               // GB9
    if b == G.spacingMark { return false }                                        // GB9a
    if a == G.prepend { return false }                                            // GB9b
    if incbState == 2 && (p &>> 5) & 3 == G.incbConsonant { return false }        // GB9c
    if pictState == 2 && p & G.pictographic != 0 { return false }                 // GB11
    if a == G.regionalIndicator && b == G.regionalIndicator && riCount & 1 == 1 { return false } // GB12/13
    return true                                                                   // GB999
  }
}

/// Whether a boundary before a scalar with properties `b` that follows one
/// with properties `a` holds whatever came before `a`.
internal func _isCertainBoundary(_ a: UInt8, _ b: UInt8) -> Bool {
  typealias G = _GraphemeBreak
  let ga = a & 15, gb = b & 15
  if ga == G.cr { return gb != G.lf }
  if ga == G.lf || ga == G.control || gb == G.cr || gb == G.lf || gb == G.control { return true }
  return a == G.other && gb != G.extend && gb != G.zwj && gb != G.spacingMark
}

/// The end of the grapheme cluster starting at byte `i` of valid UTF-8.
internal func _nextGraphemeBoundary(_ p: UnsafePointer<UInt8>, _ i: Int, _ end: Int) -> Int {
  if i >= end { return end }
  // ASCII other than CR followed by ASCII: one byte.
  let b0 = p[i]
  if b0 < 0x80 && b0 != 0x0D && (i + 1 == end || p[i + 1] < 0x80) { return i + 1 }
  let (c0, l0) = _decodeUTF8Scalar(p, i)
  var state = _GraphemeState(first: _graphemeProperties(c0))
  var j = i + l0
  while j < end {
    let (c, l) = _decodeUTF8Scalar(p, j)
    let props = _graphemeProperties(c)
    if state.breaks(before: props) { break }
    state.note(props)
    j += l
  }
  return j
}

/// The start of the grapheme cluster that ends at byte `i` (which must be
/// past `start`) of valid UTF-8.
internal func _previousGraphemeBoundary(_ p: UnsafePointer<UInt8>, _ i: Int, _ start: Int, _ end: Int) -> Int {
  // ASCII other than LF preceded by ASCII: one byte.
  let last = p[i - 1]
  if last < 0x80 && last != 0x0A && (i - 1 == start || p[i - 2] < 0x80) { return i - 1 }
  // Walk back to a boundary that holds regardless of earlier text, then
  // forward.
  var k = i - _decodeUTF8ScalarBefore(p, i).length
  var anchor = start
  if k > start {
    var after = _graphemeProperties(_decodeUTF8Scalar(p, k).scalar)
    while k > start {
      let (c, l) = _decodeUTF8ScalarBefore(p, k)
      let before = _graphemeProperties(c)
      if _isCertainBoundary(before, after) { anchor = k; break }
      k -= l
      after = before
    }
  }
  var b = anchor
  while true {
    let n = _nextGraphemeBoundary(p, b, end)
    if n >= i { return b }
    b = n
  }
}

// ---- normalization -------------------------------------------------------------------

@inline(__always)
internal func _combiningClass(_ c: UInt32) -> UInt8 {
  if c < 0x300 { return 0 }
  return _unicodeTables.combiningClass.lookup(c)
}

/// A growable buffer of scalars.
internal struct _ScalarBuffer {
  internal var base: UnsafeMutablePointer<UInt32>
  internal var count = 0
  internal var capacity: Int

  internal init(capacity: Int) {
    self.capacity = capacity < 16 ? 16 : capacity
    base = UnsafeMutablePointer<UInt32>.allocate(capacity: self.capacity)
  }

  internal mutating func append(_ c: UInt32) {
    if count == capacity {
      let bigger = UnsafeMutablePointer<UInt32>.allocate(capacity: capacity * 2)
      bigger.update(from: base, count: count)
      base.deallocate()
      base = bigger
      capacity *= 2
    }
    base[count] = c
    count += 1
  }

  internal func free() { base.deallocate() }
}

internal let _hangulSBase: UInt32 = 0xAC00, _hangulLBase: UInt32 = 0x1100,
             _hangulVBase: UInt32 = 0x1161, _hangulTBase: UInt32 = 0x11A7
internal let _hangulLCount: UInt32 = 19, _hangulVCount: UInt32 = 21, _hangulTCount: UInt32 = 28
internal let _hangulNCount: UInt32 = 588, _hangulSCount: UInt32 = 11172

internal func _appendDecomposed(_ c: UInt32, to out: inout _ScalarBuffer) {
  if c < 0xC0 { out.append(c); return }
  if c >= _hangulSBase && c < _hangulSBase + _hangulSCount {
    let s = c - _hangulSBase
    out.append(_hangulLBase + s / _hangulNCount)
    out.append(_hangulVBase + (s % _hangulNCount) / _hangulTCount)
    let t = s % _hangulTCount
    if t != 0 { out.append(_hangulTBase + t) }
    return
  }
  if let (p, n) = _unicodeTables.decomposition.lookup(c) {
    var i = 0
    while i < n { out.append(p[i]); i += 1 }
  } else {
    out.append(c)
  }
}

internal func _compose(_ a: UInt32, _ b: UInt32) -> UInt32? {
  // Hangul L+V and LV+T.
  if a >= _hangulLBase && a < _hangulLBase + _hangulLCount && b >= _hangulVBase && b < _hangulVBase + _hangulVCount {
    return _hangulSBase + ((a - _hangulLBase) * _hangulVCount + (b - _hangulVBase)) * _hangulTCount
  }
  if a >= _hangulSBase && a < _hangulSBase + _hangulSCount && (a - _hangulSBase) % _hangulTCount == 0
     && b > _hangulTBase && b < _hangulTBase + _hangulTCount {
    return a + (b - _hangulTBase)
  }
  return _unicodeTables.composition.lookup(a, b)
}

/// NFC of the scalars in `buf`, in place.
internal func _normalizeNFC(_ buf: inout _ScalarBuffer) {
  let p = buf.base
  let n = buf.count
  // Canonical ordering of each run of non-starters.
  var i = 1
  while i < n {
    let cc = _combiningClass(p[i])
    if cc != 0 {
      var j = i
      while j > 0 {
        let pc = _combiningClass(p[j - 1])
        if pc <= cc { break }
        let t = p[j]; p[j] = p[j - 1]; p[j - 1] = t
        j -= 1
      }
    }
    i += 1
  }
  // Canonical composition.
  var out = 0
  var starter = -1
  var lastClass: UInt8 = 0
  i = 0
  while i < n {
    let c = p[i]
    let cc = _combiningClass(c)
    if starter >= 0 {
      let adjacent = out - 1 == starter
      let blocked = !adjacent && (lastClass == 0 || lastClass >= cc)
      if !blocked, let comp = _compose(p[starter], c) {
        p[starter] = comp
        i += 1
        continue
      }
    }
    if cc == 0 { starter = out }
    lastClass = cc
    p[out] = c
    out += 1
    i += 1
  }
  buf.count = out
}

/// Whether bytes of valid UTF-8 are already in NFC for certain (every
/// scalar below U+0300 is).
internal func _isTriviallyNFC(_ b: UnsafeBufferPointer<UInt8>) -> Bool {
  let n = b.count
  if n == 0 { return true }
  let p = b.baseAddress._unsafelyUnwrappedUnchecked
  var i = 0
  while i < n {
    let x = p[i]
    if x >= 0xCC { return false }  // lead byte of U+0300 and above
    i += 1
  }
  return true
}

/// Calls `body` with the NFC form of valid UTF-8 bytes.
internal func _withNFC<R>(_ b: UnsafeBufferPointer<UInt8>, _ body: (UnsafeBufferPointer<UInt8>) -> R) -> R {
  if _isTriviallyNFC(b) { return body(b) }
  var scalars = _ScalarBuffer(capacity: b.count)
  let p = b.baseAddress._unsafelyUnwrappedUnchecked
  var i = 0
  while i < b.count {
    let (c, l) = _decodeUTF8Scalar(p, i)
    _appendDecomposed(c, to: &scalars)
    i += l
  }
  _normalizeNFC(&scalars)
  let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: scalars.count * 4 + 1)
  var m = 0
  i = 0
  while i < scalars.count { m += _encodeUTF8(scalars.base[i], into: bytes + m); i += 1 }
  scalars.free()
  let r = body(UnsafeBufferPointer(start: UnsafePointer(bytes), count: m))
  bytes.deallocate()
  return r
}

// ---- case mapping -------------------------------------------------------------------

internal func _appendCaseMapped(_ s: UInt32, upper: Bool, to result: inout String) {
  if s < 0x80 {
    if upper && s >= 0x61 && s <= 0x7A { result._appendScalar(s - 0x20); return }
    if !upper && s >= 0x41 && s <= 0x5A { result._appendScalar(s + 0x20); return }
    result._appendScalar(s)
    return
  }
  let table = upper ? _unicodeTables.uppercase : _unicodeTables.lowercase
  if let (p, n) = table.lookup(s) {
    var i = 0
    while i < n { result._appendScalar(p[i]); i += 1 }
  } else {
    result._appendScalar(s)
  }
}
