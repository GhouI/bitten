// Immediate-mode drawing: Canvas and GraphicsContext, gradients, materials,
// ImageRenderer, and Transaction's animation.

import CoreGraphics
import Foundation

// MARK: - Transaction

/// The animation a transaction carries, kept in its property list.
@usableFromInline
internal final class _TransactionStorage {
  var animation: Animation?
  var disablesAnimations = false
  init(animation: Animation?, disablesAnimations: Bool) {
    self.animation = animation
    self.disablesAnimations = disablesAnimations
  }
}

extension Transaction {
  private var _storage: _TransactionStorage? { return plist.elements as? _TransactionStorage }
  private mutating func _mutableStorage() -> _TransactionStorage {
    if let s = _storage {
      if isKnownUniquelyReferenced(&plist.elements) { return s }
      let c = _TransactionStorage(animation: s.animation, disablesAnimations: s.disablesAnimations)
      plist.elements = c
      return c
    }
    let s = _TransactionStorage(animation: nil, disablesAnimations: false)
    plist.elements = s
    return s
  }
  public init(animation: Animation?) {
    self.init()
    self.animation = animation
  }
  public var animation: Animation? {
    get { return _storage?.animation }
    set { _mutableStorage().animation = newValue }
  }
  public var disablesAnimations: Bool {
    get { return _storage?.disablesAnimations ?? false }
    set { _mutableStorage().disablesAnimations = newValue }
  }
  public var isContinuous: Bool { return false }
}

// MARK: - GraphicsContext

/// What Canvas renderers draw with. One reference wide (the app passes it in
/// a register); copies share nothing because every mutation copies first.
@frozen
public struct GraphicsContext {
  @usableFromInline
  internal final class Storage {
    let cg: CGContext
    var environment: EnvironmentValues
    var transform: CGAffineTransform
    var opacity: Double = 1
    var blendMode: BlendMode = .normal
    /// Clips in device space (already transformed).
    var clips: [(CGPath, Bool)] = []
    var shadow: (Color, CGFloat, CGSize)?
    init(cg: CGContext, environment: EnvironmentValues, transform: CGAffineTransform) {
      self.cg = cg
      self.environment = environment
      self.transform = transform
    }
    func copy() -> Storage {
      let s = Storage(cg: cg, environment: environment, transform: transform)
      s.opacity = opacity
      s.blendMode = blendMode
      s.clips = clips
      s.shadow = shadow
      return s
    }
  }
  @usableFromInline internal var storage: Storage

  internal init(cg: CGContext, environment: EnvironmentValues, origin: CGPoint) {
    storage = Storage(cg: cg, environment: environment, transform: CGAffineTransformMake(1, 0, 0, 1, origin.x, origin.y))
  }
  private mutating func _unique() -> Storage {
    if !isKnownUniquelyReferenced(&storage) { storage = storage.copy() }
    return storage
  }

  @frozen
  public struct BlendMode: RawRepresentable, Equatable, Sendable {
    public let rawValue: Int32
    @inlinable public init(rawValue: Int32) { self.rawValue = rawValue }
    public static var normal: BlendMode { return BlendMode(rawValue: 0) }
    public static var multiply: BlendMode { return BlendMode(rawValue: 1) }
    public static var screen: BlendMode { return BlendMode(rawValue: 2) }
    public static var overlay: BlendMode { return BlendMode(rawValue: 3) }
    public static var darken: BlendMode { return BlendMode(rawValue: 4) }
    public static var lighten: BlendMode { return BlendMode(rawValue: 5) }
    public static var colorDodge: BlendMode { return BlendMode(rawValue: 6) }
    public static var colorBurn: BlendMode { return BlendMode(rawValue: 7) }
    public static var softLight: BlendMode { return BlendMode(rawValue: 8) }
    public static var hardLight: BlendMode { return BlendMode(rawValue: 9) }
    public static var difference: BlendMode { return BlendMode(rawValue: 10) }
    public static var exclusion: BlendMode { return BlendMode(rawValue: 11) }
    public static var hue: BlendMode { return BlendMode(rawValue: 12) }
    public static var saturation: BlendMode { return BlendMode(rawValue: 13) }
    public static var color: BlendMode { return BlendMode(rawValue: 14) }
    public static var luminosity: BlendMode { return BlendMode(rawValue: 15) }
    public static var clear: BlendMode { return BlendMode(rawValue: 16) }
    public static var copy: BlendMode { return BlendMode(rawValue: 17) }
    public static var sourceIn: BlendMode { return BlendMode(rawValue: 18) }
    public static var sourceOut: BlendMode { return BlendMode(rawValue: 19) }
    public static var sourceAtop: BlendMode { return BlendMode(rawValue: 20) }
    public static var destinationOver: BlendMode { return BlendMode(rawValue: 21) }
    public static var destinationIn: BlendMode { return BlendMode(rawValue: 22) }
    public static var destinationOut: BlendMode { return BlendMode(rawValue: 23) }
    public static var destinationAtop: BlendMode { return BlendMode(rawValue: 24) }
    public static var xor: BlendMode { return BlendMode(rawValue: 25) }
    public static var plusDarker: BlendMode { return BlendMode(rawValue: 26) }
    public static var plusLighter: BlendMode { return BlendMode(rawValue: 27) }
  }

