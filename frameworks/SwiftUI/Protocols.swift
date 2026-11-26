// Protocols programs conform to, with Apple's requirement lists (programs
// bind their witnesses by requirement) and default implementations under
// Apple's names: preferences, custom layouts, AppKit views and view
// controllers inside SwiftUI, commands, toolbars and styles.

import CoreGraphics
import Dispatch

// MARK: - preferences

public protocol PreferenceKey {
  associatedtype Value
  static var defaultValue: Value { get }
  static func reduce(value: inout Value, nextValue: () -> Value)
  static var _includesRemovedValues: Bool { get }
  static var _isReadableByHost: Bool { get }
}
extension PreferenceKey {
  public static var _includesRemovedValues: Bool { return false }
  public static var _isReadableByHost: Bool { return false }
}
extension PreferenceKey where Value: ExpressibleByNilLiteral {
  public static var defaultValue: Value { return nil }
}

/// Preference values written by views, read by `onPreferenceChange`. Values
/// flow up through the node tree: each node merges its children's.
internal final class _PreferenceNode<K: PreferenceKey>: _ViewNode {
  let value: K.Value
  init(value: K.Value, content: _ViewNode, environment: EnvironmentValues) {
    self.value = value
    super.init(environment: environment, children: [content])
  }
  override func preference(_ key: ObjectIdentifier, into values: inout [Any]) {
    if key == ObjectIdentifier(K.self) { values.append(value) }
    super.preference(key, into: &values)
  }
}

@frozen
public struct _PreferenceWritingModifier<Key: PreferenceKey>: ViewModifier {
  public var value: Key.Value
  @inlinable public init(key: Key.Type = Key.self, value: Key.Value) { self.value = value }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let content = body(_Graph(), inputs).node
    return _ViewOutputs(_PreferenceNode<Key>(value: modifier.value.value, content: content, environment: inputs.environment))
  }
  public func body(content: Content) -> Never { fatalError("no body") }
  public typealias Body = Never
}

@frozen
public struct _PreferenceActionModifier<Key: PreferenceKey>: ViewModifier where Key.Value: Equatable {
  public var action: (Key.Value) -> Void
  @inlinable public init(action: @escaping (Key.Value) -> Void) { self.action = action }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let content = body(_Graph(), inputs).node
    let action = modifier.value.action
    let last = inputs.base.context.store(inputs.base.path + "#pref") { _Box<Key.Value?>(nil) }
    let node = _CallbackNode(content: content, environment: inputs.environment)
    node.afterLayout = { n in
      var values: [Any] = []
      n.preference(ObjectIdentifier(Key.self), into: &values)
      var v = Key.defaultValue
      for case let x as Key.Value in values { Key.reduce(value: &v) { x } }
      if last.value != v {
        last.value = v
        DispatchQueue.main.async { action(v) }
      }
    }
    return _ViewOutputs(node)
  }
  public func body(content: Content) -> Never { fatalError("no body") }
  public typealias Body = Never
}

extension View {
  public func preference<K: PreferenceKey>(key: K.Type = K.self, value: K.Value) -> some View {
    return modifier(_PreferenceWritingModifier<K>(value: value))
  }
  public func onPreferenceChange<K: PreferenceKey>(_ key: K.Type = K.self,
                                                   perform action: @escaping (K.Value) -> Void) -> some View
    where K.Value: Equatable {
    return modifier(_PreferenceActionModifier<K>(action: action))
  }
}

final class _Box<T> {
  var value: T
  init(_ v: T) { value = v }
}

/// A node that runs callbacks as it is laid out.
internal final class _CallbackNode: _ViewNode {
  var afterLayout: ((_ViewNode) -> Void)?
  init(content: _ViewNode, environment: EnvironmentValues) {
    super.init(environment: environment, children: [content])
  }
  override func place(in rect: CGRect) {
    super.place(in: rect)
    afterLayout?(self)
  }
}

// MARK: - custom layouts

public struct LayoutProperties: Sendable {
  public var stackOrientation: Axis?
  public init() { stackOrientation = nil }
}

public struct ViewSpacing: Sendable {
  internal var value: CGFloat
  public static let zero = ViewSpacing(value: 0)
  public init() { value = 8 }
  internal init(value: CGFloat) { self.value = value }
  public func distance(to next: ViewSpacing, along axis: Axis) -> CGFloat { return max(value, next.value) }
  public mutating func formUnion(_ other: ViewSpacing, edges: Edge.Set = .all) { value = max(value, other.value) }
  public func union(_ other: ViewSpacing, edges: Edge.Set = .all) -> ViewSpacing {
    var s = self
    s.formUnion(other, edges: edges)
    return s
  }
}

