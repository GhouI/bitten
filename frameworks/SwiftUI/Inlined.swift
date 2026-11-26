// Types that Apple's inlinable SwiftUI code (compiled into apps) builds
// directly: their stored properties are ABI, laid out as the app's code
// expects. Also tables, attributed-string scopes and smaller additions.

import CoreGraphics
import Foundation
import os
import Symbols

// MARK: - modifiers built by inlined code

/// `onHover(perform:)`.
@frozen
public struct _HoverRegionModifier: ViewModifier {
  public var callback: (Bool) -> Void
  @inlinable public init(_ callback: @escaping (Bool) -> Void) { self.callback = callback }
  public typealias Body = Never
  public func body(content: Content) -> Never { fatalError("no body") }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    return body(_Graph(), inputs)
  }
}

/// `safeAreaInset(edge:alignment:spacing:content:)`: the content placed on
/// one edge of the view, which keeps the rest.
@frozen
public struct _InsetViewModifier<Content: View>: ViewModifier {
  @usableFromInline var content: Content
  @usableFromInline var properties: (regions: SafeAreaRegions, spacing: CGFloat?, edge: Edge, alignmentKey: AlignmentKey)
  @inlinable internal init(content: Content, edge: Edge, regions: SafeAreaRegions, spacing: CGFloat?,
                           alignmentKey: AlignmentKey) {
    self.content = content
    self.properties = (regions, spacing, edge, alignmentKey)
  }
  public typealias Body = Never
  public func body(content: Self.Content) -> Never { fatalError("no body") }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let m = modifier.value
    let main = body(_Graph(), inputs).node
    let inset = _makeNode(m.content, inputs: inputs.named("inset"))
    let spacing = m.properties.spacing ?? 0
    let edge = m.properties.edge
    let vertical = edge == .top || edge == .bottom
    let first = edge == .top || edge == .leading
    let children = first ? [inset, main] : [main, inset]
    return _ViewOutputs(_StackNode(axis: vertical ? .vertical : .horizontal, alignment: .center, spacing: spacing,
                                   environment: inputs.environment, children: children))
  }
}

/// `mask(alignment:_:)`: draws the view where the mask is opaque. Here
/// the mask's frame clips.
/// Alignment first, then the mask: programs build it inline in that order.
@frozen
public struct _MaskAlignmentEffect<Mask: View>: ViewModifier {
  public var alignment: Alignment
  public var mask: Mask
  @inlinable public init(mask: Mask, alignment: Alignment = .center) {
    self.mask = mask
    self.alignment = alignment
  }
  public typealias Body = Never
  public func body(content: Content) -> Never { fatalError("no body") }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    return body(_Graph(), inputs)
  }
}

/// `matchedGeometryEffect(id:in:properties:anchor:isSource:)`; geometry is
/// not shared between views here.
@frozen
public struct _MatchedGeometryEffect<ID: Hashable>: ViewModifier {
  public var id: ID
  public var namespace: Namespace.ID
  public var args: (properties: MatchedGeometryProperties, anchor: UnitPoint, isSource: Bool)
  @inlinable public init(id: ID, namespace: Namespace.ID, properties: MatchedGeometryProperties, anchor: UnitPoint,
                         isSource: Bool) {
    (self.id, self.namespace) = (id, namespace)
    args = (properties: properties, anchor: anchor, isSource: isSource)
  }
  public typealias Body = Never
  public func body(content: Content) -> Never { fatalError("no body") }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    return body(_Graph(), inputs)
  }
}

/// `transformPreference(_:_:)`.
@frozen
public struct _PreferenceTransformModifier<Key: PreferenceKey>: ViewModifier {
  public var transform: (inout Key.Value) -> Void
  public typealias Body = Never
  @inlinable public init(key: Key.Type = Key.self, transform: @escaping (inout Key.Value) -> Void) {
    self.transform = transform
  }
  public func body(content: Content) -> Never { fatalError("no body") }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    return body(_Graph(), inputs)
  }
}

