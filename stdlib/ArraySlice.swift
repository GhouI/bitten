// ArraySlice: a view of a range of some array storage's elements, with
// the original indices. A slice mutates its storage in place when it holds
// the only reference to it and (for changes of length) its elements are
// all of the storage's; otherwise it first copies its elements into new
// storage of its own, keeping its startIndex.

@frozen
public struct ArraySlice<Element>: _DestructorSafeContainer {
  @usableFromInline internal typealias _Buffer = _SliceBuffer<Element>
  @usableFromInline internal var _buffer: _Buffer

  @inlinable internal init(_buffer: _Buffer) {
    self._buffer = _buffer
  }
}

extension ArraySlice {
  @inlinable public init() {
    _buffer = _Buffer()
  }

  @inlinable internal init(_native: _ContiguousArrayBuffer<Element>, startIndex: Int = 0) {
    _buffer = _Buffer(_buffer: _native, shiftedToStartIndex: startIndex)
  }

  @inlinable public init<S: Sequence>(_ s: S) where S.Element == Element {
    self.init(_native: s._copyToContiguousArray()._buffer)
  }

  @inlinable public init(repeating repeatedValue: Element, count: Int) {
    _precondition(count >= 0, "Can't construct ArraySlice with count < 0")
    self.init(_native: ContiguousArray(repeating: repeatedValue, count: count)._buffer)
  }

  @inlinable public var count: Int { return _buffer.count }
  @inlinable public var capacity: Int { return _buffer.capacity }
  @inlinable public var isEmpty: Bool { return count == 0 }

  @inlinable internal func _checkSubscript(_ index: Int) {
    _precondition(index >= _buffer.startIndex && index < _buffer.endIndex, "Index out of bounds")
  }
  @inlinable internal func _checkIndex(_ index: Int) {
    _precondition(index <= _buffer.endIndex, "ArraySlice index is out of range")
    _precondition(index >= _buffer.startIndex, "ArraySlice index is out of range (before startIndex)")
  }

  // ---- making room ----

  @inlinable
  internal mutating func _makeMutableAndUnique() {
    if _slowPath(!(_buffer._hasNativeBuffer && _buffer.isUniquelyReferenced())) {
      _buffer = _Buffer(_buffer: _buffer._copyToNative(), shiftedToStartIndex: _buffer.startIndex)
    }
  }

  @inlinable internal mutating func _endMutation() {}

  /// Storage holding exactly this slice's elements, uniquely, with room
  /// for `minimumCapacity`.
  @inlinable
  internal mutating func _ownWholeStorage(minimumCapacity: Int, growForAppend: Bool) {
    let ownsAll = _buffer._ownsWholeNativeStorage()
    if ownsAll && _buffer.nativeBuffer.capacity >= minimumCapacity { return }
    let c = _buffer.count
    let oldCapacity = ownsAll ? _buffer.nativeBuffer.capacity : c
    let newCapacity = _growArrayCapacity(oldCapacity: oldCapacity,
                                         minimumCapacity: minimumCapacity > c ? minimumCapacity : c,
                                         growForAppend: growForAppend)
    let native = _ContiguousArrayBuffer<Element>(_uninitializedCount: c, minimumCapacity: newCapacity)
    if ownsAll {
      native.firstElementAddress.moveInitialize(from: _buffer.firstElementAddress, count: c)
      _buffer.nativeBuffer.count = 0
    } else {
      _buffer._copyContents(subRange: _buffer.indices, initializing: native.firstElementAddress)
    }
    _buffer = _Buffer(_buffer: native, shiftedToStartIndex: _buffer.startIndex)
  }

  @inlinable
  public mutating func reserveCapacity(_ minimumCapacity: Int) {
    _ownWholeStorage(minimumCapacity: minimumCapacity, growForAppend: false)
  }

  // ---- RangeReplaceableCollection ----

  @inlinable
  public mutating func append(_ newElement: __owned Element) {
    let oldCount = _buffer.count
    _ownWholeStorage(minimumCapacity: oldCount + 1, growForAppend: true)
    let native = _buffer.nativeBuffer
    (native.firstElementAddress + oldCount).initialize(to: newElement)
    native.count = oldCount + 1
    _buffer.count = oldCount + 1
  }

