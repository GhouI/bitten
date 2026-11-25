// CGFloat lives in this library on current macOS but keeps the mangled
// module name it was first defined in, CoreGraphics. On 64-bit platforms it
// wraps a Double and behaves as one: every requirement forwards to `native`.

@frozen
@available(macOS 10.15, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 14.0)
public struct CGFloat: Sendable {
  public typealias NativeType = Double
  public var native: NativeType
  @_transparent public init() { native = 0.0 }
  @_transparent public init(_ value: Float) { native = Double(value) }
  @_transparent public init(_ value: Double) { native = value }
  @_transparent public init(_ value: Float80) { native = Double(value) }
  @_transparent public init(_ value: CGFloat) { native = value.native }
  @_transparent public init(_ value: Int) { native = Double(value) }
  @_transparent public init<Source: BinaryInteger>(_ value: Source) { native = Double(value) }
  @_transparent public init<Source: BinaryFloatingPoint>(_ value: Source) { native = Double(value) }
  public init?<Source: BinaryInteger>(exactly value: Source) {
    guard let d = Double(exactly: value) else { return nil }
    native = d
  }
  public init?<Source: BinaryFloatingPoint>(exactly value: Source) {
    guard let d = Double(exactly: value) else { return nil }
    native = d
  }
}

@available(macOS 10.15, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 14.0)
extension CGFloat: Equatable {
  @_transparent public static func == (lhs: CGFloat, rhs: CGFloat) -> Bool { return lhs.native == rhs.native }
}

@available(macOS 10.15, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 14.0)
extension CGFloat: Hashable {
  public func hash(into hasher: inout Hasher) { native.hash(into: &hasher) }
}

@available(macOS 10.15, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 14.0)
extension CGFloat: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
  @_transparent public init(floatLiteral value: Double) { native = value }
  @_transparent public init(integerLiteral value: Int) { native = Double(value) }
}

@available(macOS 10.15, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 14.0)
extension CGFloat: Comparable {
  @_transparent public static func < (lhs: CGFloat, rhs: CGFloat) -> Bool { return lhs.native < rhs.native }
  @_transparent public static func <= (lhs: CGFloat, rhs: CGFloat) -> Bool { return lhs.native <= rhs.native }
  @_transparent public static func > (lhs: CGFloat, rhs: CGFloat) -> Bool { return lhs.native > rhs.native }
  @_transparent public static func >= (lhs: CGFloat, rhs: CGFloat) -> Bool { return lhs.native >= rhs.native }
}

@available(macOS 10.15, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 14.0)
extension CGFloat: Strideable {
  @_transparent public func distance(to other: CGFloat) -> CGFloat { return CGFloat(other.native - native) }
  @_transparent public func advanced(by amount: CGFloat) -> CGFloat { return CGFloat(native + amount.native) }
}

@available(macOS 10.15, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 14.0)
extension CGFloat: SignedNumeric {
  public typealias Magnitude = CGFloat
  @_transparent public var magnitude: CGFloat { return CGFloat(native.magnitude) }
  @_transparent public static func + (lhs: CGFloat, rhs: CGFloat) -> CGFloat { return CGFloat(lhs.native + rhs.native) }
  @_transparent public static func - (lhs: CGFloat, rhs: CGFloat) -> CGFloat { return CGFloat(lhs.native - rhs.native) }
  @_transparent public static func * (lhs: CGFloat, rhs: CGFloat) -> CGFloat { return CGFloat(lhs.native * rhs.native) }
  @_transparent public static func += (lhs: inout CGFloat, rhs: CGFloat) { lhs.native += rhs.native }
  @_transparent public static func -= (lhs: inout CGFloat, rhs: CGFloat) { lhs.native -= rhs.native }
  @_transparent public static func *= (lhs: inout CGFloat, rhs: CGFloat) { lhs.native *= rhs.native }
  @_transparent public static prefix func - (x: CGFloat) -> CGFloat { return CGFloat(-x.native) }
  @_transparent public mutating func negate() { native.negate() }
}

