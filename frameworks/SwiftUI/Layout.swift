// Layout: alignments, edges, stacks, spacers, padding and frames, and
// ModifiedContent. The frozen types keep Apple's stored layout (programs
// build stacks and modifiers inline); the nodes do the layout.

import CoreGraphics

// MARK: - alignment

public protocol AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> CGFloat
}

@frozen
public struct AlignmentKey: Hashable, Comparable {
  private let bits: UInt
  internal init(bits: UInt) { self.bits = bits }
  internal var index: UInt { return bits >> 1 }
  public static func < (a: AlignmentKey, b: AlignmentKey) -> Bool { return a.bits < b.bits }
}

/// Alignment IDs get indices as they are first used; built-ins come first.
internal enum _AlignmentRegistry {
  nonisolated(unsafe) static var ids: [ObjectIdentifier] = []
  nonisolated(unsafe) static var types: [any AlignmentID.Type] = []
  static func key(_ id: any AlignmentID.Type, vertical: Bool) -> AlignmentKey {
    let oid = ObjectIdentifier(id)
    let i: Int
    if let found = ids.firstIndex(of: oid) {
      i = found
    } else {
      ids.append(oid)
      types.append(id)
      i = ids.count - 1
    }
    return AlignmentKey(bits: UInt(i) << 1 | (vertical ? 1 : 0))
  }
}

internal enum _LeadingID: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { return 0 } }
internal enum _HCenterID: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { return d.width / 2 } }
internal enum _TrailingID: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { return d.width } }
internal enum _TopID: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { return 0 } }
internal enum _VCenterID: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { return d.height / 2 } }
internal enum _BottomID: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { return d.height } }
internal enum _FirstBaselineID: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { return d.height * 0.8 } }
internal enum _LastBaselineID: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { return d.height * 0.8 } }

@frozen
public struct HorizontalAlignment: Equatable {
  public let key: AlignmentKey
  public init(_ id: any AlignmentID.Type) { key = _AlignmentRegistry.key(id, vertical: false) }
  public static var leading: HorizontalAlignment { return HorizontalAlignment(_LeadingID.self) }
  public static var center: HorizontalAlignment { return HorizontalAlignment(_HCenterID.self) }
  public static var trailing: HorizontalAlignment { return HorizontalAlignment(_TrailingID.self) }
  public static var listRowSeparatorLeading: HorizontalAlignment { return .leading }
  public static var listRowSeparatorTrailing: HorizontalAlignment { return .trailing }
  public static func == (a: HorizontalAlignment, b: HorizontalAlignment) -> Bool { return a.key == b.key }
  /// Where this alignment falls in a box of `size` (0 = leading).
  internal func offset(in size: CGSize) -> CGFloat {
    let t = _AlignmentRegistry.types[Int(key.index)]
    return t.defaultValue(in: ViewDimensions(width: size.width, height: size.height))
  }
}

@frozen
public struct VerticalAlignment: Equatable {
  public let key: AlignmentKey
  public init(_ id: any AlignmentID.Type) { key = _AlignmentRegistry.key(id, vertical: true) }
  public static var top: VerticalAlignment { return VerticalAlignment(_TopID.self) }
  public static var center: VerticalAlignment { return VerticalAlignment(_VCenterID.self) }
  public static var bottom: VerticalAlignment { return VerticalAlignment(_BottomID.self) }
  public static var firstTextBaseline: VerticalAlignment { return VerticalAlignment(_FirstBaselineID.self) }
  public static var lastTextBaseline: VerticalAlignment { return VerticalAlignment(_LastBaselineID.self) }
  public static func == (a: VerticalAlignment, b: VerticalAlignment) -> Bool { return a.key == b.key }
  internal func offset(in size: CGSize) -> CGFloat {
    let t = _AlignmentRegistry.types[Int(key.index)]
    return t.defaultValue(in: ViewDimensions(width: size.width, height: size.height))
  }
}

