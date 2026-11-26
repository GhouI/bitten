// Leaf views (Color, Text, Image, Button) and what they read from the
// environment: fonts, foreground and background styles, tint. Color, Font,
// Image, Text and KeyEquivalent keep Apple's frozen layouts.

import CoreGraphics
import CoreText

// MARK: - Color

@usableFromInline
internal class AnyColorBox: @unchecked Sendable {
  func resolve(in environment: EnvironmentValues) -> Color.Resolved { return Color.Resolved(red: 0, green: 0, blue: 0) }
  func isEqual(to other: AnyColorBox) -> Bool { return self === other }
  var description: String { return "Color" }
}

final class _RGBColorBox: AnyColorBox, @unchecked Sendable {
  let color: Color.Resolved
  let name: String?
  init(_ c: Color.Resolved, name: String? = nil) {
    color = c
    self.name = name
  }
  override func resolve(in environment: EnvironmentValues) -> Color.Resolved { return color }
  override func isEqual(to other: AnyColorBox) -> Bool {
    guard let o = other as? _RGBColorBox else { return false }
    return o.color == color
  }
  override var description: String { return name ?? "#\(color)" }
}

/// Colours that depend on the environment (primary and secondary follow the
/// colour scheme).
final class _DynamicColorBox: AnyColorBox, @unchecked Sendable {
  let light: Color.Resolved, dark: Color.Resolved
  let name: String
  init(_ name: String, light: Color.Resolved, dark: Color.Resolved) {
    self.name = name
    self.light = light
    self.dark = dark
  }
  override func resolve(in environment: EnvironmentValues) -> Color.Resolved {
    return environment.colorScheme == .dark ? dark : light
  }
  override func isEqual(to other: AnyColorBox) -> Bool { return (other as? _DynamicColorBox)?.name == name }
  override var description: String { return name }
}

final class _OpacityColorBox: AnyColorBox, @unchecked Sendable {
  let base: Color, opacity: Double
  init(_ base: Color, _ opacity: Double) {
    self.base = base
    self.opacity = opacity
  }
  override func resolve(in environment: EnvironmentValues) -> Color.Resolved {
    var r = base.provider.resolve(in: environment)
    r.opacity *= Float(opacity)
    return r
  }
  override func isEqual(to other: AnyColorBox) -> Bool {
    guard let o = other as? _OpacityColorBox else { return false }
    return o.base == base && o.opacity == opacity
  }
  override var description: String { return "\(opacity * 100)% \(base)" }
}

final class _NSColorBox: AnyColorBox, @unchecked Sendable {
  let color: NSColor
  init(_ c: NSColor) { color = c }
  override func resolve(in environment: EnvironmentValues) -> Color.Resolved {
    return Color.Resolved(cgColor: color.cgColor)
  }
  override func isEqual(to other: AnyColorBox) -> Bool { return (other as? _NSColorBox)?.color == color }
}

@frozen
public struct Color: Hashable, CustomStringConvertible, Sendable {
  @usableFromInline internal var provider: AnyColorBox
  internal init(box: AnyColorBox) { provider = box }

  public enum RGBColorSpace: Hashable, Sendable {
    case sRGB
    case sRGBLinear
    case displayP3
  }

  @frozen
  public struct Resolved: Hashable, Sendable {
    public var linearRed: Float
    public var linearGreen: Float
    public var linearBlue: Float
    public var opacity: Float

    static func toLinear(_ c: Float) -> Float {
      return c <= 0.04045 ? c / 12.92 : Float(Foundation.pow(Double((c + 0.055) / 1.055), 2.4))
    }
    static func toSRGB(_ c: Float) -> Float {
      return c <= 0.0031308 ? c * 12.92 : 1.055 * Float(Foundation.pow(Double(c), 1 / 2.4)) - 0.055
    }
    public init(colorSpace: RGBColorSpace = .sRGB, red: Float, green: Float, blue: Float, opacity: Float = 1) {
      if colorSpace == .sRGBLinear {
        linearRed = red
        linearGreen = green
        linearBlue = blue
      } else {
        linearRed = Color.Resolved.toLinear(red)
        linearGreen = Color.Resolved.toLinear(green)
        linearBlue = Color.Resolved.toLinear(blue)
      }
      self.opacity = opacity
    }
    internal init(cgColor: CGColor) {
      let n = CGColorGetNumberOfComponents(cgColor)
      guard let c = CGColorGetComponents(cgColor), n > 0 else {
        self.init(red: 0, green: 0, blue: 0)
        return
      }
      if n >= 3 {
        self.init(red: Float(c[0]), green: Float(c[1]), blue: Float(c[2]), opacity: Float(CGColorGetAlpha(cgColor)))
      } else {
        self.init(red: Float(c[0]), green: Float(c[0]), blue: Float(c[0]), opacity: Float(CGColorGetAlpha(cgColor)))
      }
    }
    public var red: Float {
      get { return Color.Resolved.toSRGB(linearRed) }
      set { linearRed = Color.Resolved.toLinear(newValue) }
    }
    public var green: Float {
      get { return Color.Resolved.toSRGB(linearGreen) }
      set { linearGreen = Color.Resolved.toLinear(newValue) }
    }
    public var blue: Float {
      get { return Color.Resolved.toSRGB(linearBlue) }
      set { linearBlue = Color.Resolved.toLinear(newValue) }
    }
    public var cgColor: CGColor {
      return CGColorCreateSRGB(CGFloat(red), CGFloat(green), CGFloat(blue), CGFloat(opacity))
    }
    internal var paint: _Paint {
      return _Paint(r: CGFloat(red), g: CGFloat(green), b: CGFloat(blue), a: CGFloat(opacity))
    }
  }

  public init(_ colorSpace: RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) {
    provider = _RGBColorBox(Resolved(colorSpace: colorSpace, red: Float(red), green: Float(green), blue: Float(blue),
                                     opacity: Float(opacity)))
  }
  public init(_ colorSpace: RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) {
    self.init(colorSpace, red: white, green: white, blue: white, opacity: opacity)
  }
  public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) {
    let h = (hue - Foundation.floor(hue)) * 6, i = Int(h), f = h - Double(i)
    let p = brightness * (1 - saturation), q = brightness * (1 - saturation * f), t = brightness * (1 - saturation * (1 - f))
    let rgb: (Double, Double, Double)
    switch i % 6 {
    case 0: rgb = (brightness, t, p)
    case 1: rgb = (q, brightness, p)
    case 2: rgb = (p, brightness, t)
    case 3: rgb = (p, q, brightness)
    case 4: rgb = (t, p, brightness)
    default: rgb = (brightness, p, q)
    }
    self.init(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2, opacity: opacity)
  }
  public init(_ resolved: Resolved) { provider = _RGBColorBox(resolved) }
  public init(nsColor: NSColor) { provider = _NSColorBox(nsColor) }
  public init(_ nsColor: NSColor) { self.init(nsColor: nsColor) }
  public init(cgColor: CGColor) { provider = _RGBColorBox(Resolved(cgColor: cgColor)) }
  /// A named colour from the asset catalogue; without one, a neutral grey.
  public init(_ name: String, bundle: Bundle? = nil) {
    provider = _RGBColorBox(Resolved(red: 0.5, green: 0.5, blue: 0.5), name: name)
  }

  public func resolve(in environment: EnvironmentValues) -> Resolved { return provider.resolve(in: environment) }
  public func opacity(_ opacity: Double) -> Color { return Color(box: _OpacityColorBox(self, opacity)) }
  public func mix(with other: Color, by fraction: Double, in colorSpace: Gradient.ColorSpace = .perceptual) -> Color {
    return Color(box: _MixColorBox(self, other, fraction))
  }
  public var cgColor: CGColor? { return provider.resolve(in: EnvironmentValues()).cgColor }

  public static func == (a: Color, b: Color) -> Bool { return a.provider === b.provider || a.provider.isEqual(to: b.provider) }
  public func hash(into hasher: inout Hasher) { hasher.combine(description) }
  public var description: String { return provider.description }

  static func named(_ n: String, _ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) -> Color {
    return Color(box: _RGBColorBox(Resolved(red: r, green: g, blue: b, opacity: a), name: n))
  }
  public static let black = Color.named("black", 0, 0, 0)
  public static let white = Color.named("white", 1, 1, 1)
  public static let gray = Color.named("gray", 0.557, 0.557, 0.576)
  public static let red = Color.named("red", 1, 0.231, 0.188)
  public static let orange = Color.named("orange", 1, 0.584, 0)
  public static let yellow = Color.named("yellow", 1, 0.8, 0)
  public static let green = Color.named("green", 0.204, 0.78, 0.349)
  public static let mint = Color.named("mint", 0, 0.78, 0.745)
  public static let teal = Color.named("teal", 0.188, 0.69, 0.78)
  public static let cyan = Color.named("cyan", 0.196, 0.678, 0.902)
  public static let blue = Color.named("blue", 0, 0.478, 1)
  public static let indigo = Color.named("indigo", 0.345, 0.337, 0.839)
  public static let purple = Color.named("purple", 0.686, 0.322, 0.871)
  public static let pink = Color.named("pink", 1, 0.176, 0.333)
  public static let brown = Color.named("brown", 0.635, 0.518, 0.369)
  public static let clear = Color.named("clear", 0, 0, 0, 0)
  public static let primary = Color(box: _DynamicColorBox("primary", light: Resolved(red: 0, green: 0, blue: 0, opacity: 0.85),
                                                          dark: Resolved(red: 1, green: 1, blue: 1, opacity: 0.85)))
  public static let secondary = Color(box: _DynamicColorBox("secondary", light: Resolved(red: 0, green: 0, blue: 0, opacity: 0.5),
                                                            dark: Resolved(red: 1, green: 1, blue: 1, opacity: 0.55)))
  public static var accentColor: Color { return .blue }
  static let _windowBackground = Color(box: _DynamicColorBox("windowBackground", light: Resolved(red: 0.925, green: 0.925, blue: 0.925),
                                                             dark: Resolved(red: 0.196, green: 0.196, blue: 0.196)))
  static let _controlBackground = Color(box: _DynamicColorBox("controlBackground", light: Resolved(red: 1, green: 1, blue: 1),
                                                              dark: Resolved(red: 0.37, green: 0.37, blue: 0.37)))
}

