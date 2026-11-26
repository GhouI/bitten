// The standard library: lazy sequences, reversed/joined, random numbers,
// collection casts, Mirror, ManagedBuffer, KeyValuePairs, AnyCollection,
// Error's defaults.

struct Point { var x: Int; var y: Double; let name: String }
final class Box { var value = 3; var label = "box" }
enum Plain: Error { case oops }


@_silgen_name("swl_reflection_lazy") public func lazy() -> Int {
  var bad = 0
  var calls = 0
  let mapped = [1, 2, 3, 4].lazy.map { (x: Int) -> Int in calls += 1; return x * 10 }
  if calls != 0 { bad |= 1 }
  if Array(mapped) != [10, 20, 30, 40] || calls != 4 { bad |= 2 }
  if Array([1, 2, 3, 4, 5].lazy.filter { $0 % 2 == 1 }) != [1, 3, 5] { bad |= 4 }
  if Array([1, 2, 3].reversed()) != [3, 2, 1] || [1, 2, 3].reversed().first != 3 { bad |= 8 }
  if Array([[1, 2], [], [3]].joined()) != [1, 2, 3] { bad |= 16 }
  if Array([1, 2, 3].lazy.compactMap { $0 == 2 ? nil : $0 }) != [1, 3] { bad |= 32 }
  return bad
}

@_silgen_name("swl_reflection_random") public func random() -> Int {
  var bad = 0
  for _ in 0..<200 {
    let i = Int.random(in: 3..<7)
    if i < 3 || i >= 7 { bad |= 1 }
    let c = UInt8.random(in: 250...255)
    if c < 250 { bad |= 2 }
    let d = Double.random(in: 1.0..<2.0)
    if d < 1.0 || d >= 2.0 { bad |= 4 }
  }
  if Int.random(in: Int.min...Int.max) == 0 && Int.random(in: Int.min...Int.max) == 0 { bad |= 8 }
  var s = [1, 2, 3, 4, 5]
  s.shuffle()
  if s.sorted() != [1, 2, 3, 4, 5] || [7].randomElement() != 7 || [Int]().randomElement() != nil { bad |= 16 }
  return bad
}

@_silgen_name("swl_reflection_casts") public func casts() -> Int {
  var bad = 0
  let any: [Any] = [1, 2, 3]
  if (any as? [Int]) != [1, 2, 3] || (any as? [String]) != nil || (any as! [Int]).count != 3 { bad |= 1 }
  let dict: [String: Int] = ["a": 1]
  let up = dict as [AnyHashable: Any]
  if up.count != 1 || (up["a"] as? Int) != 1 { bad |= 2 }
  if (up as? [String: Int]) != ["a": 1] { bad |= 4 }
  let set: Set<Int> = [1, 2]
  if (set as Set<AnyHashable>).count != 2 { bad |= 8 }
  return bad
}

@_silgen_name("swl_reflection_mirror") public func mirror() -> Int {
  var bad = 0
  let m = Mirror(reflecting: Point(x: 4, y: 2.5, name: "p"))
  if m.displayStyle != .struct || m.children.count != 3 { bad |= 1 }
  let labels = m.children.map { $0.label ?? "?" }
  if labels != ["x", "y", "name"] { bad |= 2 }
  if (m.children.first?.value as? Int) != 4 || (m.descendant("name") as? String) != "p" { bad |= 4 }
  let c = Mirror(reflecting: Box())
  if c.displayStyle != .class || (c.descendant("label") as? String) != "box" || (c.descendant(0) as? Int) != 3 { bad |= 8 }
  let t = Mirror(reflecting: (a: 1, "two"))
  if t.displayStyle != .tuple || t.children.first?.label != "a" || t.children.count != 2 { bad |= 16 }
  let arr = Mirror(reflecting: [5, 6])
  if arr.displayStyle != .collection || arr.children.count != 2 { bad |= 32 }
  let kv: KeyValuePairs = ["k": 1, "j": 2]
  if kv.count != 2 || kv[0].key != "k" { bad |= 64 }
  let anyc = AnyCollection([1, 2, 3])
  if anyc.count != 3 || Array(anyc) != [1, 2, 3] || anyc[anyc.startIndex] != 1 { bad |= 128 }
  return bad
}

@_silgen_name("swl_reflection_buffers") public func buffers() -> Int {
  var bad = 0
  // (A subclass of ManagedBuffer from another module needs metadata
  // relocation, which the runtime does not do yet.)
  let b = ManagedBuffer<Int, Int>.create(minimumCapacity: 8) { _ in 0 }
  if b.capacity < 8 { bad |= 1 }
  b.withUnsafeMutablePointers { h, e in
    for i in 0..<8 { e[i] = i * i }
    h.pointee = 8
  }
  if b.header != 8 || b.withUnsafeMutablePointerToElements({ $0[3] }) != 9 { bad |= 2 }
  if Plain.oops._domain.hasSuffix("Plain") == false || Plain.oops._getEmbeddedNSError() != nil { bad |= 4 }
  return bad
}
