// ContiguousArray: an array whose elements are always in native storage.
//
// Mutation follows one pattern, shared with Array (whose entry points
// programs inline and call by these names): make the buffer unique
// (copying when it is shared), make room (moving into larger storage when
// it is full), then change the storage in place.

@frozen
public struct ContiguousArray<Element>: _DestructorSafeContainer {
  @usableFromInline internal typealias _Buffer = _ContiguousArrayBuffer<Element>
  @usableFromInline internal var _buffer: _Buffer

  @inlinable internal init(_buffer: _Buffer) {
    self._buffer = _buffer
  }
}

extension ContiguousArray {
  @inlinable public init() {
    _buffer = _Buffer()
  }

  @inlinable public init<S: Sequence>(_ s: S) where S.Element == Element {
    self = s._copyToContiguousArray()
  }

  @inlinable public init(repeating repeatedValue: Element, count: Int) {
    _precondition(count >= 0, "Can't construct ContiguousArray with count < 0")
    _buffer = _Buffer(_uninitializedCount: count, minimumCapacity: 0)
    if count > 0 { _buffer.firstElementAddress.initialize(repeating: repeatedValue, count: count) }
  }

  /// An array of `count` elements the caller initializes.
  @inlinable internal init(_uninitializedCount count: Int) {
    _precondition(count >= 0, "Can't construct ContiguousArray with count < 0")
    _buffer = _Buffer(_uninitializedCount: count, minimumCapacity: 0)
  }

  @inlinable
  public init(unsafeUninitializedCapacity: Int,
              initializingWith initializer: (inout UnsafeMutableBufferPointer<Element>, inout Int) throws -> Void) rethrows {
    _buffer = _Buffer(_uninitializedCount: 0, minimumCapacity: unsafeUninitializedCapacity)
    var initializedCount = 0
    var bp = UnsafeMutableBufferPointer(start: _buffer.firstElementAddress, count: unsafeUninitializedCapacity)
    let original = bp
    defer {
      _precondition(initializedCount <= unsafeUninitializedCapacity,
                    "Initialized count set to greater than specified capacity.")
      _precondition(bp.baseAddress == original.baseAddress && bp.count == original.count,
                    "ContiguousArray(unsafeUninitializedCapacity:initializingWith:): replacing the buffer is not allowed")
      if unsafeUninitializedCapacity > 0 { _buffer.count = initializedCount }
    }
    try initializer(&bp, &initializedCount)
  }

  @inlinable
  internal static func _allocateBufferUninitialized(minimumCapacity: Int) -> _Buffer {
    return _Buffer(_uninitializedCount: 0, minimumCapacity: minimumCapacity)
  }

  /// An array of `count` uninitialized elements and the address of the
  /// first one.
  @inlinable
  internal static func _allocateUninitialized(_ count: Int) -> (ContiguousArray, UnsafeMutablePointer<Element>) {
    let result = ContiguousArray(_uninitializedCount: count)
    return (result, result._buffer.firstElementAddress)
  }

  @inlinable public var count: Int { return _buffer.count }
  @inlinable public var capacity: Int { return _buffer.capacity }
  @inlinable public var isEmpty: Bool { return count == 0 }

  @inlinable internal func _checkSubscript(_ index: Int) {
    _precondition(index >= 0 && index < _buffer.count, "Index out of range")
  }
  @inlinable internal func _checkIndex(_ index: Int) {
    _precondition(index <= _buffer.count, "ContiguousArray index is out of range")
    _precondition(index >= 0, "Negative ContiguousArray index is out of range")
  }

  // ---- the mutation protocol (names as in Apple's library) ----

  @inlinable
  internal mutating func _makeMutableAndUnique() {
    if _slowPath(!_buffer.isUniquelyReferenced()) {
      _buffer = _buffer._consumeAndCreateNew()
    }
  }

  @inlinable
  @_specialize(exported: true, where Element == AnyObject)
  internal mutating func _makeUniqueAndReserveCapacityIfNotUnique() {
    if _slowPath(!_buffer.isUniquelyReferenced()) {
      _createNewBuffer(bufferIsUnique: false, minimumCapacity: count + 1, growForAppend: true)
    }
  }