@frozen
public struct Alignment: Equatable {
  public var horizontal: HorizontalAlignment
  public var vertical: VerticalAlignment
  @inlinable public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
    self.horizontal = horizontal
    self.vertical = vertical
  }
  public static var center: Alignment { return Alignment(horizontal: .center, vertical: .center) }
  public static var leading: Alignment { return Alignment(horizontal: .leading, vertical: .center) }
  public static var trailing: Alignment { return Alignment(horizontal: .trailing, vertical: .center) }
  public static var top: Alignment { return Alignment(horizontal: .center, vertical: .top) }
  public static var bottom: Alignment { return Alignment(horizontal: .center, vertical: .bottom) }
  public static var topLeading: Alignment { return Alignment(horizontal: .leading, vertical: .top) }
  public static var topTrailing: Alignment { return Alignment(horizontal: .trailing, vertical: .top) }
  public static var bottomLeading: Alignment { return Alignment(horizontal: .leading, vertical: .bottom) }
  public static var bottomTrailing: Alignment { return Alignment(horizontal: .trailing, vertical: .bottom) }
  /// The origin of a child of `child` size placed in `container`.
  internal func origin(of child: CGSize, in container: CGRect) -> CGPoint {
    let x = horizontal.offset(in: container.size) - horizontal.offset(in: child)
    let y = vertical.offset(in: container.size) - vertical.offset(in: child)
    return CGPoint(x: container._minX + x, y: container._minY + y)
  }
}

public struct ViewDimensions: Equatable {
  public let width: CGFloat
  public let height: CGFloat
  internal init(width: CGFloat, height: CGFloat) {
    self.width = width
    self.height = height
  }
  public subscript(guide: HorizontalAlignment) -> CGFloat { return guide.offset(in: CGSize(width: width, height: height)) }
  public subscript(guide: VerticalAlignment) -> CGFloat { return guide.offset(in: CGSize(width: width, height: height)) }
  public subscript(explicit guide: HorizontalAlignment) -> CGFloat? { return self[guide] }
  public subscript(explicit guide: VerticalAlignment) -> CGFloat? { return self[guide] }
}

// MARK: - edges

@frozen
public enum Edge: Int8, CaseIterable, Hashable, Sendable {
  case top, leading, bottom, trailing

  @frozen
  public struct Set: OptionSet, Sendable {
    public let rawValue: Int8
    @inlinable public init(rawValue: Int8) { self.rawValue = rawValue }
    public static let top = Set(rawValue: 1 << 0)
    public static let leading = Set(rawValue: 1 << 1)
    public static let bottom = Set(rawValue: 1 << 2)
    public static let trailing = Set(rawValue: 1 << 3)
    public static let all: Set = [.top, .leading, .bottom, .trailing]
    public static let horizontal: Set = [.leading, .trailing]
    public static let vertical: Set = [.top, .bottom]
    public init(_ e: Edge) { self.init(rawValue: 1 << e.rawValue) }
  }
}

@frozen
public enum HorizontalEdge: Int8, CaseIterable, Hashable, Sendable {
  case leading, trailing
}
@frozen
public enum VerticalEdge: Int8, CaseIterable, Hashable, Sendable {
  case top, bottom
}

@frozen
public struct EdgeInsets: Equatable, Sendable {
  public var top: CGFloat
  public var leading: CGFloat
  public var bottom: CGFloat
  public var trailing: CGFloat
  @inlinable public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
    self.top = top
    self.leading = leading
    self.bottom = bottom
    self.trailing = trailing
  }
  @inlinable public init() { self.init(top: 0, leading: 0, bottom: 0, trailing: 0) }
  @usableFromInline internal init(_all: CGFloat) { self.init(top: _all, leading: _all, bottom: _all, trailing: _all) }
}

@frozen
public enum Axis: Int8, CaseIterable, Hashable, Sendable {
  case horizontal, vertical
  @frozen
  public struct Set: OptionSet, Sendable {
    public let rawValue: Int8
    public init(rawValue: Int8) { self.rawValue = rawValue }
    public static let horizontal = Set(rawValue: 1)
    public static let vertical = Set(rawValue: 2)
  }
}

// MARK: - ModifiedContent and ViewModifier

public protocol ViewModifier {
  static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs
  static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs,
                            body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs
  static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int?
  associatedtype Body: View
  @ViewBuilder @MainActor @preconcurrency func body(content: Self.Content) -> Self.Body
  typealias Content = _ViewModifier_Content<Self>
}

/// The content a modifier's body wraps: the modified view, as built so far.
public struct _ViewModifier_Content<Modifier: ViewModifier>: View {
  internal let _make: (_ViewInputs) -> _ViewNode
  internal init(_make: @escaping (_ViewInputs) -> _ViewNode) { self._make = _make }
  public typealias Body = Never
  public var body: Never { fatalError("_ViewModifier_Content has no body") }
  public static func _makeView(view: _GraphValue<_ViewModifier_Content>, inputs: _ViewInputs) -> _ViewOutputs {
    return _ViewOutputs(view.value._make(inputs))
  }
}

