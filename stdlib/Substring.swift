// Substring and its views: @frozen slices of String and of String's views,
// as in Apple's layout (Slice<String> is start index, end index, base).
// Characters are counted within the substring's bounds.

@frozen
public struct Substring: Sendable {
  @usableFromInline internal var _slice: Slice<String>

  @inlinable @inline(__always)
  internal init(_unchecked slice: Slice<String>) { _slice = slice }
}

extension Substring {
  @inlinable
  public init() { self.init(_unchecked: Slice(base: "", bounds: "".startIndex..<"".endIndex)) }

  public init(_ content: String) {
    self.init(_unchecked: Slice(base: content, bounds: content.startIndex..<content.endIndex))
  }

  @_alwaysEmitIntoClient
  public var base: String { return _slice._base }

  @inlinable
  internal var _wholeGuts: _StringGuts { return _slice._base._guts }

  internal var _lo: Int { return _slice._startIndex._encodedOffset }
  internal var _hi: Int { return _slice._endIndex._encodedOffset }

  /// The substring's own string: shares storage when it is all of it.
  internal var _string: String { return _wholeGuts.substring(_lo, _hi) }
}

extension String {
  @usableFromInline
  internal static func _fromSubstring(_ substring: __shared Substring) -> String {
    return substring._string
  }

  public init(_ substring: __shared Substring) {
    self = substring._string
  }
}

extension Substring: BidirectionalCollection {
  public typealias Index = String.Index
  public typealias Element = Character
  public typealias SubSequence = Substring
  public typealias Indices = DefaultIndices<Substring>
  public typealias Iterator = IndexingIterator<Substring>

  @inlinable @inline(__always)
  public var startIndex: Index { return _slice._startIndex }

  @inlinable @inline(__always)
  public var endIndex: Index { return _slice._endIndex }

  internal func _characterOffset(_ i: Index) -> Int {
    let o = i._encodedOffset
    _precondition(o >= _lo && o <= _hi, "Substring index is out of bounds")
    if i._isCharacterAligned || o == _lo { return o }
    return _wholeGuts.characterAlign(o, start: _lo, end: _hi)
  }

  public func index(after i: Index) -> Index {
    let o = _characterOffset(i)
    _precondition(o < _hi, "Substring index is out of bounds")
    return Index(_characterAt: _wholeGuts.nextCharacterBoundary(o, end: _hi), stride: 0)
  }

  public func index(before i: Index) -> Index {
    let o = _characterOffset(i)
    _precondition(o > _lo, "Substring index is out of bounds")
    return Index(_characterAt: _wholeGuts.previousCharacterBoundary(o, start: _lo, end: _hi), stride: 0)
  }

  public func index(_ i: Index, offsetBy distance: Int) -> Index {
    var r = i
    var k = distance
    while k > 0 { r = index(after: r); k -= 1 }
    while k < 0 { r = index(before: r); k += 1 }
    return r
  }

  public func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    var r = i
    var k = distance
    while k > 0 {
      if r == limit { return nil }
      r = index(after: r); k -= 1
      if r > limit && i <= limit { return nil }
    }
    while k < 0 {
      if r == limit { return nil }
      r = index(before: r); k += 1
      if r < limit && i >= limit { return nil }
    }
    return r
  }

  public func distance(from start: Index, to end: Index) -> Int {
    return _wholeGuts.characterDistance(_characterOffset(start), _characterOffset(end), start: _lo, end: _hi)
  }

  public subscript(i: Index) -> Character {
    let o = _characterOffset(i)
    _precondition(o < _hi, "Substring index is out of bounds")
    return Character(unchecked: _wholeGuts.substring(o, _wholeGuts.nextCharacterBoundary(o, end: _hi)))
  }

  public subscript(r: Range<Index>) -> Substring {
    _precondition(r.lowerBound._encodedOffset >= _lo && r.upperBound._encodedOffset <= _hi,
                  "Substring index range is out of bounds")
    return Substring(_unchecked: Slice(base: _slice._base, bounds: r))
  }

  public var count: Int { return distance(from: startIndex, to: endIndex) }

  @inlinable
  public var isEmpty: Bool { return _slice._startIndex == _slice._endIndex }
}

