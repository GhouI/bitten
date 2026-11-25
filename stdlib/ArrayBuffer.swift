// The storage behind Array, ContiguousArray and ArraySlice.
//
// Programs inline against this representation, so it is Apple's, as the
// Swift ABI and compiled code fix it on x86-64 Darwin:
//
//   ContiguousArray<E>      = _ContiguousArrayBuffer<E> = one reference to a
//                             __ContiguousArrayStorageBase
//   Array<E>                = _ArrayBuffer<E> = _BridgeStorage<...> = one
//                             Builtin.BridgeObject: native storage, or an
//                             NSArray (bit 62 set); bit 1 on native storage
//                             marks elements whose type is not checked yet
//                             (an [AnyObject] cast down lazily)
//   ArraySlice<E>           = _SliceBuffer<E>: owner, subscript base
//                             address, startIndex, endIndex << 1 | isNative
//
// The storage object is a Swift class instance with tail-allocated
// elements: {isa, refcount, count, capacity << 1 | bridgedVerbatim,
// elements...}, the elements at offset 32 rounded up to their alignment.
// Every empty array shares one immortal object, _swiftEmptyArrayStorage,
// which the runtime provides (src/frameworks/swift/array.c).

// ---- small generic helpers ------------------------------------------------------

@inlinable
public func isKnownUniquelyReferenced<T: AnyObject>(_ object: inout T) -> Bool {
  return Bool(Builtin.isUnique(&object))
}

@inlinable
public func isKnownUniquelyReferenced<T: AnyObject>(_ object: inout T?) -> Bool {
  return Bool(Builtin.isUnique(&object))
}

/// Whether values of `T` are class references (or class-bound
/// existentials without witness tables), the elements an NSArray can hold
/// as they are.
@inlinable
internal func _isClassOrObjCExistential<T>(_ x: T.Type) -> Bool {
  let canBe = Int8(Builtin.canBeClass(x))
  if canBe == 0 { return false }
  if canBe == 1 { return true }
  return _swift_isClassOrObjCExistentialType(x)
}

@usableFromInline @_silgen_name("_swift_isClassOrObjCExistentialType")
internal func _swift_isClassOrObjCExistentialType<T>(_ x: T.Type) -> Bool

/// Traps: the Objective-C (NSArray) half of Array is not implemented yet.
@usableFromInline @inline(never)
internal func _arrayCocoaUnimplemented(_ what: StaticString,
                                       file: StaticString = #file, line: UInt = #line) -> Never {
  _assertionFailure("Fatal error", what, file: file, line: line, flags: 0)
}

// ---- _ArrayBody -----------------------------------------------------------------

/// The header of array storage, after the object header.
@frozen @usableFromInline
internal struct _ArrayBody {
  @usableFromInline internal var _count: Int
  @usableFromInline internal var _capacityAndFlags: UInt

  @inlinable
  internal init(count: Int, capacity: Int, elementTypeIsBridgedVerbatim: Bool = false) {
    _count = count
    _capacityAndFlags = UInt(bitPattern: capacity) &<< 1
    if elementTypeIsBridgedVerbatim { _capacityAndFlags |= 1 }
  }
  @inlinable internal init() {
    _count = 0
    _capacityAndFlags = 0
  }
  @inlinable internal var count: Int {
    get { return _count }
    set { _count = newValue }
  }
  @inlinable internal var capacity: Int {
    return Int(bitPattern: _capacityAndFlags &>> 1)
  }
  @inlinable internal var elementTypeIsBridgedVerbatim: Bool {
    get { return _capacityAndFlags & 1 != 0 }
    set { _capacityAndFlags = (_capacityAndFlags & ~1) | (newValue ? 1 : 0) }
  }
}

// ---- storage classes ------------------------------------------------------------

/// On Darwin the root of Swift array storage, which would make it an
/// NSArray subclass. Here it is a plain Swift root class; the instance
/// layout (no stored properties) is the same.
@_fixed_layout @usableFromInline
internal class __SwiftNativeNSArrayWithContiguousStorage {
  @inlinable internal init() {}
  @inlinable deinit {}
}

@_fixed_layout @usableFromInline
internal class __ContiguousArrayStorageBase: __SwiftNativeNSArrayWithContiguousStorage {
  @usableFromInline final internal var countAndCapacity: _ArrayBody