extension ViewModifier {
  /// The default: the modifier's body, around the content.
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    var m = modifier.value
    _installDynamicProperties(&m, inputs: inputs)
    if Body.self == Never.self { return body(_Graph(), inputs) }
    let content = _ViewModifier_Content<Self>(_make: { body(_Graph(), $0).node })
    let built = _withObservation(inputs) { m.body(content: content) }
    if _debugGraph { _dbg("bitten: modifier \(Self.self) body \(Body.self) built \(type(of: built as Any))") }
    return Body._makeView(view: _GraphValue({ built }), inputs: inputs.child(0))
  }
  public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs,
                                   body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
    let one = _makeView(modifier: modifier, inputs: inputs.base) { g, i in
      let nodes = body(g, _ViewListInputs(i)).nodes
      return _ViewOutputs(nodes.count == 1 ? nodes[0] : _StackNode(axis: .vertical, alignment: .center, spacing: nil,
                                                                  environment: i.environment, children: nodes))
    }
    return _ViewListOutputs([one.node])
  }
  public static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int? {
    return body(inputs)
  }
}

extension ViewModifier where Self: Animatable {
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    var m = modifier.value
    _installDynamicProperties(&m, inputs: inputs)
    let content = _ViewModifier_Content<Self>(_make: { body(_Graph(), $0).node })
    let built = _withObservation(inputs) { m.body(content: content) }
    return Body._makeView(view: _GraphValue({ built }), inputs: inputs.child(0))
  }
  public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs,
                                   body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
    let one = _makeView(modifier: modifier, inputs: inputs.base) { g, i in
      let nodes = body(g, _ViewListInputs(i)).nodes
      return _ViewOutputs(nodes.count == 1 ? nodes[0] : _StackNode(axis: .vertical, alignment: .center, spacing: nil,
                                                                  environment: i.environment, children: nodes))
    }
    return _ViewListOutputs([one.node])
  }
}

@frozen
public struct ModifiedContent<Content, Modifier> {
  public var content: Content
  public var modifier: Modifier
  @inlinable public init(content: Content, modifier: Modifier) {
    self.content = content
    self.modifier = modifier
  }
}

extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
  public typealias Body = Never
  public var body: Never { fatalError("ModifiedContent has no body") }
  public static func _makeView(view: _GraphValue<ModifiedContent>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    if _debugGraph && "\(Content.self)".hasPrefix("GeometryReader") {
      var c = v.content
      let w = withUnsafeBytes(of: &c) { r in (0..<min(2, r.count / 8)).map { String(r.load(fromByteOffset: $0 * 8, as: UInt.self), radix: 16) } }
      _dbg("bitten: modified geometry \(w) modifier \(Modifier.self)")
    }
    return Modifier._makeView(modifier: _GraphValue({ v.modifier }), inputs: inputs.named("m")) { _, i in
      Content._makeView(view: _GraphValue({ v.content }), inputs: i.named("c"))
    }
  }
  /// The modifier decides: environment and trait modifiers pass the
  /// content's elements through (a ForEach with `.disabled` in a picker or
  /// stack is still one element per view), others wrap them.
  public static func _makeViewList(view: _GraphValue<ModifiedContent>, inputs: _ViewListInputs) -> _ViewListOutputs {
    let v = view.value
    return Modifier._makeViewList(modifier: _GraphValue({ v.modifier }),
                                  inputs: _ViewListInputs(inputs.base.named("m"))) { _, i in
      Content._makeViewList(view: _GraphValue({ v.content }), inputs: _ViewListInputs(i.base.named("c")))
    }
  }
}

extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {
  public typealias Body = Never
  public func body(content: _ViewModifier_Content<ModifiedContent>) -> Never { fatalError("no body") }
  public static func _makeView(modifier: _GraphValue<ModifiedContent>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let m = modifier.value
    return Modifier._makeView(modifier: _GraphValue({ m.modifier }), inputs: inputs) { _, i in
      Content._makeView(modifier: _GraphValue({ m.content }), inputs: i, body: body)
    }
  }
}

extension View {
  @inlinable public func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> {
    return ModifiedContent(content: self, modifier: modifier)
  }
}