/// `.secondary`, `.tertiary`... of a shape style: the style at a lower
/// level of emphasis (less opaque).
@frozen
public struct HierarchicalShapeStyleModifier<Base: ShapeStyle>: ShapeStyle {
  @usableFromInline var base: Base
  @usableFromInline var level: Int
  @_alwaysEmitIntoClient init(base: Base, level: Int) { (self.base, self.level) = (base, level) }
  public func _apply(to shape: inout _ShapeStyle_Shape) {
    base._apply(to: &shape)
    let opacities: [CGFloat] = [1, 0.5, 0.25, 0.18, 0.1]
    shape.paint = shape.paint?.with(opacity: opacities[min(max(level, 0), opacities.count - 1)])
  }
}

/// `symbolEffect(_:options:isActive:)` for indefinite effects; symbols do
/// not animate here.
@frozen
public struct _IndefiniteSymbolEffectModifier: ViewModifier {
  @usableFromInline var config: SymbolEffectConfiguration
  @usableFromInline var options: SymbolEffectOptions
  @usableFromInline var isActive: Bool
  public typealias Body = Never
  public func body(content: Content) -> Never { fatalError("no body") }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    return body(_Graph(), inputs)
  }
}

// MARK: - stroked shape views

/// `shape.stroke(_:style:antialiased:)`.
@frozen
public struct StrokeShapeView<Content: Shape, Style: ShapeStyle, Background: View>: View {
  @usableFromInline typealias ViewType = ModifiedContent<_ShapeView<_StrokedShape<Content>, Style>, _BackgroundModifier<Background>>
  @usableFromInline var view: ViewType
  @_alwaysEmitIntoClient public init(shape: Content, style: Style, strokeStyle: StrokeStyle, isAntialiased: Bool,
                                     background: Background) {
    view = .init(content: _ShapeView(shape: _StrokedShape(shape: shape, style: strokeStyle), style: style,
                                     fillStyle: FillStyle(antialiased: isAntialiased)),
                 modifier: _BackgroundModifier(background: background))
  }
  public typealias Body = Never
  public var body: Never { fatalError("no body") }
  public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value.view
    return ViewType._makeView(view: _GraphValue({ v }), inputs: inputs)
  }
}

/// `shape.strokeBorder(_:style:antialiased:)`: stroked inside the shape.
@frozen
public struct StrokeBorderShapeView<Content: InsettableShape, Style: ShapeStyle, Background: View>: View {
  @usableFromInline typealias ViewType = ModifiedContent<_ShapeView<_StrokedShape<Content.InsetShape>, Style>, _BackgroundModifier<Background>>
  public var shape: Content
  @usableFromInline var view: ViewType
  @_alwaysEmitIntoClient public init(shape: Content, style: Style, strokeStyle: StrokeStyle, isAntialiased: Bool,
                                     background: Background) {
    self.shape = shape
    view = .init(content: _ShapeView(shape: _StrokedShape(shape: shape.inset(by: strokeStyle.lineWidth * 0.5),
                                                          style: strokeStyle),
                                     style: style, fillStyle: FillStyle(antialiased: isAntialiased)),
                 modifier: _BackgroundModifier(background: background))
  }
  public typealias Body = Never
  public var body: Never { fatalError("no body") }
  public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value.view
    return ViewType._makeView(view: _GraphValue({ v }), inputs: inputs)
  }
}

// MARK: - toolbar content behind an availability check

@usableFromInline
internal class _AnyToolbarContentBox {
  func makeContent(inputs: _GraphInputs, resolved: inout _ToolbarItemList) {}
}
internal final class _ToolbarContentBox<C: ToolbarContent>: _AnyToolbarContentBox {
  let content: C
  init(_ content: C) { self.content = content }
  override func makeContent(inputs: _GraphInputs, resolved: inout _ToolbarItemList) {
    let c = content
    C._makeContent(content: _GraphValue({ c }), inputs: inputs, resolved: &resolved)
  }
}

/// What `ToolbarContentBuilder.buildLimitedAvailability` makes: one
/// reference to the erased content.
@frozen
public struct LimitedAvailabilityToolbarContent: CustomizableToolbarContent {
  @usableFromInline internal var storage: _AnyToolbarContentBox
  public init<C: ToolbarContent>(erasing content: C) { storage = _ToolbarContentBox(content) }
  public typealias Body = Never
  public var body: Never { return fatalError("no body") }
  public static func _makeContent(content: _GraphValue<Self>, inputs: _GraphInputs, resolved: inout _ToolbarItemList) {
    content.value.storage.makeContent(inputs: inputs, resolved: &resolved)
  }
}

