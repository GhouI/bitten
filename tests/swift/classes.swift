// Class metadata built by the runtime: generic classes and subclasses
// (swift_allocateGenericClassMetadata, swift_initClassMetadata2), a
// non-generic subclass of a generic class (singleton initialisation with a
// static vtable) and a class with a resilient stored property. Each is also
// an Objective-C class; the C driver checks both views.
import classes_lib

public typealias AnyObject = Builtin.AnyObject
public typealias I8 = Builtin.Int8
public typealias I32 = Builtin.Int32
public typealias I64 = Builtin.Int64

public class Base<T> {
  public var t: T
  public var k: I8
  public init(_ t: T, _ k: I8) { self.t = t; self.k = k }
  public func get() -> T { return t }
  public func pick(_ a: I64, _ b: I64, _ c: I64) -> I64 { return a }
}
public class Sub<U>: Base<U> {
  public var u: I64
  public override init(_ t: U, _ k: I8) { self.u = Builtin.zeroInitializer(); super.init(t, k) }
  public override func pick(_ a: I64, _ b: I64, _ c: I64) -> I64 { return b }
}
public class Deep<W>: Sub<W> {
  public var w: W
  public override init(_ t: W, _ k: I8) { self.w = t; super.init(t, k) }
  public override func pick(_ a: I64, _ b: I64, _ c: I64) -> I64 { return c }
}
public class D: Base<I64> {
  public var d: I32
  public override init(_ t: I64, _ k: I8) { self.d = Builtin.zeroInitializer(); super.init(t, k) }
  public override func pick(_ a: I64, _ b: I64, _ c: I64) -> I64 { return b }
}
public class RC {
  public var x: I8
  public var r: R
  public var y: I64
  public init(_ a: I64, _ y: I64) { self.x = Builtin.zeroInitializer(); self.r = R(a, Builtin.zeroInitializer()); self.y = y }
}

@inline(never) public func pickOf<T>(_ b: Base<T>, _ a: I64, _ x: I64, _ c: I64) -> I64 { return b.pick(a, x, c) }
@inline(never) public func getOf<T>(_ b: Base<T>) -> T { return b.get() }

// Returns the object at +1 (the C driver keeps it).
@inline(__always) func keep<C: AnyObject>(_ o: C) -> Builtin.RawPointer {
  Builtin.retain(o)
  return Builtin.bridgeToRawPointer(o)
}
@_cdecl("cls_new_base") public func cls_new_base(_ t: I64) -> Builtin.RawPointer {
  return keep(Base(t, Builtin.zeroInitializer()))
}
@_cdecl("cls_new_sub") public func cls_new_sub(_ t: I64) -> Builtin.RawPointer {
  return keep(Sub(t, Builtin.zeroInitializer()))
}
@_cdecl("cls_new_deep8") public func cls_new_deep8(_ t: I8) -> Builtin.RawPointer {
  return keep(Deep(t, t))
}
@_cdecl("cls_new_d") public func cls_new_d(_ t: I64) -> Builtin.RawPointer {
  return keep(D(t, Builtin.zeroInitializer()))
}
@_cdecl("cls_new_rc") public func cls_new_rc(_ a: I64, _ y: I64) -> Builtin.RawPointer {
  return keep(RC(a, y))
}
@_cdecl("cls_pick_i64") public func cls_pick_i64(_ p: Builtin.RawPointer, _ a: I64, _ b: I64, _ c: I64) -> I64 {
  let o: Base<I64> = Builtin.bridgeFromRawPointer(p)
  return pickOf(o, a, b, c)
}
@_cdecl("cls_pick_i8") public func cls_pick_i8(_ p: Builtin.RawPointer, _ a: I64, _ b: I64, _ c: I64) -> I64 {
  let o: Base<I8> = Builtin.bridgeFromRawPointer(p)
  return pickOf(o, a, b, c)
}
@_cdecl("cls_get_i64") public func cls_get_i64(_ p: Builtin.RawPointer) -> I64 {
  let o: Base<I64> = Builtin.bridgeFromRawPointer(p)
  return getOf(o)
}
@_cdecl("cls_rc_y") public func cls_rc_y(_ p: Builtin.RawPointer) -> I64 {
  let o: RC = Builtin.bridgeFromRawPointer(p)
  return o.y
}
@_cdecl("cls_rc_a") public func cls_rc_a(_ p: Builtin.RawPointer) -> I64 {
  let o: RC = Builtin.bridgeFromRawPointer(p)
  return o.r.a
}
