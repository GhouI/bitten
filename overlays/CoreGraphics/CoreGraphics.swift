// The Swift overlay of CoreGraphics. The importer maps the C typedef
// `CGFloat` to the Swift type `CGFloat` found in this module; it is defined
// in the CoreFoundation overlay (where current macOS keeps it, under its
// original mangled module CoreGraphics) and re-exported here.
@_exported import CoreGraphics
@_exported import CoreFoundation

// On current macOS this API lives in CoreGraphics.framework itself; the
// framework image bitten installs re-exports this library (see the
// Makefile), so programs bound to either find it.

public enum CGPathFillRule: Int, Sendable {
  case winding
  case evenOdd
}

// ---- geometry ----

extension CGPoint: Equatable {
  @_transparent public static func == (a: CGPoint, b: CGPoint) -> Bool { return a.x == b.x && a.y == b.y }
}
extension CGSize: Equatable {
  @_transparent public static func == (a: CGSize, b: CGSize) -> Bool { return a.width == b.width && a.height == b.height }
}
extension CGRect: Equatable {
  @_transparent public static func == (a: CGRect, b: CGRect) -> Bool { return a.origin == b.origin && a.size == b.size }
}
extension CGAffineTransform: Equatable {
  public static func == (a: CGAffineTransform, b: CGAffineTransform) -> Bool {
    return a.a == b.a && a.b == b.b && a.c == b.c && a.d == b.d && a.tx == b.tx && a.ty == b.ty
  }
}

