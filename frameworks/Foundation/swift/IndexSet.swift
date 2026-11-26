// IndexSet: a set of non-negative integers kept as sorted, disjoint,
// non-adjacent ranges.

public struct IndexSet: CustomStringConvertible, CustomDebugStringConvertible, Equatable, BidirectionalCollection, SetAlgebra, Hashable, Sendable {
  public typealias Element = Int

  @usableFromInline internal var _ranges: [Range<Int>]

  public struct Index: CustomStringConvertible, Comparable, Hashable, Sendable {
    internal var value: Int
    internal var rangeIndex: Int
    public var description: String { return "\(value)" }
    public static func == (a: Index, b: Index) -> Bool { return a.value == b.value && a.rangeIndex == b.rangeIndex }
    public static func < (a: Index, b: Index) -> Bool {
      return a.rangeIndex < b.rangeIndex || (a.rangeIndex == b.rangeIndex && a.value < b.value)
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(value) }
  }

  public struct RangeView: Equatable, BidirectionalCollection, Sendable {
    internal let ranges: [Range<Int>]
    public typealias Index = Int
    public var startIndex: Int { return 0 }
    public var endIndex: Int { return ranges.count }
    public subscript(index: Int) -> Range<Int> { return ranges[index] }
    public func index(after i: Int) -> Int { return i + 1 }
    public func index(before i: Int) -> Int { return i - 1 }
    public static func == (a: RangeView, b: RangeView) -> Bool { return a.ranges == b.ranges }
  }

  public init() { _ranges = [] }
  public init(integersIn range: Range<Element>) { _ranges = range.isEmpty ? [] : [range] }
  public init<R: RangeExpression>(integersIn range: R) where R.Bound == Element {
    self.init(integersIn: range.relative(to: 0..<Int.max))
  }
  public init(integer: Element) { _ranges = [integer..<integer + 1] }

  public var description: String { return "\(count) indexes" }
  public var debugDescription: String { return "\(_ranges)" }

  public var rangeView: RangeView { return RangeView(ranges: _ranges) }
  public func rangeView(of range: Range<Element>) -> RangeView {
    return RangeView(ranges: _ranges.compactMap { r in
      let lo = Swift.max(r.lowerBound, range.lowerBound), hi = Swift.min(r.upperBound, range.upperBound)
      return lo < hi ? lo..<hi : nil
    })
  }

  // MARK: collection

  public var startIndex: Index {
    return _ranges.isEmpty ? endIndex : Index(value: _ranges[0].lowerBound, rangeIndex: 0)
  }
  public var endIndex: Index {
    return Index(value: _ranges.last?.upperBound ?? 0, rangeIndex: _ranges.count)
  }
  public subscript(index: Index) -> Element { return index.value }
  public subscript(bounds: Range<Index>) -> Slice<IndexSet> { return Slice(base: self, bounds: bounds) }
  public func index(after i: Index) -> Index {
    let r = _ranges[i.rangeIndex]
    if i.value + 1 < r.upperBound { return Index(value: i.value + 1, rangeIndex: i.rangeIndex) }
    let next = i.rangeIndex + 1
    return next < _ranges.count ? Index(value: _ranges[next].lowerBound, rangeIndex: next) : endIndex
  }
  public func index(before i: Index) -> Index {
    if i.rangeIndex < _ranges.count && i.value > _ranges[i.rangeIndex].lowerBound {
      return Index(value: i.value - 1, rangeIndex: i.rangeIndex)
    }
    let prev = i.rangeIndex - 1
    return Index(value: _ranges[prev].upperBound - 1, rangeIndex: prev)
  }
  public func formIndex(after i: inout Index) { i = index(after: i) }
  public func formIndex(before i: inout Index) { i = index(before: i) }

