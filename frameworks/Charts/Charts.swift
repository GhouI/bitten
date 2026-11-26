// Swift Charts over SwiftUI: chart content collects marks (lines, points,
// bars, rules), and Chart lays them out on linear scales and draws them
// with SwiftUI shapes: a series per foreground-style value, colours in
// Apple's default order, axis labels at the edges. Axes hidden with
// chartXAxis(.hidden) are not drawn.
import Foundation
import SwiftUI

// ---- values ------------------------------------------------------------------

public protocol Plottable {
  associatedtype PrimitivePlottable
  var primitivePlottable: PrimitivePlottable { get }
  init?(primitivePlottable: PrimitivePlottable)
}
extension Double: Plottable {
  public var primitivePlottable: Double { return self }
  public init?(primitivePlottable: Double) { self = primitivePlottable }
}
extension Float: Plottable {
  public var primitivePlottable: Double { return Double(self) }
  public init?(primitivePlottable: Double) { self = Float(primitivePlottable) }
}
extension Int: Plottable {
  public var primitivePlottable: Int { return self }
  public init?(primitivePlottable: Int) { self = primitivePlottable }
}
extension String: Plottable {
  public var primitivePlottable: String { return self }
  public init?(primitivePlottable: String) { self = primitivePlottable }
}
extension Date: Plottable {
  public var primitivePlottable: Date { return self }
  public init?(primitivePlottable: Date) { self = primitivePlottable }
}

/// A position as a number (for scales) or a category name.
internal enum _PlotValue: Hashable {
  case number(Double)
  case category(String)

  init<V: Plottable>(_ v: V) {
    switch v.primitivePlottable {
    case let d as Double: self = .number(d)
    case let i as Int: self = .number(Double(i))
    case let s as String: self = .category(s)
    case let date as Date: self = .number(date.timeIntervalSinceReferenceDate)
    default: self = .category(String(describing: v))
    }
  }
}

public struct PlottableValue<Value: Plottable> {
  internal let label: LocalizedStringKey
  internal let value: Value
  public static func value(_ label: LocalizedStringKey, _ value: Value) -> PlottableValue<Value> {
    return PlottableValue(label: label, value: value)
  }
  public static func value<S: StringProtocol>(_ label: S, _ value: Value) -> PlottableValue<Value> {
    return PlottableValue(label: LocalizedStringKey(String(label)), value: value)
  }
}

// ---- content ------------------------------------------------------------------

internal enum _MarkKind { case line, point, bar, area, rule }

internal struct _Mark {
  var kind: _MarkKind
  var x: _PlotValue?
  var y: _PlotValue?
  var series: _PlotValue?
  var style: _PlotValue?
}

/// What built-in content does: add its marks.
internal protocol _ChartPrimitive {
  func _collect(into marks: inout [_Mark])
}

public protocol ChartContent {
  associatedtype Body: ChartContent
  @ChartContentBuilder var body: Body { get }
}

extension Never: ChartContent {
  public typealias Body = Never
  public var body: Never { fatalError() }
}

internal func _collect<C: ChartContent>(_ content: C, into marks: inout [_Mark]) {
  if let p = content as? _ChartPrimitive {
    p._collect(into: &marks)
  } else if C.Body.self != Never.self {
    _collect(content.body, into: &marks)
  }
}

public struct LineMark: ChartContent, _ChartPrimitive {
  internal var mark: _Mark
  public init<X: Plottable, Y: Plottable, S: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>,
                                                       series: PlottableValue<S>) {
    mark = _Mark(kind: .line, x: _PlotValue(x.value), y: _PlotValue(y.value), series: _PlotValue(series.value))
  }
  public init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>) {
    mark = _Mark(kind: .line, x: _PlotValue(x.value), y: _PlotValue(y.value))
  }
  public var body: Never { fatalError() }
  func _collect(into marks: inout [_Mark]) { marks.append(mark) }
}

public struct PointMark: ChartContent, _ChartPrimitive {
  internal var mark: _Mark
  public init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>) {
    mark = _Mark(kind: .point, x: _PlotValue(x.value), y: _PlotValue(y.value))
  }
  public var body: Never { fatalError() }
  func _collect(into marks: inout [_Mark]) { marks.append(mark) }
}

public struct BarMark: ChartContent, _ChartPrimitive {
  internal var mark: _Mark
  public init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>) {
    mark = _Mark(kind: .bar, x: _PlotValue(x.value), y: _PlotValue(y.value))
  }
  public var body: Never { fatalError() }
  func _collect(into marks: inout [_Mark]) { marks.append(mark) }
}