final class _MixColorBox: AnyColorBox, @unchecked Sendable {
  let a: Color, b: Color, t: Double
  init(_ a: Color, _ b: Color, _ t: Double) {
    self.a = a
    self.b = b
    self.t = t
  }
  override func resolve(in environment: EnvironmentValues) -> Color.Resolved {
    let x = a.provider.resolve(in: environment), y = b.provider.resolve(in: environment)
    let f = Float(t)
    return Color.Resolved(colorSpace: .sRGBLinear, red: x.linearRed + (y.linearRed - x.linearRed) * f,
                          green: x.linearGreen + (y.linearGreen - x.linearGreen) * f,
                          blue: x.linearBlue + (y.linearBlue - x.linearBlue) * f,
                          opacity: x.opacity + (y.opacity - x.opacity) * f)
  }
}

extension Color: ShapeStyle {
  public func _apply(to shape: inout _ShapeStyle_Shape) {
    shape.paint = provider.resolve(in: shape.environment).paint
  }
}
extension Color.Resolved: ShapeStyle {
  public func _apply(to shape: inout _ShapeStyle_Shape) { shape.paint = paint }
  public typealias Resolved = Never
}

extension Color: View {
  public typealias Body = Never
  public var body: Never { fatalError("Color has no body") }
  public static func _makeView(view: _GraphValue<Color>, inputs: _ViewInputs) -> _ViewOutputs {
    let c = view.value
    return _ShapeView<Rectangle, Color>._makeView(view: _GraphValue({ _ShapeView(shape: Rectangle(), style: c) }),
                                                  inputs: inputs)
  }
}

extension NSColor {
  public convenience init(_ color: Color) {
    let r = color.resolve(in: EnvironmentValues())
    self.init(srgbRed: CGFloat(r.red), green: CGFloat(r.green), blue: CGFloat(r.blue), alpha: CGFloat(r.opacity))
  }
}

public enum ColorScheme: Hashable, CaseIterable, Sendable {
  case light
  case dark
}

// MARK: - gradients

@frozen
public struct Gradient: Hashable, Sendable {
  @frozen
  public struct Stop: Hashable, Sendable {
    public var color: Color
    public var location: CGFloat
    public init(color: Color, location: CGFloat) {
      self.color = color
      self.location = location
    }
  }
  public var stops: [Stop]
  public init(stops: [Stop]) { self.stops = stops }
  public init(colors: [Color]) {
    let n = colors.count
    stops = colors.enumerated().map { Stop(color: $0.element, location: n > 1 ? CGFloat($0.offset) / CGFloat(n - 1) : 0) }
  }

  public struct ColorSpace: Hashable, Sendable {
    let id: Int
    public static let device = ColorSpace(id: 0)
    public static let perceptual = ColorSpace(id: 1)
  }
}

// MARK: - environment entries

struct _ColorSchemeKey: EnvironmentKey { static let defaultValue = ColorScheme.light }
struct _FontKey: EnvironmentKey { static let defaultValue: Font? = nil }
struct _ForegroundStyleKey: EnvironmentKey { static let defaultValue: AnyShapeStyle? = nil }
struct _BackgroundStyleKey: EnvironmentKey { static let defaultValue: AnyShapeStyle? = nil }
struct _TintKey: EnvironmentKey { static let defaultValue: AnyShapeStyle? = nil }
struct _ImageScaleKey: EnvironmentKey { static let defaultValue = Image.Scale.medium }
struct _TruncationModeKey: EnvironmentKey { static let defaultValue = Text.TruncationMode.tail }
struct _IsEnabledKey: EnvironmentKey { static let defaultValue = true }
struct _LineLimitKey: EnvironmentKey { static let defaultValue: Int? = nil }
struct _MultilineAlignmentKey: EnvironmentKey { static let defaultValue = TextAlignment.leading }

extension EnvironmentValues {
  public var colorScheme: ColorScheme {
    get { return self[_ColorSchemeKey.self] }
    set { self[_ColorSchemeKey.self] = newValue }
  }
  public var font: Font? {
    get { return self[_FontKey.self] }
    set { self[_FontKey.self] = newValue }
  }
  internal var _foregroundStyle: AnyShapeStyle? {
    get { return self[_ForegroundStyleKey.self] }
    set { self[_ForegroundStyleKey.self] = newValue }
  }
  internal var _backgroundStyle: AnyShapeStyle? {
    get { return self[_BackgroundStyleKey.self] }
    set { self[_BackgroundStyleKey.self] = newValue }
  }
  public var backgroundStyle: AnyShapeStyle? {
    get { return _backgroundStyle }
    set { _backgroundStyle = newValue }
  }
  public var tint: AnyShapeStyle? {
    get { return self[_TintKey.self] }
    set { self[_TintKey.self] = newValue }
  }
  public var tintColor: Color? {
    get { return nil }
    set { tint = newValue.map { AnyShapeStyle($0) } }
  }
  public var imageScale: Image.Scale {
    get { return self[_ImageScaleKey.self] }
    set { self[_ImageScaleKey.self] = newValue }
  }
  public var truncationMode: Text.TruncationMode {
    get { return self[_TruncationModeKey.self] }
    set { self[_TruncationModeKey.self] = newValue }
  }
  public var isEnabled: Bool {
    get { return self[_IsEnabledKey.self] }
    set { self[_IsEnabledKey.self] = newValue }
  }
  public var lineLimit: Int? {
    get { return self[_LineLimitKey.self] }
    set { self[_LineLimitKey.self] = newValue }
  }
  public var multilineTextAlignment: TextAlignment {
    get { return self[_MultilineAlignmentKey.self] }
    set { self[_MultilineAlignmentKey.self] = newValue }
  }
}

public enum TextAlignment: Hashable, CaseIterable, Sendable {
  case leading, center, trailing
}

// MARK: - environment-writing modifiers