  public var count: Int { return _ranges.reduce(0) { $0 + $1.count } }
  public var isEmpty: Bool { return _ranges.isEmpty }
  public var first: Element? { return _ranges.first?.lowerBound }
  public var last: Element? { return _ranges.last.map { $0.upperBound - 1 } }
  public func makeIterator() -> IndexingIterator<IndexSet> { return IndexingIterator(_elements: self) }

  public func count(in range: Range<Element>) -> Int { return rangeView(of: range).reduce(0) { $0 + $1.count } }
  public func contains(_ integer: Element) -> Bool { return _rangeIndex(containing: integer) != nil }
  public func contains(integersIn range: Range<Element>) -> Bool {
    if range.isEmpty { return true }
    guard let i = _rangeIndex(containing: range.lowerBound) else { return false }
    return _ranges[i].upperBound >= range.upperBound
  }
  public func contains(integersIn indexSet: IndexSet) -> Bool {
    return indexSet._ranges.allSatisfy { contains(integersIn: $0) }
  }
  public func intersects(integersIn range: Range<Element>) -> Bool {
    return _ranges.contains { $0.overlaps(range) }
  }
  public func integerGreaterThan(_ integer: Element) -> Element? { return first { $0 > integer } }
  public func integerLessThan(_ integer: Element) -> Element? { return reversed().first { $0 < integer } }
  public func integerGreaterThanOrEqualTo(_ integer: Element) -> Element? { return first { $0 >= integer } }
  public func integerLessThanOrEqualTo(_ integer: Element) -> Element? { return reversed().first { $0 <= integer } }
  public func indexRange(in range: Range<Element>) -> Range<Index> {
    let lo = firstIndex { $0 >= range.lowerBound } ?? endIndex
    let hi = firstIndex { $0 >= range.upperBound } ?? endIndex
    return lo..<hi
  }

  internal func _rangeIndex(containing x: Int) -> Int? {
    var lo = 0, hi = _ranges.count
    while lo < hi {
      let mid = (lo + hi) / 2
      if _ranges[mid].upperBound <= x { lo = mid + 1 } else if _ranges[mid].lowerBound > x { hi = mid } else { return mid }
    }
    return nil
  }

  // MARK: mutation

  public mutating func insert(integersIn range: Range<Element>) {
    if range.isEmpty { return }
    var lo = range.lowerBound, hi = range.upperBound
    var out: [Range<Int>] = []
    var placed = false
    for r in _ranges {
      if r.upperBound < lo { out.append(r); continue }
      if r.lowerBound > hi {
        if !placed { out.append(lo..<hi); placed = true }
        out.append(r)
        continue
      }
      lo = Swift.min(lo, r.lowerBound)
      hi = Swift.max(hi, r.upperBound)
    }
    if !placed { out.append(lo..<hi) }
    _ranges = out
  }
  public mutating func insert<R: RangeExpression>(integersIn range: R) where R.Bound == Element {
    insert(integersIn: range.relative(to: 0..<Int.max))
  }
  public mutating func remove(integersIn range: Range<Element>) {
    if range.isEmpty { return }
    var out: [Range<Int>] = []
    for r in _ranges {
      if r.upperBound <= range.lowerBound || r.lowerBound >= range.upperBound {
        out.append(r)
        continue
      }
      if r.lowerBound < range.lowerBound { out.append(r.lowerBound..<range.lowerBound) }
      if r.upperBound > range.upperBound { out.append(range.upperBound..<r.upperBound) }
    }
    _ranges = out
  }
  public mutating func remove<R: RangeExpression>(integersIn range: R) where R.Bound == Element {
    remove(integersIn: range.relative(to: 0..<Int.max))
  }
  public mutating func removeAll() { _ranges.removeAll() }

  @discardableResult
  public mutating func insert(_ integer: Element) -> (inserted: Bool, memberAfterInsert: Element) {
    if contains(integer) { return (false, integer) }
    insert(integersIn: integer..<integer + 1)
    return (true, integer)
  }
  @discardableResult
  public mutating func update(with integer: Element) -> Element? {
    insert(integer)
    return integer
  }
  @discardableResult
  public mutating func remove(_ integer: Element) -> Element? {
    guard contains(integer) else { return nil }
    remove(integersIn: integer..<integer + 1)
    return integer
  }

