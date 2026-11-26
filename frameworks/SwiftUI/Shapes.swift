// Paths, shapes and shape styles. Path, Color and the built-in shapes keep
// Apple's frozen layouts; the styles resolve to a paint the nodes draw.

import CoreGraphics

// MARK: - geometry types

@frozen
public struct UnitPoint: Hashable, Sendable {
  public var x: CGFloat
  public var y: CGFloat
  @inlinable public init() { self.init(x: 0, y: 0) }
  @inlinable public init(x: CGFloat, y: CGFloat) {
    self.x = x
    self.y = y
  }
  public static let zero = UnitPoint(x: 0, y: 0)
  public static let center = UnitPoint(x: 0.5, y: 0.5)
  public static let leading = UnitPoint(x: 0, y: 0.5)
  public static let trailing = UnitPoint(x: 1, y: 0.5)
  public static let top = UnitPoint(x: 0.5, y: 0)
  public static let bottom = UnitPoint(x: 0.5, y: 1)
  public static let topLeading = UnitPoint(x: 0, y: 0)
  public static let topTrailing = UnitPoint(x: 1, y: 0)
  public static let bottomLeading = UnitPoint(x: 0, y: 1)
  public static let bottomTrailing = UnitPoint(x: 1, y: 1)
}

public enum RoundedCornerStyle: Hashable, Sendable {
  case circular
  case continuous
}

@frozen
public struct FillStyle: Equatable, Sendable {
  public var isEOFilled: Bool
  public var isAntialiased: Bool
  @inlinable public init(eoFill: Bool = false, antialiased: Bool = true) {
    isEOFilled = eoFill
    isAntialiased = antialiased
  }
}

@frozen
public struct StrokeStyle: Equatable, Sendable {
  public var lineWidth: CGFloat
  public var lineCap: CGLineCap
  public var lineJoin: CGLineJoin
  public var miterLimit: CGFloat
  public var dash: [CGFloat]
  public var dashPhase: CGFloat
  public init(lineWidth: CGFloat = 1, lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter,
              miterLimit: CGFloat = 10, dash: [CGFloat] = [], dashPhase: CGFloat = 0) {
    self.lineWidth = lineWidth
    self.lineCap = lineCap
    self.lineJoin = lineJoin
    self.miterLimit = miterLimit
    self.dash = dash
    self.dashPhase = dashPhase
  }
  public static func == (a: StrokeStyle, b: StrokeStyle) -> Bool {
    return a.lineWidth == b.lineWidth && a.lineCap == b.lineCap && a.lineJoin == b.lineJoin &&
      a.miterLimit == b.miterLimit && a.dash == b.dash && a.dashPhase == b.dashPhase
  }
}

public enum LayoutDirection: Hashable, CaseIterable, Sendable {
  case leftToRight
  case rightToLeft
}

public enum LayoutDirectionBehavior: Hashable, Sendable {
  case fixed
  case mirrors(in: LayoutDirection)
  public static var mirrors: LayoutDirectionBehavior { return .mirrors(in: .rightToLeft) }
}

public enum ShapeRole: Hashable, Sendable {
  case fill
  case stroke
  case separator
}

// MARK: - Path

@usableFromInline
internal struct FixedRoundedRect: Equatable {
  var rect: CGRect
  var cornerSize: CGSize
  var style: RoundedCornerStyle
  @usableFromInline static func == (a: FixedRoundedRect, b: FixedRoundedRect) -> Bool {
    return a.rect._equals(b.rect) && a.cornerSize.width == b.cornerSize.width &&
      a.cornerSize.height == b.cornerSize.height && a.style == b.style
  }
}
@usableFromInline
internal struct StrokedPath: Equatable {
  var path: Path
  var style: StrokeStyle
}
@usableFromInline
internal struct TrimmedPath: Equatable {
  var path: Path
  var from: CGFloat
  var to: CGFloat
}

