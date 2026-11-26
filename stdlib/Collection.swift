// The collection protocols and their default implementations.

public protocol Collection<Element>: Sequence {
  override associatedtype Element
  associatedtype Index: Comparable
  where Index == Indices.Element, Indices.Element == Indices.Index, Indices.Index == SubSequence.Index
  var startIndex: Index { get }
  var endIndex: Index { get }
  associatedtype Iterator = IndexingIterator<Self>
  override __consuming func makeIterator() -> Iterator
  associatedtype SubSequence: Collection = Slice<Self>
  where Element == SubSequence.Element, SubSequence == SubSequence.SubSequence
  // A read coroutine, as Apple declares it (programs' conformances
  // supply a `_read` witness).
  @_borrowed
  subscript(position: Index) -> Element { get }
  subscript(bounds: Range<Index>) -> SubSequence { get }
  associatedtype Indices: Collection = DefaultIndices<Self> where Indices == Indices.SubSequence
  var indices: Indices { get }
  var isEmpty: Bool { get }
  var count: Int { get }
  func _customIndexOfEquatableElement(_ element: Element) -> Index??
  func _customLastIndexOfEquatableElement(_ element: Element) -> Index??
  func index(_ i: Index, offsetBy distance: Int) -> Index
  func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index?
  func distance(from start: Index, to end: Index) -> Int
  func _failEarlyRangeCheck(_ index: Index, bounds: Range<Index>)
  func _failEarlyRangeCheck(_ index: Index, bounds: ClosedRange<Index>)
  func _failEarlyRangeCheck(_ range: Range<Index>, bounds: Range<Index>)
  func index(after i: Index) -> Index
  func formIndex(after i: inout Index)
}

// Traps with a message once the message machinery exists; for now a trap.
@usableFromInline @inline(never)
internal func _collectionPrecondition(_ condition: Bool) {
  if !condition { Builtin.int_trap() }
}

extension Collection where Iterator == IndexingIterator<Self> {
  @inlinable @inline(__always)
  public __consuming func makeIterator() -> IndexingIterator<Self> {
    return IndexingIterator(_elements: self)
  }
}

extension Collection where SubSequence == Slice<Self> {
  @inlinable public subscript(bounds: Range<Index>) -> Slice<Self> {
    _failEarlyRangeCheck(bounds, bounds: startIndex..<endIndex)
    return Slice(base: self, bounds: bounds)
  }
}

extension Collection where Indices == DefaultIndices<Self> {
  @inlinable public var indices: DefaultIndices<Self> {
    return DefaultIndices(_elements: self, startIndex: startIndex, endIndex: endIndex)
  }
}

extension Collection {
  @inlinable public var isEmpty: Bool { return startIndex == endIndex }
  @inlinable public var count: Int { return distance(from: startIndex, to: endIndex) }
  @inlinable public var underestimatedCount: Int { return count }

  @inlinable public func _customIndexOfEquatableElement(_ element: Iterator.Element) -> Index?? { return nil }
  @inlinable public func _customLastIndexOfEquatableElement(_ element: Iterator.Element) -> Index?? { return nil }

  @inlinable public func formIndex(after i: inout Index) { i = index(after: i) }

  @inlinable public func _failEarlyRangeCheck(_ index: Index, bounds: Range<Index>) {
    _collectionPrecondition(bounds.lowerBound <= index && index < bounds.upperBound)
  }
  @inlinable public func _failEarlyRangeCheck(_ index: Index, bounds: ClosedRange<Index>) {
    _collectionPrecondition(bounds.lowerBound <= index && index <= bounds.upperBound)
  }
  @inlinable public func _failEarlyRangeCheck(_ range: Range<Index>, bounds: Range<Index>) {
    _collectionPrecondition(bounds.lowerBound <= range.lowerBound && range.upperBound <= bounds.upperBound)
  }

