// Dictionary and Set: lookups, growth, deletion without tombstones,
// copy-on-write, iteration, the views and the set operations, with trivial
// and class-typed elements (deinit counts are kept by the C driver). Each
// function returns a bit for every failed check. The storage layout is also
// checked from C, the way programs read it inline.

@_silgen_name("swd_note_deinit") func noteDeinit(_ id: Int)

final class Box: Hashable {
  let id: Int
  init(_ id: Int) { self.id = id }
  deinit { noteDeinit(id) }
  static func == (a: Box, b: Box) -> Bool { a.id == b.id }
  func hash(into h: inout Hasher) { h.combine(id) }
}

/// A key whose hashes collide in groups of eight, to make long probe runs.
struct Clash: Hashable {
  var v: Int
  func hash(into h: inout Hasher) { h.combine(v / 8) }
}

@inline(never) func opaque<T>(_ x: T) -> T { x }

func every(_ step: Int, from start: Int, to end: Int, _ body: (Int) -> Void) {
  var i = start
  while i < end { body(i); i += step }
}
func downward(_ n: Int, _ body: (Int) -> Void) {
  var i = n
  while i > 0 { i -= 1; body(i) }
}

@inline(never) func storageAddress<K, V>(_ d: [K: V]) -> UInt {
  unsafeBitCast(d, to: UInt.self)
}
@inline(never) func storageAddress<E>(_ s: Set<E>) -> UInt {
  unsafeBitCast(s, to: UInt.self)
}

// ---- exported to the driver ---------------------------------------------------------

@_silgen_name("swd_empty_storage") public func emptyStorage() -> UInt {
  storageAddress([Int: Int]())
}
@_silgen_name("swd_empty_set_storage") public func emptySetStorage() -> UInt {
  storageAddress(Set<Int>())
}

var keptDictionary = [Int: Int]()
var keptSet = Set<Int>()

/// A dictionary of n squares, kept alive for the driver to walk.
@_silgen_name("swd_squares") public func squares(_ n: Int) -> UInt {
  var d = [Int: Int]()
  for i in 0..<n { d[i] = i * i }
  keptDictionary = d
  return storageAddress(keptDictionary)
}
@_silgen_name("swd_set_of") public func setOf(_ n: Int) -> UInt {
  var s = Set<Int>()
  for i in 0..<n { s.insert(i * 3) }
  keptSet = s
  return storageAddress(keptSet)
}
@_silgen_name("swd_seed_hash") public func seedHash(_ key: Int, _ seed: Int) -> Int {
  key._rawHashValue(seed: seed)
}

@_silgen_name("swd_basics") public func basics() -> Int {
  var bad = 0
  var d = [Int: Int]()
  if !d.isEmpty || d.count != 0 || d[1] != nil || d.index(forKey: 1) != nil { bad |= 1 }
  for _ in d { bad |= 2 }
  if d.startIndex != d.endIndex { bad |= 2 }

  d[1] = 10
  d[2] = 20
  if d.count != 2 || d[1] != 10 || d[2] != 20 || d[3] != nil { bad |= 4 }
  if d.updateValue(11, forKey: 1) != 10 || d[1] != 11 { bad |= 8 }
  if d.updateValue(30, forKey: 3) != nil || d.count != 3 { bad |= 8 }
  if d.removeValue(forKey: 2) != 20 || d[2] != nil || d.count != 2 { bad |= 16 }
  if d.removeValue(forKey: 2) != nil { bad |= 16 }
  d[3] = nil
  if d.count != 1 || d[3] != nil { bad |= 32 }

  // default: subscript, reading and mutating in place.
  if d[7, default: 70] != 70 || d[7] != nil { bad |= 64 }
  d[7, default: 0] += 5
  d[1, default: 0] += 5
  if d[7] != 5 || d[1] != 16 { bad |= 64 }

  // Indices.
  guard let i = d.index(forKey: 7) else { return bad | 128 }
  if d[i].key != 7 || d[i].value != 5 || d.keys[i] != 7 || d.values[i] != 5 { bad |= 128 }
  let removed = d.remove(at: i)
  if removed.key != 7 || removed.value != 5 || d.count != 1 { bad |= 128 }

  // popFirst and removeAll.
  if d.popFirst()?.key != 1 || !d.isEmpty || d.popFirst()?.key != nil { bad |= 256 }
  d[5] = 5
  d.removeAll(keepingCapacity: true)
  if !d.isEmpty || d.capacity < 1 { bad |= 512 }
  d.removeAll()
  if storageAddress(d) != emptyStorage() { bad |= 512 }

  // minimumCapacity, reserveCapacity.
  var e = [Int: Int](minimumCapacity: 100)
  if e.capacity < 100 { bad |= 1024 }
  let before = storageAddress(e)
  for k in 0..<100 { e[k] = k }
  if storageAddress(e) != before { bad |= 1024 }
  var f = [Int: Int]()
  f.reserveCapacity(50)
  if f.capacity < 50 { bad |= 2048 }
  return bad
}