/// Modifiers that do their own layout: they wrap the content's node.
internal protocol _NodeModifier: ViewModifier where Body == Never {
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode
}
extension _NodeModifier {
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let content = body(_Graph(), inputs).node
    return _ViewOutputs(modifier.value.makeNode(content: content, environment: inputs.environment))
  }
  public func body(content: Content) -> Never { fatalError("no body") }
}

// MARK: - variadic views and stacks

public protocol _VariadicView_Root {}
public protocol _VariadicView_ViewRoot: _VariadicView_Root {}
public protocol _VariadicView_UnaryViewRoot: _VariadicView_ViewRoot {}
public protocol _VariadicView_MultiViewRoot: _VariadicView_ViewRoot {}

public enum _VariadicView {
  @frozen
  public struct Tree<Root: _VariadicView_Root, Content> {
    public var root: Root
    public var content: Content
    @inlinable internal init(root: Root, content: Content) {
      self.root = root
      self.content = content
    }
    @inlinable public init(_ root: Root, @ViewBuilder content: () -> Content) {
      self.root = root
      self.content = content()
    }
  }
}

/// Roots that lay out the children of a variadic tree.
internal protocol _StackRoot: _VariadicView_ViewRoot {
  func makeNode(_ children: [_ViewNode], environment: EnvironmentValues) -> _ViewNode
}

extension _VariadicView.Tree: View where Root: _VariadicView_ViewRoot, Content: View {
  public typealias Body = Never
  public var body: Never { fatalError("_VariadicView.Tree has no body") }
  public static func _makeView(view: _GraphValue<_VariadicView.Tree<Root, Content>>, inputs: _ViewInputs) -> _ViewOutputs {
    let tree = view.value
    let children = _makeNodes(tree.content, inputs: inputs.named("content"))
    if let stack = tree.root as? _StackRoot {
      return _ViewOutputs(stack.makeNode(children, environment: inputs.environment))
    }
    return _ViewOutputs(_StackNode(axis: .vertical, alignment: .center, spacing: nil,
                                   environment: inputs.environment, children: children))
  }
}

@frozen
public struct _VStackLayout: _StackRoot, _VariadicView_UnaryViewRoot {
  public var alignment: HorizontalAlignment
  public var spacing: CGFloat?
  @inlinable public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil) {
    self.alignment = alignment
    self.spacing = spacing
  }
  func makeNode(_ children: [_ViewNode], environment: EnvironmentValues) -> _ViewNode {
    return _StackNode(axis: .vertical, alignment: Alignment(horizontal: alignment, vertical: .center), spacing: spacing,
                      environment: environment, children: children)
  }
}

@frozen
public struct _HStackLayout: _StackRoot, _VariadicView_UnaryViewRoot {
  public var alignment: VerticalAlignment
  public var spacing: CGFloat?
  @inlinable public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil) {
    self.alignment = alignment
    self.spacing = spacing
  }
  func makeNode(_ children: [_ViewNode], environment: EnvironmentValues) -> _ViewNode {
    return _StackNode(axis: .horizontal, alignment: Alignment(horizontal: .center, vertical: alignment), spacing: spacing,
                      environment: environment, children: children)
  }
}

@frozen
public struct _ZStackLayout: _StackRoot, _VariadicView_UnaryViewRoot {
  public var alignment: Alignment
  @inlinable public init(alignment: Alignment = .center) { self.alignment = alignment }
  func makeNode(_ children: [_ViewNode], environment: EnvironmentValues) -> _ViewNode {
    return _ZStackNode(alignment: alignment, environment: environment, children: children)
  }
}

@frozen
public struct VStack<Content: View>: View {
  @usableFromInline internal var _tree: _VariadicView.Tree<_VStackLayout, Content>
  @inlinable public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                         @ViewBuilder content: () -> Content) {
    _tree = .init(root: _VStackLayout(alignment: alignment, spacing: spacing), content: content())
  }
  public typealias Body = Never
  public var body: Never { fatalError("VStack has no body") }
  public static func _makeView(view: _GraphValue<VStack>, inputs: _ViewInputs) -> _ViewOutputs {
    return _VariadicView.Tree<_VStackLayout, Content>._makeView(view: view[\._tree], inputs: inputs)
  }
}