@available(macOS 10.15, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 14.0)
extension CGFloat: BinaryFloatingPoint {
  public typealias Exponent = Int
  public typealias RawSignificand = UInt64
  public typealias RawExponent = UInt
  public init(sign: FloatingPointSign, exponent: Int, significand: CGFloat) {
    native = Double(sign: sign, exponent: exponent, significand: significand.native)
  }
  public init(signOf: CGFloat, magnitudeOf: CGFloat) { native = Double(signOf: signOf.native, magnitudeOf: magnitudeOf.native) }
  public init(sign: FloatingPointSign, exponentBitPattern: UInt, significandBitPattern: UInt64) {
    native = Double(sign: sign, exponentBitPattern: exponentBitPattern, significandBitPattern: significandBitPattern)
  }
  public static var radix: Int { return 2 }
  public static var nan: CGFloat { return CGFloat(Double.nan) }
  public static var signalingNaN: CGFloat { return CGFloat(Double.signalingNaN) }
  public static var infinity: CGFloat { return CGFloat(Double.infinity) }
  public static var greatestFiniteMagnitude: CGFloat { return CGFloat(Double.greatestFiniteMagnitude) }
  public static var pi: CGFloat { return CGFloat(Double.pi) }
  public var ulp: CGFloat { return CGFloat(native.ulp) }
  public static var ulpOfOne: CGFloat { return CGFloat(Double.ulpOfOne) }
  public static var leastNormalMagnitude: CGFloat { return CGFloat(Double.leastNormalMagnitude) }
  public static var leastNonzeroMagnitude: CGFloat { return CGFloat(Double.leastNonzeroMagnitude) }
  public var sign: FloatingPointSign { return native.sign }
  public var exponent: Int { return native.exponent }
  public var significand: CGFloat { return CGFloat(native.significand) }
  public static func / (lhs: CGFloat, rhs: CGFloat) -> CGFloat { return CGFloat(lhs.native / rhs.native) }
  public static func /= (lhs: inout CGFloat, rhs: CGFloat) { lhs.native /= rhs.native }
  public mutating func formRemainder(dividingBy other: CGFloat) { native.formRemainder(dividingBy: other.native) }
  public mutating func formTruncatingRemainder(dividingBy other: CGFloat) {
    native.formTruncatingRemainder(dividingBy: other.native)
  }
  public mutating func formSquareRoot() { native.formSquareRoot() }
  public mutating func addProduct(_ lhs: CGFloat, _ rhs: CGFloat) { native.addProduct(lhs.native, rhs.native) }
  public mutating func round(_ rule: FloatingPointRoundingRule) { native.round(rule) }
  public var nextUp: CGFloat { return CGFloat(native.nextUp) }
  public var nextDown: CGFloat { return CGFloat(native.nextDown) }
  public func isEqual(to other: CGFloat) -> Bool { return native.isEqual(to: other.native) }
  public func isLess(than other: CGFloat) -> Bool { return native.isLess(than: other.native) }
  public func isLessThanOrEqualTo(_ other: CGFloat) -> Bool { return native.isLessThanOrEqualTo(other.native) }
  public func isTotallyOrdered(belowOrEqualTo other: CGFloat) -> Bool {
    return native.isTotallyOrdered(belowOrEqualTo: other.native)
  }
  public var isNormal: Bool { return native.isNormal }
  public var isFinite: Bool { return native.isFinite }
  public var isZero: Bool { return native.isZero }
  public var isSubnormal: Bool { return native.isSubnormal }
  public var isInfinite: Bool { return native.isInfinite }
  public var isNaN: Bool { return native.isNaN }
  public var isSignalingNaN: Bool { return native.isSignalingNaN }
  public var isCanonical: Bool { return true }
  public static var exponentBitCount: Int { return Double.exponentBitCount }
  public static var significandBitCount: Int { return Double.significandBitCount }
  public var exponentBitPattern: UInt { return native.exponentBitPattern }
  public var significandBitPattern: UInt64 { return native.significandBitPattern }
  public var binade: CGFloat { return CGFloat(native.binade) }
  public var significandWidth: Int { return native.significandWidth }
}

@available(macOS 10.15, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 14.0)
extension CGFloat: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String { return native.description }
  public var debugDescription: String { return native.description }
}

extension Double {
  @_transparent public init(_ value: CGFloat) { self = value.native }
}
extension Float {
  @_transparent public init(_ value: CGFloat) { self = Float(value.native) }
}
extension Int {
  @_transparent public init(_ value: CGFloat) { self = Int(value.native) }
}