// MARK: - search with no results

public struct SearchUnavailableContent {
  public struct Label: View {
    @usableFromInline var _text: String
    public var body: some View { SwiftUI.Label("No Results", systemImage: "magnifyingglass") }
  }
  public struct Description: View {
    @usableFromInline var _text: String
    public var body: some View {
      Text(_text.isEmpty ? "Check the spelling or try a new search." : "Check the spelling or try a new search for \u{201C}\(_text)\u{201D}.")
    }
  }
  public struct Actions: View {
    public var body: some View { EmptyView() }
  }
}
extension ContentUnavailableView where Label == SearchUnavailableContent.Label,
  Description == SearchUnavailableContent.Description, Actions == SearchUnavailableContent.Actions {
  public static var search: ContentUnavailableView { return .search(text: "") }
  public static func search(text: String) -> ContentUnavailableView {
    return ContentUnavailableView(label: { SearchUnavailableContent.Label(_text: text) },
                                  description: { SearchUnavailableContent.Description(_text: text) },
                                  actions: { SearchUnavailableContent.Actions() })
  }
}

// MARK: - tables

public protocol TableRowContent<TableRowValue> {
  associatedtype TableRowValue: Identifiable = TableRowBody.TableRowValue
  associatedtype TableRowBody: TableRowContent
  var tableRowBody: TableRowBody { get }
  func _rows() -> [TableRowValue]
}
extension TableRowContent {
  public func _rows() -> [TableRowValue] { return [] }
}
extension Never: TableRowContent {
  public typealias TableRowValue = Never
  public typealias TableRowBody = Never
  public var tableRowBody: Never { fatalError("no body") }
}
extension Never: Identifiable {
  public var id: Never { fatalError("no id") }
}

public protocol TableColumnContent<TableRowValue, TableColumnSortComparator> {
  associatedtype TableRowValue: Identifiable = TableColumnBody.TableRowValue
  associatedtype TableColumnSortComparator: SortComparator = TableColumnBody.TableColumnSortComparator
  associatedtype TableColumnBody: TableColumnContent
  var tableColumnBody: TableColumnBody { get }
  func _columns() -> [_TableColumnEntry<TableRowValue>]
}
extension TableColumnContent {
  public func _columns() -> [_TableColumnEntry<TableRowValue>] { return [] }
}
extension Never: TableColumnContent {
  public typealias TableColumnSortComparator = Never
  public typealias TableColumnBody = Never
  public var tableColumnBody: Never { fatalError("no body") }
}

/// One column of a table: a title and a view of each row's value.
public struct _TableColumnEntry<RowValue> {
  let title: String
  let width: CGFloat?
  let cell: (RowValue) -> AnyView
}

public struct TableColumn<RowValue: Identifiable, Sort: SortComparator, Content: View, Label: View>: TableColumnContent {
  public typealias TableRowValue = RowValue
  public typealias TableColumnSortComparator = Sort
  public typealias TableColumnBody = Never
  let label: Label
  let title: String
  let content: (RowValue) -> Content
  var _width: CGFloat?
  public var tableColumnBody: Never { fatalError("no body") }
  public func width(_ width: CGFloat? = nil) -> TableColumn<RowValue, Sort, Content, Label> {
    var c = self
    c._width = width
    return c
  }
  public func width(min: CGFloat? = nil, ideal: CGFloat? = nil, max: CGFloat? = nil) -> TableColumn {
    return width(ideal ?? min)
  }
  public func _columns() -> [_TableColumnEntry<RowValue>] {
    let f = content
    return [_TableColumnEntry(title: title, width: _width, cell: { AnyView(f($0)) })]
  }
}
extension TableColumn where Sort == Never, Label == Text {
  public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: @escaping (RowValue) -> Content) {
    label = Text(titleKey)
    title = label._string
    self.content = content
  }
  public init(_ titleKey: LocalizedStringKey, value: KeyPath<RowValue, String>) where Content == Text {
    label = Text(titleKey)
    title = label._string
    content = { Text(verbatim: $0[keyPath: value]) }
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, @ViewBuilder content: @escaping (RowValue) -> Content) {
    label = Text(verbatim: String(title))
    self.title = String(title)
    self.content = content
  }
}