@frozen
public struct Path: Equatable, @unchecked Sendable {
  @usableFromInline
  internal final class PathBox: Equatable {
    let cg: CGMutablePath
    init(_ cg: CGMutablePath) { self.cg = cg }
    @usableFromInline static func == (a: PathBox, b: PathBox) -> Bool { return a === b || CGPathEqualToPath(a.cg, b.cg) }
  }

  @usableFromInline @frozen
  internal enum Storage: Equatable {
    case empty
    case rect(CGRect)
    case ellipse(CGRect)
    indirect case roundedRect(FixedRoundedRect)
    indirect case stroked(StrokedPath)
    indirect case trimmed(TrimmedPath)
    case path(PathBox)
    @usableFromInline static func == (a: Storage, b: Storage) -> Bool {
      switch (a, b) {
      case (.empty, .empty): return true
      case (.rect(let x), .rect(let y)), (.ellipse(let x), .ellipse(let y)): return x._equals(y)
      case (.roundedRect(let x), .roundedRect(let y)): return x == y
      case (.stroked(let x), .stroked(let y)): return x == y
      case (.trimmed(let x), .trimmed(let y)): return x == y
      case (.path(let x), .path(let y)): return x == y
      default: return false
      }
    }
  }
  internal var storage: Storage

  public init() { storage = .empty }
  public init(_ rect: CGRect) { storage = .rect(rect) }
  public init(ellipseIn rect: CGRect) { storage = .ellipse(rect) }
  public init(roundedRect rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous) {
    storage = .roundedRect(FixedRoundedRect(rect: rect, cornerSize: cornerSize, style: style))
  }
  public init(roundedRect rect: CGRect, cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
    self.init(roundedRect: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: style)
  }
  public init(_ path: CGPath) { storage = .path(PathBox(CGPathCreateMutableCopy(path)!)) }
  public init(_ path: CGMutablePath) { storage = .path(PathBox(CGPathCreateMutableCopy(path)!)) }
  public init(_ callback: (inout Path) -> ()) {
    var p = Path()
    callback(&p)
    self = p
  }

  /// The path as a CGPath.
  public var cgPath: CGPath {
    switch storage {
    case .empty: return CGPathCreateMutable()
    case .rect(let r): return CGPathCreateWithRect(r, nil)
    case .ellipse(let r): return CGPathCreateWithEllipseInRect(r, nil)
    case .roundedRect(let rr):
      let w = min(rr.cornerSize.width, rr.rect._width / 2), h = min(rr.cornerSize.height, rr.rect._height / 2)
      return CGPathCreateWithRoundedRect(rr.rect, max(0, w), max(0, h), nil)
    case .stroked(let s):
      return CGPathCreateCopyByStrokingPath(s.path.cgPath, nil, s.style.lineWidth, s.style.lineCap, s.style.lineJoin,
                                            s.style.miterLimit) ?? CGPathCreateMutable()
    case .trimmed(let t): return t.path.cgPath
    case .path(let box): return box.cg
    }
  }

  /// A path of our own to add to: the box is copied unless only this
  /// value holds it.
  private mutating func mutable() -> CGMutablePath {
    if case .path(let box) = storage {
      storage = .empty
      var b = box
      if isKnownUniquelyReferenced(&b) {
        storage = .path(b)
        return b.cg
      }
      let m = CGPathCreateMutableCopy(b.cg)!
      storage = .path(PathBox(m))
      return m
    }
    let m = CGPathCreateMutableCopy(cgPath)!
    storage = .path(PathBox(m))
    return m
  }

  public var isEmpty: Bool {
    if case .empty = storage { return true }
    return CGPathIsEmpty(cgPath)
  }
  public var boundingRect: CGRect {
    switch storage {
    case .empty: return ._zero
    case .rect(let r), .ellipse(let r): return r
    case .roundedRect(let rr): return rr.rect
    default: return CGPathGetPathBoundingBox(cgPath)
    }
  }
  public func contains(_ p: CGPoint, eoFill: Bool = false) -> Bool {
    return CGPathContainsPoint(cgPath, nil, p, eoFill)
  }