  // Storage is never initialized: it comes from Builtin.allocWithTailElems_1
  // (or is the static empty or constant storage) and the header is written
  // directly.
  @inlinable @nonobjc internal init(_doNotCallMeBase: ()) {
    Builtin.int_trap()
  }

  @inlinable
  internal func canStoreElements(ofDynamicType _: Any.Type) -> Bool {
    Builtin.int_trap()
  }

  /// The element type the storage was created for.
  @inlinable
  internal var staticElementType: Any.Type {
    Builtin.int_trap()
  }

  @inlinable deinit {}
}

/// The class of `_swiftEmptyArrayStorage`.
@_fixed_layout @usableFromInline @_objc_non_lazy_realization
internal final class __EmptyArrayStorage: __ContiguousArrayStorageBase {
  @inlinable @nonobjc internal init(_doNotCallMe: ()) {
    Builtin.int_trap()
  }
  @inlinable
  override internal func canStoreElements(ofDynamicType _: Any.Type) -> Bool {
    return false
  }
  @inlinable
  override internal var staticElementType: Any.Type {
    return Void.self
  }
}

/// The class of array storage the compiler emits as constant data (global
/// array literals at -O); such objects are immortal.
@_fixed_layout @usableFromInline @_objc_non_lazy_realization
internal final class __StaticArrayStorage: __ContiguousArrayStorageBase {
  @inlinable @nonobjc internal init(_doNotCallMe: ()) {
    Builtin.int_trap()
  }
  @inlinable
  override internal func canStoreElements(ofDynamicType _: Any.Type) -> Bool {
    return false
  }
  @inlinable
  override internal var staticElementType: Any.Type {
    Builtin.int_trap()
  }
}

/// Storage for elements of type `Element`; destroys them with itself.
@_fixed_layout @usableFromInline
internal final class _ContiguousArrayStorage<Element>: __ContiguousArrayStorageBase {
  @inlinable deinit {
    let elements = UnsafeMutablePointer<Element>(Builtin.projectTailElems(self, Element.self))
    elements.deinitialize(count: countAndCapacity.count)
  }

  @inlinable
  override internal func canStoreElements(ofDynamicType proposedElementType: Any.Type) -> Bool {
    // Exact type match; subclasses would need the runtime's cast check.
    return ObjectIdentifier(proposedElementType) == ObjectIdentifier(Element.self)
  }

  @inlinable
  override internal var staticElementType: Any.Type {
    return Element.self
  }
}

// The empty-array singleton. Its symbol is data, which Swift cannot name,
// so its address is taken as that of a "function" with the same name: a
// thin function value is the symbol's address.
@usableFromInline @_silgen_name("_swiftEmptyArrayStorage")
internal func _swiftEmptyArrayStorage()

@inlinable
internal var _emptyArrayStorage: __EmptyArrayStorage {
  @inline(__always) get {
    let symbol: @convention(thin) () -> () = _swiftEmptyArrayStorage
    return Builtin.bridgeFromRawPointer(Builtin.reinterpretCast(symbol) as Builtin.RawPointer)
  }
}

/// The storage class to allocate for `Element`.
@inlinable
internal func getContiguousArrayStorageType<Element>(for: Element.Type)
  -> _ContiguousArrayStorage<Element>.Type {
  return _ContiguousArrayStorage<Element>.self
}

// ---- _BridgeStorage -------------------------------------------------------------

// _BridgeStorage itself is in BridgeStorage.swift (shared with Dictionary and Set).

@usableFromInline
internal typealias _ArrayBridgeStorage = _BridgeStorage<__ContiguousArrayStorageBase>

// ---- capacity growth --------------------------------------------------------------

@inlinable
internal func _growArrayCapacity(oldCapacity: Int, minimumCapacity: Int, growForAppend: Bool) -> Int {
  if !growForAppend { return minimumCapacity }
  if minimumCapacity <= oldCapacity { return oldCapacity }
  // Double, so that a run of appends is linear overall.
  let doubled = oldCapacity &* 2
  return doubled > minimumCapacity ? doubled : minimumCapacity
}

// ---- _ContiguousArrayBuffer ------------------------------------------------------

/// A reference to native array storage.
@frozen @usableFromInline
internal struct _ContiguousArrayBuffer<Element> {
  @usableFromInline internal var _storage: __ContiguousArrayStorageBase