  @inlinable
  @_specialize(exported: true, where Element == AnyObject)
  internal mutating func _reserveCapacityAssumingUniqueBuffer(oldCount: Int) {
    if _slowPath(oldCount + 1 > _buffer.capacity) {
      _createNewBuffer(bufferIsUnique: true, minimumCapacity: oldCount + 1, growForAppend: true)
    }
  }

  @inlinable
  @_specialize(exported: true, where Element == AnyObject)
  internal mutating func _appendElementAssumeUniqueAndCapacity(_ oldCount: Int, newElement: __owned Element) {
    _buffer.count = oldCount + 1
    (_buffer.firstElementAddress + oldCount).initialize(to: newElement)
  }

  @inlinable
  @_specialize(exported: true, where Element == AnyObject)
  internal mutating func _endMutation() {}

  @inline(never) @usableFromInline
  internal mutating func _createNewBuffer(bufferIsUnique: Bool, minimumCapacity: Int, growForAppend: Bool) {
    _buffer = _buffer._consumeAndCreateNew(bufferIsUnique: bufferIsUnique,
                                           minimumCapacity: minimumCapacity,
                                           growForAppend: growForAppend)
  }

  /// Unique storage with room for `minimumCapacity` elements.
  @inlinable
  internal mutating func _reserveCapacityImpl(minimumCapacity: Int, growForAppend: Bool) {
    let isUnique = _buffer.isUniquelyReferenced()
    if _slowPath(!isUnique || _buffer.capacity < minimumCapacity) {
      _createNewBuffer(bufferIsUnique: isUnique,
                       minimumCapacity: minimumCapacity > count ? minimumCapacity : count,
                       growForAppend: growForAppend)
    }
  }

  @inlinable
  @_specialize(exported: true, where Element == AnyObject)
  public mutating func reserveCapacity(_ minimumCapacity: Int) {
    _reserveCapacityImpl(minimumCapacity: minimumCapacity, growForAppend: false)
  }

  // ---- RangeReplaceableCollection ----

  @inlinable
  public mutating func append(_ newElement: __owned Element) {
    _makeUniqueAndReserveCapacityIfNotUnique()
    let oldCount = _buffer.count
    _reserveCapacityAssumingUniqueBuffer(oldCount: oldCount)
    _appendElementAssumeUniqueAndCapacity(oldCount, newElement: newElement)
    _endMutation()
  }

  @inlinable
  public mutating func append<S: Sequence>(contentsOf newElements: __owned S) where S.Element == Element {
    let oldCount = count
    _reserveCapacityImpl(minimumCapacity: oldCount + newElements.underestimatedCount, growForAppend: true)
    let room = _buffer.capacity - oldCount
    let tail = UnsafeMutableBufferPointer(start: _buffer.firstElementAddress + oldCount, count: room)
    var (remainder, written) = newElements._copyContents(initializing: tail)
    _buffer.count = oldCount + written
    if written == room {
      while let element = remainder.next() { append(element) }
    }
  }

  @inlinable
  public mutating func insert(_ newElement: __owned Element, at i: Int) {
    _checkIndex(i)
    let oldCount = count
    _reserveCapacityImpl(minimumCapacity: oldCount + 1, growForAppend: true)
    let p = _buffer.firstElementAddress + i
    (p + 1).moveInitialize(from: p, count: oldCount - i)
    p.initialize(to: newElement)
    _buffer.count = oldCount + 1
  }

  @inlinable @discardableResult
  public mutating func remove(at index: Int) -> Element {
    _makeMutableAndUnique()
    let oldCount = _buffer.count
    _precondition(index >= 0 && index < oldCount, "Index out of range")
    let p = _buffer.firstElementAddress + index
    let result = p.move()
    p.moveInitialize(from: p + 1, count: oldCount - index - 1)
    _buffer.count = oldCount - 1
    return result
  }

