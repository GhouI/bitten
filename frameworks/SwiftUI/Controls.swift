// Containers and controls: ForEach, Group, Section, List, ScrollView,
// lazy stacks and grids, Label, LabeledContent, GroupBox, Form, Toggle,
// Slider, Stepper, Picker, Menu, TextField, ProgressView,
// ContentUnavailableView, ControlGroup, NavigationSplitView, Table,
// GeometryReader, TimelineView, focus state, Bindable and AppStorage.
// Generic parameters and where clauses follow Apple's (they are part of the
// mangled names programs bind to); frozen types keep Apple's layouts.

import CoreGraphics
import Dispatch

// MARK: - lists of views

public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content> {
  public var data: Data
  public var content: (Data.Element) -> Content
  let idOf: (Data.Element) -> ID
  internal init(data: Data, id: @escaping (Data.Element) -> ID, content: @escaping (Data.Element) -> Content) {
    self.data = data
    self.content = content
    idOf = id
  }
}

extension ForEach: View where Content: View {
  public typealias Body = Never
  public var body: Never { return fatalError("ForEach has no body") }
  nonisolated public static func _makeView(view: _GraphValue<ForEach>, inputs: _ViewInputs) -> _ViewOutputs {
    let nodes = _makeViewList(view: view, inputs: _ViewListInputs(inputs)).nodes
    return _ViewOutputs(_StackNode(axis: .vertical, alignment: .center, spacing: nil, environment: inputs.environment,
                                   children: nodes))
  }
  nonisolated public static func _makeViewList(view: _GraphValue<ForEach>, inputs: _ViewListInputs) -> _ViewListOutputs {
    let v = view.value
    var nodes: [_ViewNode] = []
    for element in v.data {
      let id = v.idOf(element)
      nodes += _makeNodes(v.content(element), inputs: inputs.base.named("each:\(id.hashValue)"))
    }
    return _ViewListOutputs(nodes)
  }
}

extension ForEach where ID == Data.Element.ID, Content: View, Data.Element: Identifiable {
  public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
    self.init(data: data, id: { $0.id }, content: content)
  }
}
extension ForEach where Content: View {
  public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
    self.init(data: data, id: { $0[keyPath: id] }, content: content)
  }
}
extension ForEach where Data == Range<Int>, ID == Int, Content: View {
  public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
    self.init(data: data, id: { $0 }, content: content)
  }
}

@frozen
public struct Group<Content> {
  public typealias Body = Never
  @usableFromInline internal var content: Content
  @inlinable public init(@ViewBuilder content: () -> Content) { self.content = content() }
}
extension Group: View where Content: View {
  public var body: Never { return fatalError("Group has no body") }
  nonisolated public static func _makeView(view: _GraphValue<Group>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    return Content._makeView(view: _GraphValue({ v.content }), inputs: inputs)
  }
  nonisolated public static func _makeViewList(view: _GraphValue<Group>, inputs: _ViewListInputs) -> _ViewListOutputs {
    let v = view.value
    return Content._makeViewList(view: _GraphValue({ v.content }), inputs: inputs)
  }
}

@frozen
public struct Section<Parent, Content, Footer> {
  @usableFromInline internal var header: Parent
  @usableFromInline internal var content: Content
  @usableFromInline internal var footer: Footer
  /// Collapsible sections' state (Apple's fourth stored property: the app's
  /// inlined initializers build all four and require this layout).
  @usableFromInline internal var isExpanded: Binding<Bool>?
  @inlinable internal init(header: Parent, content: Content, footer: Footer, isExpanded: Binding<Bool>? = nil) {
    self.header = header
    self.content = content
    self.footer = footer
    self.isExpanded = isExpanded
  }
}
extension Section: View where Parent: View, Content: View, Footer: View {
  public typealias Body = Never
  public var body: Never { return fatalError("Section has no body") }
  nonisolated public static func _makeView(view: _GraphValue<Section>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    var header = inputs
    header.environment.font = .headline
    var children: [_ViewNode] = []
    var items: [_ViewNode] = []
    if Parent.self != EmptyView.self { children.append(_makeNode(v.header, inputs: header.named("header"))) }
    // a collapsed section shows its header only
    if v.isExpanded?.wrappedValue ?? true {
      items = _makeNodes(v.content, inputs: inputs.named("content"))
      children += items
      if Footer.self != EmptyView.self { children.append(_makeNode(v.footer, inputs: inputs.named("footer"))) }
    }
    let stack = _StackNode(axis: .vertical, alignment: Alignment(horizontal: .leading, vertical: .center),
                           spacing: 6, environment: inputs.environment, children: children)
    stack.sectionItems = items
    return _ViewOutputs(stack)
  }
}
extension Section where Parent == EmptyView, Content: View, Footer == EmptyView {
  @inlinable public init(@ViewBuilder content: () -> Content) {
    self.init(header: EmptyView(), content: content(), footer: EmptyView())
  }
}
extension Section where Parent: View, Content: View, Footer: View {
  @inlinable public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent, @ViewBuilder footer: () -> Footer) {
    self.init(header: header(), content: content(), footer: footer())
  }
}
extension Section where Parent: View, Content: View, Footer == EmptyView {
  @inlinable public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent) {
    self.init(header: header(), content: content(), footer: EmptyView())
  }
}
extension Section where Parent: View, Content: View, Footer == EmptyView {
  /// A collapsible section, expanded while `isExpanded` is true.
  public init(isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent) {
    self.init(header: header(), content: content(), footer: EmptyView(), isExpanded: isExpanded)
  }
}
extension Section where Parent == Text, Content: View, Footer == EmptyView {
  public init(_ titleKey: LocalizedStringKey, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
    self.init(header: Text(titleKey), content: content(), footer: EmptyView(), isExpanded: isExpanded)
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
    self.init(header: Text(title), content: content(), footer: EmptyView(), isExpanded: isExpanded)
  }
  public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
    self.init(header: Text(titleKey), content: content(), footer: EmptyView())
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
    self.init(header: Text(title), content: content(), footer: EmptyView())
  }
}

// MARK: - lists and scrolling

public struct List<SelectionValue: Hashable, Content: View>: View {
  let content: Content
  public typealias Body = Never
  public var body: Never { return fatalError("List has no body") }
  nonisolated public static func _makeView(view: _GraphValue<List>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    let rows = _makeNodes(v.content, inputs: inputs.named("rows"))
    var children: [_ViewNode] = []
    for (i, r) in rows.enumerated() {
      if i > 0 { children.append(_DividerNode(environment: inputs.environment)) }
      children.append(_PaddingNode(insets: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8),
                                   environment: inputs.environment, children: [r]))
    }
    let stack = _StackNode(axis: .vertical, alignment: Alignment(horizontal: .leading, vertical: .center), spacing: 0,
                           environment: inputs.environment, children: children)
    return _ViewOutputs(_ScrollNode(axes: .vertical, key: inputs.base.path + "#scroll", context: inputs.base.context,
                                    content: _FillWidthNode(content: stack, environment: inputs.environment),
                                    environment: inputs.environment))
  }
}
extension List where SelectionValue == Never {
  public init(@ViewBuilder content: () -> Content) { self.content = content() }
}
extension List {
  public init(selection: Binding<SelectionValue?>?, @ViewBuilder content: () -> Content) { self.content = content() }
  public init(selection: Binding<Set<SelectionValue>>?, @ViewBuilder content: () -> Content) { self.content = content() }
}

/// Lays its content out at its own width (proposed), leading-aligned.
internal final class _FillWidthNode: _ViewNode {
  init(content: _ViewNode, environment: EnvironmentValues) { super.init(environment: environment, children: [content]) }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    let s = children[0].sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
    return CGSize(width: proposal.width ?? s.width, height: s.height)
  }
  override func place(in rect: CGRect) {
    frame = rect
    let s = children[0].sizeThatFits(ProposedViewSize(width: rect._width, height: nil))
    children[0].place(in: CGRect(origin: rect.origin, size: CGSize(width: rect._width, height: s.height)))
  }
}

public struct ScrollView<Content: View>: View {
  public var content: Content
  public var axes: Axis.Set
  public var showsIndicators: Bool
  public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
    self.axes = axes
    self.showsIndicators = showsIndicators
    self.content = content()
  }
  public typealias Body = Never
  public var body: Never { return fatalError("ScrollView has no body") }
  nonisolated public static func _makeView(view: _GraphValue<ScrollView>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    let content = _makeNode(v.content, inputs: inputs.named("content"))
    return _ViewOutputs(_ScrollNode(axes: v.axes, key: inputs.base.path + "#scroll", context: inputs.base.context,
                                    content: content, environment: inputs.environment))
  }
}

/// Scroll offsets survive rebuilds, by position.
final class _ScrollState {
  var offset = CGPoint(x: 0, y: 0)
}

/// Content laid out at its ideal size along the scrolling axes, clipped to
/// the frame and moved by the offset; the wheel scrolls it.
internal final class _ScrollNode: _ViewNode {
  let axes: Axis.Set
  let state: _ScrollState
  init(axes: Axis.Set, key: String, context: _RenderContext, content: _ViewNode, environment: EnvironmentValues) {
    self.axes = axes
    state = context.store(key) { _ScrollState() }
    super.init(environment: environment, children: [content])
  }
  var contentSize = CGSize(width: 0, height: 0)
  func contentProposal(_ size: CGSize) -> ProposedViewSize {
    return ProposedViewSize(width: axes.contains(.horizontal) ? nil : size.width,
                            height: axes.contains(.vertical) ? nil : size.height)
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    let s = children[0].sizeThatFits(contentProposal(proposal.replacingUnspecifiedDimensions()))
    return CGSize(width: proposal.width ?? s.width, height: proposal.height ?? s.height)
  }
  override func place(in rect: CGRect) {
    frame = rect
    let s = children[0].sizeThatFits(contentProposal(rect.size))
    contentSize = CGSize(width: max(s.width, axes.contains(.horizontal) ? 0 : rect._width), height: s.height)
    clamp()
    children[0].place(in: CGRect(origin: CGPoint(x: rect._minX - state.offset.x, y: rect._minY - state.offset.y),
                                 size: CGSize(width: max(contentSize.width, rect._width), height: contentSize.height)))
  }
  func clamp() {
    state.offset.x = max(0, min(state.offset.x, contentSize.width - frame._width))
    state.offset.y = max(0, min(state.offset.y, contentSize.height - frame._height))
  }
  override func draw(_ context: CGContext) {
    CGContextSaveGState(context)
    CGContextClipToRect(context, frame)
    children[0].draw(context)
    CGContextRestoreGState(context)
  }
  override func hit(_ point: CGPoint) -> _ViewNode? {
    guard frame._contains(point) else { return nil }
    return children[0].hit(point)
  }
  override func scroll(at point: CGPoint, dx: CGFloat, dy: CGFloat) -> Bool {
    guard frame._contains(point) else { return false }
    if children[0].scroll(at: point, dx: dx, dy: dy) { return true }
    let before = state.offset
    if axes.contains(.vertical) { state.offset.y -= dy }
    if axes.contains(.horizontal) { state.offset.x -= dx }
    clamp()
    return before.x != state.offset.x || before.y != state.offset.y
  }
}

