// String's code unit and scalar views: UTF8View, UTF16View and
// UnicodeScalarView, each a @frozen wrapper of the guts as in Apple's
// layout. Their indices are String.Index. The `_foreign*` entry points are
// what inlined code calls for strings without UTF-8 in memory (bridged
// NSStrings); there are none here yet, so they trap.

// ---- UTF-8 ------------------------------------------------------------------------

extension String {
  @frozen
  public struct UTF8View: Sendable {
    @usableFromInline internal var _guts: _StringGuts

    @inlinable @inline(__always)
    internal init(_ guts: _StringGuts) { _guts = guts }
  }

  @inlinable
  public var utf8: UTF8View {
    get { return UTF8View(_guts) }
    set { self = String(newValue._guts) }
  }

  @inlinable @inline(__always)
  public init(_ utf8: UTF8View) { self.init(utf8._guts) }
}

extension String.UTF8View: BidirectionalCollection {
  public typealias Index = String.Index
  public typealias Element = UInt8
  public typealias SubSequence = Substring.UTF8View
  public typealias Indices = DefaultIndices<String.UTF8View>

  @inlinable @inline(__always)
  public var startIndex: Index { return _guts.startIndex }

  @inlinable @inline(__always)
  public var endIndex: Index { return _guts.endIndex }

  @inlinable @inline(__always)
  public func index(after i: Index) -> Index {
    if _slowPath(_guts.isForeign) { return _foreignIndex(after: i) }
    return Index(_byteAt: i._encodedOffset &+ 1)
  }

  @inlinable @inline(__always)
  public func index(before i: Index) -> Index {
    if _slowPath(_guts.isForeign) { return _foreignIndex(before: i) }
    _precondition(i._encodedOffset > 0, "String index is out of bounds")
    return Index(_byteAt: i._encodedOffset &- 1)
  }

  @inlinable @inline(__always)
  public func index(_ i: Index, offsetBy n: Int) -> Index {
    if _slowPath(_guts.isForeign) { return _foreignIndex(i, offsetBy: n) }
    let o = i._encodedOffset + n
    _precondition(o >= 0 && o <= _guts.count, "String index is out of bounds")
    return Index(_byteAt: o)
  }

  @inlinable @inline(__always)
  public func index(_ i: Index, offsetBy n: Int, limitedBy limit: Index) -> Index? {
    let l = limit._encodedOffset - i._encodedOffset
    if (n > 0 && l >= 0 && l < n) || (n < 0 && l <= 0 && l > n) { return nil }
    return index(i, offsetBy: n)
  }

  @inlinable @inline(__always)
  public func distance(from i: Index, to j: Index) -> Int {
    if _slowPath(_guts.isForeign) { return _foreignDistance(from: i, to: j) }
    return j._encodedOffset &- i._encodedOffset
  }

  @inlinable @inline(__always)
  public subscript(i: Index) -> UInt8 {
    if _slowPath(_guts.isForeign) { return _foreignSubscript(position: i) }
    let o = i._encodedOffset
    _precondition(o >= 0 && o < _guts.count, "String index is out of bounds")
    return _guts.utf8Byte(at: o)
  }

  @inlinable
  public subscript(r: Range<Index>) -> Substring.UTF8View {
    return Substring.UTF8View(self, _bounds: r)
  }

  @inlinable
  public var count: Int {
    if _slowPath(_guts.isForeign) { return _foreignCount() }
    return _guts.count
  }

  @inlinable
  public var isEmpty: Bool { return _guts.isEmpty }

  @inlinable
  public func withContiguousStorageIfAvailable<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R? {
    if _guts.isForeign { return nil }
    return try _guts.withFastUTF8(body)
  }

  @inlinable
  public __consuming func makeIterator() -> Iterator { return Iterator(_guts) }

  @frozen
  public struct Iterator: IteratorProtocol, Sendable {
    @usableFromInline internal var _guts: _StringGuts
    @usableFromInline internal var _position: Int = 0
    @usableFromInline internal var _end: Int

    @inlinable
    internal init(_ guts: _StringGuts) {
      _end = guts.count
      _guts = guts
    }

    @inlinable
    public mutating func next() -> UInt8? {
      if _position == _end { return nil }
      let b = _guts.utf8Byte(at: _position)
      _position &+= 1
      return b
    }
  }
}