  public mutating func move(to p: CGPoint) { CGPathMoveToPoint(mutable(), nil, p.x, p.y) }
  public mutating func addLine(to p: CGPoint) { CGPathAddLineToPoint(mutable(), nil, p.x, p.y) }
  public mutating func addQuadCurve(to p: CGPoint, control cp: CGPoint) {
    CGPathAddQuadCurveToPoint(mutable(), nil, cp.x, cp.y, p.x, p.y)
  }
  public mutating func addCurve(to p: CGPoint, control1 cp1: CGPoint, control2 cp2: CGPoint) {
    CGPathAddCurveToPoint(mutable(), nil, cp1.x, cp1.y, cp2.x, cp2.y, p.x, p.y)
  }
  public mutating func closeSubpath() { CGPathCloseSubpath(mutable()) }
  public mutating func addRect(_ rect: CGRect, transform: CGAffineTransform = CGAffineTransformMake(1, 0, 0, 1, 0, 0)) {
    var t = transform
    CGPathAddRect(mutable(), &t, rect)
  }
  public mutating func addRoundedRect(in rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .continuous,
                                      transform: CGAffineTransform = CGAffineTransformMake(1, 0, 0, 1, 0, 0)) {
    var t = transform
    let w = min(cornerSize.width, rect._width / 2), h = min(cornerSize.height, rect._height / 2)
    CGPathAddRoundedRect(mutable(), &t, rect, max(0, w), max(0, h))
  }
  public mutating func addEllipse(in rect: CGRect, transform: CGAffineTransform = CGAffineTransformMake(1, 0, 0, 1, 0, 0)) {
    var t = transform
    CGPathAddEllipseInRect(mutable(), &t, rect)
  }
  public mutating func addArc(center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle, clockwise: Bool,
                              transform: CGAffineTransform = CGAffineTransformMake(1, 0, 0, 1, 0, 0)) {
    var t = transform
    CGPathAddArc(mutable(), &t, center.x, center.y, radius, startAngle.radians, endAngle.radians, clockwise)
  }
  public mutating func addLines(_ lines: [CGPoint]) {
    guard let first = lines.first else { return }
    move(to: first)
    for p in lines.dropFirst() { addLine(to: p) }
  }
  public mutating func addPath(_ path: Path, transform: CGAffineTransform = CGAffineTransformMake(1, 0, 0, 1, 0, 0)) {
    var t = transform
    CGPathAddPath(mutable(), &t, path.cgPath)
  }
  public func applying(_ transform: CGAffineTransform) -> Path {
    var t = transform
    guard let c = CGPathCreateMutableCopyByTransformingPath(cgPath, &t) else { return self }
    return Path(c)
  }
  public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path {
    return applying(CGAffineTransformMakeTranslation(dx, dy))
  }
  public func strokedPath(_ style: StrokeStyle) -> Path {
    return Path(cgPath: .stroked(StrokedPath(path: self, style: style)))
  }
  public func trimmedPath(from: CGFloat, to: CGFloat) -> Path {
    return Path(cgPath: .trimmed(TrimmedPath(path: self, from: from, to: to)))
  }
  private init(cgPath storage: Storage) { self.storage = storage }
}

extension Path: Shape {
  public func path(in rect: CGRect) -> Path { return self }
  public typealias AnimatableData = EmptyAnimatableData
  public typealias Body = _ShapeView<Path, ForegroundStyle>
}

extension CGRect {
  internal func _equals(_ o: CGRect) -> Bool {
    return origin.x == o.origin.x && origin.y == o.origin.y && size.width == o.size.width && size.height == o.size.height
  }
  internal func _insetBy(_ d: CGFloat) -> CGRect {
    return CGRect(_x: origin.x + d, y: origin.y + d, width: max(0, size.width - 2 * d), height: max(0, size.height - 2 * d))
  }
}

