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
    sx = "s" if signed else "u"
    return f"""
extension {name}: FixedWidthInteger, {conf} {{
  public typealias Magnitude = {mag}
  public typealias Stride = Int
{magnitude}
  @_transparent public static var max: {name} {{ return {mx} }}
  @_transparent public static var min: {name} {{ return {mn} }}
  @_transparent public init(_truncatingBits bits: UInt) {{ self.init({from64}) }}
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

print("// Generated by tools/gen-integers.py. Do not edit.")
print("// The fixed-width integer types. Each is @frozen around a Builtin integer, as")
print("// the ABI requires: programs inline arithmetic against the layout.")
for t in TYPES:
    print(one(*t))
for t in TYPES:
    print(tower(*t))
