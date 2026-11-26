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
