// Decimal (the C struct NSDecimal): sign, a 128-bit mantissa in 16-bit
// words and a base-10 exponent in -128...127. Arithmetic works on the
// mantissa as a little-endian array of words, keeping at most 38 decimal
// digits and rounding the rest away.

public typealias Decimal = NSDecimal

// MARK: - mantissa arithmetic

internal struct _DecimalWords {
  var w: [UInt16] // little-endian, no high zero words

  init(_ w: [UInt16]) {
    self.w = w
    trim()
  }
  init(_ v: UInt64) {
    var x = v
    w = []
    while x != 0 { w.append(UInt16(truncatingIfNeeded: x)); x >>= 16 }
  }
  mutating func trim() { while let l = w.last, l == 0 { w.removeLast() } }
  var isZero: Bool { return w.isEmpty }

  /// self = self * k + add; true when the result no longer fits 128 bits.
  mutating func mulAdd(_ k: UInt32, _ add: UInt32 = 0) -> Bool {
    var carry = UInt32(add)
    for i in 0..<w.count {
      let v = UInt32(w[i]) * k + carry
      w[i] = UInt16(truncatingIfNeeded: v)
      carry = v >> 16
    }
    while carry != 0 { w.append(UInt16(truncatingIfNeeded: carry)); carry >>= 16 }
    return w.count > 8
  }
  /// self /= k, returning the remainder.
  mutating func divSmall(_ k: UInt32) -> UInt32 {
    var rem: UInt32 = 0
    var i = w.count - 1
    while i >= 0 {
      let v = rem << 16 | UInt32(w[i])
      w[i] = UInt16(v / k)
      rem = v % k
      i -= 1
    }
    trim()
    return rem
  }
  static func compare(_ a: _DecimalWords, _ b: _DecimalWords) -> Int {
    if a.w.count != b.w.count { return a.w.count < b.w.count ? -1 : 1 }
    var i = a.w.count - 1
    while i >= 0 {
      if a.w[i] != b.w[i] { return a.w[i] < b.w[i] ? -1 : 1 }
      i -= 1
    }
    return 0
  }
  static func + (a: _DecimalWords, b: _DecimalWords) -> _DecimalWords {
    var out: [UInt16] = []
    var carry: UInt32 = 0
    for i in 0..<Swift.max(a.w.count, b.w.count) {
      let v = UInt32(i < a.w.count ? a.w[i] : 0) + UInt32(i < b.w.count ? b.w[i] : 0) + carry
      out.append(UInt16(truncatingIfNeeded: v))
      carry = v >> 16
    }
    if carry != 0 { out.append(UInt16(carry)) }
    return _DecimalWords(out)
  }
  /// a - b for a >= b.
  static func - (a: _DecimalWords, b: _DecimalWords) -> _DecimalWords {
    var out: [UInt16] = []
    var borrow: Int32 = 0
    for i in 0..<a.w.count {
      var v = Int32(a.w[i]) - Int32(i < b.w.count ? b.w[i] : 0) - borrow
      borrow = 0
      if v < 0 { v += 65536; borrow = 1 }
      out.append(UInt16(v))
    }
    return _DecimalWords(out)
  }
  static func * (a: _DecimalWords, b: _DecimalWords) -> _DecimalWords {
    if a.isZero || b.isZero { return _DecimalWords([]) }
    var out = [UInt32](repeating: 0, count: a.w.count + b.w.count + 1)
    for i in 0..<a.w.count {
      var carry: UInt32 = 0
      for j in 0..<b.w.count {
        let v = UInt32(a.w[i]) * UInt32(b.w[j]) + out[i + j] + carry
        out[i + j] = v & 0xFFFF
        carry = v >> 16
      }
      var k = i + b.w.count
      while carry != 0 {
        let v = out[k] + carry
        out[k] = v & 0xFFFF
        carry = v >> 16
        k += 1
      }
    }
    return _DecimalWords(out.map { UInt16($0) })
  }
  var digits: String {
    if isZero { return "0" }
    var copy = self
    var ds: [UInt8] = []
    while !copy.isZero { ds.append(UInt8(copy.divSmall(10)) + 48) }
    return String(decoding: ds.reversed(), as: UTF8.self)
  }
  var digitCount: Int { return isZero ? 1 : digits.utf8.count }
}

/// An unpacked decimal: (-1)^negative * m * 10^exponent, exponent unbounded.
internal struct _DecimalParts {
  var negative: Bool
  var m: _DecimalWords
  var exponent: Int
  var isNaN = false

