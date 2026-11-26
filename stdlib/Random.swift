// Random numbers: RandomNumberGenerator, the system generator (arc4random)
// and random values of integers, floats, Bool and collections.

@_silgen_name("arc4random_buf") @usableFromInline
internal func _bitten_arc4random_buf(_ buf: UnsafeMutableRawPointer, _ count: Int)

public protocol RandomNumberGenerator {
  mutating func next() -> UInt64
}

extension RandomNumberGenerator {
  @inlinable
  public mutating func next<T: FixedWidthInteger & UnsignedInteger>() -> T {
    if T.bitWidth <= UInt64.bitWidth { return T(truncatingIfNeeded: next() as UInt64) }
    var result: T = 0
    var shift = 0
    while shift < T.bitWidth {
      result |= T(truncatingIfNeeded: next() as UInt64) << shift
      shift += UInt64.bitWidth
    }
    return result
  }

  /// A uniform value in 0..<upperBound (rejection sampling, no modulo bias).
  @inlinable
  public mutating func next<T: FixedWidthInteger & UnsignedInteger>(upperBound: T) -> T {
    _precondition(upperBound != 0, "upperBound cannot be zero.")
    let limit = T.max - T.max % upperBound
    while true {
      let r: T = next()
      if r < limit || limit == 0 { return r % upperBound }
    }
  }
}

@frozen
public struct SystemRandomNumberGenerator: RandomNumberGenerator, Sendable {
  @inlinable public init() {}
  @inlinable public mutating func next() -> UInt64 {
    var v: UInt64 = 0
    _bitten_arc4random_buf(UnsafeMutableRawPointer(Builtin.addressof(&v)), 8)
    return v
  }
}

extension FixedWidthInteger {
  @inlinable
  public static func random<T: RandomNumberGenerator>(in range: Range<Self>, using generator: inout T) -> Self {
    _precondition(!range.isEmpty, "Can't get random value with an empty range")
    let delta = Magnitude(truncatingIfNeeded: range.upperBound &- range.lowerBound)
    return Self(truncatingIfNeeded: Magnitude(truncatingIfNeeded: range.lowerBound) &+ generator.next(upperBound: delta))
  }
  @inlinable
  public static func random(in range: Range<Self>) -> Self {
    var g = SystemRandomNumberGenerator()
    return random(in: range, using: &g)
  }
  @inlinable
  public static func random<T: RandomNumberGenerator>(in range: ClosedRange<Self>, using generator: inout T) -> Self {
    var delta = Magnitude(truncatingIfNeeded: range.upperBound &- range.lowerBound)
    if delta == Magnitude.max {
      return Self(truncatingIfNeeded: generator.next() as Magnitude)
    }
    delta += 1
    return Self(truncatingIfNeeded: Magnitude(truncatingIfNeeded: range.lowerBound) &+ generator.next(upperBound: delta))
  }
  @inlinable
  public static func random(in range: ClosedRange<Self>) -> Self {
    var g = SystemRandomNumberGenerator()
    return random(in: range, using: &g)
  }
}

extension Double {
  public static func random<T: RandomNumberGenerator>(in range: Range<Double>, using generator: inout T) -> Double {
    _precondition(!range.isEmpty, "Can't get random value with an empty range")
    let unit = Double(generator.next() >> 11) * (1.0 / 9007199254740992.0) // 53 random bits in [0, 1)
    return range.lowerBound + unit * (range.upperBound - range.lowerBound)
  }
  public static func random(in range: Range<Double>) -> Double {
    var g = SystemRandomNumberGenerator()
    return random(in: range, using: &g)
  }
  public static func random<T: RandomNumberGenerator>(in range: ClosedRange<Double>, using generator: inout T) -> Double {
    let unit = Double(generator.next() >> 11) * (1.0 / 9007199254740991.0) // [0, 1]
    return range.lowerBound + unit * (range.upperBound - range.lowerBound)
  }
  public static func random(in range: ClosedRange<Double>) -> Double {
    var g = SystemRandomNumberGenerator()
    return random(in: range, using: &g)
  }
}

extension Float {
  public static func random(in range: Range<Float>) -> Float {
    return Float(Double.random(in: Double(range.lowerBound)..<Double(range.upperBound)))
  }
  public static func random(in range: ClosedRange<Float>) -> Float {
    return Float(Double.random(in: Double(range.lowerBound)...Double(range.upperBound)))
  }
}

extension Bool {
  @inlinable public static func random<T: RandomNumberGenerator>(using generator: inout T) -> Bool {
    return (generator.next() >> 17) & 1 == 0
  }
  @inlinable public static func random() -> Bool {
    var g = SystemRandomNumberGenerator()
    return random(using: &g)
  }
}

extension Collection {
  @inlinable
  public func randomElement<T: RandomNumberGenerator>(using generator: inout T) -> Element? {
    guard !isEmpty else { return nil }
    let offset = Int.random(in: 0..<count, using: &generator)
    return self[index(startIndex, offsetBy: offset)]
  }
  @inlinable
  public func randomElement() -> Element? {
    var g = SystemRandomNumberGenerator()
    return randomElement(using: &g)
  }
}

extension MutableCollection where Self: RandomAccessCollection {
  @inlinable
  public mutating func shuffle<T: RandomNumberGenerator>(using generator: inout T) {
    guard count > 1 else { return }
    var amount = count
    var current = startIndex
    while amount > 1 {
      let random = Int.random(in: 0..<amount, using: &generator)
      amount -= 1
      swapAt(current, index(current, offsetBy: random))
      formIndex(after: &current)
    }
  }
  @inlinable
  public mutating func shuffle() {
    var g = SystemRandomNumberGenerator()
    shuffle(using: &g)
  }
}

extension Sequence {
  @inlinable
  public func shuffled<T: RandomNumberGenerator>(using generator: inout T) -> [Element] {
    var result = ContiguousArray(self)
    result.shuffle(using: &generator)
    return Array(result)
  }
  @inlinable
  public func shuffled() -> [Element] {
    var g = SystemRandomNumberGenerator()
    return shuffled(using: &g)
  }
}

// MARK: - sorting helpers programs inline

/// The minimum run length for merging (Apple's sort is a modified timsort
/// whose inlined parts call this).
@usableFromInline
internal func _minimumMergeRunLength(_ c: Int) -> Int {
  let bitsToUse = 6
  if c < 1 &<< bitsToUse { return c }
  let offset = (Int.bitWidth &- bitsToUse) &- c.leadingZeroBitCount
  let mask = (1 &<< offset) &- 1
  return c &>> offset &+ (c & mask != 0 ? 1 : 0)
}