public struct ScrollViewProxy {
  public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {}
}
@frozen
public struct ScrollViewReader<Content: View>: View {
  public var content: (ScrollViewProxy) -> Content
  public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) { self.content = content }
  public typealias Body = Never
  public var body: Never { return fatalError("ScrollViewReader has no body") }
  nonisolated public static func _makeView(view: _GraphValue<ScrollViewReader>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    return _ViewOutputs(_makeNode(v.content(ScrollViewProxy()), inputs: inputs.named("reader")))
  }
}

public struct PinnedScrollableViews: OptionSet, Sendable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  public static let sectionHeaders = PinnedScrollableViews(rawValue: 1)
  public static let sectionFooters = PinnedScrollableViews(rawValue: 2)
}

public struct LazyVStack<Content: View>: View {
  let alignment: HorizontalAlignment, spacing: CGFloat?, content: Content
  public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
              pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) {
    self.alignment = alignment
    self.spacing = spacing
    self.content = content()
  }
  public typealias Body = Never
  public var body: Never { return fatalError("LazyVStack has no body") }
  nonisolated public static func _makeView(view: _GraphValue<LazyVStack>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    return _ViewOutputs(_StackNode(axis: .vertical, alignment: Alignment(horizontal: v.alignment, vertical: .center),
                                   spacing: v.spacing, environment: inputs.environment,
                                   children: _makeNodes(v.content, inputs: inputs.named("content"))))
  }
}
public struct LazyHStack<Content: View>: View {
  let alignment: VerticalAlignment, spacing: CGFloat?, content: Content
  public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil,
              pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) {
    self.alignment = alignment
    self.spacing = spacing
    self.content = content()
  }
  public typealias Body = Never
  public var body: Never { return fatalError("LazyHStack has no body") }
  nonisolated public static func _makeView(view: _GraphValue<LazyHStack>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    return _ViewOutputs(_StackNode(axis: .horizontal, alignment: Alignment(horizontal: .center, vertical: v.alignment),
                                   spacing: v.spacing, environment: inputs.environment,
                                   children: _makeNodes(v.content, inputs: inputs.named("content"))))
  }
}

public struct GridItem: Sendable {
  public enum Size: Sendable {
    case fixed(CGFloat)
    case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
    case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
  }
  public var size: Size
  public var spacing: CGFloat?
  public var alignment: Alignment?
  public init(_ size: Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {
    self.size = size
    self.spacing = spacing
    self.alignment = alignment
  }
}

public struct LazyVGrid<Content: View>: View {
  let columns: [GridItem], alignment: HorizontalAlignment, spacing: CGFloat?, content: Content
  public init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
              pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) {
    self.columns = columns
    self.alignment = alignment
    self.spacing = spacing
    self.content = content()
  }
  public typealias Body = Never
  public var body: Never { return fatalError("LazyVGrid has no body") }
  nonisolated public static func _makeView(view: _GraphValue<LazyVGrid>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    return _ViewOutputs(_GridNode(columns: v.columns, spacing: v.spacing ?? 8, environment: inputs.environment,
                                  children: _makeNodes(v.content, inputs: inputs.named("content"))))
  }
}

/// Cells in rows of a column count (from the grid items; adaptive items
/// fit as many as the width allows), each column an equal share.
internal final class _GridNode: _ViewNode {
  let columns: [GridItem]
  let spacing: CGFloat
  init(columns: [GridItem], spacing: CGFloat, environment: EnvironmentValues, children: [_ViewNode]) {
    self.columns = columns
    self.spacing = spacing
    super.init(environment: environment, children: children)
  }
  func columnCount(_ width: CGFloat?) -> Int {
    if columns.count == 1, case .adaptive(let minimum, _) = columns[0].size, let w = width {
      return max(1, Int((w + spacing) / (minimum + spacing)))
    }
    return max(1, columns.count)
  }
  func layout(_ width: CGFloat?) -> (cols: Int, colWidth: CGFloat?, rows: [CGFloat]) {
    let n = columnCount(width)
    let cw = width.map { max(0, ($0 - spacing * CGFloat(n - 1)) / CGFloat(n)) }
    var rows: [CGFloat] = []
    var i = 0
    while i < children.count {
      var h: CGFloat = 0
      for c in children[i..<min(i + n, children.count)] {
        h = max(h, c.sizeThatFits(ProposedViewSize(width: cw, height: nil)).height)
      }
      rows.append(h)
      i += n
    }
    return (n, cw, rows)
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    let l = layout(proposal.width)
    let h = l.rows.reduce(0, +) + spacing * CGFloat(max(0, l.rows.count - 1))
    let w = proposal.width ?? CGFloat(l.cols) * (children.first?.sizeThatFits(.unspecified).width ?? 0)
    return CGSize(width: w, height: h)
  }
  override func place(in rect: CGRect) {
    frame = rect
    let l = layout(rect._width)
    let cw = l.colWidth ?? 0
    var y = rect._minY
    for (r, h) in l.rows.enumerated() {
      for c in 0..<l.cols {
        let i = r * l.cols + c
        guard i < children.count else { break }
        let x = rect._minX + CGFloat(c) * (cw + spacing)
        let cell = CGRect(_x: x, y: y, width: cw, height: h)
        let s = children[i].sizeThatFits(ProposedViewSize(cell.size))
        children[i].place(in: CGRect(origin: Alignment.center.origin(of: s, in: cell), size: s))
      }
      y += h + spacing
    }
  }
}

// Grid and GridRow: frozen trees, as Apple's inlinable initializers build
// them.
@frozen
public struct GridLayout: _StackRoot, _VariadicView_UnaryViewRoot {
  public var alignment: Alignment
  public var horizontalSpacing: CGFloat?
  public var verticalSpacing: CGFloat?
  @inlinable public init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil) {
    self.alignment = alignment
    self.horizontalSpacing = horizontalSpacing
    self.verticalSpacing = verticalSpacing
  }
  func makeNode(_ children: [_ViewNode], environment: EnvironmentValues) -> _ViewNode {
    return _TableGridNode(hSpacing: horizontalSpacing ?? 8, vSpacing: verticalSpacing ?? 8, alignment: alignment,
                          environment: environment, children: children)
  }
}
@frozen
public struct Grid<Content: View>: View {
  @usableFromInline internal var _tree: _VariadicView.Tree<GridLayout, Content>
  @inlinable public init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil,
                         verticalSpacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
    _tree = .init(root: GridLayout(alignment: alignment, horizontalSpacing: horizontalSpacing,
                                    verticalSpacing: verticalSpacing), content: content())
  }
  public typealias Body = Never
  public var body: Never { return fatalError("Grid has no body") }
  nonisolated public static func _makeView(view: _GraphValue<Grid>, inputs: _ViewInputs) -> _ViewOutputs {
    return _VariadicView.Tree<GridLayout, Content>._makeView(view: view[\._tree], inputs: inputs)
  }
}
@frozen
public struct _GridRowLayout: _StackRoot, _VariadicView_UnaryViewRoot {
  public var alignment: VerticalAlignment?
  @inlinable public init(alignment: VerticalAlignment? = nil) { self.alignment = alignment }
  func makeNode(_ children: [_ViewNode], environment: EnvironmentValues) -> _ViewNode {
    let row = _GridRowNode(environment: environment, children: children)
    row.alignment = alignment
    return row
  }
}
/// Apple's GridRow stores its alignment and its content as two fields:
/// programs read the content's offset from the metadata's field offsets
/// (the second entry) when its size is only known at run time.
@frozen
public struct GridRow<Content: View>: View {
  @usableFromInline internal var alignment: VerticalAlignment?
  @usableFromInline internal var content: Content
  @inlinable public init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) {
    self.alignment = alignment
    self.content = content()
  }
  internal var _tree: _VariadicView.Tree<_GridRowLayout, Content> {
    return .init(root: _GridRowLayout(alignment: alignment), content: content)
  }
  public typealias Body = Never
  public var body: Never { return fatalError("GridRow has no body") }
  nonisolated public static func _makeView(view: _GraphValue<GridRow>, inputs: _ViewInputs) -> _ViewOutputs {
    return _VariadicView.Tree<_GridRowLayout, Content>._makeView(view: view[\._tree], inputs: inputs)
  }
}
internal final class _GridRowNode: _ViewNode {
  var alignment: VerticalAlignment?
}

/// What grid cell modifiers say about a cell: the columns it spans, the
/// axes it doesn't size the grid in, its column's alignment and anchor.
internal final class _GridCellNode: _ViewNode {
  var columns = 1
  var unsized: Axis.Set = []
  var columnAlignment: HorizontalAlignment?
  var anchor: UnitPoint?
  init(content: _ViewNode, environment: EnvironmentValues) {
    super.init(environment: environment, children: [content])
  }
  /// The settings of `node` and the cell nodes right under it.
  static func info(_ node: _ViewNode) -> (columns: Int, unsized: Axis.Set, column: HorizontalAlignment?, anchor: UnitPoint?) {
    var columns: Int?, unsized: Axis.Set = [], column: HorizontalAlignment?, anchor: UnitPoint?
    var n: _ViewNode? = node
    while let c = n as? _GridCellNode {
      if columns == nil, c.columns != 1 { columns = c.columns }
      unsized.formUnion(c.unsized)
      if column == nil { column = c.columnAlignment }
      if anchor == nil { anchor = c.anchor }
      n = c.children.first
    }
    return (max(1, columns ?? 1), unsized, column, anchor)
  }
}