@frozen
public struct Angle: Hashable, Comparable, Sendable {
  public var radians: Double
  @inlinable public var degrees: Double {
    get { return radians * (180.0 / .pi) }
    set { radians = newValue * (.pi / 180.0) }
  }
  @inlinable public init() { self.init(radians: 0.0) }
  @inlinable public init(radians: Double) { self.radians = radians }
  @inlinable public init(degrees: Double) { self.init(radians: degrees * (.pi / 180.0)) }
  @inlinable public static func radians(_ radians: Double) -> Angle { return Angle(radians: radians) }
  @inlinable public static func degrees(_ degrees: Double) -> Angle { return Angle(degrees: degrees) }
  public static let zero = Angle()
  public static func < (a: Angle, b: Angle) -> Bool { return a.radians < b.radians }
}

// MARK: - shape styles

/// What a style paints: a solid sRGB colour (gradients draw as their first
/// stop for now).
internal struct _Paint {
  var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
  static let clear = _Paint(r: 0, g: 0, b: 0, a: 0)
  func with(opacity: CGFloat) -> _Paint { return _Paint(r: r, g: g, b: b, a: a * opacity) }
  func fill(_ path: CGPath, in context: CGContext, eoFill: Bool = false) {
    guard a > 0 else { return }
    CGContextSetRGBFillColor(context, r, g, b, a)
    CGContextAddPath(context, path)
    if eoFill { CGContextEOFillPath(context) } else { CGContextFillPath(context) }
  }
  func stroke(_ path: CGPath, in context: CGContext, width: CGFloat) {
    guard a > 0 else { return }
    CGContextSetRGBStrokeColor(context, r, g, b, a)
    CGContextSetLineWidth(context, width)
    CGContextAddPath(context, path)
    CGContextStrokePath(context)
  }
}

public struct _ShapeStyle_Shape {
  internal var environment: EnvironmentValues
  internal var paint: _Paint?
  internal init(environment: EnvironmentValues) { self.environment = environment }
}
public struct _ShapeStyle_ShapeType {
  internal init() {}
}

public protocol ShapeStyle: Sendable {
  static func _makeView<S: Shape>(view: _GraphValue<_ShapeView<S, Self>>, inputs: _ViewInputs) -> _ViewOutputs
  func _apply(to shape: inout _ShapeStyle_Shape)
  static func _apply(to type: inout _ShapeStyle_ShapeType)
  associatedtype Resolved: ShapeStyle = Never
  func resolve(in environment: EnvironmentValues) -> Resolved
}

extension ShapeStyle {
  public static func _makeView<S: Shape>(view: _GraphValue<_ShapeView<S, Self>>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    return _ViewOutputs(_ShapeNode(shape: v.shape, paint: v.style._paint(in: inputs.environment),
                                   eoFill: v.fillStyle.isEOFilled, stroke: nil, environment: inputs.environment))
  }
  /// The default: a style that resolves to another applies that one.
  public func _apply(to shape: inout _ShapeStyle_Shape) {
    if Resolved.self != Never.self { resolve(in: shape.environment)._apply(to: &shape) }
  }
  public static func _apply(to type: inout _ShapeStyle_ShapeType) {}
  internal func _paint(in environment: EnvironmentValues) -> _Paint {
    var s = _ShapeStyle_Shape(environment: environment)
    _apply(to: &s)
    return s.paint ?? .clear
  }
}
extension ShapeStyle where Resolved == Never {
  public func resolve(in environment: EnvironmentValues) -> Never { fatalError("\(Self.self) does not resolve") }
}

extension Never: ShapeStyle {
  public typealias Resolved = Never
}

extension ShapeStyle {
  @inlinable public func opacity(_ opacity: Double) -> some ShapeStyle {
    return _OpacityShapeStyle(style: self, opacity: Float(opacity))
  }
}

@frozen
public struct _OpacityShapeStyle<Style: ShapeStyle>: ShapeStyle {
  public var style: Style
  public var opacity: Float
  @inlinable public init(style: Style, opacity: Float) {
    self.style = style
    self.opacity = opacity
  }
  public func _apply(to shape: inout _ShapeStyle_Shape) {
    style._apply(to: &shape)
    shape.paint = shape.paint?.with(opacity: CGFloat(opacity))
  }
}

