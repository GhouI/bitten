// Duration: a signed count of attoseconds (1e-18 s) in 128 bits, the
// layout Apple's @frozen Duration has (low word first). The clocks that
// produce Instants live in _Concurrency.

public protocol DurationProtocol: Comparable, AdditiveArithmetic, Sendable {
  static func / (_ lhs: Self, _ rhs: Int) -> Self
  static func /= (_ lhs: inout Self, _ rhs: Int)
  static func * (_ lhs: Self, _ rhs: Int) -> Self
  static func *= (_ lhs: inout Self, _ rhs: Int)
  static func / (_ lhs: Self, _ rhs: Self) -> Double
}

public protocol InstantProtocol<Duration>: Comparable, Hashable, Sendable {
  associatedtype Duration: DurationProtocol
  func advanced(by duration: Duration) -> Self
  func duration(to other: Self) -> Duration
}

@frozen
public struct Duration: Sendable {
  public var _low: UInt64
  public var _high: Int64

  @inlinable public init(_high: Int64, low: UInt64) {
    self._low = low
    self._high = _high
  }

  /// attoseconds as (high, low) of a two's complement 128-bit integer.
  internal init(attoseconds: (high: Int64, low: UInt64)) { self.init(_high: attoseconds.high, low: attoseconds.low) }

  internal static let attosecondsPerSecond: UInt64 = 1_000_000_000_000_000_000

  public init(secondsComponent: Int64, attosecondsComponent: Int64) {
    var d = Duration._fromSeconds(secondsComponent)
    d = d + Duration._fromAttoseconds(attosecondsComponent)
    self = d
  }

  /// seconds * 1e18 as 128 bits.
  internal static func _fromSeconds(_ s: Int64) -> Duration {
    let negative = s < 0
    let m = s.magnitude
    // m * 1e18 with 64x64->128 multiplication.
    let (hi, lo) = m.multipliedFullWidth(by: attosecondsPerSecond)
    var d = Duration(_high: Int64(bitPattern: hi), low: lo)
    if negative { d = Duration.zero - d }
    return d
  }
  internal static func _fromAttoseconds(_ a: Int64) -> Duration {
    return Duration(_high: a < 0 ? -1 : 0, low: UInt64(bitPattern: a))
  }

  public var components: (seconds: Int64, attoseconds: Int64) {
    // Divide the 128-bit value by 1e18, rounding toward negative infinity
    // like Apple's (attoseconds then has the sign of the remainder).
    let negative = _high < 0
    let mag = negative ? (Duration.zero - self) : self
    let (q, r) = Duration._divide(high: UInt64(bitPattern: mag._high), low: mag._low, by: Duration.attosecondsPerSecond)
    var seconds = Int64(bitPattern: q)
    var atto = Int64(bitPattern: r)
    if negative {
      seconds = -seconds
      atto = -atto
    }
    return (seconds, atto)
  }

  /// (high:low) / d for a divisor that fits in 64 bits, by long division.
  internal static func _divide(high: UInt64, low: UInt64, by d: UInt64) -> (UInt64, UInt64) {
    var q: UInt64 = 0
    var r: UInt64 = 0
    var bit = 127
    while bit >= 0 {
      let b: UInt64 = bit >= 64 ? (high >> UInt64(bit - 64)) & 1 : (low >> UInt64(bit)) & 1
      // r = r * 2 + b, tracking overflow past 64 bits.
      let carry = r >> 63
      r = (r << 1) | b
      if carry == 1 || r >= d {
        r = r &- d
        if bit < 64 { q |= (1 as UInt64) << UInt64(bit) }
      }
      bit -= 1
    }
    return (q, r)
  }

  internal var _doubleSeconds: Double {
    let c = components
    return Double(c.seconds) + Double(c.attoseconds) / 1e18
  }