  @inlinable public func index(_ i: Index, offsetBy distance: Int) -> Index {
    _collectionPrecondition(distance >= 0)
    var i = i
    for _ in 0..<distance { formIndex(after: &i) }
    return i
  }
  @inlinable public func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    _collectionPrecondition(distance >= 0)
    var i = i
    for _ in 0..<distance {
      if i == limit { return nil }
      formIndex(after: &i)
    }
    return i
  }
  @inlinable public func distance(from start: Index, to end: Index) -> Int {
    _collectionPrecondition(start <= end)
    var start = start
    var count = 0
    while start != end {
      count += 1
      formIndex(after: &start)
    }
    return count
  }

  @inlinable public func formIndex(_ i: inout Index, offsetBy distance: Int) {
    i = index(i, offsetBy: distance)
  }

  @inlinable public var first: Element? {
    let start = startIndex
    if start != endIndex { return self[start] }
    return nil
  }

  @inlinable public func firstIndex(where predicate: (Element) throws -> Bool) rethrows -> Index? {
    var i = startIndex
    while i != endIndex {
      if try predicate(self[i]) { return i }
      formIndex(after: &i)
    }
    return nil
  }

  @inlinable public __consuming func dropFirst(_ k: Int = 1) -> SubSequence {
    _collectionPrecondition(k >= 0)
    let start = index(startIndex, offsetBy: k, limitedBy: endIndex) ?? endIndex
    return self[start..<endIndex]
  }
  @inlinable public __consuming func dropLast(_ k: Int = 1) -> SubSequence {
    _collectionPrecondition(k >= 0)
    let amount = Swift.max(0, count - k)
    let end = index(startIndex, offsetBy: amount, limitedBy: endIndex) ?? endIndex
    return self[startIndex..<end]
  }
  @inlinable public __consuming func prefix(_ maxLength: Int) -> SubSequence {
    _collectionPrecondition(maxLength >= 0)
    let end = index(startIndex, offsetBy: maxLength, limitedBy: endIndex) ?? endIndex
    return self[startIndex..<end]
  }
  @inlinable public __consuming func suffix(_ maxLength: Int) -> SubSequence {
    _collectionPrecondition(maxLength >= 0)
    let amount = Swift.max(0, count - maxLength)
    let start = index(startIndex, offsetBy: amount, limitedBy: endIndex) ?? endIndex
    return self[start..<endIndex]
  }
  @inlinable public __consuming func prefix(upTo end: Index) -> SubSequence { return self[startIndex..<end] }
  @inlinable public __consuming func suffix(from start: Index) -> SubSequence { return self[start..<endIndex] }
  @inlinable public __consuming func prefix(through position: Index) -> SubSequence {
    return prefix(upTo: index(after: position))
  }

  @inlinable public subscript<R: RangeExpression>(r: R) -> SubSequence where R.Bound == Index {
    return self[r.relative(to: self)]
  }
  @inlinable public subscript(x: UnboundedRange) -> SubSequence {
    return self[startIndex...]
  }
}

extension Collection where Element: Equatable {
  @inlinable public func firstIndex(of element: Element) -> Index? {
    if let result = _customIndexOfEquatableElement(element) { return result }
    return firstIndex { $0 == element }
  }
}

// Used by the compiler's checks of collection indexing in inlined code.
@inlinable
public func _expectEnd<C: Collection>(of s: C, is i: C.Index) {}

// ---- BidirectionalCollection ------------------------------------------------------

public protocol BidirectionalCollection<Element>: Collection
where Indices: BidirectionalCollection, SubSequence: BidirectionalCollection {
  override associatedtype Element
  override associatedtype Index
  override associatedtype SubSequence
  override associatedtype Indices
  func index(before i: Index) -> Index
  func formIndex(before i: inout Index)
  override func index(after i: Index) -> Index
  override func formIndex(after i: inout Index)
  // New requirements, not overrides, as in Apple's declaration.
  @_nonoverride func index(_ i: Index, offsetBy distance: Int) -> Index
  @_nonoverride func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index?
  @_nonoverride func distance(from start: Index, to end: Index) -> Int
  override var indices: Indices { get }
  override subscript(bounds: Range<Index>) -> SubSequence { get }
  override var startIndex: Index { get }
  override var endIndex: Index { get }
}

