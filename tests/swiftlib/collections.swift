// The sequence and collection protocols with their default implementations,
// ranges, slices and the small collection types, used generically.

// A user-defined mutable random-access collection over a fixed buffer.
struct Eight: RandomAccessCollection, MutableCollection {
  var a, b, c, d, e, f, g, h: Int
  var startIndex: Int { 0 }
  var endIndex: Int { 8 }
  subscript(i: Int) -> Int {
    get {
      switch i { case 0: return a; case 1: return b; case 2: return c; case 3: return d
      case 4: return e; case 5: return f; case 6: return g; default: return h }
    }
    set {
      switch i { case 0: a = newValue; case 1: b = newValue; case 2: c = newValue; case 3: d = newValue
      case 4: e = newValue; case 5: f = newValue; case 6: g = newValue; default: h = newValue }
    }
  }
}

// A forward-only linked sequence.
struct Countdown: Sequence, IteratorProtocol {
  var n: Int
  mutating func next() -> Int? { if n == 0 { return nil }; n -= 1; return n + 1 }
}

@inline(never) func total<S: Sequence>(_ s: S) -> Int where S.Element == Int {
  s.reduce(0, +)
}

@_silgen_name("swc_run") public func run() -> Int {
  var r = 0
  if total(1...10) == 55 && total(0..<4) == 6 { r |= 1 }
  if total(Countdown(n: 4)) == 10 && Countdown(n: 3).contains(2) { r |= 2 }
  var x = Eight(a: 5, b: 3, c: 8, d: 1, e: 9, f: 2, g: 7, h: 4)
  x.sort()
  if x.a == 1 && x.d == 4 && x.h == 9 && !x.contains(6) && x.allSatisfy({ (1...9).contains($0) }) { r |= 4 }
  if x.first == 1 && x.last == 9 && x.count == 8 && x.firstIndex(of: 7) == 5 { r |= 8 }
  let s = x[2..<5]
  if s.count == 3 && s.first == 3 && total(s) == 12 && s.indices == 2..<5 { r |= 16 }
  if total(x.dropFirst(6)) == 17 && total(x.prefix(2)) == 3 && total(x.suffix(1)) == 9 { r |= 32 }
  var e = 0
  for (i, v) in x.enumerated() where i == v - 1 { e += 1 }
  if e == 5 { r |= 64 }
  var z = 0
  for (p, q) in zip(0..<100, Countdown(n: 3)) { z += p * q }
  if z == 0 * 3 + 1 * 2 + 2 * 1 { r |= 128 }
  if total(CollectionOfOne(42)) == 42 && EmptyCollection<Int>().isEmpty { r |= 256 }
  x.reverse()
  if x.a == 9 && x.h == 1 { r |= 512 }
  let pivot = x.partition { $0 >= 5 }
  if x[..<pivot].allSatisfy({ $0 < 5 }) && x[pivot...].allSatisfy({ $0 >= 5 }) && pivot == 4 { r |= 1024 }
  if (3..<9).clamped(to: 5..<20) == 5..<9 && !(0..<2).overlaps(2..<4) && (1...3).contains(3) { r |= 2048 }
  return r
}