  /// Moves every index at or above `index` by `delta` (removing what a
  /// negative shift overruns).
  public mutating func shift(startingAt index: Element, by delta: Int) {
    var out = IndexSet()
    for r in _ranges {
      if r.upperBound <= index {
        out.insert(integersIn: r)
        continue
      }
      if r.lowerBound < index { out.insert(integersIn: r.lowerBound..<index) }
      let lo = Swift.max(r.lowerBound, index) + delta, hi = r.upperBound + delta
      let floor = delta < 0 ? index : 0
      if hi > Swift.max(lo, floor) { out.insert(integersIn: Swift.max(lo, floor)..<hi) }
    }
    self = out
  }

  // MARK: set algebra

  public func union(_ other: IndexSet) -> IndexSet {
    var r = self
    r.formUnion(other)
    return r
  }
  public mutating func formUnion(_ other: IndexSet) {
    for r in other._ranges { insert(integersIn: r) }
  }
  public func intersection(_ other: IndexSet) -> IndexSet {
    var out = IndexSet()
    for a in _ranges {
      for b in other._ranges {
        let lo = Swift.max(a.lowerBound, b.lowerBound), hi = Swift.min(a.upperBound, b.upperBound)
        if lo < hi { out.insert(integersIn: lo..<hi) }
      }
    }
    return out
  }
  public mutating func formIntersection(_ other: IndexSet) { self = intersection(other) }
  public func symmetricDifference(_ other: IndexSet) -> IndexSet {
    return union(other).subtracting(intersection(other))
  }
  public mutating func formSymmetricDifference(_ other: IndexSet) { self = symmetricDifference(other) }
  public func subtracting(_ other: IndexSet) -> IndexSet {
    var r = self
    for x in other._ranges { r.remove(integersIn: x) }
    return r
  }
  public mutating func subtract(_ other: IndexSet) { self = subtracting(other) }
  public func isSubset(of other: IndexSet) -> Bool { return other.contains(integersIn: self) }
  public func isSuperset(of other: IndexSet) -> Bool { return contains(integersIn: other) }
  public func isDisjoint(with other: IndexSet) -> Bool { return intersection(other).isEmpty }
  public func isStrictSubset(of other: IndexSet) -> Bool { return isSubset(of: other) && self != other }
  public func isStrictSuperset(of other: IndexSet) -> Bool { return isSuperset(of: other) && self != other }

  public func filteredIndexSet(in range: Range<Element>, includeInteger: (Element) throws -> Bool) rethrows -> IndexSet {
    var out = IndexSet()
    for r in rangeView(of: range) { for i in r where try includeInteger(i) { out.insert(i) } }
    return out
  }
  public func filteredIndexSet(includeInteger: (Element) throws -> Bool) rethrows -> IndexSet {
    var out = IndexSet()
    for i in self where try includeInteger(i) { out.insert(i) }
    return out
  }

  public static func == (a: IndexSet, b: IndexSet) -> Bool { return a._ranges == b._ranges }
  public func hash(into hasher: inout Hasher) {
    for r in _ranges {
      hasher.combine(r.lowerBound)
      hasher.combine(r.upperBound)
    }
  }
}

extension IndexSet: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: Int...) {
    self.init()
    for e in elements { insert(e) }
  }
}

extension IndexSet: Codable {
  public init(from decoder: Decoder) throws {
    var c = try decoder.unkeyedContainer()
    self.init()
    while !c.isAtEnd {
      let lo = try c.decode(Int.self), n = try c.decode(Int.self)
      insert(integersIn: lo..<lo + n)
    }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.unkeyedContainer()
    for r in _ranges {
      try c.encode(r.lowerBound)
      try c.encode(r.count)
    }
  }
}
