// The numeric protocol tower. Requirements are added as the types they
// mention exist: BinaryInteger will gain CustomStringConvertible
// and `words`; FixedWidthInteger will gain
// LosslessStringConvertible. Programs reach requirements through dispatch
// thunks and method descriptors, so adding requirements later is harmless.

public protocol AdditiveArithmetic: Equatable {
  static var zero: Self { get }
  static func + (lhs: Self, rhs: Self) -> Self
  static func += (lhs: inout Self, rhs: Self)
  static func - (lhs: Self, rhs: Self) -> Self
  static func -= (lhs: inout Self, rhs: Self)
}
extension AdditiveArithmetic where Self: ExpressibleByIntegerLiteral {
  @inlinable public static var zero: Self { return 0 }
}
extension AdditiveArithmetic {
  @_transparent public static prefix func + (x: Self) -> Self { return x }
}

public protocol Numeric: AdditiveArithmetic, ExpressibleByIntegerLiteral {
  init?<T>(exactly source: T) where T: BinaryInteger
  associatedtype Magnitude: Comparable, Numeric
  var magnitude: Magnitude { get }
  static func * (lhs: Self, rhs: Self) -> Self
  static func *= (lhs: inout Self, rhs: Self)
}

public protocol SignedNumeric: Numeric {
  static prefix func - (operand: Self) -> Self
  mutating func negate()
}
extension SignedNumeric {
  @_transparent public static prefix func - (operand: Self) -> Self {
    var result = operand
    result.negate()
    return result
  }
  @_transparent public mutating func negate() { self = 0 - self }
}

public protocol Strideable<Stride>: Comparable {
  associatedtype Stride: Comparable, SignedNumeric
  func distance(to other: Self) -> Stride
  func advanced(by n: Stride) -> Self
  static func _step(after current: (index: Int?, value: Self), from start: Self, by distance: Self.Stride)
    -> (index: Int?, value: Self)
}
extension Strideable {
  @inlinable
  public static func _step(after current: (index: Int?, value: Self), from start: Self, by distance: Self.Stride)
    -> (index: Int?, value: Self) {
    return (nil, current.value.advanced(by: distance))
  }
}

public protocol BinaryInteger: Hashable, Numeric, Strideable
where Magnitude: BinaryInteger, Magnitude.Magnitude == Magnitude {
  static var isSigned: Bool { get }
  init?<T>(exactly source: T) where T: BinaryFloatingPoint
  init<T>(_ source: T) where T: BinaryFloatingPoint
  init<T>(_ source: T) where T: BinaryInteger
  init<T>(truncatingIfNeeded source: T) where T: BinaryInteger
  init<T>(clamping source: T) where T: BinaryInteger
  var _lowWord: UInt { get }
  var bitWidth: Int { get }
  func _binaryLogarithm() -> Int
  var trailingZeroBitCount: Int { get }
  static func / (lhs: Self, rhs: Self) -> Self
  static func /= (lhs: inout Self, rhs: Self)
  static func % (lhs: Self, rhs: Self) -> Self
  static func %= (lhs: inout Self, rhs: Self)
  override static func + (lhs: Self, rhs: Self) -> Self
  override static func += (lhs: inout Self, rhs: Self)
  override static func - (lhs: Self, rhs: Self) -> Self
  override static func -= (lhs: inout Self, rhs: Self)
  override static func * (lhs: Self, rhs: Self) -> Self
  override static func *= (lhs: inout Self, rhs: Self)
  static prefix func ~ (x: Self) -> Self
  static func & (lhs: Self, rhs: Self) -> Self
  static func &= (lhs: inout Self, rhs: Self)
  static func | (lhs: Self, rhs: Self) -> Self
  static func |= (lhs: inout Self, rhs: Self)
  static func ^ (lhs: Self, rhs: Self) -> Self
  static func ^= (lhs: inout Self, rhs: Self)
  static func >> <RHS: BinaryInteger>(lhs: Self, rhs: RHS) -> Self
  static func >>= <RHS: BinaryInteger>(lhs: inout Self, rhs: RHS)
  static func << <RHS: BinaryInteger>(lhs: Self, rhs: RHS) -> Self
  static func <<= <RHS: BinaryInteger>(lhs: inout Self, rhs: RHS)
  func quotientAndRemainder(dividingBy rhs: Self) -> (quotient: Self, remainder: Self)
  func isMultiple(of other: Self) -> Bool
  func signum() -> Self
}

