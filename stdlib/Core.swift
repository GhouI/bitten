// Types and protocols the compiler itself depends on: Void, Never, the
// equality/ordering protocols and the literal protocols.

public typealias Void = ()
public typealias AnyObject = Builtin.AnyObject
public typealias AnyClass = AnyObject.Type

@frozen public enum Never {}

public protocol Equatable {
  static func == (lhs: Self, rhs: Self) -> Bool
}
extension Equatable {
  @_transparent
  public static func != (lhs: Self, rhs: Self) -> Bool { return !(lhs == rhs) }
}

public protocol Comparable: Equatable {
  static func < (lhs: Self, rhs: Self) -> Bool
  static func <= (lhs: Self, rhs: Self) -> Bool
  static func >= (lhs: Self, rhs: Self) -> Bool
  static func > (lhs: Self, rhs: Self) -> Bool
}
extension Comparable {
  @inlinable public static func > (lhs: Self, rhs: Self) -> Bool { return rhs < lhs }
  @inlinable public static func <= (lhs: Self, rhs: Self) -> Bool { return !(rhs < lhs) }
  @inlinable public static func >= (lhs: Self, rhs: Self) -> Bool { return !(lhs < rhs) }
}

// ---- literals ---------------------------------------------------------------
// The compiler converts literals through these, by name.

public protocol _ExpressibleByBuiltinIntegerLiteral {
  init(_builtinIntegerLiteral value: Builtin.IntLiteral)
}
public protocol ExpressibleByIntegerLiteral {
  associatedtype IntegerLiteralType: _ExpressibleByBuiltinIntegerLiteral
  init(integerLiteral value: IntegerLiteralType)
}
public protocol _ExpressibleByBuiltinFloatLiteral {
  init(_builtinFloatLiteral value: _MaxBuiltinFloatType)
}
public protocol ExpressibleByFloatLiteral {
  associatedtype FloatLiteralType: _ExpressibleByBuiltinFloatLiteral
  init(floatLiteral value: FloatLiteralType)
}
public protocol _ExpressibleByBuiltinBooleanLiteral {
  init(_builtinBooleanLiteral value: Builtin.Int1)
}
public protocol ExpressibleByBooleanLiteral {
  associatedtype BooleanLiteralType: _ExpressibleByBuiltinBooleanLiteral
  init(booleanLiteral value: BooleanLiteralType)
}
public protocol ExpressibleByNilLiteral: ~Copyable {
  init(nilLiteral: ())
}

public typealias IntegerLiteralType = Int
public typealias BooleanLiteralType = Bool
public typealias _MaxBuiltinFloatType = Builtin.FPIEEE80

// ---- Bool ---------------------------------------------------------------------

@frozen public struct Bool: Sendable {
  public var _value: Builtin.Int1
  @_transparent public init() { _value = Builtin.trunc_Int8_Int1(Builtin.zeroInitializer()) }
  @_transparent public init(_ v: Builtin.Int1) { _value = v }
  @inlinable public init(_ value: Bool) { self = value }
}
extension Bool: _ExpressibleByBuiltinBooleanLiteral, ExpressibleByBooleanLiteral {
  @_transparent public init(_builtinBooleanLiteral value: Builtin.Int1) { _value = value }
  @_transparent public init(booleanLiteral value: Bool) { self = value }
}
extension Bool: Equatable {
  @_transparent public static func == (lhs: Bool, rhs: Bool) -> Bool {
    return Bool(Builtin.cmp_eq_Int1(lhs._value, rhs._value))
  }
}
extension Bool {
  @_transparent public static prefix func ! (a: Bool) -> Bool {
    return Bool(Builtin.xor_Int1(a._value, true._value))
  }
  @_transparent @inline(__always)
  public static func && (lhs: Bool, rhs: @autoclosure () throws -> Bool) rethrows -> Bool {
    return lhs ? try rhs() : false
  }
  @_transparent @inline(__always)
  public static func || (lhs: Bool, rhs: @autoclosure () throws -> Bool) rethrows -> Bool {
    return lhs ? true : try rhs()
  }
  @inlinable public mutating func toggle() { self = !self }
}

// The compiler branches on Bool through this.
extension Bool {
  @_transparent public func _getBuiltinLogicValue() -> Builtin.Int1 { return _value }
}

// ---- marker protocols ------------------------------------------------------------
@_marker public protocol Sendable {}
@_marker public protocol SendableMetatype {}