@_silgen_name("swd_growth") public func growth() -> Int {
  var bad = 0
  var d = [Int: Int]()
  for i in 0..<2000 { d[i] = -i }
  if d.count != 2000 { bad |= 1 }
  for i in 0..<2000 where d[i] != -i { bad |= 2 }
  if d[2000] != nil || d[-1] != nil { bad |= 2 }

  // Remove every other key, re-check, re-insert, several rounds: deletion
  // shifts entries back, so lookups must still find every key.
  for round in 0..<5 {
    every(2, from: round & 1, to: 2000) { d[$0] = nil }
    if d.count != 1000 { bad |= 4 }
    for i in 0..<2000 {
      let expected: Int? = (i & 1) == (round & 1) ? nil : -i
      if d[i] != expected { bad |= 8 }
    }
    every(2, from: round & 1, to: 2000) { d[$0] = -$0 }
    if d.count != 2000 { bad |= 16 }
  }

  // Colliding hashes: long runs, deletions in the middle of runs.
  var c = [Clash: Int]()
  for i in 0..<512 { c[Clash(v: i)] = i }
  every(3, from: 0, to: 512) { c[Clash(v: $0)] = nil }
  for i in 0..<512 {
    let expected: Int? = i % 3 == 0 ? nil : i
    if c[Clash(v: i)] != expected { bad |= 32 }
  }
  var sum = 0
  for (k, v) in c {
    if k.v != v { bad |= 64 }
    sum += v
  }
  var expectedSum = 0
  for i in 0..<512 where i % 3 != 0 { expectedSum += i }
  if sum != expectedSum || c.count != 512 - 171 { bad |= 64 }

  // Insert/remove churn at a constant size never fills the table.
  var churn = [Int: Int]()
  for i in 0..<10_000 {
    churn[i] = i
    if i >= 10 { churn[i - 10] = nil }
  }
  if churn.count != 10 || churn.capacity > 64 { bad |= 128 }
  for i in 9990..<10_000 where churn[i] != i { bad |= 128 }
  return bad
}

@_silgen_name("swd_cow") public func cow() -> Int {
  var bad = 0
  var a = [Int: Int]()
  for i in 0..<10 { a[i] = i }
  var b = a
  if storageAddress(a) != storageAddress(b) { bad |= 1 }
  b[3] = 33
  if a[3] != 3 || b[3] != 33 || storageAddress(a) == storageAddress(b) { bad |= 2 }
  // A unique dictionary mutates in place.
  let addr = storageAddress(b)
  b[4] = 44
  b[100] = nil
  if storageAddress(b) != addr { bad |= 4 }
  // Removal from a shared dictionary copies.
  var c = a
  c[0] = nil
  if a[0] != 0 || c[0] != nil || a.count != 10 || c.count != 9 { bad |= 8 }
  // Through the values view, and from inside a loop over a copy.
  var v = a
  for k in v.keys { v[k] = k * 2 }
  if a[5] != 5 || v[5] != 10 { bad |= 16 }
  if let i = v.index(forKey: 5) {
    v.values[i] += 1
    if v[5] != 11 { bad |= 32 }
  }
  // Sets.
  var s = Set<Int>()
  for i in 0..<10 { s.insert(i) }
  var t = s
  t.remove(4)
  if !s.contains(4) || t.contains(4) || s.count != 10 || t.count != 9 { bad |= 64 }
  return bad
}