/// SwiftUI's Grid: rows of cells in shared columns. A column is as wide as
/// its widest cell; a cell can span columns (gridCellColumns), and a cell
/// unsized on an axis (gridCellUnsizedAxes) takes the size the others give
/// it there. A view that isn't a GridRow is a row spanning every column.
internal final class _TableGridNode: _ViewNode {
  let hSpacing: CGFloat, vSpacing: CGFloat
  let alignment: Alignment
  init(hSpacing: CGFloat, vSpacing: CGFloat, alignment: Alignment = .center, environment: EnvironmentValues,
       children: [_ViewNode]) {
    self.hSpacing = hSpacing
    self.vSpacing = vSpacing
    self.alignment = alignment
    super.init(environment: environment, children: children)
  }
  struct Cell {
    let node: _ViewNode
    let column: Int, span: Int
    let unsized: Axis.Set
    let columnAlignment: HorizontalAlignment?
  }
  struct Row {
    let cells: [Cell]
    let full: Bool
    let alignment: VerticalAlignment?
  }
  /// The rows, with each cell's place; and the number of columns.
  func layoutRows() -> ([Row], Int) {
    var rows: [Row] = []
    var columns = 0
    for child in children {
      if let r = child as? _GridRowNode {
        var at = 0
        var cells: [Cell] = []
        for c in r.children {
          let i = _GridCellNode.info(c)
          cells.append(Cell(node: c, column: at, span: i.columns, unsized: i.unsized, columnAlignment: i.column))
          at += i.columns
        }
        columns = max(columns, at)
        rows.append(Row(cells: cells, full: false, alignment: r.alignment))
      } else {
        let i = _GridCellNode.info(child)
        rows.append(Row(cells: [Cell(node: child, column: 0, span: 0, unsized: i.unsized, columnAlignment: nil)],
                        full: true, alignment: nil))
      }
    }
    return (rows, columns)
  }
  /// Column widths at their ideal sizes (spanning cells widen the last
  /// column they span when they need more).
  func widths(_ rows: [Row], _ n: Int) -> [CGFloat] {
    var w = Array(repeating: CGFloat(0), count: n)
    for row in rows where !row.full {
      for c in row.cells where c.span == 1 && !c.unsized.contains(.horizontal) && c.column < n {
        w[c.column] = max(w[c.column], c.node.measure(.unspecified).width)
      }
    }
    for row in rows where !row.full {
      for c in row.cells where c.span > 1 && !c.unsized.contains(.horizontal) {
        let last = min(n, c.column + c.span) - 1
        guard last >= c.column else { continue }
        let have = w[c.column...last].reduce(0, +) + hSpacing * CGFloat(last - c.column)
        let want = c.node.measure(.unspecified).width
        if want > have { w[last] += want - have }
      }
    }
    return w
  }
  func span(_ w: [CGFloat], _ c: Cell, _ n: Int) -> CGFloat {
    if c.span == 0 { return w.reduce(0, +) + hSpacing * CGFloat(max(0, n - 1)) }
    let last = min(n, c.column + c.span) - 1
    guard last >= c.column else { return 0 }
    return w[c.column...last].reduce(0, +) + hSpacing * CGFloat(last - c.column)
  }
  func heights(_ rows: [Row], _ w: [CGFloat], _ n: Int) -> [CGFloat] {
    return rows.map { row in
      row.cells.filter { !$0.unsized.contains(.vertical) }
        .map { $0.node.measure(ProposedViewSize(width: span(w, $0, n), height: nil)).height }.max() ?? 0
    }
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    let (rows, n) = layoutRows()
    var w = widths(rows, n)
    // Full-width rows not sized horizontally only take what there is.
    var width = w.reduce(0, +) + hSpacing * CGFloat(max(0, n - 1))
    for row in rows where row.full && !row.cells[0].unsized.contains(.horizontal) {
      width = max(width, row.cells[0].node.measure(.unspecified).width)
    }
    if n == 0 { w = [] }
    let h = heights(rows, w, n)
    return CGSize(width: width, height: h.reduce(0, +) + vSpacing * CGFloat(max(0, h.count - 1)))
  }
  override func place(in rect: CGRect) {
    frame = rect
    let (rows, n) = layoutRows()
    let w = widths(rows, n)
    let h = heights(rows, w, n)
    var y = rect._minY
    for (ri, row) in rows.enumerated() {
      for c in row.cells {
        var x = rect._minX
        for i in 0..<min(c.column, n) { x += w[i] + hSpacing }
        let cell = CGRect(_x: x, y: y, width: c.span == 0 ? rect._width : span(w, c, n), height: h[ri])
        let s = c.node.measure(ProposedViewSize(cell.size))
        let a = Alignment(horizontal: c.columnAlignment ?? alignment.horizontal,
                          vertical: row.alignment ?? alignment.vertical)
        let size = CGSize(width: min(s.width, cell._width), height: min(s.height, cell._height))
        c.node.place(in: CGRect(origin: a.origin(of: size, in: cell), size: size))
      }
      y += h[ri] + vSpacing
    }
  }
}

@frozen
public struct _GridCellSizeModifier: _NodeModifier {
  @usableFromInline var columnCount: Int
  @inlinable init(columnCount: Int) { self.columnCount = columnCount }
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode {
    let c = _GridCellNode(content: content, environment: environment)
    c.columns = columnCount
    return c
  }
}
@frozen
public struct _GridUnsizedAxesModifier: _NodeModifier {
  @usableFromInline var axes: Axis.Set
  @inlinable init(axes: Axis.Set) { self.axes = axes }
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode {
    let c = _GridCellNode(content: content, environment: environment)
    c.unsized = axes
    return c
  }
}
@frozen
public struct _GridAlignmentModifier: _NodeModifier {
  @usableFromInline var alignment: HorizontalAlignment
  @inlinable init(alignment: HorizontalAlignment) { self.alignment = alignment }
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode {
    let c = _GridCellNode(content: content, environment: environment)
    c.columnAlignment = alignment
    return c
  }
}
@frozen
public struct _GridAnchorModifier: _NodeModifier {
  @usableFromInline var anchor: UnitPoint
  @inlinable init(anchor: UnitPoint) { self.anchor = anchor }
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode {
    let c = _GridCellNode(content: content, environment: environment)
    c.anchor = anchor
    return c
  }
}
extension View {
  @inlinable public func gridCellColumns(_ count: Int) -> some View { return modifier(_GridCellSizeModifier(columnCount: count)) }
  @inlinable public func gridCellUnsizedAxes(_ axes: Axis.Set) -> some View { return modifier(_GridUnsizedAxesModifier(axes: axes)) }
  @inlinable public func gridColumnAlignment(_ guide: HorizontalAlignment) -> some View {
    return modifier(_GridAlignmentModifier(alignment: guide))
  }
  @inlinable public func gridCellAnchor(_ anchor: UnitPoint) -> some View { return modifier(_GridAnchorModifier(anchor: anchor)) }
}

// MARK: - labels and groups

public struct Label<Title: View, Icon: View>: View {
  let title: Title, icon: Icon
  public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {
    self.title = title()
    self.icon = icon()
  }
  public typealias Body = Never
  public var body: Never { return fatalError("Label has no body") }
  nonisolated public static func _makeView(view: _GraphValue<Label>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    let style = inputs.environment._labelStyle
    var children: [_ViewNode] = []
    if style != .titleOnly { children.append(_makeNode(v.icon, inputs: inputs.named("icon"))) }
    if style != .iconOnly { children.append(_makeNode(v.title, inputs: inputs.named("title"))) }
    return _ViewOutputs(_StackNode(axis: .horizontal, alignment: .center, spacing: 6, environment: inputs.environment,
                                   children: children))
  }
}
extension Label where Title == Text, Icon == Image {
  public init(_ titleKey: LocalizedStringKey, systemImage name: String) {
    self.init(title: { Text(titleKey) }, icon: { Image(systemName: name) })
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, systemImage name: String) {
    self.init(title: { Text(title) }, icon: { Image(systemName: name) })
  }
  public init(_ titleKey: LocalizedStringKey, image name: String) {
    self.init(title: { Text(titleKey) }, icon: { Image(name) })
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, image name: String) {
    self.init(title: { Text(title) }, icon: { Image(name) })
  }
}

internal enum _LabelAppearance { case titleAndIcon, iconOnly, titleOnly }
struct _LabelsHiddenKey: EnvironmentKey { static let defaultValue = false }
struct _FormGroupedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
  internal var _formGrouped: Bool {
    get { return self[_FormGroupedKey.self] }
    set { self[_FormGroupedKey.self] = newValue }
  }
}
extension EnvironmentValues {
  internal var _labelsHidden: Bool {
    get { return self[_LabelsHiddenKey.self] }
    set { self[_LabelsHiddenKey.self] = newValue }
  }
}
struct _LabelStyleKey: EnvironmentKey { static let defaultValue = _LabelAppearance.titleAndIcon }
extension EnvironmentValues {
  internal var _labelStyle: _LabelAppearance {
    get { return self[_LabelStyleKey.self] }
    set { self[_LabelStyleKey.self] = newValue }
  }
}
public struct TitleAndIconLabelStyle: LabelStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View { return EmptyView() }
}
public struct IconOnlyLabelStyle: LabelStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View { return EmptyView() }
}
public struct TitleOnlyLabelStyle: LabelStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View { return EmptyView() }
}
public struct DefaultLabelStyle: LabelStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View { return EmptyView() }
}
extension LabelStyle where Self == TitleAndIconLabelStyle { public static var titleAndIcon: TitleAndIconLabelStyle { return .init() } }
extension LabelStyle where Self == IconOnlyLabelStyle { public static var iconOnly: IconOnlyLabelStyle { return .init() } }
extension LabelStyle where Self == TitleOnlyLabelStyle { public static var titleOnly: TitleOnlyLabelStyle { return .init() } }
extension LabelStyle where Self == DefaultLabelStyle { public static var automatic: DefaultLabelStyle { return .init() } }
extension View {
  public func labelStyle<S: LabelStyle>(_ style: S) -> some View {
    let a: _LabelAppearance = style is IconOnlyLabelStyle ? .iconOnly : style is TitleOnlyLabelStyle ? .titleOnly : .titleAndIcon
    return environment(\._labelStyle, a)
  }
  /// Controls inside leave out their labels (the label still names them).
  public func labelsHidden() -> some View { return environment(\._labelsHidden, true) }
  public func labeledContentStyle<S: LabeledContentStyle>(_ style: S) -> some View { return self }
}

public struct LabeledContent<Label, Content> {
  let label: Label, content: Content
}
extension LabeledContent: View where Label: View, Content: View {
  public typealias Body = Never
  public var body: Never { return fatalError("LabeledContent has no body") }
  nonisolated public static func _makeView(view: _GraphValue<LabeledContent>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    var secondary = inputs
    secondary.environment._foregroundStyle = AnyShapeStyle(HierarchicalShapeStyle.secondary)
    if inputs.environment._labelsHidden { return _ViewOutputs(_makeNode(v.content, inputs: inputs.named("content"))) }
    return _ViewOutputs(_StackNode(axis: .horizontal, alignment: .center, spacing: 8, environment: inputs.environment,
                                   children: [_makeNode(v.label, inputs: inputs.named("label")),
                                              _SpacerNode(minLength: 8, environment: inputs.environment),
                                              _makeNode(v.content, inputs: secondary.named("content"))]))
  }
}
extension LabeledContent where Label: View, Content: View {
  public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.label = label()
    self.content = content()
  }
}
extension LabeledContent where Label == Text, Content: View {
  public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
    label = Text(titleKey)
    self.content = content()
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
    label = Text(title)
    self.content = content()
  }
}
extension LabeledContent where Label == Text, Content == Text {
  public init<S: StringProtocol>(_ titleKey: LocalizedStringKey, value: S) {
    label = Text(titleKey)
    content = Text(value)
  }
}

public struct GroupBox<Label: View, Content: View>: View {
  let label: Label, content: Content
  public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.label = label()
    self.content = content()
  }
  public typealias Body = Never
  public var body: Never { return fatalError("GroupBox has no body") }
  nonisolated public static func _makeView(view: _GraphValue<GroupBox>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    let box = _PaddingNode(insets: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8), environment: inputs.environment,
                           children: [_makeNode(v.content, inputs: inputs.named("content"))])
    let bg = _ShapeNode(shape: RoundedRectangle(cornerRadius: 6), paint: _Paint(r: 0, g: 0, b: 0, a: 0.05), eoFill: false,
                        stroke: nil, environment: inputs.environment)
    var children: [_ViewNode] = []
    if Label.self != EmptyView.self { children.append(_makeNode(v.label, inputs: inputs.named("label"))) }
    children.append(_LayeredNode(primary: box, layer: bg, alignment: .center, behind: true, environment: inputs.environment))
    return _ViewOutputs(_StackNode(axis: .vertical, alignment: Alignment(horizontal: .leading, vertical: .center),
                                   spacing: 4, environment: inputs.environment, children: children))
  }
}
extension GroupBox where Label == Text {
  public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
    self.init(content: content, label: { Text(titleKey) })
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
    self.init(content: content, label: { Text(title) })
  }
}
extension GroupBox where Label == EmptyView {
  public init(@ViewBuilder content: () -> Content) { self.init(content: content, label: { EmptyView() }) }
}

