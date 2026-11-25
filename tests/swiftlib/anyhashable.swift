// AnyHashable: equality and hashing across wrapped types, unwrapping with
// dynamic casts, nesting, classes with a Hashable base class, and the
// compiler's implicit conversion. Returns a bit for each failed check.

class Animal: Hashable {
  let id: Int
  init(_ id: Int) { self.id = id }
  static func == (a: Animal, b: Animal) -> Bool { a.id == b.id }
  func hash(into h: inout Hasher) { h.combine(id) }
}
final class Dog: Animal {}

struct Key: Hashable {
  var a: Int
  var b: Int8?
}

@inline(never) func erase<H: Hashable>(_ x: H) -> AnyHashable { AnyHashable(x) }
@inline(never) func implicit(_ x: AnyHashable) -> AnyHashable { x }

@_silgen_name("swl_anyhashable") public func run() -> Int {
  var bad = 0
  let i1 = erase(42), i2 = erase(42), i3 = erase(43)
  if i1 != i2 || i1 == i3 { bad |= 1 }
  if i1.hashValue != 42.hashValue || i1.hashValue != i2.hashValue { bad |= 2 }
  var h = Hasher(); h.combine(i1)
  var g = Hasher(); g.combine(42)
  if h.finalize() != g.finalize() { bad |= 4 }
  if i1._rawHashValue(seed: 5) != 42._rawHashValue(seed: 5) { bad |= 8 }

  // Different types are different values.
  if erase(true) == erase(1) || erase(UInt8(1)) == erase(Int16(1)) { bad |= 16 }

  // base and casts back.
  if (i1.base as? Int) != 42 || (i1.base as? Bool) != nil { bad |= 32 }

  // A struct with a synthesized conformance, stored inline in the box.
  let k1 = erase(Key(a: 1, b: nil)), k2 = erase(Key(a: 1, b: nil)), k3 = erase(Key(a: 1, b: 0))
  if k1 != k2 || k1 == k3 || k1.hashValue != Key(a: 1, b: nil).hashValue { bad |= 64 }

  // Nesting does not wrap twice.
  let n = erase(erase(7))
  if n != erase(7) || (n.base as? Int) != 7 { bad |= 128 }

  // Classes: a subclass instance compares through the base class's ==, from
  // either side.
  let animal = erase(Animal(3)), dog = erase(Dog(3)) as AnyHashable, other = erase(Animal(4))
  if animal != dog || dog != animal || animal == other { bad |= 256 }

  // An Optional holding a value is that value, as on macOS; nil stays nil.
  let o1 = erase(Optional(5)), o2 = erase(Optional<Int>.none)
  if o1 == o2 || o1 != erase(Optional(5)) || o2 != erase(Optional<Int>.none) { bad |= 512 }
  if o1 != erase(5) || o1.hashValue != 5.hashValue || (o1.base as? Int) != 5 { bad |= 2048 }
  if erase(Optional(Optional(6))) != erase(6) || o2 == erase(0) { bad |= 4096 }

  // The compiler converts implicitly.
  if implicit(9) != erase(9) || implicit(Key(a: 2, b: 3)) != erase(Key(a: 2, b: 3)) { bad |= 1024 }
  return bad
}
