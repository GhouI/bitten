// module: Swift
// Weak and unowned references, to Swift objects and (through AnyObject) to
// Objective-C objects. Weak references need Optional, which the compiler
// looks up in the standard library by name, so this test is compiled as the
// module "Swift" itself (see the Makefile) and declares the little it needs.
@frozen public enum Optional<Wrapped> { case none; case some(Wrapped) }
public protocol ExpressibleByNilLiteral { init(nilLiteral: ()) }
extension Optional: ExpressibleByNilLiteral {
  @_transparent public init(nilLiteral: ()) { self = .none }
}
public typealias AnyObject = Builtin.AnyObject
public typealias Int = Builtin.Int64
@_silgen_name("note") func note(_ x: Int)

public final class Tracker {
  let id: Int
  init(_ id: Int) { self.id = id }
  deinit { note(id) }
}

public final class Holder {
  weak var w: Tracker?
  weak var any: AnyObject?
  unowned var u: AnyObject
  init(_ u: AnyObject) { self.u = u }
}

public struct WeakPair {
  weak var a: Tracker?
  weak var b: AnyObject?
}

@inline(never) func zero() -> Int { return Builtin.zeroInitializer() }
@inline(never) func id(of t: Tracker?, or none: Int) -> Int {
  switch t { case .some(let t): return t.id case .none: return none }
}

public var strong = Tracker(zero())
public var holder = Holder(strong)

@_cdecl("weak_track") public func weak_track(_ i: Int) { strong = Tracker(i) }
@_cdecl("weak_link") public func weak_link() { holder.w = .some(strong) }
@_cdecl("weak_read") public func weak_read(_ none: Int) -> Int { return id(of: holder.w, or: none) }
@_cdecl("weak_strong") public func weak_strong() -> Builtin.RawPointer { return Builtin.bridgeToRawPointer(strong) }

// Copies of a struct holding weak references (copy-init / assign / take).
public var pairs = WeakPair(a: .none, b: .none)
@_cdecl("weak_pair_copy") public func weak_pair_copy(_ none: Int) -> Int {
  var p = WeakPair(a: .none, b: .none)
  p.a = .some(strong)
  p.b = .some(strong)
  pairs = p
  let q = pairs
  return id(of: q.a, or: none)
}
@_cdecl("weak_pair_read") public func weak_pair_read(_ none: Int) -> Int { return id(of: pairs.a, or: none) }
@_cdecl("weak_pair_any_nil") public func weak_pair_any_nil() -> Builtin.Int1 {
  switch pairs.b { case .some: return Builtin.zeroInitializer() case .none: return Builtin.trunc_Int64_Int1(Builtin.zext_Int1_Int64(Builtin.cmp_eq_Int64(zero(), zero()))) }
}

// AnyObject references: any object, Swift or Objective-C.
@inline(never) func object(_ p: Builtin.RawPointer) -> AnyObject { return Builtin.bridgeFromRawPointer(p) }
@_cdecl("weak_any_set") public func weak_any_set(_ p: Builtin.RawPointer) { holder.any = .some(object(p)) }
@_cdecl("weak_any_get") public func weak_any_get() -> Builtin.RawPointer {
  switch holder.any {
  case .some(let o): return Builtin.bridgeToRawPointer(o)
  case .none: return Builtin.inttoptr_Int64(zero())
  }
}
@_cdecl("weak_unowned_set") public func weak_unowned_set(_ p: Builtin.RawPointer) { holder.u = object(p) }
@_cdecl("weak_unowned_get") public func weak_unowned_get() -> Builtin.RawPointer {
  return Builtin.bridgeToRawPointer(holder.u)
}