  /// Drops digits until the mantissa fits 128 bits (and the exponent its
  /// range), rounding half up; nil when the value cannot be represented.
  func packed() -> Decimal? {
    if isNaN { return Decimal.nan }
    var m = self.m
    var e = exponent
    var lastRem: UInt32 = 0
    var sticky = false
    while m.w.count > 8 || e < -128 {
      if lastRem != 0 { sticky = true }
      lastRem = m.divSmall(10)
      e += 1
      if m.isZero && e > -128 { break }
    }
    if lastRem >= 5 { // round half up
      if m.mulAdd(1, 1) { // overflowed 128 bits: one more digit
        _ = m.divSmall(10)
        e += 1
      }
    }
    while e > 127 {
      if m.isZero { e = 0; break }
      if m.mulAdd(10) { return nil }
      e -= 1
    }
    if m.isZero { return Decimal() }
    // Compact: remove trailing zeros.
    while !m.isZero && e < 127 {
      var probe = m
      if probe.divSmall(10) != 0 { break }
      m = probe
      e += 1
    }
    var d = Decimal()
    d._exponent = Int32(e)
    d._length = UInt32(m.w.count)
    d._isNegative = negative ? 1 : 0
    d._isCompact = 1
    var words = m.w + [UInt16](repeating: 0, count: 8 - m.w.count)
    d._mantissa = (words[0], words[1], words[2], words[3], words[4], words[5], words[6], words[7])
    words.removeAll()
    return d
  }
}

extension Decimal {
  internal var _words: _DecimalWords {
    let t = _mantissa
    let all = [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7]
    return _DecimalWords(Array(all[0..<Int(_length)]))
  }
  internal var _parts: _DecimalParts {
    return _DecimalParts(negative: _isNegative != 0, m: _words, exponent: Int(_exponent), isNaN: isNaN)
  }
  internal init(_parts p: _DecimalParts) { self = p.packed() ?? .nan }

  public static let nan: Decimal = {
    var d = Decimal()
    d._isNegative = 1 // length 0 with the sign set
    return d
  }()
  public static var quietNaN: Decimal { return nan }
  public static let leastFiniteMagnitude = Decimal(_parts: _DecimalParts(negative: true,
    m: _DecimalWords([UInt16](repeating: 0xFFFF, count: 8)), exponent: 127))
  public static let greatestFiniteMagnitude = Decimal(_parts: _DecimalParts(negative: false,
    m: _DecimalWords([UInt16](repeating: 0xFFFF, count: 8)), exponent: 127))
  public static let leastNormalMagnitude = Decimal(_parts: _DecimalParts(negative: false, m: _DecimalWords(1), exponent: -128))
  public static let leastNonzeroMagnitude = leastNormalMagnitude
  public static var pi: Decimal { return Decimal(string: "3.14159265358979323846264338327950288419")! }

  public var isNaN: Bool { return _length == 0 && _isNegative != 0 }
  public var isZero: Bool { return _length == 0 && _isNegative == 0 }
  public var isFinite: Bool { return !isNaN }
  public var isInfinite: Bool { return false }
  public var isSignMinus: Bool { return _isNegative != 0 }
  public var isNormal: Bool { return !isZero && !isNaN }
  public var isCanonical: Bool { return true }
  public var isSignaling: Bool { return false }
  public var isSignalingNaN: Bool { return false }
  public var exponent: Int { return Int(_exponent) }
  public var significand: Decimal {
    var d = self
    d._exponent = 0
    d._isNegative = 0
    return d
  }
  public var sign: FloatingPointSign { return _isNegative != 0 ? .minus : .plus }
  public var magnitude: Decimal {
    var d = self
    if !isNaN { d._isNegative = 0 }
    return d
  }
  public var ulp: Decimal {
    return Decimal(_parts: _DecimalParts(negative: false, m: _DecimalWords(1), exponent: Int(_exponent)))
  }

  // MARK: initializers

