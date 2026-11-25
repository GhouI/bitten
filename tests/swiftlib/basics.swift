// Ordinary Swift against bitten's own standard library (stdlib/): integer
// arithmetic, comparisons, Bool logic and Optional, at -O and -Onone.

@inline(never) func pick(_ c: Bool, _ a: Int, _ b: Int) -> Int { c ? a : b }

@_silgen_name("swl_arith") public func arith(_ a: Int, _ b: Int) -> Int {
  var x = a
  x += b * 3
  x -= 1
  return x / 2 + x % 5
}
@_silgen_name("swl_compare") public func compare(_ a: Int, _ b: Int) -> Int {
  var r = 0
  if a < b { r |= 1 }
  if a <= b { r |= 2 }
  if a > b { r |= 4 }
  if a >= b { r |= 8 }
  if a == b { r |= 16 }
  if a != b && !(a == b) { r |= 32 }
  return r
}
@_silgen_name("swl_unsigned") public func unsigned(_ a: UInt8) -> UInt8 {
  return (a &+ 200) &>> 1
}
@_silgen_name("swl_optional") public func optional(_ a: Int) -> Int {
  let o: Int? = a > 10 ? a : nil
  let p: Int?? = .some(o)
  guard case .some(let inner) = p else { return -100 }
  return (inner ?? -1) + pick(o == nil, 1000, 0)
}
