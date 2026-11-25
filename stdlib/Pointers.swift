// MemoryLayout and the unsafe pointer family.
//
// Apple declares the typed pointers over `Pointee: ~Copyable` but keeps the
// pre-Swift-6 mangling of their members (@_preInverseGenerics). Declaring
// them as plain generics here produces exactly those older names.

@frozen public enum MemoryLayout<T> {
  @_transparent public static var size: Int { return Int(Builtin.sizeof(T.self)) }
  @_transparent public static var stride: Int { return Int(Builtin.strideof(T.self)) }
  @_transparent public static var alignment: Int { return Int(Builtin.alignof(T.self)) }
}
extension MemoryLayout {
  @_transparent public static func size(ofValue value: T) -> Int { return MemoryLayout.size }
  @_transparent public static func stride(ofValue value: T) -> Int { return MemoryLayout.stride }
  @_transparent public static func alignment(ofValue value: T) -> Int { return MemoryLayout.alignment }
}


// ---- the common pointer protocol ----------------------------------------------

public protocol _Pointer: Hashable, Strideable {
  typealias Distance = Int
  associatedtype Pointee
  var _rawValue: Builtin.RawPointer { get }
  init(_ _rawValue: Builtin.RawPointer)
}

extension _Pointer {
  @_transparent public init(_ other: OpaquePointer) { self.init(other._rawValue) }
  @_transparent public init?(_ other: OpaquePointer?) {
    guard let unwrapped = other else { return nil }
    self.init(unwrapped._rawValue)
  }
  @_transparent public init?(bitPattern: Int) {
    if bitPattern == 0 { return nil }
    self.init(Builtin.inttoptr_Word(bitPattern._builtinWordValue))
  }
  @_transparent public init?(bitPattern: UInt) {
    if bitPattern == 0 { return nil }
    self.init(Builtin.inttoptr_Word(bitPattern._builtinWordValue))
  }
  @_transparent public init(_ other: Self) { self.init(other._rawValue) }
  @_transparent public init?(_ other: Self?) {
    guard let unwrapped = other else { return nil }
    self.init(unwrapped._rawValue)
  }
  @_transparent public static func == (lhs: Self, rhs: Self) -> Bool {
    return Bool(Builtin.cmp_eq_RawPointer(lhs._rawValue, rhs._rawValue))
  }
  @_transparent public static func < (lhs: Self, rhs: Self) -> Bool {
    return Bool(Builtin.cmp_ult_RawPointer(lhs._rawValue, rhs._rawValue))
  }
  @_transparent public func successor() -> Self { return advanced(by: 1) }
  @_transparent public func predecessor() -> Self { return advanced(by: -1) }
  @_transparent public func distance(to end: Self) -> Int {
    return (Int(bitPattern: end) - Int(bitPattern: self)) / MemoryLayout<Pointee>.stride
  }
  @_transparent public func advanced(by n: Int) -> Self {
    return Self(Builtin.gep_Word(_rawValue, n._builtinWordValue, Pointee.self))
  }
  @inlinable public func hash(into hasher: inout Hasher) {
    hasher.combine(UInt(bitPattern: self))
  }
}

extension Int {
  @_transparent public init<P: _Pointer>(bitPattern pointer: P?) {
    if let pointer = pointer { self = Int(Builtin.ptrtoint_Word(pointer._rawValue)) } else { self = 0 }
  }
}
extension UInt {
  @_transparent public init<P: _Pointer>(bitPattern pointer: P?) {
    if let pointer = pointer { self = UInt(Builtin.ptrtoint_Word(pointer._rawValue)) } else { self = 0 }
  }
}

extension Strideable where Self: _Pointer {
  @_transparent public static func + (lhs: Self, rhs: Self.Stride) -> Self { return lhs.advanced(by: rhs) }
  @_transparent public static func + (lhs: Self.Stride, rhs: Self) -> Self { return rhs.advanced(by: lhs) }
  @_transparent public static func - (lhs: Self, rhs: Self.Stride) -> Self { return lhs.advanced(by: 0 - rhs) }
  @_transparent public static func - (lhs: Self, rhs: Self) -> Self.Stride { return rhs.distance(to: lhs) }
  @_transparent public static func += (lhs: inout Self, rhs: Self.Stride) { lhs = lhs.advanced(by: rhs) }
  @_transparent public static func -= (lhs: inout Self, rhs: Self.Stride) { lhs = lhs.advanced(by: 0 - rhs) }
}

