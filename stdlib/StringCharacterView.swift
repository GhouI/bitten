// String as a collection of Characters, and its mutations.

extension String: BidirectionalCollection {
  public typealias Element = Character
  public typealias SubSequence = Substring
  public typealias Indices = DefaultIndices<String>

  @inlinable @inline(__always)
  public var startIndex: Index { return _guts.startIndex }

  @inlinable @inline(__always)
  public var endIndex: Index { return _guts.endIndex }

  /// The UTF-8 offset of a valid index, rounded down to a character.
  internal func _characterOffset(_ i: Index) -> Int {
    let o = i._encodedOffset
    _precondition(o <= _guts.count, "String index is out of bounds")
    if i._isCharacterAligned { return o }
    return _guts.characterAlign(o, start: 0, end: _guts.count)
  }

  public func index(after i: Index) -> Index {
    let o = _characterOffset(i)
    _precondition(o < _guts.count, "String index is out of bounds")
    let n = _guts.nextCharacterBoundary(o, end: _guts.count)
    let next = n < _guts.count ? _guts.nextCharacterBoundary(n, end: _guts.count) - n : 0
    return Index(_characterAt: n, stride: next)
  }

  public func index(before i: Index) -> Index {
    let o = _characterOffset(i)
    _precondition(o > 0, "String index is out of bounds")
    let p = _guts.previousCharacterBoundary(o, start: 0, end: _guts.count)
    return Index(_characterAt: p, stride: o - p)
  }

  public func index(_ i: Index, offsetBy distance: Int) -> Index {
    var o = _characterOffset(i)
    let n = _guts.count
    var k = distance
    while k > 0 {
      _precondition(o < n, "String index is out of bounds")
      o = _guts.nextCharacterBoundary(o, end: n); k -= 1
    }
    while k < 0 {
      _precondition(o > 0, "String index is out of bounds")
      o = _guts.previousCharacterBoundary(o, start: 0, end: n); k += 1
    }
    return Index(_characterAt: o, stride: 0)
  }

  public func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    var o = _characterOffset(i)
    let l = limit._encodedOffset
    let n = _guts.count
    var k = distance
    while k > 0 {
      if o == l && i <= limit { return nil }
      _precondition(o < n, "String index is out of bounds")
      o = _guts.nextCharacterBoundary(o, end: n); k -= 1
      if o > l && i <= limit { return nil }
    }
    while k < 0 {
      if o == l && i >= limit { return nil }
      _precondition(o > 0, "String index is out of bounds")
      o = _guts.previousCharacterBoundary(o, start: 0, end: n); k += 1
      if o < l && i >= limit { return nil }
    }
    return Index(_characterAt: o, stride: 0)
  }

  public func distance(from start: Index, to end: Index) -> Int {
    return _guts.characterDistance(_characterOffset(start), _characterOffset(end), start: 0, end: _guts.count)
  }

  public subscript(i: Index) -> Character {
    let o = _characterOffset(i)
    _precondition(o < _guts.count, "String index is out of bounds")
    let e = _guts.nextCharacterBoundary(o, end: _guts.count)
    return Character(unchecked: _guts.substring(o, e))
  }

  public subscript(r: Range<Index>) -> Substring {
    let lo = r.lowerBound._encodedOffset, hi = r.upperBound._encodedOffset
    _precondition(hi <= _guts.count, "String index range is out of bounds")
    return Substring(_unchecked: Slice(base: self, bounds: r))
  }

  public var count: Int {
    return _guts.characterDistance(0, _guts.count, start: 0, end: _guts.count)
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

    public mutating func next() -> Character? {
      if _position >= _end { return nil }
      let e = _guts.nextCharacterBoundary(_position, end: _end)
      let c = Character(unchecked: _guts.substring(_position, e))
      _position = e
      return c
    }

    public typealias Element = Character
  }
}

extension _StringGuts {
  /// A new string of the bytes `start..<end` (on scalar boundaries).
  internal func substring(_ start: Int, _ end: Int) -> String {
    if start == 0 && end == count { return String(self) }
    let ascii = isASCII
    return withFastUTF8(range: start..<end) { String._uncheckedFromUTF8($0, isASCII: ascii || _allASCII($0)) }
  }

  /// The number of characters between two character boundaries.
  internal func characterDistance(_ from: Int, _ to: Int, start: Int, end: Int) -> Int {
    if from == to { return 0 }
    let (a, b) = from < to ? (from, to) : (to, from)
    var n = 0
    withFastUTF8 { buf in
      let p = buf.baseAddress._unsafelyUnwrappedUnchecked
      var i = a
      while i < b { i = _nextGraphemeBoundary(p, i, end); n += 1 }
    }
    return from < to ? n : -n
  }
}

// ---- mutation ----------------------------------------------------------------------

extension String: RangeReplaceableCollection {
  public init(repeating repeatedValue: Character, count: Int) {
    self.init(repeating: repeatedValue._str, count: count)
  }

  public init<S: Sequence>(_ characters: S) where S.Element == Character {
    self.init()
    for c in characters { append(c) }
  }

  public init<T: LosslessStringConvertible & Sequence>(_ other: T) where T.Element == Character {
    self = other.description
  }

  public mutating func append(_ c: Character) {
    append(c._str)
  }

  public mutating func append<S: Sequence>(contentsOf newElements: S) where S.Element == Character {
    for c in newElements { append(c._str) }
  }

  public mutating func replaceSubrange<C: Collection>(_ subrange: Range<Index>, with newElements: C)
    where C.Element == Character {
    var replacement = String()
    for c in newElements { replacement.append(c._str) }
    let lo = _characterOffset(subrange.lowerBound), hi = _characterOffset(subrange.upperBound)
    _precondition(lo <= hi && hi <= _guts.count, "String index range is out of bounds")
    _replaceUTF8(lo..<hi, with: replacement)
  }

  internal mutating func _replaceUTF8(_ range: Range<Int>, with replacement: String) {
    let ascii = replacement._guts.isASCII
    replacement._guts.withFastUTF8 { _guts.replace(utf8Range: range, with: $0, isASCII: ascii) }
  }

  public mutating func insert(_ newElement: Character, at i: Index) {
    let o = _characterOffset(i)
    _replaceUTF8(o..<o, with: newElement._str)
  }

  public mutating func insert<S: Collection>(contentsOf newElements: S, at i: Index) where S.Element == Character {
    replaceSubrange(i..<i, with: newElements)
  }

  @discardableResult
  public mutating func remove(at i: Index) -> Character {
    let c = self[i]
    let o = _characterOffset(i)
    _replaceUTF8(o..<(o + c._str._guts.count), with: "")
    return c
  }

  public mutating func removeSubrange(_ bounds: Range<Index>) {
    let lo = _characterOffset(bounds.lowerBound), hi = _characterOffset(bounds.upperBound)
    _precondition(lo <= hi && hi <= _guts.count, "String index range is out of bounds")
    _replaceUTF8(lo..<hi, with: "")
  }

  public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
    self = ""
  }
}
