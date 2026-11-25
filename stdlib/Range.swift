// Ranges and the small collection types the protocols default to.

public protocol RangeExpression<Bound> {
  associatedtype Bound: Comparable
  func relative<C: Collection>(to collection: C) -> Range<Bound> where C.Index == Bound
  func contains(_ element: Bound) -> Bool
}
extension RangeExpression {
  @inlinable public static func ~= (pattern: Self, value: Bound) -> Bool { return pattern.contains(value) }
}

// ---- Range ------------------------------------------------------------------------

@frozen public struct Range<Bound: Comparable> {
  public let lowerBound: Bound
  public let upperBound: Bound
  @_alwaysEmitIntoClient @inline(__always)
  internal init(_uncheckedBounds bounds: (lower: Bound, upper: Bound)) {
    self.lowerBound = bounds.lower
    self.upperBound = bounds.upper
  }
  @inlinable public init(uncheckedBounds bounds: (lower: Bound, upper: Bound)) {
    self.init(_uncheckedBounds: bounds)
  }
  @inlinable public func contains(_ element: Bound) -> Bool {
    return lowerBound <= element && element < upperBound
  }
  @inlinable public var isEmpty: Bool { return lowerBound == upperBound }
}

extension Range: RangeExpression {
  @inlinable public func relative<C: Collection>(to collection: C) -> Range<Bound> where C.Index == Bound {
    return self
  }
}

extension Range: Equatable {
  @inlinable public static func == (lhs: Range<Bound>, rhs: Range<Bound>) -> Bool {
    return lhs.lowerBound == rhs.lowerBound && lhs.upperBound == rhs.upperBound
  }
}

extension Range: Sequence where Bound: Strideable, Bound.Stride: SignedInteger {
  public typealias Element = Bound
  public typealias Iterator = IndexingIterator<Range<Bound>>
}

extension Range: Collection, BidirectionalCollection, RandomAccessCollection
where Bound: Strideable, Bound.Stride: SignedInteger {
  public typealias Index = Bound
  public typealias Indices = Range<Bound>
  public typealias SubSequence = Range<Bound>
  @inlinable public var startIndex: Index { return lowerBound }
  @inlinable public var endIndex: Index { return upperBound }
  @inlinable public func index(after i: Index) -> Index { return i.advanced(by: 1) }
  @inlinable public func index(before i: Index) -> Index { return i.advanced(by: -1) }
  @inlinable public func index(_ i: Index, offsetBy n: Int) -> Index {
    return i.advanced(by: Bound.Stride(truncatingIfNeeded: n))
  }
  @inlinable public func distance(from start: Index, to end: Index) -> Int {
    return Int(truncatingIfNeeded: start.distance(to: end))
  }
  @inlinable public subscript(bounds: Range<Index>) -> Range<Bound> { return bounds }
  @inlinable public var indices: Indices { return self }
  @inlinable public subscript(position: Index) -> Element { return position }
  @inlinable public func _customContainsEquatableElement(_ element: Element) -> Bool? {
    return lowerBound <= element && element < upperBound
  }
  @inlinable public func _customIndexOfEquatableElement(_ element: Bound) -> Index?? {
    return lowerBound <= element && element < upperBound ? .some(element) : .some(nil)
  }
  @inlinable public func _customLastIndexOfEquatableElement(_ element: Bound) -> Index?? {
    return _customIndexOfEquatableElement(element)
  }
}

extension Range {
  @inlinable public func clamped(to limits: Range) -> Range {
    let lower = limits.lowerBound > lowerBound ? limits.lowerBound
      : limits.upperBound < lowerBound ? limits.upperBound : lowerBound
    let upper = limits.upperBound < upperBound ? limits.upperBound
      : limits.lowerBound > upperBound ? limits.lowerBound : upperBound
    return Range(_uncheckedBounds: (lower: lower, upper: upper))
  }
  @inlinable public func overlaps(_ other: Range<Bound>) -> Bool {
    let isDisjoint = other.upperBound <= lowerBound || upperBound <= other.lowerBound
      || isEmpty || other.isEmpty
    return !isDisjoint
  }
}

// ---- ClosedRange ---------------------------------------------------------------------

@frozen public struct ClosedRange<Bound: Comparable> {
  public let lowerBound: Bound
  public let upperBound: Bound
  @_alwaysEmitIntoClient @inline(__always)
  internal init(_uncheckedBounds bounds: (lower: Bound, upper: Bound)) {
    self.lowerBound = bounds.lower
    self.upperBound = bounds.upper
  }
  @inlinable public init(uncheckedBounds bounds: (lower: Bound, upper: Bound)) {
    self.init(_uncheckedBounds: bounds)
  }
  @inlinable public func contains(_ element: Bound) -> Bool {
    return lowerBound <= element && element <= upperBound
  }
  @inlinable public var isEmpty: Bool { return false }
}

