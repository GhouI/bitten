// View modifiers that change geometry, drawing or behaviour: offset,
// opacity, scale, rotation, shadow, clip, fixed size, aspect ratio,
// position, hit testing, appear/disappear, tasks, traits, value changes,
// animation and transactions. The modifier types keep Apple's frozen
// layouts: Apple's inlinable modifiers build them inside programs.

import CoreGraphics

// MARK: - geometry effects

public struct ProjectionTransform: Equatable, Sendable {
  public var m11: CGFloat = 1, m12: CGFloat = 0, m13: CGFloat = 0
  public var m21: CGFloat = 0, m22: CGFloat = 1, m23: CGFloat = 0
  public var m31: CGFloat = 0, m32: CGFloat = 0, m33: CGFloat = 1
  public init() {}
  public init(_ t: CGAffineTransform) {
    m11 = t.a; m12 = t.b; m21 = t.c; m22 = t.d; m31 = t.tx; m32 = t.ty
  }
  public var isIdentity: Bool { return self == ProjectionTransform() }
  var affine: CGAffineTransform { return CGAffineTransformMake(m11, m12, m21, m22, m31, m32) }
}

public protocol GeometryEffect: Animatable, ViewModifier where Body == Never {
  func effectValue(size: CGSize) -> ProjectionTransform
}
extension GeometryEffect {
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let m = modifier.value
    let content = body(_Graph(), inputs).node
    return _ViewOutputs(_TransformNode(content: content, environment: inputs.environment) { m.effectValue(size: $0).affine })
  }
  public func body(content: Content) -> Never { fatalError("no body") }
}

/// Draws (and hit-tests) its content through a transform of the content's
/// frame, computed from its size; layout is unchanged.
internal final class _TransformNode: _ViewNode {
  let transform: (CGSize) -> CGAffineTransform
  init(content: _ViewNode, environment: EnvironmentValues, transform: @escaping (CGSize) -> CGAffineTransform) {
    self.transform = transform
    super.init(environment: environment, children: [content])
  }
  override func draw(_ context: CGContext) {
    let t = transform(frame.size)
    CGContextSaveGState(context)
    CGContextTranslateCTM(context, frame._minX, frame._minY)
    CGContextConcatCTM(context, t)
    CGContextTranslateCTM(context, -frame._minX, -frame._minY)
    children[0].draw(context)
    CGContextRestoreGState(context)
  }
  override func hit(_ point: CGPoint) -> _ViewNode? {
    let t = CGAffineTransformInvert(transform(frame.size))
    let local = CGPoint(x: point.x - frame._minX, y: point.y - frame._minY)
    let p = CGPoint(x: t.a * local.x + t.c * local.y + t.tx + frame._minX, y: t.b * local.x + t.d * local.y + t.ty + frame._minY)
    return children[0].hit(p)
  }
}

@frozen
public struct _OffsetEffect: GeometryEffect, Equatable {
  public var offset: CGSize
  @inlinable public init(offset: CGSize) { self.offset = offset }
  public func effectValue(size: CGSize) -> ProjectionTransform {
    return ProjectionTransform(CGAffineTransformMakeTranslation(offset.width, offset.height))
  }
  public var animatableData: CGSize.AnimatableData {
    get { return AnimatablePair(offset.width, offset.height) }
    set { offset = CGSize(width: newValue.first, height: newValue.second) }
  }
  public static func == (a: _OffsetEffect, b: _OffsetEffect) -> Bool {
    return a.offset.width == b.offset.width && a.offset.height == b.offset.height
  }
}

@frozen
public struct _ScaleEffect: GeometryEffect, Equatable {
  public var scale: CGSize
  public var anchor: UnitPoint
  @inlinable public init(scale: CGSize, anchor: UnitPoint = .center) {
    self.scale = scale
    self.anchor = anchor
  }
  public func effectValue(size: CGSize) -> ProjectionTransform {
    let ax = size.width * anchor.x, ay = size.height * anchor.y
    var t = CGAffineTransformMakeTranslation(ax, ay)
    t = CGAffineTransformScale(t, scale.width, scale.height)
    t = CGAffineTransformTranslate(t, -ax, -ay)
    return ProjectionTransform(t)
  }
  public typealias AnimatableData = EmptyAnimatableData
  public static func == (a: _ScaleEffect, b: _ScaleEffect) -> Bool {
    return a.scale.width == b.scale.width && a.scale.height == b.scale.height && a.anchor == b.anchor
  }
}

@frozen
public struct _RotationEffect: GeometryEffect, Equatable {
  public var angle: Angle
  public var anchor: UnitPoint
  @inlinable public init(angle: Angle, anchor: UnitPoint = .center) {
    self.angle = angle
    self.anchor = anchor
  }
  public func effectValue(size: CGSize) -> ProjectionTransform {
    let ax = size.width * anchor.x, ay = size.height * anchor.y
    var t = CGAffineTransformMakeTranslation(ax, ay)
    t = CGAffineTransformRotate(t, CGFloat(angle.radians))
    t = CGAffineTransformTranslate(t, -ax, -ay)
    return ProjectionTransform(t)
  }
  public typealias AnimatableData = EmptyAnimatableData
}

extension CGSize {
  public typealias AnimatableData = AnimatablePair<CGFloat, CGFloat>
}

// MARK: - drawing effects

/// Draws its content with a change to the graphics state.
internal final class _DrawEffectNode: _ViewNode {
  let apply: (CGContext, CGRect) -> Bool
  init(content: _ViewNode, environment: EnvironmentValues, apply: @escaping (CGContext, CGRect) -> Bool) {
    self.apply = apply
    super.init(environment: environment, children: [content])
  }
  override func draw(_ context: CGContext) {
    CGContextSaveGState(context)
    if apply(context, frame) { children[0].draw(context) }
    CGContextRestoreGState(context)
  }
}

