// Mangled type names, conformances and associated types, as the compiler
// emits them (driver: demangle.c). Only non-generic types for now: generic
// types, and types whose value witnesses are the builtin ones, need
// metadata.c. The structs have mixed-size fields so that the compiler emits
// their own value witness tables.
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