/// Modifiers that change the environment of their content.
internal protocol _EnvironmentModifier: ViewModifier where Body == Never {
  func _modify(_ environment: inout EnvironmentValues)
}
extension _EnvironmentModifier {
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    var i = inputs
    modifier.value._modify(&i.environment)
    return body(_Graph(), i)
  }
  public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs,
                                   body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
    var i = inputs
    modifier.value._modify(&i.base.environment)
    return body(_Graph(), i)
  }
  public func body(content: Content) -> Never { fatalError("no body") }
}

@frozen
public struct _EnvironmentKeyWritingModifier<Value>: _EnvironmentModifier {
  public var keyPath: WritableKeyPath<EnvironmentValues, Value>
  public var value: Value
  @inlinable public init(keyPath: WritableKeyPath<EnvironmentValues, Value>, value: Value) {
    self.keyPath = keyPath
    self.value = value
  }
  func _modify(_ environment: inout EnvironmentValues) { environment[keyPath: keyPath] = value }
}

@frozen
public struct _EnvironmentKeyTransformModifier<Value>: _EnvironmentModifier {
  public var keyPath: WritableKeyPath<EnvironmentValues, Value>
  public var transform: (inout Value) -> ()
  @inlinable public init(keyPath: WritableKeyPath<EnvironmentValues, Value>, transform: @escaping (inout Value) -> ()) {
    self.keyPath = keyPath
    self.transform = transform
  }
  func _modify(_ environment: inout EnvironmentValues) { transform(&environment[keyPath: keyPath]) }
}

@frozen
public struct _ForegroundStyleModifier<Style: ShapeStyle>: _EnvironmentModifier {
  public var style: Style
  @inlinable public init(style: Style) { self.style = style }
  func _modify(_ environment: inout EnvironmentValues) { environment._foregroundStyle = AnyShapeStyle(style) }
}
@frozen
public struct _ForegroundStyleModifier2<S1: ShapeStyle, S2: ShapeStyle>: _EnvironmentModifier {
  public var primary: S1
  public var secondary: S2
  @inlinable public init(primary: S1, secondary: S2) {
    self.primary = primary
    self.secondary = secondary
  }
  func _modify(_ environment: inout EnvironmentValues) { environment._foregroundStyle = AnyShapeStyle(primary) }
}
@frozen
public struct _ForegroundStyleModifier3<S1: ShapeStyle, S2: ShapeStyle, S3: ShapeStyle>: _EnvironmentModifier {
  public var primary: S1
  public var secondary: S2
  public var tertiary: S3
  @inlinable public init(primary: S1, secondary: S2, tertiary: S3) {
    self.primary = primary
    self.secondary = secondary
    self.tertiary = tertiary
  }
  func _modify(_ environment: inout EnvironmentValues) { environment._foregroundStyle = AnyShapeStyle(primary) }
}

@frozen
public struct _BackgroundStyleModifier<Style: ShapeStyle>: _NodeModifier {
  public var style: Style
  public var ignoresSafeAreaEdges: Edge.Set
  @inlinable public init(style: Style, ignoresSafeAreaEdges: Edge.Set) {
    self.style = style
    self.ignoresSafeAreaEdges = ignoresSafeAreaEdges
  }
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode {
    let fill = _ShapeNode(shape: Rectangle(), paint: style._paint(in: environment), eoFill: false, stroke: nil,
                          environment: environment)
    return _LayeredNode(primary: content, layer: fill, alignment: .center, behind: true, environment: environment)
  }
}

@frozen
public struct _EnvironmentBackgroundStyleModifier<Style: ShapeStyle>: _EnvironmentModifier {
  public var style: Style
  @inlinable public init(style: Style) { self.style = style }
  func _modify(_ environment: inout EnvironmentValues) { environment._backgroundStyle = AnyShapeStyle(style) }
}

@frozen
public struct _BackgroundModifier<Background: View>: ViewModifier {
  public var background: Background
  public var alignment: Alignment
  @inlinable public init(background: Background, alignment: Alignment = .center) {
    self.background = background
    self.alignment = alignment
  }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let m = modifier.value
    let content = body(_Graph(), inputs).node
    let layer = _makeNode(m.background, inputs: inputs.named("bg"))
    return _ViewOutputs(_LayeredNode(primary: content, layer: layer, alignment: m.alignment, behind: true,
                                     environment: inputs.environment))
  }
  public func body(content: Content) -> Never { fatalError("no body") }
  public typealias Body = Never
}

@frozen
public struct _OverlayModifier<Overlay: View>: ViewModifier {
  public var overlay: Overlay
  public var alignment: Alignment
  @inlinable public init(overlay: Overlay, alignment: Alignment = .center) {
    self.overlay = overlay
    self.alignment = alignment
  }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let m = modifier.value
    let content = body(_Graph(), inputs).node
    let layer = _makeNode(m.overlay, inputs: inputs.named("ov"))
    return _ViewOutputs(_LayeredNode(primary: content, layer: layer, alignment: m.alignment, behind: false,
                                     environment: inputs.environment))
  }
  public func body(content: Content) -> Never { fatalError("no body") }
  public typealias Body = Never
}

/// Content with a background or overlay laid out in the content's frame.
internal final class _LayeredNode: _ViewNode {
  let alignment: Alignment
  let behind: Bool
  init(primary: _ViewNode, layer: _ViewNode, alignment: Alignment, behind: Bool, environment: EnvironmentValues) {
    self.alignment = alignment
    self.behind = behind
    super.init(environment: environment, children: [primary, layer])
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { return children[0].sizeThatFits(proposal) }
  override func place(in rect: CGRect) {
    frame = rect
    children[0].place(in: rect)
    let s = children[1].sizeThatFits(ProposedViewSize(rect.size))
    children[1].place(in: CGRect(origin: alignment.origin(of: s, in: rect), size: s))
  }
  override func draw(_ context: CGContext) {
    if behind {
      children[1].draw(context)
      children[0].draw(context)
    } else {
      children[0].draw(context)
      children[1].draw(context)
    }
  }
  override func hit(_ point: CGPoint) -> _ViewNode? {
    guard frame._contains(point) else { return nil }
    if behind { return children[0].hit(point) ?? children[1].hit(point) }
    return children[1].hit(point) ?? children[0].hit(point)
  }
}

extension View {
  @inlinable public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
    return modifier(_EnvironmentKeyWritingModifier(keyPath: keyPath, value: value))
  }
  @inlinable public func transformEnvironment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>,
                                                 transform: @escaping (inout V) -> Void) -> some View {
    return modifier(_EnvironmentKeyTransformModifier(keyPath: keyPath, transform: transform))
  }
  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View {
    return modifier(_ForegroundStyleModifier(style: style))
  }
  public func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle>(_ primary: S1, _ secondary: S2) -> some View {
    return modifier(_ForegroundStyleModifier2(primary: primary, secondary: secondary))
  }
  public func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle, S3: ShapeStyle>(_ primary: S1, _ secondary: S2,
                                                                              _ tertiary: S3) -> some View {
    return modifier(_ForegroundStyleModifier3(primary: primary, secondary: secondary, tertiary: tertiary))
  }
  public func foregroundColor(_ color: Color?) -> some View {
    return modifier(_EnvironmentKeyWritingModifier(keyPath: \._foregroundStyle, value: color.map { AnyShapeStyle($0) }))
  }
  public func tint<S: ShapeStyle>(_ tint: S?) -> some View {
    return modifier(_EnvironmentKeyWritingModifier(keyPath: \.tint, value: tint.map { AnyShapeStyle($0) }))
  }
  public func tint(_ tint: Color?) -> some View {
    return modifier(_EnvironmentKeyWritingModifier(keyPath: \.tint, value: tint.map { AnyShapeStyle($0) }))
  }
  public func font(_ font: Font?) -> some View {
    return environment(\.font, font)
  }
  public func fontWeight(_ weight: Font.Weight?) -> some View {
    return transformEnvironment(\.font) { f in if let w = weight { f = (f ?? .body).weight(w) } }
  }
  public func bold(_ isActive: Bool = true) -> some View {
    return fontWeight(isActive ? .bold : nil)
  }
  public func monospaced(_ isActive: Bool = true) -> some View {
    return transformEnvironment(\.font) { f in if isActive { f = (f ?? .body).monospaced() } }
  }
  public func colorScheme(_ colorScheme: ColorScheme) -> some View {
    return environment(\.colorScheme, colorScheme)
  }
  public func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View {
    return transformEnvironment(\.colorScheme) { c in if let s = colorScheme { c = s } }
  }
  public func disabled(_ disabled: Bool) -> some View {
    return transformEnvironment(\.isEnabled) { e in if disabled { e = false } }
  }
  public func lineLimit(_ number: Int?) -> some View {
    return environment(\.lineLimit, number)
  }
  public func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
    return environment(\.multilineTextAlignment, alignment)
  }
  public func truncationMode(_ mode: Text.TruncationMode) -> some View {
    return environment(\.truncationMode, mode)
  }
  public func imageScale(_ scale: Image.Scale) -> some View {
    return environment(\.imageScale, scale)
  }

  public func background<S: ShapeStyle>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
    return modifier(_BackgroundStyleModifier(style: style, ignoresSafeAreaEdges: edges))
  }
  public func background(ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
    return modifier(_BackgroundStyleModifier(style: BackgroundStyle(), ignoresSafeAreaEdges: edges))
  }
  public func background<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View {
    return modifier(_BackgroundModifier(background: content(), alignment: alignment))
  }
  public func background<S: ShapeStyle, T: Shape>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
    return modifier(_BackgroundModifier(background: shape.fill(style, style: fillStyle), alignment: .center))
  }
  public func background<T: Shape>(in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
    return modifier(_BackgroundModifier(background: shape.fill(BackgroundStyle(), style: fillStyle), alignment: .center))
  }
  public func backgroundStyle<S: ShapeStyle>(_ style: S) -> some View {
    return modifier(_EnvironmentBackgroundStyleModifier(style: style))
  }
  public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View {
    return modifier(_OverlayModifier(overlay: content(), alignment: alignment))
  }
  public func overlay<S: ShapeStyle>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
    return modifier(_OverlayModifier(overlay: Rectangle().fill(style), alignment: .center))
  }
  public func overlay<S: ShapeStyle, T: Shape>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
    return modifier(_OverlayModifier(overlay: shape.fill(style, style: fillStyle), alignment: .center))
  }
}