@frozen
public struct HStack<Content: View>: View {
  @usableFromInline internal var _tree: _VariadicView.Tree<_HStackLayout, Content>
  public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
    _tree = .init(root: _HStackLayout(alignment: alignment, spacing: spacing), content: content())
  }
  public typealias Body = Never
  public var body: Never { fatalError("HStack has no body") }
  public static func _makeView(view: _GraphValue<HStack>, inputs: _ViewInputs) -> _ViewOutputs {
    return _VariadicView.Tree<_HStackLayout, Content>._makeView(view: view[\._tree], inputs: inputs)
  }
}

@frozen
public struct ZStack<Content: View>: View {
  @usableFromInline internal var _tree: _VariadicView.Tree<_ZStackLayout, Content>
  @inlinable public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
    _tree = .init(root: _ZStackLayout(alignment: alignment), content: content())
  }
  public typealias Body = Never
  public var body: Never { fatalError("ZStack has no body") }
  public static func _makeView(view: _GraphValue<ZStack>, inputs: _ViewInputs) -> _ViewOutputs {
    return _VariadicView.Tree<_ZStackLayout, Content>._makeView(view: view[\._tree], inputs: inputs)
  }
}

@frozen
public struct Spacer: View {
  public var minLength: CGFloat?
  @inlinable public init(minLength: CGFloat? = nil) { self.minLength = minLength }
  public typealias Body = Never
  public var body: Never { fatalError("Spacer has no body") }
  public static func _makeView(view: _GraphValue<Spacer>, inputs: _ViewInputs) -> _ViewOutputs {
    return _ViewOutputs(_SpacerNode(minLength: view.value.minLength ?? 8, environment: inputs.environment))
  }
}

// MARK: - padding and frames

@frozen
public struct _PaddingLayout: _NodeModifier, Animatable {
  public var edges: Edge.Set
  public var insets: EdgeInsets?
  @inlinable public init(edges: Edge.Set = .all, insets: EdgeInsets?) {
    self.edges = edges
    self.insets = insets
  }
  public typealias AnimatableData = EmptyAnimatableData
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode {
    let d: CGFloat = 16
    let i = insets ?? EdgeInsets(top: d, leading: d, bottom: d, trailing: d)
    let e = EdgeInsets(top: edges.contains(.top) ? i.top : 0, leading: edges.contains(.leading) ? i.leading : 0,
                       bottom: edges.contains(.bottom) ? i.bottom : 0, trailing: edges.contains(.trailing) ? i.trailing : 0)
    return _PaddingNode(insets: e, environment: environment, children: [content])
  }
}

extension View {
  @inlinable public func padding(_ insets: EdgeInsets) -> some View {
    return modifier(_PaddingLayout(insets: insets))
  }
  @inlinable public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
    let insets = length.map { EdgeInsets(top: $0, leading: $0, bottom: $0, trailing: $0) }
    return modifier(_PaddingLayout(edges: edges, insets: insets))
  }
  @inlinable public func padding(_ length: CGFloat) -> some View {
    return padding(.all, length)
  }
}

@frozen
public struct _FrameLayout: _NodeModifier, Animatable {
  @usableFromInline let width: CGFloat?
  @usableFromInline let height: CGFloat?
  @usableFromInline let alignment: Alignment
  @usableFromInline internal init(width: CGFloat?, height: CGFloat?, alignment: Alignment) {
    self.width = width
    self.height = height
    self.alignment = alignment
  }
  public typealias AnimatableData = EmptyAnimatableData
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode {
    return _FrameNode(minW: width, idealW: width, maxW: width, minH: height, idealH: height, maxH: height,
                      alignment: alignment, environment: environment, children: [content])
  }
}

@frozen
public struct _FlexFrameLayout: _NodeModifier, Animatable {
  @usableFromInline let minWidth: CGFloat?
  @usableFromInline let idealWidth: CGFloat?
  @usableFromInline let maxWidth: CGFloat?
  @usableFromInline let minHeight: CGFloat?
  @usableFromInline let idealHeight: CGFloat?
  @usableFromInline let maxHeight: CGFloat?
  @usableFromInline let alignment: Alignment
  @usableFromInline internal init(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
                                  minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil,
                                  alignment: Alignment) {
    self.minWidth = minWidth
    self.idealWidth = idealWidth
    self.maxWidth = maxWidth
    self.minHeight = minHeight
    self.idealHeight = idealHeight
    self.maxHeight = maxHeight
    self.alignment = alignment
  }
  public typealias AnimatableData = EmptyAnimatableData
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode {
    return _FrameNode(minW: minWidth, idealW: idealWidth, maxW: maxWidth, minH: minHeight, idealH: idealHeight,
                      maxH: maxHeight, alignment: alignment, environment: environment, children: [content])
  }
}