@_silgen_name("swd_objects") public func objects() -> Int {
  // Class keys and values: every object dies exactly once (counted in C).
  var bad = 0
  do {
    var d = [Box: Box]()
    for i in 0..<20 { d[Box(i)] = Box(100 + i) }
    if d[Box(5)]?.id != 105 { bad |= 1 }
    d[Box(5)] = nil          // key 5 and value 105 die
    d[Box(6)] = Box(206)     // the old value 106 dies
    let copy = d
    d[Box(7)] = nil          // a copy keeps 7 and 107 alive
    if copy[Box(7)]?.id != 107 || d[Box(7)] != nil { bad |= 2 }
    var s = Set<Box>()
    for i in 0..<10 { s.insert(Box(300 + i)) }
    s.remove(Box(303))
    for i in 0..<200 { d[Box(1000 + i)] = Box(2000 + i) }   // grow with objects
    for i in 0..<200 { d[Box(1000 + i)] = nil }
    if d.count != 18 { bad |= 4 }
  }
  return bad
}

@_silgen_name("swd_iteration") public func iteration() -> Int {
  var bad = 0
  var d = [Int: Int]()
  for i in 0..<300 { d[i * 7] = i }
  var order1 = 0, order2 = 0, n = 0
  for (k, _) in d { order1 = order1 &* 31 &+ k; n += 1 }
  for (k, _) in opaque(d) { order2 = order2 &* 31 &+ k }
  if order1 != order2 || n != 300 { bad |= 1 }
  // keys, values and indices agree with iteration.
  var keySum = 0, valueSum = 0, viaIndex = 0
  for k in d.keys { keySum += k }
  for v in d.values { valueSum += v }
  var i = d.startIndex
  while i != d.endIndex { viaIndex = viaIndex &* 31 &+ d[i].key; d.formIndex(after: &i) }
  if keySum != 7 * 299 * 300 / 2 || valueSum != 299 * 300 / 2 || viaIndex != order1 { bad |= 2 }
  if d.keys.count != 300 || !d.keys.contains(70) || d.keys.contains(71) { bad |= 4 }
  if d.values.count != 300 || d.keys.first == nil { bad |= 4 }
  // A copy iterates in the same order.
  var order3 = 0
  let copy = d
  for (k, _) in copy { order3 = order3 &* 31 &+ k }
  if order3 != order1 { bad |= 8 }
  // Keys views compare by contents.
  var e = [Int: Int]()
  downward(300) { e[$0 * 7] = 0 }
  if d.keys != e.keys { bad |= 16 }
  return bad
}

