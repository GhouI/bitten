// Lazy sequences, FlattenSequence and ReversedCollection. These are @frozen
// in Apple's library with the stored properties below, because programs
// inline their iteration.

// MARK: - LazySequenceProtocol

public protocol LazySequenceProtocol: Sequence {
  associatedtype Elements: Sequence = Self where Elements.Element == Element
  var elements: Elements { get }
}

extension LazySequenceProtocol where Elements == Self {
  @inlinable public var elements: Self { return self }
}

extension LazySequenceProtocol {
  @inlinable public var lazy: LazySequence<Elements> { return elements.lazy }
}

public protocol LazyCollectionProtocol: Collection, LazySequenceProtocol where Elements: Collection {}

@frozen
public struct LazySequence<Base: Sequence> {
  @usableFromInline internal var _base: Base
  @inlinable internal init(_base: Base) { self._base = _base }
}

extension LazySequence: Sequence {
  public typealias Element = Base.Element
  public typealias Iterator = Base.Iterator
  @inlinable public __consuming func makeIterator() -> Iterator { return _base.makeIterator() }
  @inlinable public var underestimatedCount: Int { return _base.underestimatedCount }
}

extension LazySequence: LazySequenceProtocol {
  public typealias Elements = Base
  @inlinable public var elements: Base { return _base }
}

extension LazySequence: Collection where Base: Collection {
  public typealias Index = Base.Index
  public typealias Indices = Base.Indices
  public typealias SubSequence = Slice<LazySequence<Base>>
  @inlinable public var startIndex: Index { return _base.startIndex }
  @inlinable public var endIndex: Index { return _base.endIndex }
  @inlinable public var indices: Indices { return _base.indices }
  @inlinable public func index(after i: Index) -> Index { return _base.index(after: i) }
  @inlinable public subscript(position: Index) -> Element { return _base[position] }
  @inlinable public var count: Int { return _base.count }
}
extension LazySequence: LazyCollectionProtocol where Base: Collection {}
extension LazySequence: BidirectionalCollection where Base: BidirectionalCollection {
  @inlinable public func index(before i: Index) -> Index { return _base.index(before: i) }
}
extension LazySequence: RandomAccessCollection where Base: RandomAccessCollection {}

extension Sequence {
  @inlinable public var lazy: LazySequence<Self> { return LazySequence(_base: self) }
}

// MARK: - LazyMapSequence

@frozen
public struct LazyMapSequence<Base: Sequence, Element> {
  public typealias Elements = LazyMapSequence
  @usableFromInline internal var _base: Base
  @usableFromInline internal let _transform: (Base.Element) -> Element
  @inlinable internal init(_base: Base, transform: @escaping (Base.Element) -> Element) {
    self._base = _base
    self._transform = transform
  }
}

extension LazyMapSequence {
  @frozen
  public struct Iterator {
    @usableFromInline internal var _base: Base.Iterator
    @usableFromInline internal let _transform: (Base.Element) -> Element
    @inlinable public var base: Base.Iterator { return _base }
    @inlinable internal init(_base: Base.Iterator, _transform: @escaping (Base.Element) -> Element) {
      self._base = _base
      self._transform = _transform
    }
  }
}

extension LazyMapSequence.Iterator: IteratorProtocol, Sequence {
  @inlinable public mutating func next() -> Element? { return _base.next().map(_transform) }
}

extension LazyMapSequence: LazySequenceProtocol {
  @inlinable public __consuming func makeIterator() -> Iterator {
    return Iterator(_base: _base.makeIterator(), _transform: _transform)
  }
  @inlinable public var underestimatedCount: Int { return _base.underestimatedCount }
}

extension LazyMapSequence: Collection where Base: Collection {
  public typealias Index = Base.Index
  public typealias Indices = Base.Indices
  public typealias SubSequence = LazyMapSequence<Base.SubSequence, Element>
  @inlinable public var startIndex: Base.Index { return _base.startIndex }
  @inlinable public var endIndex: Base.Index { return _base.endIndex }
  @inlinable public var indices: Indices { return _base.indices }
  @inlinable public func index(after i: Index) -> Index { return _base.index(after: i) }
  @inlinable public func formIndex(after i: inout Index) { _base.formIndex(after: &i) }
  @inlinable public subscript(position: Base.Index) -> Element { return _transform(_base[position]) }
  @inlinable public subscript(bounds: Range<Base.Index>) -> SubSequence {
    return SubSequence(_base: _base[bounds], transform: _transform)
  }
  @inlinable public var isEmpty: Bool { return _base.isEmpty }
  @inlinable public var count: Int { return _base.count }
  @inlinable public func index(_ i: Index, offsetBy n: Int) -> Index { return _base.index(i, offsetBy: n) }
  @inlinable public func index(_ i: Index, offsetBy n: Int, limitedBy limit: Index) -> Index? {
    return _base.index(i, offsetBy: n, limitedBy: limit)
  }
  @inlinable public func distance(from start: Index, to end: Index) -> Int { return _base.distance(from: start, to: end) }
}
extension LazyMapSequence: LazyCollectionProtocol where Base: Collection {}
extension LazyMapSequence: BidirectionalCollection where Base: BidirectionalCollection {
  @inlinable public func index(before i: Index) -> Index { return _base.index(before: i) }
  @inlinable public func formIndex(before i: inout Index) { _base.formIndex(before: &i) }
}
extension LazyMapSequence: RandomAccessCollection where Base: RandomAccessCollection {}