  @inlinable
  public mutating func append<S: Sequence>(contentsOf newElements: __owned S) where S.Element == Element {
    let oldCount = _buffer.count
    _ownWholeStorage(minimumCapacity: oldCount + newElements.underestimatedCount, growForAppend: true)
    let native = _buffer.nativeBuffer
    let room = native.capacity - oldCount
    let tail = UnsafeMutableBufferPointer(start: native.firstElementAddress + oldCount, count: room)
    var (remainder, written) = newElements._copyContents(initializing: tail)
    native.count = oldCount + written
    _buffer.count = oldCount + written
    if written == room {
      while let element = remainder.next() { append(element) }
    }
  }

  @inlinable
  public mutating func replaceSubrange<C: Collection>(_ subrange: Range<Int>, with newElements: __owned C)
  where C.Element == Element {
    _precondition(subrange.lowerBound >= _buffer.startIndex,
                  "ArraySlice replace: subrange start is before the slice's start")
    _precondition(subrange.upperBound <= _buffer.endIndex,
                  "ArraySlice replace: subrange extends past the end")
    let start = _buffer.startIndex
    let oldCount = _buffer.count
    let relative = (subrange.lowerBound - start)..<(subrange.upperBound - start)
    let insertCount = newElements.count
    let newCount = oldCount - (relative.upperBound - relative.lowerBound) + insertCount
    if _buffer._ownsWholeNativeStorage() && _buffer.nativeBuffer.capacity >= newCount {
      _buffer.nativeBuffer._replaceInPlace(relative, with: insertCount, elementsOf: newElements)
      _buffer.count = newCount
    } else {
      let native = _ContiguousArrayBuffer<Element>._replacingCopy(
        of: _buffer.firstElementAddress, count: oldCount, relative, with: insertCount,
        elementsOf: newElements,
        minimumCapacity: _growArrayCapacity(oldCapacity: _buffer.capacity, minimumCapacity: newCount,
                                            growForAppend: true))
      _buffer = _Buffer(_buffer: native, shiftedToStartIndex: start)
    }
  }

  @inlinable
  public mutating func insert(_ newElement: __owned Element, at i: Int) {
    _checkIndex(i)
    replaceSubrange(i..<i, with: CollectionOfOne(newElement))
  }

  @inlinable @discardableResult
  public mutating func remove(at index: Int) -> Element {
    _checkSubscript(index)
    let result = _buffer[index]
    replaceSubrange(index..<(index + 1), with: EmptyCollection())
    return result
  }

  @inlinable
  public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
    if !keepCapacity {
      _buffer = _Buffer()
    } else {
      replaceSubrange(_buffer.indices, with: EmptyCollection())
    }
  }

  // ---- buffer access ----

  @inlinable
  public func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows -> R {
    return try _buffer.withUnsafeBufferPointer(body)
  }

  @inlinable
  public mutating func withUnsafeMutableBufferPointer<R>(
    _ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R) rethrows -> R {
    _makeMutableAndUnique()
    let n = _buffer.count
    let base = _buffer.firstElementAddress
    var inoutBuffer = UnsafeMutableBufferPointer(start: base, count: n)
    defer {
      _precondition(inoutBuffer.baseAddress == base && inoutBuffer.count == n,
                    "ArraySlice withUnsafeMutableBufferPointer: replacing the buffer is not allowed")
      _fixLifetime(self)
    }
    return try body(&inoutBuffer)
  }

  @inlinable
  public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    return try withUnsafeBufferPointer { try body(UnsafeRawBufferPointer($0)) }
  }

  @inlinable
  public mutating func withUnsafeMutableBytes<R>(_ body: (UnsafeMutableRawBufferPointer) throws -> R) rethrows -> R {
    return try withUnsafeMutableBufferPointer { try body(UnsafeMutableRawBufferPointer($0)) }
  }

  @inlinable
  public __consuming func _copyToContiguousArray() -> ContiguousArray<Element> {
    return ContiguousArray(_buffer: _buffer._copyToNative())
  }
}

extension ArraySlice: ExpressibleByArrayLiteral {
  @inlinable public init(arrayLiteral elements: Element...) {
    self.init(_native: elements._buffer._native)
  }
}

