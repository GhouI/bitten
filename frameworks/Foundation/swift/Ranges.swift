// NSRange in Swift: equality, hashing, and conversion to and from Swift
// ranges (of integers, and of String indices measured in UTF-16); also
// AffineTransform and the bridging of geometry, Float and Locale.

import CoreGraphics

extension NSRange: Hashable, CustomStringConvertible {
  public static func == (a: NSRange, b: NSRange) -> Bool { return a.location == b.location && a.length == b.length }
  public func hash(into h: inout Hasher) {
    h.combine(location)
    h.combine(length)
  }
  public var description: String { return "{\(location), \(length)}" }
  public var lowerBound: Int { return location }
  public var upperBound: Int { return location + length }
  public func contains(_ index: Int) -> Bool { return index >= location && index < upperBound }
  public func union(_ other: NSRange) -> NSRange {
    let lo = Swift.min(location, other.location), hi = Swift.max(upperBound, other.upperBound)
    return NSRange(location: lo, length: hi - lo)
  }
  public func intersection(_ other: NSRange) -> NSRange? {
    let lo = Swift.max(location, other.location), hi = Swift.min(upperBound, other.upperBound)
    return lo <= hi ? NSRange(location: lo, length: hi - lo) : nil
  }

  public init<R: RangeExpression>(_ region: R) where R.Bound: FixedWidthInteger {
    let r = region.relative(to: 0..<R.Bound.max)
    self.init(location: Int(r.lowerBound), length: Int(r.upperBound - r.lowerBound))
  }
  /// The UTF-16 offsets of a range of String indices.
  public init<R: RangeExpression, S: StringProtocol>(_ region: R, in target: S) where R.Bound == String.Index {
    let r = region.relative(to: target)
    let u = target.utf16
    let start = u.distance(from: u.startIndex, to: r.lowerBound)
    self.init(location: start, length: u.distance(from: r.lowerBound, to: r.upperBound))
  }
  public init(_ range: Range<String.Index>, in target: some StringProtocol) {
    let u = target.utf16
    self.init(location: u.distance(from: u.startIndex, to: range.lowerBound),
              length: u.distance(from: range.lowerBound, to: range.upperBound))
  }
}

extension Range where Bound == Int {
  public init?(_ range: NSRange) {
    guard range.location != NSNotFound else { return nil }
    self = range.location..<(range.location + range.length)
  }
}

extension Range where Bound == String.Index {
  /// The String indices of UTF-16 offsets, if they fall on character
  /// boundaries within the string.
  public init?(_ range: NSRange, in string: __shared String) {
    guard range.location != NSNotFound else { return nil }
    let u = string.utf16
    guard range.location >= 0, range.length >= 0, range.location + range.length <= u.count,
          let lo = u.index(u.startIndex, offsetBy: range.location, limitedBy: u.endIndex),
          let hi = u.index(lo, offsetBy: range.length, limitedBy: u.endIndex),
          let a = lo.samePosition(in: string), let b = hi.samePosition(in: string) else { return nil }
    self = a..<b
  }
  public init?<S: StringProtocol>(_ range: NSRange, in string: __shared S) {
    self.init(range, in: String(string))
  }
}

// MARK: - AffineTransform