extension BidirectionalCollection {
  @inlinable public func formIndex(before i: inout Index) { i = index(before: i) }
  @inlinable public func index(_ i: Index, offsetBy distance: Int) -> Index {
    var i = i
    if distance >= 0 {
      for _ in 0..<distance { formIndex(after: &i) }
    } else {
      for _ in 0..<(0 - distance) { formIndex(before: &i) }
    }
    return i
  }
  @inlinable public func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    var i = i
    if distance >= 0 {
      for _ in 0..<distance {
        if i == limit { return nil }
        formIndex(after: &i)
      }
    } else {
      for _ in 0..<(0 - distance) {
        if i == limit { return nil }
        formIndex(before: &i)
      }
    }
    return i
  }
  @inlinable public func distance(from start: Index, to end: Index) -> Int {
    var start = start
    var count = 0
    if start < end {
      while start != end { count += 1; formIndex(after: &start) }
    } else if start > end {
      while start != end { count -= 1; formIndex(before: &start) }
    }
    return count
  }
  @inlinable public var last: Element? {
    return isEmpty ? nil : self[index(before: endIndex)]
  }
  @inlinable public func lastIndex(where predicate: (Element) throws -> Bool) rethrows -> Index? {
    var i = endIndex
    while i != startIndex {
      formIndex(before: &i)
      if try predicate(self[i]) { return i }
    }
    return nil
  }
}

extension BidirectionalCollection where Element: Equatable {
  @inlinable public func lastIndex(of element: Element) -> Index? {
    if let result = _customLastIndexOfEquatableElement(element) { return result }
    return lastIndex { $0 == element }
  }
}

// ---- RandomAccessCollection -------------------------------------------------------------

public protocol RandomAccessCollection<Element>: BidirectionalCollection
where Indices: RandomAccessCollection, SubSequence: RandomAccessCollection {
  override associatedtype Element
  override associatedtype Index
  override associatedtype SubSequence
  override associatedtype Indices
  override var indices: Indices { get }
  override subscript(bounds: Range<Index>) -> SubSequence { get }
  override var startIndex: Index { get }
  override var endIndex: Index { get }
  override func index(before i: Index) -> Index
  override func formIndex(before i: inout Index)
  override func index(after i: Index) -> Index
  override func formIndex(after i: inout Index)
  @_nonoverride func index(_ i: Index, offsetBy distance: Int) -> Index
  @_nonoverride func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index?
  @_nonoverride func distance(from start: Index, to end: Index) -> Int
}

extension RandomAccessCollection {
  @inlinable public func index(_ i: Index, offsetBy distance: Int, limitedBy limit: Index) -> Index? {
    let l = self.distance(from: i, to: limit)
    if distance > 0 ? l >= 0 && l < distance : l <= 0 && distance < l { return nil }
    return index(i, offsetBy: distance)
  }
}

// Strideable indices (Int above all) get O(1) index arithmetic.
extension RandomAccessCollection where Index: Strideable, Index.Stride == Int, Indices == Range<Index> {
  @inlinable public var indices: Range<Index> { return startIndex..<endIndex }
  @inlinable public func index(after i: Index) -> Index { return i.advanced(by: 1) }
  @inlinable public func index(before i: Index) -> Index { return i.advanced(by: -1) }
  @inlinable public func index(_ i: Index, offsetBy distance: Index.Stride) -> Index {
    return i.advanced(by: distance)
  }
  @inlinable public func distance(from start: Index, to end: Index) -> Index.Stride {
    return start.distance(to: end)
  }
}

// ---- MutableCollection --------------------------------------------------------------------

public protocol MutableCollection<Element>: Collection where SubSequence: MutableCollection {
  override associatedtype Element
  override associatedtype Index
  override associatedtype SubSequence
  override subscript(position: Index) -> Element { get set }
  override subscript(bounds: Range<Index>) -> SubSequence { get set }
  mutating func partition(by belongsInSecondPartition: (Element) throws -> Bool) rethrows -> Index
  mutating func swapAt(_ i: Index, _ j: Index)
  mutating func _withUnsafeMutableBufferPointerIfSupported<R>(
    _ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R) rethrows -> R?
  mutating func withContiguousMutableStorageIfAvailable<R>(
    _ body: (_ buffer: inout UnsafeMutableBufferPointer<Element>) throws -> R) rethrows -> R?
}