// ---- OpaquePointer ------------------------------------------------------------------

@frozen public struct OpaquePointer {
  @usableFromInline internal var _rawValue: Builtin.RawPointer
  @usableFromInline @_transparent internal init(_ v: Builtin.RawPointer) { _rawValue = v }
  @_transparent public init?(bitPattern: Int) {
    if bitPattern == 0 { return nil }
    _rawValue = Builtin.inttoptr_Word(bitPattern._builtinWordValue)
  }
  @_transparent public init?(bitPattern: UInt) {
    if bitPattern == 0 { return nil }
    _rawValue = Builtin.inttoptr_Word(bitPattern._builtinWordValue)
  }
  @_transparent public init<T>(_ from: UnsafePointer<T>) { _rawValue = from._rawValue }
  @_transparent public init?<T>(_ from: UnsafePointer<T>?) {
    guard let unwrapped = from else { return nil }
    _rawValue = unwrapped._rawValue
  }
  @_transparent public init<T>(_ from: UnsafeMutablePointer<T>) { _rawValue = from._rawValue }
  @_transparent public init?<T>(_ from: UnsafeMutablePointer<T>?) {
    guard let unwrapped = from else { return nil }
    _rawValue = unwrapped._rawValue
  }
  @_transparent public init(_ from: UnsafeRawPointer) { _rawValue = from._rawValue }
  @_transparent public init(_ from: UnsafeMutableRawPointer) { _rawValue = from._rawValue }
}
extension OpaquePointer: Equatable {
  @inlinable public static func == (lhs: OpaquePointer, rhs: OpaquePointer) -> Bool {
    return Bool(Builtin.cmp_eq_RawPointer(lhs._rawValue, rhs._rawValue))
  }
}
extension OpaquePointer: Hashable {
  @inlinable public func hash(into hasher: inout Hasher) {
    hasher.combine(Int(Builtin.ptrtoint_Word(_rawValue)))
  }
}

// ---- typed pointers ---------------------------------------------------------------

@frozen public struct UnsafePointer<Pointee>: _Pointer {
  public typealias Distance = Int
  public let _rawValue: Builtin.RawPointer
  @_transparent public init(_ _rawValue: Builtin.RawPointer) { self._rawValue = _rawValue }
  // In the type itself: the compiler looks `pointee` up here for implicit
  // pointer conversions.
  @inlinable public var pointee: Pointee {
    @_transparent unsafeAddress { return self }
  }
}
extension UnsafePointer {
  @_transparent public init(_ other: UnsafeMutablePointer<Pointee>) { _rawValue = other._rawValue }
  @_transparent public init?(_ other: UnsafeMutablePointer<Pointee>?) {
    guard let unwrapped = other else { return nil }
    _rawValue = unwrapped._rawValue
  }
  @inlinable public subscript(i: Int) -> Pointee {
    @_transparent unsafeAddress { return self + i }
  }
  @inlinable public func deallocate() { Builtin.deallocRaw(_rawValue, (-1)._builtinWordValue, (0)._builtinWordValue) }
  @inlinable public func withMemoryRebound<T, Result>(to type: T.Type, capacity count: Int,
                                                     _ body: (UnsafePointer<T>) throws -> Result) rethrows -> Result {
    return try body(UnsafePointer<T>(_rawValue))
  }
}

@frozen public struct UnsafeMutablePointer<Pointee>: _Pointer {
  public typealias Distance = Int
  public let _rawValue: Builtin.RawPointer
  @_transparent public init(_ _rawValue: Builtin.RawPointer) { self._rawValue = _rawValue }
  @inlinable public var pointee: Pointee {
    @_transparent unsafeAddress { return UnsafePointer(_rawValue) }
    @_transparent nonmutating unsafeMutableAddress { return self }
  }
}
extension UnsafeMutablePointer {
  @_transparent public init(mutating other: UnsafePointer<Pointee>) { _rawValue = other._rawValue }
  @_transparent public init?(mutating other: UnsafePointer<Pointee>?) {
    guard let unwrapped = other else { return nil }
    _rawValue = unwrapped._rawValue
  }
  @_transparent public init(_ other: UnsafeMutablePointer<Pointee>) { _rawValue = other._rawValue }

