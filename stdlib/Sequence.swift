// Iterators and sequences.
//
// Still to come with the Array work: the requirement _copyToContiguousArray
// and the operations that return arrays (map, filter, sorted, compactMap...).

public protocol IteratorProtocol<Element> {
  associatedtype Element
  mutating func next() -> Element?
}

public protocol Sequence<Element> {
  associatedtype Element where Element == Iterator.Element
  associatedtype Iterator: IteratorProtocol
  __consuming func makeIterator() -> Iterator
  var underestimatedCount: Int { get }
  func _customContainsEquatableElement(_ element: Element) -> Bool?
  __consuming func _copyContents(initializing ptr: UnsafeMutableBufferPointer<Element>)
    -> (Iterator, UnsafeMutableBufferPointer<Element>.Index)
  func withContiguousStorageIfAvailable<R>(_ body: (_ buffer: UnsafeBufferPointer<Element>) throws -> R) rethrows -> R?
}

extension Sequence where Self: IteratorProtocol {
  @inlinable public __consuming func makeIterator() -> Self { return self }
}

extension Sequence {
  @inlinable public var underestimatedCount: Int { return 0 }
  @inlinable public func _customContainsEquatableElement(_ element: Iterator.Element) -> Bool? { return nil }

  @inlinable
  public __consuming func _copyContents(initializing buffer: UnsafeMutableBufferPointer<Element>) -> (Iterator, Int) {
    var it = makeIterator()
    guard var p = buffer.baseAddress else { return (it, 0) }
    for i in 0..<buffer.count {
      guard let x = it.next() else { return (it, i) }
      p.initialize(to: x)
      p += 1
    }
    return (it, buffer.count)
  }

  @inlinable
  public func withContiguousStorageIfAvailable<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows -> R? {
    return nil
  }

  @inlinable public func forEach(_ body: (Element) throws -> Void) rethrows {
    for element in self { try body(element) }
  }

  @inlinable public func first(where predicate: (Element) throws -> Bool) rethrows -> Element? {
    for element in self where try predicate(element) { return element }
    return nil
  }

  @inlinable public func contains(where predicate: (Element) throws -> Bool) rethrows -> Bool {
    for element in self where try predicate(element) { return true }
    return false
  }

  @inlinable public func allSatisfy(_ predicate: (Element) throws -> Bool) rethrows -> Bool {
    for element in self where try !predicate(element) { return false }
    return true
  }

  @inlinable
  public func reduce<Result>(_ initialResult: Result,
                             _ nextPartialResult: (_ partialResult: Result, Element) throws -> Result) rethrows -> Result {
    var accumulator = initialResult
    for element in self { accumulator = try nextPartialResult(accumulator, element) }
    return accumulator
  }

  @inlinable
  public func reduce<Result>(into initialResult: __owned Result,
                             _ updateAccumulatingResult: (_ partialResult: inout Result, Element) throws -> ()) rethrows -> Result {
    var accumulator = initialResult
    for element in self { try updateAccumulatingResult(&accumulator, element) }
    return accumulator
  }

  @inlinable public func enumerated() -> EnumeratedSequence<Self> {
    return EnumeratedSequence(_base: self)
  }

  @inlinable public __consuming func prefix(_ maxLength: Int) -> PrefixSequence<Self> {
    return PrefixSequence(self, maxLength: maxLength)
  }