extension MutableCollection {
  @inlinable public mutating func _withUnsafeMutableBufferPointerIfSupported<R>(
    _ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R) rethrows -> R? {
    return nil
  }
  @inlinable public mutating func withContiguousMutableStorageIfAvailable<R>(
    _ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R) rethrows -> R? {
    return nil
  }
  @inlinable public mutating func swapAt(_ i: Index, _ j: Index) {
    if i == j { return }
    let tmp = self[i]
    self[i] = self[j]
    self[j] = tmp
  }
  @inlinable public subscript<R: RangeExpression>(r: R) -> SubSequence where R.Bound == Index {
    get { return self[r.relative(to: self)] }
    set { self[r.relative(to: self)] = newValue }
  }
  @inlinable
  public mutating func partition(by belongsInSecondPartition: (Element) throws -> Bool) rethrows -> Index {
    // Lomuto-style: keep the first partition at the front.
    var pivot = startIndex
    var i = startIndex
    while i != endIndex {
      if try !belongsInSecondPartition(self[i]) {
        swapAt(i, pivot)
        formIndex(after: &pivot)
      }
      formIndex(after: &i)
    }
    return pivot
  }
}

extension MutableCollection where SubSequence == Slice<Self> {
  @inlinable public subscript(bounds: Range<Index>) -> Slice<Self> {
    get {
      _failEarlyRangeCheck(bounds, bounds: startIndex..<endIndex)
      return Slice(base: self, bounds: bounds)
    }
    set {
      var i = bounds.lowerBound
      var j = newValue.startIndex
      while i != bounds.upperBound {
        self[i] = newValue[j]
        formIndex(after: &i)
        newValue.formIndex(after: &j)
      }
    }
  }
}

extension MutableCollection where Self: BidirectionalCollection {
  @inlinable
  public mutating func partition(by belongsInSecondPartition: (Element) throws -> Bool) rethrows -> Index {
    var lo = startIndex
    var hi = endIndex
    while true {
      while true {
        if lo == hi { return lo }
        if try belongsInSecondPartition(self[lo]) { break }
        formIndex(after: &lo)
      }
      while true {
        formIndex(before: &hi)
        if lo == hi { return lo }
        if try !belongsInSecondPartition(self[hi]) { break }
      }
      swapAt(lo, hi)
      formIndex(after: &lo)
    }
  }
  @inlinable public mutating func reverse() {
    if isEmpty { return }
    var f = startIndex
    var l = index(before: endIndex)
    while f < l {
      swapAt(f, l)
      formIndex(after: &f)
      formIndex(before: &l)
    }
  }
}