  @inlinable public static func allocate(capacity count: Int) -> UnsafeMutablePointer<Pointee> {
    let size = MemoryLayout<Pointee>.stride * count
    // Like Apple's: at least word alignment, so the memory can be handed to
    // C allocators' callers and freed with deallocate().
    // Builtin.allocRaw takes an alignment (0: the allocator's default) and
    // becomes swift_slowAlloc(size, alignment - 1).
    var align = Builtin.alignof(Pointee.self)
    if Int(align) <= MemoryLayout<Int>.alignment { align = (0)._builtinWordValue }
    let raw = Builtin.allocRaw(size._builtinWordValue, align)
    Builtin.bindMemory(raw, count._builtinWordValue, Pointee.self)
    return UnsafeMutablePointer(raw)
  }
  @inlinable public func deallocate() {
    Builtin.deallocRaw(_rawValue, (-1)._builtinWordValue, (0)._builtinWordValue)
  }
  @inlinable public subscript(i: Int) -> Pointee {
    @_transparent unsafeAddress { return UnsafePointer(self + i) }
    @_transparent nonmutating unsafeMutableAddress { return self + i }
  }
  @inlinable public func initialize(to value: Pointee) {
    Builtin.initialize(value, _rawValue)
  }
  @inlinable public func initialize(repeating repeatedValue: Pointee, count: Int) {
    _collectionPrecondition(count >= 0)
    var i = 0
    while i < count {
      Builtin.initialize(repeatedValue, (self + i)._rawValue)
      i += 1
    }
  }
  @inlinable public func initialize(from source: UnsafePointer<Pointee>, count: Int) {
    _collectionPrecondition(count >= 0)
    Builtin.copyArray(Pointee.self, self._rawValue, source._rawValue, count._builtinWordValue)
  }
  @inlinable public func move() -> Pointee {
    return Builtin.take(_rawValue)
  }
  @inlinable public func moveInitialize(from source: UnsafeMutablePointer, count: Int) {
    _collectionPrecondition(count >= 0)
    if self < source || self >= source + count {
      Builtin.takeArrayFrontToBack(Pointee.self, self._rawValue, source._rawValue, count._builtinWordValue)
    } else if self != source {
      Builtin.takeArrayBackToFront(Pointee.self, self._rawValue, source._rawValue, count._builtinWordValue)
    }
  }
  @inlinable public func moveUpdate(from source: UnsafeMutablePointer, count: Int) {
    _collectionPrecondition(count >= 0)
    Builtin.assignTakeArray(Pointee.self, self._rawValue, source._rawValue, count._builtinWordValue)
  }
  @inlinable public func update(from source: UnsafePointer<Pointee>, count: Int) {
    _collectionPrecondition(count >= 0)
    Builtin.assignCopyArrayNoAlias(Pointee.self, self._rawValue, source._rawValue, count._builtinWordValue)
  }
  @inlinable public func update(repeating repeatedValue: Pointee, count: Int) {
    var i = 0
    while i < count { self[i] = repeatedValue; i += 1 }
  }
  @inlinable @discardableResult
  public func deinitialize(count: Int) -> UnsafeMutableRawPointer {
    _collectionPrecondition(count >= 0)
    Builtin.destroyArray(Pointee.self, _rawValue, count._builtinWordValue)
    return UnsafeMutableRawPointer(self)
  }
  @inlinable public func withMemoryRebound<T, Result>(to type: T.Type, capacity count: Int,
                                                     _ body: (UnsafeMutablePointer<T>) throws -> Result) rethrows -> Result {
    return try body(UnsafeMutablePointer<T>(_rawValue))
  }
}

// ---- raw pointers ----------------------------------------------------------------

