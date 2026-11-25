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