// Apple's overlay conveniences (programs built against it inline most of
// them; code built here calls these).
extension CGPoint {
  public static var zero: CGPoint { return CGPoint(x: 0 as CGFloat, y: 0 as CGFloat) }
  public init(x: Int, y: Int) { self.init(x: CGFloat(x), y: CGFloat(y)) }
  public init(x: Double, y: Double) { self.init(x: CGFloat(x), y: CGFloat(y)) }
  public func applying(_ t: CGAffineTransform) -> CGPoint {
    return CGPoint(x: t.a * x + t.c * y + t.tx, y: t.b * x + t.d * y + t.ty)
  }
}
extension CGSize {
  public static var zero: CGSize { return CGSize(width: 0 as CGFloat, height: 0 as CGFloat) }
  public init(width: Int, height: Int) { self.init(width: CGFloat(width), height: CGFloat(height)) }
  public init(width: Double, height: Double) { self.init(width: CGFloat(width), height: CGFloat(height)) }
}
extension CGVector {
  public static var zero: CGVector { return CGVector(dx: 0 as CGFloat, dy: 0 as CGFloat) }
  public init(dx: Int, dy: Int) { self.init(dx: CGFloat(dx), dy: CGFloat(dy)) }
  public init(dx: Double, dy: Double) { self.init(dx: CGFloat(dx), dy: CGFloat(dy)) }
}
extension CGRect {
  public static var zero: CGRect { return CGRect(origin: .zero, size: .zero) }
  public static var null: CGRect {
    return CGRect(origin: CGPoint(x: CGFloat.infinity, y: CGFloat.infinity), size: .zero)
  }
  public static var infinite: CGRect {
    let big = CGFloat.greatestFiniteMagnitude
    return CGRect(origin: CGPoint(x: -big / 2, y: -big / 2), size: CGSize(width: big, height: big))
  }
  public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
    self.init(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
  }
  public init(x: Double, y: Double, width: Double, height: Double) {
    self.init(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
  }
  public init(x: Int, y: Int, width: Int, height: Int) {
    self.init(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
  }
  public var width: CGFloat { return abs(size.width) }
  public var height: CGFloat { return abs(size.height) }
  public var minX: CGFloat { return Swift.min(origin.x, origin.x + size.width) }
  public var maxX: CGFloat { return Swift.max(origin.x, origin.x + size.width) }
  public var midX: CGFloat { return origin.x + size.width / 2 }
  public var minY: CGFloat { return Swift.min(origin.y, origin.y + size.height) }
  public var maxY: CGFloat { return Swift.max(origin.y, origin.y + size.height) }
  public var midY: CGFloat { return origin.y + size.height / 2 }
  public var isNull: Bool { return origin.x.isInfinite || origin.y.isInfinite }
  public var isEmpty: Bool { return isNull || size.width == 0 || size.height == 0 }
  public var isInfinite: Bool { return self == CGRect.infinite }
  public var standardized: CGRect {
    if isNull { return self }
    return CGRect(x: minX, y: minY, width: width, height: height)
  }
  public var integral: CGRect {
    if isNull { return self }
    let s = standardized
    let x0 = s.minX.rounded(.down), y0 = s.minY.rounded(.down)
    return CGRect(x: x0, y: y0, width: s.maxX.rounded(.up) - x0, height: s.maxY.rounded(.up) - y0)
  }
  public func insetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
    if isNull { return self }
    let s = standardized
    let r = CGRect(x: s.minX + dx, y: s.minY + dy, width: s.width - 2 * dx, height: s.height - 2 * dy)
    return r.size.width < 0 || r.size.height < 0 ? .null : r
  }
  public func offsetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
    if isNull { return self }
    return CGRect(x: origin.x + dx, y: origin.y + dy, width: size.width, height: size.height)
  }
  public func union(_ r: CGRect) -> CGRect {
    if isNull { return r }
    if r.isNull { return self }
    let x0 = Swift.min(minX, r.minX), y0 = Swift.min(minY, r.minY)
    return CGRect(x: x0, y: y0, width: Swift.max(maxX, r.maxX) - x0, height: Swift.max(maxY, r.maxY) - y0)
  }
  public func intersection(_ r: CGRect) -> CGRect {
    if isNull || r.isNull { return .null }
    let x0 = Swift.max(minX, r.minX), y0 = Swift.max(minY, r.minY)
    let x1 = Swift.min(maxX, r.maxX), y1 = Swift.min(maxY, r.maxY)
    return x1 < x0 || y1 < y0 ? .null : CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }
  public func intersects(_ r: CGRect) -> Bool {
    let i = intersection(r)
    return !i.isNull && i.width > 0 && i.height > 0
  }
  public func contains(_ p: CGPoint) -> Bool {
    return !isNull && p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
  }
  public func contains(_ r: CGRect) -> Bool { return union(r) == self }
  public func applying(_ t: CGAffineTransform) -> CGRect {
    if isNull { return self }
    let ps = [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: minX, y: maxY), CGPoint(x: maxX, y: maxY)]
      .map { $0.applying(t) }
    let xs = ps.map { $0.x }, ys = ps.map { $0.y }
    let x0 = xs.min()!, y0 = ys.min()!
    return CGRect(x: x0, y: y0, width: xs.max()! - x0, height: ys.max()! - y0)
  }
}

// As Apple's overlay prints them: "(1.0, 2.0)", "(x, y, width, height)".
extension CGPoint: CustomDebugStringConvertible {
  public var debugDescription: String { return "(\(x), \(y))" }
}
extension CGSize: CustomDebugStringConvertible {
  public var debugDescription: String { return "(\(width), \(height))" }
}
extension CGVector: CustomDebugStringConvertible {
  public var debugDescription: String { return "(\(dx), \(dy))" }
}
extension CGRect: CustomDebugStringConvertible {
  public var debugDescription: String { return "(\(origin.x), \(origin.y), \(size.width), \(size.height))" }
}

extension CGRect {
  public init?(dictionaryRepresentation dict: CFDictionary) {
    var r = CGRect()
    guard CGRectMakeWithDictionaryRepresentation(dict, &r) else { return nil }
    self = r
  }
  public var dictionaryRepresentation: CFDictionary { return CGRectCreateDictionaryRepresentation(self) }
}
extension CGPoint {
  public init?(dictionaryRepresentation dict: CFDictionary) {
    var p = CGPoint()
    guard CGPointMakeWithDictionaryRepresentation(dict, &p) else { return nil }
    self = p
  }
  public var dictionaryRepresentation: CFDictionary { return CGPointCreateDictionaryRepresentation(self) }
}
extension CGSize {
  public init?(dictionaryRepresentation dict: CFDictionary) {
    var s = CGSize()
    guard CGSizeMakeWithDictionaryRepresentation(dict, &s) else { return nil }
    self = s
  }
  public var dictionaryRepresentation: CFDictionary { return CGSizeCreateDictionaryRepresentation(self) }
}