extension ClosedRange: RangeExpression where Bound: Strideable, Bound.Stride: SignedInteger {
  @inlinable public func relative<C: Collection>(to collection: C) -> Range<Bound> where C.Index == Bound {
    return Range(_uncheckedBounds: (lower: lowerBound, upper: collection.index(after: upperBound)))
  }
}

extension ClosedRange: Equatable {
  @inlinable public static func == (lhs: ClosedRange<Bound>, rhs: ClosedRange<Bound>) -> Bool {
    return lhs.lowerBound == rhs.lowerBound && lhs.upperBound == rhs.upperBound
  }
}

extension ClosedRange where Bound: Strideable, Bound.Stride: SignedInteger {
  /// Iterates lower...upper without overflowing past upperBound.
  @frozen public struct Iterator: IteratorProtocol {
    @usableFromInline internal var _next: Bound
    @usableFromInline internal let _upper: Bound
    @usableFromInline internal var _done: Bool
    @inlinable internal init(_ r: ClosedRange<Bound>) {
      _next = r.lowerBound
      _upper = r.upperBound
      _done = false
    }
    @inlinable public mutating func next() -> Bound? {
      if _done { return nil }
      let v = _next
      if v == _upper { _done = true } else { _next = v.advanced(by: 1) }
      return v
    }
  }
}
extension ClosedRange: Sequence where Bound: Strideable, Bound.Stride: SignedInteger {
  public typealias Element = Bound
  @inlinable public __consuming func makeIterator() -> Iterator { return Iterator(self) }
}

// ---- partial ranges ---------------------------------------------------------------------

@frozen public struct PartialRangeUpTo<Bound: Comparable> {
  public let upperBound: Bound
  @inlinable public init(_ upperBound: Bound) { self.upperBound = upperBound }
}
extension PartialRangeUpTo: RangeExpression {
  @_transparent public func relative<C: Collection>(to collection: C) -> Range<Bound> where C.Index == Bound {
    return collection.startIndex..<self.upperBound
  }
  @_transparent public func contains(_ element: Bound) -> Bool { return element < upperBound }
}

@frozen public struct PartialRangeThrough<Bound: Comparable> {
  public let upperBound: Bound
  @inlinable public init(_ upperBound: Bound) { self.upperBound = upperBound }
}
extension PartialRangeThrough: RangeExpression {
  @_transparent public func relative<C: Collection>(to collection: C) -> Range<Bound> where C.Index == Bound {
    return collection.startIndex..<collection.index(after: self.upperBound)
  }
  @_transparent public func contains(_ element: Bound) -> Bool { return element <= upperBound }
}

@frozen public struct PartialRangeFrom<Bound: Comparable> {
  public let lowerBound: Bound
  @inlinable public init(_ lowerBound: Bound) { self.lowerBound = lowerBound }
}
extension PartialRangeFrom: RangeExpression {
  @_transparent public func relative<C: Collection>(to collection: C) -> Range<Bound> where C.Index == Bound {
    return self.lowerBound..<collection.endIndex
  }
  @inlinable public func contains(_ element: Bound) -> Bool { return lowerBound <= element }
}

public enum UnboundedRange_ {
  public static postfix func ... (_: UnboundedRange_) -> () {}
}
public typealias UnboundedRange = (UnboundedRange_) -> ()

extension Comparable {
  @_transparent public static func ..< (minimum: Self, maximum: Self) -> Range<Self> {
    _collectionPrecondition(minimum <= maximum)
    return Range(_uncheckedBounds: (lower: minimum, upper: maximum))
  }
  @_transparent public static func ... (minimum: Self, maximum: Self) -> ClosedRange<Self> {
    _collectionPrecondition(minimum <= maximum)
    return ClosedRange(_uncheckedBounds: (lower: minimum, upper: maximum))
  }
  @_transparent public static prefix func ..< (maximum: Self) -> PartialRangeUpTo<Self> {
    return PartialRangeUpTo(maximum)
  }
  @_transparent public static prefix func ... (maximum: Self) -> PartialRangeThrough<Self> {
    return PartialRangeThrough(maximum)
  }
  @_transparent public static postfix func ... (minimum: Self) -> PartialRangeFrom<Self> {
    return PartialRangeFrom(minimum)
  }
}

// ---- IndexingIterator -----------------------------------------------------------------