@frozen public struct UnsafeRawPointer: _Pointer {
  public typealias Pointee = UInt8
  public let _rawValue: Builtin.RawPointer
  @_transparent public init(_ _rawValue: Builtin.RawPointer) { self._rawValue = _rawValue }
}
extension UnsafeRawPointer {
  @_transparent public init<T>(_ other: UnsafePointer<T>) { _rawValue = other._rawValue }
  @_transparent public init?<T>(_ other: UnsafePointer<T>?) {
    guard let unwrapped = other else { return nil }
    _rawValue = unwrapped._rawValue
  }
  @_transparent public init<T>(_ other: UnsafeMutablePointer<T>) { _rawValue = other._rawValue }
  @_transparent public init?<T>(_ other: UnsafeMutablePointer<T>?) {
    guard let unwrapped = other else { return nil }
    _rawValue = unwrapped._rawValue
  }
  @_transparent public init(_ other: UnsafeMutableRawPointer) { _rawValue = other._rawValue }
  @_transparent public init?(_ other: UnsafeMutableRawPointer?) {
    guard let unwrapped = other else { return nil }
    _rawValue = unwrapped._rawValue
  }
  @inlinable public func deallocate() {
    Builtin.deallocRaw(_rawValue, (-1)._builtinWordValue, (0)._builtinWordValue)
  }
  @_transparent public func assumingMemoryBound<T>(to: T.Type) -> UnsafePointer<T> {
    return UnsafePointer<T>(_rawValue)
  }
  @_transparent public func bindMemory<T>(to type: T.Type, capacity count: Int) -> UnsafePointer<T> {
    Builtin.bindMemory(_rawValue, count._builtinWordValue, type)
    return UnsafePointer<T>(_rawValue)
  }
  @inlinable public func load<T>(fromByteOffset offset: Int = 0, as type: T.Type) -> T {
    return Builtin.loadRaw((self + offset)._rawValue)
  }
  @inlinable public func loadUnaligned<T>(fromByteOffset offset: Int = 0, as type: T.Type) -> T {
    return Builtin.loadRaw((self + offset)._rawValue)
  }
}

@frozen public struct UnsafeMutableRawPointer: _Pointer {
  public typealias Pointee = UInt8
  public let _rawValue: Builtin.RawPointer
  @_transparent public init(_ _rawValue: Builtin.RawPointer) { self._rawValue = _rawValue }
}
extension UnsafeMutableRawPointer {
  @_transparent public init<T>(_ other: UnsafeMutablePointer<T>) { _rawValue = other._rawValue }
  @_transparent public init?<T>(_ other: UnsafeMutablePointer<T>?) {
    guard let unwrapped = other else { return nil }
    _rawValue = unwrapped._rawValue
  }
  @_transparent public init(mutating other: UnsafeRawPointer) { _rawValue = other._rawValue }
  @_transparent public init?(mutating other: UnsafeRawPointer?) {
    guard let unwrapped = other else { return nil }
    _rawValue = unwrapped._rawValue
  }
  @inlinable public static func allocate(byteCount: Int, alignment: Int) -> UnsafeMutableRawPointer {
    var align = alignment
    if align <= MemoryLayout<Int>.alignment { align = 0 }
    return UnsafeMutableRawPointer(Builtin.allocRaw(byteCount._builtinWordValue, align._builtinWordValue))
  }
  @inlinable public func deallocate() {
    Builtin.deallocRaw(_rawValue, (-1)._builtinWordValue, (0)._builtinWordValue)
  }
  @_transparent public func assumingMemoryBound<T>(to: T.Type) -> UnsafeMutablePointer<T> {
    return UnsafeMutablePointer<T>(_rawValue)
  }
  @_transparent @discardableResult
  public func bindMemory<T>(to type: T.Type, capacity count: Int) -> UnsafeMutablePointer<T> {
    Builtin.bindMemory(_rawValue, count._builtinWordValue, type)
    return UnsafeMutablePointer<T>(_rawValue)
  }
  @inlinable public func load<T>(fromByteOffset offset: Int = 0, as type: T.Type) -> T {
    return Builtin.loadRaw((self + offset)._rawValue)
  }
  @inlinable public func loadUnaligned<T>(fromByteOffset offset: Int = 0, as type: T.Type) -> T {
    return Builtin.loadRaw((self + offset)._rawValue)
  }
  @inlinable public func storeBytes<T>(of value: T, toByteOffset offset: Int = 0, as type: T.Type) {
    // The raw store builtins require a trivial type, which is what this
    // API demands of its callers.
    Builtin.initialize(value, (self + offset)._rawValue)
  }
  @inlinable public func copyMemory(from source: UnsafeRawPointer, byteCount: Int) {
    _memmove(dest: self, src: source, size: UInt(bitPattern: byteCount))
  }
  @inlinable @discardableResult
  public func initializeMemory<T>(as type: T.Type, repeating repeatedValue: T, count: Int) -> UnsafeMutablePointer<T> {
    Builtin.bindMemory(_rawValue, count._builtinWordValue, type)
    let p = UnsafeMutablePointer<T>(_rawValue)
    p.initialize(repeating: repeatedValue, count: count)
    return p
  }
}