  public init(_ value: UInt64) { self.init(_parts: _DecimalParts(negative: false, m: _DecimalWords(value), exponent: 0)) }
  public init(_ value: Int64) {
    self.init(_parts: _DecimalParts(negative: value < 0, m: _DecimalWords(value.magnitude), exponent: 0))
  }
  public init(_ value: Int) { self.init(Int64(value)) }
  public init(_ value: UInt) { self.init(UInt64(value)) }
  public init(_ value: Int32) { self.init(Int64(value)) }
  public init(_ value: UInt32) { self.init(UInt64(value)) }
  public init(_ value: Int16) { self.init(Int64(value)) }
  public init(_ value: UInt16) { self.init(UInt64(value)) }
  public init(_ value: Int8) { self.init(Int64(value)) }
  public init(_ value: UInt8) { self.init(UInt64(value)) }
  public init(_ value: Double) {
    if value.isNaN || value.isInfinite { self = .nan; return }
    // Through the shortest decimal text of the double, as people expect
    // Decimal(0.1) to be 0.1.
    self = Decimal(string: "\(value)") ?? .nan
  }
  public init(sign: FloatingPointSign, exponent: Int, significand: Decimal) {
    var p = significand._parts
    p.exponent += exponent
    p.negative = (sign == .minus) != p.negative
    self.init(_parts: p)
  }
  public init(signOf: Decimal, magnitudeOf magnitude: Decimal) {
    var p = magnitude._parts
    p.negative = signOf.isSignMinus
    self.init(_parts: p)
  }

  public init?(string: __shared String, locale: __shared Locale? = nil) {
    let b = Array(string.utf8)
    var i = 0
    while i < b.count && (b[i] == 32 || b[i] == 9) { i += 1 }
    var negative = false
    if i < b.count && (b[i] == 45 || b[i] == 43) { negative = b[i] == 45; i += 1 }
    var m = _DecimalWords([])
    var exponent = 0
    var sawDigit = false
    var dropped = false
    while i < b.count && b[i] >= 48 && b[i] <= 57 {
      sawDigit = true
      if !dropped && m.digitCount < 38 { _ = m.mulAdd(10, UInt32(b[i] - 48)) } else { dropped = true; exponent += 1 }
      i += 1
    }
    let separator: UInt8 = locale.map { $0.identifier.hasPrefix("de") || $0.identifier.hasPrefix("fr") ? 44 : 46 } ?? 46
    if i < b.count && b[i] == separator {
      i += 1
      while i < b.count && b[i] >= 48 && b[i] <= 57 {
        sawDigit = true
        if !dropped && m.digitCount < 38 { _ = m.mulAdd(10, UInt32(b[i] - 48)); exponent -= 1 } else { dropped = true }
        i += 1
      }
    }
    if !sawDigit { return nil }
    if i < b.count && (b[i] == 101 || b[i] == 69) {
      var j = i + 1
      var eneg = false
      if j < b.count && (b[j] == 45 || b[j] == 43) { eneg = b[j] == 45; j += 1 }
      var e = 0
      var any = false
      while j < b.count && b[j] >= 48 && b[j] <= 57 {
        e = Swift.min(e * 10 + Int(b[j] - 48), 100000)
        j += 1
        any = true
      }
      if any {
        exponent += eneg ? -e : e
        i = j
      }
    }
    // Trailing text after a number is ignored, like NSScanner does.
    guard let d = _DecimalParts(negative: negative && !m.isZero, m: m, exponent: exponent).packed() else { return nil }
    self = d
  }

  // MARK: text

  public var description: String {
    if isNaN { return "NaN" }
    if isZero { return "0" }
    var digits = Array(_words.digits.utf8)
    let e = Int(_exponent)
    var out: [UInt8] = _isNegative != 0 ? [45] : []
    if e >= 0 {
      out += digits
      out += [UInt8](repeating: 48, count: e)
    } else {
      let point = digits.count + e
      if point <= 0 {
        out += [48, 46]
        out += [UInt8](repeating: 48, count: -point)
        out += digits
      } else {
        out += digits[0..<point]
        out.append(46)
        out += digits[point..<digits.count]
      }
    }
    digits.removeAll()
    return String(decoding: out, as: UTF8.self)
  }

  internal var _doubleValue: Double {
    if isNaN { return .nan }
    let d = Double(_words.digits) ?? 0
    var result = d
    var e = Int(_exponent)
    while e > 0 { result *= 10; e -= 1 }
    while e < 0 { result /= 10; e += 1 }
    return _isNegative != 0 ? -result : result
  }
}

// MARK: - arithmetic