/// The current foreground style (`.foregroundStyle`, or primary).
@frozen
public struct ForegroundStyle: ShapeStyle {
  @inlinable public init() {}
  public func _apply(to shape: inout _ShapeStyle_Shape) {
    if let s = shape.environment._foregroundStyle {
      s._apply(to: &shape)
    } else {
      Color.primary._apply(to: &shape)
    }
  }
}

@frozen
public struct BackgroundStyle: ShapeStyle {
  @inlinable public init() {}
  public func _apply(to shape: inout _ShapeStyle_Shape) {
    if let s = shape.environment._backgroundStyle { s._apply(to: &shape) } else { Color._windowBackground._apply(to: &shape) }
  }
}

@frozen
public struct TintShapeStyle: ShapeStyle {
  @inlinable public init() {}
  public func _apply(to shape: inout _ShapeStyle_Shape) {
    if let t = shape.environment.tint { t._apply(to: &shape) } else { Color.accentColor._apply(to: &shape) }
  }
}

@frozen
public struct HierarchicalShapeStyle: ShapeStyle {
  @usableFromInline internal var id: UInt32
  @usableFromInline internal init(id: UInt32) { self.id = id }
  public static let primary = HierarchicalShapeStyle(id: 0)
  public static let secondary = HierarchicalShapeStyle(id: 1)
  public static let tertiary = HierarchicalShapeStyle(id: 2)
  public static let quaternary = HierarchicalShapeStyle(id: 3)
  public static let quinary = HierarchicalShapeStyle(id: 4)
  /// Set while the foreground is being resolved: a foreground that is
  /// itself hierarchical (`.foregroundStyle(.secondary)`) leveled against
  /// itself would recurse, so it levels the primary colour instead.
  nonisolated(unsafe) private static var resolving = false
  public func _apply(to shape: inout _ShapeStyle_Shape) {
    if HierarchicalShapeStyle.resolving {
      Color.primary._apply(to: &shape)
    } else {
      HierarchicalShapeStyle.resolving = true
      ForegroundStyle()._apply(to: &shape)
      HierarchicalShapeStyle.resolving = false
    }
    let levels: [CGFloat] = [1, 0.5, 0.25, 0.18, 0.1]
    shape.paint = shape.paint?.with(opacity: levels[Int(min(id, 4))])
  }
}

extension ShapeStyle where Self == ForegroundStyle {
  public static var foreground: ForegroundStyle { return ForegroundStyle() }
}
extension ShapeStyle where Self == BackgroundStyle {
  public static var background: BackgroundStyle { return BackgroundStyle() }
}
extension ShapeStyle where Self == TintShapeStyle {
  public static var tint: TintShapeStyle { return TintShapeStyle() }
}
extension ShapeStyle where Self == HierarchicalShapeStyle {
  public static var primary: HierarchicalShapeStyle { return .primary }
  public static var secondary: HierarchicalShapeStyle { return .secondary }
  public static var tertiary: HierarchicalShapeStyle { return .tertiary }
  public static var quaternary: HierarchicalShapeStyle { return .quaternary }
}

@usableFromInline
internal class AnyShapeStyleBox: @unchecked Sendable {
  func apply(to shape: inout _ShapeStyle_Shape) {}
}
final class _ShapeStyleBox<S: ShapeStyle>: AnyShapeStyleBox, @unchecked Sendable {
  let style: S
  init(_ s: S) { style = s }
  override func apply(to shape: inout _ShapeStyle_Shape) { style._apply(to: &shape) }
}

@frozen
public struct AnyShapeStyle: ShapeStyle {
  @usableFromInline internal var storage: AnyShapeStyleBox
  public init<S: ShapeStyle>(_ style: S) {
    if let any = style as? AnyShapeStyle { storage = any.storage } else { storage = _ShapeStyleBox(style) }
  }
  public func _apply(to shape: inout _ShapeStyle_Shape) { storage.apply(to: &shape) }
}

// MARK: - shapes

public protocol Shape: Sendable, Animatable, View {
  func path(in rect: CGRect) -> Path
  static var role: ShapeRole { get }
  var layoutDirectionBehavior: LayoutDirectionBehavior { get }
  func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize
}

