// Floating point: IEEE arithmetic and comparisons, rounding, the bit-level
// properties, and conversions between floats and integers. The generic
// helpers go through the FloatingPoint/BinaryFloatingPoint witness tables
// at -Onone.

@inline(never) func hyp<T: FloatingPoint>(_ a: T, _ b: T) -> T { (a * a + b * b).squareRoot() }
@inline(never) func lessGeneric<T: FloatingPoint>(_ a: T, _ b: T) -> Bool { a < b }
@inline(never) func eqGeneric<T: FloatingPoint>(_ a: T, _ b: T) -> Bool { a == b }
@inline(never) func toInt<T: BinaryFloatingPoint, I: FixedWidthInteger>(_ x: T, _: I.Type) -> I? { I(exactly: x) }
@inline(never) func truncInt<T: BinaryFloatingPoint, I: FixedWidthInteger>(_ x: T, _: I.Type) -> I { I(x) }
@inline(never) func toFloat<I: BinaryInteger, T: BinaryFloatingPoint>(_ x: I, _: T.Type) -> T { T(x) }
@inline(never) func toFloatExactly<I: BinaryInteger, T: BinaryFloatingPoint>(_ x: I, _: T.Type) -> T? { T(exactly: x) }
@inline(never) func convert<S: BinaryFloatingPoint, T: BinaryFloatingPoint>(_ x: S, _: T.Type) -> T { T(x) }
@inline(never) func convertExactly<S: BinaryFloatingPoint, T: BinaryFloatingPoint>(_ x: S, _: T.Type) -> T? { T(exactly: x) }
@inline(never) func classify<T: FloatingPoint>(_ x: T) -> FloatingPointClassification { x.floatingPointClass }
@inline(never) func roundGeneric<T: FloatingPoint>(_ x: T, _ rule: FloatingPointRoundingRule) -> T { x.rounded(rule) }
@inline(never) func pieces<T: BinaryFloatingPoint>(_ x: T) -> (T.Exponent, T) { (x.exponent, x.significand) }
@inline(never) func build<T: FloatingPoint>(_ s: FloatingPointSign, _ e: T.Exponent, _ m: T) -> T {
  T(sign: s, exponent: e, significand: m)
}
@inline(never) func opaque(_ x: Double) -> Double { x }
@inline(never) func hashOf<T: Hashable>(_ x: T) -> Int { x.hashValue }
@inline(never) func hashInto<T: Hashable>(_ x: T) -> Int {
  var h = Hasher()
  h.combine(x)
  return h.finalize()
}

// Values crossing into C: doubles and floats travel in xmm registers in
// both conventions.
@_silgen_name("swf_hypot") public func swfHypot(_ a: Double, _ b: Double) -> Double { hyp(a, b) }
@_silgen_name("swf_hypotf") public func swfHypotf(_ a: Float, _ b: Float) -> Float { hyp(a, b) }
@_silgen_name("swf_round") public func swfRound(_ x: Double, _ rule: Int) -> Double {
  var r: FloatingPointRoundingRule = .toNearestOrAwayFromZero
  if rule == 1 { r = .toNearestOrEven }
  if rule == 2 { r = .up }
  if rule == 3 { r = .down }
  if rule == 4 { r = .towardZero }
  if rule == 5 { r = .awayFromZero }
  return roundGeneric(x, r)
}
@_silgen_name("swf_rem") public func swfRem(_ x: Double, _ y: Double) -> Double { x.remainder(dividingBy: y) }
@_silgen_name("swf_fmod") public func swfFmod(_ x: Double, _ y: Double) -> Double { x.truncatingRemainder(dividingBy: y) }
@_silgen_name("swf_to_int") public func swfToInt(_ x: Double) -> Int { truncInt(x, Int.self) }
@_silgen_name("swf_from_int") public func swfFromInt(_ x: Int) -> Double { toFloat(x, Double.self) }
@_silgen_name("swf_from_uint") public func swfFromUInt(_ x: UInt) -> Double { toFloat(x, Double.self) }
@_silgen_name("swf_bits") public func swfBits(_ x: Double) -> UInt64 { x.bitPattern }
@_silgen_name("swf_pi") public func swfPi() -> Double { .pi }
// A literal type whose literals are Doubles: a generic literal of it is
// converted by Double's _ExpressibleByBuiltinIntegerLiteral witness at run
// time, which for literals wider than 64 bits calls swift_intToFloat64.
struct Wide: ExpressibleByIntegerLiteral {
  var d: Double
  init(integerLiteral v: Double) { d = v }
}
struct Narrow: ExpressibleByIntegerLiteral {
  var f: Float
  init(integerLiteral v: Float) { f = v }
}
@inline(never) func big<T: ExpressibleByIntegerLiteral>(_: T.Type) -> T { 36893488147419103232 }  // 2^65
@inline(never) func odd<T: ExpressibleByIntegerLiteral>(_: T.Type) -> T { -36893488147419103233 }
@inline(never) func huge<T: ExpressibleByIntegerLiteral>(_: T.Type) -> T {
  340282356779733661637539395458142568448  // 2^128 - 2^103: rounds up to infinity in Float
}
@_silgen_name("swf_big_literal") public func swfBigLiteral() -> Double {
  let x: Double = 36893488147419103232
  return big(Wide.self).d - odd(Wide.self).d + x
}
@_silgen_name("swf_big_literal_f") public func swfBigLiteralF() -> Float {
  return huge(Narrow.self).f
}

