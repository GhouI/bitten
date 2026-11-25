// module: Swift
// Dynamic casts and errors (driver: casts.c). Compiled as the module Swift
// so that it can declare the Error protocol the compiler uses for `throw`.
// Existential metadata comes with metadata.c; until then the driver builds
// the few it needs by hand.
public protocol Error {}
public typealias Int = Builtin.Int64

public protocol P { func value() -> Int }
public protocol Q {}

public struct Small: P {
  public var a: Int
  public var b: Builtin.Int32
  public func value() -> Int { return a }
}
// Too big for an existential's inline buffer: boxed.
public struct Big: P {
  public var a: Int
  public var b: Builtin.Int32
  public var c: Int
  public var d: Int
  public func value() -> Int { return Builtin.add_Int64(a, d) }
}

public class Base {}
public class Derived: Base {}
public class Other {}
extension Base: Q {}
// An Objective-C protocol, registered with the Objective-C runtime.
@objc public protocol Marked {}
extension Derived: Marked {}

public struct MyErr: Error {
  public var code: Int
  public var small: Builtin.Int32
}

@inline(never) func boom(_ code: Int) throws -> Int {
  throw MyErr(code: code, small: Builtin.zeroInitializer())
}
public var saved: any Error = MyErr(code: Builtin.zeroInitializer(), small: Builtin.zeroInitializer())
@_cdecl("casts_catch") public func casts_catch(_ code: Int) -> Int {
  do { return try boom(code) } catch { saved = error; return Builtin.zeroInitializer() }
}
@_cdecl("casts_saved_error") public func casts_saved_error() -> Builtin.RawPointer {
  return Builtin.reinterpretCast(saved)
}

// `as!` between classes: swift_dynamicCastClassUnconditional.
@_cdecl("casts_force_derived") public func casts_force_derived(_ p: Builtin.RawPointer) -> Builtin.RawPointer {
  let b: Base = Builtin.bridgeFromRawPointer(p)
  let d = b as! Derived
  return Builtin.bridgeToRawPointer(d)
}
// Instances kept alive by globals.
public let theBase = Base(), theDerived: Base = Derived(), theOther = Other()
@_cdecl("casts_new_base") public func casts_new_base() -> Builtin.RawPointer { return Builtin.bridgeToRawPointer(theBase) }
@_cdecl("casts_new_derived") public func casts_new_derived() -> Builtin.RawPointer { return Builtin.bridgeToRawPointer(theDerived) }
@_cdecl("casts_new_other") public func casts_new_other() -> Builtin.RawPointer { return Builtin.bridgeToRawPointer(theOther) }
// Calls P.value() through an existential container built by the runtime.
@_cdecl("casts_value_of") public func casts_value_of(_ p: Builtin.RawPointer) -> Int {
  let e: any P = Builtin.load(p)
  return e.value()
}