extension View {
  public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View {
    return modifier(_FrameLayout(width: width, height: height, alignment: alignment))
  }
  public func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
                    minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil,
                    alignment: Alignment = .center) -> some View {
    return modifier(_FlexFrameLayout(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth, minHeight: minHeight,
                                     idealHeight: idealHeight, maxHeight: maxHeight, alignment: alignment))
  }
}

// MARK: - layout nodes

internal final class _StackNode: _ViewNode {
  let axis: Axis
  let alignment: Alignment
  let spacing: CGFloat
  var sizes: [CGSize] = []
  /// A Section's stack: its content's views (without header and footer),
  /// which a picker offers as options.
  var sectionItems: [_ViewNode]?

  init(axis: Axis, alignment: Alignment, spacing: CGFloat?, environment: EnvironmentValues, children: [_ViewNode]) {
    self.axis = axis
    self.alignment = alignment
    self.spacing = spacing ?? 8
    super.init(environment: environment, children: children)
  }

  private func main(_ s: CGSize) -> CGFloat { return axis == .vertical ? s.height : s.width }
  private func cross(_ s: CGSize) -> CGFloat { return axis == .vertical ? s.width : s.height }
  private func size(main m: CGFloat, cross c: CGFloat) -> CGSize {
    return axis == .vertical ? CGSize(width: c, height: m) : CGSize(width: m, height: c)
  }

  /// Gives fixed-size children what they need and shares the rest among
  /// flexible ones (spacers and views that grow), like SwiftUI's stacks.
  private func layout(_ proposal: ProposedViewSize) -> [CGSize] {
    let n = children.count
    guard n > 0 else { return [] }
    let available = axis == .vertical ? proposal.height : proposal.width
    let crossProposal = axis == .vertical ? proposal.width : proposal.height
    let gaps = spacing * CGFloat(n - 1)
    // Ideal sizes first.
    let ideal = children.map { child -> CGSize in
      let p = axis == .vertical ? ProposedViewSize(width: crossProposal, height: nil)
                                : ProposedViewSize(width: nil, height: crossProposal)
      return child.measure(p)
    }
    guard let total = available else { return ideal }
    // More wanted than there is: as SwiftUI's stacks, every child shares the
    // shortfall by flexibility (how much it changes between being offered
    // nothing and everything), the least flexible first, each offered an
    // equal share of what is left, by layout priority.
    let wanted = (0..<n).reduce(CGFloat(0)) { $0 + (children[$1].isSpacer ? 0 : main(ideal[$1])) }
    if wanted > total - gaps + 0.5 {
      func offer(_ m: CGFloat) -> ProposedViewSize {
        return axis == .vertical ? ProposedViewSize(width: crossProposal, height: m)
                                 : ProposedViewSize(width: m, height: crossProposal)
      }
      let mins = children.map { main($0.measure(offer(0))) }
      let maxs = children.map { $0.isSpacer ? CGFloat.infinity : main($0.measure(offer(1e6))) }
      let priorities = children.map { $0.layoutPriority }
      var result = ideal
      var remaining = total - gaps
      for priority in Set(priorities).sorted(by: >) {
        let group = (0..<n).filter { priorities[$0] == priority }
          .sorted { (maxs[$0] - mins[$0]) < (maxs[$1] - mins[$1]) }
        let reserved = (0..<n).filter { priorities[$0] < priority }.reduce(CGFloat(0)) { $0 + mins[$1] }
        // Spacers keep only their minimum length while the others share
        // what there is; they take what is left after (SwiftUI's stacks).
        let views = group.filter { !children[$0].isSpacer }, spacers = group.filter { children[$0].isSpacer }
        let spacerMins = spacers.reduce(CGFloat(0)) { $0 + mins[$1] }
        var avail = remaining - reserved - spacerMins
        var left = views.count
        for i in views {
          let share = max(0, avail) / CGFloat(left)
          result[i] = children[i].measure(offer(share))
          avail -= main(result[i])
          remaining -= main(result[i])
          left -= 1
        }
        avail += spacerMins
        left = spacers.count
        for i in spacers {
          let share = max(0, avail) / CGFloat(left)
          result[i] = size(main: max(share, mins[i]), cross: 0)
          avail -= main(result[i])
          remaining -= main(result[i])
          left -= 1
        }
      }
      return result
    }
    var remaining = total - gaps
    var result = ideal
    var flexible: [Int] = []
    for i in 0..<n {
      if children[i].isSpacer { flexible.append(i); continue }
      remaining -= main(ideal[i])
    }
    // Children that would grow if offered more space are flexible too.
    for i in 0..<n where !children[i].isSpacer {
      let bigger = axis == .vertical ? ProposedViewSize(width: crossProposal, height: main(ideal[i]) + 10000)
                                     : ProposedViewSize(width: main(ideal[i]) + 10000, height: crossProposal)
      if main(children[i].measure(bigger)) > main(ideal[i]) + 1 {
        flexible.append(i)
        remaining += main(ideal[i])
      }
    }
    if !flexible.isEmpty {
      // One at a time, the largest first (spacers last), each from what the others
      // left (a child that cannot shrink to its share takes more, and the
      // rest share less), as SwiftUI's stacks do.
      // Children that stop growing at some size (a frame's maxWidth) come
      // before those that would take anything, as SwiftUI orders the less
      // flexible first; otherwise the largest first, spacers last.
      let most: [CGFloat] = flexible.reduce(into: Array(repeating: CGFloat.infinity, count: n)) { m, i in
        if !children[i].isSpacer {
          let p = axis == .vertical ? ProposedViewSize(width: crossProposal, height: 1e6)
                                    : ProposedViewSize(width: 1e6, height: crossProposal)
          let grown = main(children[i].measure(p))
          m[i] = grown < 1e5 ? grown : .infinity
        }
      }
      let order = flexible.sorted { a, b in
        if children[a].isSpacer != children[b].isSpacer { return children[b].isSpacer }
        if most[a] != most[b] { return most[a] < most[b] }
        let fa = children[a].isSpacer ? -CGFloat.infinity : main(ideal[a])
        let fb = children[b].isSpacer ? -CGFloat.infinity : main(ideal[b])
        return fa > fb
      }
      var left = order.count
      for i in order {
        let share = max(0, remaining) / CGFloat(left)
        let p = axis == .vertical ? ProposedViewSize(width: crossProposal, height: share)
                                  : ProposedViewSize(width: share, height: crossProposal)
        result[i] = children[i].measure(p)
        if children[i].isSpacer { result[i] = size(main: max(share, main(result[i])), cross: 0) }
        remaining -= main(result[i])
        left -= 1
      }
    }
    return result
  }