@_silgen_name("swf_ieee") public func ieee() -> Int {
  var r = 0
  let nan = Double.nan
  if !(nan == nan) && nan != nan && !lessGeneric(nan, 1.0) && !lessGeneric(1.0, nan) && !eqGeneric(nan, nan) { r |= 1 }
  if eqGeneric(0.0, -0.0) && (-0.0 as Double).sign == .minus && (0.0 as Double).sign == .plus { r |= 2 }
  if Double.infinity > Double.greatestFiniteMagnitude && -Double.infinity < -Double.greatestFiniteMagnitude { r |= 4 }
  if (1.0 / opaque(0.0)) == .infinity && (opaque(0.0) / opaque(0.0)).isNaN { r |= 8 }
  if classify(Double.signalingNaN) == .signalingNaN && classify(-Double.nan) == .quietNaN
    && classify(-Double.infinity) == .negativeInfinity && classify(Double.leastNonzeroMagnitude) == .positiveSubnormal
    && classify(-0.0 as Double) == .negativeZero && classify(1.5 as Float) == .positiveNormal { r |= 16 }
  if Double.minimum(.nan, 2) == 2 && Double.maximum(1, .nan) == 1 && Double.minimum(-0.0, 3) == -0.0 { r |= 32 }
  if (2.0 as Double).isTotallyOrdered(belowOrEqualTo: .nan) && (-0.0 as Double).isTotallyOrdered(belowOrEqualTo: 0.0)
    && !(0.0 as Double).isTotallyOrdered(belowOrEqualTo: -0.0) { r |= 64 }
  if (5.0 as Double).addingProduct(2, 3) == 11 && (-7.5 as Double).magnitude == 7.5 { r |= 128 }
  return r
}

@_silgen_name("swf_bitlevel") public func bitlevel() -> Int {
  var r = 0
  if Double.ulpOfOne == 2.220446049250313e-16 && Float.ulpOfOne.bitPattern == 0x3400_0000 { r |= 1 }
  if (1.0 as Double).nextUp == 1.0 + Double.ulpOfOne && (1.0 as Double).nextDown == 1.0 - Double.ulpOfOne / 2 { r |= 2 }
  if (0.0 as Double).nextUp == Double.leastNonzeroMagnitude && (-Double.leastNonzeroMagnitude).nextUp.isZero
    && Double.greatestFiniteMagnitude.nextUp == .infinity && (-Double.infinity).nextUp == -Double.greatestFiniteMagnitude { r |= 4 }
  let (e, m) = pieces(12.0 as Double)
  if e == 3 && m == 1.5 { r |= 8 }
  let (se, sm) = pieces(Double.leastNonzeroMagnitude * 3)
  if se == -1073 && sm == 1.5 { r |= 16 }
  if build(.minus, 3, 1.5 as Double) == -12 && build(.plus, -1074, 1.0 as Double) == .leastNonzeroMagnitude
    && build(.plus, 2000, 0.25 as Double) == .infinity && build(.plus, -1100, 1.0 as Double) == 0 { r |= 32 }
  if (12.0 as Double).binade == 8 && (12.0 as Double).significandWidth == 1 && (1.0 as Double).significandWidth == 0
    && (Double.leastNonzeroMagnitude * 6).binade == Double.leastNonzeroMagnitude * 4 { r |= 64 }
  if Double(sign: .minus, exponentBitPattern: 1023, significandBitPattern: 1 << 51) == -1.5
    && (-1.5 as Double).exponentBitPattern == 1023 && (-1.5 as Double).significandBitPattern == 1 << 51 { r |= 128 }
  if (1.0 as Double).ulp == Double.ulpOfOne && Double.leastNonzeroMagnitude.ulp == Double.leastNonzeroMagnitude
    && Double.infinity.ulp.isNaN { r |= 256 }
  if Double(nan: 5, signaling: true).isSignalingNaN && !Double(nan: 5, signaling: false).isSignalingNaN
    && Double(nan: 5, signaling: false).significandBitPattern == (1 << 51) | 5 { r |= 512 }
  if Double(signOf: -2, magnitudeOf: 3) == -3 && Float(signOf: 1, magnitudeOf: -4) == 4 { r |= 1024 }
  if Float.pi.bitPattern == 0x4049_0FDA && Double.pi.bitPattern == 0x4009_21FB_5444_2D18 { r |= 2048 }
  return r
}