internal protocol _DrawingModifier: ViewModifier where Body == Never {
  /// Changes `context` for the content; false skips drawing it.
  func apply(_ context: CGContext, _ frame: CGRect, _ environment: EnvironmentValues) -> Bool
}
extension _DrawingModifier {
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let m = modifier.value
    let env = inputs.environment
    let content = body(_Graph(), inputs).node
    return _ViewOutputs(_DrawEffectNode(content: content, environment: env) { m.apply($0, $1, env) })
  }
  public func body(content: Content) -> Never { fatalError("no body") }
}

@frozen
public struct _OpacityEffect: _DrawingModifier, Animatable, Equatable {
  public var opacity: Double
  @inlinable public init(opacity: Double) { self.opacity = opacity }
  public var animatableData: Double {
    get { return opacity }
    set { opacity = newValue }
  }
  func apply(_ context: CGContext, _ frame: CGRect, _ environment: EnvironmentValues) -> Bool {
    CGContextSetAlpha(context, CGFloat(max(0, min(1, opacity))))
    return opacity > 0
  }
}

@frozen
public struct _ShadowEffect: _DrawingModifier, Equatable {
  public var color: Color
  public var radius: CGFloat
  public var offset: CGSize
  @inlinable public init(color: Color, radius: CGFloat, offset: CGSize) {
    self.color = color
    self.radius = radius
    self.offset = offset
  }
  func apply(_ context: CGContext, _ frame: CGRect, _ environment: EnvironmentValues) -> Bool {
    CGContextSetShadowWithColor(context, CGSize(width: offset.width, height: -offset.height), radius,
                                color.resolve(in: environment).cgColor)
    return true
  }
  public static func == (a: _ShadowEffect, b: _ShadowEffect) -> Bool {
    return a.color == b.color && a.radius == b.radius && a.offset.width == b.offset.width && a.offset.height == b.offset.height
  }
}

@frozen
public struct _BlurEffect: _DrawingModifier, Equatable {
  public var radius: CGFloat
  public var isOpaque: Bool
  @inlinable public init(radius: CGFloat, opaque: Bool) {
    self.radius = radius
    isOpaque = opaque
  }
  func apply(_ context: CGContext, _ frame: CGRect, _ environment: EnvironmentValues) -> Bool { return true }
}

@frozen
public struct _ClipEffect<ClipShape: Shape>: _DrawingModifier {
  public var shape: ClipShape
  public var style: FillStyle
  @inlinable public init(shape: ClipShape, style: FillStyle = FillStyle()) {
    self.shape = shape
    self.style = style
  }
  func apply(_ context: CGContext, _ frame: CGRect, _ environment: EnvironmentValues) -> Bool {
    CGContextAddPath(context, shape.path(in: frame).cgPath)
    if style.isEOFilled { CGContextEOClip(context) } else { CGContextClip(context) }
    return true
  }
}

@frozen
public struct _SaturationEffect: _DrawingModifier, Equatable {
  public var amount: Double
  @inlinable public init(amount: Double) { self.amount = amount }
  func apply(_ context: CGContext, _ frame: CGRect, _ environment: EnvironmentValues) -> Bool { return true }
}
@frozen
public struct _GrayscaleEffect: _DrawingModifier, Equatable {
  public var amount: Double
  @inlinable public init(amount: Double) { self.amount = amount }
  func apply(_ context: CGContext, _ frame: CGRect, _ environment: EnvironmentValues) -> Bool { return true }
}
@frozen
public struct _BlendModeEffect: _DrawingModifier, Equatable {
  public var blendMode: BlendMode
  @inlinable public init(blendMode: BlendMode) { self.blendMode = blendMode }
  func apply(_ context: CGContext, _ frame: CGRect, _ environment: EnvironmentValues) -> Bool { return true }
}
@frozen
public struct _CompositingGroupEffect: _DrawingModifier, Equatable {
  @inlinable public init() {}
  func apply(_ context: CGContext, _ frame: CGRect, _ environment: EnvironmentValues) -> Bool { return true }
}
@frozen
public struct _GeometryGroupEffect: _DrawingModifier, Equatable {
  @inlinable public init() {}
  func apply(_ context: CGContext, _ frame: CGRect, _ environment: EnvironmentValues) -> Bool { return true }
}
@frozen
public struct _HiddenModifier: _DrawingModifier, Equatable {
  @inlinable public init() {}
  func apply(_ context: CGContext, _ frame: CGRect, _ environment: EnvironmentValues) -> Bool { return false }
}

public enum BlendMode: Sendable, Equatable, Hashable {
  case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight, difference,
    exclusion, hue, saturation, color, luminosity, sourceAtop, destinationOver, destinationOut, plusDarker,
    plusLighter
}

public enum ColorRenderingMode: Equatable, Hashable, Sendable {
  case nonLinear, linear, extendedLinear
}

// MARK: - layout effects

@frozen
public struct _FixedSizeLayout: _NodeModifier {
  @usableFromInline internal var horizontal: Bool
  @usableFromInline internal var vertical: Bool
  @inlinable public init(horizontal: Bool = true, vertical: Bool = true) {
    self.horizontal = horizontal
    self.vertical = vertical
  }
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode {
    let h = horizontal, v = vertical
    return _ProposalNode(content: content, environment: environment) { p in
      ProposedViewSize(width: h ? nil : p.width, height: v ? nil : p.height)
    }
  }
}