public struct Form<Content: View>: View {
  let content: Content
  public init(@ViewBuilder content: () -> Content) { self.content = content() }
  public typealias Body = Never
  public var body: Never { return fatalError("Form has no body") }
  nonisolated public static func _makeView(view: _GraphValue<Form>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    let stack = _StackNode(axis: .vertical, alignment: Alignment(horizontal: .leading, vertical: .center), spacing: 12,
                           environment: inputs.environment, children: _makeNodes(v.content, inputs: inputs.named("content")))
    let padded = _PaddingNode(insets: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
                              environment: inputs.environment, children: [stack])
    // As on macOS, a form scrolls vertically, filling its space with its
    // rows from the top and as wide as the form.
    return _ViewOutputs(_ScrollNode(axes: .vertical, key: inputs.base.path + "#form", context: inputs.base.context,
                                    content: _FillWidthNode(content: padded, environment: inputs.environment),
                                    environment: inputs.environment))
  }
}
public protocol FormStyle {}
public struct GroupedFormStyle: FormStyle { public init() {} }
public struct ColumnsFormStyle: FormStyle { public init() {} }
extension FormStyle where Self == GroupedFormStyle { public static var grouped: GroupedFormStyle { return .init() } }
extension FormStyle where Self == ColumnsFormStyle { public static var columns: ColumnsFormStyle { return .init() } }
extension View {
  /// Grouped forms put each control row's label on the left and the
  /// control on the right, as macOS settings do.
  public func formStyle<S: FormStyle>(_ style: S) -> some View {
    return environment(\._formGrouped, style is GroupedFormStyle)
  }
}

public struct ControlGroup<Content: View>: View {
  let content: Content
  public init(@ViewBuilder content: () -> Content) { self.content = content() }
  public typealias Body = Never
  public var body: Never { return fatalError("ControlGroup has no body") }
  nonisolated public static func _makeView(view: _GraphValue<ControlGroup>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    return _ViewOutputs(_StackNode(axis: .horizontal, alignment: .center, spacing: 2, environment: inputs.environment,
                                   children: _makeNodes(v.content, inputs: inputs.named("content"))))
  }
}
public protocol ControlGroupStyle {}
public struct NavigationControlGroupStyle: ControlGroupStyle { public init() {} }
public struct AutomaticControlGroupStyle: ControlGroupStyle { public init() {} }
extension ControlGroupStyle where Self == NavigationControlGroupStyle {
  public static var navigation: NavigationControlGroupStyle { return .init() }
}
extension ControlGroupStyle where Self == AutomaticControlGroupStyle {
  public static var automatic: AutomaticControlGroupStyle { return .init() }
}
extension View {
  public func controlGroupStyle<S: ControlGroupStyle>(_ style: S) -> some View { return self }
}

public struct ContentUnavailableView<Label: View, Description: View, Actions: View>: View {
  let label: Label, description: Description, actions: Actions
  public init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description = { EmptyView() },
              @ViewBuilder actions: () -> Actions = { EmptyView() }) {
    self.label = label()
    self.description = description()
    self.actions = actions()
  }
  public typealias Body = Never
  public var body: Never { return fatalError("ContentUnavailableView has no body") }
  nonisolated public static func _makeView(view: _GraphValue<ContentUnavailableView>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    var title = inputs
    title.environment.font = .title2.bold()
    title.environment.multilineTextAlignment = .center
    var secondary = inputs
    secondary.environment._foregroundStyle = AnyShapeStyle(HierarchicalShapeStyle.secondary)
    // The description's lines are centred under the title, as on macOS.
    secondary.environment.multilineTextAlignment = .center
    let children = [_makeNode(v.label, inputs: title.named("label")),
                    _makeNode(v.description, inputs: secondary.named("description")),
                    _makeNode(v.actions, inputs: inputs.named("actions"))]
    return _ViewOutputs(_StackNode(axis: .vertical, alignment: .center, spacing: 8, environment: inputs.environment,
                                   children: children))
  }
}
extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
  public init(_ title: LocalizedStringKey, systemImage name: String, description: Text? = nil) {
    self.init(label: { SwiftUI.Label(title, systemImage: name) }, description: { description }, actions: { EmptyView() })
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, systemImage name: String, description: Text? = nil) {
    self.init(label: { SwiftUI.Label(title, systemImage: name) }, description: { description }, actions: { EmptyView() })
  }
}

// MARK: - controls

/// A node that handles clicks itself (with the click point).
internal class _ControlNode: _ViewNode {
  var onTap: ((CGPoint) -> Void)?
  var onDrag: ((CGPoint, CGPoint, Bool) -> Void)?
  override var handlesTaps: Bool { return environment.isEnabled && (onTap != nil || onDrag != nil) }
  /// Controls and gestures inside take the click first, as in SwiftUI (a
  /// container's tap gesture does not swallow its buttons' clicks).
  override func hit(_ point: CGPoint) -> _ViewNode? {
    guard frame._contains(point) else { return nil }
    if let inner = super.hit(point), inner !== self { return inner }
    guard handlesTaps else { return nil }
    // A control drawing itself takes its frame; a gesture on content takes
    // only the points where that content draws (or has a content shape).
    if children.isEmpty { return self }
    return children.contains { $0.hitsContent(point) } ? self : nil
  }
  var tapPoint = CGPoint(x: 0, y: 0)
  override func tap() { onTap?(tapPoint) }
  override func press(at p: CGPoint) { tapPoint = p }
  override func drag(from start: CGPoint, to p: CGPoint, ended: Bool) -> Bool {
    guard let d = onDrag else { return false }
    d(start, p, ended)
    return true
  }
}

public struct Toggle<Label: View>: View {
  let isOn: Binding<Bool>
  let label: Label
  public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
    self.isOn = isOn
    self.label = label()
  }
  public typealias Body = Never
  public var body: Never { return fatalError("Toggle has no body") }
  nonisolated public static func _makeView(view: _GraphValue<Toggle>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    let on = v.isOn.wrappedValue
    let isSwitch = inputs.environment._toggleStyle == .switch
    let mark = _ControlNode(environment: inputs.environment, children: [
      _ToggleMarkNode(on: on, isSwitch: isSwitch, environment: inputs.environment),
    ])
    let sized = _FrameNode(minW: isSwitch ? 32 : 14, idealW: isSwitch ? 32 : 14, maxW: isSwitch ? 32 : 14,
                           minH: isSwitch ? 16 : 14, idealH: isSwitch ? 16 : 14, maxH: isSwitch ? 16 : 14, alignment: .center, environment: inputs.environment, children: [mark])
    let binding = v.isOn
    let row = _ControlNode(environment: inputs.environment, children: [
      _StackNode(axis: .horizontal, alignment: .center, spacing: 6, environment: inputs.environment,
                 children: inputs.environment._labelsHidden ? [sized]
                   : isSwitch ? [_makeNode(v.label, inputs: inputs.named("label")),
                                 _SpacerNode(minLength: 8, environment: inputs.environment), sized]
                              : [sized, _makeNode(v.label, inputs: inputs.named("label"))]),
    ])
    row.onTap = { _ in binding.wrappedValue.toggle() }
    return _ViewOutputs(row)
  }
}
extension Toggle where Label == Text {
  public init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) {
    self.init(isOn: isOn) { Text(titleKey) }
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) {
    self.init(isOn: isOn) { Text(title) }
  }
}
/// A toggle's mark as macOS draws it: a switch is a track with a white
/// knob at the end it is set to; a checkbox is a box with a check when on.
internal final class _ToggleMarkNode: _ViewNode {
  let on: Bool, isSwitch: Bool
  init(on: Bool, isSwitch: Bool, environment: EnvironmentValues) {
    self.on = on
    self.isSwitch = isSwitch
    super.init(environment: environment)
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    return CGSize(width: proposal.width ?? (isSwitch ? 32 : 14), height: proposal.height ?? (isSwitch ? 16 : 14))
  }
  /// The switch or box it draws is what a click lands on.
  override func hitsContent(_ point: CGPoint) -> Bool { return frame._contains(point) }
  override func draw(_ context: CGContext) {
    let f = frame
    let accent = Color.accentColor.resolve(in: environment).paint
    // Off: a grey track (switch) or a light box (checkbox), each with a
    // thin edge, as AppKit draws them in light and dark appearances.
    let dark = environment.colorScheme == .dark
    let off = dark ? _Paint(r: 0.32, g: 0.32, b: 0.33, a: 1) : _Paint(r: 0.82, g: 0.82, b: 0.83, a: 1)
    let edge = dark ? _Paint(r: 1, g: 1, b: 1, a: 0.12) : _Paint(r: 0, g: 0, b: 0, a: 0.14)
    if isSwitch {
      let r = f._height / 2
      (on ? accent : off).fill(CGPathCreateWithRoundedRect(f, r, r, nil), in: context)
      if !on { edge.stroke(CGPathCreateWithRoundedRect(f, r, r, nil), in: context, width: 0.5) }
      let d = f._height - 2
      let knob = CGRect(_x: on ? f._maxX - d - 1 : f._minX + 1, y: f._minY + 1, width: d, height: d)
      _Paint(r: 1, g: 1, b: 1, a: 1).fill(CGPathCreateWithEllipseInRect(knob, nil), in: context)
      _Paint(r: 0, g: 0, b: 0, a: 0.12).stroke(CGPathCreateWithEllipseInRect(knob, nil), in: context, width: 0.5)
    } else {
      let box = dark ? _Paint(r: 0.24, g: 0.24, b: 0.25, a: 1) : _Paint(r: 1, g: 1, b: 1, a: 1)
      (on ? accent : box).fill(CGPathCreateWithRoundedRect(f, 3, 3, nil), in: context)
      guard on else {
        let border = dark ? _Paint(r: 1, g: 1, b: 1, a: 0.25) : _Paint(r: 0, g: 0, b: 0, a: 0.28)
        border.stroke(CGPathCreateWithRoundedRect(f, 3, 3, nil), in: context, width: 0.75)
        return
      }
      let check = CGPathCreateMutable()
      CGPathMoveToPoint(check, nil, f._minX + f._width * 0.25, f._minY + f._height * 0.52)
      CGPathAddLineToPoint(check, nil, f._minX + f._width * 0.43, f._minY + f._height * 0.72)
      CGPathAddLineToPoint(check, nil, f._minX + f._width * 0.76, f._minY + f._height * 0.3)
      _Paint(r: 1, g: 1, b: 1, a: 1).stroke(check, in: context, width: 1.8)
    }
  }
}
internal enum _ToggleAppearance { case automatic, `switch`, checkbox, button }
struct _ToggleStyleKey: EnvironmentKey { static let defaultValue = _ToggleAppearance.automatic }
extension EnvironmentValues {
  internal var _toggleStyle: _ToggleAppearance {
    get { return self[_ToggleStyleKey.self] }
    set { self[_ToggleStyleKey.self] = newValue }
  }
}
public protocol ToggleStyle {}
public struct SwitchToggleStyle: ToggleStyle { public init() {} }
public struct CheckboxToggleStyle: ToggleStyle { public init() {} }
public struct ButtonToggleStyle: ToggleStyle { public init() {} }
public struct DefaultToggleStyle: ToggleStyle { public init() {} }
extension ToggleStyle where Self == SwitchToggleStyle { public static var `switch`: SwitchToggleStyle { return .init() } }
extension ToggleStyle where Self == CheckboxToggleStyle { public static var checkbox: CheckboxToggleStyle { return .init() } }
extension ToggleStyle where Self == ButtonToggleStyle { public static var button: ButtonToggleStyle { return .init() } }
extension ToggleStyle where Self == DefaultToggleStyle { public static var automatic: DefaultToggleStyle { return .init() } }
extension View {
  public func toggleStyle<S: ToggleStyle>(_ style: S) -> some View {
    let a: _ToggleAppearance = style is SwitchToggleStyle ? .switch : style is ButtonToggleStyle ? .button
      : style is CheckboxToggleStyle ? .checkbox : .automatic
    return environment(\._toggleStyle, a)
  }
}

