// Checks the metadata layouts swift_abi.h describes against what the
// compiler emits, without calling into the runtime.
public struct Point {
  public var x: Builtin.Int64
  public var y: Builtin.Int32
  public var z: Builtin.Int64
}
@_cdecl("layout_point_z") public func layout_point_z(_ p: Builtin.RawPointer) -> Builtin.Int64 {
  let pt: Point = Builtin.load(p)
  return pt.z
}