  @frozen
  public struct ClipOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    @inlinable public init(rawValue: UInt32) { self.rawValue = rawValue }
    @inlinable public static var inverse: ClipOptions { return ClipOptions(rawValue: 1) }
  }
  @frozen
  public struct BlurOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    @inlinable public init(rawValue: UInt32) { self.rawValue = rawValue }
    @inlinable public static var opaque: BlurOptions { return BlurOptions(rawValue: 1) }
    @inlinable public static var dithersResult: BlurOptions { return BlurOptions(rawValue: 2) }
  }
  @frozen
  public struct ShadowOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    @inlinable public init(rawValue: UInt32) { self.rawValue = rawValue }
    @inlinable public static var shadowAbove: ShadowOptions { return ShadowOptions(rawValue: 1) }
    @inlinable public static var shadowOnly: ShadowOptions { return ShadowOptions(rawValue: 2) }
    @inlinable public static var invertsAlpha: ShadowOptions { return ShadowOptions(rawValue: 4) }
    @inlinable public static var disablesGroup: ShadowOptions { return ShadowOptions(rawValue: 8) }
  }
  @frozen
  public struct GradientOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    @inlinable public init(rawValue: UInt32) { self.rawValue = rawValue }
    @inlinable public static var `repeat`: GradientOptions { return GradientOptions(rawValue: 1) }
    @inlinable public static var mirror: GradientOptions { return GradientOptions(rawValue: 2) }
    @inlinable public static var linearColor: GradientOptions { return GradientOptions(rawValue: 4) }
  }
  @frozen
  public struct FilterOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    @inlinable public init(rawValue: UInt32) { self.rawValue = rawValue }
    @inlinable public static var linearColor: FilterOptions { return FilterOptions(rawValue: 1) }
  }

  /// How a path is painted.
  public struct Shading: Sendable {
    internal enum Kind: @unchecked Sendable {
      case color(Color)
      case style(AnyShapeStyle)
      case linear(Gradient, CGPoint, CGPoint)
      case radial(Gradient, CGPoint, CGFloat, CGFloat)
    }
    internal var kind: Kind
    public static var foreground: Shading { return Shading(kind: .style(AnyShapeStyle(ForegroundStyle()))) }
    public static func color(_ color: Color) -> Shading { return Shading(kind: .color(color)) }
    public static func color(_ colorSpace: Color.RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double,
                             opacity: Double = 1) -> Shading {
      return Shading(kind: .color(Color(colorSpace, red: red, green: green, blue: blue, opacity: opacity)))
    }
    public static func style<S: ShapeStyle>(_ style: S) -> Shading { return Shading(kind: .style(AnyShapeStyle(style))) }
    public static func linearGradient(_ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint,
                                      options: GradientOptions = GradientOptions()) -> Shading {
      return Shading(kind: .linear(gradient, startPoint, endPoint))
    }
    public static func radialGradient(_ gradient: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat,
                                      options: GradientOptions = GradientOptions()) -> Shading {
      return Shading(kind: .radial(gradient, center, startRadius, endRadius))
    }
  }

  /// Effects applied to what is drawn after them.
  public struct Filter: Sendable {
    internal enum Kind: @unchecked Sendable {
      case blur(CGFloat)
      case shadow(Color, CGFloat, CGSize)
      case other
    }
    internal var kind: Kind
    public static func blur(radius: CGFloat, options: BlurOptions = BlurOptions()) -> Filter {
      return Filter(kind: .blur(radius))
    }
    public static func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat,
                              x: CGFloat = 0, y: CGFloat = 0, blendMode: BlendMode = .normal,
                              options: ShadowOptions = ShadowOptions()) -> Filter {
      return Filter(kind: .shadow(color, radius, CGSize(width: x, height: y)))
    }
    public static func opacity(_ amount: Double) -> Filter { return Filter(kind: .other) }
    public static func grayscale(_ amount: Double) -> Filter { return Filter(kind: .other) }
    public static func saturation(_ amount: Double) -> Filter { return Filter(kind: .other) }
    public static func brightness(_ amount: Double) -> Filter { return Filter(kind: .other) }
    public static func contrast(_ amount: Double) -> Filter { return Filter(kind: .other) }
    public static func hueRotation(_ angle: Angle) -> Filter { return Filter(kind: .other) }
    public static func colorMultiply(_ color: Color) -> Filter { return Filter(kind: .other) }
  }

  public var environment: EnvironmentValues { return storage.environment }
  public var opacity: Double {
    get { return storage.opacity }
    set { _unique().opacity = newValue }
  }
  public var blendMode: BlendMode {
    get { return storage.blendMode }
    set { _unique().blendMode = newValue }
  }
  public var transform: CGAffineTransform {
    get { return storage.transform }
    set { _unique().transform = newValue }
  }

  public mutating func translateBy(x: CGFloat, y: CGFloat) {
    let s = _unique()
    s.transform = CGAffineTransformTranslate(s.transform, x, y)
  }
  public mutating func scaleBy(x: CGFloat, y: CGFloat) {
    let s = _unique()
    s.transform = CGAffineTransformScale(s.transform, x, y)
  }
  public mutating func rotate(by angle: Angle) {
    let s = _unique()
    s.transform = CGAffineTransformRotate(s.transform, CGFloat(angle.radians))
  }
  public mutating func concatenate(_ matrix: CGAffineTransform) {
    let s = _unique()
    s.transform = CGAffineTransformConcat(matrix, s.transform)
  }
  public mutating func clip(to path: Path, style: FillStyle = FillStyle(), options: ClipOptions = ClipOptions()) {
    let s = _unique()
    var t = s.transform
    if let p = CGPathCreateCopyByTransformingPath(path.cgPath, &t) { s.clips.append((p, style.isEOFilled)) }
  }
  public mutating func clipToLayer(opacity: Double = 1, options: ClipOptions = ClipOptions(),
                                   content: (inout GraphicsContext) throws -> Void) rethrows {}
  public mutating func addFilter(_ filter: Filter, options: FilterOptions = FilterOptions()) {
    let s = _unique()
    if case .shadow(let c, let r, let o) = filter.kind { s.shadow = (c, r, o) }
  }

  /// Runs `body` with the CG state set up for this context.
  private func _withState(_ body: (CGContext) -> Void) {
    let s = storage, cg = s.cg
    CGContextSaveGState(cg)
    for (p, eo) in s.clips {
      CGContextAddPath(cg, p)
      if eo { CGContextEOClip(cg) } else { CGContextClip(cg) }
    }
    CGContextConcatCTM(cg, s.transform)
    CGContextSetAlpha(cg, CGFloat(s.opacity))
    if let m = CGBlendMode(rawValue: s.blendMode.rawValue) { CGContextSetBlendMode(cg, m) }
    if let (c, r, o) = s.shadow {
      let p = c._paint(in: s.environment)
      CGContextSetShadowWithColor(cg, o, r, CGColorCreateSRGB(p.r, p.g, p.b, p.a))
    }
    body(cg)
    CGContextRestoreGState(cg)
  }
  private func _gradient(_ g: Gradient) -> CGGradient? {
    var comps: [CGFloat] = []
    var locs: [CGFloat] = []
    for stop in g.stops {
      let p = stop.color._paint(in: storage.environment)
      comps += [p.r, p.g, p.b, p.a]
      locs.append(stop.location)
    }
    return CGGradientCreateWithColorComponents(CGColorSpaceCreateDeviceRGB(), comps, locs, locs.count)
  }
  /// Fills (or, with a width, strokes) the current path with `shading`.
  private func _paint(_ path: CGPath, _ shading: Shading, eoFill: Bool, stroke: StrokeStyle?) {
    _withState { cg in
      func addPath() {
        CGContextAddPath(cg, path)
        if let st = stroke {
          CGContextSetLineWidth(cg, st.lineWidth)
          CGContextSetLineCap(cg, st.lineCap)
          CGContextSetLineJoin(cg, st.lineJoin)
          if !st.dash.isEmpty { CGContextSetLineDash(cg, st.dashPhase, st.dash, st.dash.count) }
        }
      }
      switch shading.kind {
      case .color(let c):
        let p = c._paint(in: storage.environment)
        if let st = stroke {
          addPath()
          CGContextSetRGBStrokeColor(cg, p.r, p.g, p.b, p.a)
          CGContextSetLineWidth(cg, st.lineWidth)
          CGContextStrokePath(cg)
        } else {
          p.fill(path, in: cg, eoFill: eoFill)
        }
      case .style(let s):
        let p = s._paint(in: storage.environment)
        if let st = stroke {
          addPath()
          CGContextSetRGBStrokeColor(cg, p.r, p.g, p.b, p.a)
          CGContextSetLineWidth(cg, st.lineWidth)
          CGContextStrokePath(cg)
        } else {
          p.fill(path, in: cg, eoFill: eoFill)
        }
      case .linear(let g, let a, let b):
        guard let grad = _gradient(g) else { return }
        if stroke != nil {
          addPath()
          CGContextReplacePathWithStrokedPath(cg)
        } else {
          CGContextAddPath(cg, path)
        }
        if eoFill { CGContextEOClip(cg) } else { CGContextClip(cg) }
        CGContextDrawLinearGradient(cg, grad, a, b, CGGradientDrawingOptions(rawValue: 3))
      case .radial(let g, let c, let r0, let r1):
        guard let grad = _gradient(g) else { return }
        if stroke != nil {
          addPath()
          CGContextReplacePathWithStrokedPath(cg)
        } else {
          CGContextAddPath(cg, path)
        }
        if eoFill { CGContextEOClip(cg) } else { CGContextClip(cg) }
        CGContextDrawRadialGradient(cg, grad, c, r0, c, r1, CGGradientDrawingOptions(rawValue: 3))
      }
    }
  }
  public func fill(_ path: Path, with shading: Shading, style: FillStyle = FillStyle()) {
    _paint(path.cgPath, shading, eoFill: style.isEOFilled, stroke: nil)
  }
  public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
    _paint(path.cgPath, shading, eoFill: false, stroke: style)
  }
  public func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
    _paint(path.cgPath, shading, eoFill: false, stroke: StrokeStyle(lineWidth: lineWidth))
  }
  public func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint = .center) {
    let (font, paint) = text._attributes(in: storage.environment)
    let p = paint ?? ForegroundStyle()._paint(in: storage.environment)
    let s = text._string
    let w = _TextRenderer.width(s, font: font)
    let h = _TextRenderer.metrics(font).lineHeight
    _withState { cg in
      _TextRenderer.draw(s, font: font, paint: p, at: CGPoint(x: point.x - w * anchor.x, y: point.y - h * anchor.y),
                         lineHeight: h, in: cg)
    }
  }
  public func draw(_ text: Text, in rect: CGRect) {
    draw(text, at: CGPoint(x: rect.origin.x, y: rect.origin.y), anchor: .topLeading)
  }
  public func draw(_ image: Image, in rect: CGRect, style: FillStyle = FillStyle()) {
    let node = _makeNode(image.resizable(), inputs: _ViewInputs(_GraphInputs(environment: storage.environment,
                                                                             context: _RenderContext(), path: "")))
    node.place(in: rect)
    _withState { cg in node.draw(cg) }
  }
  public func draw(_ image: Image, at point: CGPoint, anchor: UnitPoint = .center) {
    let node = _makeNode(image, inputs: _ViewInputs(_GraphInputs(environment: storage.environment,
                                                                 context: _RenderContext(), path: "")))
    let size = node.sizeThatFits(.unspecified)
    node.place(in: CGRect(origin: CGPoint(x: point.x - size.width * anchor.x, y: point.y - size.height * anchor.y),
                          size: size))
    _withState { cg in node.draw(cg) }
  }
  public func drawLayer(content: (inout GraphicsContext) throws -> Void) throws {
    var layer = GraphicsContext(storage: storage.copy())
    CGContextSaveGState(storage.cg)
    defer { CGContextRestoreGState(storage.cg) }
    try content(&layer)
  }
  internal init(storage: Storage) { self.storage = storage }
}