@usableFromInline @_silgen_name("memmove")
internal func _swift_memmove(_ dest: Builtin.RawPointer, _ src: Builtin.RawPointer, _ size: UInt) -> Builtin.RawPointer

@inlinable
internal func _memmove(dest: UnsafeMutableRawPointer, src: UnsafeRawPointer, size: UInt) {
  _ = _swift_memmove(dest._rawValue, src._rawValue, size)
}

// ---- with* scoping helpers ----------------------------------------------------------

@inlinable
public func withUnsafeMutablePointer<T, Result>(to value: inout T,
                                                _ body: (UnsafeMutablePointer<T>) throws -> Result) rethrows -> Result {
  return try body(UnsafeMutablePointer<T>(Builtin.addressof(&value)))
}
@inlinable
public func withUnsafePointer<T, Result>(to value: inout T,
                                         _ body: (UnsafePointer<T>) throws -> Result) rethrows -> Result {
  return try body(UnsafePointer<T>(Builtin.addressof(&value)))
}
@inlinable
public func withUnsafePointer<T, Result>(to value: T, _ body: (UnsafePointer<T>) throws -> Result) rethrows -> Result {
  var copy = value
  return try withUnsafePointer(to: &copy, body)
}

// ---- implicit pointer conversions -------------------------------------------------
// The compiler calls these by name for the implicit conversions at call
// sites: mutable to immutable pointers, typed to raw, and `&x` to a pointer.

@_transparent
public func _convertPointerToPointerArgument<FromPointer: _Pointer, ToPointer: _Pointer>(_ from: FromPointer) -> ToPointer {
  return ToPointer(from._rawValue)
}
@_transparent
public func _convertInOutToPointerArgument<ToPointer: _Pointer>(_ from: Builtin.RawPointer) -> ToPointer {
  return ToPointer(from)
}

// The compiler accepts implicit pointer conversions only when all of these
// exist (ASTContext::hasPointerArgumentIntrinsics): every pointer type,
// AutoreleasingUnsafeMutablePointer under Objective-C interop, and the
// five conversion functions. The array and string ones below are
// placeholders that trap: they are replaced by the real conversions when
// Array and String exist. Programs never import them (they are inlined at
// the call site), so the placeholders only matter to our own tests.
@_transparent
public func _convertMutableArrayToPointerArgument<A, ToPointer: _Pointer>(_ a: inout A) -> (AnyObject?, ToPointer) {
  Builtin.int_trap()
}
@_transparent
public func _convertConstArrayToPointerArgument<A, ToPointer: _Pointer>(_ arr: A) -> (AnyObject?, ToPointer) {
  Builtin.int_trap()
}
@_transparent
public func _convertConstStringToUTF8PointerArgument<S, ToPointer: _Pointer>(_ str: S) -> (AnyObject?, ToPointer) {
  Builtin.int_trap()
}

/// A pointer to an Objective-C object reference argument (`NSError **`),
/// written with autorelease semantics.
@frozen public struct AutoreleasingUnsafeMutablePointer<Pointee>: _Pointer {
  public let _rawValue: Builtin.RawPointer
  @_transparent public init(_ _rawValue: Builtin.RawPointer) { self._rawValue = _rawValue }
  @inlinable public var pointee: Pointee {
    @_transparent unsafeAddress { return UnsafePointer(_rawValue) }
    @_transparent nonmutating unsafeMutableAddress { return UnsafeMutablePointer(_rawValue) }
  }
  @_transparent public init<U>(_ from: UnsafeMutablePointer<U>) { _rawValue = from._rawValue }
}
