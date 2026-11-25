#!/usr/bin/env python3
"""Generate stdlib Floats.swift: Float, Double and Float80 share one
template. Usage: gen-floats.py > Floats.swift

Each type is @frozen around a Builtin floating-point value, as the ABI
requires. Float and Double are IEEE binary32/binary64; Float80 is the x87
extended format, whose significand stores its integer bit explicitly."""

TYPES = [
    # name, builtin, bit width, raw significand, significand bits, exponent bits
    ("Float", "FPIEEE32", 32, "UInt32", 23, 8),
    ("Double", "FPIEEE64", 64, "UInt64", 52, 11),
    ("Float80", "FPIEEE80", 80, "UInt64", 63, 15),
]

# Fields of an IEEE type stored in one integer (Float, Double).
PACKED = """
  @inlinable public var bitPattern: $R {
    return $R(Builtin.bitcast_$FP_Int$W(_value))
  }
  @inlinable public init(bitPattern: $R) {
    self.init(Builtin.bitcast_Int$W_$FP(bitPattern._value))
  }
  @inlinable public var sign: FloatingPointSign {
    return bitPattern &>> $SIGNSHIFT == 0 ? .plus : .minus
  }
  @inlinable public var exponentBitPattern: UInt {
    return UInt(truncatingIfNeeded: bitPattern &>> $S) & $T._infinityExponent
  }
  @inlinable public var significandBitPattern: $R {
    return bitPattern & $T._significandMask
  }
  @inlinable
  public init(sign: FloatingPointSign, exponentBitPattern: UInt, significandBitPattern: $R) {
    let s: $R = sign == .minus ? 1 &<< $SIGNSHIFT : 0
    let e = $R(truncatingIfNeeded: exponentBitPattern & $T._infinityExponent) &<< $S
    self.init(bitPattern: s | e | (significandBitPattern & $T._significandMask))
  }
  @inlinable public var isCanonical: Bool { return true }
"""

# Float80: 64 significand bits with an explicit integer bit, then 16 bits
# of sign and exponent.
X87 = """
  @inlinable internal var _explicitSignificand: UInt64 {
    return UInt64(Builtin.truncOrBitCast_Int80_Int64(Builtin.bitcast_FPIEEE80_Int80(_value)))
  }
  @inlinable internal var _signAndExponent: UInt16 {
    let shifted = Builtin.lshr_Int80(Builtin.bitcast_FPIEEE80_Int80(_value),
                                     Builtin.zextOrBitCast_Int64_Int80((64 as Int64)._value))
    return UInt16(Builtin.truncOrBitCast_Int80_Int16(shifted))
  }
  @inlinable internal init(_explicitSignificand low: UInt64, signAndExponent high: UInt16) {
    let h = Builtin.shl_Int80(Builtin.zextOrBitCast_Int16_Int80(high._value),
                              Builtin.zextOrBitCast_Int64_Int80((64 as Int64)._value))
    self.init(Builtin.bitcast_Int80_FPIEEE80(Builtin.or_Int80(h, Builtin.zextOrBitCast_Int64_Int80(low._value))))
  }
  @inlinable public var sign: FloatingPointSign {
    return _signAndExponent &>> 15 == 0 ? .plus : .minus
  }
  @inlinable public var exponentBitPattern: UInt {
    return UInt(truncatingIfNeeded: _signAndExponent) & Float80._infinityExponent
  }
  @inlinable public var significandBitPattern: UInt64 {
    return _explicitSignificand & Float80._significandMask
  }
  @inlinable
  public init(sign: FloatingPointSign, exponentBitPattern: UInt, significandBitPattern: UInt64) {
    let e = exponentBitPattern & Float80._infinityExponent
    let high = UInt16(truncatingIfNeeded: e) | (sign == .minus ? 0x8000 : 0)
    let integerBit: UInt64 = e == 0 ? 0 : 1 &<< 63
    self.init(_explicitSignificand: (significandBitPattern & Float80._significandMask) | integerBit,
              signAndExponent: high)
  }
  // The integer bit must agree with the exponent (unnormals and pseudo-
  // denormals are not canonical).
  @inlinable public var isCanonical: Bool {
    let integerBit = _explicitSignificand &>> 63 != 0
    let e = exponentBitPattern
    if e == 0 { return !integerBit }
    return integerBit
  }
"""

