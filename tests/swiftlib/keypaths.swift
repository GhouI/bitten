// Key paths: instantiation of compiler-emitted patterns (stored, computed,
// subscripts with arguments, optional chains, generic contexts, external
// property descriptors), reads and writes through them, equality, hashing
// and appending. Each function returns a bit for each check that failed.

var deinits = 0

struct Point {
  var x: Int
  var y: Int
  let z: Int16
}

struct Line {
  var a: Point
  var b: Point
  var pair: (Int8, Int)
}

final class Box {
  var p: Point
  var next: Box?
  let id: Int
  init(_ id: Int, next: Box? = nil) {
    self.p = Point(x: id, y: id * 10, z: 0)
    self.next = next
    self.id = id
  }
  deinit { deinits += 1 }
}

class Base {
  var v = 1
  var u: Int8 = 2
}
class Derived: Base {
  var w = 3
}

struct Comp {
  var raw: Int
  var doubled: Int {
    get { raw * 2 }
    set { raw = newValue / 2 }
  }
  subscript(i: Int) -> Int {
    get { raw + i }
    set { raw = newValue - i }
  }
  subscript(i: Int, box: Box) -> Int {
    get { raw * i + box.id }
  }
}

final class Holder {
  var c = Comp(raw: 5)
  var nonmut: Int {
    get { c.raw }
    set { c.raw = newValue }
  }
}

struct G<T> {
  var n: Int
  var t: T
  var both: (T, Int) {
    get { (t, n) }
    set { t = newValue.0; n = newValue.1 }
  }
}

@inline(never) func get<R, V>(_ r: R, _ k: KeyPath<R, V>) -> V { r[keyPath: k] }
@inline(never) func set<R, V>(_ r: inout R, _ k: WritableKeyPath<R, V>, _ v: V) { r[keyPath: k] = v }
@inline(never) func setRef<R, V>(_ r: R, _ k: ReferenceWritableKeyPath<R, V>, _ v: V) { r[keyPath: k] = v }
@inline(never) func bump(_ r: inout Line, _ k: WritableKeyPath<Line, Int>) { r[keyPath: k] += 100 }
@inline(never) func genericPath<T>(_: T.Type) -> WritableKeyPath<G<T>, T> { \G<T>.t }
@inline(never) func genericBoth<T>(_: T.Type) -> WritableKeyPath<G<T>, (T, Int)> { \G<T>.both }
@inline(never) func indexPath(_ i: Int) -> WritableKeyPath<Comp, Int> { \Comp.[i] }
@inline(never) func boxIndexPath(_ i: Int, _ b: Box) -> KeyPath<Comp, Int> { \Comp.[i, b] }
@inline(never) func any(_ k: AnyKeyPath) -> AnyKeyPath { k }

@_silgen_name("swl_kp_stored") public func stored() -> Int {
  var bad = 0
  var l = Line(a: Point(x: 1, y: 2, z: 3), b: Point(x: 4, y: 5, z: 6), pair: (7, 8))
  if get(l, \Line.a.x) != 1 || get(l, \Line.b.y) != 5 || get(l, \Line.b.z) != 6 { bad |= 1 }
  if l[keyPath: \Line.pair.1] != 8 || l[keyPath: \Line.pair.0] != 7 { bad |= 2 }
  set(&l, \Line.b.x, 40)
  l[keyPath: \Line.a.y] = 20
  if l.b.x != 40 || l.a.y != 20 || l.a.x != 1 { bad |= 4 }
  bump(&l, \Line.pair.1)
  bump(&l, \.b.y)
  if l.pair.1 != 108 || l.b.y != 105 { bad |= 8 }
  // identity
  var p = Point(x: 9, y: 8, z: 7)
  if get(p, \Point.self).y != 8 { bad |= 16 }
  set(&p, \Point.self, Point(x: 1, y: 2, z: 3))
  if p.x != 1 || p.z != 3 { bad |= 32 }
  // a key path as a function
  let f: (Point) -> Int = \.y
  if f(p) != 2 { bad |= 64 }
  return bad
}