public struct LayoutSubview: Equatable {
  internal let node: _ViewNode
  internal init(node: _ViewNode) { self.node = node }
  public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { return node.sizeThatFits(proposal) }
  public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
    let s = node.sizeThatFits(proposal)
    return ViewDimensions(width: s.width, height: s.height)
  }
  public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
    let s = node.sizeThatFits(proposal)
    let origin = CGPoint(x: position.x - s.width * anchor.x, y: position.y - s.height * anchor.y)
    node.place(in: CGRect(origin: origin, size: s))
  }
  public var priority: Double { return node.layoutPriority }
  public var spacing: ViewSpacing { return ViewSpacing() }
  public subscript<K: LayoutValueKey>(key: K.Type) -> K.Value {
    return (node.layoutValues[ObjectIdentifier(key)] as? K.Value) ?? K.defaultValue
  }
  public static func == (a: LayoutSubview, b: LayoutSubview) -> Bool { return a.node === b.node }
}

public protocol LayoutValueKey {
  associatedtype Value
  static var defaultValue: Value { get }
}

public struct LayoutSubviews: Equatable, RandomAccessCollection {
  internal let subviews: [LayoutSubview]
  public typealias Element = LayoutSubview
  public typealias Index = Int
  public typealias SubSequence = LayoutSubviews
  public var startIndex: Int { return 0 }
  public var endIndex: Int { return subviews.count }
  public subscript(index: Int) -> LayoutSubview { return subviews[index] }
  public subscript(bounds: Range<Int>) -> LayoutSubviews { return LayoutSubviews(subviews: Array(subviews[bounds])) }
  public var layoutDirection: LayoutDirection { return .leftToRight }
  public static func == (a: LayoutSubviews, b: LayoutSubviews) -> Bool { return a.subviews == b.subviews }
}

public protocol Layout: Animatable {
  static var layoutProperties: LayoutProperties { get }
  associatedtype Cache = Void
  func makeCache(subviews: Subviews) -> Cache
  func updateCache(_ cache: inout Cache, subviews: Subviews)
  func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache)
  func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                         subviews: Subviews, cache: inout Cache) -> CGFloat?
  func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                         subviews: Subviews, cache: inout Cache) -> CGFloat?
  static func _makeLayoutView(root: _GraphValue<Self>, inputs: _ViewInputs,
                              body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs
  typealias Subviews = LayoutSubviews
}

extension Layout {
  public static var layoutProperties: LayoutProperties { return LayoutProperties() }
  public func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = makeCache(subviews: subviews) }
  public func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing { return ViewSpacing() }
  public func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                                subviews: Subviews, cache: inout Cache) -> CGFloat? { return nil }
  public func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                                subviews: Subviews, cache: inout Cache) -> CGFloat? { return nil }
  public static func _makeLayoutView(root: _GraphValue<Self>, inputs: _ViewInputs,
                                     body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
    let children = body(_Graph(), inputs).nodes
    return _ViewOutputs(_CustomLayoutNode(layout: root.value, environment: inputs.environment, children: children))
  }
  /// `MyLayout { ... }`: the layout applied to its content.
  public func callAsFunction<V: View>(@ViewBuilder _ content: () -> V) -> some View {
    return _VariadicView.Tree(root: _LayoutRoot(self), content: content())
  }
}
extension Layout where Cache == () {
  public func makeCache(subviews: Subviews) -> () { return () }
}

@frozen
public struct _LayoutRoot<L: Layout>: _VariadicView_UnaryViewRoot, _StackRoot {
  @usableFromInline var layout: L
  @inlinable init(_ layout: L) { self.layout = layout }
  func makeNode(_ children: [_ViewNode], environment: EnvironmentValues) -> _ViewNode {
    return _CustomLayoutNode(layout: layout, environment: environment, children: children)
  }
}

internal final class _CustomLayoutNode<L: Layout>: _ViewNode {
  let layout: L
  var cache: L.Cache?
  init(layout: L, environment: EnvironmentValues, children: [_ViewNode]) {
    self.layout = layout
    super.init(environment: environment, children: children)
  }
  var subviews: LayoutSubviews { return LayoutSubviews(subviews: children.map { LayoutSubview(node: $0) }) }
  func withCache<T>(_ f: (inout L.Cache) -> T) -> T {
    let s = subviews
    var c = cache ?? layout.makeCache(subviews: s)
    let r = f(&c)
    cache = c
    return r
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    let s = subviews
    return withCache { layout.sizeThatFits(proposal: proposal, subviews: s, cache: &$0) }
  }
  override func place(in rect: CGRect) {
    frame = rect
    let s = subviews
    withCache { layout.placeSubviews(in: rect, proposal: ProposedViewSize(rect.size), subviews: s, cache: &$0) }
  }
}