@_silgen_name("swf_conversions") public func conversions() -> Int {
  var r = 0
  if truncInt(3.99 as Double, Int.self) == 3 && truncInt(-3.99 as Float, Int8.self) == -3 && Int(-0.5) == 0 { r |= 1 }
  if toInt(128.0 as Double, Int8.self) == nil && toInt(-128.0 as Double, Int8.self) == -128 && toInt(1.5 as Float, Int.self) == nil { r |= 2 }
  if toInt(-1.0 as Double, UInt.self) == nil && toInt(18446744073709549568.0 as Double, UInt64.self) == 18446744073709549568 { r |= 4 }
  if toInt(9223372036854775808.0 as Double, Int64.self) == nil && toInt(-9223372036854775808.0 as Double, Int64.self) == Int64.min { r |= 8 }
  if toInt(Double.nan, Int.self) == nil && toInt(Double.infinity, Int32.self) == nil && toInt(-0.0 as Double, UInt8.self) == 0 { r |= 16 }
  if toFloat(UInt64.max, Double.self) == 18446744073709551616.0 && toFloat(16777217 as Int32, Float.self) == 16777216 { r |= 32 }
  if toFloatExactly(Int64.max, Double.self) == nil && toFloatExactly(1 << 53 as Int, Double.self) == 9007199254740992.0
    && toFloatExactly(UInt64.max, Float80.self) == 18446744073709551615.0 { r |= 64 }
  if convert(0.1 as Double, Float.self) == (0.1 as Float) && convert(Float.greatestFiniteMagnitude, Double.self) == Double(Float.greatestFiniteMagnitude)
    && convert(1e300 as Double, Float.self) == .infinity { r |= 128 }
  if convertExactly(0.1 as Double, Float.self) == nil && convertExactly(0.5 as Double, Float.self) == 0.5
    && convertExactly(Double.nan, Float80.self) == nil && convertExactly(0.1 as Float, Double.self) != nil { r |= 256 }
  if convert(Double.leastNonzeroMagnitude, Float.self) == 0 && convert(-Double.infinity, Float80.self) == -.infinity
    && convert(Float.leastNonzeroMagnitude, Double.self) == Double(Float.leastNonzeroMagnitude) { r |= 512 }
  if Int8(exactly: 127.0 as Float80) == 127 && UInt16(65535.9 as Double) == 65535 && Int32(exactly: -2147483648.0 as Float) == Int32.min { r |= 1024 }
  if Float(exactly: 16777217 as Int) == nil && Double(exactly: -5 as Int8) == -5 && Float80(UInt64.max) == 18446744073709551615.0 { r |= 2048 }
  return r
}

@_silgen_name("swf_float80") public func float80() -> Int {
  var r = 0
  let a: Float80 = 1.0 / 3.0
  if a * 3 == 1 && a.significandBitPattern != 0 && Float80.significandBitCount == 63 { r |= 1 }
  if (Float80.pi > 3.14159265358979 && Float80.pi < 3.1415926535897933) && Float80.pi.exponent == 1 { r |= 2 }
  if (2.0 as Float80).squareRoot() == 1.41421356237309504880 && (2.0 as Float80).squareRoot() != Float80(Double(2).squareRoot()) { r |= 4 }
  if Float80(Double.pi) != Float80.pi && Double(Float80.pi) == Double.pi { r |= 8 }
  if (Float80.leastNonzeroMagnitude * 4).significandWidth == 0 && (1.0 as Float80).nextUp > 1 && Float80.infinity.isInfinite
    && Float80.nan.isNaN && (-Float80.greatestFiniteMagnitude).nextDown == -.infinity { r |= 16 }
  if (7.5 as Float80).rounded(.toNearestOrEven) == 8 && (-7.5 as Float80).rounded(.towardZero) == -7
    && (7.25 as Float80).remainder(dividingBy: 2) == -0.75 { r |= 32 }
  return r
}

@_silgen_name("swf_misc") public func misc() -> Int {
  var r = 0
  if (1.5 as Double).distance(to: 4) == 2.5 && (1.5 as Float).advanced(by: -2) == -0.5 { r |= 1 }
  let s = Double._step(after: (2, 1.5), from: 1, by: 0.25)
  if s.index == 3 && s.value == 1.75 { r |= 2 }
  var x: Double = 10
  x += 2; x -= 1; x *= 3; x /= 11
  if x == 3 { r |= 4 }
  if hashOf(0.0 as Double) == hashOf(-0.0 as Double) && hashOf(1.5 as Double) != hashOf(2.5 as Double)
    && hashInto(-0.0 as Float) == hashInto(0.0 as Float) && hashInto(-0.0 as Float80) == hashInto(0.0 as Float80)
    && hashInto(1.0 as Float80) != hashInto(-1.0 as Float80) && hashInto(1.0 as Double) == hashInto(1.0 as Double)
    && hashOf(FloatingPointSign.minus) == hashOf(1 as Int) { r |= 8 }
  return r
}