internal func _decimalAlign(_ a: _DecimalParts, _ b: _DecimalParts) -> (_DecimalWords, _DecimalWords, Int) {
  // Bring both to the smaller exponent (multiplying the other's mantissa).
  var x = a, y = b
  if x.exponent > y.exponent { swap(&x, &y) }
  var ym = y.m
  var diff = y.exponent - x.exponent
  while diff > 0 {
    var probe = ym
    if probe.mulAdd(10) || probe.w.count > 16 { break }
    ym = probe
    diff -= 1
  }
  var xm = x.m
  var e = x.exponent
  // If y could not be scaled all the way, drop digits from x instead.
  while diff > 0 {
    _ = xm.divSmall(10)
    e += 1
    diff -= 1
  }
  if a.exponent > b.exponent { return (ym, xm, e) }
  return (xm, ym, e)
}

extension Decimal {
  public static func + (lhs: Decimal, rhs: Decimal) -> Decimal {
    if lhs.isNaN || rhs.isNaN { return .nan }
    let a = lhs._parts, b = rhs._parts
    let (am, bm, e) = _decimalAlign(a, b)
    if a.negative == b.negative { return Decimal(_parts: _DecimalParts(negative: a.negative, m: am + bm, exponent: e)) }
    let c = _DecimalWords.compare(am, bm)
    if c == 0 { return Decimal() }
    return c > 0 ? Decimal(_parts: _DecimalParts(negative: a.negative, m: am - bm, exponent: e))
                 : Decimal(_parts: _DecimalParts(negative: b.negative, m: bm - am, exponent: e))
  }
  public static func - (lhs: Decimal, rhs: Decimal) -> Decimal { return lhs + (-rhs) }
  public static prefix func - (d: Decimal) -> Decimal {
    if d.isNaN || d.isZero { return d }
    var r = d
    r._isNegative = d._isNegative == 0 ? 1 : 0
    return r
  }
  public static func * (lhs: Decimal, rhs: Decimal) -> Decimal {
    if lhs.isNaN || rhs.isNaN { return .nan }
    let a = lhs._parts, b = rhs._parts
    let m = a.m * b.m
    if m.isZero { return Decimal() }
    return Decimal(_parts: _DecimalParts(negative: a.negative != b.negative, m: m, exponent: a.exponent + b.exponent))
  }
  public static func / (lhs: Decimal, rhs: Decimal) -> Decimal {
    if lhs.isNaN || rhs.isNaN || rhs.isZero { return .nan }
    if lhs.isZero { return Decimal() }
    let a = lhs._parts, b = rhs._parts
    // Scale the dividend up to ~76 digits, then long-divide.
    var num = a.m
    var e = a.exponent - b.exponent
    while num.digitCount < 76 {
      _ = num.mulAdd(10)
      e -= 1
    }
    let q = _decimalDivide(num, b.m)
    return Decimal(_parts: _DecimalParts(negative: a.negative != b.negative, m: q, exponent: e))
  }
  public static func += (lhs: inout Decimal, rhs: Decimal) { lhs = lhs + rhs }
  public static func -= (lhs: inout Decimal, rhs: Decimal) { lhs = lhs - rhs }
  public static func *= (lhs: inout Decimal, rhs: Decimal) { lhs = lhs * rhs }
  public static func /= (lhs: inout Decimal, rhs: Decimal) { lhs = lhs / rhs }

  public mutating func negate() { self = -self }
  public func distance(to other: Decimal) -> Decimal { return other - self }
  public func advanced(by n: Decimal) -> Decimal { return self + n }
}

/// Long division of big mantissas, bit by bit.
internal func _decimalDivide(_ n: _DecimalWords, _ d: _DecimalWords) -> _DecimalWords {
  var q = _DecimalWords([])
  var r = _DecimalWords([])
  var i = n.w.count * 16 - 1
  while i >= 0 {
    _ = r.mulAdd(2, UInt32(n.w[i / 16] >> UInt16(i % 16) & 1))
    _ = q.mulAdd(2)
    if _DecimalWords.compare(r, d) >= 0 {
      r = r - d
      _ = q.mulAdd(1, 1)
    }
    i -= 1
  }
  return q
}

extension Decimal: Equatable, Comparable, Hashable {
  public static func == (lhs: Decimal, rhs: Decimal) -> Bool {
    if lhs.isNaN || rhs.isNaN { return lhs.isNaN && rhs.isNaN }
    if lhs.isZero && rhs.isZero { return true }
    let a = lhs._parts, b = rhs._parts
    if a.negative != b.negative { return false }
    let (am, bm, _) = _decimalAlign(a, b)
    return _DecimalWords.compare(am, bm) == 0
  }
  public static func < (lhs: Decimal, rhs: Decimal) -> Bool {
    if lhs.isNaN || rhs.isNaN { return false }
    let a = lhs._parts, b = rhs._parts
    if lhs.isZero { return !b.negative && !rhs.isZero }
    if rhs.isZero { return a.negative }
    if a.negative != b.negative { return a.negative }
    let (am, bm, _) = _decimalAlign(a, b)
    let c = _DecimalWords.compare(am, bm)
    return a.negative ? c > 0 : c < 0
  }
  public func hash(into hasher: inout Hasher) {
    // Equal values have equal compact forms.
    let c = Decimal(_parts: _parts)
    hasher.combine(c.description)
  }
}