// MARK: - Font

@usableFromInline
internal class AnyFontBox: @unchecked Sendable {
  var size: CGFloat { return 13 }
  var weight: Font.Weight { return .regular }
  var design: Font.Design { return .default }
  var italic: Bool { return false }
  func isEqual(to other: AnyFontBox) -> Bool { return self === other }
}

final class _FontBox: AnyFontBox, @unchecked Sendable {
  let s: CGFloat, w: Font.Weight, d: Font.Design, i: Bool
  init(size: CGFloat, weight: Font.Weight, design: Font.Design, italic: Bool = false) {
    s = size
    w = weight
    d = design
    i = italic
  }
  override var size: CGFloat { return s }
  override var weight: Font.Weight { return w }
  override var design: Font.Design { return d }
  override var italic: Bool { return i }
  override func isEqual(to other: AnyFontBox) -> Bool {
    guard let o = other as? _FontBox else { return false }
    return o.s == s && o.w == w && o.d == d && o.i == i
  }
}

@frozen
public struct Font: Hashable, Sendable {
  @usableFromInline internal let provider: AnyFontBox
  internal init(provider: AnyFontBox) { self.provider = provider }

  @frozen
  public struct Weight: Hashable, Sendable {
    @usableFromInline internal var value: CGFloat
    @usableFromInline internal init(value: CGFloat) { self.value = value }
    public static let ultraLight = Weight(value: -0.8)
    public static let thin = Weight(value: -0.6)
    public static let light = Weight(value: -0.4)
    public static let regular = Weight(value: 0)
    public static let medium = Weight(value: 0.23)
    public static let semibold = Weight(value: 0.3)
    public static let bold = Weight(value: 0.4)
    public static let heavy = Weight(value: 0.56)
    public static let black = Weight(value: 0.62)
  }

  public enum Design: Hashable, Sendable {
    case `default`
    case serif
    case rounded
    case monospaced
  }

  public enum TextStyle: Hashable, CaseIterable, Sendable {
    case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2
    /// macOS point sizes.
    var size: CGFloat {
      switch self {
      case .largeTitle: return 26
      case .title: return 22
      case .title2: return 17
      case .title3: return 15
      case .headline, .body: return 13
      case .subheadline: return 11
      case .callout: return 12
      case .footnote, .caption, .caption2: return 10
      }
    }
    var weight: Weight { return self == .headline ? .bold : .regular }
  }

  public static func system(_ style: TextStyle, design: Design? = nil, weight: Weight? = nil) -> Font {
    return Font(provider: _FontBox(size: style.size, weight: weight ?? style.weight, design: design ?? .default))
  }
  @_disfavoredOverload
  public static func system(_ style: TextStyle, design: Design = .default) -> Font {
    return system(style, design: design, weight: nil)
  }
  public static func system(size: CGFloat, weight: Weight? = nil, design: Design? = nil) -> Font {
    return Font(provider: _FontBox(size: size, weight: weight ?? .regular, design: design ?? .default))
  }
  @_disfavoredOverload
  public static func system(size: CGFloat, weight: Weight = .regular, design: Design = .default) -> Font {
    return system(size: size, weight: Optional(weight), design: Optional(design))
  }
  public static func custom(_ name: String, size: CGFloat) -> Font {
    return Font(provider: _FontBox(size: size, weight: .regular, design: .default))
  }
  public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: TextStyle) -> Font {
    return custom(name, size: size)
  }
  public static func custom(_ name: String, fixedSize: CGFloat) -> Font { return custom(name, size: fixedSize) }
  public init(_ font: CTFont) {
    provider = _FontBox(size: CTFontGetSize(font), weight: .regular, design: .default)
  }
  public init(_ font: NSFont) {
    provider = _FontBox(size: font.pointSize, weight: .regular, design: .default)
  }

  public static let largeTitle = Font.system(.largeTitle)
  public static let title = Font.system(.title)
  public static let title2 = Font.system(.title2)
  public static let title3 = Font.system(.title3)
  public static let headline = Font.system(.headline)
  public static let subheadline = Font.system(.subheadline)
  public static let body = Font.system(.body)
  public static let callout = Font.system(.callout)
  public static let footnote = Font.system(.footnote)
  public static let caption = Font.system(.caption)
  public static let caption2 = Font.system(.caption2)

  private func with(size: CGFloat? = nil, weight: Weight? = nil, design: Design? = nil, italic: Bool? = nil) -> Font {
    let p = provider
    return Font(provider: _FontBox(size: size ?? p.size, weight: weight ?? p.weight, design: design ?? p.design,
                                   italic: italic ?? p.italic))
  }
  public func weight(_ weight: Weight) -> Font { return with(weight: weight) }
  public func bold() -> Font { return with(weight: .bold) }
  public func italic() -> Font { return with(italic: true) }
  public func monospaced() -> Font { return with(design: .monospaced) }
  public func monospacedDigit() -> Font { return self }
  public func smallCaps() -> Font { return self }
  public func leading(_ leading: Font.Leading) -> Font { return self }
  public enum Leading: Hashable, Sendable { case standard, tight, loose }

  public static func == (a: Font, b: Font) -> Bool { return a.provider === b.provider || a.provider.isEqual(to: b.provider) }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(provider.size)
    hasher.combine(provider.weight)
  }
  internal var _size: CGFloat { return provider.size }
}

// MARK: - Text

