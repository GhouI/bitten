// Array: on Darwin its buffer may also be an NSArray (or native storage
// whose elements still need a type check), so reads go through
// _ArrayBuffer and every mutation first makes the buffer unique native
// storage. The mutation entry points keep Apple's names and meanings:
// programs inline `append` and friends and call these.

/// A marker for containers whose destruction cannot run arbitrary code
/// before the elements' own.
public protocol _DestructorSafeContainer {}

@frozen
public struct Array<Element>: _DestructorSafeContainer {
  @usableFromInline internal typealias _Buffer = _ArrayBuffer<Element>
  @usableFromInline internal var _buffer: _Buffer

  @inlinable internal init(_buffer: _Buffer) {
    self._buffer = _buffer
  }
}

extension Array {
  @inlinable public init() {
    _buffer = _Buffer()
  }

  @inlinable internal init(_native: _ContiguousArrayBuffer<Element>) {
    _buffer = _Buffer(_buffer: _native, shiftedToStartIndex: 0)
  }

  @inlinable public init<S: Sequence>(_ s: S) where S.Element == Element {
    self.init(_native: s._copyToContiguousArray()._buffer)
  }

  @inlinable public init(repeating repeatedValue: Element, count: Int) {
    _precondition(count >= 0, "Can't construct Array with count < 0")
    let native = _ContiguousArrayBuffer<Element>(_uninitializedCount: count, minimumCapacity: 0)
    if count > 0 { native.firstElementAddress.initialize(repeating: repeatedValue, count: count) }
    self.init(_native: native)
  }

  @inlinable internal init(_uninitializedCount count: Int) {
    _precondition(count >= 0, "Can't construct Array with count < 0")
    self.init(_native: _ContiguousArrayBuffer(_uninitializedCount: count, minimumCapacity: 0))
  }

  @inlinable
  public init(unsafeUninitializedCapacity: Int,
              initializingWith initializer: (inout UnsafeMutableBufferPointer<Element>, inout Int) throws -> Void) rethrows {
    self = try Array(_native: ContiguousArray(unsafeUninitializedCapacity: unsafeUninitializedCapacity,
                                              initializingWith: initializer)._buffer)
  }

  @inlinable
  internal static func _allocateBufferUninitialized(minimumCapacity: Int) -> _Buffer {
    return _Buffer(_buffer: _ContiguousArrayBuffer(_uninitializedCount: 0, minimumCapacity: minimumCapacity),
                   shiftedToStartIndex: 0)
  }

  @inlinable
  internal static func _allocateUninitialized(_ count: Int) -> (Array, UnsafeMutablePointer<Element>) {
    let result = Array(_uninitializedCount: count)
    return (result, result._buffer.firstElementAddress)
  }

  /// An array over storage the caller allocated for `count` elements
  /// (array literals), and the address of the first element.
  @inlinable
  internal static func _adoptStorage(_ storage: __owned _ContiguousArrayStorage<Element>, count: Int)
    -> (Array, UnsafeMutablePointer<Element>) {
    let native = _ContiguousArrayBuffer<Element>(count: count, storage: storage)
    return (Array(_native: native), native.firstElementAddress)
  }

  @inlinable public var count: Int { return _buffer.count }
  @inlinable public var capacity: Int { return _buffer.capacity }
  @inlinable public var isEmpty: Bool { return count == 0 }

  @inlinable internal func _hoistableIsNativeTypeChecked() -> Bool {
    return _buffer.arrayPropertyIsNativeTypeChecked
  }
  @inlinable internal func _checkSubscript(_ index: Int) {
    _precondition(index >= 0 && index < _buffer.count, "Index out of range")
  }
  @inlinable internal func _checkIndex(_ index: Int) {
    _precondition(index <= _buffer.count, "Array index is out of range")
    _precondition(index >= 0, "Negative Array index is out of range")
  }
  @inlinable internal func _getElement(_ index: Int, wasNativeTypeChecked: Bool) -> Element {
    return _buffer.getElement(index, wasNativeTypeChecked: wasNativeTypeChecked)
  }

  /// The storage, which mutations below may change in place: only valid
  /// once the buffer is unique.
  @inlinable internal var _native: _ContiguousArrayBuffer<Element> {
    return _buffer._nativeTypeChecked
  }