  /// The children's sizes for a placement in `size`. Offered exactly its
  /// ideal length (as scroll views place their content), a stack gives every
  /// child its ideal size.
  private func placementSizes(_ size: CGSize) -> [CGSize] {
    let idealProposal = axis == .vertical ? ProposedViewSize(width: size.width, height: nil)
                                          : ProposedViewSize(width: nil, height: size.height)
    let ideal = layout(idealProposal)
    let idealMain = ideal.reduce(0) { $0 + main($1) } + spacing * CGFloat(max(0, ideal.count - 1))
    if abs(idealMain - main(size)) < 0.5 { return ideal }
    return layout(ProposedViewSize(size))
  }

  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    let s = layout(proposal)
    let m = s.reduce(0) { $0 + main($1) } + spacing * CGFloat(max(0, s.count - 1))
    let c = s.reduce(0) { max($0, cross($1)) }
    return size(main: m, cross: c)
  }

  override func place(in rect: CGRect) {
    frame = rect
    let s = placementSizes(rect.size)
    var pos = axis == .vertical ? rect._minY : rect._minX
    for (i, child) in children.enumerated() {
      let cs = s[i]
      let origin: CGPoint
      if axis == .vertical {
        let x = rect._minX + alignment.horizontal.offset(in: CGSize(width: rect._width, height: 0)) -
          alignment.horizontal.offset(in: CGSize(width: cs.width, height: 0))
        origin = CGPoint(x: x, y: pos)
      } else {
        let y = rect._minY + alignment.vertical.offset(in: CGSize(width: 0, height: rect._height)) -
          alignment.vertical.offset(in: CGSize(width: 0, height: cs.height))
        origin = CGPoint(x: pos, y: y)
      }
      child.place(in: CGRect(origin: origin, size: cs))
      pos += main(cs) + spacing
    }
  }
}