@usableFromInline
internal class AnyTextStorage: @unchecked Sendable {
  func resolve() -> String { return "" }
  func isEqual(to other: AnyTextStorage) -> Bool { return self === other }
}
final class _ConcatenatedTextStorage: AnyTextStorage, @unchecked Sendable {
  let first: Text, second: Text
  init(_ a: Text, _ b: Text) {
    first = a
    second = b
  }
  override func resolve() -> String { return first._string + second._string }
}
final class _LocalizedTextStorage: AnyTextStorage, @unchecked Sendable {
  let key: LocalizedStringKey, table: String?, bundle: Bundle?
  init(_ key: LocalizedStringKey, table: String?, bundle: Bundle?) {
    self.key = key
    self.table = table
    self.bundle = bundle
  }
  override func resolve() -> String {
    let b = bundle ?? Bundle.main
    let fmt = b.localizedString(forKey: key.key, value: key.key, table: table)
    return key.format(fmt)
  }
}
@usableFromInline
internal class AnyTextModifier: @unchecked Sendable {}

@frozen
public struct Text: Equatable, Sendable {
  @usableFromInline @frozen
  internal enum Storage: Equatable, @unchecked Sendable {
    case verbatim(String)
    case anyTextStorage(AnyTextStorage)
    @usableFromInline static func == (a: Storage, b: Storage) -> Bool {
      switch (a, b) {
      case (.verbatim(let x), .verbatim(let y)): return x == y
      case (.anyTextStorage(let x), .anyTextStorage(let y)): return x.isEqual(to: y)
      default: return false
      }
    }
  }
  @usableFromInline @frozen
  internal enum Modifier: Equatable, @unchecked Sendable {
    case color(Color?)
    case font(Font?)
    case italic
    case weight(Font.Weight?)
    case kerning(CGFloat)
    case tracking(CGFloat)
    case baseline(CGFloat)
    case rounded
    case anyTextModifier(AnyTextModifier)
    @usableFromInline static func == (a: Modifier, b: Modifier) -> Bool {
      switch (a, b) {
      case (.color(let x), .color(let y)): return x == y
      case (.font(let x), .font(let y)): return x == y
      case (.italic, .italic), (.rounded, .rounded): return true
      case (.weight(let x), .weight(let y)): return x == y
      case (.kerning(let x), .kerning(let y)), (.tracking(let x), .tracking(let y)), (.baseline(let x), .baseline(let y)):
        return x == y
      case (.anyTextModifier(let x), .anyTextModifier(let y)): return x === y
      default: return false
      }
    }
  }
  @usableFromInline internal var storage: Storage
  @usableFromInline internal var modifiers: [Modifier] = [Modifier]()

  public init(verbatim content: String) { storage = .verbatim(content) }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ content: S) { storage = .verbatim(String(content)) }
  public init(_ key: LocalizedStringKey, tableName: String? = nil, bundle: Bundle? = nil, comment: StaticString? = nil) {
    storage = .anyTextStorage(_LocalizedTextStorage(key, table: tableName, bundle: bundle))
  }
  public init(_ date: Date, style: DateStyle) { storage = .verbatim(style.format(date)) }

  public struct DateStyle: Sendable {
    let format: @Sendable (Date) -> String
    public static let time = DateStyle { d in d.description }
    public static let date = DateStyle { d in d.description }
    public static let relative = DateStyle { d in "\(Int(-d.timeIntervalSinceNow)) s" }
    public static let offset = relative
    public static let timer = relative
  }

  public enum TruncationMode: Hashable, Sendable {
    case head, tail, middle
  }
  public enum Case: Hashable, Sendable {
    case uppercase, lowercase
  }

  internal var _string: String {
    switch storage {
    case .verbatim(let s): return s
    case .anyTextStorage(let s): return s.resolve()
    }
  }

  private func adding(_ m: Modifier) -> Text {
    var t = self
    t.modifiers.append(m)
    return t
  }
  public func foregroundColor(_ color: Color?) -> Text { return adding(.color(color)) }
  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text {
    if let c = style as? Color { return adding(.color(c)) }
    return self
  }
  public func font(_ font: Font?) -> Text { return adding(.font(font)) }
  public func fontWeight(_ weight: Font.Weight?) -> Text { return adding(.weight(weight)) }
  public func bold() -> Text { return adding(.weight(.bold)) }
  public func bold(_ isActive: Bool) -> Text { return isActive ? bold() : self }
  public func italic() -> Text { return adding(.italic) }
  public func italic(_ isActive: Bool) -> Text { return isActive ? italic() : self }
  public func monospaced(_ isActive: Bool = true) -> Text { return isActive ? adding(.font(.body.monospaced())) : self }
  public func monospacedDigit() -> Text { return self }
  public func kerning(_ kerning: CGFloat) -> Text { return adding(.kerning(kerning)) }
  public func tracking(_ tracking: CGFloat) -> Text { return adding(.tracking(tracking)) }
  public func baselineOffset(_ offset: CGFloat) -> Text { return adding(.baseline(offset)) }
  public func underline(_ isActive: Bool = true, color: Color? = nil) -> Text { return self }
  public func strikethrough(_ isActive: Bool = true, color: Color? = nil) -> Text { return self }
  public func textCase(_ c: Case?) -> Text {
    switch c {
    case .uppercase?: return Text(verbatim: _string.uppercased())._with(modifiers)
    case .lowercase?: return Text(verbatim: _string.lowercased())._with(modifiers)
    case nil: return self
    }
  }
  public func accessibilityLabel(_ label: LocalizedStringKey) -> Text { return self }
  public func accessibilityLabel<S: StringProtocol>(_ label: S) -> Text { return self }
  private func _with(_ m: [Modifier]) -> Text {
    var t = self
    t.modifiers = m
    return t
  }

  public static func + (a: Text, b: Text) -> Text {
    return Text(storage: .anyTextStorage(_ConcatenatedTextStorage(a, b)))
  }
  private init(storage: Storage) { self.storage = storage }

  /// The font and colour this text draws with in `environment`.
  internal func _attributes(in environment: EnvironmentValues) -> (Font, _Paint?) {
    var font = environment.font ?? .body
    var paint: _Paint? = nil
    for m in modifiers {
      switch m {
      case .font(let f?): font = f
      case .weight(let w?): font = font.weight(w)
      case .italic: font = font.italic()
      case .color(let c?): paint = c.resolve(in: environment).paint
      default: break
      }
    }
    return (font, paint)
  }
}

extension Text: View {
  public typealias Body = Never
  public var body: Never { fatalError("Text has no body") }
  public static func _makeView(view: _GraphValue<Text>, inputs: _ViewInputs) -> _ViewOutputs {
    let t = view.value
    let (font, paint) = t._attributes(in: inputs.environment)
    let p = paint ?? ForegroundStyle()._paint(in: inputs.environment)
    return _ViewOutputs(_TextNode(string: t._string, font: font, paint: p, environment: inputs.environment))
  }
}

@frozen
public struct LocalizedStringKey: Equatable, ExpressibleByStringInterpolation, Sendable {
  @usableFromInline internal var key: String
  @usableFromInline internal var hasFormatting: Bool = false
  @usableFromInline internal var arguments: [String] = []

  public init(_ value: String) { key = value }
  public init(stringLiteral value: String) { key = value }

  public struct StringInterpolation: StringInterpolationProtocol {
    var key: String
    var arguments: [String]
    public init(literalCapacity: Int, interpolationCount: Int) {
      key = ""
      arguments = []
    }
    public mutating func appendLiteral(_ literal: String) { key += literal.replacingOccurrences(of: "%", with: "%%") }
    public mutating func appendInterpolation(_ string: String) {
      key += "%@"
      arguments.append(string)
    }
    public mutating func appendInterpolation<T>(_ value: T) where T: _FormatSpecifiable {
      key += value._specifier
      arguments.append("\(value)")
    }
    public mutating func appendInterpolation<T>(_ value: T, specifier: String) where T: _FormatSpecifiable {
      key += "%@"
      arguments.append(String(format: specifier, value._arg))
    }
    public mutating func appendInterpolation(_ text: Text) {
      key += "%@"
      arguments.append(text._string)
    }
    public mutating func appendInterpolation(_ image: Image) {}
  }
  public init(stringInterpolation: StringInterpolation) {
    key = stringInterpolation.key
    arguments = stringInterpolation.arguments
    hasFormatting = true
  }