extension BinaryInteger {
  @inlinable public init() { self = 0 }
  @inlinable
  public func quotientAndRemainder(dividingBy rhs: Self) -> (quotient: Self, remainder: Self) {
    return (self / rhs, self % rhs)
  }
  @inlinable public func isMultiple(of other: Self) -> Bool {
    if other == 0 { return self == 0 }
    return self % other == 0
  }
  @inlinable public func signum() -> Self {
    if self < (0 as Self) { return -1 as Self }
    return self == (0 as Self) ? 0 : 1
  }
  @inlinable public func _binaryLogarithm() -> Int {
    var n = self
    var r = -1
    while n != (0 as Self) { n = n >> (1 as Int); r += 1 }
    return r
  }
  @inlinable public static func >>= <RHS: BinaryInteger>(lhs: inout Self, rhs: RHS) { lhs = lhs >> rhs }
  @inlinable public static func <<= <RHS: BinaryInteger>(lhs: inout Self, rhs: RHS) { lhs = lhs << rhs }
  @inlinable public static func != <Other: BinaryInteger>(lhs: Self, rhs: Other) -> Bool { return !(lhs == rhs) }

  // Comparisons across integer types, as the standard library offers them.
  @inlinable public static func == <Other: BinaryInteger>(lhs: Self, rhs: Other) -> Bool {
    let ln = lhs < (0 as Self), rn = rhs < (0 as Other)
    if ln != rn { return false }
    return lhs._lowWord == rhs._lowWord
  }
  @inlinable public static func < <Other: BinaryInteger>(lhs: Self, rhs: Other) -> Bool {
    let ln = lhs < (0 as Self), rn = rhs < (0 as Other)
    if ln != rn { return ln }
    return lhs._lowWord < rhs._lowWord
  }
}

public protocol FixedWidthInteger: BinaryInteger
where Magnitude: FixedWidthInteger & UnsignedInteger, Stride: SignedInteger {
  // Apple's declaration also requires Stride: FixedWidthInteger. With both,
  // this compiler's requirement machine does not terminate; nothing we
  // have met binds to the descriptor that requirement would produce.
  static var bitWidth: Int { get }
  static var max: Self { get }
  static var min: Self { get }
  func addingReportingOverflow(_ rhs: Self) -> (partialValue: Self, overflow: Bool)
  func subtractingReportingOverflow(_ rhs: Self) -> (partialValue: Self, overflow: Bool)
  func multipliedReportingOverflow(by rhs: Self) -> (partialValue: Self, overflow: Bool)
  func dividedReportingOverflow(by rhs: Self) -> (partialValue: Self, overflow: Bool)
  func remainderReportingOverflow(dividingBy rhs: Self) -> (partialValue: Self, overflow: Bool)
  init(_truncatingBits bits: UInt)
  var nonzeroBitCount: Int { get }
  var leadingZeroBitCount: Int { get }
  init(bigEndian value: Self)
  init(littleEndian value: Self)
  var bigEndian: Self { get }
  var littleEndian: Self { get }
  var byteSwapped: Self { get }
  static func &>> (lhs: Self, rhs: Self) -> Self
  static func &>>= (lhs: inout Self, rhs: Self)
  static func &<< (lhs: Self, rhs: Self) -> Self
  static func &<<= (lhs: inout Self, rhs: Self)
  static func &* (lhs: Self, rhs: Self) -> Self
}