public struct Slider<Label: View, ValueLabel: View>: View {
  let fraction: Double
  let set: (Double) -> Void
  let editing: (Bool) -> Void
  public typealias Body = Never
  public var body: Never { return fatalError("Slider has no body") }
  nonisolated public static func _makeView(view: _GraphValue<Slider>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    let node = _SliderNode(fraction: v.fraction, environment: inputs.environment)
    node.onDrag = { start, p, ended in
      let f = Double(max(0, min(1, (p.x - node.frame._minX) / max(1, node.frame._width))))
      if !ended { v.editing(true) }
      v.set(f)
      if ended { v.editing(false) }
    }
    node.onTap = { p in v.set(Double(max(0, min(1, (p.x - node.frame._minX) / max(1, node.frame._width))))) }
    return _ViewOutputs(node)
  }
}
extension Slider {
  public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, step: V.Stride = 1,
                                      onEditingChanged: @escaping (Bool) -> Void = { _ in },
                                      minimumValueLabel: ValueLabel, maximumValueLabel: ValueLabel,
                                      @ViewBuilder label: () -> Label) where V.Stride: BinaryFloatingPoint {
    self.init(value: value, in: bounds, step: step, onEditingChanged: onEditingChanged)
  }
  public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, step: V.Stride = 1,
                                      onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
    let lo = Double(bounds.lowerBound), hi = Double(bounds.upperBound), st = Double(step)
    fraction = hi > lo ? (Double(value.wrappedValue) - lo) / (hi - lo) : 0
    set = { f in
      var x = lo + f * (hi - lo)
      if st > 0 { x = lo + ((x - lo) / st).rounded() * st }
      value.wrappedValue = V(x)
    }
    editing = onEditingChanged
  }
}
extension Slider where ValueLabel == EmptyView {
  public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, step: V.Stride = 1,
                                      onEditingChanged: @escaping (Bool) -> Void = { _ in },
                                      @ViewBuilder label: () -> Label) where V.Stride: BinaryFloatingPoint {
    self.init(value: value, in: bounds, step: step, onEditingChanged: onEditingChanged)
  }
  public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1,
                                      onEditingChanged: @escaping (Bool) -> Void = { _ in },
                                      @ViewBuilder label: () -> Label) where V.Stride: BinaryFloatingPoint {
    self.init(value: value, in: bounds, onEditingChanged: onEditingChanged)
  }
  public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1,
                                      onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
    let lo = Double(bounds.lowerBound), hi = Double(bounds.upperBound)
    fraction = hi > lo ? (Double(value.wrappedValue) - lo) / (hi - lo) : 0
    set = { f in value.wrappedValue = V(lo + f * (hi - lo)) }
    editing = onEditingChanged
  }
}
internal final class _SliderNode: _ControlNode {
  let fraction: Double
  init(fraction: Double, environment: EnvironmentValues) {
    self.fraction = max(0, min(1, fraction))
    super.init(environment: environment)
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    return CGSize(width: proposal.width ?? 120, height: 20)
  }
  override func draw(_ context: CGContext) {
    let track = CGRect(_x: frame._minX, y: frame._minY + 8, width: frame._width, height: 4)
    _Paint(r: 0.8, g: 0.8, b: 0.8, a: 1).fill(CGPathCreateWithRoundedRect(track, 2, 2, nil), in: context)
    let done = CGRect(_x: frame._minX, y: frame._minY + 8, width: frame._width * CGFloat(fraction), height: 4)
    Color.accentColor.resolve(in: environment).paint.fill(CGPathCreateWithRoundedRect(done, 2, 2, nil), in: context)
    let knob = CGRect(_x: frame._minX + frame._width * CGFloat(fraction) - 8, y: frame._minY + 2, width: 16, height: 16)
    _Paint(r: 1, g: 1, b: 1, a: 1).fill(CGPathCreateWithEllipseInRect(knob, nil), in: context)
    _Paint(r: 0, g: 0, b: 0, a: 0.25).stroke(CGPathCreateWithEllipseInRect(knob, nil), in: context, width: 1)
  }
}

public struct Stepper<Label: View>: View {
  let label: Label
  let increment: (() -> Void)?, decrement: (() -> Void)?
  public init(@ViewBuilder label: () -> Label, onIncrement: (() -> Void)?, onDecrement: (() -> Void)?,
              onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
    self.label = label()
    increment = onIncrement
    decrement = onDecrement
  }
  public typealias Body = Never
  public var body: Never { return fatalError("Stepper has no body") }
  nonisolated public static func _makeView(view: _GraphValue<Stepper>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    func button(_ s: String, _ a: (() -> Void)?) -> _ViewNode {
      let b = _ButtonNode(label: _TextNode(string: s, font: .body, paint: ForegroundStyle()._paint(in: inputs.environment),
                                           environment: inputs.environment),
                          action: { a?() }, style: .bordered, environment: inputs.environment)
      return b
    }
    return _ViewOutputs(_StackNode(axis: .horizontal, alignment: .center, spacing: 4, environment: inputs.environment,
                                   children: (inputs.environment._labelsHidden ? [] : [_makeNode(v.label, inputs: inputs.named("label"))]) +
                                             [button("−", v.decrement), button("+", v.increment)]))
  }
}
extension Stepper where Label == Text {
  public init<S: StringProtocol>(_ title: S, onIncrement: (() -> Void)?, onDecrement: (() -> Void)?,
                                 onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
    self.init(label: { Text(title) }, onIncrement: onIncrement, onDecrement: onDecrement, onEditingChanged: onEditingChanged)
  }
  public init<V: Strideable>(_ titleKey: LocalizedStringKey, value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1,
                             onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
    self.init(label: { Text(titleKey) }, onIncrement: {
      let n = value.wrappedValue.advanced(by: step)
      if n <= bounds.upperBound { value.wrappedValue = n }
    }, onDecrement: {
      let n = value.wrappedValue.advanced(by: -step)
      if n >= bounds.lowerBound { value.wrappedValue = n }
    }, onEditingChanged: onEditingChanged)
  }
}

/// Picker: the option whose tag matches the selection is shown (menu
/// style, clicking cycles through the options) or highlighted (segmented,
/// clicking picks one).
public struct Picker<Label: View, SelectionValue: Hashable, Content: View>: View {
  let selection: Binding<SelectionValue>
  let label: Label
  let content: Content
  public init(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.selection = selection
    self.content = content()
    self.label = label()
  }
  public typealias Body = Never
  public var body: Never { return fatalError("Picker has no body") }
  nonisolated public static func _makeView(view: _GraphValue<Picker>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    // Sections' options are the picker's options (their headers title
    // groups of a menu; here they are left out).
    // The menu's layout: dividers become separators and sections' headers
    // titles over their options.
    var layout: [_PickerMenuEntry] = []
    func flatten(_ nodes: [_ViewNode]) -> [_ViewNode] {
      return nodes.flatMap { n -> [_ViewNode] in
        if let stack = n as? _StackNode, let items = stack.sectionItems {
          if stack.children.count > items.count, let first = stack.children.first, !items.contains(where: { $0 === first }),
             let title = _firstText(in: first) {
            if !layout.isEmpty { layout.append(.separator) }
            layout.append(.header(title))
          }
          return flatten(items)
        }
        if n is _DividerNode { layout.append(.separator); return [n] }
        layout.append(.option(n))
        return [n]
      }
    }
    let options = flatten(_makeNodes(v.content, inputs: inputs.named("options")))
    if _debugTree { _dbg("bitten: picker of \(SelectionValue.self): \(options.count) options from \(Content.self)") }
    func tag(_ n: _ViewNode) -> SelectionValue? {
      if case .tagged(let t)? = n.layoutValues[ObjectIdentifier(TagValueTraitKey<SelectionValue>.self)]
        as? TagValueTraitKey<SelectionValue>.Value { return t }
      return nil
    }
    let current = v.selection.wrappedValue
    let binding = v.selection
    if inputs.environment._pickerStyle == .segmented {
      var segs: [_ViewNode] = []
      for o in options {
        let t = tag(o)
        let selected = t == current
        let seg = _ControlNode(environment: inputs.environment, children: [
          _PaddingNode(insets: EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8), environment: inputs.environment,
                       children: [o]),
        ])
        if let t = t { seg.onTap = { _ in binding.wrappedValue = t } }
        let bg = _ShapeNode(shape: RoundedRectangle(cornerRadius: 5),
                            paint: selected ? _Paint(r: 1, g: 1, b: 1, a: 1) : _Paint(r: 0, g: 0, b: 0, a: 0.06),
                            eoFill: false, stroke: nil, environment: inputs.environment)
        segs.append(_LayeredNode(primary: seg, layer: bg, alignment: .center, behind: true, environment: inputs.environment))
      }
      return _ViewOutputs(_StackNode(axis: .horizontal, alignment: .center, spacing: 1, environment: inputs.environment,
                                     children: segs))
    }
    let shown = options.first { tag($0) == current } ?? options.first ?? _EmptyNode(environment: inputs.environment)
    let tags = options.compactMap(tag)
    var entries: [_PickerMenuItem] = []
    var optionIndex = 0
    for e in layout {
      switch e {
      case .separator: if !entries.isEmpty { entries.append(.separator) }
      case .header(let t): entries.append(.header(t))
      case .option(let n):
        guard tag(n) != nil else { continue }
        entries.append(.option(_firstText(in: n) ?? "", optionIndex))
        optionIndex += 1
      }
    }
    let anchor = _WeakNode()
    // Weakly: the button is in the host's own tree.
    let host = inputs.base.context.hostView
    let menu = _ButtonNode(label: shown, action: { [weak host] in
      guard !tags.isEmpty else { return }
      let i = tags.firstIndex(of: binding.wrappedValue)
      // A menu of the options over the picker, the current one checked
      // and placed where the picker is (as macOS pops menus up).
      if let host = host, let node = anchor.node {
        _PickerMenuTarget.show(entries, selected: i, at: node.frame, in: host) { k in binding.wrappedValue = tags[k] }
        return
      }
      binding.wrappedValue = tags[((i ?? -1) + 1) % tags.count]
    }, style: .bordered, environment: inputs.environment)
    anchor.node = menu
    var children: [_ViewNode] = []
    if Label.self != EmptyView.self && !inputs.environment._labelsHidden {
      children.append(_makeNode(v.label, inputs: inputs.named("label")))
      if inputs.environment._formGrouped { children.append(_SpacerNode(minLength: 8, environment: inputs.environment)) }
    }
    children.append(menu)
    return _ViewOutputs(_StackNode(axis: .horizontal, alignment: .center, spacing: 6, environment: inputs.environment,
                                   children: children))
  }
}
extension Picker where Label == Text {
  public init(_ titleKey: LocalizedStringKey, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
    self.init(selection: selection, content: content, label: { Text(titleKey) })
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
    self.init(selection: selection, content: content, label: { Text(title) })
  }
}
/// The first text in a view tree (a picker option's title).
internal func _firstText(in node: _ViewNode) -> String? {
  if let t = node as? _TextNode { return t.string }
  for c in node.children { if let s = _firstText(in: c) { return s } }
  return nil
}
internal final class _WeakNode { weak var node: _ViewNode? }