/// Changes the proposal its content sees.
internal final class _ProposalNode: _ViewNode {
  let change: (ProposedViewSize) -> ProposedViewSize
  init(content: _ViewNode, environment: EnvironmentValues, change: @escaping (ProposedViewSize) -> ProposedViewSize) {
    self.change = change
    super.init(environment: environment, children: [content])
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { return children[0].sizeThatFits(change(proposal)) }
  override func place(in rect: CGRect) {
    frame = rect
    let s = children[0].sizeThatFits(change(ProposedViewSize(rect.size)))
    children[0].place(in: CGRect(origin: Alignment.center.origin(of: s, in: rect), size: s))
  }
}

public enum ContentMode: Hashable, CaseIterable, Sendable {
  case fit, fill
}

@frozen
public struct _AspectRatioLayout: _NodeModifier {
  public var aspectRatio: CGFloat?
  public var contentMode: ContentMode
  @inlinable public init(aspectRatio: CGFloat? = nil, contentMode: ContentMode) {
    self.aspectRatio = aspectRatio
    self.contentMode = contentMode
  }
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode {
    return _AspectNode(ratio: aspectRatio, fill: contentMode == .fill, content: content, environment: environment)
  }
}

internal final class _AspectNode: _ViewNode {
  let ratio: CGFloat?
  let fill: Bool
  init(ratio: CGFloat?, fill: Bool, content: _ViewNode, environment: EnvironmentValues) {
    self.ratio = ratio
    self.fill = fill
    super.init(environment: environment, children: [content])
  }
  func target(_ proposal: ProposedViewSize) -> CGSize {
    let ideal = children[0].sizeThatFits(.unspecified)
    let r = ratio ?? (ideal.height > 0 ? ideal.width / ideal.height : 1)
    let p = proposal.replacingUnspecifiedDimensions(by: ideal)
    guard r > 0, p.width > 0, p.height > 0 else { return p }
    let byWidth = CGSize(width: p.width, height: p.width / r), byHeight = CGSize(width: p.height * r, height: p.height)
    if fill { return byWidth.height >= p.height ? byWidth : byHeight }
    return byWidth.height <= p.height ? byWidth : byHeight
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    return children[0].sizeThatFits(ProposedViewSize(target(proposal)))
  }
  override func place(in rect: CGRect) {
    frame = rect
    let s = children[0].sizeThatFits(ProposedViewSize(target(ProposedViewSize(rect.size))))
    children[0].place(in: CGRect(origin: Alignment.center.origin(of: s, in: rect), size: s))
  }
}

@frozen
public struct _PositionLayout: _NodeModifier {
  public var position: CGPoint
  @inlinable public init(position: CGPoint) { self.position = position }
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode {
    return _PositionNode(position: position, content: content, environment: environment)
  }
}
internal final class _PositionNode: _ViewNode {
  let position: CGPoint
  init(position: CGPoint, content: _ViewNode, environment: EnvironmentValues) {
    self.position = position
    super.init(environment: environment, children: [content])
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    return proposal.replacingUnspecifiedDimensions()
  }
  override func place(in rect: CGRect) {
    frame = rect
    let s = children[0].sizeThatFits(.unspecified)
    children[0].place(in: CGRect(origin: CGPoint(x: rect._minX + position.x - s.width / 2,
                                                 y: rect._minY + position.y - s.height / 2), size: s))
  }
}

@frozen
public struct _AlignmentWritingModifier: _NodeModifier {
  @usableFromInline let key: AlignmentKey
  @usableFromInline let computeValue: (ViewDimensions) -> CGFloat
  @inlinable init(key: AlignmentKey, computeValue: @escaping (ViewDimensions) -> CGFloat) {
    self.key = key
    self.computeValue = computeValue
  }
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode { return content }
}

extension View {
  @inlinable public func alignmentGuide(_ g: HorizontalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View {
    return modifier(_AlignmentWritingModifier(key: g.key, computeValue: computeValue))
  }
  @inlinable public func alignmentGuide(_ g: VerticalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat) -> some View {
    return modifier(_AlignmentWritingModifier(key: g.key, computeValue: computeValue))
  }
}

// MARK: - behaviour

@frozen
public struct _AllowsHitTestingModifier: _NodeModifier {
  public var allowsHitTesting: Bool
  @inlinable public init(allowsHitTesting: Bool) { self.allowsHitTesting = allowsHitTesting }
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode {
    return allowsHitTesting ? content : _NoHitNode(environment: environment, children: [content])
  }
}
internal final class _NoHitNode: _ViewNode {
  override func hit(_ point: CGPoint) -> _ViewNode? { return nil }
}

@frozen
public struct _ContentShapeModifier<ContentShape: Shape>: _NodeModifier {
  public var shape: ContentShape
  public var eoFill: Bool
  @inlinable public init(shape: ContentShape, eoFill: Bool = false) {
    self.shape = shape
    self.eoFill = eoFill
  }
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode { return content }
}

/// onAppear/onDisappear: appear runs once when the view joins its host;
/// disappear when it leaves it (the host's next rebuild no longer has it).
@frozen
public struct _AppearanceActionModifier: ViewModifier {
  public var appear: (() -> Void)?
  public var disappear: (() -> Void)?
  @inlinable public init(appear: (() -> Void)? = nil, disappear: (() -> Void)? = nil) {
    self.appear = appear
    self.disappear = disappear
  }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let m = modifier.value
    let context = inputs.base.context
    let key = inputs.base.path + "#appear"
    context.lifecycle(key, appear: m.appear, disappear: m.disappear)
    return body(_Graph(), inputs)
  }
  public func body(content: Content) -> Never { fatalError("no body") }
  public typealias Body = Never
}

/// `.task`: started when the view appears, cancelled when it goes.
@frozen
public struct _TaskModifier: ViewModifier {
  @usableFromInline internal var action: @Sendable () async -> Void
  @usableFromInline internal var priority: TaskPriority
  @inlinable internal init(priority: TaskPriority, action: @escaping @Sendable () async -> Void) {
    self.action = action
    self.priority = priority
  }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let m = modifier.value
    let box = inputs.base.context.store(inputs.base.path + "#task") { _TaskBox() }
    let key = inputs.base.path + "#task-life"
    inputs.base.context.lifecycle(key, appear: {
      box.task = Task(priority: m.priority) { await m.action() }
    }, disappear: { box.task?.cancel() })
    return body(_Graph(), inputs)
  }
  public func body(content: Content) -> Never { fatalError("no body") }
  public typealias Body = Never
}
final class _TaskBox {
  var task: Task<Void, Never>?
  var value: Any?
}

