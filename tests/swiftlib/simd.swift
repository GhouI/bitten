// SIMD: Apple's sizes (SIMD2<Float> is one 8-byte builtin vector, which
// Swift's calling convention passes in xmm registers), element access, arithmetic,
// comparisons into masks, descriptions, hashing; ArraySlice.popFirst and
// synthesized Codable for an enum without payloads (which needs it).

@inline(never) func scale(_ v: SIMD2<Float>, _ k: Float) -> SIMD2<Float> { return v * k }

enum Mode: Codable { case on, off }

@_silgen_name("swl_simd") public func simd() -> Int {
  var bad = 0
  if MemoryLayout<SIMD2<Float>>.size != 8 || MemoryLayout<SIMD3<Float>>.size != 16 { bad |= 1 }
  if MemoryLayout<SIMD4<Double>>.size != 32 || MemoryLayout<SIMD16<UInt8>>.size != 16 { bad |= 2 }
  var v = SIMD4<Float>(1, 2, 3, 4)
  v.y = 20
  if v[1] != 20 || v.w != 4 || v.scalarCount != 4 { bad |= 4 }
  let a = SIMD3<Double>(x: 1, y: 2, z: 3), b = SIMD3<Double>(repeating: 2)
  if a + b != SIMD3(3, 4, 5) || a * 2 != SIMD3(2, 4, 6) || (a - b).sum() != 0 { bad |= 8 }
  if (a / b).max() != 1.5 || a.min() != 1 { bad |= 0x10 }
  let i = SIMD8<Int32>(0, 1, 2, 3, 4, 5, 6, 7)
  if (i &+ i)[7] != 14 || i.wrappedSum() != 28 { bad |= 0x20 }
  let m = a .> SIMD3<Double>(repeating: 1.5)
  if m[0] || !m[1] || !m[2] || !any(m) || all(m) { bad |= 0x40 }
  if String(describing: SIMD2<Float>(1, 2.5)) != "SIMD2<Float>(1.0, 2.5)" { bad |= 0x80 }
  var h1 = Hasher(), h2 = Hasher()
  SIMD2<Int>(3, 4).hash(into: &h1)
  SIMD2<Int>(3, 4).hash(into: &h2)
  if h1.finalize() != h2.finalize() { bad |= 0x100 }
  let lit: SIMD4<Int> = [1, 2, 3, 4]
  if lit != SIMD4(lowHalf: SIMD2(1, 2), highHalf: SIMD2(3, 4)) { bad |= 0x200 }
  var slice = [1, 2, 3][...]
  if slice.popFirst() != 1 || slice.popFirst() != 2 || slice.count != 1 { bad |= 0x400 }
  var empty = [Int]()[...]
  if empty.popFirst() != nil { bad |= 0x800 }
  _ = Mode.on
  if scale(SIMD2(1.5, -2), 4) != SIMD2(6, -8) { bad |= 0x1000 }
  if MemoryLayout<SIMD2<Float>>.alignment != 8 { bad |= 0x2000 }
  return bad
}
