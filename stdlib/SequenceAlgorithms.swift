// Operations of sequences and collections whose results are arrays.

// ---- copying into a ContiguousArray --------------------------------------------------

@inlinable
internal func _copySequenceToContiguousArray<S: Sequence>(_ source: S) -> ContiguousArray<S.Element> {
  var result = ContiguousArray<S.Element>()
  result.reserveCapacity(source.underestimatedCount)
  var iterator = source.makeIterator()
  while let element = iterator.next() { result.append(element) }
  return result
}

@inlinable
internal func _copyCollectionToContiguousArray<C: Collection>(_ source: C) -> ContiguousArray<C.Element> {
  let n = source.count
  if n == 0 { return ContiguousArray() }
  let buffer = _ContiguousArrayBuffer<C.Element>(_uninitializedCount: n, minimumCapacity: 0)
  let (_, copied) = source._copyContents(
    initializing: UnsafeMutableBufferPointer(start: buffer.firstElementAddress, count: n))
  _precondition(copied == n, "invalid Collection: fewer elements than its count")
  return ContiguousArray(_buffer: buffer)
}

extension Collection {
  @inlinable public __consuming func _copyToContiguousArray() -> ContiguousArray<Element> {
    return _copyCollectionToContiguousArray(self)
  }
}

// ---- implicit array-to-pointer conversions --------------------------------------------
// `f(&array)` and `f(array)` for a pointer parameter: the compiler passes the
// address of the elements and keeps the returned owner alive across the call.

@_transparent
public func _convertMutableArrayToPointerArgument<FromElement, ToPointer: _Pointer>(
  _ a: inout [FromElement]
) -> (AnyObject?, ToPointer) {
  // Unique native storage, so that writes through the pointer are seen by
  // this array alone.
  a.reserveCapacity(0)
  return (a._owner, ToPointer(a._baseAddressIfContiguous!._rawValue))
}

@_transparent
public func _convertConstArrayToPointerArgument<FromElement, ToPointer: _Pointer>(
  _ arr: [FromElement]
) -> (AnyObject?, ToPointer) {
  if let address = arr._baseAddressIfContiguous {
    return (arr._owner, ToPointer(address._rawValue))
  }
  // Not contiguous (an NSArray): pass a native copy, which the owner keeps.
  let copy = arr._copyToContiguousArray()
  return (copy._buffer.owner, ToPointer(copy._buffer.firstElementAddress._rawValue))
}

// ---- operations that return arrays -------------------------------------------------
// Declared with `rethrows`, the form programs bind to (Swift 6's typed-throws
// spellings are emitted into clients).

extension Sequence {
  @inlinable
  public func map<T>(_ transform: (Element) throws -> T) rethrows -> [T] {
    var result = ContiguousArray<T>()
    result.reserveCapacity(underestimatedCount)
    for e in self { result.append(try transform(e)) }
    return Array(result)
  }

  @inlinable
  public __consuming func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> [Element] {
    var result = ContiguousArray<Element>()
    for e in self where try isIncluded(e) { result.append(e) }
    return Array(result)
  }

  @inlinable
  public func compactMap<ElementOfResult>(_ transform: (Element) throws -> ElementOfResult?) rethrows -> [ElementOfResult] {
    var result = ContiguousArray<ElementOfResult>()
    for e in self {
      if let v = try transform(e) { result.append(v) }
    }
    return Array(result)
  }

  @inlinable
  public func flatMap<SegmentOfResult: Sequence>(_ transform: (Element) throws -> SegmentOfResult) rethrows
    -> [SegmentOfResult.Element] {
    var result: [SegmentOfResult.Element] = []
    for e in self { result.append(contentsOf: try transform(e)) }
    return result
  }

  @inlinable
  public func sorted(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> [Element] {
    var result = ContiguousArray(self)
    try result.sort(by: areInIncreasingOrder)
    return Array(result)
  }

  @inlinable
  public __consuming func reversed() -> [Element] {
    var result = Array(self)
    result.reverse()
    return result
  }

  @inlinable
  public __consuming func split(maxSplits: Int = Int.max, omittingEmptySubsequences: Bool = true,
                                whereSeparator isSeparator: (Element) throws -> Bool) rethrows -> [ArraySlice<Element>] {
    let all = Array(self)
    var result: [ArraySlice<Element>] = []
    var start = 0
    var i = 0
    while i < all.count {
      if result.count < maxSplits, try isSeparator(all[i]) {
        if !(omittingEmptySubsequences && start == i) { result.append(all[start..<i]) }
        start = i + 1
      }
      i += 1
    }
    if !(omittingEmptySubsequences && start == all.count) { result.append(all[start..<all.count]) }
    return result
  }
}

extension Sequence where Element: Comparable {
  @inlinable public func sorted() -> [Element] { return sorted(by: <) }
}

extension Sequence where Element: Equatable {
  @inlinable
  public __consuming func split(separator: Element, maxSplits: Int = Int.max,
                                omittingEmptySubsequences: Bool = true) -> [ArraySlice<Element>] {
    return split(maxSplits: maxSplits, omittingEmptySubsequences: omittingEmptySubsequences,
                 whereSeparator: { $0 == separator })
  }
}

extension Sequence where Element: Sequence {
  @inlinable
  public __consuming func joined() -> [Element.Element] {
    var result: [Element.Element] = []
    for s in self { result.append(contentsOf: s) }
    return result
  }
}

extension Collection {
  @inlinable
  public func map<T>(_ transform: (Element) throws -> T) rethrows -> [T] {
    var result = ContiguousArray<T>()
    result.reserveCapacity(count)
    for e in self { result.append(try transform(e)) }
    return Array(result)
  }
}

extension Collection {
  @inlinable
  public __consuming func split(maxSplits: Int = Int.max, omittingEmptySubsequences: Bool = true,
                                whereSeparator isSeparator: (Element) throws -> Bool) rethrows -> [SubSequence] {
    var result: [SubSequence] = []
    var start = startIndex
    var i = startIndex
    while i != endIndex {
      if result.count < maxSplits, try isSeparator(self[i]) {
        if !(omittingEmptySubsequences && start == i) { result.append(self[start..<i]) }
        start = index(after: i)
      }
      formIndex(after: &i)
    }
    if !(omittingEmptySubsequences && start == endIndex) { result.append(self[start..<endIndex]) }
    return result
  }
}

extension Collection where Element: Equatable {
  @inlinable
  public __consuming func split(separator: Element, maxSplits: Int = Int.max,
                                omittingEmptySubsequences: Bool = true) -> [SubSequence] {
    return split(maxSplits: maxSplits, omittingEmptySubsequences: omittingEmptySubsequences,
                 whereSeparator: { $0 == separator })
  }
}
