#!/usr/bin/env python3
"""Generate stdlib Integers.swift: the ten fixed-width integer types share
one template. Usage: gen-integers.py > Integers.swift"""

TYPES = [  # name, bits, signed
    ("Int8", 8, True), ("Int16", 16, True), ("Int32", 32, True), ("Int64", 64, True),
    ("Int", 64, True),
    ("UInt8", 8, False), ("UInt16", 16, False), ("UInt32", 32, False), ("UInt64", 64, False),
    ("UInt", 64, False),
]

def one(name, bits, signed):
    b = f"Int{bits}"
    s = "s" if signed else "u"
    cmp_lt = f"Builtin.cmp_{'s' if signed else 'u'}lt_{b}"
    cmp_le = f"Builtin.cmp_{'s' if signed else 'u'}le_{b}"
    div = f"Builtin.{'s' if signed else 'u'}div_{b}"
    rem = f"Builtin.{'s' if signed else 'u'}rem_{b}"
    shr = f"Builtin.{'a' if signed else 'l'}shr_{b}"
    lit = (f"Builtin.s_to_{s}_checked_trunc_IntLiteral_{b}(value).0")
    return f"""
// ---- {name} ----
@frozen public struct {name}: Sendable {{
  public var _value: Builtin.{b}
  @_transparent public init(_ _value: Builtin.{b}) {{ self._value = _value }}
  @_transparent public init() {{ _value = Builtin.zeroInitializer() }}
}}
extension {name}: _ExpressibleByBuiltinIntegerLiteral, ExpressibleByIntegerLiteral {{
  @_transparent public init(_builtinIntegerLiteral value: Builtin.IntLiteral) {{ _value = {lit} }}
  @_transparent public init(integerLiteral value: {name}) {{ self = value }}
  public typealias IntegerLiteralType = {name}
}}
extension {name}: Equatable {{
  @_transparent public static func == (lhs: {name}, rhs: {name}) -> Bool {{
    return Bool(Builtin.cmp_eq_{b}(lhs._value, rhs._value))
  }}
}}
extension {name}: Comparable {{
  @_transparent public static func < (lhs: {name}, rhs: {name}) -> Bool {{ return Bool({cmp_lt}(lhs._value, rhs._value)) }}
  @_transparent public static func <= (lhs: {name}, rhs: {name}) -> Bool {{ return Bool({cmp_le}(lhs._value, rhs._value)) }}
  @_transparent public static func > (lhs: {name}, rhs: {name}) -> Bool {{ return rhs < lhs }}
  @_transparent public static func >= (lhs: {name}, rhs: {name}) -> Bool {{ return rhs <= lhs }}
}}
extension {name} {{
  public static var bitWidth: Int {{ return {bits} }}
  public static var isSigned: Bool {{ return {'true' if signed else 'false'} }}
  @_transparent public static func + (lhs: {name}, rhs: {name}) -> {name} {{
    let (r, o) = Builtin.{s}add_with_overflow_{b}(lhs._value, rhs._value, false._value)
    if Bool(o) {{ Builtin.int_trap() }}
    return {name}(r)
  }}
  @_transparent public static func - (lhs: {name}, rhs: {name}) -> {name} {{
    let (r, o) = Builtin.{s}sub_with_overflow_{b}(lhs._value, rhs._value, false._value)
    if Bool(o) {{ Builtin.int_trap() }}
    return {name}(r)
  }}
  @_transparent public static func * (lhs: {name}, rhs: {name}) -> {name} {{
    let (r, o) = Builtin.{s}mul_with_overflow_{b}(lhs._value, rhs._value, false._value)
    if Bool(o) {{ Builtin.int_trap() }}
    return {name}(r)
  }}
  @_transparent public static func / (lhs: {name}, rhs: {name}) -> {name} {{
    if rhs == 0 {{ Builtin.int_trap() }}
    return {name}({div}(lhs._value, rhs._value))
  }}
  @_transparent public static func % (lhs: {name}, rhs: {name}) -> {name} {{
    if rhs == 0 {{ Builtin.int_trap() }}
    return {name}({rem}(lhs._value, rhs._value))
  }}
  @_transparent public static func &+ (lhs: {name}, rhs: {name}) -> {name} {{ return {name}(Builtin.add_{b}(lhs._value, rhs._value)) }}
  @_transparent public static func &- (lhs: {name}, rhs: {name}) -> {name} {{ return {name}(Builtin.sub_{b}(lhs._value, rhs._value)) }}
  @_transparent public static func &* (lhs: {name}, rhs: {name}) -> {name} {{ return {name}(Builtin.mul_{b}(lhs._value, rhs._value)) }}
  @_transparent public static func & (lhs: {name}, rhs: {name}) -> {name} {{ return {name}(Builtin.and_{b}(lhs._value, rhs._value)) }}
  @_transparent public static func | (lhs: {name}, rhs: {name}) -> {name} {{ return {name}(Builtin.or_{b}(lhs._value, rhs._value)) }}
  @_transparent public static func ^ (lhs: {name}, rhs: {name}) -> {name} {{ return {name}(Builtin.xor_{b}(lhs._value, rhs._value)) }}
  @_transparent public static prefix func ~ (x: {name}) -> {name} {{ return x ^ {name}(Builtin.sub_{b}(Builtin.zeroInitializer(), {name}(1)._value)) }}
  @_transparent public static func &<< (lhs: {name}, rhs: {name}) -> {name} {{
    return {name}(Builtin.shl_{b}(lhs._value, Builtin.and_{b}(rhs._value, {name}({bits - 1})._value)))
  }}
  @_transparent public static func &>> (lhs: {name}, rhs: {name}) -> {name} {{
    return {name}({shr}(lhs._value, Builtin.and_{b}(rhs._value, {name}({bits - 1})._value)))
  }}
  @_transparent public static func += (lhs: inout {name}, rhs: {name}) {{ lhs = lhs + rhs }}
  @_transparent public static func -= (lhs: inout {name}, rhs: {name}) {{ lhs = lhs - rhs }}
  @_transparent public static func *= (lhs: inout {name}, rhs: {name}) {{ lhs = lhs * rhs }}
  @_transparent public static func &+= (lhs: inout {name}, rhs: {name}) {{ lhs = lhs &+ rhs }}
  @_transparent public static func &-= (lhs: inout {name}, rhs: {name}) {{ lhs = lhs &- rhs }}
  @_transparent public static func &= (lhs: inout {name}, rhs: {name}) {{ lhs = lhs & rhs }}
  @_transparent public static func |= (lhs: inout {name}, rhs: {name}) {{ lhs = lhs | rhs }}
  @_transparent public static func ^= (lhs: inout {name}, rhs: {name}) {{ lhs = lhs ^ rhs }}
  @_transparent public static func /= (lhs: inout {name}, rhs: {name}) {{ lhs = lhs / rhs }}
  @_transparent public static func %= (lhs: inout {name}, rhs: {name}) {{ lhs = lhs % rhs }}
}}
"""