@frozen
public struct AnyLayout: Layout {
  @usableFromInline var storage: _AnyLayoutBox
  public init<L: Layout>(_ layout: L) { storage = _ConcreteLayoutBox(layout) }
  public typealias Cache = Any
  public typealias AnimatableData = EmptyAnimatableData
  public func makeCache(subviews: Subviews) -> Any { return storage.makeCache(subviews) }
  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Any) -> CGSize {
    return storage.sizeThatFits(proposal, subviews, &cache)
  }
  public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Any) {
    storage.place(bounds, proposal, subviews, &cache)
  }
}
@usableFromInline class _AnyLayoutBox {
  func makeCache(_ s: LayoutSubviews) -> Any { return () }
  func sizeThatFits(_ p: ProposedViewSize, _ s: LayoutSubviews, _ c: inout Any) -> CGSize { return ._zero }
  func place(_ b: CGRect, _ p: ProposedViewSize, _ s: LayoutSubviews, _ c: inout Any) {}
}
final class _ConcreteLayoutBox<L: Layout>: _AnyLayoutBox {
  let layout: L
  init(_ l: L) { layout = l }
  override func makeCache(_ s: LayoutSubviews) -> Any { return layout.makeCache(subviews: s) }
  override func sizeThatFits(_ p: ProposedViewSize, _ s: LayoutSubviews, _ c: inout Any) -> CGSize {
    var cache = (c as? L.Cache) ?? layout.makeCache(subviews: s)
    defer { c = cache }
    return layout.sizeThatFits(proposal: p, subviews: s, cache: &cache)
  }
  override func place(_ b: CGRect, _ p: ProposedViewSize, _ s: LayoutSubviews, _ c: inout Any) {
    var cache = (c as? L.Cache) ?? layout.makeCache(subviews: s)
    defer { c = cache }
    layout.placeSubviews(in: b, proposal: p, subviews: s, cache: &cache)
  }
}

extension _VStackLayout: Layout {
  public typealias AnimatableData = EmptyAnimatableData
  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    return makeNode(subviews.subviews.map { $0.node }, environment: EnvironmentValues()).sizeThatFits(proposal)
  }
  public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    makeNode(subviews.subviews.map { $0.node }, environment: EnvironmentValues()).place(in: bounds)
  }
}
extension _HStackLayout: Layout {
  public typealias AnimatableData = EmptyAnimatableData
  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    return makeNode(subviews.subviews.map { $0.node }, environment: EnvironmentValues()).sizeThatFits(proposal)
  }
  public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    makeNode(subviews.subviews.map { $0.node }, environment: EnvironmentValues()).place(in: bounds)
  }
}
extension _ZStackLayout: Layout {
  public typealias AnimatableData = EmptyAnimatableData
  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    return makeNode(subviews.subviews.map { $0.node }, environment: EnvironmentValues()).sizeThatFits(proposal)
  }
  public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    makeNode(subviews.subviews.map { $0.node }, environment: EnvironmentValues()).place(in: bounds)
  }
}
public typealias VStackLayout = _VStackLayout
public typealias HStackLayout = _HStackLayout
public typealias ZStackLayout = _ZStackLayout

// MARK: - AppKit views in SwiftUI

public struct _LayoutTraits {
  internal init() {}
}
public struct _ProposedSize {
  public var width: CGFloat?
  public var height: CGFloat?
  internal init(width: CGFloat?, height: CGFloat?) {
    self.width = width
    self.height = height
  }
}
public enum _IdentifiedViewTree {
  case empty
  case proxy(_IdentifiedViewProxy)
}
public struct _IdentifiedViewProxy {
  internal init() {}
}
public struct _PlatformViewRepresentableLayoutOptions: OptionSet {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
}

@MainActor @preconcurrency
public struct NSViewRepresentableContext<Representable: NSViewRepresentable> {
  public let coordinator: Representable.Coordinator
  public var transaction: Transaction
  public var environment: EnvironmentValues
}
@MainActor @preconcurrency
public struct NSViewControllerRepresentableContext<Representable: NSViewControllerRepresentable> {
  public let coordinator: Representable.Coordinator
  public var transaction: Transaction
  public var environment: EnvironmentValues
}

@MainActor @preconcurrency
public protocol NSViewRepresentable: View where Body == Never {
  associatedtype NSViewType: NSView
  func makeNSView(context: Context) -> NSViewType
  func updateNSView(_ nsView: NSViewType, context: Context)
  static func _modifyBridgedViewInputs(_ inputs: inout _ViewInputs)
  func _identifiedViewTree(in nsView: NSViewType) -> _IdentifiedViewTree
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSViewType, context: Context) -> CGSize?
  func _overrideSizeThatFits(_ size: inout CGSize, in proposedSize: _ProposedSize, nsView: NSViewType)
  func _overrideLayoutTraits(_ layoutTraits: inout _LayoutTraits, for nsView: NSViewType)
  static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator)
  associatedtype Coordinator = Void
  func makeCoordinator() -> Coordinator
  static var _invalidatesSizeOnConstraintChanges: Bool { get }
  static func _layoutOptions(_ provider: NSViewType) -> _PlatformViewRepresentableLayoutOptions
  typealias Context = NSViewRepresentableContext<Self>
}