COMMON = """
// ---- $T ----
@frozen public struct $T: Sendable {
  public var _value: Builtin.$FP
  @_transparent public init() { _value = Builtin.zeroInitializer() }
  @_transparent public init(_ _value: Builtin.$FP) { self._value = _value }
}

extension $T: BinaryFloatingPoint {
  public typealias Magnitude = $T
  public typealias Exponent = Int
  public typealias RawSignificand = $R
  public typealias RawExponent = UInt
  public typealias FloatLiteralType = $T
  public typealias Stride = $T

  @inlinable public static var exponentBitCount: Int { return $E }
  @inlinable public static var significandBitCount: Int { return $S }
  @usableFromInline internal static var _infinityExponent: UInt {
    @inline(__always) get { return $INFEXP }
  }
  @usableFromInline internal static var _exponentBias: UInt {
    @inline(__always) get { return $BIAS }
  }
  @usableFromInline internal static var _significandMask: $R {
    @inline(__always) get { return ($R(1) &<< $S) &- 1 }
  }
  @usableFromInline internal static var _quietNaNMask: $R {
    @inline(__always) get { return $R(1) &<< ($S - 1) }
  }
$FIELDS
  @inlinable public static var infinity: $T {
    return $T(sign: .plus, exponentBitPattern: _infinityExponent, significandBitPattern: 0)
  }
  @inlinable public static var nan: $T {
    return $T(sign: .plus, exponentBitPattern: _infinityExponent, significandBitPattern: _quietNaNMask)
  }
  @inlinable public static var signalingNaN: $T {
    return $T(sign: .plus, exponentBitPattern: _infinityExponent, significandBitPattern: _quietNaNMask &>> 1)
  }
  @inlinable public static var greatestFiniteMagnitude: $T {
    return $T(sign: .plus, exponentBitPattern: _infinityExponent - 1, significandBitPattern: _significandMask)
  }
  /// pi rounded toward zero, as the standard library documents it.
  @inlinable public static var pi: $T {
    return $T(sign: .plus, exponentBitPattern: _exponentBias + 1, significandBitPattern: $PI)
  }
  @inlinable public static var leastNormalMagnitude: $T {
    return $T(sign: .plus, exponentBitPattern: 1, significandBitPattern: 0)
  }
  @inlinable public static var leastNonzeroMagnitude: $T {
    return $T(sign: .plus, exponentBitPattern: 0, significandBitPattern: 1)
  }
  @inlinable public static var ulpOfOne: $T {
    return $T(sign: .plus, exponentBitPattern: _exponentBias - $S, significandBitPattern: 0)
  }

  @inlinable public var ulp: $T {
    if !isFinite { return .nan }
    let e = exponentBitPattern
    if e > $S {
      return $T(sign: .plus, exponentBitPattern: e - $S, significandBitPattern: 0)
    }
    let shift = e == 0 ? 0 : e - 1
    return $T(sign: .plus, exponentBitPattern: 0, significandBitPattern: $R(1) &<< $R(truncatingIfNeeded: shift))
  }

  /// The unbiased exponent; Int.min for zero, Int.max for infinity and NaN.
  @inlinable public var exponent: Int {
    if !isFinite { return .max }
    if isZero { return .min }
    let e = Int(truncatingIfNeeded: exponentBitPattern)
    let bias = Int(truncatingIfNeeded: $T._exponentBias)
    if e != 0 { return e - bias }
    let width = $R.bitWidth - significandBitPattern.leadingZeroBitCount
    return 1 - bias - $S + width - 1
  }

  @inlinable public var significand: $T {
    if isNaN { return self }
    if isInfinite { return .infinity }
    if isZero { return 0 }
    var bits = significandBitPattern
    if exponentBitPattern == 0 {
      let width = $R.bitWidth - bits.leadingZeroBitCount
      bits = (bits &<< $R(truncatingIfNeeded: $S - width + 1)) & $T._significandMask
    }
    return $T(sign: .plus, exponentBitPattern: $T._exponentBias, significandBitPattern: bits)
  }

  /// An exact power of two, for 2^e within the representable range
  /// (subnormal powers included).
  @inlinable internal static func _powerOfTwo(_ e: Int) -> $T {
    let bias = Int(truncatingIfNeeded: _exponentBias)
    if e >= 1 - bias {
      return $T(sign: .plus, exponentBitPattern: UInt(truncatingIfNeeded: e + bias), significandBitPattern: 0)
    }
    return $T(sign: .plus, exponentBitPattern: 0,
              significandBitPattern: $R(1) &<< $R(truncatingIfNeeded: e - (1 - bias - $S)))
  }

  /// significand * 2^exponent, negated when sign is minus. Scaling is done
  /// by exact powers of two; only the last multiplication rounds.
  @inlinable public init(sign: FloatingPointSign, exponent: Int, significand: $T) {
    let bias = Int(truncatingIfNeeded: $T._exponentBias)
    let maxStep = bias
    let minStep = 1 - bias - $S
    var x = significand
    var e = exponent
    if e > maxStep {
      if e > 3 * maxStep { e = 3 * maxStep }
      while e > maxStep { x = x * $T._powerOfTwo(maxStep); e -= maxStep }
    } else if e < minStep {
      if e < 3 * minStep { e = 3 * minStep }
      while e < minStep { x = x * $T._powerOfTwo(1 - bias); e -= 1 - bias }
    }
    x = x * $T._powerOfTwo(e)
    self = sign == .minus ? -x : x
  }

  @inlinable public init(nan payload: $R, signaling: Bool) {
    if payload >= $T._quietNaNMask &>> 1 { Builtin.int_trap() }
    let bits = payload | ($T._quietNaNMask &>> (signaling ? 1 : 0))
    self.init(sign: .plus, exponentBitPattern: $T._infinityExponent, significandBitPattern: bits)
  }

  @inlinable public var nextUp: $T {
    if isNaN { return self + 0 }
    if sign == .minus {
      if isZero { return $T.leastNonzeroMagnitude }
      // Toward zero: one step down in magnitude.
      var e = exponentBitPattern
      var s = significandBitPattern
      if s == 0 { e -= 1; s = $T._significandMask } else { s -= 1 }
      return $T(sign: .minus, exponentBitPattern: e, significandBitPattern: s)
    }
    if isInfinite { return self }
    if isZero { return $T.leastNonzeroMagnitude }
    var e = exponentBitPattern
    var s = significandBitPattern
    if s == $T._significandMask { e += 1; s = 0 } else { s += 1 }
    return $T(sign: .plus, exponentBitPattern: e, significandBitPattern: s)
  }

  @inlinable public var isNormal: Bool {
    let e = exponentBitPattern
    return e != 0 && e != $T._infinityExponent
  }
  @inlinable public var isFinite: Bool { return exponentBitPattern != $T._infinityExponent }
  @inlinable public var isZero: Bool { return exponentBitPattern == 0 && significandBitPattern == 0 }
  @inlinable public var isSubnormal: Bool { return exponentBitPattern == 0 && significandBitPattern != 0 }
  @inlinable public var isInfinite: Bool {
    return exponentBitPattern == $T._infinityExponent && significandBitPattern == 0
  }
  @_transparent public var isNaN: Bool { return Bool(Builtin.fcmp_uno_$FP(_value, _value)) }
  @inlinable public var isSignalingNaN: Bool {
    return isNaN && significandBitPattern & $T._quietNaNMask == 0
  }

  @inlinable public var binade: $T {
    if !isFinite { return .nan }
    if exponentBitPattern != 0 {
      return $T(sign: sign, exponentBitPattern: exponentBitPattern, significandBitPattern: 0)
    }
    let s = significandBitPattern
    if s == 0 { return self }
    let top = $R(1) &<< $R(truncatingIfNeeded: $R.bitWidth - 1 - s.leadingZeroBitCount)
    return $T(sign: sign, exponentBitPattern: 0, significandBitPattern: top)
  }

  /// Fraction bits needed after the leading one; -1 for zero, infinity, NaN.
  @inlinable public var significandWidth: Int {
    if !isFinite || isZero { return -1 }
    let s = significandBitPattern
    if exponentBitPattern != 0 {
      return s == 0 ? 0 : $S - s.trailingZeroBitCount
    }
    return $R.bitWidth - 1 - s.leadingZeroBitCount - s.trailingZeroBitCount
  }

  @inlinable public init(floatLiteral value: $T) { self = value }

  @inlinable public init(signOf sign: $T, magnitudeOf mag: $T) {
    _value = Builtin.int_copysign_$FP(mag._value, sign._value)
  }

  @inlinable public mutating func round(_ rule: FloatingPointRoundingRule) {
    switch rule {
    case .toNearestOrAwayFromZero: _value = Builtin.int_round_$FP(_value)
    case .toNearestOrEven: _value = Builtin.int_rint_$FP(_value)
    case .up: _value = Builtin.int_ceil_$FP(_value)
    case .down: _value = Builtin.int_floor_$FP(_value)
    case .towardZero: _value = Builtin.int_trunc_$FP(_value)
    case .awayFromZero:
      _value = sign == .minus ? Builtin.int_floor_$FP(_value) : Builtin.int_ceil_$FP(_value)
    @unknown default: Builtin.int_trap()
    }
  }

  @_transparent public mutating func negate() { _value = Builtin.fneg_$FP(_value) }
  @_transparent public static func += (lhs: inout $T, rhs: $T) { lhs._value = Builtin.fadd_$FP(lhs._value, rhs._value) }
  @_transparent public static func -= (lhs: inout $T, rhs: $T) { lhs._value = Builtin.fsub_$FP(lhs._value, rhs._value) }
  @_transparent public static func *= (lhs: inout $T, rhs: $T) { lhs._value = Builtin.fmul_$FP(lhs._value, rhs._value) }
  @_transparent public static func /= (lhs: inout $T, rhs: $T) { lhs._value = Builtin.fdiv_$FP(lhs._value, rhs._value) }

  /// IEEE remainder: self - n * other, n the integer nearest self / other
  /// (ties to even). Reduced modulo 2|other| first (exact, and it keeps the
  /// parity of n), then at most two subtractions of |other|, each exact
  /// because the operands are within a factor of two.
  @inlinable public mutating func formRemainder(dividingBy other: $T) {
    if isNaN || other.isNaN || isInfinite || other.isZero { self = .nan; return }
    if other.isInfinite { return }
    let negative = sign == .minus
    let y = other.magnitude
    var a = magnitude
    let twice = y + y
    if twice.isFinite { a.formTruncatingRemainder(dividingBy: twice) }
    var odd = false
    if a >= y { a -= y; odd = true }
    // a + a is exact, or overflows only when it is certainly above y.
    let doubled = a + a
    if doubled > y || (doubled == y && odd) { a -= y }
    self = negative ? -a : a
  }
  @inlinable public mutating func formTruncatingRemainder(dividingBy other: $T) {
    _value = Builtin.frem_$FP(_value, other._value)
  }
  @_transparent public mutating func formSquareRoot() { _value = Builtin.int_sqrt_$FP(_value) }
  @_transparent public mutating func addProduct(_ lhs: $T, _ rhs: $T) {
    _value = Builtin.int_fma_$FP(lhs._value, rhs._value, _value)
  }

  @_transparent public func isEqual(to other: $T) -> Bool {
    return Bool(Builtin.fcmp_oeq_$FP(_value, other._value))
  }
  @_transparent public func isLess(than other: $T) -> Bool {
    return Bool(Builtin.fcmp_olt_$FP(_value, other._value))
  }
  @_transparent public func isLessThanOrEqualTo(_ other: $T) -> Bool {
    return Bool(Builtin.fcmp_ole_$FP(_value, other._value))
  }
}

extension $T: _ExpressibleByBuiltinIntegerLiteral, ExpressibleByIntegerLiteral {
  @_transparent public init(_builtinIntegerLiteral value: Builtin.IntLiteral) {
    _value = Builtin.itofp_with_overflow_IntLiteral_$FP(value)
  }
  @_transparent public init(integerLiteral value: Int64) {
    _value = Builtin.sitofp_Int64_$FP(value._value)
  }
  public typealias IntegerLiteralType = Int64
}

extension $T: _ExpressibleByBuiltinFloatLiteral {
  @_transparent public init(_builtinFloatLiteral value: Builtin.FPIEEE80) {
    _value = $FROMLIT
  }
}

extension $T {
  @inlinable public var magnitude: $T { return $T(Builtin.int_fabs_$FP(_value)) }
  @_transparent public static prefix func - (x: $T) -> $T { return $T(Builtin.fneg_$FP(x._value)) }
  @_transparent public static func + (lhs: $T, rhs: $T) -> $T { return $T(Builtin.fadd_$FP(lhs._value, rhs._value)) }
  @_transparent public static func - (lhs: $T, rhs: $T) -> $T { return $T(Builtin.fsub_$FP(lhs._value, rhs._value)) }
  @_transparent public static func * (lhs: $T, rhs: $T) -> $T { return $T(Builtin.fmul_$FP(lhs._value, rhs._value)) }
  @_transparent public static func / (lhs: $T, rhs: $T) -> $T { return $T(Builtin.fdiv_$FP(lhs._value, rhs._value)) }
}

extension $T {
  @_transparent public func distance(to other: $T) -> $T { return other - self }
  @_transparent public func advanced(by amount: $T) -> $T { return self + amount }
}

// Conversions from integers: one rounding, to nearest even.
extension $T {
  @_transparent public init(_ v: Int) { _value = Builtin.sitofp_Int64_$FP(v._value) }
  @inlinable public init<Source: BinaryInteger>(_ value: Source) {
    if value.bitWidth <= 64 {
      if Source.isSigned {
        _value = Builtin.sitofp_Int64_$FP(Int64(truncatingIfNeeded: value)._value)
      } else {
        _value = Builtin.uitofp_Int64_$FP(UInt64(truncatingIfNeeded: value)._value)
      }
    } else {
      self = $T._convert(from: value).value
    }
  }
  @inlinable public init?<Source: BinaryInteger>(exactly value: Source) {
    let (v, exact) = $T._convert(from: value)
    if !exact { return nil }
    self = v
  }
}
"""