public struct AreaMark: ChartContent, _ChartPrimitive {
  internal var mark: _Mark
  public init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>) {
    mark = _Mark(kind: .area, x: _PlotValue(x.value), y: _PlotValue(y.value))
  }
  public var body: Never { fatalError() }
  func _collect(into marks: inout [_Mark]) { marks.append(mark) }
}

public struct RuleMark: ChartContent, _ChartPrimitive {
  internal var mark: _Mark
  public init<Y: Plottable>(y: PlottableValue<Y>) { mark = _Mark(kind: .rule, y: _PlotValue(y.value)) }
  public init<X: Plottable>(x: PlottableValue<X>) { mark = _Mark(kind: .rule, x: _PlotValue(x.value)) }
  public var body: Never { fatalError() }
  func _collect(into marks: inout [_Mark]) { marks.append(mark) }
}

/// Content with a foreground style chosen by a value (a series colour).
public struct _ForegroundStyledContent<Content: ChartContent>: ChartContent, _ChartPrimitive {
  internal let content: Content
  internal let style: _PlotValue
  public var body: Never { fatalError() }
  func _collect(into marks: inout [_Mark]) {
    var inner: [_Mark] = []
    Charts._collect(content, into: &inner)
    for var m in inner {
      m.style = style
      marks.append(m)
    }
  }
}

extension ChartContent {
  public func foregroundStyle<D: Plottable>(by value: PlottableValue<D>) -> some ChartContent {
    return _ForegroundStyledContent(content: self, style: _PlotValue(value.value))
  }
}

public struct AnyChartContent: ChartContent, _ChartPrimitive {
  internal let collect: (inout [_Mark]) -> Void
  public init<C: ChartContent>(_ content: C) { collect = { Charts._collect(content, into: &$0) } }
  public init(erasing content: some ChartContent) { self.init(content) }
  public var body: Never { fatalError() }
  func _collect(into marks: inout [_Mark]) { collect(&marks) }
}

/// What the content builder makes of several pieces of content.
public struct BuilderTuple<each Content> {
  internal let content: (repeat each Content)
  public init(_ content: repeat each Content) { self.content = (repeat each content) }
}
extension BuilderTuple: ChartContent where repeat each Content: ChartContent {
  public var body: Never { fatalError() }
}
extension BuilderTuple: _ChartPrimitive where repeat each Content: ChartContent {
  func _collect(into marks: inout [_Mark]) {
    for c in repeat each content { Charts._collect(c, into: &marks) }
  }
}

public struct BuilderEmpty: ChartContent, _ChartPrimitive {
  public init() {}
  public var body: Never { fatalError() }
  func _collect(into marks: inout [_Mark]) {}
}

public struct BuilderConditional<TrueContent: ChartContent, FalseContent: ChartContent>: ChartContent, _ChartPrimitive {
  internal enum Storage { case first(TrueContent), second(FalseContent) }
  internal let storage: Storage
  public var body: Never { fatalError() }
  func _collect(into marks: inout [_Mark]) {
    switch storage {
    case let .first(c): Charts._collect(c, into: &marks)
    case let .second(c): Charts._collect(c, into: &marks)
    }
  }
}

extension Optional: ChartContent where Wrapped: ChartContent {
  public var body: Never { fatalError() }
}
extension Optional: _ChartPrimitive where Wrapped: ChartContent {
  func _collect(into marks: inout [_Mark]) { if let c = self { Charts._collect(c, into: &marks) } }
}

extension ForEach: ChartContent where Content: ChartContent {
  public var body: Never { fatalError() }
}
extension ForEach: _ChartPrimitive where Content: ChartContent {
  func _collect(into marks: inout [_Mark]) {
    for element in data { Charts._collect(content(element), into: &marks) }
  }
}
extension ForEach where Content: ChartContent {
  public init(_ data: Data, @ChartContentBuilder content: @escaping (Data.Element) -> Content)
    where ID == Data.Element.ID, Data.Element: Identifiable
  {
    self.init(_chartData: data, id: { $0.id }, content: content)
  }
  public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ChartContentBuilder content: @escaping (Data.Element) -> Content) {
    self.init(_chartData: data, id: { $0[keyPath: id] }, content: content)
  }
}

