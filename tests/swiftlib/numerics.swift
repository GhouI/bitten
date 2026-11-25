// The integer protocol tower, used generically (through witness tables at
// -Onone): conversions, overflow reporting, smart shifts, strides.

@inline(never) func sum<T: FixedWidthInteger>(_ xs: T, _ ys: T, _ zs: T) -> T { xs + ys + zs }
@inline(never) func wrap<T: FixedWidthInteger>(_ x: T) -> T { x &+ T.max }
@inline(never) func convert<T: BinaryInteger, U: FixedWidthInteger>(_ x: T, to: U.Type) -> U? { U(exactly: x) }
@inline(never) func clamp<T: BinaryInteger, U: FixedWidthInteger>(_ x: T, to: U.Type) -> U { U(clamping: x) }
@inline(never) func steps<T: Strideable>(_ a: T, _ b: T) -> T.Stride { a.distance(to: b) }
@inline(never) func bits<T: FixedWidthInteger>(_ x: T) -> Int {
  x.nonzeroBitCount * 10000 + x.leadingZeroBitCount * 100 + x.trailingZeroBitCount
}

@_silgen_name("swn_generic") public func generic() -> Int {
  var r = 0
  if sum(1 as Int8, 2, 3) == 6 { r |= 1 }
  if wrap(1 as UInt8) == 0 { r |= 2 }
  if convert(300, to: UInt8.self) == nil { r |= 4 }
  if convert(-1, to: UInt.self) == nil { r |= 8 }
  if convert(-128, to: Int8.self) == -128 { r |= 16 }
  if clamp(-5, to: UInt16.self) == 0 && clamp(70000, to: UInt16.self) == 65535 { r |= 32 }
  if steps(10 as UInt64, 3) == -7 && steps(-3 as Int16, 4) == 7 { r |= 64 }
  if bits(0x00F0 as UInt16) == 4 * 10000 + 8 * 100 + 4 { r |= 128 }
  let (p, o) = (Int32.max).addingReportingOverflow(1)
  if o && p == Int32.min { r |= 256 }
  if (UInt32(0x12345678)).byteSwapped == 0x78563412 { r |= 512 }
  if (-16 as Int) >> 2 == -4 && (1 as Int) << 70 == 0 && (8 as UInt8) >> -1 == 16 { r |= 1024 }
  let qr = (7 as Int).quotientAndRemainder(dividingBy: 2)
  if qr.quotient == 3 && qr.remainder == 1 && (-7 as Int).signum() == -1 { r |= 2048 }
  return r
}
