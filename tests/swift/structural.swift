// module: Swift
// Function, existential and existential metatype metadata made by the
// runtime, and their value witnesses seen through Optional (generic code,
// runtime layout) against the compiler's fixed layouts. Compiled as the
// module Swift for Optional (see the Makefile).
@frozen public enum Optional<Wrapped> { case none; case some(Wrapped) }
public typealias AnyObject = Builtin.AnyObject
public typealias I64 = Builtin.Int64
public protocol P {}
public protocol Q {}
public protocol CP: AnyObject {}
public typealias F1 = (I64) -> I64
public typealias FT = @convention(thin) (I64) -> Builtin.Int8
public typealias FC = @convention(c) (I64) -> Builtin.Int8
public typealias F2 = (I64, Builtin.Int8) throws -> ()
public typealias F4 = (inout I64, __owned Builtin.Int8, Builtin.Int8, Builtin.Int8) -> ()
public typealias PQ = P & Q
public typealias AT = Any.Type
public typealias PT = any P.Type

@inline(never) public func meta<T>(_ t: T.Type) -> Builtin.RawPointer { return Builtin.reinterpretCast(t) }
@inline(never) public func id<T>(_ t: T) -> T { return t }
@inline(never) public func none<T>(_ t: T.Type) -> Optional<T> { return .none }
@inline(never) public func some<T>(_ t: T) -> Optional<T> { return .some(t) }

@_cdecl("md_f1") public func md_f1() -> Builtin.RawPointer { return meta(F1.self) }
@_cdecl("md_ft") public func md_ft() -> Builtin.RawPointer { return meta(FT.self) }
@_cdecl("md_fc") public func md_fc() -> Builtin.RawPointer { return meta(FC.self) }
@_cdecl("md_f2") public func md_f2() -> Builtin.RawPointer { return meta(F2.self) }
@_cdecl("md_f4") public func md_f4() -> Builtin.RawPointer { return meta(F4.self) }
@_cdecl("md_any") public func md_any() -> Builtin.RawPointer { return meta(Any.self) }
@_cdecl("md_anyobject") public func md_anyobject() -> Builtin.RawPointer { return meta(AnyObject.self) }
@_cdecl("md_pq") public func md_pq() -> Builtin.RawPointer { return meta(PQ.self) }
@_cdecl("md_cp") public func md_cp() -> Builtin.RawPointer { return meta(CP.self) }
@_cdecl("md_at") public func md_at() -> Builtin.RawPointer { return meta(AT.self) }
@_cdecl("md_pt") public func md_pt() -> Builtin.RawPointer { return meta(PT.self) }

// A closure through generic code (thick function value witnesses).
@inline(never) func adder(_ x: I64) -> F1 { return { y in Builtin.add_Int64(x, y) } }
@_cdecl("fn_call") public func fn_call(_ x: I64, _ y: I64) -> I64 {
  let f = id(adder(x))
  let g = id(some(f))
  switch g { case .some(let h): return h(y); case .none: return y }
}

// Optional<Optional<T>>.none: the payload's second extra inhabitant.
@_cdecl("g_nn_pq") public func g_nn_pq(_ o: Builtin.RawPointer) { Builtin.initialize(none(Optional<PQ>.self), o) }
@_cdecl("c_nn_pq") public func c_nn_pq(_ o: Builtin.RawPointer) { Builtin.initialize(Optional<Optional<PQ>>.none, o) }
@_cdecl("g_nn_cp") public func g_nn_cp(_ o: Builtin.RawPointer) { Builtin.initialize(none(Optional<CP>.self), o) }
@_cdecl("c_nn_cp") public func c_nn_cp(_ o: Builtin.RawPointer) { Builtin.initialize(Optional<Optional<CP>>.none, o) }
@_cdecl("g_nn_f1") public func g_nn_f1(_ o: Builtin.RawPointer) { Builtin.initialize(none(Optional<F1>.self), o) }
@_cdecl("c_nn_f1") public func c_nn_f1(_ o: Builtin.RawPointer) { Builtin.initialize(Optional<Optional<F1>>.none, o) }
@_cdecl("g_nn_ft") public func g_nn_ft(_ o: Builtin.RawPointer) { Builtin.initialize(none(Optional<FT>.self), o) }
@_cdecl("c_nn_ft") public func c_nn_ft(_ o: Builtin.RawPointer) { Builtin.initialize(Optional<Optional<FT>>.none, o) }
@_cdecl("g_nn_at") public func g_nn_at(_ o: Builtin.RawPointer) { Builtin.initialize(none(Optional<AT>.self), o) }
@_cdecl("c_nn_at") public func c_nn_at(_ o: Builtin.RawPointer) { Builtin.initialize(Optional<Optional<AT>>.none, o) }