  public static func seconds<T: BinaryInteger>(_ seconds: T) -> Duration { return _fromSeconds(Int64(seconds)) }
  public static func seconds(_ seconds: Double) -> Duration {
    let whole = seconds.rounded(.towardZero)
    let frac = seconds - whole
    return _fromSeconds(Int64(whole)) + _fromAttoseconds(Int64(frac * 1e18))
  }
  public static func milliseconds<T: BinaryInteger>(_ ms: T) -> Duration {
    return _fromSeconds(Int64(ms) / 1000) + _fromAttoseconds(Int64(ms) % 1000 * 1_000_000_000_000_000)
  }
  public static func milliseconds(_ ms: Double) -> Duration { return seconds(ms / 1000) }
  public static func microseconds<T: BinaryInteger>(_ us: T) -> Duration {
    return _fromSeconds(Int64(us) / 1_000_000) + _fromAttoseconds(Int64(us) % 1_000_000 * 1_000_000_000_000)
  }
  public static func microseconds(_ us: Double) -> Duration { return seconds(us / 1e6) }
  public static func nanoseconds<T: BinaryInteger>(_ ns: T) -> Duration {
    return _fromSeconds(Int64(ns) / 1_000_000_000) + _fromAttoseconds(Int64(ns) % 1_000_000_000 * 1_000_000_000)
  }
}

extension Duration: Equatable {
  public static func == (lhs: Duration, rhs: Duration) -> Bool { return lhs._high == rhs._high && lhs._low == rhs._low }
}
extension Duration: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(_high)
    hasher.combine(_low)
  }
}
extension Duration: Comparable {
  public static func < (lhs: Duration, rhs: Duration) -> Bool {
    return lhs._high < rhs._high || (lhs._high == rhs._high && lhs._low < rhs._low)
  }
}
extension Duration: AdditiveArithmetic {
  public static var zero: Duration { return Duration(_high: 0, low: 0) }
  public static func + (lhs: Duration, rhs: Duration) -> Duration {
    let (lo, carry) = lhs._low.addingReportingOverflow(rhs._low)
    return Duration(_high: lhs._high &+ rhs._high &+ (carry ? 1 : 0), low: lo)
  }
  public static func - (lhs: Duration, rhs: Duration) -> Duration {
    let (lo, borrow) = lhs._low.subtractingReportingOverflow(rhs._low)
    return Duration(_high: lhs._high &- rhs._high &- (borrow ? 1 : 0), low: lo)
  }
  public static func += (lhs: inout Duration, rhs: Duration) { lhs = lhs + rhs }
  public static func -= (lhs: inout Duration, rhs: Duration) { lhs = lhs - rhs }
}
extension Duration: DurationProtocol {
  public static func / (lhs: Duration, rhs: Int) -> Duration { return .seconds(lhs._doubleSeconds / Double(rhs)) }
  public static func /= (lhs: inout Duration, rhs: Int) { lhs = lhs / rhs }
  public static func * (lhs: Duration, rhs: Int) -> Duration { return lhs * Double(rhs) }
  public static func *= (lhs: inout Duration, rhs: Int) { lhs = lhs * rhs }
  public static func / (lhs: Duration, rhs: Duration) -> Double { return lhs._doubleSeconds / rhs._doubleSeconds }
  public static func * (lhs: Duration, rhs: Double) -> Duration { return .seconds(lhs._doubleSeconds * rhs) }
  public static func * <T: BinaryInteger>(lhs: Duration, rhs: T) -> Duration { return lhs * Double(Int64(rhs)) }
  public static func / <T: BinaryInteger>(lhs: Duration, rhs: T) -> Duration { return lhs / Int(rhs) }
}
extension Duration: CustomStringConvertible {
  public var description: String { return "\(_doubleSeconds) seconds" }
}
extension Duration: Codable {
  public init(from decoder: any Decoder) throws {
    var c = try decoder.unkeyedContainer()
    let high = try c.decode(Int64.self)
    let low = try c.decode(UInt64.self)
    self.init(_high: high, low: low)
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.unkeyedContainer()
    try c.encode(_high)
    try c.encode(_low)
  }
}