extension String.UTF8View {
  @usableFromInline @inline(never)
  internal func _foreignIndex(after i: Index) -> Index { _guts._foreignUTF8Unavailable() }
  @usableFromInline @inline(never)
  internal func _foreignIndex(before i: Index) -> Index { _guts._foreignUTF8Unavailable() }
  @usableFromInline @inline(never)
  internal func _foreignIndex(_ i: Index, offsetBy n: Int) -> Index { _guts._foreignUTF8Unavailable() }
  @usableFromInline @inline(never)
  internal func _foreignDistance(from i: Index, to j: Index) -> Int { _guts._foreignUTF8Unavailable() }
  @usableFromInline @inline(never)
  internal func _foreignSubscript(position i: Index) -> UInt8 { _guts._foreignUTF8Unavailable() }
  @usableFromInline @inline(never)
  internal func _foreignCount() -> Int { _guts._foreignUTF8Unavailable() }
}

extension _StringGuts {
  /// Copies the UTF-8 into `buffer`; nil when it does not fit.
  @usableFromInline
  internal func copyUTF8(into buffer: UnsafeMutableBufferPointer<UInt8>) -> Int? {
    let n = count
    if n > buffer.count { return nil }
    if n == 0 { return 0 }
    withFastUTF8 { buffer.baseAddress._unsafelyUnwrappedUnchecked.update(from: $0.baseAddress._unsafelyUnwrappedUnchecked, count: n) }
    return n
  }

  @usableFromInline @inline(never)
  internal func _foreignCopyUTF8(into buffer: UnsafeMutableBufferPointer<UInt8>) -> Int? {
    _foreignUTF8Unavailable()
  }

  @usableFromInline @inline(never)
  internal func foreignErrorCorrectedScalar(startingAt i: String.Index) -> (Unicode.Scalar, scalarLength: Int) {
    _foreignUTF8Unavailable()
  }

  @usableFromInline @inline(never)
  internal func foreignScalarAlign(_ i: String.Index) -> String.Index {
    _foreignUTF8Unavailable()
  }
}

// ---- Unicode scalars -------------------------------------------------------------------

extension String {
  @frozen
  public struct UnicodeScalarView: Sendable {
    @usableFromInline internal var _guts: _StringGuts

    @inlinable @inline(__always)
    internal init(_ guts: _StringGuts) { _guts = guts }
  }

  @inlinable
  public var unicodeScalars: UnicodeScalarView {
    get { return UnicodeScalarView(_guts) }
    set { self = String(newValue._guts) }
  }

  @inlinable @inline(__always)
  public init(_ unicodeScalars: UnicodeScalarView) { self.init(unicodeScalars._guts) }
}

extension String.UnicodeScalarView: BidirectionalCollection {
  public typealias Index = String.Index
  public typealias Element = Unicode.Scalar
  public typealias SubSequence = Substring.UnicodeScalarView
  public typealias Indices = DefaultIndices<String.UnicodeScalarView>

  @inlinable @inline(__always)
  public var startIndex: Index { return _guts.startIndex }

  @inlinable @inline(__always)
  public var endIndex: Index { return _guts.endIndex }

  internal func _offset(_ i: Index) -> Int {
    let o = i._encodedOffset
    _precondition(o <= _guts.count, "String index is out of bounds")
    return i._isScalarAligned ? o : _guts.scalarAlign(o)
  }

  public func index(after i: Index) -> Index {
    if _slowPath(_guts.isForeign) { return _foreignIndex(after: i) }
    let o = _offset(i)
    _precondition(o < _guts.count, "String index is out of bounds")
    return Index(_scalarAt: o + _guts.fastUTF8ScalarLength(startingAt: o))
  }

  public func index(before i: Index) -> Index {
    if _slowPath(_guts.isForeign) { return _foreignIndex(before: i) }
    let o = _offset(i)
    _precondition(o > 0, "String index is out of bounds")
    return Index(_scalarAt: o - _guts.fastUTF8ScalarLength(endingAt: o))
  }

  public subscript(position: Index) -> Unicode.Scalar {
    let o = _offset(position)
    _precondition(o < _guts.count, "String index is out of bounds")
    return Unicode.Scalar(_value: _guts.scalar(at: o).scalar)
  }