extension ArraySlice: RandomAccessCollection, MutableCollection {
  public typealias Index = Int
  public typealias Indices = Range<Int>
  public typealias Iterator = IndexingIterator<ArraySlice<Element>>
  public typealias SubSequence = ArraySlice<Element>

  @inlinable public var startIndex: Int { return _buffer.startIndex }
  @inlinable public var endIndex: Int { return _buffer.endIndex }
  @inlinable public func index(after i: Int) -> Int { return i + 1 }
  @inlinable public func formIndex(after i: inout Int) { i += 1 }
  @inlinable public func index(before i: Int) -> Int { return i - 1 }
  @inlinable public func formIndex(before i: inout Int) { i -= 1 }
  @inlinable public func index(_ i: Int, offsetBy distance: Int) -> Int { return i + distance }
  @inlinable public func index(_ i: Int, offsetBy distance: Int, limitedBy limit: Int) -> Int? {
    let l = limit - i
    if distance > 0 ? l >= 0 && l < distance : l <= 0 && distance < l { return nil }
    return i + distance
  }
  @inlinable public func distance(from start: Int, to end: Int) -> Int { return end - start }
  @inlinable public func _failEarlyRangeCheck(_ index: Int, bounds: Range<Int>) {}
  @inlinable public func _failEarlyRangeCheck(_ range: Range<Int>, bounds: Range<Int>) {}

  @inlinable public subscript(index: Int) -> Element {
    get {
      _checkSubscript(index)
      return _buffer[index]
    }
    _modify {
      _makeMutableAndUnique()
      _checkSubscript(index)
      let address = _buffer.subscriptBaseAddress + index
      defer { _endMutation() }
      yield &address.pointee
    }
  }

  @inlinable public subscript(bounds: Range<Int>) -> ArraySlice<Element> {
    get {
      _precondition(bounds.lowerBound >= _buffer.startIndex && bounds.upperBound <= _buffer.endIndex,
                    "ArraySlice index is out of range")
      return ArraySlice(_buffer: _buffer[bounds])
    }
    set {
      _precondition(bounds.lowerBound >= _buffer.startIndex && bounds.upperBound <= _buffer.endIndex,
                    "ArraySlice index is out of range")
      replaceSubrange(bounds, with: newValue)
    }
  }

  @inlinable
  public func withContiguousStorageIfAvailable<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows -> R? {
    return try withUnsafeBufferPointer(body)
  }

  @inlinable
  public mutating func withContiguousMutableStorageIfAvailable<R>(
    _ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R) rethrows -> R? {
    return try withUnsafeMutableBufferPointer(body)
  }

  @inlinable
  public mutating func _withUnsafeMutableBufferPointerIfSupported<R>(
    _ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R) rethrows -> R? {
    return try withUnsafeMutableBufferPointer(body)
  }

  @inlinable public var underestimatedCount: Int { return count }

  @inlinable
  public __consuming func _copyContents(initializing buffer: UnsafeMutableBufferPointer<Element>)
    -> (Iterator, Int) {
    let n = Swift.min(count, buffer.count)
    if n > 0 {
      _buffer._copyContents(subRange: startIndex..<(startIndex + n), initializing: buffer.baseAddress!)
    }
    return (IndexingIterator(_elements: self, _position: startIndex + n), n)
  }
}

extension ArraySlice: RangeReplaceableCollection {}

extension ArraySlice: Equatable where Element: Equatable {
  @inlinable public static func == (lhs: ArraySlice<Element>, rhs: ArraySlice<Element>) -> Bool {
    let n = lhs.count
    if n != rhs.count { return false }
    if n == 0 || lhs._buffer.identity == rhs._buffer.identity { return true }
    var i = lhs.startIndex
    var j = rhs.startIndex
    while i < lhs.endIndex {
      if lhs[i] != rhs[j] { return false }
      i += 1
      j += 1
    }
    return true
  }
}

extension ArraySlice: Hashable where Element: Hashable {
  @inlinable public func hash(into hasher: inout Hasher) {
    hasher.combine(count)
    for element in self { hasher.combine(element) }
  }
  @inlinable public var hashValue: Int { return _hashValue(for: self) }
}
