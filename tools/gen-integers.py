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

print("// Generated by tools/gen-integers.py. Do not edit.")
print("// The fixed-width integer types. Each is @frozen around a Builtin integer, as")
print("// the ABI requires: programs inline arithmetic against the layout.")
for t in TYPES:
    print(one(*t))