internal final class _ZStackNode: _ViewNode {
  let alignment: Alignment
  init(alignment: Alignment, environment: EnvironmentValues, children: [_ViewNode]) {
    self.alignment = alignment
    super.init(environment: environment, children: children)
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    return children.reduce(CGSize._zero) { acc, c in
      let s = c.sizeThatFits(proposal)
      return CGSize(width: max(acc.width, s.width), height: max(acc.height, s.height))
    }
  }
  override func place(in rect: CGRect) {
    frame = rect
    for c in children {
      let s = c.sizeThatFits(ProposedViewSize(rect.size))
      c.place(in: CGRect(origin: alignment.origin(of: s, in: rect), size: s))
    }
  }
}

internal final class _SpacerNode: _ViewNode {
  let minLength: CGFloat
  init(minLength: CGFloat, environment: EnvironmentValues) {
    self.minLength = minLength
    super.init(environment: environment)
  }
  override var isSpacer: Bool { return true }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    return CGSize(width: max(minLength, proposal.width ?? 0), height: max(minLength, proposal.height ?? 0))
  }
}

internal final class _PaddingNode: _ViewNode {
  let insets: EdgeInsets
  init(insets: EdgeInsets, environment: EnvironmentValues, children: [_ViewNode]) {
    self.insets = insets
    super.init(environment: environment, children: children)
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    let h = insets.leading + insets.trailing, v = insets.top + insets.bottom
    let inner = ProposedViewSize(width: proposal.width.map { max(0, $0 - h) }, height: proposal.height.map { max(0, $0 - v) })
    let s = children[0].sizeThatFits(inner)
    return CGSize(width: s.width + h, height: s.height + v)
  }
  override func place(in rect: CGRect) {
    frame = rect
    let x: CGFloat = rect._minX + insets.leading
    let y: CGFloat = rect._minY + insets.top
    let w: CGFloat = max(0, rect._width - insets.leading - insets.trailing)
    let h: CGFloat = max(0, rect._height - insets.top - insets.bottom)
    children[0].place(in: CGRect(_x: x, y: y, width: w, height: h))
  }
}

internal final class _FrameNode: _ViewNode {
  let minW, idealW, maxW, minH, idealH, maxH: CGFloat?
  let alignment: Alignment
  init(minW: CGFloat?, idealW: CGFloat?, maxW: CGFloat?, minH: CGFloat?, idealH: CGFloat?, maxH: CGFloat?,
       alignment: Alignment, environment: EnvironmentValues, children: [_ViewNode]) {
    self.minW = minW; self.idealW = idealW; self.maxW = maxW
    self.minH = minH; self.idealH = idealH; self.maxH = maxH
    self.alignment = alignment
    super.init(environment: environment, children: children)
  }
  private func clamp(_ v: CGFloat, _ lo: CGFloat?, _ hi: CGFloat?) -> CGFloat {
    var r = v
    if let hi = hi { r = min(r, hi) }
    if let lo = lo { r = max(r, lo) }
    return r
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    let pw = proposal.width ?? idealW, ph = proposal.height ?? idealH
    let child = children[0].sizeThatFits(ProposedViewSize(width: pw.map { clamp($0, minW, maxW) },
                                                          height: ph.map { clamp($0, minH, maxH) }))
    // A bounded frame is its bound when proposed more; an infinite maximum
    // takes all that is proposed.
    func dim(_ c: CGFloat, _ p: CGFloat?, _ lo: CGFloat?, _ ideal: CGFloat?, _ hi: CGFloat?) -> CGFloat {
      if lo == nil && hi == nil && ideal == nil { return c }
      if let lo = lo, let hi = hi, lo == hi { return lo }
      if let p = p {
        // SwiftUI's flexible frame: a minimum lets a smaller proposal win
        // over the content (down to the minimum), a maximum a larger one
        // (up to the maximum).
        var r = c
        if let lo = lo { r = max(lo, min(r, p)) }
        if let hi = hi { r = min(hi, max(r, p)) }
        return r
      }
      return clamp(ideal ?? c, lo, hi)
    }
    return CGSize(width: dim(child.width, proposal.width, minW, idealW, maxW),
                  height: dim(child.height, proposal.height, minH, idealH, maxH))
  }
  override func place(in rect: CGRect) {
    frame = rect
    let s = children[0].sizeThatFits(ProposedViewSize(rect.size))
    let cs = CGSize(width: min(s.width, rect._width), height: min(s.height, rect._height))
    children[0].place(in: CGRect(origin: alignment.origin(of: cs, in: rect), size: cs))
  }
}