public struct TupleTableColumnContent<RowValue: Identifiable, Sort: SortComparator, T>: TableColumnContent {
  public typealias TableRowValue = RowValue
  public typealias TableColumnSortComparator = Sort
  public typealias TableColumnBody = Never
  public var value: T
  let columns: [_TableColumnEntry<RowValue>]
  public var tableColumnBody: Never { fatalError("no body") }
  public func _columns() -> [_TableColumnEntry<RowValue>] { return columns }
}

@resultBuilder
public struct TableColumnBuilder<RowValue: Identifiable, Sort: SortComparator> {
  public static func buildExpression<C: TableColumnContent>(_ c: C) -> C
    where C.TableRowValue == RowValue, C.TableColumnSortComparator == Sort { return c }
  public static func buildBlock<C: TableColumnContent>(_ c: C) -> C
    where C.TableRowValue == RowValue, C.TableColumnSortComparator == Sort { return c }
  public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent>(_ c0: C0, _ c1: C1)
    -> TupleTableColumnContent<RowValue, Sort, (C0, C1)>
    where C0.TableRowValue == RowValue, C1.TableRowValue == RowValue {
    return TupleTableColumnContent(value: (c0, c1), columns: c0._columns() + c1._columns())
  }
  public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent>(
    _ c0: C0, _ c1: C1, _ c2: C2) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2)>
    where C0.TableRowValue == RowValue, C1.TableRowValue == RowValue, C2.TableRowValue == RowValue {
    return TupleTableColumnContent(value: (c0, c1, c2), columns: c0._columns() + c1._columns() + c2._columns())
  }
  public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent,
                                C3: TableColumnContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3)
    -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3)>
    where C0.TableRowValue == RowValue, C1.TableRowValue == RowValue, C2.TableRowValue == RowValue,
    C3.TableRowValue == RowValue {
    return TupleTableColumnContent(value: (c0, c1, c2, c3),
                                   columns: c0._columns() + c1._columns() + c2._columns() + c3._columns())
  }
}

/// The rows of a table made from a collection.
public struct TableForEachContent<Data: RandomAccessCollection>: TableRowContent where Data.Element: Identifiable {
  public typealias TableRowValue = Data.Element
  public typealias TableRowBody = Never
  public var data: Data
  public var tableRowBody: Never { fatalError("no body") }
  public func _rows() -> [Data.Element] { return Array(data) }
}