  /// The empty buffer.
  @inlinable internal init() {
    _storage = _emptyArrayStorage
  }

  @inlinable internal init(_ storage: __ContiguousArrayStorageBase) {
    _storage = storage
  }

  /// New storage for `uninitializedCount` elements (which the caller
  /// initializes) and room for at least `minimumCapacity`.
  @inlinable
  internal init(_uninitializedCount uninitializedCount: Int, minimumCapacity: Int) {
    let capacity = uninitializedCount > minimumCapacity ? uninitializedCount : minimumCapacity
    if capacity == 0 {
      _storage = _emptyArrayStorage
      return
    }
    _precondition(capacity > 0, "Negative array capacity")
    let storage = Builtin.allocWithTailElems_1(
      getContiguousArrayStorageType(for: Element.self), capacity._builtinWordValue, Element.self)
    _storage = storage
    _initStorageHeader(count: uninitializedCount, capacity: capacity)
  }

  /// Adopts storage allocated for `count` elements (array literals).
  @inlinable
  internal init(count: Int, storage: _ContiguousArrayStorage<Element>) {
    _storage = storage
    _initStorageHeader(count: count, capacity: count)
  }

  @inlinable
  internal func _initStorageHeader(count: Int, capacity: Int) {
    _storage.countAndCapacity = _ArrayBody(
      count: count, capacity: capacity,
      elementTypeIsBridgedVerbatim: _isClassOrObjCExistential(Element.self))
  }

  @inlinable internal var count: Int {
    get { return _storage.countAndCapacity.count }
    nonmutating set { _storage.countAndCapacity.count = newValue }
  }
  @inlinable internal var mutableCount: Int {
    get { return count }
    nonmutating set { count = newValue }
  }
  @inlinable internal var capacity: Int {
    return _storage.countAndCapacity.capacity
  }
  @inlinable internal var mutableCapacity: Int { return capacity }

  @inlinable internal var firstElementAddress: UnsafeMutablePointer<Element> {
    return UnsafeMutablePointer(Builtin.projectTailElems(_storage, Element.self))
  }
  @inlinable internal var mutableFirstElementAddress: UnsafeMutablePointer<Element> {
    return firstElementAddress
  }
  @inlinable internal var firstElementAddressIfContiguous: UnsafeMutablePointer<Element>? {
    return firstElementAddress
  }
  @inlinable internal var subscriptBaseAddress: UnsafeMutablePointer<Element> {
    return firstElementAddress
  }

  @inlinable internal var owner: AnyObject { return _storage }
  @inlinable internal var nativeOwner: AnyObject { return _storage }
  @inlinable internal var identity: UnsafeRawPointer {
    return UnsafeRawPointer(firstElementAddress._rawValue)
  }
  @inlinable internal var arrayPropertyIsNativeTypeChecked: Bool { return true }

  @inlinable internal var startIndex: Int { return 0 }
  @inlinable internal var endIndex: Int { return count }
  @inlinable internal var indices: Range<Int> { return 0..<count }

  @inlinable internal subscript(i: Int) -> Element {
    get { return firstElementAddress[i] }
    nonmutating set { firstElementAddress[i] = newValue }
  }

  @inlinable
  internal mutating func isUniquelyReferenced() -> Bool {
    return Bool(Builtin.isUnique(&_storage))
  }
  @inlinable
  internal mutating func isMutableAndUniquelyReferenced() -> Bool {
    return isUniquelyReferenced()
  }

  @inlinable
  internal func requestNativeBuffer() -> _ContiguousArrayBuffer<Element>? {
    return self
  }

  /// A buffer holding a copy (or, when `bufferIsUnique`, the moved
  /// elements) of this one with room for `minimumCapacity`. A moved-from
  /// buffer is left with count 0.
  @inlinable
  @_specialize(exported: true, where Element == AnyObject)
  internal __consuming func _consumeAndCreateNew(bufferIsUnique: Bool, minimumCapacity: Int,
                                                 growForAppend: Bool) -> _ContiguousArrayBuffer<Element> {
    let newCapacity = _growArrayCapacity(oldCapacity: capacity, minimumCapacity: minimumCapacity,
                                         growForAppend: growForAppend)
    let c = count
    let newBuffer = _ContiguousArrayBuffer<Element>(_uninitializedCount: c, minimumCapacity: newCapacity)
    if c > 0 {
      if bufferIsUnique {
        newBuffer.firstElementAddress.moveInitialize(from: firstElementAddress, count: c)
        count = 0
      } else {
        newBuffer.firstElementAddress.initialize(from: UnsafePointer(firstElementAddress), count: c)
      }
    }
    return newBuffer
  }