  public subscript(r: Range<Index>) -> Substring.UnicodeScalarView {
    return Substring.UnicodeScalarView(self, _bounds: r)
  }

  @inlinable
  public __consuming func makeIterator() -> Iterator { return Iterator(_guts) }

  @frozen
  public struct Iterator: IteratorProtocol, Sendable {
    @usableFromInline internal var _guts: _StringGuts
    @usableFromInline internal var _position: Int = 0
    @usableFromInline internal var _end: Int

    @inlinable
    internal init(_ guts: _StringGuts) {
      _end = guts.count
      _guts = guts
    }

    public mutating func next() -> Unicode.Scalar? {
      if _position >= _end { return nil }
      let (s, l) = _guts.scalar(at: _position)
      _position += l
      return Unicode.Scalar(_value: s)
    }
  }
}

extension String.UnicodeScalarView: RangeReplaceableCollection {
  @inlinable
  public init() { self.init(_StringGuts()) }

  public mutating func append(_ c: Unicode.Scalar) {
    var s = String(_guts)
    _guts = _StringGuts()
    s._appendScalar(c.value)
    _guts = s._guts
  }

  public mutating func append<S: Sequence>(contentsOf newElements: S) where S.Element == Unicode.Scalar {
    var s = String(_guts)
    _guts = _StringGuts()
    for c in newElements { s._appendScalar(c.value) }
    _guts = s._guts
  }

  public mutating func replaceSubrange<C: Collection>(_ subrange: Range<Index>, with newElements: C)
    where C.Element == Unicode.Scalar {
    var replacement = String()
    for c in newElements { replacement._appendScalar(c.value) }
    let lo = _offset(subrange.lowerBound), hi = _offset(subrange.upperBound)
    var s = String(_guts)
    _guts = _StringGuts()
    s._replaceUTF8(lo..<hi, with: replacement)
    _guts = s._guts
  }
}

extension String.UnicodeScalarView {
  @usableFromInline @inline(never)
  internal func _foreignIndex(after i: Index) -> Index { _guts._foreignUTF8Unavailable() }
  @usableFromInline @inline(never)
  internal func _foreignIndex(before i: Index) -> Index { _guts._foreignUTF8Unavailable() }
}

// ---- UTF-16 ---------------------------------------------------------------------------

extension String {
  @frozen
  public struct UTF16View: Sendable {
    @usableFromInline internal var _guts: _StringGuts

    @inlinable @inline(__always)
    internal init(_ guts: _StringGuts) { _guts = guts }
  }

  @inlinable
  public var utf16: UTF16View {
    get { return UTF16View(_guts) }
    set { self = String(newValue._guts) }
  }

  @inlinable @inline(__always)
  public init(_ utf16: UTF16View) { self.init(utf16._guts) }
}

extension String.UTF16View: BidirectionalCollection {
  public typealias Index = String.Index
  public typealias Element = UInt16
  public typealias SubSequence = Substring.UTF16View
  public typealias Indices = DefaultIndices<String.UTF16View>

  @inlinable @inline(__always)
  public var startIndex: Index { return _guts.startIndex }

  @inlinable @inline(__always)
  public var endIndex: Index { return _guts.endIndex }

  internal func _offset(_ i: Index) -> Int {
    let o = i._encodedOffset
    _precondition(o <= _guts.count, "String index is out of bounds")
    return i._isScalarAligned ? o : _guts.scalarAlign(o)
  }

  public func index(after i: Index) -> Index {
    let o = _offset(i)
    _precondition(o < _guts.count, "String index is out of bounds")
    let l = _guts.fastUTF8ScalarLength(startingAt: o)
    if l == 4 && i.transcodedOffset == 0 { return Index(_trailingSurrogateAt: o) }
    return Index(_scalarAt: o + l)
  }

  public func index(before i: Index) -> Index {
    let o = _offset(i)
    if i.transcodedOffset == 1 { return Index(_scalarAt: o) }
    _precondition(o > 0, "String index is out of bounds")
    let l = _guts.fastUTF8ScalarLength(endingAt: o)
    if l == 4 { return Index(_trailingSurrogateAt: o - 4) }
    return Index(_scalarAt: o - l)
  }

  @_effects(releasenone)
  public func index(_ i: Index, offsetBy n: Int) -> Index {
    let target = _nativeGetOffset(for: i) + n
    _precondition(target >= 0 && target <= count, "String index is out of bounds")
    return _nativeGetIndex(for: target)
  }