def tower(name, bits, signed):
    b = f"Int{bits}"
    ext = "sext" if signed else "zext"
    mag = ("UInt" + name[3:]) if signed else name
    if signed:
        mx, mn = str(2 ** (bits - 1) - 1), "-" + str(2 ** (bits - 1))
        magnitude = f"""  @inlinable public var magnitude: {mag} {{
    let bits = {mag}(Builtin.zextOrBitCast_{b}_{b}(_value))
    return self < 0 ? 0 &- bits : bits
  }}"""
    else:
        mx, mn = str(2 ** bits - 1), "0"
        magnitude = ""
    to64 = f"Builtin.{ext}OrBitCast_{b}_Int64"
    if bits == 64:
        from64 = "bits._value"
    else:
        from64 = f"Builtin.truncOrBitCast_Int64_{b}(bits._value)"
    if signed and bits == 64:
        distance = "return Int((other - self)._value)"
        advanced = f"return self + {name}(n._value)"
    elif bits < 64:
        distance = "return Int(truncatingIfNeeded: other) - Int(truncatingIfNeeded: self)"
        advanced = f"return {name}(Int(truncatingIfNeeded: self) + n)"
    else:
        distance = ("if other >= self { return Int(other - self) }\n"
                    "    return 0 - Int(self - other)")
        advanced = (f"if n >= 0 {{ return self + {name}(n) }}\n"
                    f"    return self - {name}(n.magnitude)")
    swap = "return self" if bits == 8 else f"return {name}(Builtin.int_bswap_{b}(_value))"
    conf = "SignedInteger" if signed else "UnsignedInteger"
    bits2 = bits * 2
    shr = "ashr" if signed else "lshr"
    widen = "zextOrBitCast" if bits2 > 64 else "truncOrBitCast"
    other = ("UInt" + name[3:]) if signed else name[1:]
    sx = "s" if signed else "u"
    return f"""
extension {name}: FixedWidthInteger, {conf} {{
  public typealias Magnitude = {mag}
  public typealias Stride = Int
{magnitude}
  @_transparent public static var max: {name} {{ return {mx} }}
  @_transparent public static var min: {name} {{ return {mn} }}
  @_transparent public init(_truncatingBits bits: UInt) {{ self.init({from64}) }}
  @_transparent public init(bitPattern x: {other}) {{ _value = x._value }}
  @_transparent public var _lowWord: UInt {{ return UInt({to64}(_value)) }}
  @_transparent public var trailingZeroBitCount: Int {{
    return Int(Builtin.zextOrBitCast_{b}_Int64(Builtin.int_cttz_{b}(_value, false._value)))
  }}
  @_transparent public var leadingZeroBitCount: Int {{
    return Int(Builtin.zextOrBitCast_{b}_Int64(Builtin.int_ctlz_{b}(_value, false._value)))
  }}
  @_transparent public var nonzeroBitCount: Int {{
    return Int(Builtin.zextOrBitCast_{b}_Int64(Builtin.int_ctpop_{b}(_value)))
  }}
  @_transparent public var byteSwapped: {name} {{ {swap} }}
  /// The full double-width product, through the Builtin integer twice as wide.
  @_transparent public func multipliedFullWidth(by other: {name}) -> (high: {name}, low: {mag}) {{
    let a = Builtin.{ext}OrBitCast_{b}_Int{bits2}(_value)
    let c = Builtin.{ext}OrBitCast_{b}_Int{bits2}(other._value)
    let p = Builtin.mul_Int{bits2}(a, c)
    let lo = Builtin.truncOrBitCast_Int{bits2}_{b}(p)
    let hi = Builtin.truncOrBitCast_Int{bits2}_{b}(Builtin.{shr}_Int{bits2}(p, Builtin.{widen}_Int64_Int{bits2}(Int64({bits})._value)))
    return ({name}(hi), {mag}(lo))
  }}
  @_transparent public func addingReportingOverflow(_ rhs: {name}) -> (partialValue: {name}, overflow: Bool) {{
    let (r, o) = Builtin.{sx}add_with_overflow_{b}(_value, rhs._value, false._value)
    return ({name}(r), Bool(o))
  }}
  @_transparent public func subtractingReportingOverflow(_ rhs: {name}) -> (partialValue: {name}, overflow: Bool) {{
    let (r, o) = Builtin.{sx}sub_with_overflow_{b}(_value, rhs._value, false._value)
    return ({name}(r), Bool(o))
  }}
  @_transparent public func multipliedReportingOverflow(by rhs: {name}) -> (partialValue: {name}, overflow: Bool) {{
    let (r, o) = Builtin.{sx}mul_with_overflow_{b}(_value, rhs._value, false._value)
    return ({name}(r), Bool(o))
  }}
  @inlinable public func dividedReportingOverflow(by rhs: {name}) -> (partialValue: {name}, overflow: Bool) {{
    if rhs == 0 {{ return (self, true) }}
    {"if self == .min && rhs == -1 { return (self, true) }" if signed else ""}
    return (self / rhs, false)
  }}
  @inlinable public func remainderReportingOverflow(dividingBy rhs: {name}) -> (partialValue: {name}, overflow: Bool) {{
    if rhs == 0 {{ return (self, true) }}
    {"if self == .min && rhs == -1 { return (0, true) }" if signed else ""}
    return (self % rhs, false)
  }}
  @inlinable public func distance(to other: {name}) -> Int {{
    {distance}
  }}
  @inlinable public func advanced(by n: Int) -> {name} {{
    {advanced}
  }}
}}
"""

