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