/// Rows of values in titled columns.
public struct Table<Value, Rows: TableRowContent, Columns: TableColumnContent>: View
  where Value == Rows.TableRowValue, Rows.TableRowValue == Columns.TableRowValue {
  let rows: Rows
  let columns: Columns
  let selection: Binding<Value.ID?>?
  public init<Data: RandomAccessCollection>(_ data: Data, @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Columns.TableRowValue == Data.Element {
    rows = TableForEachContent(data: data)
    self.columns = columns()
    selection = nil
  }
  public init<Data: RandomAccessCollection>(_ data: Data, selection: Binding<Value.ID?>,
                                            @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Columns.TableRowValue == Data.Element {
    rows = TableForEachContent(data: data)
    self.columns = columns()
    self.selection = selection
  }
  public var body: some View {
    let cols = columns._columns()
    let values = rows._rows()
    return ScrollView {
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
        GridRow {
          ForEach(0..<cols.count, id: \.self) { i in Text(verbatim: cols[i].title).font(.headline) }
        }
        Divider()
        ForEach(0..<values.count, id: \.self) { r in
          GridRow {
            ForEach(0..<cols.count, id: \.self) { i in cols[i].cell(values[r]) }
          }
        }
      }
      .padding(8)
    }
  }
}

// MARK: - attributed strings

extension AttributeScopes {
  public struct SwiftUIAttributes: AttributeScope {
    public enum ForegroundColorAttribute: AttributedStringKey {
      public typealias Value = Color
      public static var name: String { return "SwiftUI.ForegroundColor" }
    }
    public enum FontAttribute: AttributedStringKey {
      public typealias Value = Font
      public static var name: String { return "SwiftUI.Font" }
    }
    public enum BackgroundColorAttribute: AttributedStringKey {
      public typealias Value = Color
      public static var name: String { return "SwiftUI.BackgroundColor" }
    }
    public let foregroundColor: ForegroundColorAttribute
    public let font: FontAttribute
    public let backgroundColor: BackgroundColorAttribute
    public let foundation: AttributeScopes.FoundationAttributes
  }
  public var swiftUI: SwiftUIAttributes.Type { return SwiftUIAttributes.self }
}

extension Text {
  /// Attributed text, as its characters (runs' attributes are not drawn).
  @_disfavoredOverload
  public init(_ attributedContent: AttributedString) {
    self.init(verbatim: String(attributedContent.characters))
  }
}

// MARK: - smaller pieces

public enum Log {
  /// Where SwiftUI reports runtime issues.
  public static let runtimeIssuesLog: OSLog = os_log_create("com.apple.runtime-issues", "SwiftUI")
}

extension Double: Animatable {
  public typealias AnimatableData = Double
  public var animatableData: Double {
    get { return self }
    set { self = newValue }
  }
}
extension CGFloat: Animatable {
  public typealias AnimatableData = CGFloat
  public var animatableData: CGFloat {
    get { return self }
    set { self = newValue }
  }
}

extension MutableCollection {
  /// Moves the elements at `source` (in order) to before `destination`.
  public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
    var items = Array(self)
    let moving = source.map { items[$0] }
    var dest = destination
    for i in source.reversed() {
      items.remove(at: i)
      if i < dest { dest -= 1 }
    }
    items.insert(contentsOf: moving, at: Swift.max(0, Swift.min(dest, items.count)))
    var i = startIndex
    for e in items {
      self[i] = e
      formIndex(after: &i)
    }
  }
}
extension RangeReplaceableCollection where Self: MutableCollection {
  public mutating func remove(atOffsets offsets: IndexSet) {
    for o in offsets.reversed() { remove(at: index(startIndex, offsetBy: o)) }
  }
}

extension ModifiedContent where Modifier == AccessibilityAttachmentModifier {
  public func accessibilityHint<S: StringProtocol>(_ hint: S) -> ModifiedContent<Content, Modifier> { return self }
  public func accessibilityValue<S: StringProtocol>(_ value: S) -> ModifiedContent<Content, Modifier> { return self }
}

extension View {
  /// The older spelling; a shape style or `background(alignment:content:)`
  /// is preferred when both fit.
  @_disfavoredOverload
  public func background<Background: View>(_ background: Background, alignment: Alignment = .center) -> some View {
    return modifier(_BackgroundModifier(background: background, alignment: alignment))
  }
  @_disfavoredOverload
  public func overlay<Overlay: View>(_ overlay: Overlay, alignment: Alignment = .center) -> some View {
    return modifier(_OverlayModifier(overlay: overlay, alignment: alignment))
  }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
  public static var scrollView: NamedCoordinateSpace { return .named("SwiftUI.scrollView") }
  public static func scrollView(axis: Axis) -> NamedCoordinateSpace {
    return .named(axis == .horizontal ? "SwiftUI.scrollView.horizontal" : "SwiftUI.scrollView.vertical")
  }
}

extension VisualEffect {
  public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some VisualEffect { return self }
  public func offset(_ offset: CGSize) -> some VisualEffect { return self }
  public func opacity(_ opacity: Double) -> some VisualEffect { return self }
  public func scaleEffect(_ scale: CGFloat, anchor: UnitPoint = .center) -> some VisualEffect { return self }
  public func blur(radius: CGFloat, opaque: Bool = false) -> some VisualEffect { return self }
}

extension ContentTransition {
  public static func symbolEffect<T: ContentTransitionSymbolEffect & SymbolEffect>(
    _ effect: T, options: SymbolEffectOptions = .default) -> ContentTransition {
    return .symbolEffect
  }
}