# Equal values hash alike: both zeros hash as +0. NaNs hash by their bits.
HASH_PACKED = """
extension $T: Hashable {
  @inlinable public func hash(into hasher: inout Hasher) {
    hasher._combine(isZero ? 0 : bitPattern)
  }
  @inlinable public func _rawHashValue(seed: Int) -> Int {
    return Hasher._hash(seed: seed, bytes: UInt64(isZero ? 0 : bitPattern), count: $BYTES)
  }
  public var hashValue: Int { return _hashValue(for: self) }
}
"""
HASH_X87 = """
extension Float80: Hashable {
  @inlinable public func hash(into hasher: inout Hasher) {
    if isZero { hasher._combine(0 as UInt64); hasher._combine(0 as UInt16); return }
    hasher._combine(_explicitSignificand)
    hasher._combine(_signAndExponent)
  }
  public var hashValue: Int { return _hashValue(for: self) }
}
"""

def conversions(name, fp, others):
    out = ["\n// Conversions between the floating-point types.\nextension %s {" % name]
    for oname, ofp, owidth in others:
        if ofp == fp:
            body = "_value = other._value"
            exact = "self = other\n    if other.isNaN { return nil }"
        else:
            mine = dict((t[0], t[2]) for t in TYPES)[name]
            op = "fpext" if owidth < mine else "fptrunc"
            body = f"_value = Builtin.{op}_{ofp}_{fp}(other._value)"
            exact = (f"self.init(other)\n"
                     f"    if {oname}(self) != other {{ return nil }}")
        out.append(f"""  @inlinable public init(_ other: {oname}) {{ {body} }}
  @inlinable public init?(exactly other: {oname}) {{
    {exact}
  }}""")
    out.append("}")
    return "\n".join(out)

PI = {"Float": "0x490FDA", "Double": "0x921FB54442D18", "Float80": "0x490FDAA22168C234"}

def gen(name, fp, width, raw, sig, exp):
    fields = X87 if name == "Float80" else PACKED
    fromlit = "value" if fp == "FPIEEE80" else f"Builtin.fptrunc_FPIEEE80_{fp}(value)"
    text = COMMON.replace("$FIELDS", fields) + (HASH_X87 if name == "Float80" else HASH_PACKED)
    subst = {
        "$T": name, "$FP": fp, "$R": raw, "$W": str(width), "$S": str(sig), "$E": str(exp),
        "$SIGNSHIFT": str(width - 1), "$INFEXP": str((1 << exp) - 1),
        "$BIAS": str((1 << (exp - 1)) - 1), "$BYTES": str(width // 8), "$PI": PI[name], "$FROMLIT": fromlit,
    }
    for k in sorted(subst, key=len, reverse=True):
        text = text.replace(k, subst[k])
    others = [(t[0], t[1], t[2]) for t in TYPES]
    return text + conversions(name, fp, others)

print("// Generated by tools/gen-floats.py. Do not edit.")
for t in TYPES:
    print(gen(*t))