// MARK: - Canvas

public struct Canvas<Symbols: View>: View {
  public var symbols: Symbols
  public var renderer: (inout GraphicsContext, CGSize) -> Void
  public var isOpaque: Bool
  public var colorMode: ColorRenderingMode
  public var rendersAsynchronously: Bool
  public init(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false,
              renderer: @escaping (inout GraphicsContext, CGSize) -> Void, @ViewBuilder symbols: () -> Symbols) {
    self.symbols = symbols()
    self.renderer = renderer
    isOpaque = opaque
    self.colorMode = colorMode
    self.rendersAsynchronously = rendersAsynchronously
  }
  public typealias Body = Never
  public var body: Never { fatalError("no body") }
  public static func _makeView(view: _GraphValue<Canvas>, inputs: _ViewInputs) -> _ViewOutputs {
    return _ViewOutputs(_CanvasNode(renderer: view.value.renderer, environment: inputs.environment))
  }
}
extension Canvas where Symbols == EmptyView {
  public init(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false,
              renderer: @escaping (inout GraphicsContext, CGSize) -> Void) {
    self.init(opaque: opaque, colorMode: colorMode, rendersAsynchronously: rendersAsynchronously, renderer: renderer) {
      EmptyView()
    }
  }
}

internal final class _CanvasNode: _ViewNode {
  override func hitsContent(_ point: CGPoint) -> Bool { return frame._contains(point) }
  let renderer: (inout GraphicsContext, CGSize) -> Void
  init(renderer: @escaping (inout GraphicsContext, CGSize) -> Void, environment: EnvironmentValues) {
    self.renderer = renderer
    super.init(environment: environment)
  }
  override func draw(_ context: CGContext) {
    CGContextSaveGState(context)
    CGContextClipToRect(context, frame)
    var g = GraphicsContext(cg: context, environment: environment, origin: frame.origin)
    renderer(&g, frame.size)
    CGContextRestoreGState(context)
  }
}