// ---- paths ----

extension CGMutablePath {
  public func move(to point: CGPoint, transform: CGAffineTransform = CGAffineTransformIdentity) {
    var t = transform
    CGPathMoveToPoint(self, &t, point.x, point.y)
  }
  public func addLine(to point: CGPoint, transform: CGAffineTransform = CGAffineTransformIdentity) {
    var t = transform
    CGPathAddLineToPoint(self, &t, point.x, point.y)
  }
  public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint,
                       transform: CGAffineTransform = CGAffineTransformIdentity) {
    var t = transform
    CGPathAddCurveToPoint(self, &t, control1.x, control1.y, control2.x, control2.y, end.x, end.y)
  }
  public func addQuadCurve(to end: CGPoint, control: CGPoint, transform: CGAffineTransform = CGAffineTransformIdentity) {
    var t = transform
    CGPathAddQuadCurveToPoint(self, &t, control.x, control.y, end.x, end.y)
  }
  public func addRect(_ rect: CGRect, transform: CGAffineTransform = CGAffineTransformIdentity) {
    var t = transform
    CGPathAddRect(self, &t, rect)
  }
  public func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat,
                             transform: CGAffineTransform = CGAffineTransformIdentity) {
    var t = transform
    CGPathAddRoundedRect(self, &t, rect, cornerWidth, cornerHeight)
  }
  public func addEllipse(in rect: CGRect, transform: CGAffineTransform = CGAffineTransformIdentity) {
    var t = transform
    CGPathAddEllipseInRect(self, &t, rect)
  }
  public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool,
                     transform: CGAffineTransform = CGAffineTransformIdentity) {
    var t = transform
    CGPathAddArc(self, &t, center.x, center.y, radius, startAngle, endAngle, clockwise)
  }
  public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat,
                     transform: CGAffineTransform = CGAffineTransformIdentity) {
    var t = transform
    CGPathAddArcToPoint(self, &t, tangent1End.x, tangent1End.y, tangent2End.x, tangent2End.y, radius)
  }
  public func addPath(_ path: CGPath, transform: CGAffineTransform = CGAffineTransformIdentity) {
    var t = transform
    CGPathAddPath(self, &t, path)
  }
  public func closeSubpath() { CGPathCloseSubpath(self) }
}

extension CGPath {
  /// The two outlines together. bitten has no path boolean operations: the
  /// result holds both subpath sets, which fills as their union under the
  /// non-zero rule when they wind the same way.
  public func union(_ other: CGPath, using rule: CGPathFillRule = .winding) -> CGPath {
    let m = CGPathCreateMutableCopy(self)!
    CGPathAddPath(m, nil, other)
    return m
  }
}

// ---- contexts ----

extension CGContext {
  public func fillPath(using rule: CGPathFillRule = .winding) {
    if rule == .evenOdd { CGContextEOFillPath(self) } else { CGContextFillPath(self) }
  }
  public func clip(using rule: CGPathFillRule = .winding) {
    if rule == .evenOdd { CGContextEOClip(self) } else { CGContextClip(self) }
  }
  public func draw(_ image: CGImage, in rect: CGRect, byTiling: Bool = false) {
    if byTiling { CGContextDrawTiledImage(self, rect, image) } else { CGContextDrawImage(self, rect, image) }
  }
  public func setLineDash(phase: CGFloat, lengths: [CGFloat]) {
    lengths.withUnsafeBufferPointer { CGContextSetLineDash(self, phase, $0.baseAddress, $0.count) }
  }
  public var textPosition: CGPoint {
    get { return CGContextGetTextPosition(self) }
    set { CGContextSetTextPosition(self, newValue.x, newValue.y) }
  }
}