extension FixedWidthInteger {
  @inlinable public var bitWidth: Int { return Self.bitWidth }
  @inlinable public init(bigEndian value: Self) { self = value.byteSwapped }
  @inlinable public init(littleEndian value: Self) { self = value }
  @inlinable public var bigEndian: Self { return byteSwapped }
  @inlinable public var littleEndian: Self { return self }
  @inlinable public static func &+ (lhs: Self, rhs: Self) -> Self { return lhs.addingReportingOverflow(rhs).partialValue }
  @inlinable public static func &- (lhs: Self, rhs: Self) -> Self { return lhs.subtractingReportingOverflow(rhs).partialValue }
  @inlinable public static func &+= (lhs: inout Self, rhs: Self) { lhs = lhs &+ rhs }
  @inlinable public static func &-= (lhs: inout Self, rhs: Self) { lhs = lhs &- rhs }
  @inlinable public static func &*= (lhs: inout Self, rhs: Self) { lhs = lhs &* rhs }
  @inlinable public static func &>>= (lhs: inout Self, rhs: Self) { lhs = lhs &>> rhs }
  @inlinable public static func &<<= (lhs: inout Self, rhs: Self) { lhs = lhs &<< rhs }

  /// The truncating conversion every fixed-width integer shares: the low
  /// word of the source, sign-extended or not, cut to Self's width. All
  /// types here are at most one word wide.
  @inlinable public init<T: BinaryInteger>(truncatingIfNeeded source: T) {
    self.init(_truncatingBits: source._lowWord)
  }

  /// A checked conversion; traps when the value does not fit.
  @inlinable public init<T: BinaryInteger>(_ source: T) {
    guard let v = Self(exactly: source) else { Builtin.int_trap() }
    self = v
  }

  @inlinable public init?<T: BinaryInteger>(exactly source: T) {
    let negative = source < (0 as T)
    if negative && !Self.isSigned { return nil }
    // Sources wider than a word only fit when their high words carry no
    // information; with one-word types the low word and sign decide.
    if source.bitWidth > 64 {
      let back = T(truncatingIfNeeded: Self(_truncatingBits: source._lowWord))
      if back != source { return nil }
    }
    let candidate = Self(_truncatingBits: source._lowWord)
    if (candidate < (0 as Self)) != negative { return nil }
    if T(truncatingIfNeeded: candidate) != source { return nil }
    self = candidate
  }

  @inlinable public init<T: BinaryInteger>(clamping source: T) {
    if let v = Self(exactly: source) { self = v; return }
    self = source < (0 as T) ? Self.min : Self.max
  }

  // Smart shifts: negative amounts shift the other way, over-wide amounts
  // saturate.
  @inlinable public static func >> <RHS: BinaryInteger>(lhs: Self, rhs: RHS) -> Self {
    if rhs < (0 as RHS) { return lhs << (0 - Int(truncatingIfNeeded: rhs)) }
    if rhs >= RHS(truncatingIfNeeded: Self.bitWidth) {
      return lhs < (0 as Self) ? ~(0 as Self) : 0
    }
    return lhs &>> Self(truncatingIfNeeded: rhs)
  }
  @inlinable public static func << <RHS: BinaryInteger>(lhs: Self, rhs: RHS) -> Self {
    if rhs < (0 as RHS) { return lhs >> (0 - Int(truncatingIfNeeded: rhs)) }
    if rhs >= RHS(truncatingIfNeeded: Self.bitWidth) { return 0 }
    return lhs &<< Self(truncatingIfNeeded: rhs)
  }
  @inlinable public static func &>> <Other: BinaryInteger>(lhs: Self, rhs: Other) -> Self {
    return lhs &>> Self(truncatingIfNeeded: rhs)
  }
  @inlinable public static func &<< <Other: BinaryInteger>(lhs: Self, rhs: Other) -> Self {
    return lhs &<< Self(truncatingIfNeeded: rhs)
  }
}

public protocol SignedInteger: BinaryInteger, SignedNumeric {
  static func _maskingAdd(_ lhs: Self, _ rhs: Self) -> Self
  static func _maskingSubtract(_ lhs: Self, _ rhs: Self) -> Self
}
extension SignedInteger {
  @inlinable public static var isSigned: Bool { return true }
}
extension SignedInteger where Self: FixedWidthInteger {
  @inlinable public static func _maskingAdd(_ lhs: Self, _ rhs: Self) -> Self { return lhs &+ rhs }
  @inlinable public static func _maskingSubtract(_ lhs: Self, _ rhs: Self) -> Self { return lhs &- rhs }
}

public protocol UnsignedInteger: BinaryInteger {}
extension UnsignedInteger {
  @inlinable public static var isSigned: Bool { return false }
  @inlinable public var magnitude: Self { return self }
}