@_silgen_name("swd_api") public func api() -> Int {
  var bad = 0
  let d = Dictionary(uniqueKeysWithValues: zip(0..<10, 100..<110))
  if d.count != 10 || d[3] != 103 { bad |= 1 }
  let m = Dictionary(zip(repeatElement(1, count: 4), 1...4), uniquingKeysWith: +)
  if m.count != 1 || m[1] != 10 { bad |= 2 }
  let mv = d.mapValues { $0 * 2 }
  if mv.count != 10 || mv[4] != 208 { bad |= 4 }
  let cm = d.compactMapValues { $0 % 2 == 0 ? $0 : nil }
  if cm.count != 5 || cm[1] != nil || cm[2] != 102 { bad |= 8 }
  let f = d.filter { $0.key >= 5 }
  if f.count != 5 || f[4] != nil || f[9] != 109 { bad |= 16 }
  var g = d
  g.merge(zip(8..<12, 0..<4)) { old, new in old + new }
  if g.count != 12 || g[8] != 108 || g[9] != 110 || g[11] != 3 { bad |= 32 }
  let h = d.merging(g) { a, _ in a }
  if h.count != 12 || h[9] != 109 { bad |= 64 }
  // Equatable and Hashable regardless of insertion order.
  var x = [Int: Int](), y = [Int: Int]()
  for i in 0..<50 { x[i] = i }
  downward(50) { y[$0] = $0 }
  if x != y || x.hashValue != y.hashValue { bad |= 128 }
  y[3] = 4
  if x == y { bad |= 256 }
  // AnyHashable of a dictionary.
  if AnyHashable(x) != AnyHashable(opaque(x)) { bad |= 512 }
  // Nested dictionaries.
  var nested = [Int: [Int: Int]]()
  nested[1, default: Dictionary()][2] = 3
  nested[1, default: Dictionary()][4] = 5
  if nested[1]?.count != 2 || nested[1]?[4] != 5 { bad |= 1024 }
  return bad
}


@_silgen_name("swd_sets") public func sets() -> Int {
  var bad = 0
  var s = Set<Int>()
  if !s.isEmpty || s.contains(0) { bad |= 1 }
  let r1 = s.insert(5)
  let r2 = s.insert(5)
  if !r1.inserted || r2.inserted || r2.memberAfterInsert != 5 || s.count != 1 { bad |= 2 }
  if s.update(with: 5) != 5 || s.update(with: 6) != nil || s.count != 2 { bad |= 4 }
  if s.remove(5) != 5 || s.remove(5) != nil || s.count != 1 { bad |= 8 }

  let a = Set(0..<10), b = Set(5..<15)
  if a.count != 10 || !a.contains(9) || a.contains(10) { bad |= 16 }
  if a.union(b) != Set(0..<15) { bad |= 32 }
  if a.intersection(b) != Set(5..<10) || a.intersection(5..<100) != Set(5..<10) { bad |= 64 }
  if a.subtracting(b) != Set(0..<5) || a.subtracting(3..<100) != Set(0..<3) { bad |= 128 }
  let sd = a.symmetricDifference(b)
  if sd.count != 10 || sd.contains(5) || !sd.contains(0) || !sd.contains(14) { bad |= 256 }
  if !Set(2..<4).isSubset(of: a) || a.isSubset(of: b) || !a.isSubset(of: 0..<10) { bad |= 512 }
  if !a.isSuperset(of: Set(1..<3)) || !a.isSuperset(of: 1..<3) || a.isSuperset(of: b) { bad |= 1024 }
  if !a.isStrictSubset(of: Set(0..<11)) || a.isStrictSubset(of: a) || !a.isStrictSuperset(of: 0..<9) {
    bad |= 2048
  }
  if a.isDisjoint(with: b) || !a.isDisjoint(with: Set(10..<20)) || !a.isDisjoint(with: 20..<30) {
    bad |= 4096
  }
  var m = a
  m.formUnion(20..<22)
  m.subtract(0..<5)
  m.formIntersection(Set(3..<21))
  var expected = Set(5..<10)
  expected.insert(20)
  if m != expected { bad |= 8192 }
  var evens = Set<Int>()
  every(2, from: 0, to: 10) { evens.insert($0) }
  if a.filter({ $0 % 2 == 0 }) != evens { bad |= 16384 }
  var backwards = Set<Int>()
  downward(10) { backwards.insert($0) }
  if a.hashValue != backwards.hashValue || a != backwards { bad |= 32768 }
  var big = Set<Int>()
  for i in 0..<5000 { big.insert(i) }
  for i in 0..<5000 where i % 7 != 0 { big.remove(i) }
  if big.count != 715 || !big.contains(7) || big.contains(8) { bad |= 65536 }
  var total = 0
  for x in big { total += x }
  if total != 7 * 714 * 715 / 2 { bad |= 65536 }
  return bad
}