@_silgen_name("swl_kp_classes") public func classes() -> Int {
  var bad = 0
  do {
    let b = Box(1, next: Box(2))
    if get(b, \Box.p.y) != 10 || get(b, \Box.id) != 1 { bad |= 1 }
    setRef(b, \Box.p.x, 77)
    b[keyPath: \Box.p.y] += 5
    if b.p.x != 77 || b.p.y != 15 { bad |= 2 }
    // optional chaining: nil and not
    if get(b, \Box.next?.p.x) != 2 || get(b, \Box.next?.next?.p.x) != nil { bad |= 4 }
    // force unwrap, written through
    setRef(b, \Box.next!.p.y, 99)
    if b.next!.p.y != 99 { bad |= 8 }
    // inherited fields
    let d = Derived()
    if get(d, \Derived.v) != 1 || get(d, \Derived.w) != 3 || get(d, \Derived.u) != 2 { bad |= 16 }
    setRef(d, \Derived.v, 10)
    setRef(d, \Derived.w, 30)
    if d.v != 10 || d.w != 30 || d.u != 2 { bad |= 32 }
    // a struct holding a class: writable through the reference
    struct S { let box: Box }
    let s = S(box: b)
    let k: ReferenceWritableKeyPath<S, Int> = \S.box.p.x
    setRef(s, k, 5)
    if b.p.x != 5 { bad |= 64 }
  }
  if deinits != 2 { bad |= 128 }
  return bad
}

@_silgen_name("swl_kp_computed") public func computed() -> Int {
  var bad = 0
  var c = Comp(raw: 3)
  if get(c, \Comp.doubled) != 6 { bad |= 1 }
  set(&c, \Comp.doubled, 20)
  if c.raw != 10 { bad |= 2 }
  c[keyPath: \Comp.doubled] += 4
  if c.raw != 12 { bad |= 4 }
  if get(c, indexPath(5)) != 17 || c[keyPath: \Comp.[1]] != 13 { bad |= 8 }
  set(&c, indexPath(2), 50)
  if c.raw != 48 { bad |= 16 }
  // nonmutating setter on a class: reached through the reference
  let h = Holder()
  setRef(h, \Holder.nonmut, 8)
  h[keyPath: \Holder.c.doubled] += 2
  if h.c.raw != 9 || get(h, \Holder.c.[1]) != 10 { bad |= 32 }
  // a subscript capturing a class reference: copied into the key path,
  // released with it
  deinits = 0
  do {
    let b = Box(4)
    let k = boxIndexPath(3, b)
    if get(Comp(raw: 2), k) != 10 { bad |= 64 }
    let k2 = boxIndexPath(3, b)
    if k != k2 || k.hashValue != k2.hashValue { bad |= 128 }
    if k == boxIndexPath(3, Box(4)) { bad |= 256 } // different id: not equal
  }
  if deinits != 2 { bad |= 512 }
  return bad
}

@_silgen_name("swl_kp_generic") public func generic() -> Int {
  var bad = 0
  var gi = G(n: 1, t: 42)
  if get(gi, genericPath(Int.self)) != 42 { bad |= 1 }
  set(&gi, genericPath(Int.self), 7)
  if gi.t != 7 { bad |= 2 }
  var g8 = G<Int8>(n: 2, t: 3)
  if get(g8, genericPath(Int8.self)) != 3 || get(g8, \G<Int8>.n) != 2 { bad |= 4 }
  set(&g8, genericBoth(Int8.self), (9, 10))
  if g8.t != 9 || g8.n != 10 || get(g8, genericBoth(Int8.self)).1 != 10 { bad |= 8 }
  deinits = 0
  do {
    var gb = G(n: 0, t: Box(5))
    if get(gb, genericPath(Box.self)).id != 5 { bad |= 16 }
    set(&gb, genericPath(Box.self), Box(6))
    if gb.t.id != 6 || deinits != 1 { bad |= 32 }
  }
  if deinits != 2 { bad |= 64 }
  // equality across instantiations
  if genericPath(Int.self) != genericPath(Int.self) { bad |= 128 }
  if any(genericPath(Int.self)) == any(genericPath(Int8.self)) { bad |= 256 }
  // external property descriptor (a generic property of the stdlib)
  let ptr = UnsafeMutablePointer<Int>.allocate(capacity: 1)
  ptr.initialize(to: 11)
  if get(ptr, \UnsafeMutablePointer<Int>.pointee) != 11 { bad |= 512 }
  setRef(ptr, \UnsafeMutablePointer<Int>.pointee, 12)
  if ptr.pointee != 12 { bad |= 1024 }
  ptr.deallocate()
  return bad
}