  @inlinable
  internal __consuming func _consumeAndCreateNew() -> _ContiguousArrayBuffer<Element> {
    return _consumeAndCreateNew(bufferIsUnique: false, minimumCapacity: 0, growForAppend: false)
  }

  /// Copies `bounds` into `target` (initializing it); returns the end.
  @inlinable @discardableResult
  internal __consuming func _copyContents(subRange bounds: Range<Int>,
                                          initializing target: UnsafeMutablePointer<Element>)
    -> UnsafeMutablePointer<Element> {
    let n = bounds.upperBound - bounds.lowerBound
    target.initialize(from: UnsafePointer(firstElementAddress + bounds.lowerBound), count: n)
    return target + n
  }

  /// A slice of this buffer's storage.
  @inlinable
  internal subscript(bounds: Range<Int>) -> _SliceBuffer<Element> {
    return _SliceBuffer(owner: _storage, subscriptBaseAddress: firstElementAddress,
                        indices: bounds, hasNativeBuffer: true)
  }

  @inlinable
  internal func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(UnsafeBufferPointer(start: UnsafePointer(firstElementAddress), count: count))
  }

  @inlinable
  internal mutating func withUnsafeMutableBufferPointer<R>(
    _ body: (UnsafeMutableBufferPointer<Element>) throws -> R) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(UnsafeMutableBufferPointer(start: firstElementAddress, count: count))
  }

  @inlinable
  internal func _asCocoaArray() -> AnyObject {
    _arrayCocoaUnimplemented("Bridging a Swift array to NSArray is not implemented")
  }

  /// Replaces `subrange` with `newCount` elements of `newValues`, in place:
  /// the buffer must be unique with enough capacity.
  @inlinable
  internal func _replaceInPlace<C: Collection>(_ subrange: Range<Int>, with newCount: Int,
                                               elementsOf newValues: __owned C) where C.Element == Element {
    let oldCount = count
    let eraseCount = subrange.upperBound - subrange.lowerBound
    let growth = newCount - eraseCount
    let holeStart = firstElementAddress + subrange.lowerBound
    holeStart.deinitialize(count: eraseCount)
    let tailCount = oldCount - subrange.upperBound
    if growth != 0 && tailCount > 0 {
      (holeStart + newCount).moveInitialize(from: holeStart + eraseCount, count: tailCount)
    }
    var p = holeStart
    var i = newValues.startIndex
    var written = 0
    while written < newCount {
      p.initialize(to: newValues[i])
      newValues.formIndex(after: &i)
      p += 1
      written += 1
    }
    _precondition(i == newValues.endIndex,
                  "invalid Collection: count differed in successive traversals")
    count = oldCount + growth
  }

  /// New storage holding the `oldCount` elements at `source` (copied) with
  /// `subrange` (0-based) replaced by `newCount` elements of `newValues`.
  @inlinable
  internal static func _replacingCopy<C: Collection>(
    of source: UnsafeMutablePointer<Element>, count oldCount: Int,
    _ subrange: Range<Int>, with newCount: Int, elementsOf newValues: __owned C,
    minimumCapacity: Int
  ) -> _ContiguousArrayBuffer<Element> where C.Element == Element {
    let eraseCount = subrange.upperBound - subrange.lowerBound
    let newTotal = oldCount - eraseCount + newCount
    let result = _ContiguousArrayBuffer<Element>(_uninitializedCount: newTotal,
                                                 minimumCapacity: minimumCapacity)
    var p = result.firstElementAddress
    p.initialize(from: UnsafePointer(source), count: subrange.lowerBound)
    p += subrange.lowerBound
    var i = newValues.startIndex
    var written = 0
    while written < newCount {
      p.initialize(to: newValues[i])
      newValues.formIndex(after: &i)
      p += 1
      written += 1
    }
    _precondition(i == newValues.endIndex,
                  "invalid Collection: count differed in successive traversals")
    p.initialize(from: UnsafePointer(source + subrange.upperBound), count: oldCount - subrange.upperBound)
    return result
  }
}

