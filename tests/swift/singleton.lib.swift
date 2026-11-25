// A resilient module (built with -enable-library-evolution): clients may not
// assume these layouts, so types that contain them are laid out at run time.
public struct R {
  public var a: Builtin.Int64
  public var b: Builtin.Int8
  public init(_ a: Builtin.Int64, _ b: Builtin.Int8) { self.a = a; self.b = b }
}
public struct RB {
  public var x: Builtin.Int1
  public init(_ x: Builtin.Int1) { self.x = x }
}
