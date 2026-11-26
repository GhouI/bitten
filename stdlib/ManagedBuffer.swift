// ManagedBuffer: a class instance holding a header followed by a
// tail-allocated array of elements. Fixed layout like Apple's (programs
// subclass it and inline its accessors): the object header, the stored
// `header`, then the elements.

@_silgen_name("malloc_size") @usableFromInline
internal func _bitten_malloc_size(_ p: UnsafeRawPointer) -> Int

@_fixed_layout
open class ManagedBuffer<Header, Element> {
  /// The stored header.
  public final var header: Header

  @usableFromInline
  internal init(_doNotCallMe: ()) {
    Builtin.unreachable()
  }

  @inlinable
  deinit {}

  /// A new buffer with room for at least `minimumCapacity` elements and a
  /// header made by `factory` (which sees the buffer, header uninitialized).
  @inlinable
  public final class func create(
    minimumCapacity: Int,
    makingHeaderWith factory: (ManagedBuffer<Header, Element>) throws -> Header
  ) rethrows -> ManagedBuffer<Header, Element> {
    let p = Builtin.allocWithTailElems_1(self, minimumCapacity._builtinWordValue, Element.self)
    let initHeaderVal = try factory(p)
    p.headerAddress.initialize(to: initHeaderVal)
    _fixLifetime(p)
    return p
  }

  /// The number of elements that fit (at least the minimum asked for).
  @inlinable
  public final var capacity: Int {
    let storageAddr = UnsafeMutableRawPointer(Builtin.bridgeToRawPointer(self))
    let endAddr = storageAddr + _bitten_malloc_size(UnsafeRawPointer(storageAddr))
    let firstRaw = UnsafeMutableRawPointer(firstElementAddress)
    return (endAddr - firstRaw) / MemoryLayout<Element>.stride
  }

  @inlinable
  internal final var firstElementAddress: UnsafeMutablePointer<Element> {
    return UnsafeMutablePointer(Builtin.projectTailElems(self, Element.self))
  }

  @inlinable
  internal final var headerAddress: UnsafeMutablePointer<Header> {
    return UnsafeMutablePointer<Header>(Builtin.addressof(&header))
  }

  @inlinable
  public final func withUnsafeMutablePointerToHeader<R>(_ body: (UnsafeMutablePointer<Header>) throws -> R) rethrows -> R {
    return try withUnsafeMutablePointers { (v, _) in return try body(v) }
  }

  @inlinable
  public final func withUnsafeMutablePointerToElements<R>(_ body: (UnsafeMutablePointer<Element>) throws -> R) rethrows -> R {
    return try withUnsafeMutablePointers { return try body($1) }
  }

  @inlinable
  public final func withUnsafeMutablePointers<R>(
    _ body: (UnsafeMutablePointer<Header>, UnsafeMutablePointer<Element>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(headerAddress, firstElementAddress)
  }
}

@_silgen_name("swift_bufferAllocate") @usableFromInline
internal func _bitten_bufferAllocate(_ bufferType: AnyClass, _ size: Int, _ alignMask: Int) -> AnyObject

/// A buffer object's header and elements addressed directly; the object
/// can be any class (tail allocation sized at creation). Fixed layout like
/// Apple's: one native object reference.
@frozen
public struct ManagedBufferPointer<Header, Element> {
  @usableFromInline internal var _nativeBuffer: Builtin.NativeObject

  /// Header after the object header; elements after the header.
  @inlinable internal static var _headerOffset: Int {
    let align = MemoryLayout<Header>.alignment
    return (16 + align - 1) & ~(align - 1)
  }
  @inlinable internal static var _elementOffset: Int {
    let align = MemoryLayout<Element>.alignment
    return (_headerOffset + MemoryLayout<Header>.size + align - 1) & ~(align - 1)
  }
  @inlinable internal static var _alignmentMask: Int {
    return Swift.max(Swift.max(MemoryLayout<Header>.alignment, MemoryLayout<Element>.alignment), 16) - 1
  }

  public init(bufferClass: AnyClass, minimumCapacity: Int,
              makingHeaderWith factory: (_ buffer: AnyObject, _ capacity: (AnyObject) -> Int) throws -> Header) rethrows {
    let size = ManagedBufferPointer._elementOffset + Swift.max(minimumCapacity, 0) * MemoryLayout<Element>.stride
    let object = _bitten_bufferAllocate(bufferClass, size, ManagedBufferPointer._alignmentMask)
    self._nativeBuffer = Builtin.unsafeCastToNativeObject(object)
    let header = try factory(object) { o in
      let bytes = _bitten_malloc_size(UnsafeRawPointer(Builtin.bridgeToRawPointer(o)))
      return (bytes - ManagedBufferPointer._elementOffset) / MemoryLayout<Element>.stride
    }
    _headerPointer.initialize(to: header)
  }

  public init(unsafeBufferObject buffer: AnyObject) {
    self._nativeBuffer = Builtin.unsafeCastToNativeObject(buffer)
  }

  @inlinable internal init(_nativeBuffer buffer: Builtin.NativeObject) { self._nativeBuffer = buffer }

  internal var _address: UnsafeMutableRawPointer {
    return UnsafeMutableRawPointer(Builtin.bridgeToRawPointer(_nativeBuffer))
  }
  @usableFromInline internal var _headerPointer: UnsafeMutablePointer<Header> {
    return (_address + ManagedBufferPointer._headerOffset).assumingMemoryBound(to: Header.self)
  }
  @usableFromInline internal var _elementPointer: UnsafeMutablePointer<Element> {
    return (_address + ManagedBufferPointer._elementOffset).assumingMemoryBound(to: Element.self)
  }

  public var header: Header {
    _read { yield _headerPointer.pointee }
    nonmutating _modify { yield &_headerPointer.pointee }
  }
  public var buffer: AnyObject { return Builtin.castFromNativeObject(_nativeBuffer) }
  public var capacity: Int {
    let bytes = _bitten_malloc_size(UnsafeRawPointer(_address))
    return (bytes - ManagedBufferPointer._elementOffset) / MemoryLayout<Element>.stride
  }

  public func withUnsafeMutablePointerToHeader<R>(_ body: (UnsafeMutablePointer<Header>) throws -> R) rethrows -> R {
    defer { _fixLifetime(_nativeBuffer) }
    return try body(_headerPointer)
  }
  public func withUnsafeMutablePointerToElements<R>(_ body: (UnsafeMutablePointer<Element>) throws -> R) rethrows -> R {
    defer { _fixLifetime(_nativeBuffer) }
    return try body(_elementPointer)
  }
  public func withUnsafeMutablePointers<R>(
    _ body: (UnsafeMutablePointer<Header>, UnsafeMutablePointer<Element>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(_nativeBuffer) }
    return try body(_headerPointer, _elementPointer)
  }

  public mutating func isUniqueReference() -> Bool {
    return Bool(Builtin.isUnique(&_nativeBuffer))
  }
}

extension ManagedBufferPointer: Equatable {
  public static func == (lhs: ManagedBufferPointer, rhs: ManagedBufferPointer) -> Bool {
    return lhs._address == rhs._address
  }
}