  @inlinable
  public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
    if !keepCapacity {
      _buffer = _Buffer()
    } else if _buffer.isUniquelyReferenced() {
      let n = _buffer.count
      _buffer.count = 0
      _buffer.firstElementAddress.deinitialize(count: n)
    } else {
      _buffer = _Buffer(_uninitializedCount: 0, minimumCapacity: capacity)
    }
  }

  @inlinable
  public mutating func _customRemoveLast() -> Element? {
    _makeMutableAndUnique()
    let n = _buffer.count
    _precondition(n > 0, "Can't removeLast from an empty ContiguousArray")
    _buffer.count = n - 1
    return (_buffer.firstElementAddress + (n - 1)).move()
  }

  @inlinable
  public mutating func popLast() -> Element? {
    if isEmpty { return nil }
    return _customRemoveLast()
  }

  @inlinable
  public mutating func replaceSubrange<C: Collection>(_ subrange: Range<Int>, with newElements: __owned C)
  where C.Element == Element {
    _precondition(subrange.lowerBound >= 0, "ContiguousArray replace: subrange start is negative")
    _precondition(subrange.upperBound <= _buffer.count, "ContiguousArray replace: subrange extends past the end")
    let oldCount = _buffer.count
    let insertCount = newElements.count
    let newCount = oldCount - (subrange.upperBound - subrange.lowerBound) + insertCount
    if _buffer.isUniquelyReferenced() && _buffer.capacity >= newCount {
      _buffer._replaceInPlace(subrange, with: insertCount, elementsOf: newElements)
    } else {
      _buffer = _Buffer._replacingCopy(
        of: _buffer.firstElementAddress, count: oldCount, subrange, with: insertCount,
        elementsOf: newElements,
        minimumCapacity: _growArrayCapacity(oldCapacity: _buffer.capacity, minimumCapacity: newCount,
                                            growForAppend: true))
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
                    "ContiguousArray withUnsafeMutableBufferPointer: replacing the buffer is not allowed")
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
    return self
  }
}

extension ContiguousArray: ExpressibleByArrayLiteral {
  @inlinable public init(arrayLiteral elements: Element...) {
    self.init(_buffer: elements._buffer._native)
  }
}

extension ContiguousArray: RandomAccessCollection, MutableCollection {
  public typealias Index = Int
  public typealias Indices = Range<Int>
  public typealias Iterator = IndexingIterator<ContiguousArray<Element>>

  @inlinable public var startIndex: Int { return 0 }
  @inlinable public var endIndex: Int { return _buffer.count }
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
      return _buffer.firstElementAddress[index]
    }
    _modify {
      _makeMutableAndUnique()
      _checkSubscript(index)
      let address = _buffer.firstElementAddress + index
      defer { _endMutation() }
      yield &address.pointee
    }
  }

  @inlinable public subscript(bounds: Range<Int>) -> ArraySlice<Element> {
    get {
      _precondition(bounds.lowerBound >= 0 && bounds.upperBound <= _buffer.count,
                    "ContiguousArray index is out of range")
      return ArraySlice(_buffer: _buffer[bounds])
    }
    set {
      _precondition(bounds.lowerBound >= 0 && bounds.upperBound <= _buffer.count,
                    "ContiguousArray index is out of range")
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
      buffer.baseAddress!.initialize(from: UnsafePointer(_buffer.firstElementAddress), count: n)
    }
    return (IndexingIterator(_elements: self, _position: n), n)
  }
}

extension ContiguousArray: RangeReplaceableCollection {}

extension ContiguousArray: Equatable where Element: Equatable {
  @inlinable public static func == (lhs: ContiguousArray<Element>, rhs: ContiguousArray<Element>) -> Bool {
    let n = lhs.count
    if n != rhs.count { return false }
    if n == 0 || lhs._buffer.identity == rhs._buffer.identity { return true }
    var i = 0
    while i < n {
      if lhs[i] != rhs[i] { return false }
      i += 1
    }
    return true
  }
}

extension ContiguousArray: Hashable where Element: Hashable {
  @inlinable public func hash(into hasher: inout Hasher) {
    hasher.combine(count)
    for element in self { hasher.combine(element) }
  }
  @inlinable public var hashValue: Int { return _hashValue(for: self) }
}