@frozen
public struct _TaskValueModifier<Value: Equatable>: ViewModifier {
  @usableFromInline internal var action: @Sendable () async -> Void
  @usableFromInline internal var priority: TaskPriority
  @usableFromInline internal var value: Value
  public init(value: Value, priority: TaskPriority, action: @escaping @Sendable () async -> Void) {
    self.action = action
    self.priority = priority
    self.value = value
  }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let m = modifier.value
    let box = inputs.base.context.store(inputs.base.path + "#taskv") { _TaskBox() }
    if (box.value as? Value) != m.value || box.task == nil {
      box.task?.cancel()
      box.value = m.value
      box.task = Task(priority: m.priority) { await m.action() }
    }
    inputs.base.context.lifecycle(inputs.base.path + "#taskv-life", appear: nil, disappear: { box.task?.cancel() })
    return body(_Graph(), inputs)
  }
  public func body(content: Content) -> Never { fatalError("no body") }
  public typealias Body = Never
}

/// The old `onChange(of:perform:)`.
@frozen
public struct _ValueActionModifier<Value: Equatable>: ViewModifier {
  public var value: Value
  public var action: (Value) -> Void
  @inlinable public init(value: Value, action: @escaping (Value) -> Void) {
    self.value = value
    self.action = action
  }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let m = modifier.value
    _valueChanged(m.value, key: inputs.base.path + "#change", inputs: inputs, initial: false) { _, new in m.action(new) }
    return body(_Graph(), inputs)
  }
  public func body(content: Content) -> Never { fatalError("no body") }
  public typealias Body = Never
}

/// Calls `action(old, new)` after this update when `value` differs from
/// the last one seen at `key` (or the first time, when `initial`).
internal func _valueChanged<V: Equatable>(_ value: V, key: String, inputs: _ViewInputs, initial: Bool,
                                          _ action: @escaping (V, V) -> Void) {
  let box = inputs.base.context.store(key) { _Box<V?>(nil) }
  let old = box.value
  box.value = value
  if let o = old {
    if o != value { DispatchQueue.main.async { action(o, value) } }
  } else if initial {
    DispatchQueue.main.async { action(value, value) }
  }
}

@frozen
public struct _AnimationModifier<Value: Equatable>: ViewModifier {
  public var animation: Animation?
  public var value: Value
  @inlinable public init(animation: Animation?, value: Value) {
    self.animation = animation
    self.value = value
  }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    return body(_Graph(), inputs)
  }
  public func body(content: Content) -> Never { fatalError("no body") }
  public typealias Body = Never
}

@frozen
public struct _TransactionModifier: ViewModifier {
  public var transform: (inout Transaction) -> Void
  @inlinable public init(transform: @escaping (inout Transaction) -> Void) { self.transform = transform }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    return body(_Graph(), inputs)
  }
  public func body(content: Content) -> Never { fatalError("no body") }
  public typealias Body = Never
}

@frozen
public struct _BackgroundShapeModifier<Style: ShapeStyle, Bg: Shape>: _NodeModifier {
  public var style: Style
  public var shape: Bg
  public var fillStyle: FillStyle
  @inlinable public init(style: Style, shape: Bg, fillStyle: FillStyle) {
    self.style = style
    self.shape = shape
    self.fillStyle = fillStyle
  }
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode {
    let fill = _ShapeNode(shape: shape, paint: style._paint(in: environment), eoFill: fillStyle.isEOFilled, stroke: nil,
                          environment: environment)
    return _LayeredNode(primary: content, layer: fill, alignment: .center, behind: true, environment: environment)
  }
}

public protocol InsettableShape: Shape {
  associatedtype InsetShape: InsettableShape
  func inset(by amount: CGFloat) -> InsetShape
}
extension Rectangle: InsettableShape {
  public func inset(by amount: CGFloat) -> some InsettableShape { return _InsetRect(amount: amount) }
}
public struct _InsetRect: InsettableShape {
  var amount: CGFloat
  public func path(in rect: CGRect) -> Path { return Path(rect._insetBy(amount)) }
  public func inset(by a: CGFloat) -> _InsetRect { return _InsetRect(amount: amount + a) }
  public typealias AnimatableData = EmptyAnimatableData
  public typealias Body = _ShapeView<_InsetRect, ForegroundStyle>
}
extension RoundedRectangle: InsettableShape {
  public func inset(by amount: CGFloat) -> RoundedRectangle._Inset { return _Inset(base: self, amount: amount) }
}
extension RoundedRectangle._Inset: InsettableShape {
  public func inset(by a: CGFloat) -> RoundedRectangle._Inset { return RoundedRectangle._Inset(base: base, amount: amount + a) }
}
extension Circle: InsettableShape {
  public func inset(by amount: CGFloat) -> Circle._Inset { return _Inset(amount: amount) }
}
extension Circle._Inset: InsettableShape {
  public func inset(by a: CGFloat) -> Circle._Inset { return Circle._Inset(amount: amount + a) }
}
extension Capsule: InsettableShape {
  public func inset(by amount: CGFloat) -> some InsettableShape { return _InsetCapsule(amount: amount) }
}
public struct _InsetCapsule: InsettableShape {
  var amount: CGFloat
  public func path(in rect: CGRect) -> Path { return Capsule().path(in: rect._insetBy(amount)) }
  public func inset(by a: CGFloat) -> _InsetCapsule { return _InsetCapsule(amount: amount + a) }
  public typealias AnimatableData = EmptyAnimatableData
  public typealias Body = _ShapeView<_InsetCapsule, ForegroundStyle>
}