extension Substring: RangeReplaceableCollection {
  public init<S: Sequence>(_ elements: S) where S.Element == Character {
    self.init(String(elements))
  }

  public mutating func replaceSubrange<C: Collection>(_ subrange: Range<Index>, with newElements: C)
    where C.Element == Character {
    var replacement = String()
    for c in newElements { replacement.append(c) }
    let lo = _characterOffset(subrange.lowerBound), hi = _characterOffset(subrange.upperBound)
    let start = _lo, end = _hi
    var base = _slice._base
    self = Substring()
    base._replaceUTF8(lo..<hi, with: replacement)
    let newEnd = end - (hi - lo) + replacement._guts.count
    self = Substring(_unchecked: Slice(base: base, bounds: String.Index(_characterAt: start, stride: 0)..<String.Index(_characterAt: newEnd, stride: 0)))
  }

  public mutating func replaceSubrange(_ subrange: Range<Index>, with newElements: Substring) {
    replaceSubrange(subrange, with: String(newElements))
  }

  @inlinable
  public mutating func append<S: Sequence>(contentsOf elements: S) where S.Element == Character {
    var s = String()
    for c in elements { s.append(c) }
    replaceSubrange(endIndex..<endIndex, with: s)
  }
}

extension Substring: Equatable {
  public static func == (lhs: Substring, rhs: Substring) -> Bool {
    return _stringCompareInternal(lhs._wholeGuts, lhs._lo..<lhs._hi, rhs._wholeGuts, rhs._lo..<rhs._hi, expecting: .equal)
  }
}

extension Substring: Comparable {
  public static func < (lhs: Substring, rhs: Substring) -> Bool {
    return _stringCompareInternal(lhs._wholeGuts, lhs._lo..<lhs._hi, rhs._wholeGuts, rhs._lo..<rhs._hi, expecting: .less)
  }
}

extension Substring: Hashable {
  public func hash(into hasher: inout Hasher) {
    _wholeGuts._hashNormalized(into: &hasher, range: _lo..<_hi)
  }
}

extension Substring: TextOutputStream, TextOutputStreamable, CustomStringConvertible, LosslessStringConvertible {
  public mutating func write(_ other: String) {
    append(contentsOf: other)
  }

  @inlinable
  public func write<Target: TextOutputStream>(to target: inout Target) {
    target.write(String(self))
  }

  @inlinable @inline(__always)
  public var description: String { return String(self) }
}

extension Substring: _ExpressibleByBuiltinStringLiteral, ExpressibleByStringLiteral {
  @inlinable
  public init(_builtinUnicodeScalarLiteral value: Builtin.Int32) {
    self.init(String(_builtinUnicodeScalarLiteral: value))
  }
  @inlinable
  public init(_builtinExtendedGraphemeClusterLiteral start: Builtin.RawPointer,
              utf8CodeUnitCount: Builtin.Word, isASCII: Builtin.Int1) {
    self.init(String(_builtinExtendedGraphemeClusterLiteral: start, utf8CodeUnitCount: utf8CodeUnitCount, isASCII: isASCII))
  }
  @inlinable
  public init(_builtinStringLiteral start: Builtin.RawPointer,
              utf8CodeUnitCount: Builtin.Word, isASCII: Builtin.Int1) {
    self.init(String(_builtinStringLiteral: start, utf8CodeUnitCount: utf8CodeUnitCount, isASCII: isASCII))
  }
  @inlinable
  public init(stringLiteral value: String) { self.init(value) }
  @inlinable
  public init(extendedGraphemeClusterLiteral value: String) { self.init(value) }
  @inlinable
  public init(unicodeScalarLiteral value: String) { self.init(value) }

  public typealias StringLiteralType = String
  public typealias ExtendedGraphemeClusterLiteralType = String
  public typealias UnicodeScalarLiteralType = String
}

