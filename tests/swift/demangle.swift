// Mangled type names, conformances and associated types, as the compiler
// emits them (driver: demangle.c). The structs have mixed-size fields so
// that the compiler emits their own value witness tables.
public protocol Q { static func id(_ x: Builtin.Int64) -> Builtin.Int64 }
public protocol P {
  associatedtype A
  associatedtype B: Q
  func get() -> A
}
public protocol Unused {}

public struct QQ: Q {
  public var a: Builtin.Int64
  public var b: Builtin.Int32
  public static func id(_ x: Builtin.Int64) -> Builtin.Int64 { return Builtin.add_Int64(x, x) }
}
public struct S: P {
  public var x: Builtin.Int64
  public var y: Builtin.Int32
  public typealias B = QQ
  public func get() -> QQ { return QQ(a: x, b: y) }
}
// Subclasses inherit conformances.
public class Base {}
public class Derived: Base {}
extension Base: Q { public static func id(_ x: Builtin.Int64) -> Builtin.Int64 { return x } }

public struct Holder {
  public var s: S
  public var q: QQ
  public var n: Builtin.Int64
}

// Generic functions kept generic, so that they ask the runtime for
// associated types and conformances.
@inline(never) @_semantics("optimize.sil.specialize.generic.never")
func assocA<T: P>(_ t: T.Type) -> Builtin.RawPointer {
  return Builtin.reinterpretCast(T.A.self)
}
@inline(never) @_semantics("optimize.sil.specialize.generic.never")
func idOfB<T: P>(_ t: T.Type, _ x: Builtin.Int64) -> Builtin.Int64 {
  return T.B.id(x)
}
@_cdecl("demangle_assoc_a_of_s") public func demangle_assoc_a_of_s() -> Builtin.RawPointer { return assocA(S.self) }
@_cdecl("demangle_id_of_b_of_s") public func demangle_id_of_b_of_s(_ x: Builtin.Int64) -> Builtin.Int64 { return idOfB(S.self, x) }

// An opaque result type: its descriptor records the underlying type and
// conformance for swift_getOpaqueTypeMetadata2/Conformance2.
public func opaque() -> some P { return S(x: Builtin.zeroInitializer(), y: Builtin.zeroInitializer()) }

// Generic types: field types in terms of generic parameters, conditional
// conformances with generic witness tables, nested generic contexts.
public struct Pair<T, U> {
  public var t: T
  public var u: U
}
extension Pair: P where T: P {
  public typealias B = T.B
  public func get() -> T.A { return t.get() }
}
public struct Box<T: P> {
  public var x: T
  public var y: T.A
  public var z: (T, Builtin.Int64)
  public var w: Pair<T.B, T>
}
public struct Outer<X> {
  public struct Inner<Y> { public var x: X; public var y: Y }
}
@inline(never) func meta<T>(_ t: T.Type) -> Builtin.RawPointer { return Builtin.reinterpretCast(t) }
@_cdecl("demangle_pair_s_qq") public func demangle_pair_s_qq() -> Builtin.RawPointer { return meta(Pair<S, QQ>.self) }
@_cdecl("demangle_box_s") public func demangle_box_s() -> Builtin.RawPointer { return meta(Box<S>.self) }
@_cdecl("demangle_inner") public func demangle_inner() -> Builtin.RawPointer { return meta(Outer<S>.Inner<QQ>.self) }
@_cdecl("demangle_assoc_a_of_pair") public func demangle_assoc_a_of_pair() -> Builtin.RawPointer {
  return assocA(Pair<S, QQ>.self)
}
@_cdecl("demangle_id_of_b_of_pair") public func demangle_id_of_b_of_pair(_ x: Builtin.Int64) -> Builtin.Int64 {
  return idOfB(Pair<S, QQ>.self, x)
}