extension _ContiguousArrayBuffer {
  /// Elements of an ordinary collection, copied into new storage.
  @inlinable
  internal init<C: Collection>(_copying source: C) where C.Element == Element {
    let n = source.count
    self.init(_uninitializedCount: n, minimumCapacity: 0)
    if n == 0 { return }
    let filled = source.withContiguousStorageIfAvailable { buffer -> Bool in
      self.firstElementAddress.initialize(from: buffer.baseAddress!, count: n)
      return true
    }
    if filled == nil {
      var p = firstElementAddress
      var i = source.startIndex
      var k = 0
      while k < n {
        p.initialize(to: source[i])
        source.formIndex(after: &i)
        p += 1
        k += 1
      }
    }
  }
}

// ---- _CocoaArrayWrapper -----------------------------------------------------------

/// An NSArray seen as a collection of objects. Bridging is not implemented
/// yet: nothing creates a non-native array buffer, and these trap.
@frozen @usableFromInline
internal struct _CocoaArrayWrapper: RandomAccessCollection {
  @usableFromInline internal typealias Indices = Range<Int>
  @usableFromInline internal var buffer: AnyObject

  @inlinable internal init(_ buffer: AnyObject) { self.buffer = buffer }

  @inlinable internal var startIndex: Int { return 0 }
  @usableFromInline internal var endIndex: Int {
    _arrayCocoaUnimplemented("NSArray bridging is not implemented")
  }
  @usableFromInline internal subscript(i: Int) -> AnyObject {
    _arrayCocoaUnimplemented("NSArray bridging is not implemented")
  }
  @usableFromInline internal subscript(bounds: Range<Int>) -> _SliceBuffer<AnyObject> {
    _arrayCocoaUnimplemented("NSArray bridging is not implemented")
  }
  @usableFromInline
  internal func _copyContents(subRange bounds: Range<Int>,
                              initializing target: UnsafeMutablePointer<AnyObject>)
    -> UnsafeMutablePointer<AnyObject> {
    _arrayCocoaUnimplemented("NSArray bridging is not implemented")
  }
}

// ---- _ArrayBuffer ------------------------------------------------------------------

/// Array's buffer: native storage, possibly flagged as not type-checked,
/// or an NSArray.
@frozen @usableFromInline
internal struct _ArrayBuffer<Element> {
  @usableFromInline internal typealias NativeBuffer = _ContiguousArrayBuffer<Element>
  @usableFromInline internal var _storage: _ArrayBridgeStorage

  @inlinable internal init() {
    _storage = _ArrayBridgeStorage(native: _emptyArrayStorage)
  }
  @inlinable internal init(storage: _ArrayBridgeStorage) {
    _storage = storage
  }
  @inlinable internal init(_buffer source: NativeBuffer, shiftedToStartIndex: Int) {
    _precondition(shiftedToStartIndex == 0, "shiftedToStartIndex must be 0")
    _storage = _ArrayBridgeStorage(native: source._storage)
  }
  @inlinable internal init(nsArray: AnyObject) {
    _storage = _ArrayBridgeStorage(objC: nsArray)
  }

  @inlinable internal var _isNative: Bool {
    if !_isClassOrObjCExistential(Element.self) { return true }
    return _storage.isNative
  }
  @inlinable internal var _isNativeTypeChecked: Bool {
    if !_isClassOrObjCExistential(Element.self) { return true }
    return _storage.isUnflaggedNative
  }
  @inlinable internal var arrayPropertyIsNativeTypeChecked: Bool { return _isNativeTypeChecked }
  @inlinable internal var needsElementTypeCheck: Bool { return !_isNativeTypeChecked }

  /// The native buffer (also when flagged).
  @inlinable internal var _native: NativeBuffer {
    return NativeBuffer(_storage.nativeInstance)
  }
  /// The native buffer, when it is known to be unflagged native.
  @inlinable internal var _nativeTypeChecked: NativeBuffer {
    return NativeBuffer(_storage.nativeInstance)
  }
  @inlinable internal var _nonNative: _CocoaArrayWrapper {
    return _CocoaArrayWrapper(_storage.objCInstance)
  }