/// Shows a picker's options as a pop-up menu and reports the chosen one.
final class _PickerMenuTarget: NSObject {
  let choose: (Int) -> Void
  init(_ choose: @escaping (Int) -> Void) { self.choose = choose }
  @objc(choosePickerItem:) func choosePickerItem(_ sender: NSMenuItem) {
    MainActor.assumeIsolated { choose(sender.tag) }
  }
  /// The menu in use keeps its target (menu items hold theirs weakly).
  nonisolated(unsafe) static var current: _PickerMenuTarget?
  static func show(_ entries: [_PickerMenuItem], selected: Int?, at rect: CGRect, in view: NSView,
                   choose: @escaping (Int) -> Void) {
    let target = _PickerMenuTarget(choose)
    current = target
    let menu = NSMenu(title: "")
    var selectedItem: NSMenuItem?
    for e in entries {
      switch e {
      case .separator:
        menu.addItem(NSMenuItem.separator())
      case .header(let title):
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
      case .option(let title, let k):
        let item = NSMenuItem(title: title, action: #selector(_PickerMenuTarget.choosePickerItem(_:)), keyEquivalent: "")
        item.target = target
        item.tag = k
        if k == selected {
          item.state = 1  // on
          selectedItem = item
        }
        menu.addItem(item)
      }
    }
    let item = selectedItem
    _ = menu.popUp(positioning: item, at: NSMakePoint(rect.origin.x, rect.origin.y), in: view)
  }
}

/// What a picker's content lays out in its menu.
internal enum _PickerMenuEntry { case option(_ViewNode), separator, header(String) }
/// A picker menu's items: options (their index among the options),
/// separators and section titles.
internal enum _PickerMenuItem { case option(String, Int), separator, header(String) }

internal enum _PickerAppearance { case automatic, menu, segmented, inline, radioGroup }
struct _PickerStyleKey: EnvironmentKey { static let defaultValue = _PickerAppearance.automatic }
extension EnvironmentValues {
  internal var _pickerStyle: _PickerAppearance {
    get { return self[_PickerStyleKey.self] }
    set { self[_PickerStyleKey.self] = newValue }
  }
}
public protocol PickerStyle {}
public struct MenuPickerStyle: PickerStyle { public init() {} }
public struct SegmentedPickerStyle: PickerStyle { public init() {} }
public struct InlinePickerStyle: PickerStyle { public init() {} }
public struct RadioGroupPickerStyle: PickerStyle { public init() {} }
public struct DefaultPickerStyle: PickerStyle { public init() {} }
extension PickerStyle where Self == MenuPickerStyle { public static var menu: MenuPickerStyle { return .init() } }
extension PickerStyle where Self == SegmentedPickerStyle { public static var segmented: SegmentedPickerStyle { return .init() } }
extension PickerStyle where Self == InlinePickerStyle { public static var inline: InlinePickerStyle { return .init() } }
extension PickerStyle where Self == RadioGroupPickerStyle { public static var radioGroup: RadioGroupPickerStyle { return .init() } }
extension PickerStyle where Self == DefaultPickerStyle { public static var automatic: DefaultPickerStyle { return .init() } }
extension View {
  public func pickerStyle<S: PickerStyle>(_ style: S) -> some View {
    let a: _PickerAppearance = style is SegmentedPickerStyle ? .segmented : style is MenuPickerStyle ? .menu
      : style is InlinePickerStyle ? .inline : style is RadioGroupPickerStyle ? .radioGroup : .automatic
    return environment(\._pickerStyle, a)
  }
}

public struct Menu<Label: View, Content: View>: View {
  let label: Label, content: Content
  public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.content = content()
    self.label = label()
  }
  public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label, primaryAction: @escaping () -> Void) {
    self.init(content: content, label: label)
  }
  public typealias Body = Never
  public var body: Never { return fatalError("Menu has no body") }
  nonisolated public static func _makeView(view: _GraphValue<Menu>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    let items = _menuItems(v.content)
    let button = _ButtonNode(label: _makeNode(v.label, inputs: inputs.named("label")), action: {
      // A pop-up menu: the first item's action stands in for choosing one.
      items.first(where: { !$0.isSeparator })?.action?()
    }, style: inputs.environment._buttonStyle, environment: inputs.environment)
    return _ViewOutputs(button)
  }
  public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) where Label == Text {
    self.init(content: content, label: { Text(title) })
  }
  public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) where Label == Text {
    self.init(content: content, label: { Text(titleKey) })
  }
}
public protocol MenuStyle {}
public struct ButtonMenuStyle: MenuStyle { public init() {} }
public struct BorderlessButtonMenuStyle: MenuStyle { public init() {} }
public struct DefaultMenuStyle: MenuStyle { public init() {} }
extension MenuStyle where Self == ButtonMenuStyle { public static var button: ButtonMenuStyle { return .init() } }
extension MenuStyle where Self == BorderlessButtonMenuStyle {
  public static var borderlessButton: BorderlessButtonMenuStyle { return .init() }
}
extension MenuStyle where Self == DefaultMenuStyle { public static var automatic: DefaultMenuStyle { return .init() } }
extension View {
  public func menuStyle<S: MenuStyle>(_ style: S) -> some View { return self }
  public func menuIndicator(_ visibility: Visibility) -> some View { return environment(\.menuIndicatorVisibility, visibility) }
}

// MARK: - text fields

public struct TextField<Label: View>: View {
  let text: Binding<String>
  let label: Label
  let prompt: String
  let editing: (Bool) -> Void
  public typealias Body = Never
  public var body: Never { return fatalError("TextField has no body") }
  nonisolated public static func _makeView(view: _GraphValue<TextField>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    let focus = inputs.environment._focus
    let node = _TextFieldNode(text: v.text, prompt: v.prompt, font: inputs.environment.font ?? .body,
                              focus: focus, environment: inputs.environment)
    node.onSubmit = inputs.environment._onSubmit
    return _ViewOutputs(node)
  }
}
extension TextField where Label == Text {
  public init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
    self.text = text
    label = Text(titleKey)
    prompt = Text(titleKey)._string
    editing = { _ in }
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, text: Binding<String>) {
    self.text = text
    label = Text(title)
    prompt = String(title)
    editing = { _ in }
  }
  public init(_ titleKey: LocalizedStringKey, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void,
              onCommit: @escaping () -> Void = {}) {
    self.text = text
    label = Text(titleKey)
    prompt = Text(titleKey)._string
    editing = onEditingChanged
  }
  public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) {
    self.text = text
    label = Text(titleKey)
    self.prompt = prompt?._string ?? Text(titleKey)._string
    editing = { _ in }
  }
}

/// Typing goes to the text field that has keyboard focus.
internal final class _TextFieldNode: _ControlNode {
  let text: Binding<String>
  let prompt: String
  let font: Font
  let focus: _FocusTarget?
  var onSubmit: (() -> Void)?
  init(text: Binding<String>, prompt: String, font: Font, focus: _FocusTarget?, environment: EnvironmentValues) {
    self.text = text
    self.prompt = prompt
    self.font = font
    self.focus = focus
    super.init(environment: environment)
    onTap = { [unowned self] _ in _KeyboardFocus.current = self; self.focus?.set(true) }
  }
  var isFocused: Bool { return _KeyboardFocus.current === self || focus?.isFocused == true }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    return CGSize(width: proposal.width ?? 160, height: _TextRenderer.metrics(font).lineHeight + 8)
  }
  override func draw(_ context: CGContext) {
    let box = CGPathCreateWithRoundedRect(frame, 4, 4, nil)
    _Paint(r: 1, g: 1, b: 1, a: 1).fill(box, in: context)
    (isFocused ? Color.accentColor.resolve(in: environment).paint : _Paint(r: 0, g: 0, b: 0, a: 0.2))
      .stroke(box, in: context, width: 1)
    let s = text.wrappedValue
    let paint = s.isEmpty ? _Paint(r: 0, g: 0, b: 0, a: 0.35) : ForegroundStyle()._paint(in: environment)
    _TextRenderer.draw(s.isEmpty ? prompt : s, font: font, paint: paint, at: CGPoint(x: frame._minX + 6, y: frame._minY + 4),
                       lineHeight: _TextRenderer.metrics(font).lineHeight, in: context)
    if isFocused {
      let x = frame._minX + 6 + _TextRenderer.width(s, font: font)
      _Paint(r: 0, g: 0, b: 0, a: 0.8).fill(CGPathCreateWithRect(CGRect(_x: x, y: frame._minY + 4, width: 1,
                                                                           height: frame._height - 8), nil), in: context)
    }
  }
  override func key(_ characters: String, keyCode: UInt16) -> Bool {
    guard isFocused else { return false }
    switch keyCode {
    case 51: if !text.wrappedValue.isEmpty { text.wrappedValue.removeLast() }
    case 36, 76: onSubmit?()
    case 53: _KeyboardFocus.current = nil
    default:
      let printable = characters.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 && ($0.value < 0xF700 || $0.value > 0xF8FF) }
      text.wrappedValue += String(String.UnicodeScalarView(printable))
    }
    return true
  }
}

enum _KeyboardFocus {
  nonisolated(unsafe) static weak var current: _ViewNode?
}

public struct RoundedBorderTextFieldStyle: TextFieldStyle { public init() {} }
public struct PlainTextFieldStyle: TextFieldStyle { public init() {} }
public struct DefaultTextFieldStyle: TextFieldStyle { public init() {} }
public protocol TextFieldStyle {}
extension TextFieldStyle where Self == RoundedBorderTextFieldStyle {
  public static var roundedBorder: RoundedBorderTextFieldStyle { return .init() }
}
extension TextFieldStyle where Self == PlainTextFieldStyle { public static var plain: PlainTextFieldStyle { return .init() } }
extension TextFieldStyle where Self == DefaultTextFieldStyle { public static var automatic: DefaultTextFieldStyle { return .init() } }
extension View {
  public func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View { return self }
  public func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping () -> Void) -> some View {
    return environment(\._onSubmit, action)
  }
}
public struct SubmitTriggers: OptionSet, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let text = SubmitTriggers(rawValue: 1)
  public static let search = SubmitTriggers(rawValue: 2)
}
struct _OnSubmitKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
struct _FocusKey: EnvironmentKey { static let defaultValue: _FocusTarget? = nil }
extension EnvironmentValues {
  internal var _onSubmit: (() -> Void)? {
    get { return self[_OnSubmitKey.self] }
    set { self[_OnSubmitKey.self] = newValue }
  }
  internal var _focus: _FocusTarget? {
    get { return self[_FocusKey.self] }
    set { self[_FocusKey.self] = newValue }
  }
}

// MARK: - focus

/// The field `.focused(...)` ties to a focus state.
final class _FocusTarget {
  let isFocusedGet: () -> Bool
  let set: (Bool) -> Void
  init(isFocused: @escaping () -> Bool, set: @escaping (Bool) -> Void) {
    isFocusedGet = isFocused
    self.set = set
  }
  var isFocused: Bool { return isFocusedGet() }
}

@frozen @propertyWrapper
public struct FocusState<Value: Hashable>: DynamicProperty {
  // Apple's layout: the value, its location (once installed), the value it
  // resets to.
  @usableFromInline internal var _value: Value
  @usableFromInline internal var _box: _FocusBox<Value>?
  @usableFromInline internal var _reset: Value