@resultBuilder
public enum ChartContentBuilder {
  public static func buildExpression<C: ChartContent>(_ c: C) -> C { return c }
  public static func buildBlock() -> BuilderEmpty { return BuilderEmpty() }
  public static func buildBlock<C: ChartContent>(_ c: C) -> C { return c }
  public static func buildBlock<each C: ChartContent>(_ c: repeat each C) -> BuilderTuple<repeat each C> {
    return BuilderTuple(repeat each c)
  }
  public static func buildIf<C: ChartContent>(_ c: C?) -> C? { return c }
  public static func buildEither<T: ChartContent, F: ChartContent>(first: T) -> BuilderConditional<T, F> {
    return BuilderConditional(storage: .first(first))
  }
  public static func buildEither<T: ChartContent, F: ChartContent>(second: F) -> BuilderConditional<T, F> {
    return BuilderConditional(storage: .second(second))
  }
}

// ---- the chart view -------------------------------------------------------------

public struct AnnotationPosition: Hashable, Sendable {
  internal let id: Int
  public static var automatic: AnnotationPosition { return AnnotationPosition(id: 0) }
  public static var top: AnnotationPosition { return AnnotationPosition(id: 1) }
  public static var bottom: AnnotationPosition { return AnnotationPosition(id: 2) }
  public static var leading: AnnotationPosition { return AnnotationPosition(id: 3) }
  public static var trailing: AnnotationPosition { return AnnotationPosition(id: 4) }
  public static var overlay: AnnotationPosition { return AnnotationPosition(id: 5) }
}

/// Apple's default series colours, in order.
internal let _seriesColors: [Color] = [.blue, .green, .orange, .purple, .red, .teal, .pink, .gray]

/// A chart's marks laid out in a size: scales from the data's extent.
internal struct _ChartLayout {
  let marks: [_Mark]
  var xCategories: [String] = []
  var yCategories: [String] = []
  var xRange: ClosedRange<Double> = 0...1
  var yRange: ClosedRange<Double> = 0...1
  var styles: [_PlotValue] = []

  init(_ marks: [_Mark]) {
    self.marks = marks
    var xs: [Double] = [], ys: [Double] = []
    for m in marks {
      switch m.x {
      case let .number(d)?: xs.append(d)
      case let .category(s)?: if !xCategories.contains(s) { xCategories.append(s) }
      case nil: break
      }
      switch m.y {
      case let .number(d)?: ys.append(d)
      case let .category(s)?: if !yCategories.contains(s) { yCategories.append(s) }
      case nil: break
      }
      if let s = m.style ?? m.series, !styles.contains(s) { styles.append(s) }
    }
    if let lo = xs.min(), let hi = xs.max() { xRange = lo...(hi > lo ? hi : lo + 1) }
    // Like Swift Charts, a y scale of numbers starts at zero when the data allow.
    if let lo = ys.min(), let hi = ys.max() {
      let start = Swift.min(lo, 0)
      yRange = start...(hi > start ? hi : start + 1)
    }
  }

  func x(_ v: _PlotValue?, _ width: CGFloat) -> CGFloat {
    switch v {
    case let .number(d)?: return CGFloat((d - xRange.lowerBound) / (xRange.upperBound - xRange.lowerBound)) * width
    case let .category(s)?:
      let i = xCategories.firstIndex(of: s) ?? 0
      return (CGFloat(i) + 0.5) / CGFloat(Swift.max(xCategories.count, 1)) * width
    case nil: return 0
    }
  }
  func y(_ v: _PlotValue?, _ height: CGFloat) -> CGFloat {
    switch v {
    case let .number(d)?: return height - CGFloat((d - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound)) * height
    case let .category(s)?:
      let i = yCategories.firstIndex(of: s) ?? 0
      return (CGFloat(i) + 0.5) / CGFloat(Swift.max(yCategories.count, 1)) * height
    case nil: return height
    }
  }
  func color(_ m: _Mark) -> Color {
    guard let s = m.style ?? m.series, let i = styles.firstIndex(of: s) else { return _seriesColors[0] }
    return _seriesColors[i % _seriesColors.count]
  }

