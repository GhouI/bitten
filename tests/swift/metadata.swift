// Generic struct metadata instantiated by the runtime (swift_getGenericMetadata,
// swift_allocateGenericValueMetadata, swift_initStructMetadata), tuples and
// metatypes. The C driver asks for the metadata through the compiler's
// accessors and checks layouts and value witnesses; the Swift functions
// below make the compiler itself go through the runtime (at -Onone).
public struct Pair<T, U> { public var a: T; public var b: U }
public struct Wrap<T> { public var x: Builtin.Int8; public var p: Pair<T, Builtin.Int8>; public var t: T }
public struct Nest<T> { public var w: Wrap<Pair<T, T>>; public var b: Builtin.Int1 }
public struct Tup<T, U> { public var t: (T, Builtin.Int8, U) }
public struct Meta<T> { public var m: T.Type }

@inline(never) public func make<T, U>(_ a: T, _ b: U) -> Pair<T, U> { return Pair(a: a, b: b) }
@inline(never) public func second<T, U>(_ p: Pair<T, U>) -> U { return p.b }
@inline(never) public func swapTuple<T, U>(_ t: (T, U)) -> (U, T) { return (t.1, t.0) }
@inline(never) public func wrapIt<T>(_ t: T) -> Wrap<T> {
  return Wrap(x: Builtin.zeroInitializer(), p: Pair(a: t, b: Builtin.zeroInitializer()), t: t)
}

// Pair<Int64, Pair<Double, Int8>> built through generic code; returns b.b.
@_cdecl("meta_nested") public func meta_nested(_ x: Builtin.Int64, _ f: Builtin.FPIEEE64,
                                                _ c: Builtin.Int8) -> Builtin.Int8 {
  let inner = make(f, c)
  let outer = make(x, inner)
  return second(second(outer) as Pair<Builtin.FPIEEE64, Builtin.Int8>)
}
@_cdecl("meta_swap") public func meta_swap(_ x: Builtin.Int64, _ c: Builtin.Int8) -> Builtin.Int64 {
  let t = swapTuple((x, c))
  return t.1
}
@_cdecl("meta_wrap") public func meta_wrap(_ x: Builtin.Int32) -> Builtin.Int32 {
  return wrapIt(x).t
}