  /// As in Apple's SDK, a focus binding wraps a SwiftUI Binding (programs
  /// read its words directly: transaction, location, value).
  @propertyWrapper @frozen
  public struct Binding {
    @usableFromInline internal var binding: SwiftUI.Binding<Value>
    @inlinable internal init(binding: SwiftUI.Binding<Value>) { self.binding = binding }
    public var wrappedValue: Value {
      get { return binding.wrappedValue }
      nonmutating set { binding.wrappedValue = newValue }
    }
    public var projectedValue: Binding { return self }
    /// The focus state's storage (or the stand-in a binding was made with).
    internal var _box: _FocusBox<Value> {
      if let box = binding.location as? _FocusBox<Value> { return box }
      return _FocusBox(binding.wrappedValue)
    }
  }
  public var wrappedValue: Value {
    get { return _box?.value ?? _value }
    nonmutating set { _box?.value = newValue }
  }
  public var projectedValue: Binding {
    let box = _box ?? _FocusBox(_value)
    return Binding(binding: SwiftUI.Binding(location: box, transaction: Transaction()))
  }
}
extension FocusState {
  public init() where Value == Bool {
    _value = false
    _box = nil
    _reset = false
  }
  public init<T: Hashable>() where Value == T? {
    _value = nil
    _box = nil
    _reset = nil
  }
}
@usableFromInline
final class _FocusBox<Value>: AnyLocation<Value> {
  var value: Value {
    didSet { if !_bn_sameValue(oldValue, value) { _bn_invalidate(owner) } }
  }
  weak var owner: _RenderContext?
  init(_ v: Value) {
    value = v
    super.init()
  }
  override func get() -> Value { return value }
  override func set(_ newValue: Value, transaction: Transaction) { value = newValue }
}
extension FocusState: _GraphInstallable {
  mutating func _install(key: String, inputs: _ViewInputs) {
    let initial = _value
    let box = inputs.base.context.store(key) { _FocusBox(initial) }
    box.owner = inputs.base.context
    _box = box
  }
}
extension View {
  public func focused(_ condition: FocusState<Bool>.Binding) -> some View {
    let box = condition._box
    return environment(\._focus, _FocusTarget(isFocused: { box.value }, set: { box.value = $0 }))
  }
  public func focused<V: Hashable>(_ binding: FocusState<V>.Binding, equals value: V) -> some View {
    let box = binding._box
    return environment(\._focus, _FocusTarget(isFocused: { box.value == value }, set: { if $0 { box.value = value } }))
  }
  public func focusable(_ isFocusable: Bool = true) -> some View { return self }
  public func focusEffectDisabled(_ disabled: Bool = true) -> some View { return self }
  public func focusedSceneValue<T>(_ keyPath: WritableKeyPath<FocusedValues, T?>, _ value: T) -> some View { return self }
  public func focusedValue<T>(_ keyPath: WritableKeyPath<FocusedValues, T?>, _ value: T) -> some View { return self }
}

// MARK: - progress

public struct ProgressView<Label: View, CurrentValueLabel: View>: View {
  let fraction: Double?
  public typealias Body = Never
  public var body: Never { return fatalError("ProgressView has no body") }
  nonisolated public static func _makeView(view: _GraphValue<ProgressView>, inputs: _ViewInputs) -> _ViewOutputs {
    return _ViewOutputs(_ProgressNode(fraction: view.value.fraction, environment: inputs.environment))
  }
}
extension ProgressView where CurrentValueLabel == EmptyView {
  public init() where Label == EmptyView { fraction = nil }
}
extension ProgressView {
  public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0) where Label == EmptyView, CurrentValueLabel == EmptyView {
    fraction = value.map { total > 0 ? Double($0 / total) : 0 }
  }
}
internal final class _ProgressNode: _ViewNode {
  let fraction: Double?
  init(fraction: Double?, environment: EnvironmentValues) {
    self.fraction = fraction
    super.init(environment: environment)
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    return fraction == nil ? CGSize(width: 20, height: 20) : CGSize(width: proposal.width ?? 160, height: 6)
  }
  override func draw(_ context: CGContext) {
    if let f = fraction {
      _Paint(r: 0, g: 0, b: 0, a: 0.1).fill(CGPathCreateWithRoundedRect(frame, 3, 3, nil), in: context)
      let done = CGRect(_x: frame._minX, y: frame._minY, width: frame._width * CGFloat(max(0, min(1, f))), height: frame._height)
      Color.accentColor.resolve(in: environment).paint.fill(CGPathCreateWithRoundedRect(done, 3, 3, nil), in: context)
    } else {
      _Paint(r: 0, g: 0, b: 0, a: 0.3).stroke(CGPathCreateWithEllipseInRect(frame._insetBy(3), nil), in: context, width: 2)
    }
  }
}
public struct CircularProgressViewStyle: ProgressViewStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View { return EmptyView() }
}
public struct LinearProgressViewStyle: ProgressViewStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View { return EmptyView() }
}
extension ProgressViewStyle where Self == CircularProgressViewStyle {
  public static var circular: CircularProgressViewStyle { return .init() }
}
extension ProgressViewStyle where Self == LinearProgressViewStyle { public static var linear: LinearProgressViewStyle { return .init() } }
extension View {
  public func progressViewStyle<S: ProgressViewStyle>(_ style: S) -> some View { return self }
}

// MARK: - navigation split view

public struct NavigationSplitView<Sidebar: View, Content: View, Detail: View>: View {
  let sidebar: Sidebar, content: Content, detail: Detail
  public typealias Body = Never
  public var body: Never { return fatalError("NavigationSplitView has no body") }
  nonisolated public static func _makeView(view: _GraphValue<NavigationSplitView>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    let side = _FrameNode(minW: 180, idealW: 220, maxW: 220, minH: nil, idealH: nil, maxH: .infinity, alignment: .topLeading,
                          environment: inputs.environment, children: [_makeNode(v.sidebar, inputs: inputs.named("sidebar"))])
    var children: [_ViewNode] = [side, _DividerNode(environment: inputs.environment)]
    if Content.self != EmptyView.self { children.append(_makeNode(v.content, inputs: inputs.named("content"))) }
    let detail = _FrameNode(minW: nil, idealW: nil, maxW: .infinity, minH: nil, idealH: nil, maxH: .infinity,
                            alignment: .center, environment: inputs.environment,
                            children: [_makeNode(v.detail, inputs: inputs.named("detail"))])
    children.append(detail)
    return _ViewOutputs(_StackNode(axis: .horizontal, alignment: .center, spacing: 0, environment: inputs.environment,
                                   children: children))
  }
}
extension NavigationSplitView {
  public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) where Content == EmptyView {
    self.sidebar = sidebar()
    content = EmptyView()
    self.detail = detail()
  }
  public init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content, @ViewBuilder detail: () -> Detail) {
    self.sidebar = sidebar()
    self.content = content()
    self.detail = detail()
  }
}
extension View {
  public func navigationTitle(_ titleKey: LocalizedStringKey) -> some View { return self }
  public func navigationTitle<S: StringProtocol>(_ title: S) -> some View { return self }
  public func navigationTitle(_ title: Text) -> some View { return self }
  public func navigationSubtitle(_ subtitleKey: LocalizedStringKey) -> some View { return self }
  public func navigationSubtitle<S: StringProtocol>(_ subtitle: S) -> some View { return self }
  public func navigationSplitViewColumnWidth(_ width: CGFloat) -> some View { return self }
  public func navigationSplitViewColumnWidth(min: CGFloat? = nil, ideal: CGFloat, max: CGFloat? = nil) -> some View { return self }
}

// MARK: - geometry

public protocol CoordinateSpaceProtocol {}
public struct LocalCoordinateSpace: CoordinateSpaceProtocol { public init() {} }
public struct GlobalCoordinateSpace: CoordinateSpaceProtocol { public init() {} }
public struct NamedCoordinateSpace: CoordinateSpaceProtocol, Equatable {
  let name: AnyHashable
  public static func named<N: Hashable>(_ name: N) -> NamedCoordinateSpace { return NamedCoordinateSpace(name: AnyHashable(name)) }
}
extension CoordinateSpaceProtocol where Self == LocalCoordinateSpace { public static var local: LocalCoordinateSpace { return .init() } }
extension CoordinateSpaceProtocol where Self == GlobalCoordinateSpace { public static var global: GlobalCoordinateSpace { return .init() } }
extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
  public static func named<N: Hashable>(_ name: N) -> NamedCoordinateSpace { return NamedCoordinateSpace(name: AnyHashable(name)) }
}
extension View {
  public func coordinateSpace(_ name: NamedCoordinateSpace) -> some View { return self }
  public func coordinateSpace<T: Hashable>(name: T) -> some View { return self }
}

public struct GeometryProxy {
  let frameInHost: CGRect
  public var size: CGSize { return frameInHost.size }
  public var safeAreaInsets: EdgeInsets { return EdgeInsets() }
  public func frame<S: CoordinateSpaceProtocol>(in space: S) -> CGRect {
    if space is LocalCoordinateSpace { return CGRect(origin: CGPoint(x: 0, y: 0), size: size) }
    return frameInHost
  }
  public func bounds(of space: NamedCoordinateSpace) -> CGRect? { return CGRect(origin: CGPoint(x: 0, y: 0), size: size) }
}

/// Frozen in Apple's SwiftUI: programs get it back from `init(content:)` in
/// registers, not through an indirect result.
@frozen
public struct GeometryReader<Content: View>: View {
  public var content: (GeometryProxy) -> Content
  public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) { self.content = content }
  public typealias Body = Never
  public var body: Never { return fatalError("GeometryReader has no body") }
  nonisolated public static func _makeView(view: _GraphValue<GeometryReader>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    if _debugGraph { _dbg("bitten: geometry reader of \(Content.self)") }
    return _ViewOutputs(_GeometryNode(inputs: inputs.named("geometry"), environment: inputs.environment) { proxy, i in
      _makeNode(v.content(proxy), inputs: i)
    })
  }
}

/// Takes all it is offered and builds its content once its frame is
/// known (content placed at the top leading corner).
internal final class _GeometryNode: _ViewNode {
  let inputs: _ViewInputs
  let make: (GeometryProxy, _ViewInputs) -> _ViewNode
  init(inputs: _ViewInputs, environment: EnvironmentValues, make: @escaping (GeometryProxy, _ViewInputs) -> _ViewNode) {
    self.inputs = inputs
    self.make = make
    super.init(environment: environment)
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { return proposal.replacingUnspecifiedDimensions() }
  override func place(in rect: CGRect) {
    frame = rect
    // The old content stays alive until the new one is placed: placing can
    // run program code that still holds parts of it.
    let previous = children
    let child = make(GeometryProxy(frameInHost: rect), inputs)
    children = [child]
    defer { withExtendedLifetime(previous) {} }
    let s = child.sizeThatFits(ProposedViewSize(rect.size))
    child.place(in: CGRect(origin: rect.origin, size: s))
  }
}

@frozen
public struct _GeometryActionModifier<Value: Equatable>: ViewModifier {
  @usableFromInline var value: (GeometryProxy) -> Value
  @usableFromInline var action: (Value) -> Void
  public init(value: @escaping (GeometryProxy) -> Value, action: @escaping (Value) -> Void) {
    self.value = value
    self.action = action
  }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let m = modifier.value
    let last = inputs.base.context.store(inputs.base.path + "#geo") { _Box<Value?>(nil) }
    let node = _CallbackNode(content: body(_Graph(), inputs).node, environment: inputs.environment)
    node.afterLayout = { n in
      let v = m.value(GeometryProxy(frameInHost: n.frame))
      if last.value != v {
        last.value = v
        DispatchQueue.main.async { m.action(v) }
      }
    }
    return _ViewOutputs(node)
  }
  public func body(content: Content) -> Never { fatalError("no body") }
  public typealias Body = Never
}
extension View {
  public func onGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (GeometryProxy) -> T,
                                             action: @escaping (T) -> Void) -> some View {
    return modifier(_GeometryActionModifier(value: transform, action: action))
  }
  public func onGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (GeometryProxy) -> T,
                                             action: @escaping (T, T) -> Void) -> some View {
    var old: T?
    return modifier(_GeometryActionModifier(value: transform, action: { new in
      action(old ?? new, new)
      old = new
    }))
  }
}