extension Shape {
  public static var role: ShapeRole { return .fill }
  public var layoutDirectionBehavior: LayoutDirectionBehavior { return .mirrors }
  public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    return proposal.replacingUnspecifiedDimensions()
  }
  public var body: _ShapeView<Self, ForegroundStyle> { return _ShapeView(shape: self, style: ForegroundStyle()) }
  public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
    let shape = view.value
    return _ShapeView<Self, ForegroundStyle>._makeView(view: _GraphValue({ _ShapeView(shape: shape, style: ForegroundStyle()) }),
                                                        inputs: inputs)
  }
  public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
    return _ViewListOutputs([_makeView(view: view, inputs: inputs.base).node])
  }

  public func fill<S: ShapeStyle>(_ content: S, style: FillStyle = FillStyle()) -> _ShapeView<Self, S> {
    return _ShapeView(shape: self, style: content, fillStyle: style)
  }
  public func fill(style: FillStyle = FillStyle()) -> _ShapeView<Self, ForegroundStyle> {
    return _ShapeView(shape: self, style: ForegroundStyle(), fillStyle: style)
  }
  public func stroke<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1) -> some View {
    return _StrokedShapeView(shape: self, style: content, strokeStyle: StrokeStyle(lineWidth: lineWidth))
  }
  public func stroke<S: ShapeStyle>(_ content: S, style: StrokeStyle) -> some View {
    return _StrokedShapeView(shape: self, style: content, strokeStyle: style)
  }
  public func stroke(lineWidth: CGFloat = 1) -> some View {
    return _StrokedShapeView(shape: self, style: ForegroundStyle(), strokeStyle: StrokeStyle(lineWidth: lineWidth))
  }
  public func stroke(style: StrokeStyle) -> some View {
    return _StrokedShapeView(shape: self, style: ForegroundStyle(), strokeStyle: style)
  }
}

extension Shape where AnimatableData == EmptyAnimatableData {}

@frozen
public struct _ShapeView<Content: Shape, Style: ShapeStyle>: View {
  public var shape: Content
  public var style: Style
  public var fillStyle: FillStyle
  @inlinable public init(shape: Content, style: Style, fillStyle: FillStyle = FillStyle()) {
    self.shape = shape
    self.style = style
    self.fillStyle = fillStyle
  }
  public typealias Body = Never
  public var body: Never { fatalError("_ShapeView has no body") }
  public static func _makeView(view: _GraphValue<_ShapeView>, inputs: _ViewInputs) -> _ViewOutputs {
    return Style._makeView(view: view, inputs: inputs)
  }
}

internal struct _StrokedShapeView<Content: Shape, Style: ShapeStyle>: View {
  var shape: Content
  var style: Style
  var strokeStyle: StrokeStyle
  typealias Body = Never
  var body: Never { fatalError("no body") }
  static func _makeView(view: _GraphValue<_StrokedShapeView>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    return _ViewOutputs(_ShapeNode(shape: v.shape, paint: v.style._paint(in: inputs.environment), eoFill: false,
                                   stroke: v.strokeStyle, environment: inputs.environment))
  }
}