  @_effects(releasenone)
  public func index(_ i: Index, offsetBy n: Int, limitedBy limit: Index) -> Index? {
    let a = _nativeGetOffset(for: i), l = _nativeGetOffset(for: limit)
    let d = l - a
    if (n > 0 && d >= 0 && d < n) || (n < 0 && d <= 0 && d > n) { return nil }
    return index(i, offsetBy: n)
  }

  @_effects(releasenone)
  public func distance(from start: Index, to end: Index) -> Int {
    return _nativeGetOffset(for: end) - _nativeGetOffset(for: start)
  }

  public var count: Int {
    if _slowPath(_guts.isForeign) { return _foreignCount() }
    return _guts.utf16Count(0, _guts.count)
  }

  public subscript(i: Index) -> UInt16 {
    let o = _offset(i)
    _precondition(o < _guts.count, "String index is out of bounds")
    let s = _guts.scalar(at: o).scalar
    if s < 0x10000 { return UInt16(truncatingIfNeeded: s) }
    let v = s - 0x10000
    if i.transcodedOffset == 0 { return UInt16(truncatingIfNeeded: 0xD800 + (v &>> 10)) }
    return UInt16(truncatingIfNeeded: 0xDC00 + (v & 0x3FF))
  }

  public subscript(r: Range<Index>) -> Substring.UTF16View {
    return Substring.UTF16View(self, _bounds: r)
  }

  @usableFromInline
  internal func _nativeGetOffset(for i: Index) -> Int {
    return _guts.utf16Count(0, _offset(i)) + i.transcodedOffset
  }

  @usableFromInline
  internal func _nativeGetIndex(for offset: Int) -> Index {
    return _guts.index(utf16Offset: offset)
  }

  @usableFromInline @inline(never)
  internal func _foreignCount() -> Int { _guts._foreignUTF8Unavailable() }

  @inlinable
  public __consuming func makeIterator() -> Iterator { return Iterator(_guts) }

  @frozen
  public struct Iterator: IteratorProtocol, Sendable {
    @usableFromInline internal var _guts: _StringGuts
    @usableFromInline internal var _position: Int = 0
    @usableFromInline internal var _end: Int
    @usableFromInline internal var _nextIsTrailingSurrogate: UInt16? = nil

    @inlinable
    internal init(_ guts: _StringGuts) {
      _end = guts.count
      _guts = guts
    }

    public mutating func next() -> UInt16? {
      if let t = _nextIsTrailingSurrogate {
        _nextIsTrailingSurrogate = nil
        return t
      }
      if _position >= _end { return nil }
      let (s, l) = _guts.scalar(at: _position)
      _position += l
      if s < 0x10000 { return UInt16(truncatingIfNeeded: s) }
      let v = s - 0x10000
      _nextIsTrailingSurrogate = UInt16(truncatingIfNeeded: 0xDC00 + (v & 0x3FF))
      return UInt16(truncatingIfNeeded: 0xD800 + (v &>> 10))
    }
  }
}

extension String.Index {
  /// This index in another view of the same string, when it is a valid
  /// position there.
  public func samePosition(in utf8: String.UTF8View) -> String.UTF8View.Index? {
    return transcodedOffset == 0 ? String.Index(_byteAt: _encodedOffset) : nil
  }

  public func samePosition(in unicodeScalars: String.UnicodeScalarView) -> String.UnicodeScalarIndex? {
    let g = unicodeScalars._guts
    if transcodedOffset != 0 || _encodedOffset > g.count || g.scalarAlign(_encodedOffset) != _encodedOffset { return nil }
    return String.Index(_scalarAt: _encodedOffset)
  }

  public func samePosition(in utf16: String.UTF16View) -> String.UTF16View.Index? {
    let g = utf16._guts
    if _encodedOffset > g.count || g.scalarAlign(_encodedOffset) != _encodedOffset { return nil }
    return transcodedOffset == 0 ? String.Index(_scalarAt: _encodedOffset) : self
  }

  public func samePosition(in characters: String) -> String.Index? {
    let g = characters._guts
    if transcodedOffset != 0 || !g.isCharacterBoundary(_encodedOffset) { return nil }
    return String.Index(_characterAt: _encodedOffset, stride: 0)
  }
}