// MARK: - gradients and materials

@frozen
public struct LinearGradient: ShapeStyle, View, Sendable {
  internal var gradient: Gradient
  internal var startPoint: UnitPoint
  internal var endPoint: UnitPoint
  public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
    self.gradient = gradient
    self.startPoint = startPoint
    self.endPoint = endPoint
  }
  public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
    self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
  }
  public init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {
    self.init(gradient: Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint)
  }
  /// Flat shapes get the gradient's middle colour.
  public func _apply(to shape: inout _ShapeStyle_Shape) {
    guard !gradient.stops.isEmpty else { return }
    gradient.stops[gradient.stops.count / 2].color._apply(to: &shape)
  }
  public typealias Body = _ShapeView<Rectangle, LinearGradient>
  public var body: _ShapeView<Rectangle, LinearGradient> { return _ShapeView(shape: Rectangle(), style: self) }
}

/// A two-dimensional grid of colours.
public struct MeshGradient: ShapeStyle, View, Sendable {
  public enum Locations: Equatable, Sendable {
    case points([SIMD2<Float>])
    case bezierPoints([BezierPoint])
  }
  public enum Colors: Equatable, Sendable {
    case colors([Color])
    case resolvedColors([Color.Resolved])
  }
  @frozen
  public struct BezierPoint: Equatable, Sendable {
    public var position: SIMD2<Float>
    public var leadingControlPoint: SIMD2<Float>
    public var topControlPoint: SIMD2<Float>
    public var trailingControlPoint: SIMD2<Float>
    public var bottomControlPoint: SIMD2<Float>
  }
  public var width: Int
  public var height: Int
  public var locations: Locations
  public var colors: Colors
  public var background: Color
  public var smoothsColors: Bool
  public var colorSpace: Gradient.ColorSpace
  public init(width: Int, height: Int, locations: Locations, colors: Colors, background: Color = .clear,
              smoothsColors: Bool = true, colorSpace: Gradient.ColorSpace = .device) {
    self.width = width
    self.height = height
    self.locations = locations
    self.colors = colors
    self.background = background
    self.smoothsColors = smoothsColors
    self.colorSpace = colorSpace
  }
  public init(width: Int, height: Int, points: [SIMD2<Float>], colors: [Color], background: Color = .clear,
              smoothsColors: Bool = true, colorSpace: Gradient.ColorSpace = .device) {
    self.init(width: width, height: height, locations: .points(points), colors: .colors(colors), background: background,
              smoothsColors: smoothsColors, colorSpace: colorSpace)
  }
  /// Flat shapes get the average of the mesh's colours.
  public func _apply(to shape: inout _ShapeStyle_Shape) {
    guard case .colors(let cs) = colors, !cs.isEmpty else {
      background._apply(to: &shape)
      return
    }
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    for c in cs {
      let p = c._paint(in: shape.environment)
      r += p.r; g += p.g; b += p.b; a += p.a
    }
    let n = CGFloat(cs.count)
    shape.paint = _Paint(r: r / n, g: g / n, b: b / n, a: a / n)
  }
  public typealias Body = _ShapeView<Rectangle, MeshGradient>
  public var body: _ShapeView<Rectangle, MeshGradient> { return _ShapeView(shape: Rectangle(), style: self) }
}