extension Substring {
  public func lowercased() -> String { return String(self).lowercased() }
  public func uppercased() -> String { return String(self).uppercased() }

  public func hasPrefix(_ prefix: String) -> Bool { return String(self).hasPrefix(prefix) }
  public func hasSuffix(_ suffix: String) -> Bool { return String(self).hasSuffix(suffix) }

  @inlinable
  public func withCString<Result>(_ body: (UnsafePointer<CChar>) throws -> Result) rethrows -> Result {
    return try String(self).withCString(body)
  }

  public init(cString nullTerminatedUTF8: UnsafePointer<CChar>) {
    self.init(String(cString: nullTerminatedUTF8))
  }
}

// ---- views --------------------------------------------------------------------------

extension Substring {
  @frozen
  public struct UTF8View: Sendable {
    @usableFromInline internal var _slice: Slice<String.UTF8View>

    @inlinable
    internal init(_ base: String.UTF8View, _bounds: Range<String.Index>) {
      _slice = Slice(base: base, bounds: _bounds)
    }
  }

  @inlinable
  public var utf8: UTF8View {
    return UTF8View(_slice._base.utf8, _bounds: _slice._startIndex..<_slice._endIndex)
  }

  public init(_ content: UTF8View) {
    self.init(_unchecked: Slice(base: String(content._slice._base._guts),
                                bounds: content._slice._startIndex..<content._slice._endIndex))
  }

  @frozen
  public struct UTF16View: Sendable {
    @usableFromInline internal var _slice: Slice<String.UTF16View>

    @inlinable
    internal init(_ base: String.UTF16View, _bounds: Range<String.Index>) {
      _slice = Slice(base: base, bounds: _bounds)
    }
  }

  @inlinable
  public var utf16: UTF16View {
    return UTF16View(_slice._base.utf16, _bounds: _slice._startIndex..<_slice._endIndex)
  }

  public init(_ content: UTF16View) {
    self.init(_unchecked: Slice(base: String(content._slice._base._guts),
                                bounds: content._slice._startIndex..<content._slice._endIndex))
  }

  @frozen
  public struct UnicodeScalarView: Sendable {
    @usableFromInline internal var _slice: Slice<String.UnicodeScalarView>

    @inlinable
    internal init(_ base: String.UnicodeScalarView, _bounds: Range<String.Index>) {
      _slice = Slice(base: base, bounds: _bounds)
    }
  }

  @inlinable
  public var unicodeScalars: UnicodeScalarView {
    return UnicodeScalarView(_slice._base.unicodeScalars, _bounds: _slice._startIndex..<_slice._endIndex)
  }

  public init(_ content: UnicodeScalarView) {
    self.init(_unchecked: Slice(base: String(content._slice._base._guts),
                                bounds: content._slice._startIndex..<content._slice._endIndex))
  }
}

extension Substring.UTF8View: BidirectionalCollection {
  public typealias Index = String.Index
  public typealias Element = UInt8
  public typealias SubSequence = Substring.UTF8View
  public typealias Indices = DefaultIndices<Substring.UTF8View>
  public typealias Iterator = IndexingIterator<Substring.UTF8View>

  @inlinable public var startIndex: Index { return _slice._startIndex }
  @inlinable public var endIndex: Index { return _slice._endIndex }
  @inlinable public subscript(index: Index) -> UInt8 { return _slice._base[index] }
  @inlinable public subscript(r: Range<Index>) -> Substring.UTF8View {
    return Substring.UTF8View(_slice._base, _bounds: r)
  }
  @inlinable public func index(after i: Index) -> Index { return _slice._base.index(after: i) }
  @inlinable public func formIndex(after i: inout Index) { i = _slice._base.index(after: i) }
  @inlinable public func index(before i: Index) -> Index { return _slice._base.index(before: i) }
  @inlinable public func formIndex(before i: inout Index) { i = _slice._base.index(before: i) }
  @inlinable public func index(_ i: Index, offsetBy n: Int) -> Index { return _slice._base.index(i, offsetBy: n) }
  @inlinable public func index(_ i: Index, offsetBy n: Int, limitedBy limit: Index) -> Index? {
    return _slice._base.index(i, offsetBy: n, limitedBy: limit)
  }
  @inlinable public func distance(from start: Index, to end: Index) -> Int {
    return _slice._base.distance(from: start, to: end)
  }
}