  // ---- the mutation protocol ----

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
    if _slowPath(oldCount + 1 > _buffer.mutableCapacity) {
      _createNewBuffer(bufferIsUnique: true, minimumCapacity: oldCount + 1, growForAppend: true)
    }
  }

  @inlinable
  @_specialize(exported: true, where Element == AnyObject)
  internal mutating func _appendElementAssumeUniqueAndCapacity(_ oldCount: Int, newElement: __owned Element) {
    _buffer.mutableCount = oldCount + 1
    (_buffer.mutableFirstElementAddress + oldCount).initialize(to: newElement)
  }

  @inlinable
  @_specialize(exported: true, where Element == AnyObject)
  internal mutating func _endMutation() {}

  @inline(never)
  @_specialize(exported: true, where Element == AnyObject)
  @usableFromInline
  internal mutating func _createNewBuffer(bufferIsUnique: Bool, minimumCapacity: Int, growForAppend: Bool) {
    _buffer = _buffer._consumeAndCreateNew(bufferIsUnique: bufferIsUnique,
                                           minimumCapacity: minimumCapacity,
                                           growForAppend: growForAppend)
  }

  @inlinable
  internal mutating func _reserveCapacityImpl(minimumCapacity: Int, growForAppend: Bool) {
    let isUnique = _buffer.isUniquelyReferenced()
    if _slowPath(!isUnique || _buffer.mutableCapacity < minimumCapacity) {
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
    let oldCount = _buffer.mutableCount
    _reserveCapacityAssumingUniqueBuffer(oldCount: oldCount)
    _appendElementAssumeUniqueAndCapacity(oldCount, newElement: newElement)
    _endMutation()
  }

  @inlinable
  public mutating func append<S: Sequence>(contentsOf newElements: __owned S) where S.Element == Element {
    let oldCount = count
    _reserveCapacityImpl(minimumCapacity: oldCount + newElements.underestimatedCount, growForAppend: true)
    let native = _native
    let room = native.capacity - oldCount
    let tail = UnsafeMutableBufferPointer(start: native.firstElementAddress + oldCount, count: room)
    var (remainder, written) = newElements._copyContents(initializing: tail)
    native.count = oldCount + written
    if written == room {
      while let element = remainder.next() { append(element) }
    }
  }

  @inlinable
  public mutating func insert(_ newElement: __owned Element, at i: Int) {
    _checkIndex(i)
    let oldCount = count
    _reserveCapacityImpl(minimumCapacity: oldCount + 1, growForAppend: true)
    let native = _native
    let p = native.firstElementAddress + i
    (p + 1).moveInitialize(from: p, count: oldCount - i)
    p.initialize(to: newElement)
    native.count = oldCount + 1
  }

  @inlinable @discardableResult
  public mutating func remove(at index: Int) -> Element {
    _makeMutableAndUnique()
    let native = _native
    let oldCount = native.count
    _precondition(index >= 0 && index < oldCount, "Index out of range")
    let p = native.firstElementAddress + index
    let result = p.move()
    p.moveInitialize(from: p + 1, count: oldCount - index - 1)
    native.count = oldCount - 1
    return result
  }

  @inlinable
  public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
    if !keepCapacity {
      _buffer = _Buffer()
    } else if _buffer.isUniquelyReferenced() {
      let native = _native
      let n = native.count
      native.count = 0
      native.firstElementAddress.deinitialize(count: n)
    } else {
      self = Array(_native: _ContiguousArrayBuffer(_uninitializedCount: 0, minimumCapacity: capacity))
    }
  }

  @inlinable
  public mutating func _customRemoveLast() -> Element? {
    _makeMutableAndUnique()
    let native = _native
    let n = native.count
    _precondition(n > 0, "Can't removeLast from an empty Array")
    native.count = n - 1
    return (native.firstElementAddress + (n - 1)).move()
  }

  @inlinable
  public mutating func popLast() -> Element? {
    if isEmpty { return nil }
    return _customRemoveLast()
  }

  @inlinable
  public mutating func replaceSubrange<C: Collection>(_ subrange: Range<Int>, with newElements: __owned C)
  where C.Element == Element {
    _precondition(subrange.lowerBound >= 0, "Array replace: subrange start is negative")
    _precondition(subrange.upperBound <= count, "Array replace: subrange extends past the end")
    if !_buffer._isNativeTypeChecked { _buffer = _buffer._consumeAndCreateNew() }
    let native = _native
    let oldCount = native.count
    let insertCount = newElements.count
    let newCount = oldCount - (subrange.upperBound - subrange.lowerBound) + insertCount
    if _buffer.isUniquelyReferenced() && native.capacity >= newCount {
      native._replaceInPlace(subrange, with: insertCount, elementsOf: newElements)
    } else {
      self = Array(_native: _ContiguousArrayBuffer._replacingCopy(
        of: native.firstElementAddress, count: oldCount, subrange, with: insertCount,
        elementsOf: newElements,
        minimumCapacity: _growArrayCapacity(oldCapacity: native.capacity, minimumCapacity: newCount,
                                            growForAppend: true)))
    }
  }

  @inlinable
  public static func + (lhs: Array, rhs: Array) -> Array {
    var result = lhs
    result.append(contentsOf: rhs)
    return result
  }

  @inlinable
  public static func += (lhs: inout Array, rhs: Array) {
    lhs.append(contentsOf: rhs)
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
    let n = _native.count
    let base = _native.firstElementAddress
    var inoutBuffer = UnsafeMutableBufferPointer(start: base, count: n)
    defer {
      _precondition(inoutBuffer.baseAddress == base && inoutBuffer.count == n,
                    "Array withUnsafeMutableBufferPointer: replacing the buffer is not allowed")
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
    if _buffer._isNativeTypeChecked { return ContiguousArray(_buffer: _buffer._nativeTypeChecked) }
    return ContiguousArray(_buffer: _buffer._consumeAndCreateNew()._nativeTypeChecked)
  }

  /// The owner and address handed to C for `&array` and `array` arguments.
  @inlinable
  internal var _baseAddressIfContiguous: UnsafeMutablePointer<Element>? {
    return _buffer.firstElementAddressIfContiguous
  }
  @inlinable
  internal var _owner: AnyObject? {
    return _buffer.owner
  }
}