extension NSViewRepresentable {
  public var body: Never { return fatalError("NSViewRepresentable has no body") }
  public static func _modifyBridgedViewInputs(_ inputs: inout _ViewInputs) {}
  public func _identifiedViewTree(in nsView: NSViewType) -> _IdentifiedViewTree { return .empty }
  public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSViewType, context: Context) -> CGSize? { return nil }
  public func _overrideSizeThatFits(_ size: inout CGSize, in proposedSize: _ProposedSize, nsView: NSViewType) {}
  public func _overrideLayoutTraits(_ layoutTraits: inout _LayoutTraits, for nsView: NSViewType) {}
  public static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator) {}
  public static var _invalidatesSizeOnConstraintChanges: Bool { return true }
  public static func _layoutOptions(_ provider: NSViewType) -> _PlatformViewRepresentableLayoutOptions { return [] }

  nonisolated public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
    return MainActor.assumeIsolated {
      var rep = view.value
      _installDynamicProperties(&rep, inputs: inputs)
      let host = inputs.base.context.store(inputs.base.path + "#nsview") { _PlatformViewBox() }
      let coordinator: Coordinator
      if let c = host.coordinator as? Coordinator {
        coordinator = c
      } else {
        coordinator = rep.makeCoordinator()
        host.coordinator = coordinator
      }
      let context = Context(coordinator: coordinator, transaction: Transaction(), environment: inputs.environment)
      let nsView: NSViewType
      if let v = host.view as? NSViewType {
        nsView = v
      } else {
        nsView = rep.makeNSView(context: context)
        host.view = nsView
      }
      rep.updateNSView(nsView, context: context)
      let sizer: (ProposedViewSize) -> CGSize? = { p in rep.sizeThatFits(p, nsView: nsView, context: context) }
      return _ViewOutputs(_PlatformViewNode(view: nsView, context: inputs.base.context, sizer: sizer,
                                            environment: inputs.environment))
    }
  }
  nonisolated public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
    return _ViewListOutputs([_makeView(view: view, inputs: inputs.base).node])
  }
}
extension NSViewRepresentable where Coordinator == () {
  public func makeCoordinator() -> () { return () }
}

@MainActor @preconcurrency
public protocol NSViewControllerRepresentable: View where Body == Never {
  associatedtype NSViewControllerType: NSViewController
  func makeNSViewController(context: Context) -> NSViewControllerType
  func updateNSViewController(_ nsViewController: NSViewControllerType, context: Context)
  func _identifiedViewTree(in nsViewController: NSViewControllerType) -> _IdentifiedViewTree
  func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: NSViewControllerType, context: Context) -> CGSize?
  static func dismantleNSViewController(_ nsViewController: NSViewControllerType, coordinator: Coordinator)
  associatedtype Coordinator = Void
  func makeCoordinator() -> Coordinator
  static var _invalidatesSizeOnConstraintChanges: Bool { get }
  static func _layoutOptions(_ provider: NSViewControllerType) -> _PlatformViewRepresentableLayoutOptions
  typealias Context = NSViewControllerRepresentableContext<Self>
}

extension NSViewControllerRepresentable {
  public var body: Never { return fatalError("NSViewControllerRepresentable has no body") }
  public func _identifiedViewTree(in nsViewController: NSViewControllerType) -> _IdentifiedViewTree { return .empty }
  public func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: NSViewControllerType,
                           context: Context) -> CGSize? { return nil }
  public static func dismantleNSViewController(_ nsViewController: NSViewControllerType, coordinator: Coordinator) {}
  public static var _invalidatesSizeOnConstraintChanges: Bool { return true }
  public static func _layoutOptions(_ provider: NSViewControllerType) -> _PlatformViewRepresentableLayoutOptions {
    return []
  }
  nonisolated public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
    return MainActor.assumeIsolated {
      var rep = view.value
      _installDynamicProperties(&rep, inputs: inputs)
      let host = inputs.base.context.store(inputs.base.path + "#nsvc") { _PlatformViewBox() }
      let coordinator: Coordinator
      if let c = host.coordinator as? Coordinator {
        coordinator = c
      } else {
        coordinator = rep.makeCoordinator()
        host.coordinator = coordinator
      }
      let context = Context(coordinator: coordinator, transaction: Transaction(), environment: inputs.environment)
      let vc: NSViewControllerType
      if let c = host.controller as? NSViewControllerType {
        vc = c
      } else {
        vc = rep.makeNSViewController(context: context)
        host.controller = vc
      }
      rep.updateNSViewController(vc, context: context)
      let sizer: (ProposedViewSize) -> CGSize? = { p in rep.sizeThatFits(p, nsViewController: vc, context: context) }
      return _ViewOutputs(_PlatformViewNode(view: vc.view, context: inputs.base.context, sizer: sizer,
                                            environment: inputs.environment))
    }
  }
  nonisolated public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
    return _ViewListOutputs([_makeView(view: view, inputs: inputs.base).node])
  }
}
extension NSViewControllerRepresentable where Coordinator == () {
  public func makeCoordinator() -> () { return () }
}

/// The AppKit view (and its coordinator) behind a representable, kept
/// across rebuilds.
final class _PlatformViewBox {
  var view: NSView?
  var controller: NSViewController?
  var coordinator: Any?
}

private typealias _DrawInFn = @convention(c) (AnyObject, Selector, CGContext, ObjCBool) -> Void
/// Draws an AppKit view (and its subviews) into `context`, whose space is
/// its (flipped) superview's.
@MainActor internal func _drawAppKitView(_ v: NSView, _ context: CGContext) {
  let sel = NSSelectorFromString("_bn_drawIn:parentFlipped:")
  guard let m = class_getMethodImplementation(object_getClass(v), sel) else { return }
  unsafeBitCast(m, to: _DrawInFn.self)(v, sel, context, ObjCBool(true))
}

