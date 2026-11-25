// MemoryLayout, typed and raw pointers, buffer pointers. Class elements make
// copies, moves and destruction observable through deinit counts.

@_silgen_name("swp_note_deinit") func noteDeinit(_ v: Int)

final class Token {
  let v: Int
  init(_ v: Int) { self.v = v }
  deinit { noteDeinit(v) }
}

struct Pair { var a: Int8; var b: Int64 }

@_silgen_name("swp_layout") public func layout() -> Int {
  var r = 0
  if MemoryLayout<Pair>.size == 16 && MemoryLayout<Pair>.alignment == 8 && MemoryLayout<Int8>.stride == 1 { r |= 1 }
  if MemoryLayout<Token>.size == 8 && MemoryLayout<Token?>.size == 8 && MemoryLayout<Int?>.size == 9 { r |= 2 }
  return r
}

/// Copies, overlapping moves and destruction of class references. The C
/// driver checks which deinits ran after each step.
@_silgen_name("swp_objects") public func objects(_ step: Int) -> Int {
  var r = 0
  let p = UnsafeMutablePointer<Token>.allocate(capacity: 4)
  p.initialize(repeating: Token(7), count: 2)    // one object, two references
  (p + 2).initialize(to: Token(8))
  (p + 3).initialize(to: Token(9))
  if p[0] === p[1] && p[2].v == 8 && p.pointee.v == 7 { r |= 1 }
  let q = UnsafeMutablePointer<Token>.allocate(capacity: 4)
  q.initialize(from: p, count: 4)                // a second reference to each
  p.deinitialize(count: 4)                       // nothing may die: q holds them
  p.deallocate()
  if step == 1 { return r }
  let first = q.move()                           // take q[0] out
  q.moveInitialize(from: q + 1, count: 3)        // overlapping move down
  if q[0].v == 7 && q[1].v == 8 && q[2].v == 9 && first.v == 7 { r |= 2 }
  q.deinitialize(count: 3)                       // 8 and 9 die; 7 lives in `first`
  q.deallocate()
  return r
}

@_silgen_name("swp_buffers") public func buffers() -> Int {
  var r = 0
  var b = UnsafeMutableBufferPointer<Int>.allocate(capacity: 6)
  var v = 5
  for i in 0..<6 { (b.baseAddress! + i).initialize(to: v); v = (v * 5) % 7 }   // 5 4 6 2 3 1
  b.sort()
  if b.elementsEqual(1...6) { r |= 1 }
  b.swapAt(0, 5)
  if b[0] == 6 && b[5] == 1 && b.count == 6 && b.reduce(0, +) == 21 { r |= 2 }
  let ro = UnsafeBufferPointer(b)
  if ro[1..<3].reduce(0, +) == 5 && ro.firstIndex(of: 4) == 3 { r |= 4 }
  let raw = UnsafeRawBufferPointer(ro)
  if raw.count == 48 && raw[0] == 6 && raw[8] == 2 && raw.load(fromByteOffset: 16, as: Int.self) == 3 { r |= 8 }
  b.deallocate()
  var x: UInt32 = 0x11223344
  let lo = withUnsafeBytes(of: &x) { $0[0] }
  withUnsafeMutableBytes(of: &x) { $0[3] = 0xAA }
  if lo == 0x44 && x == 0xAA223344 { r |= 16 }
  let m = UnsafeMutableRawPointer.allocate(byteCount: 32, alignment: 16)
  m.storeBytes(of: 0x0102030405060708 as UInt64, toByteOffset: 8, as: UInt64.self)
  if m.load(fromByteOffset: 8, as: UInt8.self) == 8 && Int(bitPattern: m) % 16 == 0 { r |= 32 }
  m.deallocate()
  return r
}