extension Array: ExpressibleByArrayLiteral {
  @inlinable public init(arrayLiteral elements: Element...) {
    self = elements
  }
}

extension Array: RandomAccessCollection, MutableCollection {
  public typealias Index = Int
  public typealias Indices = Range<Int>
  public typealias Iterator = IndexingIterator<Array<Element>>

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
      let wasNativeTypeChecked = _hoistableIsNativeTypeChecked()
      _checkSubscript(index)
      return _getElement(index, wasNativeTypeChecked: wasNativeTypeChecked)
    }
    _modify {
      _makeMutableAndUnique()
      _checkSubscript(index)
      let address = _buffer.mutableFirstElementAddress + index
      defer { _endMutation() }
      yield &address.pointee
    }
  }

  @inlinable public subscript(bounds: Range<Int>) -> ArraySlice<Element> {
    get {
      _precondition(bounds.lowerBound >= 0 && bounds.upperBound <= _buffer.count,
                    "Array index is out of range")
      return ArraySlice(_buffer: _buffer[bounds])
    }
    set {
      _precondition(bounds.lowerBound >= 0 && bounds.upperBound <= _buffer.count,
                    "Array index is out of range")
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
      _buffer._copyContents(subRange: 0..<n, initializing: buffer.baseAddress!)
    }
    return (IndexingIterator(_elements: self, _position: n), n)
  }
}

extension Array: RangeReplaceableCollection {}

extension Array: Equatable where Element: Equatable {
  @inlinable public static func == (lhs: Array<Element>, rhs: Array<Element>) -> Bool {
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

extension Array: Hashable where Element: Hashable {
  @inlinable public func hash(into hasher: inout Hasher) {
    hasher.combine(count)
    for element in self { hasher.combine(element) }
  }
  @inlinable public var hashValue: Int { return _hashValue(for: self) }
}

// ---- array literals ---------------------------------------------------------------
// The compiler builds array literals (and variadic arguments) with these,
// by name: allocate, initialize the elements in place, finalize. When an
// element's evaluation throws, the array is deallocated uninitialized.

@inlinable @inline(__always)
public func _allocateUninitializedArray<Element>(_ builtinCount: Builtin.Word)
  -> (Array<Element>, Builtin.RawPointer) {
  let count = Int(builtinCount)
  if count > 0 {
    let storage = Builtin.allocWithTailElems_1(
      getContiguousArrayStorageType(for: Element.self), builtinCount, Element.self)
    let (array, address) = Array<Element>._adoptStorage(storage, count: count)
    return (array, address._rawValue)
  }
  let (array, address) = Array<Element>._allocateUninitialized(count)
  return (array, address._rawValue)
}

@inlinable
public func _deallocateUninitializedArray<Element>(_ array: __owned Array<Element>) {
  // Nothing was initialized: the storage goes away with no elements.
  var array = array
  array._buffer.mutableCount = 0
}

@inlinable
public func _finalizeUninitializedArray<Element>(_ array: __owned Array<Element>) -> Array<Element> {
  return array
}

public protocol ExpressibleByArrayLiteral {
  associatedtype ArrayLiteralElement
  init(arrayLiteral elements: ArrayLiteralElement...)
}
