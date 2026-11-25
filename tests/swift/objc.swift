// Swift objects seen from Objective-C: messages, ARC entry points, weak
// variables and autorelease pools all go through Swift reference counting
// (the C driver objc.c does the Objective-C side).
public typealias Int = Builtin.Int64
@_silgen_name("note") func note(_ x: Int)

public final class Tracker {
  let id: Int
  init(_ id: Int) { self.id = id }
  deinit { note(id) }
}

@inline(never) func zero() -> Int { return Builtin.zeroInitializer() }
public var held = Tracker(zero())
@_cdecl("objc_hold") public func objc_hold(_ id: Int) { held = Tracker(id) }
@_cdecl("objc_held") public func objc_held() -> Builtin.RawPointer { return Builtin.bridgeToRawPointer(held) }
@_cdecl("objc_tracker_id") public func objc_tracker_id(_ p: Builtin.RawPointer) -> Int {
  let t: Tracker = Builtin.bridgeFromRawPointer(p)
  return t.id
}