@frozen
public struct _InsettableBackgroundShapeModifier<Style: ShapeStyle, Bg: InsettableShape>: _NodeModifier {
  public var style: Style
  public var shape: Bg
  public var fillStyle: FillStyle
  @inlinable public init(style: Style, shape: Bg, fillStyle: FillStyle) {
    self.style = style
    self.shape = shape
    self.fillStyle = fillStyle
  }
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode {
    let fill = _ShapeNode(shape: shape, paint: style._paint(in: environment), eoFill: fillStyle.isEOFilled, stroke: nil,
                          environment: environment)
    return _LayeredNode(primary: content, layer: fill, alignment: .center, behind: true, environment: environment)
  }
}

@frozen
public struct _StrokedShape<S: Shape>: Shape {
  public var shape: S
  public var style: StrokeStyle
  @inlinable public init(shape: S, style: StrokeStyle) {
    self.shape = shape
    self.style = style
  }
  public func path(in rect: CGRect) -> Path { return shape.path(in: rect).strokedPath(style) }
  public typealias AnimatableData = EmptyAnimatableData
  public typealias Body = _ShapeView<_StrokedShape, ForegroundStyle>
}

@frozen
public struct _TrimmedShape<S: Shape>: Shape {
  public var shape: S
  public var startFraction: CGFloat
  public var endFraction: CGFloat
  @inlinable public init(shape: S, startFraction: CGFloat = 0, endFraction: CGFloat = 1) {
    self.shape = shape
    self.startFraction = startFraction
    self.endFraction = endFraction
  }
  public func path(in rect: CGRect) -> Path { return shape.path(in: rect) }
  public typealias AnimatableData = EmptyAnimatableData
  public typealias Body = _ShapeView<_TrimmedShape, ForegroundStyle>
}

extension Shape {
  @inlinable public func trim(from startFraction: CGFloat = 0, to endFraction: CGFloat = 1) -> some Shape {
    return _TrimmedShape(shape: self, startFraction: startFraction, endFraction: endFraction)
  }
}

// MARK: - traits

public protocol _ViewTraitKey {
  associatedtype Value
  static var defaultValue: Value { get }
}

@frozen
public struct _TraitWritingModifier<Trait: _ViewTraitKey>: ViewModifier {
  public let value: Trait.Value
  @inlinable public init(value: Trait.Value) { self.value = value }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let content = body(_Graph(), inputs).node
    return _ViewOutputs(_TraitNode(key: ObjectIdentifier(Trait.self), value: modifier.value.value, content: content,
                                   environment: inputs.environment))
  }
  public func body(content: Content) -> Never { fatalError("no body") }
  public typealias Body = Never
}

internal final class _TraitNode: _ViewNode {
  let key: ObjectIdentifier
  let value: Any
  init(key: ObjectIdentifier, value: Any, content: _ViewNode, environment: EnvironmentValues) {
    self.key = key
    self.value = value
    super.init(environment: environment, children: [content])
  }
  override var layoutPriority: Double {
    if key == ObjectIdentifier(LayoutPriorityTraitKey.self), let p = value as? Double { return p }
    return children[0].layoutPriority
  }
  override var layoutValues: [ObjectIdentifier: Any] {
    var v = children[0].layoutValues
    v[key] = value
    return v
  }
}

public struct LayoutPriorityTraitKey: _ViewTraitKey { public static let defaultValue: Double = 0 }
public struct ZIndexTraitKey: _ViewTraitKey { public static let defaultValue: Double = 0 }
public struct TagValueTraitKey<V: Hashable>: _ViewTraitKey {
  public enum Value { case untagged, tagged(V) }
  public static var defaultValue: Value { return .untagged }
}
public struct IsAuxiliaryContentTraitKey: _ViewTraitKey { public static let defaultValue = false }
public struct ListRowInsetsTraitKey: _ViewTraitKey { public static let defaultValue: EdgeInsets? = nil }
public struct ListRowBackgroundTraitKey: _ViewTraitKey { public static let defaultValue: AnyView? = nil }
public struct TransitionTraitKey: _ViewTraitKey { public static let defaultValue = AnyTransition.opacity }

extension View {
  @inlinable public func _trait<K: _ViewTraitKey>(_ key: K.Type, _ value: K.Value) -> some View {
    return modifier(_TraitWritingModifier<K>(value: value))
  }
  public func layoutPriority(_ value: Double) -> some View { return _trait(LayoutPriorityTraitKey.self, value) }
  public func zIndex(_ value: Double) -> some View { return _trait(ZIndexTraitKey.self, value) }
  public func tag<V: Hashable>(_ tag: V) -> some View { return _trait(TagValueTraitKey<V>.self, .tagged(tag)) }
  public func tag<V: Hashable>(_ tag: V, includeOptional: Bool) -> some View {
    return _trait(TagValueTraitKey<V>.self, .tagged(tag))
  }
  public func listRowInsets(_ insets: EdgeInsets?) -> some View { return _trait(ListRowInsetsTraitKey.self, insets) }
  public func listRowBackground<V: View>(_ view: V?) -> some View {
    return _trait(ListRowBackgroundTraitKey.self, view.map { AnyView($0) })
  }
  public func transition(_ t: AnyTransition) -> some View { return _trait(TransitionTraitKey.self, t) }
  public func transition<T: Transition>(_ t: T) -> some View { return _trait(TransitionTraitKey.self, AnyTransition(t)) }
}

