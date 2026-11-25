// Structs with fields of resilient types: their metadata is completed on
// first use by swift_getSingletonMetadata and swift_initStructMetadata, the
// path the Mac app window takes first (its App struct holds SwiftUI property
// wrappers). G<T> is generic over a resilient field, S2 nests S.
import singleton_lib

public struct S {
  public var x: Builtin.Int8
  public var r: R
  public var y: Builtin.Int64
  public var z: RB
}
public struct S2 { public var s: S; public var b: Builtin.Int8 }
public struct G<T> { public var t: T; public var r: R }

@_cdecl("single_make") public func single_make(_ out: Builtin.RawPointer, _ a: Builtin.Int64,
                                                 _ y: Builtin.Int64) {
  let s = S(x: Builtin.zeroInitializer(), r: R(a, Builtin.zeroInitializer()), y: y,
            z: RB(Builtin.zeroInitializer()))
  Builtin.initialize(s, out)
}
@_cdecl("single_y") public func single_y(_ p: Builtin.RawPointer) -> Builtin.Int64 {
  let s: S = Builtin.load(p)
  return s.y
}
@_cdecl("single_ra") public func single_ra(_ p: Builtin.RawPointer) -> Builtin.Int64 {
  let s: S2 = Builtin.load(p)
  return s.s.r.a
}