extension MutableCollection where Self: RandomAccessCollection {
  /// Insertion sort for small runs, otherwise a heap sort: in place,
  /// O(n log n), no allocation.
  @inlinable
  public mutating func sort(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows {
    let n = count
    if n < 2 { return }
    func at(_ k: Int) -> Index { return index(startIndex, offsetBy: k) }
    if n <= 20 {
      var i = 1
      while i < n {
        var j = i
        while j > 0, try areInIncreasingOrder(self[at(j)], self[at(j - 1)]) {
          swapAt(at(j), at(j - 1))
          j -= 1
        }
        i += 1
      }
      return
    }
    func siftDown(_ root: Int, _ end: Int) throws {
      var r = root
      while true {
        let child = 2 * r + 1
        if child >= end { return }
        var c = child
        if c + 1 < end, try areInIncreasingOrder(self[at(c)], self[at(c + 1)]) { c += 1 }
        if try !areInIncreasingOrder(self[at(r)], self[at(c)]) { return }
        swapAt(at(r), at(c))
        r = c
      }
    }
    var start = n / 2
    while start > 0 { start -= 1; try siftDown(start, n) }
    var end = n
    while end > 1 {
      end -= 1
      swapAt(at(0), at(end))
      try siftDown(0, end)
    }
  }
}

extension MutableCollection where Self: RandomAccessCollection, Element: Comparable {
  @inlinable public mutating func sort() { sort(by: <) }
}

// ---- RangeReplaceableCollection --------------------------------------------------------------

public protocol RangeReplaceableCollection<Element>: Collection
where SubSequence: RangeReplaceableCollection {
  override associatedtype SubSequence
  init()
  mutating func replaceSubrange<C>(_ subrange: Range<Index>, with newElements: __owned C)
  where C: Collection, C.Element == Element
  mutating func reserveCapacity(_ n: Int)
  init(repeating repeatedValue: Element, count: Int)
  init<S: Sequence>(_ elements: S) where S.Element == Element
  mutating func append(_ newElement: __owned Element)
  mutating func append<S: Sequence>(contentsOf newElements: __owned S) where S.Element == Element
  mutating func insert(_ newElement: __owned Element, at i: Index)
  mutating func insert<S: Collection>(contentsOf newElements: __owned S, at i: Index) where S.Element == Element
  @discardableResult mutating func remove(at i: Index) -> Element
  mutating func removeSubrange(_ bounds: Range<Index>)
  mutating func _customRemoveLast() -> Element?
  mutating func _customRemoveLast(_ n: Int) -> Bool
  @discardableResult mutating func removeFirst() -> Element
  mutating func removeFirst(_ k: Int)
  mutating func removeAll(keepingCapacity keepCapacity: Bool)
  mutating func removeAll(where shouldBeRemoved: (Element) throws -> Bool) rethrows
  override subscript(bounds: Range<Index>) -> SubSequence { get }
}

extension RangeReplaceableCollection {
  @inlinable public init(repeating repeatedValue: Element, count: Int) {
    self.init()
    if count > 0 { append(contentsOf: Repeated(_repeating: repeatedValue, count: count)) }
  }
  @inlinable public init<S: Sequence>(_ elements: S) where S.Element == Element {
    self.init()
    append(contentsOf: elements)
  }
  @inlinable public mutating func reserveCapacity(_ n: Int) {}
  @inlinable public mutating func append(_ newElement: __owned Element) {
    insert(newElement, at: endIndex)
  }
  @inlinable public mutating func append<S: Sequence>(contentsOf newElements: __owned S) where S.Element == Element {
    for element in newElements { append(element) }
  }
  @inlinable public mutating func insert(_ newElement: __owned Element, at i: Index) {
    replaceSubrange(i..<i, with: CollectionOfOne(newElement))
  }
  @inlinable public mutating func insert<C: Collection>(contentsOf newElements: __owned C, at i: Index)
  where C.Element == Element {
    replaceSubrange(i..<i, with: newElements)
  }
  @inlinable @discardableResult public mutating func remove(at position: Index) -> Element {
    _collectionPrecondition(!isEmpty)
    let result: Element = self[position]
    replaceSubrange(position..<index(after: position), with: EmptyCollection())
    return result
  }
  @inlinable public mutating func removeSubrange(_ bounds: Range<Index>) {
    replaceSubrange(bounds, with: EmptyCollection())
  }
  @inlinable public mutating func removeFirst(_ k: Int) {
    if k == 0 { return }
    _collectionPrecondition(k >= 0)
    let end = index(startIndex, offsetBy: k)
    removeSubrange(startIndex..<end)
  }
  @inlinable @discardableResult public mutating func removeFirst() -> Element {
    _collectionPrecondition(!isEmpty)
    let first = self[startIndex]
    removeSubrange(startIndex..<index(after: startIndex))
    return first
  }
  @inlinable public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
    if !keepCapacity { self = Self() } else { replaceSubrange(startIndex..<endIndex, with: EmptyCollection()) }
  }
  @inlinable public mutating func _customRemoveLast() -> Element? { return nil }
  @inlinable public mutating func _customRemoveLast(_ n: Int) -> Bool { return false }
  @inlinable public mutating func removeAll(where shouldBeRemoved: (Element) throws -> Bool) rethrows {
    var result = Self()
    for element in self where try !shouldBeRemoved(element) { result.append(element) }
    self = result
  }
  @inlinable public mutating func removeSubrange<R: RangeExpression>(_ bounds: R) where R.Bound == Index {
    removeSubrange(bounds.relative(to: self))
  }
  @inlinable public subscript(bounds: Range<Index>) -> Slice<Self> {
    return Slice(base: self, bounds: bounds)
  }
}