/// `.id(_:)`: a new identity is a new view (its state starts over).
@frozen
public struct IDView<Content: View, ID: Hashable>: View {
  public var content: Content
  public var id: ID
  @inlinable public init(_ content: Content, id: ID) {
    self.content = content
    self.id = id
  }
  public typealias Body = Never
  public var body: Never { fatalError("IDView has no body") }
  public static func _makeView(view: _GraphValue<IDView>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    return Content._makeView(view: _GraphValue({ v.content }), inputs: inputs.named("id:\(v.id.hashValue)"))
  }
}
extension View {
  @inlinable public func id<ID: Hashable>(_ id: ID) -> some View { return IDView(self, id: id) }
}

// MARK: - the modifier functions

extension View {
  public func offset(_ offset: CGSize) -> some View { return modifier(_OffsetEffect(offset: offset)) }
  public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View {
    return modifier(_OffsetEffect(offset: CGSize(width: x, height: y)))
  }
  public func opacity(_ opacity: Double) -> some View { return modifier(_OpacityEffect(opacity: opacity)) }
  public func scaleEffect(_ scale: CGSize, anchor: UnitPoint = .center) -> some View {
    return modifier(_ScaleEffect(scale: scale, anchor: anchor))
  }
  public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> some View {
    return scaleEffect(CGSize(width: s, height: s), anchor: anchor)
  }
  public func scaleEffect(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> some View {
    return scaleEffect(CGSize(width: x, height: y), anchor: anchor)
  }
  public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View {
    return modifier(_RotationEffect(angle: angle, anchor: anchor))
  }
  public func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0,
                     y: CGFloat = 0) -> some View {
    return modifier(_ShadowEffect(color: color, radius: radius, offset: CGSize(width: x, height: y)))
  }
  public func blur(radius: CGFloat, opaque: Bool = false) -> some View {
    return modifier(_BlurEffect(radius: radius, opaque: opaque))
  }
  public func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View {
    return modifier(_ClipEffect(shape: shape, style: style))
  }
  public func clipped(antialiased: Bool = false) -> some View {
    return modifier(_ClipEffect(shape: Rectangle(), style: FillStyle(antialiased: antialiased)))
  }
  public func cornerRadius(_ radius: CGFloat, antialiased: Bool = true) -> some View {
    return clipShape(RoundedRectangle(cornerRadius: radius), style: FillStyle(antialiased: antialiased))
  }
  public func saturation(_ amount: Double) -> some View { return modifier(_SaturationEffect(amount: amount)) }
  public func grayscale(_ amount: Double) -> some View { return modifier(_GrayscaleEffect(amount: amount)) }
  public func blendMode(_ blendMode: BlendMode) -> some View { return modifier(_BlendModeEffect(blendMode: blendMode)) }
  public func compositingGroup() -> some View { return modifier(_CompositingGroupEffect()) }
  public func geometryGroup() -> some View { return modifier(_GeometryGroupEffect()) }
  public func drawingGroup(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear) -> some View {
    return modifier(_CompositingGroupEffect())
  }
  public func hidden() -> some View { return modifier(_HiddenModifier()) }
  public func fixedSize(horizontal: Bool, vertical: Bool) -> some View {
    return modifier(_FixedSizeLayout(horizontal: horizontal, vertical: vertical))
  }
  public func fixedSize() -> some View { return modifier(_FixedSizeLayout()) }
  public func aspectRatio(_ aspectRatio: CGFloat? = nil, contentMode: ContentMode) -> some View {
    return modifier(_AspectRatioLayout(aspectRatio: aspectRatio, contentMode: contentMode))
  }
  public func aspectRatio(_ aspectRatio: CGSize, contentMode: ContentMode) -> some View {
    return self.aspectRatio(aspectRatio.height > 0 ? aspectRatio.width / aspectRatio.height : nil, contentMode: contentMode)
  }
  public func scaledToFit() -> some View { return aspectRatio(contentMode: .fit) }
  public func scaledToFill() -> some View { return aspectRatio(contentMode: .fill) }
  public func position(_ position: CGPoint) -> some View { return modifier(_PositionLayout(position: position)) }
  public func position(x: CGFloat = 0, y: CGFloat = 0) -> some View { return position(CGPoint(x: x, y: y)) }
  public func allowsHitTesting(_ enabled: Bool) -> some View {
    return modifier(_AllowsHitTestingModifier(allowsHitTesting: enabled))
  }
  public func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View {
    return modifier(_ContentShapeModifier(shape: shape, eoFill: eoFill))
  }
  public func onAppear(perform action: (() -> Void)? = nil) -> some View {
    return modifier(_AppearanceActionModifier(appear: action))
  }
  public func onDisappear(perform action: (() -> Void)? = nil) -> some View {
    return modifier(_AppearanceActionModifier(disappear: action))
  }
  public func task(priority: TaskPriority = .userInitiated, _ action: @escaping @Sendable () async -> Void) -> some View {
    return modifier(_TaskModifier(priority: priority, action: action))
  }
  public func task<T: Equatable>(id value: T, priority: TaskPriority = .userInitiated,
                                 _ action: @escaping @Sendable () async -> Void) -> some View {
    return modifier(_TaskValueModifier(value: value, priority: priority, action: action))
  }
  public func onChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
    return modifier(_ValueActionModifier(value: value, action: action))
  }
  public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping (V, V) -> Void) -> some View {
    return modifier(_ValueActionModifier2(value: value, initial: initial, action: action))
  }
  public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping () -> Void) -> some View {
    return modifier(_ValueActionModifier2(value: value, initial: initial, action: { _, _ in action() }))
  }
  public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
    return modifier(_AnimationModifier(animation: animation, value: value))
  }
  public func animation(_ animation: Animation?) -> some View {
    return modifier(_AnimationModifier(animation: animation, value: 0))
  }
  public func animation<V: View>(_ animation: Animation?, @ViewBuilder body: (PlaceholderContentView<Self>) -> V) -> some View {
    return body(PlaceholderContentView(content: self))
  }
  public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some View {
    return modifier(_TransactionModifier(transform: transform))
  }
  public func transaction<V: View>(_ transform: @escaping (inout Transaction) -> Void,
                                   @ViewBuilder body: (PlaceholderContentView<Self>) -> V) -> some View {
    return body(PlaceholderContentView(content: self))
  }
}