internal final class _ShapeNode<S: Shape>: _ViewNode {
  let shape: S
  let paint: _Paint
  let eoFill: Bool
  let stroke: StrokeStyle?
  init(shape: S, paint: _Paint, eoFill: Bool, stroke: StrokeStyle?, environment: EnvironmentValues) {
    self.shape = shape
    self.paint = paint
    self.eoFill = eoFill
    self.stroke = stroke
    super.init(environment: environment)
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { return shape.sizeThatFits(proposal) }
  override func draw(_ context: CGContext) {
    if let s = stroke {
      let p = shape.path(in: frame._insetBy(s.lineWidth / 2)).cgPath
      paint.stroke(p, in: context, width: s.lineWidth)
    } else {
      paint.fill(shape.path(in: frame).cgPath, in: context, eoFill: eoFill)
    }
  }
}

@frozen
public struct Rectangle: Shape {
  @inlinable public init() {}
  public func path(in rect: CGRect) -> Path { return Path(rect) }
  public typealias AnimatableData = EmptyAnimatableData
  public typealias Body = _ShapeView<Rectangle, ForegroundStyle>
}

@frozen
public struct RoundedRectangle: Shape {
  public var cornerSize: CGSize
  public var style: RoundedCornerStyle
  @inlinable public init(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) {
    self.cornerSize = cornerSize
    self.style = style
  }
  @inlinable public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
    self.init(cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: style)
  }
  public func path(in rect: CGRect) -> Path { return Path(roundedRect: rect, cornerSize: cornerSize, style: style) }
  public var animatableData: AnimatablePair<CGFloat, CGFloat> {
    get { return AnimatablePair(cornerSize.width, cornerSize.height) }
    set { cornerSize = CGSize(width: newValue.first, height: newValue.second) }
  }
  public static func _makeAnimatable(value: inout _GraphValue<RoundedRectangle>, inputs: _GraphInputs) {}
  public typealias Body = _ShapeView<RoundedRectangle, ForegroundStyle>

  @frozen
  public struct _Inset: Shape {
    @usableFromInline var base: RoundedRectangle
    @usableFromInline var amount: CGFloat
    @inlinable init(base: RoundedRectangle, amount: CGFloat) {
      self.base = base
      self.amount = amount
    }
    public func path(in rect: CGRect) -> Path { return base.path(in: rect._insetBy(amount)) }
    public var animatableData: AnimatablePair<RoundedRectangle.AnimatableData, CGFloat> {
      get { return AnimatablePair(base.animatableData, amount) }
      set {
        base.animatableData = newValue.first
        amount = newValue.second
      }
    }
    public static func _makeAnimatable(value: inout _GraphValue<_Inset>, inputs: _GraphInputs) {}
    public typealias Body = _ShapeView<_Inset, ForegroundStyle>
  }
}

@frozen
public struct UnevenRoundedRectangle: Shape {
  public var cornerRadii: RectangleCornerRadii
  public var style: RoundedCornerStyle
  public init(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) {
    self.cornerRadii = cornerRadii
    self.style = style
  }
  public init(topLeadingRadius: CGFloat = 0, bottomLeadingRadius: CGFloat = 0, bottomTrailingRadius: CGFloat = 0,
              topTrailingRadius: CGFloat = 0, style: RoundedCornerStyle = .continuous) {
    self.init(cornerRadii: RectangleCornerRadii(topLeading: topLeadingRadius, bottomLeading: bottomLeadingRadius,
                                                bottomTrailing: bottomTrailingRadius, topTrailing: topTrailingRadius),
              style: style)
  }
  public func path(in rect: CGRect) -> Path {
    let r = cornerRadii
    let x0 = rect._minX, y0 = rect._minY, x1 = rect._maxX, y1 = rect._maxY
    let lim = min(rect._width, rect._height) / 2
    let tl = min(r.topLeading, lim), tr = min(r.topTrailing, lim)
    let bl = min(r.bottomLeading, lim), br = min(r.bottomTrailing, lim)
    var p = Path()
    p.move(to: CGPoint(x: x0 + tl, y: y0))
    p.addLine(to: CGPoint(x: x1 - tr, y: y0))
    if tr > 0 { p.addQuadCurve(to: CGPoint(x: x1, y: y0 + tr), control: CGPoint(x: x1, y: y0)) }
    p.addLine(to: CGPoint(x: x1, y: y1 - br))
    if br > 0 { p.addQuadCurve(to: CGPoint(x: x1 - br, y: y1), control: CGPoint(x: x1, y: y1)) }
    p.addLine(to: CGPoint(x: x0 + bl, y: y1))
    if bl > 0 { p.addQuadCurve(to: CGPoint(x: x0, y: y1 - bl), control: CGPoint(x: x0, y: y1)) }
    p.addLine(to: CGPoint(x: x0, y: y0 + tl))
    if tl > 0 { p.addQuadCurve(to: CGPoint(x: x0 + tl, y: y0), control: CGPoint(x: x0, y: y0)) }
    p.closeSubpath()
    return p
  }
  public typealias AnimatableData = EmptyAnimatableData
  public typealias Body = _ShapeView<UnevenRoundedRectangle, ForegroundStyle>
}