public struct AffineTransform: Hashable, Sendable, CustomStringConvertible {
  public var m11: CGFloat, m12: CGFloat, m21: CGFloat, m22: CGFloat, tX: CGFloat, tY: CGFloat
  public init(m11: CGFloat, m12: CGFloat, m21: CGFloat, m22: CGFloat, tX: CGFloat, tY: CGFloat) {
    (self.m11, self.m12, self.m21, self.m22, self.tX, self.tY) = (m11, m12, m21, m22, tX, tY)
  }
  public init() { self.init(m11: 1, m12: 0, m21: 0, m22: 1, tX: 0, tY: 0) }
  public init(translationByX x: CGFloat, byY y: CGFloat) { self.init(m11: 1, m12: 0, m21: 0, m22: 1, tX: x, tY: y) }
  public init(scaleByX x: CGFloat, byY y: CGFloat) { self.init(m11: x, m12: 0, m21: 0, m22: y, tX: 0, tY: 0) }
  public init(scale factor: CGFloat) { self.init(scaleByX: factor, byY: factor) }
  public init(rotationByRadians angle: CGFloat) {
    let c = CGFloat(cos(Double(angle))), s = CGFloat(sin(Double(angle)))
    self.init(m11: c, m12: s, m21: -s, m22: c, tX: 0, tY: 0)
  }
  public init(rotationByDegrees angle: CGFloat) { self.init(rotationByRadians: angle * .pi / 180) }
  public static var identity: AffineTransform { return AffineTransform() }
  public func transform(_ p: CGPoint) -> CGPoint {
    return CGPoint(x: m11 * p.x + m21 * p.y + tX, y: m12 * p.x + m22 * p.y + tY)
  }
  public func transform(_ s: CGSize) -> CGSize {
    return CGSize(width: m11 * s.width + m21 * s.height, height: m12 * s.width + m22 * s.height)
  }
  public mutating func append(_ t: AffineTransform) {
    self = AffineTransform(m11: m11 * t.m11 + m12 * t.m21, m12: m11 * t.m12 + m12 * t.m22,
                           m21: m21 * t.m11 + m22 * t.m21, m22: m21 * t.m12 + m22 * t.m22,
                           tX: tX * t.m11 + tY * t.m21 + t.tX, tY: tX * t.m12 + tY * t.m22 + t.tY)
  }
  public mutating func prepend(_ t: AffineTransform) {
    var r = t
    r.append(self)
    self = r
  }
  public mutating func translate(x: CGFloat, y: CGFloat) { prepend(AffineTransform(translationByX: x, byY: y)) }
  public mutating func scale(_ s: CGFloat) { prepend(AffineTransform(scale: s)) }
  public mutating func scale(x: CGFloat, y: CGFloat) { prepend(AffineTransform(scaleByX: x, byY: y)) }
  public mutating func rotate(byRadians a: CGFloat) { prepend(AffineTransform(rotationByRadians: a)) }
  public mutating func rotate(byDegrees a: CGFloat) { prepend(AffineTransform(rotationByDegrees: a)) }
  public mutating func invert() { if let i = inverted() { self = i } }
  public func inverted() -> AffineTransform? {
    let det = m11 * m22 - m12 * m21
    guard det != 0 else { return nil }
    return AffineTransform(m11: m22 / det, m12: -m12 / det, m21: -m21 / det, m22: m11 / det,
                           tX: (m21 * tY - m22 * tX) / det, tY: (m12 * tX - m11 * tY) / det)
  }
  public var description: String { return "{m11:\(m11), m12:\(m12), m21:\(m21), m22:\(m22), tX:\(tX), tY:\(tY)}" }
}

// MARK: - bridging

extension CGFloat: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSNumber
  public func _bridgeToObjectiveC() -> NSNumber { return NSNumber(value: Double(self)) }
  public static func _forceBridgeFromObjectiveC(_ source: NSNumber, result: inout CGFloat?) {
    result = CGFloat(source.doubleValue)
  }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSNumber, result: inout CGFloat?) -> Bool {
    result = CGFloat(source.doubleValue)
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> CGFloat {
    return CGFloat(source?.doubleValue ?? 0)
  }
}
extension Float: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSNumber
  public func _bridgeToObjectiveC() -> NSNumber { return NSNumber(value: self) }
  public static func _forceBridgeFromObjectiveC(_ source: NSNumber, result: inout Float?) { result = source.floatValue }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSNumber, result: inout Float?) -> Bool {
    result = source.floatValue
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Float { return source?.floatValue ?? 0 }
}
extension CGPoint: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSValue
  public func _bridgeToObjectiveC() -> NSValue { return NSValue(point: self) }
  public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout CGPoint?) { result = source.pointValue }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout CGPoint?) -> Bool {
    result = source.pointValue
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> CGPoint {
    return source?.pointValue ?? CGPoint(x: 0, y: 0)
  }
}
extension CGSize: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSValue
  public func _bridgeToObjectiveC() -> NSValue { return NSValue(size: self) }
  public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout CGSize?) { result = source.sizeValue }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout CGSize?) -> Bool {
    result = source.sizeValue
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> CGSize {
    return source?.sizeValue ?? CGSize(width: 0, height: 0)
  }
}
extension CGRect: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSValue
  public func _bridgeToObjectiveC() -> NSValue { return NSValue(rect: self) }
  public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout CGRect?) { result = source.rectValue }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout CGRect?) -> Bool {
    result = source.rectValue
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> CGRect {
    return source?.rectValue ?? CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 0, height: 0))
  }
}
extension Locale: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSLocale
  public func _bridgeToObjectiveC() -> NSLocale { return NSLocale(localeIdentifier: identifier) }
  public static func _forceBridgeFromObjectiveC(_ source: NSLocale, result: inout Locale?) {
    result = Locale(identifier: source.localeIdentifier)
  }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSLocale, result: inout Locale?) -> Bool {
    result = Locale(identifier: source.localeIdentifier)
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSLocale?) -> Locale {
    return source.map { Locale(identifier: $0.localeIdentifier) } ?? Locale.current
  }
}