def word(name, signed):
    ext = "sext" if signed else "zext"
    return f"""
extension {name} {{
  @_transparent public init(_ _v: Builtin.Word) {{ _value = Builtin.{ext}OrBitCast_Word_Int64(_v) }}
  @_transparent public var _builtinWordValue: Builtin.Word {{ return Builtin.truncOrBitCast_Int64_Word(_value) }}
}}
"""

def hashing(name, bits, signed):
    b = f"Int{bits}"
    if bits == 64:
        u = "UInt" if name in ("Int", "UInt") else "UInt64"
        raw = "return Hasher._hash(seed: seed, UInt64(_value))"
    else:
        u = f"UInt{bits}"
        raw = (f"return Hasher._hash(seed: seed, bytes: UInt64(Builtin.zext_{b}_Int64(_value)), "
               f"count: {bits // 8})")
    return f"""
extension {name}: Hashable {{
  @inlinable public func hash(into hasher: inout Hasher) {{ hasher._combine({u}(_value)) }}
  @inlinable public func _rawHashValue(seed: Int) -> Int {{
    {raw}
  }}
  public var hashValue: Int {{ return _rawHashValue(seed: 0) }}
}}
"""

FLOATS = [("Float", "FPIEEE32", 24), ("Double", "FPIEEE64", 53), ("Float80", "FPIEEE80", 64)]