@frozen public struct IndexingIterator<Elements: Collection> {
  @usableFromInline internal let _elements: Elements
  @usableFromInline internal var _position: Elements.Index
  @inlinable @inline(__always) public init(_elements: Elements) {
    self._elements = _elements
    self._position = _elements.startIndex
  }
  @inlinable @inline(__always) public init(_elements: Elements, _position: Elements.Index) {
    self._elements = _elements
    self._position = _position
  }
}
extension IndexingIterator: IteratorProtocol, Sequence {
  public typealias Element = Elements.Element
  public typealias Iterator = IndexingIterator<Elements>
  @inlinable @inline(__always) public mutating func next() -> Elements.Element? {
    if _position == _elements.endIndex { return nil }
    let element = _elements[_position]
    _elements.formIndex(after: &_position)
    return element
  }
}

// ---- DefaultIndices --------------------------------------------------------------------

@frozen public struct DefaultIndices<Elements: Collection> {
  @usableFromInline internal var _elements: Elements
  @usableFromInline internal var _startIndex: Elements.Index
  @usableFromInline internal var _endIndex: Elements.Index
  @inlinable internal init(_elements: Elements, startIndex: Elements.Index, endIndex: Elements.Index) {
    self._elements = _elements
    self._startIndex = startIndex
    self._endIndex = endIndex
  }
}
extension DefaultIndices: Collection {
  public typealias Index = Elements.Index
  public typealias Element = Elements.Index
  public typealias Indices = DefaultIndices<Elements>
  public typealias SubSequence = DefaultIndices<Elements>
  public typealias Iterator = IndexingIterator<DefaultIndices<Elements>>
  @inlinable public var startIndex: Index { return _startIndex }
  @inlinable public var endIndex: Index { return _endIndex }
  @inlinable public subscript(i: Index) -> Elements.Index { return i }
  @inlinable public subscript(bounds: Range<Index>) -> DefaultIndices<Elements> {
    return DefaultIndices(_elements: _elements, startIndex: bounds.lowerBound, endIndex: bounds.upperBound)
  }
  @inlinable public func index(after i: Index) -> Index { return _elements.index(after: i) }
  @inlinable public func formIndex(after i: inout Index) { _elements.formIndex(after: &i) }
  @inlinable public var indices: Indices { return self }
}
extension DefaultIndices: BidirectionalCollection where Elements: BidirectionalCollection {
  @inlinable public func index(before i: Index) -> Index { return _elements.index(before: i) }
  @inlinable public func formIndex(before i: inout Index) { _elements.formIndex(before: &i) }
}
extension DefaultIndices: RandomAccessCollection where Elements: RandomAccessCollection {}

// ---- Slice ---------------------------------------------------------------------------------

@frozen public struct Slice<Base: Collection> {
  public var _startIndex: Base.Index
  public var _endIndex: Base.Index
  @usableFromInline internal var _base: Base
  @inlinable public init(base: Base, bounds: Range<Base.Index>) {
    self._base = base
    self._startIndex = bounds.lowerBound
    self._endIndex = bounds.upperBound
  }
  @inlinable public var base: Base { return _base }
}
extension Slice: Collection {
  public typealias Index = Base.Index
  public typealias Indices = Base.Indices
  public typealias Element = Base.Element
  public typealias SubSequence = Slice<Base>
  public typealias Iterator = IndexingIterator<Slice<Base>>
  @inlinable public var startIndex: Index { return _startIndex }
  @inlinable public var endIndex: Index { return _endIndex }
  @inlinable public subscript(index: Index) -> Base.Element {
    _base._failEarlyRangeCheck(index, bounds: _startIndex..<_endIndex)
    return _base[index]
  }
  @inlinable public subscript(bounds: Range<Index>) -> Slice<Base> {
    _base._failEarlyRangeCheck(bounds, bounds: _startIndex..<_endIndex)
    return Slice(base: _base, bounds: bounds)
  }
  public var indices: Indices { return _base.indices[_startIndex..<_endIndex] }
  @inlinable public func index(after i: Index) -> Index { return _base.index(after: i) }
  @inlinable public func formIndex(after i: inout Index) { _base.formIndex(after: &i) }
  @inlinable public func index(_ i: Index, offsetBy n: Int) -> Index { return _base.index(i, offsetBy: n) }
  @inlinable public func index(_ i: Index, offsetBy n: Int, limitedBy limit: Index) -> Index? {
    return _base.index(i, offsetBy: n, limitedBy: limit)
  }
  @inlinable public func distance(from start: Index, to end: Index) -> Int {
    return _base.distance(from: start, to: end)
  }
  @inlinable public func _failEarlyRangeCheck(_ index: Index, bounds: Range<Index>) {
    _base._failEarlyRangeCheck(index, bounds: bounds)
  }
  @inlinable public func _failEarlyRangeCheck(_ range: Range<Index>, bounds: Range<Index>) {
    _base._failEarlyRangeCheck(range, bounds: bounds)
  }
}
extension Slice: BidirectionalCollection where Base: BidirectionalCollection {
  @inlinable public func index(before i: Index) -> Index { return _base.index(before: i) }
  @inlinable public func formIndex(before i: inout Index) { _base.formIndex(before: &i) }
}
extension Slice: RandomAccessCollection where Base: RandomAccessCollection {}
extension Slice: MutableCollection where Base: MutableCollection {
  @inlinable public subscript(index: Index) -> Base.Element {
    get {
      _base._failEarlyRangeCheck(index, bounds: _startIndex..<_endIndex)
      return _base[index]
    }
    set {
      _base._failEarlyRangeCheck(index, bounds: _startIndex..<_endIndex)
      _base[index] = newValue
    }
  }
  @inlinable public subscript(bounds: Range<Index>) -> Slice<Base> {
    get { return Slice(base: _base, bounds: bounds) }
    set {
      var i = bounds.lowerBound
      var j = newValue.startIndex
      while i != bounds.upperBound {
        _base[i] = newValue[j]
        _base.formIndex(after: &i)
        newValue.formIndex(after: &j)
      }
    }
  }
}