struct _ValueActionModifier2<Value: Equatable>: ViewModifier {
  var value: Value
  var initial: Bool
  var action: (Value, Value) -> Void
  static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let m = modifier.value
    _valueChanged(m.value, key: inputs.base.path + "#change2", inputs: inputs, initial: m.initial, m.action)
    return body(_Graph(), inputs)
  }
  func body(content: Content) -> Never { fatalError("no body") }
  typealias Body = Never
}

/// The content an `animation(_:body:)` or `transaction(_:body:)` closure
/// is given.
public struct PlaceholderContentView<Value: View>: View {
  let content: Value
  public typealias Body = Never
  public var body: Never { fatalError("no body") }
  public static func _makeView(view: _GraphValue<PlaceholderContentView>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    return Value._makeView(view: _GraphValue({ v.content }), inputs: inputs)
  }
}

// MARK: - animation (no interpolation: changes land at once)

/// What an animation is; the struct is one reference wide, like the app expects.
@usableFromInline
internal final class AnimationBoxBase: @unchecked Sendable {
  let name: String
  let duration: Double
  init(name: String, duration: Double) {
    self.name = name
    self.duration = duration
  }
}

@frozen
public struct Animation: Equatable, Sendable, CustomStringConvertible {
  @usableFromInline internal var box: AnimationBoxBase
  public init<A: CustomAnimation>(_ base: A) { box = AnimationBoxBase(name: "\(A.self)", duration: 0.35) }
  init(name: String, duration: Double) { box = AnimationBoxBase(name: name, duration: duration) }
  internal var name: String { return box.name }
  internal var duration: Double { return box.duration }
  public static func == (a: Animation, b: Animation) -> Bool {
    return a.box === b.box || (a.name == b.name && a.duration == b.duration)
  }
  public var description: String { return name }
  public static let `default` = Animation(name: "default", duration: 0.35)
  public static var linear: Animation { return Animation(name: "linear", duration: 0.35) }
  public static func linear(duration: Double) -> Animation { return Animation(name: "linear", duration: duration) }
  public static var easeIn: Animation { return Animation(name: "easeIn", duration: 0.35) }
  public static func easeIn(duration: Double) -> Animation { return Animation(name: "easeIn", duration: duration) }
  public static var easeOut: Animation { return Animation(name: "easeOut", duration: 0.35) }
  public static func easeOut(duration: Double) -> Animation { return Animation(name: "easeOut", duration: duration) }
  public static var easeInOut: Animation { return Animation(name: "easeInOut", duration: 0.35) }
  public static func easeInOut(duration: Double) -> Animation { return Animation(name: "easeInOut", duration: duration) }
  public static func timingCurve(_ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double, duration: Double = 0.35)
    -> Animation { return Animation(name: "timingCurve", duration: duration) }
  public static func timingCurve(_ curve: UnitCurve, duration: TimeInterval) -> Animation {
    return Animation(name: "timingCurve", duration: duration)
  }
  public static var spring: Animation { return Animation(name: "spring", duration: 0.5) }
  public static func spring(response: Double = 0.5, dampingFraction: Double = 0.825, blendDuration: TimeInterval = 0)
    -> Animation { return Animation(name: "spring", duration: response) }
  public static func spring(duration: TimeInterval = 0.5, bounce: Double = 0, blendDuration: Double = 0) -> Animation {
    return Animation(name: "spring", duration: duration)
  }
  public static func spring(_ spring: Spring, blendDuration: TimeInterval = 0) -> Animation {
    return Animation(name: "spring", duration: 0.5)
  }
  public static func interpolatingSpring(mass: Double = 1.0, stiffness: Double, damping: Double,
                                         initialVelocity: Double = 0.0) -> Animation {
    // Settling time of a damped spring, roughly.
    let zeta = damping / (2 * (stiffness * mass).squareRoot())
    let omega = (stiffness / mass).squareRoot()
    return Animation(name: "interpolatingSpring", duration: zeta > 0 && omega > 0 ? min(4 / (zeta * omega), 2) : 0.5)
  }
  public static func interpolatingSpring(duration: TimeInterval = 0.5, bounce: Double = 0.0,
                                         initialVelocity: Double = 0.0) -> Animation {
    return Animation(name: "interpolatingSpring", duration: duration)
  }
  public static var interpolatingSpring: Animation { return Animation(name: "interpolatingSpring", duration: 0.5) }
  public static var smooth: Animation { return Animation(name: "smooth", duration: 0.5) }
  public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Animation {
    return Animation(name: "smooth", duration: duration)
  }
  public static var snappy: Animation { return Animation(name: "snappy", duration: 0.5) }
  public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Animation {
    return Animation(name: "snappy", duration: duration)
  }
  public static var bouncy: Animation { return Animation(name: "bouncy", duration: 0.5) }
  public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0) -> Animation {
    return Animation(name: "bouncy", duration: duration)
  }
  public static var interactiveSpring: Animation { return Animation(name: "interactiveSpring", duration: 0.15) }
  public static func interactiveSpring(response: Double = 0.15, dampingFraction: Double = 0.86,
                                       blendDuration: TimeInterval = 0.25) -> Animation {
    return Animation(name: "interactiveSpring", duration: response)
  }
  public func delay(_ delay: Double) -> Animation { return self }
  public func speed(_ speed: Double) -> Animation { return self }
  public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation { return self }
  public func repeatForever(autoreverses: Bool = true) -> Animation { return self }
}