/// Translucent backgrounds; drawn as a tinted window background.
public struct Material: ShapeStyle, Sendable {
  internal let opacity: CGFloat
  public static var ultraThin: Material { return Material(opacity: 0.55) }
  public static var thin: Material { return Material(opacity: 0.7) }
  public static var regular: Material { return Material(opacity: 0.8) }
  public static var thick: Material { return Material(opacity: 0.9) }
  public static var ultraThick: Material { return Material(opacity: 0.95) }
  public static var bar: Material { return Material(opacity: 0.85) }
  public func _apply(to shape: inout _ShapeStyle_Shape) {
    Color._windowBackground._apply(to: &shape)
    shape.paint = shape.paint?.with(opacity: opacity)
  }
}
extension ShapeStyle where Self == Material {
  public static var ultraThinMaterial: Material { return .ultraThin }
  public static var thinMaterial: Material { return .thin }
  public static var regularMaterial: Material { return .regular }
  public static var thickMaterial: Material { return .thick }
  public static var ultraThickMaterial: Material { return .ultraThick }
  public static var bar: Material { return .bar }
}

// MARK: - ScaledMetric

/// A value that scales with the user's text size; text size here is fixed.
@propertyWrapper
public struct ScaledMetric<Value: BinaryFloatingPoint>: DynamicProperty {
  internal var baseValue: Value
  internal var textStyle: Font.TextStyle
  public init(wrappedValue: Value, relativeTo textStyle: Font.TextStyle) {
    baseValue = wrappedValue
    self.textStyle = textStyle
  }
  public init(wrappedValue: Value) { self.init(wrappedValue: wrappedValue, relativeTo: .body) }
  public var wrappedValue: Value { return baseValue }
}