@frozen
public struct RectangleCornerRadii: Equatable, Sendable {
  public var topLeading: CGFloat
  public var bottomLeading: CGFloat
  public var bottomTrailing: CGFloat
  public var topTrailing: CGFloat
  public init(topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat) {
    self.init(topLeading: topLeft, bottomLeading: bottomLeft, bottomTrailing: bottomRight, topTrailing: topRight)
  }
  public init(topLeading: CGFloat = 0, bottomLeading: CGFloat = 0, bottomTrailing: CGFloat = 0, topTrailing: CGFloat = 0) {
    self.topLeading = topLeading
    self.bottomLeading = bottomLeading
    self.bottomTrailing = bottomTrailing
    self.topTrailing = topTrailing
  }
}

@frozen
public struct Circle: Shape {
  @inlinable public init() {}
  public func path(in rect: CGRect) -> Path {
    let d = min(rect._width, rect._height)
    let r = CGRect(_x: rect._minX + (rect._width - d) / 2, y: rect._minY + (rect._height - d) / 2, width: d, height: d)
    return Path(ellipseIn: r)
  }
  public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    let s = proposal.replacingUnspecifiedDimensions()
    let d = min(s.width, s.height)
    return CGSize(width: d, height: d)
  }
  public typealias AnimatableData = EmptyAnimatableData
  public typealias Body = _ShapeView<Circle, ForegroundStyle>

  @frozen
  public struct _Inset: Shape {
    @usableFromInline var amount: CGFloat
    @inlinable init(amount: CGFloat) { self.amount = amount }
    public func path(in rect: CGRect) -> Path { return Circle().path(in: rect._insetBy(amount)) }
    public var animatableData: CGFloat {
      get { return amount }
      set { amount = newValue }
    }
    public static func _makeAnimatable(value: inout _GraphValue<_Inset>, inputs: _GraphInputs) {}
    public typealias Body = _ShapeView<_Inset, ForegroundStyle>
  }
}

@frozen
public struct Ellipse: Shape {
  @inlinable public init() {}
  public func path(in rect: CGRect) -> Path { return Path(ellipseIn: rect) }
  public typealias AnimatableData = EmptyAnimatableData
  public typealias Body = _ShapeView<Ellipse, ForegroundStyle>
}

@frozen
public struct Capsule: Shape {
  public var style: RoundedCornerStyle
  @inlinable public init(style: RoundedCornerStyle = .continuous) { self.style = style }
  public func path(in rect: CGRect) -> Path {
    return Path(roundedRect: rect, cornerRadius: min(rect._width, rect._height) / 2, style: style)
  }
  public typealias AnimatableData = EmptyAnimatableData
  public typealias Body = _ShapeView<Capsule, ForegroundStyle>
}

@usableFromInline
internal class AnyShapeBox: @unchecked Sendable {
  func path(in rect: CGRect) -> Path { return Path() }
  func sizeThatFits(_ p: ProposedViewSize) -> CGSize { return p.replacingUnspecifiedDimensions() }
}
final class _ShapeBox<S: Shape>: AnyShapeBox, @unchecked Sendable {
  let shape: S
  init(_ s: S) { shape = s }
  override func path(in rect: CGRect) -> Path { return shape.path(in: rect) }
  override func sizeThatFits(_ p: ProposedViewSize) -> CGSize { return shape.sizeThatFits(p) }
}

@frozen
public struct AnyShape: Shape {
  @usableFromInline internal var storage: AnyShapeBox
  public init<S: Shape>(_ shape: S) { storage = _ShapeBox(shape) }
  public func path(in rect: CGRect) -> Path { return storage.path(in: rect) }
  public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { return storage.sizeThatFits(proposal) }
  public typealias AnimatableData = EmptyAnimatableData
  public typealias Body = _ShapeView<AnyShape, ForegroundStyle>
}