def from_floats(name, bits, signed):
    """Conversions from the concrete floating-point types: truncation toward
    zero, trapping (or nil) outside the range. The bounds are exact powers of
    two; the lower one excludes values that would truncate below min."""
    b = f"Int{bits}"
    conv = "fptosi" if signed else "fptoui"
    out = [f"\nextension {name} {{"]
    for fname, fp, precision in FLOATS:
        if signed:
            hi = 2 ** (bits - 1)
            # -(2^(b-1)) - 1 is representable only with enough precision;
            # otherwise no value lies strictly between it and min.
            if bits <= precision:
                lo = f"source > -{hi + 1}.0"
            else:
                lo = f"source >= -{hi}.0"
        else:
            hi = 2 ** bits
            lo = "source > -1.0"
        inrange = f"{lo} && source < {hi}.0"
        out.append(f"""  @_transparent public init(_ source: {fname}) {{
    if !({inrange}) {{ Builtin.int_trap() }}
    self.init(Builtin.{conv}_{fp}_{b}(source._value))
  }}
  @_transparent public init?(exactly source: {fname}) {{
    if !({inrange}) {{ return nil }}
    if {fname}(Builtin.int_trunc_{fp}(source._value)) != source {{ return nil }}
    self.init(Builtin.{conv}_{fp}_{b}(source._value))
  }}""")
    out.append("}")
    return "\n".join(out)

print("// Generated by tools/gen-integers.py. Do not edit.")
print("// The fixed-width integer types. Each is @frozen around a Builtin integer, as")
print("// the ABI requires: programs inline arithmetic against the layout.")
for t in TYPES:
    print(one(*t))
for t in TYPES:
    print(tower(*t))
print(word("Int", True))
print(word("UInt", False))
for t in TYPES:
    print(hashing(*t))
for t in TYPES:
    print(from_floats(*t))
# A hint for the optimizer that a signed value is not negative.
for name, bits, signed in TYPES:
    if signed:
        print(f"""@_transparent public func _assumeNonNegative(_ x: {name}) -> {name} {{
  _ = Builtin.assume_Int1((x >= 0)._value)
  return x
}}""")