  /// Fills a (possibly localised) format with the interpolated values.
  internal func format(_ fmt: String) -> String {
    guard hasFormatting else { return fmt }
    var out = ""
    var args = arguments.makeIterator()
    var it = fmt.makeIterator()
    while let c = it.next() {
      if c != "%" {
        out.append(c)
        continue
      }
      // Skip to the conversion character.
      var spec = ""
      while let d = it.next() {
        spec.append(d)
        if d.isLetter || d == "@" || d == "%" { break }
      }
      if spec == "%" { out.append("%") } else { out += args.next() ?? "" }
    }
    return out
  }
}

// _FormatSpecifiable and its conformances are Foundation's (as on Apple's
// systems): frameworks/Foundation/swift/LocalizedStringResource.swift.

/// Text layout without glyph outlines: each character is a fixed fraction
/// of the point size wide. Drawing goes through CoreText when the target
/// has it (see _TextRenderer).
internal final class _TextNode: _ViewNode {
  let string: String
  let font: Font
  let paint: _Paint
  init(string: String, font: Font, paint: _Paint, environment: EnvironmentValues) {
    self.string = string
    self.font = font
    self.paint = paint
    super.init(environment: environment)
  }
  var lineHeight: CGFloat { return _TextRenderer.metrics(font).lineHeight }
  func width(of s: Substring) -> CGFloat { return _TextRenderer.width(String(s), font: font) }
  /// Greedy word wrapping into `width`.
  func lines(in width: CGFloat?) -> [Substring] {
    var out: [Substring] = []
    for para in string.split(separator: "\n", omittingEmptySubsequences: false) {
      guard let w = width, self.width(of: para) > w else {
        out.append(para)
        continue
      }
      var line = para[para.startIndex..<para.startIndex]
      for word in para.split(separator: " ", omittingEmptySubsequences: false) {
        let candidate = line.isEmpty ? word : para[line.startIndex..<word.endIndex]
        if self.width(of: candidate) <= w || line.isEmpty {
          line = candidate
        } else {
          out.append(line)
          line = word
        }
      }
      out.append(line)
    }
    if let limit = environment.lineLimit, out.count > limit { out = Array(out.prefix(max(1, limit))) }
    return out
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    if string.isEmpty { return ._zero }
    let ls = lines(in: proposal.width)
    let w = ls.reduce(0) { max($0, width(of: $1)) }
    return CGSize(width: proposal.width.map { min($0, w) } ?? w, height: CGFloat(ls.count) * lineHeight)
  }
  override func draw(_ context: CGContext) {
    var y = frame._minY
    for line in lines(in: frame._width + 0.5) {
      _TextRenderer.draw(String(line), font: font, paint: paint, at: CGPoint(x: frame._minX, y: y),
                         lineHeight: lineHeight, in: context)
      y += lineHeight
    }
  }
}

/// Text through CoreText: SwiftUI fonts become CoreText fonts by name
/// (the system font and its weights, Menlo for monospaced), and lines are
/// measured and drawn as CTLines.
internal enum _TextRenderer {
  struct Metrics {
    let ascent: CGFloat, descent: CGFloat, leading: CGFloat
    var lineHeight: CGFloat { return (ascent + descent + leading).rounded(.up) }
  }
  nonisolated(unsafe) static var fonts: [String: CTFont] = [:]
  nonisolated(unsafe) static var widths: [String: CGFloat] = [:]
  nonisolated(unsafe) static var metricsCache: [String: Metrics] = [:]

  static func name(_ font: Font) -> String {
    let w = font.provider.weight.value
    let bold = w >= 0.35, semibold = w >= 0.2 && w < 0.35, light = w <= -0.3
    switch font.provider.design {
    case .monospaced: return bold || semibold ? "Menlo-Bold" : "Menlo-Regular"
    case .serif: return bold || semibold ? "Times-Bold" : "Times-Roman"
    default:
      return ".AppleSystemUIFont" + (bold ? "-Bold" : semibold ? "-Semibold" : light ? "-Light" : "")
    }
  }
  static func cfString(_ s: String) -> CFString {
    return CFStringCreateWithCString(nil, s, CFStringEncoding(kCFStringEncodingUTF8)) ??
      CFStringCreateWithCString(nil, "", CFStringEncoding(kCFStringEncodingUTF8))!
  }
  static func ctFont(_ font: Font) -> CTFont {
    let key = name(font) + "@\(font._size)"
    if let f = fonts[key] { return f }
    let f = CTFontCreateWithName(cfString(name(font)), font._size, nil)
    fonts[key] = f
    return f
  }
  static func line(_ s: String, font: Font, color: CGColor?) -> CTLine {
    var keys: [UnsafeRawPointer?] = [UnsafeRawPointer(Unmanaged.passUnretained(kCTFontAttributeName).toOpaque())]
    var values: [UnsafeRawPointer?] = [UnsafeRawPointer(Unmanaged.passUnretained(ctFont(font)).toOpaque())]
    if let c = color {
      keys.append(UnsafeRawPointer(Unmanaged.passUnretained(kCTForegroundColorAttributeName).toOpaque()))
      values.append(UnsafeRawPointer(Unmanaged.passUnretained(c).toOpaque()))
    }
    let n = keys.count
    let dict = keys.withUnsafeMutableBufferPointer { k in
      values.withUnsafeMutableBufferPointer { v in
        withUnsafePointer(to: kCFTypeDictionaryKeyCallBacks) { kcb in
          withUnsafePointer(to: kCFTypeDictionaryValueCallBacks) { vcb in
            CFDictionaryCreate(nil, k.baseAddress, v.baseAddress, n, kcb, vcb)
          }
        }
      }
    }
    let attributed = CFAttributedStringCreate(nil, cfString(s), dict)!
    return CTLineCreateWithAttributedString(attributed)
  }
  static func metrics(_ font: Font) -> Metrics {
    let key = name(font) + "@\(font._size)"
    if let m = metricsCache[key] { return m }
    var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
    _ = CTLineGetTypographicBounds(line("Hg", font: font, color: nil), &a, &d, &l)
    let m = Metrics(ascent: a, descent: d, leading: l)
    metricsCache[key] = m
    return m
  }
  static func width(_ s: String, font: Font) -> CGFloat {
    if s.isEmpty { return 0 }
    let key = name(font) + "@\(font._size)|" + s
    if let w = widths[key] { return w }
    let w = CGFloat(CTLineGetTypographicBounds(line(s, font: font, color: nil), nil, nil, nil)).rounded(.up)
    if widths.count > 4096 { widths.removeAll() }
    widths[key] = w
    return w
  }
  /// Draws `s` with its top-left at `p` in a flipped context.
  static func draw(_ s: String, font: Font, paint: _Paint, at p: CGPoint, lineHeight: CGFloat, in context: CGContext) {
    guard !s.isEmpty, paint.a > 0 else { return }
    let color = CGColorCreateSRGB(paint.r, paint.g, paint.b, paint.a)
    let l = line(s, font: font, color: color)
    let m = metrics(font)
    CGContextSaveGState(context)
    CGContextSetTextMatrix(context, CGAffineTransformMake(1, 0, 0, -1, 0, 0))
    CGContextSetTextPosition(context, p.x, p.y + m.ascent + m.leading / 2)
    CTLineDraw(l, context)
    CGContextRestoreGState(context)
  }
}

// MARK: - Image

@usableFromInline
internal class AnyImageProviderBox: @unchecked Sendable {
  var size: CGSize { return CGSize(width: 16, height: 16) }
  var resizable = false
  var name: String { return "" }
  func isEqual(to other: AnyImageProviderBox) -> Bool { return self === other }
  func copy() -> AnyImageProviderBox { return self }
}

final class _NamedImageBox: AnyImageProviderBox, @unchecked Sendable {
  let n: String
  let system: Bool
  init(_ n: String, system: Bool) {
    self.n = n
    self.system = system
  }
  override var name: String { return n }
  override func isEqual(to other: AnyImageProviderBox) -> Bool {
    guard let o = other as? _NamedImageBox else { return false }
    return o.n == n && o.system == system && o.resizable == resizable
  }
  override func copy() -> AnyImageProviderBox {
    let c = _NamedImageBox(n, system: system)
    c.resizable = resizable
    return c
  }
}