/// An AppKit view placed as a subview of the hosting view.
internal final class _PlatformViewNode: _ViewNode {
  let view: NSView
  weak var context: _RenderContext?
  let sizer: (ProposedViewSize) -> CGSize?
  init(view: NSView, context: _RenderContext, sizer: @escaping (ProposedViewSize) -> CGSize?, environment: EnvironmentValues) {
    self.view = view
    self.context = context
    self.sizer = sizer
    super.init(environment: environment)
  }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    if let s = MainActor.assumeIsolated({ sizer(proposal) }) { return s }
    return proposal.replacingUnspecifiedDimensions(by: CGSize(width: 100, height: 22))
  }
  override func place(in rect: CGRect) {
    frame = rect
    let v = view
    MainActor.assumeIsolated {
      if let host = context?.hostView, v.superview !== host { host.addSubview(v) }
      v.frame = NSMakeRect(rect._minX, rect._minY, rect._width, rect._height)
    }
    context?.livePlatformViews.insert(ObjectIdentifier(v))
  }
  override func collectPlatformViews(_ into: inout [NSView]) { into.append(view) }
  /// The AppKit view takes the click where it is on top and its own hit
  /// testing finds something (the hosting view then hands it the event).
  override func hit(_ point: CGPoint) -> _ViewNode? {
    guard frame._contains(point) else { return nil }
    let v = view
    let found = MainActor.assumeIsolated { () -> Bool in
      !v.isHidden && v.hitTest(NSMakePoint(point.x, point.y)) != nil
    }
    return found ? self : nil
  }
  /// Drawn here, in SwiftUI's order, rather than after all of the host's
  /// own drawing (see NSHostingView._bn_drawsOwnSubviews).
  override func draw(_ context: CGContext) {
    let v = view
    MainActor.assumeIsolated { _drawAppKitView(v, context) }
  }
}

// MARK: - commands

public struct _ResolvedCommands {
  internal var groups: [_CommandGroupEntry] = []
  internal init() {}
}
internal struct _CommandGroupEntry {
  enum Where { case before, after, replacing, menu(String) }
  var placement: CommandGroupPlacement?
  var position: Where
  var items: [_MenuItemEntry]
}
/// A menu item built from a command's content.
internal struct _MenuItemEntry {
  var title: String
  var action: (() -> Void)?
  var shortcut: KeyboardShortcut?
  var children: [_MenuItemEntry]?
  var isSeparator = false
}

public struct _CommandsInputs {
  internal var resolved: _Box<_ResolvedCommands>
  internal init() { resolved = _Box(_ResolvedCommands()) }
}
public struct _CommandsOutputs {
  internal init() {}
}

public protocol Commands {
  associatedtype Body: Commands
  @CommandsBuilder var body: Self.Body { get }
  static func _makeCommands(content: _GraphValue<Self>, inputs: _CommandsInputs) -> _CommandsOutputs
  func _resolve(into resolved: inout _ResolvedCommands)
}

extension Commands {
  public static func _makeCommands(content: _GraphValue<Self>, inputs: _CommandsInputs) -> _CommandsOutputs {
    content.value._resolve(into: &inputs.resolved.value)
    return _CommandsOutputs()
  }
  public func _resolve(into resolved: inout _ResolvedCommands) {
    if Body.self != Never.self { body._resolve(into: &resolved) }
  }
}

extension Never: Commands {}

@frozen
public struct EmptyCommands: Commands {
  @inlinable public init() {}
  public typealias Body = Never
  public var body: Never { return fatalError("EmptyCommands has no body") }
  public func _resolve(into resolved: inout _ResolvedCommands) {}
}

@frozen
public struct TupleCommandContent<T>: Commands {
  public var value: T
  public init(_ value: T) { self.value = value }
  public typealias Body = Never
  public var body: Never { return fatalError("no body") }
  public func _resolve(into resolved: inout _ResolvedCommands) {
    var r = resolved
    _forEachTupleElement(value) { (c: Any) in
      if let cmd = c as? any Commands { cmd._resolveAny(into: &r) }
    }
    resolved = r
  }
}
extension Commands {
  fileprivate func _resolveAny(into r: inout _ResolvedCommands) { _resolve(into: &r) }
}

@resultBuilder
public struct CommandsBuilder {
  @_alwaysEmitIntoClient public static func buildExpression<Content: Commands>(_ content: Content) -> Content { content }
  @_alwaysEmitIntoClient public static func buildBlock() -> EmptyCommands { EmptyCommands() }
  @_alwaysEmitIntoClient public static func buildBlock<C: Commands>(_ content: C) -> C { content }
  @_alwaysEmitIntoClient
  public static func buildBlock<each Content: Commands>(_ content: repeat each Content) -> some Commands {
    return TupleCommandContent((repeat each content))
  }
  @_alwaysEmitIntoClient public static func buildOptional<C: Commands>(_ c: C?) -> C? { c }
}
extension Optional: Commands where Wrapped: Commands {
  public typealias Body = Never
  public var body: Never { return fatalError("no body") }
  public func _resolve(into resolved: inout _ResolvedCommands) { self?._resolve(into: &resolved) }
}