extension Substring.UTF16View: BidirectionalCollection {
  public typealias Index = String.Index
  public typealias Element = UInt16
  public typealias SubSequence = Substring.UTF16View
  public typealias Indices = DefaultIndices<Substring.UTF16View>
  public typealias Iterator = IndexingIterator<Substring.UTF16View>

  @inlinable public var startIndex: Index { return _slice._startIndex }
  @inlinable public var endIndex: Index { return _slice._endIndex }
  @inlinable public subscript(index: Index) -> UInt16 { return _slice._base[index] }
  @inlinable public subscript(r: Range<Index>) -> Substring.UTF16View {
    return Substring.UTF16View(_slice._base, _bounds: r)
  }
  @inlinable public func index(after i: Index) -> Index { return _slice._base.index(after: i) }
  @inlinable public func index(before i: Index) -> Index { return _slice._base.index(before: i) }
  @inlinable public func index(_ i: Index, offsetBy n: Int) -> Index { return _slice._base.index(i, offsetBy: n) }
  @inlinable public func index(_ i: Index, offsetBy n: Int, limitedBy limit: Index) -> Index? {
    return _slice._base.index(i, offsetBy: n, limitedBy: limit)
  }
  @inlinable public func distance(from start: Index, to end: Index) -> Int {
    return _slice._base.distance(from: start, to: end)
  }
}

extension Substring.UnicodeScalarView: BidirectionalCollection {
  public typealias Index = String.Index
  public typealias Element = Unicode.Scalar
  public typealias SubSequence = Substring.UnicodeScalarView
  public typealias Indices = DefaultIndices<Substring.UnicodeScalarView>
  public typealias Iterator = IndexingIterator<Substring.UnicodeScalarView>

  @inlinable public var startIndex: Index { return _slice._startIndex }
  @inlinable public var endIndex: Index { return _slice._endIndex }
  @inlinable public subscript(index: Index) -> Unicode.Scalar { return _slice._base[index] }
  public subscript(r: Range<Index>) -> Substring.UnicodeScalarView {
    return Substring.UnicodeScalarView(_slice._base, _bounds: r)
  }
  @inlinable public func index(after i: Index) -> Index { return _slice._base.index(after: i) }
  @inlinable public func index(before i: Index) -> Index { return _slice._base.index(before: i) }
  @inlinable public func distance(from start: Index, to end: Index) -> Int {
    return _slice._base.distance(from: start, to: end)
  }
}

extension Substring.UnicodeScalarView: RangeReplaceableCollection {
  public init() { self.init(String.UnicodeScalarView(), _bounds: "".startIndex..<"".endIndex) }

  public mutating func replaceSubrange<C: Collection>(_ subrange: Range<Index>, with replacement: C)
    where C.Element == Unicode.Scalar {
    let lo = _slice._startIndex._encodedOffset, hi = _slice._endIndex._encodedOffset
    let a = subrange.lowerBound._encodedOffset, b = subrange.upperBound._encodedOffset
    _precondition(lo <= a && a <= b && b <= hi, "Substring index range is out of bounds")
    var base = _slice._base
    self = Substring.UnicodeScalarView()
    let before = base._guts.count
    base.replaceSubrange(subrange, with: replacement)
    let newHi = hi + base._guts.count - before
    self = Substring.UnicodeScalarView(base, _bounds: String.Index(_scalarAt: lo)..<String.Index(_scalarAt: newHi))
  }
}

extension Slice: @unchecked Sendable where Base: Sendable, Base.Index: Sendable {}