  /// One path per series for lines, and the other marks' shapes.
  func paths(in size: CGSize) -> [(Path, Color, Bool)] {
    var out: [(Path, Color, Bool)] = []
    var lines: [_PlotValue?: [_Mark]] = [:]
    var order: [_PlotValue?] = []
    for m in marks where m.kind == .line {
      let key = m.series ?? m.style
      if lines[key] == nil { order.append(key) }
      lines[key, default: []].append(m)
    }
    for key in order {
      let ms = lines[key] ?? []
      var p = Path()
      for (i, m) in ms.enumerated() {
        let pt = CGPoint(x: x(m.x, size.width), y: y(m.y, size.height))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
      }
      if let first = ms.first { out.append((p, color(first), true)) }
    }
    let bars = marks.filter { $0.kind == .bar }.count
    let barWidth = size.width / CGFloat(Swift.max(Swift.max(xCategories.count, bars), 1)) * 0.6
    for m in marks where m.kind != .line {
      var p = Path()
      switch m.kind {
      case .point:
        let c = CGPoint(x: x(m.x, size.width), y: y(m.y, size.height))
        p.addEllipse(in: CGRect(origin: CGPoint(x: c.x - 3, y: c.y - 3), size: CGSize(width: 6, height: 6)))
        out.append((p, color(m), false))
      case .bar:
        let cx = x(m.x, size.width), top = y(m.y, size.height), base = y(.number(Swift.max(yRange.lowerBound, 0)), size.height)
        p.addRect(CGRect(origin: CGPoint(x: cx - barWidth / 2, y: Swift.min(top, base)),
                         size: CGSize(width: barWidth, height: abs(base - top))))
        out.append((p, color(m), false))
      case .area:
        let px = x(m.x, size.width), py = y(m.y, size.height)
        p.addRect(CGRect(origin: CGPoint(x: px - 1, y: py), size: CGSize(width: 2, height: size.height - py)))
        out.append((p, color(m).opacity(0.4), false))
      case .rule:
        if m.y != nil {
          let py = y(m.y, size.height)
          p.move(to: CGPoint(x: 0, y: py))
          p.addLine(to: CGPoint(x: size.width, y: py))
        } else {
          let px = x(m.x, size.width)
          p.move(to: CGPoint(x: px, y: 0))
          p.addLine(to: CGPoint(x: px, y: size.height))
        }
        out.append((p, color(m), true))
      case .line: break
      }
    }
    return out
  }
}

/// A chart's marks drawn as one shape layer.
internal struct _ChartPlot: Shape {
  let layout: _ChartLayout
  let index: Int
  func path(in rect: CGRect) -> Path {
    let all = layout.paths(in: rect.size)
    return index < all.count ? all[index].0 : Path()
  }
}

public struct Chart<Content: ChartContent>: View {
  internal let content: Content

  public init(@ChartContentBuilder content: () -> Content) { self.content = content() }

  public init<Data: RandomAccessCollection, C: ChartContent>(_ data: Data, @ChartContentBuilder content: @escaping (Data.Element) -> C)
    where Content == ForEach<Data, Data.Element.ID, C>, Data.Element: Identifiable
  {
    self.content = ForEach(_chartData: data, id: { $0.id }, content: content)
  }

  internal var layout: _ChartLayout {
    var marks: [_Mark] = []
    Charts._collect(content, into: &marks)
    return _ChartLayout(marks)
  }

  public var body: some View {
    let layout = self.layout
    let shapes = layout.paths(in: CGSize(width: 100, height: 100))
    return ZStack {
      ForEach(0..<shapes.count, id: \.self) { i in
        if shapes[i].2 {
          _ChartPlot(layout: layout, index: i).stroke(shapes[i].1, lineWidth: 2)
        } else {
          _ChartPlot(layout: layout, index: i).fill(shapes[i].1)
        }
      }
    }
  }
}

// ---- axes ----------------------------------------------------------------------

extension View {
  /// Shown or hidden x axis. The chart draws no axis lines, so this
  /// only records the choice.
  public func chartXAxis(_ visibility: Visibility) -> some View { return self }
  public func chartYAxis(_ visibility: Visibility) -> some View { return self }

  /// A y-axis label: the text beside the chart.
  public func chartYAxisLabel(_ label: LocalizedStringKey, position: AnnotationPosition = .automatic,
                              alignment: Alignment? = nil, spacing: CGFloat? = nil) -> some View {
    return HStack(spacing: spacing ?? 4) {
      Text(label).font(.caption).foregroundColor(.gray)
      self
    }
  }
  public func chartXAxisLabel(_ label: LocalizedStringKey, position: AnnotationPosition = .automatic,
                              alignment: Alignment? = nil, spacing: CGFloat? = nil) -> some View {
    return VStack(spacing: spacing ?? 4) {
      self
      Text(label).font(.caption).foregroundColor(.gray)
    }
  }
}