public struct CommandGroupPlacement: Sendable {
  let name: String
  public static let appInfo = CommandGroupPlacement(name: "appInfo")
  public static let appSettings = CommandGroupPlacement(name: "appSettings")
  public static let systemServices = CommandGroupPlacement(name: "systemServices")
  public static let appVisibility = CommandGroupPlacement(name: "appVisibility")
  public static let appTermination = CommandGroupPlacement(name: "appTermination")
  public static let newItem = CommandGroupPlacement(name: "newItem")
  public static let saveItem = CommandGroupPlacement(name: "saveItem")
  public static let importExport = CommandGroupPlacement(name: "importExport")
  public static let printItem = CommandGroupPlacement(name: "printItem")
  public static let undoRedo = CommandGroupPlacement(name: "undoRedo")
  public static let pasteboard = CommandGroupPlacement(name: "pasteboard")
  public static let textEditing = CommandGroupPlacement(name: "textEditing")
  public static let textFormatting = CommandGroupPlacement(name: "textFormatting")
  public static let toolbar = CommandGroupPlacement(name: "toolbar")
  public static let sidebar = CommandGroupPlacement(name: "sidebar")
  public static let windowSize = CommandGroupPlacement(name: "windowSize")
  public static let windowList = CommandGroupPlacement(name: "windowList")
  public static let singleWindowList = CommandGroupPlacement(name: "singleWindowList")
  public static let windowArrangement = CommandGroupPlacement(name: "windowArrangement")
  public static let help = CommandGroupPlacement(name: "help")
}

/// Turns a view tree of buttons, dividers and menus into menu items.
internal func _menuItems<V: View>(_ content: V) -> [_MenuItemEntry] {
  let context = _RenderContext()
  let node = _makeNode(content, inputs: _ViewInputs(_GraphInputs(environment: EnvironmentValues(), context: context, path: "")))
  var out: [_MenuItemEntry] = []
  func walk(_ n: _ViewNode) {
    if let b = n as? _ButtonNode {
      out.append(_MenuItemEntry(title: b.title, action: b.action, shortcut: b.environment._keyboardShortcut, children: nil))
      return
    }
    if n is _DividerNode {
      out.append(_MenuItemEntry(title: "", action: nil, shortcut: nil, children: nil, isSeparator: true))
      return
    }
    for c in n.children { walk(c) }
  }
  walk(node)
  return out
}