  @inlinable internal var count: Int {
    get { return _isNative ? _native.count : _nonNative.endIndex }
    nonmutating set { _native.count = newValue }
  }
  @inlinable internal var mutableCount: Int {
    get { return _nativeTypeChecked.count }
    nonmutating set { _nativeTypeChecked.count = newValue }
  }
  @inlinable internal var capacity: Int {
    return _isNative ? _native.capacity : _nonNative.endIndex
  }
  @inlinable internal var mutableCapacity: Int { return _nativeTypeChecked.capacity }
  @inlinable internal var firstElementAddress: UnsafeMutablePointer<Element> {
    return _native.firstElementAddress
  }
  @inlinable internal var mutableFirstElementAddress: UnsafeMutablePointer<Element> {
    return _nativeTypeChecked.firstElementAddress
  }
  @inlinable internal var firstElementAddressIfContiguous: UnsafeMutablePointer<Element>? {
    return _isNative ? firstElementAddress : nil
  }
  @inlinable internal var subscriptBaseAddress: UnsafeMutablePointer<Element> {
    return _native.firstElementAddress
  }
  @inlinable internal var owner: AnyObject {
    return _isNative ? _native._storage : _nonNative.buffer
  }
  @inlinable internal var nativeOwner: AnyObject { return _native._storage }
  @inlinable internal var identity: UnsafeRawPointer {
    if _isNative { return _native.identity }
    return UnsafeRawPointer(Builtin.bridgeToRawPointer(_nonNative.buffer))
  }

  @inlinable internal var startIndex: Int { return 0 }
  @inlinable internal var endIndex: Int { return count }
  @inlinable internal var indices: Range<Int> { return 0..<count }

  @inlinable
  internal mutating func isUniquelyReferenced() -> Bool {
    return _storage.isUniquelyReferencedUnflaggedNative()
  }
  @inlinable
  internal mutating func isMutableAndUniquelyReferenced() -> Bool {
    return isUniquelyReferenced()
  }

  @inlinable
  internal func requestNativeBuffer() -> NativeBuffer? {
    return _isNativeTypeChecked ? _nativeTypeChecked : nil
  }

  // -- elements

  @inlinable
  internal func getElement(_ i: Int, wasNativeTypeChecked: Bool) -> Element {
    if _fastPath(wasNativeTypeChecked) { return _nativeTypeChecked[i] }
    return unsafeBitCast(_getElementSlowPath(i), to: Element.self)
  }

  /// An element of a flagged or Objective-C buffer, type-checked.
  @inline(never)
  @_specialize(exported: true, where Element == AnyObject)
  @usableFromInline
  internal func _getElementSlowPath(_ i: Int) -> AnyObject {
    let element: AnyObject
    if _isNative {
      _precondition(i >= 0 && i < _native.count, "Index out of range")
      element = UnsafeMutablePointer<AnyObject>(_native.firstElementAddress._rawValue)[i]
    } else {
      element = _nonNative[i]
    }
    _precondition(_arrayElementIsOfType(element, Element.self),
                  "NSArray element failed to match the Swift Array Element type")
    return element
  }

  /// Checks the type of element `index` of a buffer whose element types
  /// are not known to be right.
  @usableFromInline @inline(never)
  internal func _typeCheckSlowPath(_ index: Int) {
    if _isNative {
      let element = UnsafeMutablePointer<AnyObject>(_native.firstElementAddress._rawValue)[index]
      _precondition(_arrayElementIsOfType(element, Element.self),
                    "Down-casted Array element failed to match the target type")
    } else {
      let element = _nonNative[index]
      _precondition(_arrayElementIsOfType(element, Element.self),
                    "NSArray element failed to match the Swift Array Element type")
    }
  }

  @inlinable
  internal func _typeCheck(_ subRange: Range<Int>) {
    if !_isClassOrObjCExistential(Element.self) { return }
    if _slowPath(needsElementTypeCheck) {
      var i = subRange.lowerBound
      while i < subRange.upperBound {
        _typeCheckSlowPath(i)
        i += 1
      }
    }
  }

  @inlinable
  internal subscript(i: Int) -> Element {
    get { return getElement(i, wasNativeTypeChecked: _isNativeTypeChecked) }
    nonmutating set { _nativeTypeChecked[i] = newValue }
  }

  @inlinable
  internal func _checkValidSubscript(_ index: Int) {
    _precondition(index >= 0 && index < count, "Index out of range")
  }