// MARK: - ImageRenderer

/// Renders a view into a bitmap.
@MainActor @preconcurrency
public final class ImageRenderer<Content: View>: ObservableObject {
  public var content: Content
  public var label: Text?
  public var proposedSize: ProposedViewSize = .unspecified
  public var scale: CGFloat = 1
  public var isOpaque = false
  public init(content: Content) { self.content = content }

  public var cgImage: CGImage? {
    let node = _makeNode(content, inputs: _ViewInputs(_GraphInputs(environment: EnvironmentValues(),
                                                                   context: _RenderContext(), path: "")))
    let size = node.sizeThatFits(proposedSize)
    let w = Int((size.width * scale).rounded(.up)), h = Int((size.height * scale).rounded(.up))
    guard w > 0, h > 0,
          let cg = CGBitmapContextCreate(nil, w, h, 8, w * 4, CGColorSpaceCreateDeviceRGB(), 0x2002) else { return nil }
    // Draw top-down like the window does.
    CGContextTranslateCTM(cg, 0, CGFloat(h))
    CGContextScaleCTM(cg, scale, -scale)
    node.place(in: CGRect(origin: CGPoint(x: 0, y: 0), size: size))
    node.draw(cg)
    return CGBitmapContextCreateImage(cg)
  }
  public var nsImage: NSImage? {
    guard let img = cgImage else { return nil }
    return NSImage(cgImage: img, size: NSSize(width: CGFloat(CGImageGetWidth(img)) / scale,
                                              height: CGFloat(CGImageGetHeight(img)) / scale))
  }
}