extension RangeReplaceableCollection where Self: BidirectionalCollection {
  @inlinable @discardableResult public mutating func removeLast() -> Element {
    _collectionPrecondition(!isEmpty)
    if let result = _customRemoveLast() { return result }
    return remove(at: index(before: endIndex))
  }
  @inlinable public mutating func popLast() -> Element? {
    if isEmpty { return nil }
    if let result = _customRemoveLast() { return result }
    return remove(at: index(before: endIndex))
  }
  @inlinable public mutating func removeLast(_ k: Int) {
    if k == 0 { return }
    if _customRemoveLast(k) { return }
    let end = endIndex
    removeSubrange(index(end, offsetBy: 0 - k)..<end)
  }
}

extension RangeReplaceableCollection where Self: BidirectionalCollection, SubSequence == Self {
  @inlinable public mutating func _customRemoveLast() -> Element? {
    let element = last!
    self = self[startIndex..<index(before: endIndex)]
    return element
  }
  @inlinable public mutating func _customRemoveLast(_ n: Int) -> Bool {
    self = self[startIndex..<index(endIndex, offsetBy: 0 - n)]
    return true
  }
}

extension RangeReplaceableCollection where Self: MutableCollection {
  @inlinable public mutating func removeAll(where shouldBeRemoved: (Element) throws -> Bool) rethrows {
    let suffixStart = try _halfStablePartition(isSuffixElement: shouldBeRemoved)
    removeSubrange(suffixStart...)
  }
}

extension MutableCollection {
  /// Moves the elements satisfying the predicate to the end, keeping the
  /// order of the others; returns where the moved ones start.
  @inlinable
  internal mutating func _halfStablePartition(isSuffixElement: (Element) throws -> Bool) rethrows -> Index {
    guard var i = try firstIndex(where: isSuffixElement) else { return endIndex }
    var j = index(after: i)
    while j != endIndex {
      if try !isSuffixElement(self[j]) { swapAt(i, j); formIndex(after: &i) }
      formIndex(after: &j)
    }
    return i
  }
}

// A collection of one value repeated; used by init(repeating:count:).
@frozen public struct Repeated<Element> {
  public let count: Int
  public let repeatedValue: Element
  @inlinable internal init(_repeating repeatedValue: Element, count: Int) {
    self.count = count
    self.repeatedValue = repeatedValue
  }
}
extension Repeated: RandomAccessCollection {
  public typealias Indices = Range<Int>
  public typealias Index = Int
  @inlinable public var startIndex: Index { return 0 }
  @inlinable public var endIndex: Index { return count }
  @inlinable public subscript(position: Int) -> Element { return repeatedValue }
}
@inlinable public func repeatElement<T>(_ element: T, count n: Int) -> Repeated<T> {
  return Repeated(_repeating: element, count: n)
}

// Concatenation with any sequence of the same element type.
extension RangeReplaceableCollection {
  @inlinable
  public static func + <Other: Sequence>(lhs: Self, rhs: Other) -> Self where Element == Other.Element {
    var lhs = lhs
    lhs.append(contentsOf: rhs)
    return lhs
  }
  @inlinable
  public static func + <Other: Sequence>(lhs: Other, rhs: Self) -> Self where Element == Other.Element {
    var result = Self()
    result.reserveCapacity(rhs.count + lhs.underestimatedCount)
    result.append(contentsOf: lhs)
    result.append(contentsOf: rhs)
    return result
  }
  @inlinable
  public static func += <Other: Sequence>(lhs: inout Self, rhs: Other) where Element == Other.Element {
    lhs.append(contentsOf: rhs)
  }
  @inlinable
  public static func + <Other: RangeReplaceableCollection>(lhs: Self, rhs: Other) -> Self where Element == Other.Element {
    var lhs = lhs
    lhs.append(contentsOf: rhs)
    return lhs
  }
}