// ---- CollectionOfOne and EmptyCollection ---------------------------------------------------

@frozen public struct CollectionOfOne<Element> {
  @usableFromInline internal var _element: Element
  @inlinable public init(_ element: Element) { self._element = element }
}
extension CollectionOfOne {
  @frozen public struct Iterator {
    @usableFromInline internal var _elements: Element?
    @inlinable public init(_elements: Element?) { self._elements = _elements }
  }
}
extension CollectionOfOne.Iterator: IteratorProtocol {
  @inlinable public mutating func next() -> Element? {
    let result = _elements
    _elements = nil
    return result
  }
}
extension CollectionOfOne: RandomAccessCollection, MutableCollection {
  public typealias Index = Int
  public typealias Indices = Range<Int>
  public typealias SubSequence = Slice<CollectionOfOne<Element>>
  @inlinable public var startIndex: Index { return 0 }
  @inlinable public var endIndex: Index { return 1 }
  @inlinable public func index(after i: Index) -> Index { return i + 1 }
  @inlinable public func index(before i: Index) -> Index { return i - 1 }
  @inlinable public __consuming func makeIterator() -> Iterator { return Iterator(_elements: _element) }
  @inlinable public subscript(position: Int) -> Element {
    get {
      _collectionPrecondition(position == 0)
      return _element
    }
    set {
      _collectionPrecondition(position == 0)
      _element = newValue
    }
  }
  @inlinable public subscript(bounds: Range<Int>) -> SubSequence {
    get { return Slice(base: self, bounds: bounds) }
    set {
      if bounds.lowerBound == 0 && bounds.upperBound == 1 { _element = newValue[0] }
    }
  }
  @inlinable public var count: Int { return 1 }
}

@frozen public struct EmptyCollection<Element> {
  @inlinable public init() {}
}
extension EmptyCollection {
  @frozen public struct Iterator {
    @inlinable public init() {}
  }
}
extension EmptyCollection.Iterator: IteratorProtocol, Sequence {
  @inlinable public mutating func next() -> Element? { return nil }
}
extension EmptyCollection: RandomAccessCollection, MutableCollection {
  public typealias Index = Int
  public typealias Indices = Range<Int>
  public typealias SubSequence = EmptyCollection<Element>
  @inlinable public __consuming func makeIterator() -> Iterator { return Iterator() }
  @inlinable public var startIndex: Index { return 0 }
  @inlinable public var endIndex: Index { return 0 }
  @inlinable public func index(after i: Index) -> Index { Builtin.int_trap() }
  @inlinable public func index(before i: Index) -> Index { Builtin.int_trap() }
  @inlinable public subscript(position: Index) -> Element {
    get { Builtin.int_trap() }
    set { Builtin.int_trap() }
  }
  @inlinable public subscript(bounds: Range<Index>) -> SubSequence {
    get { return self }
    set {}
  }
  @inlinable public var count: Int { return 0 }
}

// Swift.max/min for two values, used above and by programs.
@inlinable public func min<T: Comparable>(_ x: T, _ y: T) -> T { return y < x ? y : x }
@inlinable public func max<T: Comparable>(_ x: T, _ y: T) -> T { return y >= x ? y : x }