  // -- copies

  @inlinable @discardableResult
  internal __consuming func _copyContents(subRange bounds: Range<Int>,
                                          initializing target: UnsafeMutablePointer<Element>)
    -> UnsafeMutablePointer<Element> {
    _typeCheck(bounds)
    if _fastPath(_isNative) {
      return _native._copyContents(subRange: bounds, initializing: target)
    }
    let end = _nonNative._copyContents(subRange: bounds,
                                       initializing: UnsafeMutablePointer<AnyObject>(target._rawValue))
    return UnsafeMutablePointer<Element>(end._rawValue)
  }

  /// A new native buffer with this one's elements, moved when unique.
  @inline(never)
  @_specialize(exported: true, where Element == AnyObject)
  @usableFromInline
  internal __consuming func _consumeAndCreateNew(bufferIsUnique: Bool, minimumCapacity: Int,
                                                 growForAppend: Bool) -> _ArrayBuffer<Element> {
    if _isNativeTypeChecked {
      let native = _nativeTypeChecked._consumeAndCreateNew(
        bufferIsUnique: bufferIsUnique, minimumCapacity: minimumCapacity, growForAppend: growForAppend)
      return _ArrayBuffer(_buffer: native, shiftedToStartIndex: 0)
    }
    // Flagged or Objective-C: copy, checking each element's type.
    let c = count
    let newCapacity = _growArrayCapacity(oldCapacity: capacity, minimumCapacity: minimumCapacity,
                                         growForAppend: growForAppend)
    let native = NativeBuffer(_uninitializedCount: c, minimumCapacity: newCapacity)
    _copyContents(subRange: 0..<c, initializing: native.firstElementAddress)
    return _ArrayBuffer(_buffer: native, shiftedToStartIndex: 0)
  }

  @inlinable
  internal __consuming func _consumeAndCreateNew() -> _ArrayBuffer<Element> {
    return _consumeAndCreateNew(bufferIsUnique: false, minimumCapacity: 0, growForAppend: false)
  }

  @inlinable
  internal subscript(bounds: Range<Int>) -> _SliceBuffer<Element> {
    _typeCheck(bounds)
    if _fastPath(_isNative) { return _native[bounds] }
    let slice = _nonNative[bounds]
    return unsafeBitCast(slice, to: _SliceBuffer<Element>.self)
  }

  @inlinable
  internal func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows -> R {
    if _fastPath(_isNativeTypeChecked) {
      return try _nativeTypeChecked.withUnsafeBufferPointer(body)
    }
    return try ContiguousArray(_buffer: _consumeAndCreateNew()._nativeTypeChecked).withUnsafeBufferPointer(body)
  }
}

/// Whether an object taken from an untyped buffer is an `Element`.
@inlinable
internal func _arrayElementIsOfType<Element>(_ object: AnyObject, _: Element.Type) -> Bool {
  return (object as Any) is Element
}

// ---- _SliceBuffer ------------------------------------------------------------------

/// ArraySlice's buffer: a range of some storage's elements.
@frozen @usableFromInline
internal struct _SliceBuffer<Element> {
  @usableFromInline internal typealias NativeBuffer = _ContiguousArrayBuffer<Element>

  @usableFromInline internal var owner: AnyObject
  /// The address of the element at index 0 (startIndex is usually not 0).
  @usableFromInline internal let subscriptBaseAddress: UnsafeMutablePointer<Element>
  @usableFromInline internal var startIndex: Int
  /// endIndex << 1 | (owner is native storage)
  @usableFromInline internal var endIndexAndFlags: UInt

  @inlinable
  internal init(owner: AnyObject, subscriptBaseAddress: UnsafeMutablePointer<Element>,
                startIndex: Int, endIndexAndFlags: UInt) {
    self.owner = owner
    self.subscriptBaseAddress = subscriptBaseAddress
    self.startIndex = startIndex
    self.endIndexAndFlags = endIndexAndFlags
  }

  @inlinable
  internal init(owner: AnyObject, subscriptBaseAddress: UnsafeMutablePointer<Element>,
                indices: Range<Int>, hasNativeBuffer: Bool) {
    self.owner = owner
    self.subscriptBaseAddress = subscriptBaseAddress
    self.startIndex = indices.lowerBound
    self.endIndexAndFlags = (UInt(bitPattern: indices.upperBound) &<< 1) | (hasNativeBuffer ? 1 : 0)
  }