extension LazySequenceProtocol {
  @inlinable
  public func map<U>(_ transform: @escaping (Element) -> U) -> LazyMapSequence<Elements, U> {
    return LazyMapSequence(_base: elements, transform: transform)
  }
  @inlinable
  public func compactMap<U>(_ transform: @escaping (Element) -> U?)
    -> LazyMapSequence<LazyFilterSequence<LazyMapSequence<Elements, U?>>, U> {
    return map(transform).filter { $0 != nil }.map { $0! }
  }
}

// MARK: - LazyFilterSequence

@frozen
public struct LazyFilterSequence<Base: Sequence> {
  public typealias Elements = LazyFilterSequence
  @usableFromInline internal var _base: Base
  @usableFromInline internal let _predicate: (Base.Element) -> Bool
  @inlinable public init(_base base: Base, _ isIncluded: @escaping (Base.Element) -> Bool) {
    self._base = base
    self._predicate = isIncluded
  }
}

extension LazyFilterSequence {
  @frozen
  public struct Iterator {
    @usableFromInline internal var _base: Base.Iterator
    @usableFromInline internal let _predicate: (Base.Element) -> Bool
    @inlinable public var base: Base.Iterator { return _base }
    @inlinable internal init(_base: Base.Iterator, _ isIncluded: @escaping (Base.Element) -> Bool) {
      self._base = _base
      self._predicate = isIncluded
    }
  }
}

extension LazyFilterSequence.Iterator: IteratorProtocol, Sequence {
  public typealias Element = Base.Element
  @inlinable public mutating func next() -> Element? {
    while let n = _base.next() {
      if _predicate(n) { return n }
    }
    return nil
  }
}

extension LazyFilterSequence: LazySequenceProtocol {
  public typealias Element = Base.Element
  @inlinable public __consuming func makeIterator() -> Iterator { return Iterator(_base: _base.makeIterator(), _predicate) }
}

extension LazyFilterSequence: Collection where Base: Collection {
  public typealias SubSequence = LazyFilterSequence<Base.SubSequence>
  public typealias Index = Base.Index
  @inlinable public var startIndex: Index {
    var index = _base.startIndex
    while index != _base.endIndex && !_predicate(_base[index]) { _base.formIndex(after: &index) }
    return index
  }
  @inlinable public var endIndex: Index { return _base.endIndex }
  @inlinable public func index(after i: Index) -> Index {
    var i = i
    formIndex(after: &i)
    return i
  }
  @inlinable public func formIndex(after i: inout Index) {
    var index = i
    _precondition(index != _base.endIndex, "Can't advance past endIndex")
    repeat { _base.formIndex(after: &index) } while index != _base.endIndex && !_predicate(_base[index])
    i = index
  }
  @inlinable public subscript(position: Index) -> Element { return _base[position] }
  @inlinable public subscript(bounds: Range<Index>) -> SubSequence {
    return SubSequence(_base: _base[bounds], _predicate)
  }
}
extension LazyFilterSequence: LazyCollectionProtocol where Base: Collection {}
extension LazyFilterSequence: BidirectionalCollection where Base: BidirectionalCollection {
  @inlinable public func index(before i: Index) -> Index {
    var i = i
    formIndex(before: &i)
    return i
  }
  @inlinable public func formIndex(before i: inout Index) {
    var index = i
    _precondition(index != _base.startIndex, "Can't retreat before startIndex")
    repeat { _base.formIndex(before: &index) } while !_predicate(_base[index])
    i = index
  }
}

extension LazySequenceProtocol {
  @inlinable
  public __consuming func filter(_ isIncluded: @escaping (Elements.Element) -> Bool) -> LazyFilterSequence<Elements> {
    return LazyFilterSequence(_base: elements, isIncluded)
  }
}