  @inlinable public func min(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> Element? {
    var it = makeIterator()
    guard var result = it.next() else { return nil }
    while let e = it.next() { if try areInIncreasingOrder(e, result) { result = e } }
    return result
  }

  @inlinable public func max(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> Element? {
    var it = makeIterator()
    guard var result = it.next() else { return nil }
    while let e = it.next() { if try areInIncreasingOrder(result, e) { result = e } }
    return result
  }
}

extension Sequence where Element: Equatable {
  @inlinable public func contains(_ element: Element) -> Bool {
    if let result = _customContainsEquatableElement(element) { return result }
    return contains { $0 == element }
  }

  @inlinable public func elementsEqual<OtherSequence: Sequence>(_ other: OtherSequence) -> Bool
  where OtherSequence.Element == Element {
    var a = makeIterator(), b = other.makeIterator()
    while true {
      switch (a.next(), b.next()) {
      case let (x?, y?): if x != y { return false }
      case (nil, nil): return true
      default: return false
      }
    }
  }
}

extension Sequence where Element: Comparable {
  @inlinable public func min() -> Element? { return self.min(by: <) }
  @inlinable public func max() -> Element? { return self.max(by: <) }
}

// ---- EnumeratedSequence -----------------------------------------------------------

@frozen public struct EnumeratedSequence<Base: Sequence> {
  @usableFromInline internal var _base: Base
  @inlinable internal init(_base: Base) { self._base = _base }
}
extension EnumeratedSequence {
  @frozen public struct Iterator {
    @usableFromInline internal var _base: Base.Iterator
    @usableFromInline internal var _count: Int
    @inlinable internal init(_base: Base.Iterator) {
      self._base = _base
      self._count = 0
    }
  }
}
extension EnumeratedSequence.Iterator: IteratorProtocol, Sequence {
  public typealias Element = (offset: Int, element: Base.Element)
  @inlinable public mutating func next() -> Element? {
    guard let b = _base.next() else { return nil }
    let result = (offset: _count, element: b)
    _count += 1
    return result
  }
}
extension EnumeratedSequence: Sequence {
  @inlinable public __consuming func makeIterator() -> Iterator {
    return Iterator(_base: _base.makeIterator())
  }
}

// ---- PrefixSequence --------------------------------------------------------------

@frozen public struct PrefixSequence<Base: Sequence> {
  @usableFromInline internal var _base: Base
  @usableFromInline internal let _maxLength: Int
  @inlinable public init(_ base: Base, maxLength: Int) {
    _base = base
    _maxLength = maxLength
  }
}
extension PrefixSequence {
  @frozen public struct Iterator {
    @usableFromInline internal var _base: Base.Iterator
    @usableFromInline internal var _remaining: Int
    @inlinable internal init(_ base: Base.Iterator, maxLength: Int) {
      _base = base
      _remaining = maxLength
    }
  }
}
extension PrefixSequence.Iterator: IteratorProtocol {
  public typealias Element = Base.Element
  @inlinable public mutating func next() -> Element? {
    if _remaining != 0 {
      _remaining &-= 1
      return _base.next()
    }
    return nil
  }
}
extension PrefixSequence: Sequence {
  @inlinable public __consuming func makeIterator() -> Iterator {
    return Iterator(_base.makeIterator(), maxLength: _maxLength)
  }
}

// ---- Zip2Sequence -------------------------------------------------------------

@frozen public struct Zip2Sequence<Sequence1: Sequence, Sequence2: Sequence> {
  @usableFromInline internal let _sequence1: Sequence1
  @usableFromInline internal let _sequence2: Sequence2
  @inlinable internal init(_ sequence1: Sequence1, _ sequence2: Sequence2) {
    (_sequence1, _sequence2) = (sequence1, sequence2)
  }
}
extension Zip2Sequence {
  @frozen public struct Iterator {
    @usableFromInline internal var _baseStream1: Sequence1.Iterator
    @usableFromInline internal var _baseStream2: Sequence2.Iterator
    @usableFromInline internal var _reachedEnd: Bool = false
    @inlinable internal init(_ iterator1: Sequence1.Iterator, _ iterator2: Sequence2.Iterator) {
      (_baseStream1, _baseStream2) = (iterator1, iterator2)
    }
  }
}
extension Zip2Sequence.Iterator: IteratorProtocol {
  public typealias Element = (Sequence1.Element, Sequence2.Element)
  @inlinable public mutating func next() -> Element? {
    if _reachedEnd { return nil }
    guard let a = _baseStream1.next(), let b = _baseStream2.next() else {
      _reachedEnd = true
      return nil
    }
    return (a, b)
  }
}
extension Zip2Sequence: Sequence {
  public typealias Element = (Sequence1.Element, Sequence2.Element)
  @inlinable public __consuming func makeIterator() -> Iterator {
    return Iterator(_sequence1.makeIterator(), _sequence2.makeIterator())
  }
}

@inlinable
public func zip<Sequence1, Sequence2>(_ sequence1: Sequence1, _ sequence2: Sequence2)
  -> Zip2Sequence<Sequence1, Sequence2> {
  return Zip2Sequence(sequence1, sequence2)
}

// ---- IteratorSequence / AnyIterator-free helpers ---------------------------------

@frozen public struct IteratorSequence<Base: IteratorProtocol> {
  @usableFromInline internal var _base: Base
  @inlinable public init(_ base: Base) { _base = base }
}
extension IteratorSequence: IteratorProtocol, Sequence {
  @inlinable public mutating func next() -> Base.Element? { return _base.next() }
}