public struct CommandGroup<Content: View>: Commands {
  let entry: (_ResolvedCommands) -> _CommandGroupEntry
  public init(before group: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {
    let content = addition()
    entry = { _ in _CommandGroupEntry(placement: group, position: .before, items: _menuItems(content)) }
  }
  public init(after group: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {
    let content = addition()
    entry = { _ in _CommandGroupEntry(placement: group, position: .after, items: _menuItems(content)) }
  }
  public init(replacing group: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {
    let content = addition()
    entry = { _ in _CommandGroupEntry(placement: group, position: .replacing, items: _menuItems(content)) }
  }
  public typealias Body = Never
  public var body: Never { return fatalError("CommandGroup has no body") }
  public func _resolve(into resolved: inout _ResolvedCommands) { resolved.groups.append(entry(resolved)) }
}

public struct CommandMenu<Content: View>: Commands {
  let name: String
  let content: Content
  public init(_ nameKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
    name = Text(nameKey)._string
    self.content = content()
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ name: S, @ViewBuilder content: () -> Content) {
    self.name = String(name)
    self.content = content()
  }
  public init(_ name: Text, @ViewBuilder content: () -> Content) {
    self.name = name._string
    self.content = content()
  }
  public typealias Body = Never
  public var body: Never { return fatalError("CommandMenu has no body") }
  public func _resolve(into resolved: inout _ResolvedCommands) {
    resolved.groups.append(_CommandGroupEntry(placement: nil, position: .menu(name), items: _menuItems(content)))
  }
}

public struct SidebarCommands: Commands {
  public init() {}
  public typealias Body = Never
  public var body: Never { return fatalError("no body") }
  public func _resolve(into resolved: inout _ResolvedCommands) {}
}
public struct ToolbarCommands: Commands {
  public init() {}
  public typealias Body = Never
  public var body: Never { return fatalError("no body") }
  public func _resolve(into resolved: inout _ResolvedCommands) {}
}
public struct TextEditingCommands: Commands {
  public init() {}
  public typealias Body = Never
  public var body: Never { return fatalError("no body") }
  public func _resolve(into resolved: inout _ResolvedCommands) {}
}

// MARK: - toolbars

public struct _ToolbarItemList {
  internal var items: [_ToolbarEntry] = []
  internal init() {}
}
internal struct _ToolbarEntry {
  var id: String?
  var placement: ToolbarItemPlacement
  var make: () -> AnyView
}
public struct _ToolbarInputs {
  internal var base: _GraphInputs
  internal var list: _Box<_ToolbarItemList>
}
public struct _ToolbarOutputs {
  internal init() {}
}

public protocol ToolbarContent {
  associatedtype Body: ToolbarContent
  @ToolbarContentBuilder var body: Self.Body { get }
  static func _makeToolbar(content: _GraphValue<Self>, inputs: _ToolbarInputs) -> _ToolbarOutputs
  static func _makeContent(content: _GraphValue<Self>, inputs: _GraphInputs, resolved: inout _ToolbarItemList)
}
public protocol CustomizableToolbarContent: ToolbarContent where Body: CustomizableToolbarContent {}

extension ToolbarContent {
  public static func _makeToolbar(content: _GraphValue<Self>, inputs: _ToolbarInputs) -> _ToolbarOutputs {
    _makeContent(content: content, inputs: inputs.base, resolved: &inputs.list.value)
    return _ToolbarOutputs()
  }
  public static func _makeContent(content: _GraphValue<Self>, inputs: _GraphInputs, resolved: inout _ToolbarItemList) {
    if Body.self == Never.self { return }
    let body = content.value.body
    Body._makeContent(content: _GraphValue({ body }), inputs: inputs, resolved: &resolved)
  }
}

extension Never: ToolbarContent, CustomizableToolbarContent {}

public struct ToolbarItemPlacement: Sendable {
  let id: Int
  public static let automatic = ToolbarItemPlacement(id: 0)
  public static let principal = ToolbarItemPlacement(id: 1)
  public static let navigation = ToolbarItemPlacement(id: 2)
  public static let primaryAction = ToolbarItemPlacement(id: 3)
  public static let secondaryAction = ToolbarItemPlacement(id: 4)
  public static let status = ToolbarItemPlacement(id: 5)
  public static let confirmationAction = ToolbarItemPlacement(id: 6)
  public static let cancellationAction = ToolbarItemPlacement(id: 7)
  public static let destructiveAction = ToolbarItemPlacement(id: 8)
}

public struct ToolbarItem<ID, Content: View>: ToolbarContent {
  let id: String?
  let placement: ToolbarItemPlacement
  let content: Content
  public typealias Body = Never
  public var body: Never { return fatalError("ToolbarItem has no body") }
  public static func _makeContent(content: _GraphValue<ToolbarItem>, inputs: _GraphInputs, resolved: inout _ToolbarItemList) {
    let item = content.value
    let c = item.content
    resolved.items.append(_ToolbarEntry(id: item.id, placement: item.placement, make: { AnyView(c) }))
  }
}
extension ToolbarItem: CustomizableToolbarContent where ID == String {}
extension ToolbarItem where ID == () {
  public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
    id = nil
    self.placement = placement
    self.content = content()
  }
}
extension ToolbarItem where ID == String {
  public init(id: String, placement: ToolbarItemPlacement = .automatic, showsByDefault: Bool = true,
              @ViewBuilder content: () -> Content) {
    self.id = id
    self.placement = placement
    self.content = content()
  }
  public init(id: String, placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
    self.init(id: id, placement: placement, showsByDefault: true, content: content)
  }
}

public struct ToolbarItemGroup<Content: View>: ToolbarContent {
  let placement: ToolbarItemPlacement
  let content: Content
  public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
    self.placement = placement
    self.content = content()
  }
  public typealias Body = Never
  public var body: Never { return fatalError("ToolbarItemGroup has no body") }
  public static func _makeContent(content: _GraphValue<ToolbarItemGroup>, inputs: _GraphInputs,
                                  resolved: inout _ToolbarItemList) {
    let g = content.value
    let c = g.content
    resolved.items.append(_ToolbarEntry(id: nil, placement: g.placement, make: { AnyView(c) }))
  }
}

@frozen
public struct TupleToolbarContent<T>: ToolbarContent {
  public var value: T
  public init(_ value: T) { self.value = value }
  public typealias Body = Never
  public var body: Never { return fatalError("no body") }
  public static func _makeContent(content: _GraphValue<TupleToolbarContent>, inputs: _GraphInputs,
                                  resolved: inout _ToolbarItemList) {
    var r = resolved
    _forEachTupleElement(content.value.value) { (c: Any) in
      if let t = c as? any ToolbarContent { t._makeContentAny(inputs: inputs, resolved: &r) }
    }
    resolved = r
  }
}
extension TupleToolbarContent: CustomizableToolbarContent {}
extension ToolbarContent {
  fileprivate func _makeContentAny(inputs: _GraphInputs, resolved: inout _ToolbarItemList) {
    let me = self
    Self._makeContent(content: _GraphValue({ me }), inputs: inputs, resolved: &resolved)
  }
}
extension Optional: ToolbarContent where Wrapped: ToolbarContent {
  public typealias Body = Never
  public var body: Never { return fatalError("no body") }
  public static func _makeContent(content: _GraphValue<Optional>, inputs: _GraphInputs, resolved: inout _ToolbarItemList) {
    if let w = content.value { w._makeContentAny(inputs: inputs, resolved: &resolved) }
  }
}
extension Optional: CustomizableToolbarContent where Wrapped: CustomizableToolbarContent {}

@resultBuilder
public struct ToolbarContentBuilder {
  @_alwaysEmitIntoClient public static func buildExpression<C: ToolbarContent>(_ content: C) -> C { content }
  @_alwaysEmitIntoClient public static func buildBlock<C: ToolbarContent>(_ content: C) -> C { content }
  @_alwaysEmitIntoClient
  public static func buildBlock<each Content: ToolbarContent>(_ content: repeat each Content) -> some ToolbarContent {
    return TupleToolbarContent((repeat each content))
  }
  @_alwaysEmitIntoClient
  public static func buildBlock<each Content: CustomizableToolbarContent>(_ content: repeat each Content)
    -> some CustomizableToolbarContent {
    return TupleToolbarContent((repeat each content))
  }
  @_alwaysEmitIntoClient public static func buildIf<C: ToolbarContent>(_ c: C?) -> C? { c }
  /// Views inside a toolbar are automatic items.
  @_alwaysEmitIntoClient
  public static func buildExpression<V: View>(_ content: V) -> ToolbarItem<(), V> {
    return ToolbarItem(placement: .automatic) { content }
  }
}

public struct ToolbarPlacement: Sendable {
  let id: Int
  public static let automatic = ToolbarPlacement(id: 0)
  public static let windowToolbar = ToolbarPlacement(id: 1)
}

public struct ToolbarDefaultItemKind: Sendable {
  let id: Int
  public static let sidebarToggle = ToolbarDefaultItemKind(id: 0)
  public static let title = ToolbarDefaultItemKind(id: 1)
}

// MARK: - styles

public struct LabelStyleConfiguration {
  public struct Title: View {
    let node: () -> AnyView
    public typealias Body = Never
    public var body: Never { return fatalError("no body") }
    public static func _makeView(view: _GraphValue<Title>, inputs: _ViewInputs) -> _ViewOutputs {
      return AnyView._makeView(view: _GraphValue({ view.value.node() }), inputs: inputs)
    }
  }
  public struct Icon: View {
    let node: () -> AnyView
    public typealias Body = Never
    public var body: Never { return fatalError("no body") }
    public static func _makeView(view: _GraphValue<Icon>, inputs: _ViewInputs) -> _ViewOutputs {
      return AnyView._makeView(view: _GraphValue({ view.value.node() }), inputs: inputs)
    }
  }
  public var title: Title
  public var icon: Icon
}

public protocol LabelStyle {
  associatedtype Body: View
  @ViewBuilder @MainActor func makeBody(configuration: Configuration) -> Body
  typealias Configuration = LabelStyleConfiguration
}

public struct LabeledContentStyleConfiguration {
  public struct Label: View {
    let content: AnyView
    public typealias Body = Never
    public var body: Never { return fatalError("no body") }
    public static func _makeView(view: _GraphValue<Label>, inputs: _ViewInputs) -> _ViewOutputs {
      return AnyView._makeView(view: _GraphValue({ view.value.content }), inputs: inputs)
    }
  }
  public struct Content: View {
    let content: AnyView
    public typealias Body = Never
    public var body: Never { return fatalError("no body") }
    public static func _makeView(view: _GraphValue<Content>, inputs: _ViewInputs) -> _ViewOutputs {
      return AnyView._makeView(view: _GraphValue({ view.value.content }), inputs: inputs)
    }
  }
  public let label: Label
  public let content: Content
}

public protocol LabeledContentStyle {
  associatedtype Body: View
  @ViewBuilder @MainActor func makeBody(configuration: Configuration) -> Body
  typealias Configuration = LabeledContentStyleConfiguration
}

public struct ProgressViewStyleConfiguration {
  public struct Label: View {
    let content: AnyView
    public typealias Body = Never
    public var body: Never { return fatalError("no body") }
    public static func _makeView(view: _GraphValue<Label>, inputs: _ViewInputs) -> _ViewOutputs {
      return AnyView._makeView(view: _GraphValue({ view.value.content }), inputs: inputs)
    }
  }
  public struct CurrentValueLabel: View {
    let content: AnyView
    public typealias Body = Never
    public var body: Never { fatalError("no body") }
    public static func _makeView(view: _GraphValue<CurrentValueLabel>, inputs: _ViewInputs) -> _ViewOutputs {
      return AnyView._makeView(view: _GraphValue({ view.value.content }), inputs: inputs)
    }
  }
  public let fractionCompleted: Double?
  public var label: Label?
  public var currentValueLabel: CurrentValueLabel?
}

public protocol ProgressViewStyle {
  associatedtype Body: View
  @ViewBuilder @MainActor func makeBody(configuration: Configuration) -> Body
  typealias Configuration = ProgressViewStyleConfiguration
}

// MARK: - focused values

public protocol FocusedValueKey {
  associatedtype Value
}
public struct FocusedValues {
  internal var values: [ObjectIdentifier: Any] = [:]
  public subscript<K: FocusedValueKey>(key: K.Type) -> K.Value? {
    get { return values[ObjectIdentifier(key)] as? K.Value }
    set { values[ObjectIdentifier(key)] = newValue }
  }
}