  @inlinable internal init() {
    let empty = _ContiguousArrayBuffer<Element>()
    self.owner = empty.owner
    self.subscriptBaseAddress = empty.firstElementAddress
    self.startIndex = 0
    self.endIndexAndFlags = 1
  }

  /// A slice over all of `buffer`, its first element at `shiftedToStartIndex`.
  @inlinable
  internal init(_buffer buffer: NativeBuffer, shiftedToStartIndex: Int) {
    let shift = 0 - shiftedToStartIndex
    self.init(owner: buffer.owner, subscriptBaseAddress: buffer.firstElementAddress + shift,
              indices: shiftedToStartIndex..<(shiftedToStartIndex + buffer.count),
              hasNativeBuffer: true)
  }

  @inlinable internal var _hasNativeBuffer: Bool { return endIndexAndFlags & 1 != 0 }
  @inlinable internal var endIndex: Int {
    get { return Int(bitPattern: endIndexAndFlags &>> 1) }
    set { endIndexAndFlags = (UInt(bitPattern: newValue) &<< 1) | (_hasNativeBuffer ? 1 : 0) }
  }
  @inlinable internal var count: Int {
    get { return endIndex - startIndex }
    set { endIndex = startIndex + newValue }
  }
  @inlinable internal var indices: Range<Int> { return startIndex..<endIndex }
  @inlinable internal var firstElementAddress: UnsafeMutablePointer<Element> {
    return subscriptBaseAddress + startIndex
  }
  @inlinable internal var firstElementAddressIfContiguous: UnsafeMutablePointer<Element>? {
    return firstElementAddress
  }
  @inlinable internal var identity: UnsafeRawPointer {
    return UnsafeRawPointer(firstElementAddress._rawValue)
  }
  @inlinable internal var nativeBuffer: NativeBuffer {
    return NativeBuffer(Builtin.castReference(owner) as __ContiguousArrayStorageBase)
  }
  /// The capacity available to this slice without reallocating: only when
  /// it ends where its native storage's elements end.
  @inlinable internal var capacity: Int {
    let c = count
    if _hasNativeBuffer {
      let native = nativeBuffer
      let nativeEnd = native.firstElementAddress + native.count
      if firstElementAddress + c == nativeEnd {
        return c + (native.capacity - native.count)
      }
    }
    return c
  }

  @inlinable internal subscript(position: Int) -> Element {
    get { return subscriptBaseAddress[position] }
    nonmutating set { subscriptBaseAddress[position] = newValue }
  }

  @inlinable internal subscript(bounds: Range<Int>) -> _SliceBuffer<Element> {
    return _SliceBuffer(owner: owner, subscriptBaseAddress: subscriptBaseAddress,
                        indices: bounds, hasNativeBuffer: _hasNativeBuffer)
  }

  @inlinable
  internal mutating func isUniquelyReferenced() -> Bool {
    return Bool(Builtin.isUnique(&owner))
  }

  /// Unique native storage whose elements are exactly this slice's, so
  /// that the slice can change its count in place.
  @inlinable
  internal mutating func _ownsWholeNativeStorage() -> Bool {
    if !_hasNativeBuffer || !isUniquelyReferenced() { return false }
    let native = nativeBuffer
    return native.firstElementAddress == firstElementAddress && native.count == count
  }

  @inlinable @discardableResult
  internal __consuming func _copyContents(subRange bounds: Range<Int>,
                                          initializing target: UnsafeMutablePointer<Element>)
    -> UnsafeMutablePointer<Element> {
    let n = bounds.upperBound - bounds.lowerBound
    target.initialize(from: UnsafePointer(subscriptBaseAddress + bounds.lowerBound), count: n)
    return target + n
  }

  /// The slice's elements in new native storage.
  @inlinable
  internal func _copyToNative(minimumCapacity: Int = 0) -> NativeBuffer {
    let c = count
    let result = NativeBuffer(_uninitializedCount: c, minimumCapacity: minimumCapacity)
    _copyContents(subRange: indices, initializing: result.firstElementAddress)
    return result
  }

  @inlinable
  internal func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(UnsafeBufferPointer(start: UnsafePointer(firstElementAddress), count: count))
  }
}
