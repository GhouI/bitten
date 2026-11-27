// Dynamic casts between tuple types: unlabeled to labeled and back,
// matching and mismatched labels, element-wise casts, and the cleanup of a
// cast that fails partway.

final class Tracked {
  static var live = 0
  init() { Tracked.live += 1 }
  deinit { Tracked.live -= 1 }
}
struct TabID: Hashable { var raw: Int }
struct BlockID: Hashable { var raw: String }

@inline(never) func opaque(_ v: Any) -> Any { v }
@inline(never) func generic<T, U>(_ v: T, to: U.Type) -> U? { v as? U }

@_silgen_name("swl_tuplecasts_labels") public func labels() -> Int {
  var bad = 0
  let plain = opaque((1, "a"))
  if let t = plain as? (x: Int, y: String) { if t.x != 1 || t.y != "a" { bad |= 1 } } else { bad |= 1 }
  let labeled = opaque((x: 2, y: "b"))
  if let t = labeled as? (Int, String) { if t.0 != 2 || t.1 != "b" { bad |= 2 } } else { bad |= 2 }
  if let t = labeled as? (x: Int, y: String) { if t.x != 2 { bad |= 4 } } else { bad |= 4 }
  if labeled as? (a: Int, b: String) != nil { bad |= 8 }
  if labeled is (x: Int, z: String) { bad |= 16 }
  if let t = labeled as? (x: Int, String) { if t.1 != "b" { bad |= 32 } } else { bad |= 32 }
  if plain as? (Int, String, Int) != nil || plain as? (String, Int) != nil { bad |= 64 }
  let ids = generic((TabID(raw: 7), BlockID(raw: "blk")), to: (tabID: TabID, blockID: BlockID).self)
  if ids?.tabID.raw != 7 || ids?.blockID.raw != "blk" { bad |= 128 }
  let forced = opaque((TabID(raw: 8), BlockID(raw: "c"))) as! (tabID: TabID, blockID: BlockID)
  if forced.tabID.raw != 8 || forced.blockID.raw != "c" { bad |= 256 }
  return bad
}

@_silgen_name("swl_tuplecasts_elements") public func elements() -> Int {
  var bad = 0
  let anys: (Any, Any) = (3, "c")
  if let t = generic(anys, to: (Int, String).self) { if t.0 != 3 || t.1 != "c" { bad |= 1 } } else { bad |= 1 }
  if generic(anys, to: (String, String).self) != nil { bad |= 2 }
  let opt = generic((Optional(4), 5 as Any), to: (n: Int, m: Int?).self)
  if opt?.n != 4 || opt?.m != 5 { bad |= 4 }
  let nested = opaque(((1, "x"), 2.5))
  if let t = nested as? (inner: (a: Int, b: String), d: Double) {
    if t.inner.a != 1 || t.inner.b != "x" || t.d != 2.5 { bad |= 8 }
  } else { bad |= 8 }
  do {
    let mixed: (Any, Any) = (Tracked(), 1)
    if generic(mixed, to: (Tracked, String).self) != nil { bad |= 16 }
    if let t = generic(mixed, to: (Tracked, Int).self) { if t.1 != 1 { bad |= 32 } } else { bad |= 32 }
  }
  if Tracked.live != 0 { bad |= 64 }
  return bad
}