// MARK: - FlattenSequence

@frozen
public struct FlattenSequence<Base: Sequence> where Base.Element: Sequence {
  @usableFromInline internal var _base: Base
  @inlinable internal init(_base: Base) { self._base = _base }
}

extension FlattenSequence {
  @frozen
  public struct Iterator {
    @usableFromInline internal var _base: Base.Iterator
    @usableFromInline internal var _inner: Base.Element.Iterator?
    @inlinable internal init(_base: Base.Iterator) {
      self._base = _base
      self._inner = nil
    }
  }
}

extension FlattenSequence.Iterator: IteratorProtocol, Sequence {
  public typealias Element = Base.Element.Element
  @inlinable public mutating func next() -> Element? {
    repeat {
      if _inner != nil, let e = _inner!.next() { return e }
      guard let s = _base.next() else { return nil }
      _inner = s.makeIterator()
    } while true
  }
}

extension FlattenSequence: Sequence {
  @inlinable public __consuming func makeIterator() -> Iterator { return Iterator(_base: _base.makeIterator()) }
}

extension FlattenSequence: LazySequenceProtocol where Base: LazySequenceProtocol {}

extension Sequence where Element: Sequence {
  @inlinable public __consuming func joined() -> FlattenSequence<Self> { return FlattenSequence(_base: self) }
}

// MARK: - ReversedCollection

@frozen
public struct ReversedCollection<Base: BidirectionalCollection> {
  public let _base: Base
  @inlinable internal init(_base: Base) { self._base = _base }
}

extension ReversedCollection {
  @frozen
  public struct Iterator {
    @usableFromInline internal let _base: Base
    @usableFromInline internal var _position: Base.Index
    @inlinable @inline(__always) public init(_base: Base) {
      self._base = _base
      self._position = _base.endIndex
    }
  }
}

extension ReversedCollection.Iterator: IteratorProtocol, Sequence {
  public typealias Element = Base.Element
  @inlinable @inline(__always) public mutating func next() -> Element? {
    guard _fastPath(_position != _base.startIndex) else { return nil }
    _base.formIndex(before: &_position)
    return _base[_position]
  }
}

extension ReversedCollection: Sequence {
  public typealias Element = Base.Element
  @inlinable @inline(__always) public __consuming func makeIterator() -> Iterator { return Iterator(_base: _base) }
}

extension ReversedCollection {
  @frozen
  public struct Index {
    public let base: Base.Index
    @inlinable public init(_ base: Base.Index) { self.base = base }
  }
}

extension ReversedCollection.Index: Comparable {
  @inlinable public static func == (lhs: ReversedCollection<Base>.Index, rhs: ReversedCollection<Base>.Index) -> Bool {
    return lhs.base == rhs.base
  }
  @inlinable public static func < (lhs: ReversedCollection<Base>.Index, rhs: ReversedCollection<Base>.Index) -> Bool {
    return lhs.base > rhs.base
  }
}

extension ReversedCollection.Index: Hashable where Base.Index: Hashable {
  @inlinable public func hash(into hasher: inout Hasher) { hasher.combine(base) }
}

extension ReversedCollection: BidirectionalCollection {
  public typealias Indices = DefaultIndices<ReversedCollection<Base>>
  public typealias SubSequence = Slice<ReversedCollection<Base>>
  @inlinable public var startIndex: Index { return Index(_base.endIndex) }
  @inlinable public var endIndex: Index { return Index(_base.startIndex) }
  @inlinable public func index(after i: Index) -> Index { return Index(_base.index(before: i.base)) }
  @inlinable public func index(before i: Index) -> Index { return Index(_base.index(after: i.base)) }
  @inlinable public func index(_ i: Index, offsetBy n: Int) -> Index { return Index(_base.index(i.base, offsetBy: -n)) }
  @inlinable public func index(_ i: Index, offsetBy n: Int, limitedBy limit: Index) -> Index? {
    return _base.index(i.base, offsetBy: -n, limitedBy: limit.base).map(Index.init)
  }
  @inlinable public func distance(from start: Index, to end: Index) -> Int {
    return _base.distance(from: end.base, to: start.base)
  }
  @inlinable public subscript(position: Index) -> Element { return _base[_base.index(before: position.base)] }
  @inlinable public var count: Int { return _base.count }
}

extension ReversedCollection: RandomAccessCollection where Base: RandomAccessCollection {}

extension ReversedCollection {
  @inlinable public __consuming func reversed() -> Base { return _base }
}

extension BidirectionalCollection {
  @inlinable public __consuming func reversed() -> ReversedCollection<Self> { return ReversedCollection(_base: self) }
}