extension Decimal: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
  public init(integerLiteral value: Int) { self.init(Int64(value)) }
  public init(floatLiteral value: Double) { self.init(value) }
}

extension Decimal: CustomStringConvertible {}

extension Decimal: SignedNumeric {
  public init?<T: BinaryInteger>(exactly source: T) {
    if source < 0 {
      guard let m = UInt64(exactly: source.magnitude) else { return nil }
      self = -Decimal(m)
    } else {
      guard let m = UInt64(exactly: source) else { return nil }
      self.init(m)
    }
  }
}

extension Decimal: Strideable {
  public typealias Stride = Decimal
}

extension Decimal: Codable {
  // Apple's keyed form: exponent, length, isNegative, isCompact, mantissa.
  private enum CodingKeys: Int, CodingKey {
    case exponent, length, isNegative, isCompact, mantissa
  }
  public init(from decoder: any Decoder) throws {
    if let single = try? decoder.singleValueContainer(), let d = try? single.decode(Double.self) {
      self.init(d)
      return
    }
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let exponent = try c.decode(Int32.self, forKey: .exponent)
    let length = try c.decode(UInt32.self, forKey: .length)
    let isNegative = try c.decode(Bool.self, forKey: .isNegative)
    let isCompact = try c.decode(Bool.self, forKey: .isCompact)
    var m = try c.nestedUnkeyedContainer(forKey: .mantissa)
    var words: [UInt16] = []
    while !m.isAtEnd && words.count < 8 { words.append(try m.decode(UInt16.self)) }
    words += [UInt16](repeating: 0, count: 8 - words.count)
    var d = Decimal()
    d._exponent = exponent
    d._length = length
    d._isNegative = isNegative ? 1 : 0
    d._isCompact = isCompact ? 1 : 0
    d._mantissa = (words[0], words[1], words[2], words[3], words[4], words[5], words[6], words[7])
    self = d
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(_exponent, forKey: .exponent)
    try c.encode(_length, forKey: .length)
    try c.encode(_isNegative != 0, forKey: .isNegative)
    try c.encode(_isCompact != 0, forKey: .isCompact)
    var m = c.nestedUnkeyedContainer(forKey: .mantissa)
    let t = _mantissa
    for w in [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7] { try m.encode(w) }
  }
}

// MARK: - C functions

/// Rounds `number` to `scale` digits after the point.
@_cdecl("NSDecimalRound")
public func _NSDecimalRound(_ result: UnsafeMutablePointer<Decimal>, _ number: UnsafePointer<Decimal>, _ scale: Int,
                            _ mode: UInt) {
  let d = number.pointee
  if d.isNaN || scale == Int(NSDecimalNoScale) || -Int(d._exponent) <= scale {
    result.pointee = d
    return
  }
  var p = d._parts
  var dropped = -p.exponent - scale
  var lastRem: UInt32 = 0
  var sticky = false
  while dropped > 0 && !p.m.isZero {
    if lastRem != 0 { sticky = true }
    lastRem = p.m.divSmall(10)
    p.exponent += 1
    dropped -= 1
  }
  if dropped > 0 { p.exponent += dropped }
  let anyDropped = lastRem != 0 || sticky
  var roundUp = false
  switch mode {
  case 0: roundUp = lastRem >= 5                                        // plain
  case 1: roundUp = anyDropped && p.negative                            // down (toward -inf)
  case 2: roundUp = anyDropped && !p.negative                           // up (toward +inf)
  default:                                                              // bankers
    if lastRem > 5 || (lastRem == 5 && sticky) { roundUp = true }
    else if lastRem == 5 {
      var probe = p.m
      roundUp = probe.divSmall(2) == 1
    }
  }
  if roundUp { _ = p.m.mulAdd(1, 1) }
  result.pointee = Decimal(_parts: p)
}

public func NSDecimalString(_ dcm: UnsafePointer<Decimal>, _ locale: Any?) -> String { return dcm.pointee.description }
