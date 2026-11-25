// Hashable and Hasher: SipHash-1-3 with the per-process seed, integer, Bool,
// Optional and ObjectIdentifier hashing, generic code through witness
// tables, and the hashes a user type gets from the compiler.

@inline(never) func hashOf<H: Hashable>(_ x: H) -> Int { x.hashValue }
@inline(never) func rawHashOf<H: Hashable>(_ x: H, _ seed: Int) -> Int { x._rawHashValue(seed: seed) }
@inline(never) func viaHasher<H: Hashable>(_ x: H) -> Int {
  var h = Hasher()
  h.combine(x)
  return h.finalize()
}

@_silgen_name("swl_hash_int") public func hashInt(_ v: Int) -> Int {
  var h = Hasher()
  h.combine(v)
  return h.finalize()
}

@_silgen_name("swl_hash_mixed") public func hashMixed() -> Int {
  var g = Hasher()
  g.combine(UInt8(7))
  g.combine(UInt16(0x1234))
  g.combine(true)
  g.combine(Int32(-5))
  return g.finalize()
}

@_silgen_name("swl_hash_value") public func hashValueOf(_ which: Int) -> Int {
  if which == 0 { return 42.hashValue }
  if which == 1 { return (7 as UInt8).hashValue }
  if which == 2 { return Optional<Int>.none.hashValue }
  if which == 3 { return Optional(3).hashValue }
  return true.hashValue
}

final class Thing {}

struct Point: Hashable {
  var x: Int
  var y: Int16
  var tag: Bool?
}

// Consistency between the ways of hashing the same value, generic and not:
// a bit for each check that failed.
@_silgen_name("swl_hash_consistency") public func consistency() -> Int {
  var bad = 0
  // hashValue, _rawHashValue(seed: 0) and a fresh Hasher agree.
  if hashOf(1234567) != viaHasher(1234567) { bad |= 1 }
  if 1234567.hashValue != rawHashOf(1234567, 0) { bad |= 2 }
  if hashOf(Int8(-3)) != viaHasher(Int8(-3)) { bad |= 4 }
  if hashOf(UInt32(99)) != (UInt32(99)).hashValue { bad |= 8 }
  if hashOf(Int64(5)) != hashOf(UInt64(5)) { bad |= 16 }   // same bytes
  if hashOf(Int16(5)) == hashOf(Int64(5)) { bad |= 32 }    // different byte counts
  // Seeds matter.
  if rawHashOf(77, 1) == rawHashOf(77, 2) { bad |= 64 }
  // Optional and Bool.
  let o: Int? = 9
  if hashOf(o) != viaHasher(o) || hashOf(o) == hashOf(9) { bad |= 128 }
  if hashOf(true) == hashOf(false) { bad |= 256 }
  // ObjectIdentifier.
  let a = Thing(), b = Thing()
  let ia = ObjectIdentifier(a), ib = ObjectIdentifier(b)
  if ia == ib || ia != ObjectIdentifier(a) { bad |= 512 }
  if hashOf(ia) != hashOf(UInt(bitPattern: ia)) { bad |= 1024 }
  if (ia < ib) == (ib < ia) { bad |= 2048 }
  if ObjectIdentifier(Int.self) != ObjectIdentifier(Int.self) ||
     ObjectIdentifier(Int.self) == ObjectIdentifier(Bool.self) { bad |= 4096 }
  if !(a === a) || a === b || !(a !== b) || (nil as AnyObject?) !== nil { bad |= 8192 }
  // A compiler-synthesized conformance.
  let p = Point(x: 1, y: 2, tag: nil), q = Point(x: 1, y: 2, tag: false)
  var hp = Hasher(); hp.combine(1); hp.combine(Int16(2)); hp.combine(Optional<Bool>.none)
  if hashOf(p) != hp.finalize() || hashOf(p) == hashOf(q) || p == q { bad |= 16384 }
  // Unicode.Scalar hashes as its UInt32 value.
  if hashOf(Unicode.Scalar(0x41 as UInt8)) != hashOf(UInt32(0x41)) { bad |= 32768 }
  return bad
}