final class _CGImageBox: AnyImageProviderBox, @unchecked Sendable {
  let image: CGImage
  let scale: CGFloat
  init(_ image: CGImage, scale: CGFloat) {
    self.image = image
    self.scale = scale
  }
  override var size: CGSize {
    return CGSize(width: CGFloat(CGImageGetWidth(image)) / scale, height: CGFloat(CGImageGetHeight(image)) / scale)
  }
  override func copy() -> AnyImageProviderBox {
    let c = _CGImageBox(image, scale: scale)
    c.resizable = resizable
    return c
  }
}

@frozen
public struct Image: Equatable, Sendable {
  @usableFromInline internal var provider: AnyImageProviderBox
  internal init(provider: AnyImageProviderBox) { self.provider = provider }

  public init(_ name: String, bundle: Bundle? = nil) { provider = _NamedImageBox(name, system: false) }
  public init(systemName: String) { provider = _NamedImageBox(systemName, system: true) }
  public init(_ name: String, bundle: Bundle? = nil, label: Text) { self.init(name, bundle: bundle) }
  public init(decorative name: String, bundle: Bundle? = nil) { self.init(name, bundle: bundle) }
  public init(nsImage: NSImage) { provider = _NamedImageBox("nsImage", system: false) }
  public init(_ cgImage: CGImage, scale: CGFloat, orientation: Orientation = .up, label: Text) {
    provider = _CGImageBox(cgImage, scale: scale)
  }
  public init(decorative cgImage: CGImage, scale: CGFloat, orientation: Orientation = .up) {
    provider = _CGImageBox(cgImage, scale: scale)
  }

  public enum Orientation: UInt8, CaseIterable, Hashable, Sendable {
    case up, upMirrored, down, downMirrored, left, leftMirrored, right, rightMirrored
  }
  public enum ResizingMode: Hashable, Sendable { case tile, stretch }
  public enum TemplateRenderingMode: Hashable, Sendable { case template, original }
  public enum Interpolation: Hashable, Sendable { case none, low, medium, high }
  public enum Scale: Hashable, Sendable { case small, medium, large }

  public func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: ResizingMode = .stretch) -> Image {
    let c = provider.copy()
    c.resizable = true
    return Image(provider: c)
  }
  public func renderingMode(_ mode: TemplateRenderingMode?) -> Image { return self }
  public func interpolation(_ interpolation: Interpolation) -> Image { return self }
  public func antialiased(_ isAntialiased: Bool) -> Image { return self }
  public func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> Image { return self }

  public static func == (a: Image, b: Image) -> Bool { return a.provider === b.provider || a.provider.isEqual(to: b.provider) }
}

public struct SymbolRenderingMode: Hashable, Sendable {
  let id: Int
  public static let monochrome = SymbolRenderingMode(id: 0)
  public static let multicolor = SymbolRenderingMode(id: 1)
  public static let hierarchical = SymbolRenderingMode(id: 2)
  public static let palette = SymbolRenderingMode(id: 3)
}

extension Image: View {
  public typealias Body = Never
  public var body: Never { fatalError("Image has no body") }
  public static func _makeView(view: _GraphValue<Image>, inputs: _ViewInputs) -> _ViewOutputs {
    let image = view.value
    return _ViewOutputs(_ImageNode(provider: image.provider, paint: ForegroundStyle()._paint(in: inputs.environment),
                                   environment: inputs.environment))
  }
}

internal final class _ImageNode: _ViewNode {
  let provider: AnyImageProviderBox
  let paint: _Paint
  init(provider: AnyImageProviderBox, paint: _Paint, environment: EnvironmentValues) {
    self.provider = provider
    self.paint = paint
    super.init(environment: environment)
  }
  var symbolSize: CGFloat {
    let base = (environment.font ?? .body)._size * 1.15
    switch environment.imageScale {
    case .small: return base * 0.8
    case .medium: return base
    case .large: return base * 1.3
    }
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    var s = provider.size
    if provider is _NamedImageBox { s = CGSize(width: symbolSize, height: symbolSize) }
    if provider.resizable {
      return CGSize(width: proposal.width ?? s.width, height: proposal.height ?? s.height)
    }
    return s
  }
  override func draw(_ context: CGContext) {
    if let cg = provider as? _CGImageBox {
      // The context is flipped: draw the image upright.
      CGContextSaveGState(context)
      CGContextTranslateCTM(context, frame._minX, frame._maxY)
      CGContextScaleCTM(context, 1, -1)
      CGContextDrawImage(context, CGRect(_x: 0, y: 0, width: frame._width, height: frame._height), cg.image)
      CGContextRestoreGState(context)
      return
    }
    // Symbols and asset images: a rounded placeholder in the foreground colour.
    let inset = frame._insetBy(min(frame._width, frame._height) * 0.15)
    paint.with(opacity: 0.6).fill(CGPathCreateWithRoundedRect(inset, inset._width * 0.25, inset._height * 0.25, nil),
                                  in: context)
  }
}

// MARK: - keys

public struct KeyEquivalent: Hashable, Sendable, ExpressibleByExtendedGraphemeClusterLiteral {
  public var character: Character
  public init(_ character: Character) { self.character = character }
  public init(extendedGraphemeClusterLiteral: Character) { character = extendedGraphemeClusterLiteral }
  public static let upArrow = KeyEquivalent("\u{F700}")
  public static let downArrow = KeyEquivalent("\u{F701}")
  public static let leftArrow = KeyEquivalent("\u{F702}")
  public static let rightArrow = KeyEquivalent("\u{F703}")
  public static let escape = KeyEquivalent("\u{1B}")
  public static let delete = KeyEquivalent("\u{8}")
  public static let deleteForward = KeyEquivalent("\u{F728}")
  public static let home = KeyEquivalent("\u{F729}")
  public static let end = KeyEquivalent("\u{F72B}")
  public static let pageUp = KeyEquivalent("\u{F72C}")
  public static let pageDown = KeyEquivalent("\u{F72D}")
  public static let clear = KeyEquivalent("\u{F739}")
  public static let tab = KeyEquivalent("\t")
  public static let space = KeyEquivalent(" ")
  public static let `return` = KeyEquivalent("\r")
}

@frozen
public struct EventModifiers: OptionSet, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let capsLock = EventModifiers(rawValue: 1)
  public static let shift = EventModifiers(rawValue: 2)
  public static let control = EventModifiers(rawValue: 4)
  public static let option = EventModifiers(rawValue: 8)
  public static let command = EventModifiers(rawValue: 16)
  public static let numericPad = EventModifiers(rawValue: 32)
  public static let function = EventModifiers(rawValue: 64)
  public static let all = EventModifiers(rawValue: 127)
}

public struct KeyboardShortcut: Hashable, Sendable {
  public var key: KeyEquivalent
  public var modifiers: EventModifiers
  public var localization: Localization
  public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) {
    self.key = key
    self.modifiers = modifiers
    localization = .automatic
  }
  public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command, localization: Localization) {
    self.key = key
    self.modifiers = modifiers
    self.localization = localization
  }
  public struct Localization: Hashable, Sendable {
    let id: Int
    public static let automatic = Localization(id: 0)
    public static let withoutMirroring = Localization(id: 1)
    public static let custom = Localization(id: 2)
  }
  public static let defaultAction = KeyboardShortcut(.return, modifiers: [])
  public static let cancelAction = KeyboardShortcut(.escape, modifiers: [])
}

struct _KeyboardShortcutKey: EnvironmentKey { static let defaultValue: KeyboardShortcut? = nil }
extension EnvironmentValues {
  internal var _keyboardShortcut: KeyboardShortcut? {
    get { return self[_KeyboardShortcutKey.self] }
    set { self[_KeyboardShortcutKey.self] = newValue }
  }
}

extension View {
  public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
    return environment(\._keyboardShortcut, KeyboardShortcut(key, modifiers: modifiers))
  }
  public func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View {
    return environment(\._keyboardShortcut, shortcut)
  }
  public func keyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
    return environment(\._keyboardShortcut, shortcut)
  }
}