public protocol CustomAnimation: Hashable, Sendable {
  func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V?
}
public struct AnimationContext<Value: VectorArithmetic> {}

public struct AnimationCompletionCriteria: Hashable, Sendable {
  let id: Int
  public static let logicallyComplete = AnimationCompletionCriteria(id: 0)
  public static let removed = AnimationCompletionCriteria(id: 1)
}

/// Runs `body` with `animation` in effect, then `completion`.
public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
  return try body()
}
public func withAnimation<Result>(_ animation: Animation? = .default, completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
                                  _ body: () throws -> Result, completion: @escaping () -> Void) rethrows -> Result {
  let r = try body()
  DispatchQueue.main.async { completion() }
  return r
}
public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
  return try body()
}

// MARK: - transitions

@usableFromInline
internal final class AnyTransitionBox: @unchecked Sendable {
  let name: String
  init(name: String) { self.name = name }
}

@frozen
public struct AnyTransition: Sendable {
  @usableFromInline internal let box: AnyTransitionBox
  public init<T: Transition>(_ transition: T) { box = AnyTransitionBox(name: "\(T.self)") }
  init(name: String) { box = AnyTransitionBox(name: name) }
  internal var name: String { return box.name }
  public static let identity = AnyTransition(name: "identity")
  public static let opacity = AnyTransition(name: "opacity")
  public static let slide = AnyTransition(name: "slide")
  public static func move(edge: Edge) -> AnyTransition { return AnyTransition(name: "move") }
  public static func offset(_ offset: CGSize) -> AnyTransition { return AnyTransition(name: "offset") }
  public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition { return AnyTransition(name: "offset") }
  public static var scale: AnyTransition { return AnyTransition(name: "scale") }
  public static func scale(scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition { return AnyTransition(name: "scale") }
  public static func push(from edge: Edge) -> AnyTransition { return AnyTransition(name: "push") }
  public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition { return insertion }
  public static func modifier<E: ViewModifier>(active: E, identity: E) -> AnyTransition {
    return AnyTransition(name: "modifier(\(E.self))")
  }
  public func combined(with other: AnyTransition) -> AnyTransition { return self }
  public func animation(_ animation: Animation?) -> AnyTransition { return self }
}

public protocol Transition {}
extension Transition {
  public func combined<T: Transition>(with other: T) -> some Transition { return _CombinedTransition(first: self, second: other) }
}
public struct _CombinedTransition<A: Transition, B: Transition>: Transition {
  var first: A, second: B
}
public struct IdentityTransition: Transition { public init() {} }
public struct OpacityTransition: Transition { public init() {} }
public struct ScaleTransition: Transition {
  public var scale: Double
  public var anchor: UnitPoint
  public init(_ scale: Double, anchor: UnitPoint = .center) {
    self.scale = scale
    self.anchor = anchor
  }
}
public struct PushTransition: Transition {
  public var edge: Edge
  public init(edge: Edge) { self.edge = edge }
}
public struct BlurReplaceTransition: Transition {
  public struct Configuration: Equatable, Sendable {
    let id: Int
    public static let downUp = Configuration(id: 0)
    public static let upUp = Configuration(id: 1)
  }
  public var configuration: Configuration
  public init(configuration: Configuration) { self.configuration = configuration }
}
extension Transition where Self == IdentityTransition { public static var identity: IdentityTransition { return .init() } }
extension Transition where Self == OpacityTransition { public static var opacity: OpacityTransition { return .init() } }
extension Transition where Self == ScaleTransition {
  public static var scale: ScaleTransition { return .init(0) }
  public static func scale(_ scale: Double, anchor: UnitPoint = .center) -> ScaleTransition { return .init(scale, anchor: anchor) }
}
extension Transition where Self == PushTransition {
  public static func push(from edge: Edge) -> PushTransition { return .init(edge: edge) }
}
extension Transition where Self == BlurReplaceTransition {
  public static var blurReplace: BlurReplaceTransition { return .init(configuration: .downUp) }
  public static func blurReplace(_ config: BlurReplaceTransition.Configuration = .downUp) -> BlurReplaceTransition {
    return .init(configuration: config)
  }
}

public struct ContentTransition: Equatable, Sendable {
  let id: Int
  public static let identity = ContentTransition(id: 0)
  public static let opacity = ContentTransition(id: 1)
  public static let interpolate = ContentTransition(id: 2)
  public static func numericText(countsDown: Bool = false) -> ContentTransition { return ContentTransition(id: 3) }
  public static func numericText(value: Double) -> ContentTransition { return ContentTransition(id: 3) }
  public static let symbolEffect = ContentTransition(id: 4)
}
extension View {
  public func contentTransition(_ transition: ContentTransition) -> some View { return self }
}