// MARK: - timelines

public protocol TimelineSchedule {
  /// Seconds between updates; nil for none.
  var _interval: Double? { get }
}
public struct PeriodicTimelineSchedule: TimelineSchedule {
  let start: Date, interval: TimeInterval
  public init(from startDate: Date, by interval: TimeInterval) {
    start = startDate
    self.interval = interval
  }
  public var _interval: Double? { return interval }
}
public struct EveryMinuteTimelineSchedule: TimelineSchedule {
  public init() {}
  public var _interval: Double? { return 60 }
}
public struct AnimationTimelineSchedule: TimelineSchedule {
  let minimumInterval: Double?
  let paused: Bool
  public init(minimumInterval: Double? = nil, paused: Bool = false) {
    self.minimumInterval = minimumInterval
    self.paused = paused
  }
  public var _interval: Double? { return paused ? nil : minimumInterval ?? (1.0 / 30) }
}
extension TimelineSchedule where Self == PeriodicTimelineSchedule {
  public static func periodic(from startDate: Date, by interval: TimeInterval) -> PeriodicTimelineSchedule {
    return .init(from: startDate, by: interval)
  }
}
extension TimelineSchedule where Self == EveryMinuteTimelineSchedule { public static var everyMinute: EveryMinuteTimelineSchedule { return .init() } }
extension TimelineSchedule where Self == AnimationTimelineSchedule {
  public static var animation: AnimationTimelineSchedule { return .init() }
  public static func animation(minimumInterval: Double? = nil, paused: Bool = false) -> AnimationTimelineSchedule {
    return .init(minimumInterval: minimumInterval, paused: paused)
  }
}

public struct TimelineView<Schedule: TimelineSchedule, Content> {
  public struct Context {
    public let date: Date
    public enum Cadence: Comparable, Sendable { case live, seconds, minutes }
    public var cadence: Cadence { return .live }
  }
  let schedule: Schedule
  let content: (Context) -> Content
}
extension TimelineView: View where Content: View {
  public typealias Body = Never
  public var body: Never { return fatalError("TimelineView has no body") }
  public init(_ schedule: Schedule, @ViewBuilder content: @escaping (Context) -> Content) {
    self.schedule = schedule
    self.content = content
  }
  nonisolated public static func _makeView(view: _GraphValue<TimelineView>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    // The timer runs while the timeline is in the tree and not paused.
    let context = inputs.base.context, key = inputs.base.path + "#timeline"
    let timer = context.store(key) { _TimelineTimer() }
    timer.run(interval: v.schedule._interval, invalidate: context.invalidate)
    context.lifecycle(key, appear: nil, disappear: { [weak context] in
      timer.run(interval: nil, invalidate: {})
      context?.storage[key] = nil
    })
    return _ViewOutputs(_makeNode(v.content(Context(date: Date())), inputs: inputs.named("timeline")))
  }
}
final class _TimelineTimer {
  var source: DispatchSourceTimer?
  var interval: Double?
  func run(interval: Double?, invalidate: @escaping () -> Void) {
    if source != nil && interval == self.interval { return }
    source?.cancel()
    source = nil
    self.interval = interval
    guard let interval = interval else { return }
    let s = DispatchSource.makeTimerSource(queue: .main)
    s.schedule(deadline: .now() + interval, repeating: interval)
    s.setEventHandler { invalidate() }
    s.resume()
    source = s
  }
  deinit { source?.cancel() }
}

// MARK: - observation helpers

@propertyWrapper @dynamicMemberLookup
public struct Bindable<Value> {
  public var wrappedValue: Value
  public var projectedValue: Bindable<Value> { return self }
  @usableFromInline internal init(_unchecked value: Value) { wrappedValue = value }
}
extension Bindable where Value: AnyObject, Value: Observable {
  public init(wrappedValue: Value) { self.init(_unchecked: wrappedValue) }
  public init(_ wrappedValue: Value) { self.init(_unchecked: wrappedValue) }
  public init(projectedValue: Bindable<Value>) { self = projectedValue }
}
extension Bindable where Value: AnyObject {
  public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject> {
    let root = wrappedValue
    return Binding(get: { root[keyPath: keyPath] }, set: { root[keyPath: keyPath] = $0 })
  }
}

/// A user default, read and written through `UserDefaults`; writes
/// rebuild the views that read it.
@frozen @propertyWrapper
public struct AppStorage<Value>: DynamicProperty {
  @usableFromInline let _location: _AppStorageLocation<Value>
  public var wrappedValue: Value {
    get { return _location.get() }
    nonmutating set { _location.set(newValue) }
  }
  public var projectedValue: Binding<Value> {
    let l = _location
    return Binding(get: { l.get() }, set: { l.set($0) })
  }
}
@usableFromInline
final class _AppStorageLocation<Value> {
  let key: String, store: UserDefaults, dflt: Value
  let read: (UserDefaults, String) -> Value?
  let write: (UserDefaults, String, Value) -> Void
  init(key: String, store: UserDefaults?, dflt: Value, read: @escaping (UserDefaults, String) -> Value?,
       write: @escaping (UserDefaults, String, Value) -> Void) {
    self.key = key
    self.store = store ?? .standard
    self.dflt = dflt
    self.read = read
    self.write = write
  }
  func get() -> Value { return read(store, key) ?? dflt }
  func set(_ v: Value) {
    write(store, key, v)
    _GraphHost.invalidate()
  }
}
extension AppStorage {
  public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Bool {
    _location = _AppStorageLocation(key: key, store: store, dflt: wrappedValue,
                                    read: { $0.object(forKey: $1) == nil ? nil : $0.bool(forKey: $1) },
                                    write: { $0.set($2, forKey: $1) })
  }
  public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Int {
    _location = _AppStorageLocation(key: key, store: store, dflt: wrappedValue,
                                    read: { $0.object(forKey: $1) == nil ? nil : $0.integer(forKey: $1) },
                                    write: { $0.set($2, forKey: $1) })
  }
  public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Double {
    _location = _AppStorageLocation(key: key, store: store, dflt: wrappedValue,
                                    read: { $0.object(forKey: $1) == nil ? nil : $0.double(forKey: $1) },
                                    write: { $0.set($2, forKey: $1) })
  }
  public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == String {
    _location = _AppStorageLocation(key: key, store: store, dflt: wrappedValue, read: { $0.string(forKey: $1) },
                                    write: { $0.set($2, forKey: $1) })
  }
  public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Data {
    _location = _AppStorageLocation(key: key, store: store, dflt: wrappedValue, read: { $0.data(forKey: $1) },
                                    write: { $0.set($2, forKey: $1) })
  }
  public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil)
    where Value: RawRepresentable, Value.RawValue == String {
    _location = _AppStorageLocation(key: key, store: store, dflt: wrappedValue,
                                    read: { $0.string(forKey: $1).flatMap(Value.init(rawValue:)) },
                                    write: { $0.set($2.rawValue, forKey: $1) })
  }
  public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil)
    where Value: RawRepresentable, Value.RawValue == Int {
    _location = _AppStorageLocation(key: key, store: store, dflt: wrappedValue,
                                    read: { $0.object(forKey: $1) == nil ? nil : Value(rawValue: $0.integer(forKey: $1)) },
                                    write: { $0.set($2.rawValue, forKey: $1) })
  }
}

@frozen @propertyWrapper
public struct Namespace: DynamicProperty {
  @usableFromInline var id: Int
  @inlinable public init() { id = 0 }
  @frozen
  public struct ID: Hashable, Sendable {
    @usableFromInline var id: Int
  }
  public var wrappedValue: ID { return ID(id: id) }
}
extension Namespace: _GraphInstallable {
  mutating func _install(key: String, inputs: _ViewInputs) { id = key.hashValue }
}
@frozen
public struct MatchedGeometryProperties: OptionSet, Sendable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  public static let position = MatchedGeometryProperties(rawValue: 1)
  public static let size = MatchedGeometryProperties(rawValue: 2)
  public static let frame: MatchedGeometryProperties = [.position, .size]
}
extension View {
  public func matchedGeometryEffect<ID: Hashable>(id: ID, in namespace: Namespace.ID,
                                                  properties: MatchedGeometryProperties = .frame,
                                                  anchor: UnitPoint = .center, isSource: Bool = true) -> some View {
    return self
  }
}

@frozen
public struct EquatableView<Content: Equatable & View>: View {
  public var content: Content
  @inlinable public init(content: Content) { self.content = content }
  public typealias Body = Never
  public var body: Never { return fatalError("EquatableView has no body") }
  nonisolated public static func _makeView(view: _GraphValue<EquatableView>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    return Content._makeView(view: _GraphValue({ v.content }), inputs: inputs)
  }
}
extension View where Self: Equatable {
  @inlinable public func equatable() -> EquatableView<Self> { return EquatableView(content: self) }
}

/// `.onReceive(publisher)`: the action runs for each value, while the view
/// is in its host.
@frozen
public struct SubscriptionView<PublisherType: Publisher, Content: View>: View where PublisherType.Failure == Never {
  public var content: Content
  public var publisher: PublisherType
  public var action: (PublisherType.Output) -> Void
  @inlinable public init(content: Content, publisher: PublisherType, action: @escaping (PublisherType.Output) -> Void) {
    self.content = content
    self.publisher = publisher
    self.action = action
  }
  public typealias Body = Never
  public var body: Never { return fatalError("SubscriptionView has no body") }
  nonisolated public static func _makeView(view: _GraphValue<SubscriptionView>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    let box = inputs.base.context.store(inputs.base.path + "#sub") { _SubscriptionBox() }
    box.action = { v.action($0 as! PublisherType.Output) }
    if box.cancellable == nil {
      // Weakly: the publisher keeps its subscription, which must not keep
      // the box (and through it the view's action) after the view is gone.
      box.cancellable = v.publisher.sink { [weak box] value in box?.action?(value) }
    }
    return Content._makeView(view: _GraphValue({ v.content }), inputs: inputs.named("content"))
  }
}
final class _SubscriptionBox {
  var cancellable: AnyCancellable?
  var action: ((Any) -> Void)?
}
extension View {
  @inlinable public func onReceive<P: Publisher>(_ publisher: P, perform action: @escaping (P.Output) -> Void) -> some View
    where P.Failure == Never {
    return SubscriptionView(content: self, publisher: publisher, action: action)
  }
}