// MARK: - Button

public struct ButtonRole: Equatable, Sendable {
  let id: Int
  public static let destructive = ButtonRole(id: 0)
  public static let cancel = ButtonRole(id: 1)
}

@MainActor @preconcurrency
public struct Button<Label: View>: View {
  let action: () -> Void
  let label: Label
  let role: ButtonRole?
  public init(action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {
    self.action = action
    self.label = label()
    role = nil
  }
  public init(role: ButtonRole?, action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {
    self.action = action
    self.label = label()
    self.role = role
  }
  public typealias Body = Never
  public var body: Never { fatalError("Button has no body") }
  nonisolated public static func _makeView(view: _GraphValue<Button>, inputs: _ViewInputs) -> _ViewOutputs {
    return MainActor.assumeIsolated {
      let b = view.value
      let labelNode = _makeNode(b.label, inputs: inputs.named("label"))
      let style = inputs.environment._buttonStyle
      return _ViewOutputs(_ButtonNode(label: labelNode, action: b.action, style: style, environment: inputs.environment))
    }
  }
}

extension Button where Label == Text {
  public init(_ titleKey: LocalizedStringKey, action: @escaping @MainActor () -> Void) {
    self.init(action: action) { Text(titleKey) }
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, action: @escaping @MainActor () -> Void) {
    self.init(action: action) { Text(title) }
  }
  public init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
    self.init(role: role, action: action) { Text(titleKey) }
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
    self.init(role: role, action: action) { Text(title) }
  }
}

internal enum _ButtonAppearance { case bordered, borderless, plain, link }
struct _ButtonStyleKey: EnvironmentKey { static let defaultValue = _ButtonAppearance.bordered }
extension EnvironmentValues {
  internal var _buttonStyle: _ButtonAppearance {
    get { return self[_ButtonStyleKey.self] }
    set { self[_ButtonStyleKey.self] = newValue }
  }
}

internal final class _ButtonNode: _ViewNode {
  let action: () -> Void
  /// The label's text, for menus.
  var title: String {
    var out = ""
    func walk(_ n: _ViewNode) {
      if let t = n as? _TextNode { out += t.string; return }
      for c in n.children { walk(c) }
    }
    walk(self)
    return out
  }
  let style: _ButtonAppearance
  init(label: _ViewNode, action: @escaping () -> Void, style: _ButtonAppearance, environment: EnvironmentValues) {
    self.action = action
    self.style = style
    super.init(environment: environment, children: [label])
  }
  var insets: EdgeInsets {
    return style == .bordered ? EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8) : EdgeInsets()
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    let i = insets
    let inner = ProposedViewSize(width: proposal.width.map { max(0, $0 - i.leading - i.trailing) }, height: nil)
    let s = children[0].sizeThatFits(inner)
    return CGSize(width: s.width + i.leading + i.trailing, height: max(s.height + i.top + i.bottom, style == .bordered ? 22 : 0))
  }
  override func place(in rect: CGRect) {
    frame = rect
    let i = insets
    let inner = CGRect(_x: rect._minX + i.leading, y: rect._minY + i.top, width: max(0, rect._width - i.leading - i.trailing),
                       height: max(0, rect._height - i.top - i.bottom))
    let s = children[0].sizeThatFits(ProposedViewSize(inner.size))
    children[0].place(in: CGRect(origin: Alignment.center.origin(of: s, in: inner), size: s))
  }
  override func draw(_ context: CGContext) {
    if style == .bordered {
      let path = CGPathCreateWithRoundedRect(frame, 5, 5, nil)
      Color._controlBackground.resolve(in: environment).paint.fill(path, in: context)
      _Paint(r: 0, g: 0, b: 0, a: 0.15).stroke(CGPathCreateWithRoundedRect(frame._insetBy(0.5), 5, 5, nil), in: context, width: 1)
    }
    super.draw(context)
  }
  override var handlesTaps: Bool { return environment.isEnabled }
  override func tap() {
    let a = action
    let after = environment._afterButtonTap
    MainActor.assumeIsolated { a() }
    after?()
  }
  override func hit(_ point: CGPoint) -> _ViewNode? {
    return frame._contains(point) && handlesTaps ? self : nil
  }
}

public protocol PrimitiveButtonStyle {
  associatedtype Body: View
  @ViewBuilder @MainActor func makeBody(configuration: Self.Configuration) -> Self.Body
  typealias Configuration = PrimitiveButtonStyleConfiguration
}
public struct PrimitiveButtonStyleConfiguration {
  public struct Label: View {
    let node: _ViewNode
    public typealias Body = Never
    public var body: Never { fatalError("no body") }
    public static func _makeView(view: _GraphValue<Label>, inputs: _ViewInputs) -> _ViewOutputs {
      return _ViewOutputs(view.value.node)
    }
  }
  public let role: ButtonRole?
  public let label: Label
  let action: () -> Void
  public func trigger() { action() }
}

public protocol ButtonStyle {
  associatedtype Body: View
  @ViewBuilder @MainActor func makeBody(configuration: Self.Configuration) -> Self.Body
  typealias Configuration = ButtonStyleConfiguration
}
public struct ButtonStyleConfiguration {
  public typealias Label = PrimitiveButtonStyleConfiguration.Label
  public let role: ButtonRole?
  public let label: Label
  public let isPressed: Bool
}

public struct BorderedButtonStyle: PrimitiveButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View { return configuration.label }
}
public struct BorderedProminentButtonStyle: PrimitiveButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View { return configuration.label }
}
public struct BorderlessButtonStyle: PrimitiveButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View { return configuration.label }
}
public struct PlainButtonStyle: PrimitiveButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View { return configuration.label }
}
public struct LinkButtonStyle: PrimitiveButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View { return configuration.label }
}
public struct DefaultButtonStyle: PrimitiveButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View { return configuration.label }
}

extension PrimitiveButtonStyle where Self == BorderedButtonStyle { public static var bordered: BorderedButtonStyle { return .init() } }
extension PrimitiveButtonStyle where Self == BorderedProminentButtonStyle {
  public static var borderedProminent: BorderedProminentButtonStyle { return .init() }
}
extension PrimitiveButtonStyle where Self == BorderlessButtonStyle { public static var borderless: BorderlessButtonStyle { return .init() } }
extension PrimitiveButtonStyle where Self == PlainButtonStyle { public static var plain: PlainButtonStyle { return .init() } }
extension PrimitiveButtonStyle where Self == LinkButtonStyle { public static var link: LinkButtonStyle { return .init() } }
extension PrimitiveButtonStyle where Self == DefaultButtonStyle { public static var automatic: DefaultButtonStyle { return .init() } }

extension View {
  public func buttonStyle<S: PrimitiveButtonStyle>(_ style: S) -> some View {
    let a: _ButtonAppearance
    switch style {
    case is BorderlessButtonStyle: a = .borderless
    case is PlainButtonStyle: a = .plain
    case is LinkButtonStyle: a = .link
    default: a = .bordered
    }
    return environment(\._buttonStyle, a)
  }
  public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
    return environment(\._buttonStyle, .plain)
  }
}

// MARK: - Divider

public struct Divider: View {
  public init() {}
  public typealias Body = Never
  public var body: Never { fatalError("Divider has no body") }
  public static func _makeView(view: _GraphValue<Divider>, inputs: _ViewInputs) -> _ViewOutputs {
    return _ViewOutputs(_DividerNode(environment: inputs.environment))
  }
}

/// A one-point line across the stack it is in (either direction).
internal final class _DividerNode: _ViewNode {
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    // In a vertical stack a divider is offered a width; in a horizontal
    // one, a height.
    if let w = proposal.width, proposal.height == nil { return CGSize(width: w, height: 1) }
    if let h = proposal.height, proposal.width == nil { return CGSize(width: 1, height: h) }
    return CGSize(width: proposal.width ?? 1, height: 1)
  }
  override func draw(_ context: CGContext) {
    _Paint(r: 0, g: 0, b: 0, a: 0.1).fill(CGPathCreateWithRect(frame, nil), in: context)
  }
}
