// Heap objects as the compiler emits them: allocation, deinit order,
// retain/release, unowned references, closures and their boxes, static
// objects, lazily initialised globals, stack-promoted objects. The C driver
// (heap.c) watches through note() and the runtime's own counters.
public typealias Int = Builtin.Int64
@_silgen_name("note") func note(_ x: Int)

public final class Tracker {
  let id: Int
  init(_ id: Int) { self.id = id }
  deinit { note(id) }
}

public final class Pair {
  let id: Int
  let a: Tracker
  let b: Tracker
  init(_ id: Int, _ a: Tracker, _ b: Tracker) { self.id = id; self.a = a; self.b = b }
  deinit { note(id) }
}

public final class Owner {
  unowned let t: Tracker
  init(_ t: Tracker) { self.t = t }
}

@inline(never) func zero() -> Int { return Builtin.zeroInitializer() }
@inline(never) func ptr(_ t: Tracker) -> Builtin.RawPointer { return Builtin.bridgeToRawPointer(t) }

// A global holding an object the driver can inspect.
public var held = Tracker(zero())
@_cdecl("heap_hold") public func heap_hold(_ id: Int) { held = Tracker(id) }
@_cdecl("heap_held") public func heap_held() -> Builtin.RawPointer { return ptr(held) }

// Deinit runs before the stored properties are released, in declaration order.
@_cdecl("heap_pair") public func heap_pair(_ p: Int, _ a: Int, _ b: Int) {
  let x = Pair(p, Tracker(a), Tracker(b))
  note(x.id)
}

// Uniqueness as seen by copy-on-write code.
@_cdecl("heap_unique") public func heap_unique(_ id: Int) -> Builtin.Int1 {
  var t = Tracker(id)
  return Builtin.isUnique(&t)
}
@_cdecl("heap_shared_unique") public func heap_shared_unique() -> Builtin.Int1 {
  return Builtin.isUnique(&held)
}

// Unowned references keep the memory, not the object.
public var owner = Owner(held)
@_cdecl("heap_owner") public func heap_owner() -> Int { owner = Owner(held); return owner.t.id }
@_cdecl("heap_owner_read") public func heap_owner_read() -> Int { return owner.t.id }

// A closure capturing a mutable local (a box) and an object.
public var keep: () -> () = {}
@inline(never) func run(_ f: @escaping () -> ()) { keep = f; keep() }
@_cdecl("heap_closure") public func heap_closure(_ start: Int, _ step: Int, _ id: Int) -> Int {
  var x = start
  let t = Tracker(id)
  run { x = Builtin.add_Int64(x, step); note(t.id) }
  keep()
  return x
}
@_cdecl("heap_drop_closure") public func heap_drop_closure() { keep = {} }

// A statically initialised object (immortal) behind swift_once.
public let shared = Tracker(Builtin.zeroInitializer())
@_cdecl("heap_static") public func heap_static() -> Builtin.RawPointer { return ptr(shared) }

// A lazily initialised global: the initialiser runs once.
@inline(never) func initial(_ marker: Int) -> Int { note(marker); return marker }
public var lazyValue: Int = initial(Builtin.zeroInitializer())
@_cdecl("heap_lazy") public func heap_lazy() -> Int { return lazyValue }
@_cdecl("heap_lazy_add") public func heap_lazy_add(_ d: Int) { lazyValue = Builtin.add_Int64(lazyValue, d) }

// An object that does not escape: promoted to the stack at -O.
@_cdecl("heap_local") public func heap_local(_ id: Int) -> Int {
  let t = Tracker(id)
  return Builtin.add_Int64(t.id, t.id)
}