@_silgen_name("swl_kp_equality") public func equality() -> Int {
  var bad = 0
  if \Point.x != \Point.x || \Point.x == \Point.y { bad |= 1 }
  if (\Point.x).hashValue != (\Point.x).hashValue { bad |= 2 }
  if \Line.b.y != \Line.b.y || \Line.b.y == \Line.a.y { bad |= 4 }
  if indexPath(3) != indexPath(3) || indexPath(3) == indexPath(4) { bad |= 8 }
  if indexPath(3).hashValue != indexPath(3).hashValue { bad |= 16 }
  if \Comp.doubled == \Comp.[0] { bad |= 32 }
  // different classes are different key paths
  if any(\Point.z) == any(\Point.x) { bad |= 64 }
  return bad
}

@_silgen_name("swl_kp_kinds") public func kinds() -> Int {
  var bad = 0
  if any(\Point.z) is WritableKeyPath<Point, Int16> { bad |= 1 }
  if !(any(\Point.x) is WritableKeyPath<Point, Int>) { bad |= 2 }
  if any(\Point.x) is ReferenceWritableKeyPath<Point, Int> { bad |= 4 }
  if !(any(\Box.p.x) is ReferenceWritableKeyPath<Box, Int>) { bad |= 8 }
  if any(\Box.id) is WritableKeyPath<Box, Int> { bad |= 16 }
  if any(\Comp.[1, Box(1)]) is WritableKeyPath<Comp, Int> { bad |= 32 }
  if !(any(\Holder.nonmut) is ReferenceWritableKeyPath<Holder, Int>) { bad |= 64 }
  if ObjectIdentifier(type(of: any(\Point.x)).rootType) != ObjectIdentifier(Point.self) ||
     ObjectIdentifier(type(of: any(\Point.z)).valueType) != ObjectIdentifier(Int16.self) {
    bad |= 128
  }
  return bad
}

@_silgen_name("swl_kp_append") public func append() -> Int {
  var bad = 0
  let ab = (\Line.b).appending(path: \Point.y)
  if ab != \Line.b.y || ab.hashValue != (\Line.b.y).hashValue { bad |= 1 }
  var l = Line(a: Point(x: 1, y: 2, z: 3), b: Point(x: 4, y: 5, z: 6), pair: (7, 8))
  if get(l, ab) != 5 { bad |= 2 }
  set(&l, ab, 50)
  if l.b.y != 50 { bad |= 4 }
  let b = Box(3)
  let bx = (\Box.p).appending(path: \Point.x)
  setRef(b, bx, 30)
  if b.p.x != 30 || get(b, bx) != 30 { bad |= 8 }
  let ci = (\Holder.c).appending(path: indexPath(4))
  let h = Holder()
  setRef(h, ci, 14)
  if h.c.raw != 10 || ci != \Holder.c.[4] { bad |= 16 }
  // read-only + writable is read-only; through Any
  let ro: KeyPath<Box, Int16> = (\Box.p).appending(path: \Point.z)
  if get(b, ro) != 0 || any(ro) is WritableKeyPath<Box, Int16> { bad |= 32 }
  if any(\Box.p).appending(path: any(\Point.y)) != \Box.p.y { bad |= 64 }
  if any(\Box.p).appending(path: any(\Line.a)) != nil { bad |= 128 }
  return bad
}
