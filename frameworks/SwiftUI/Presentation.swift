// Presentations (alerts, confirmation dialogs, sheets, popovers,
// inspectors, file importers), gestures, toolbars, accessibility, and the
// modifiers that only carry hints for platforms with more chrome (they keep
// the content as it is).

import CoreGraphics
import Dispatch
import UniformTypeIdentifiers

// MARK: - presentations

/// Content shown over its host's content while `isPresented`: a dimmed
/// backdrop and the presentation centred in a box.
internal struct _PresentationModifier<Presented: View>: ViewModifier {
  var isPresented: Binding<Bool>
  var title: String?
  var presented: () -> Presented
  var onDismiss: (() -> Void)?
  var style: Style
  enum Style { case alert, sheet, popover }
  typealias Body = Never
  func body(content: Content) -> Never { fatalError("no body") }
  static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let m = modifier.value
    let content = body(_Graph(), inputs).node
    guard m.isPresented.wrappedValue else { return _ViewOutputs(content) }
    let binding = m.isPresented
    let dismiss: () -> Void = {
      binding.wrappedValue = false
      m.onDismiss?()
    }
    var inner = inputs.named("presented")
    inner.environment[_DismissKey.self] = DismissAction(action: dismiss)
    if m.style == .alert { inner.environment._afterButtonTap = dismiss }
    var children: [_ViewNode] = []
    if let t = m.title {
      var bold = inner
      bold.environment.font = .headline
      children.append(_TextNode(string: t, font: .headline, paint: ForegroundStyle()._paint(in: bold.environment),
                                environment: bold.environment))
    }
    children += _makeNodes(m.presented(), inputs: inner)
    let stack = _StackNode(axis: m.style == .alert ? .vertical : .vertical, alignment: .center, spacing: 10,
                           environment: inner.environment, children: children)
    let box = _PaddingNode(insets: EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20),
                           environment: inner.environment, children: [stack])
    let card = _LayeredNode(primary: box, layer: _ShapeNode(shape: RoundedRectangle(cornerRadius: 10),
                                                             paint: Color._windowBackground.resolve(in: inner.environment).paint,
                                                             eoFill: false, stroke: nil, environment: inner.environment),
                            alignment: .center, behind: true, environment: inner.environment)
    let backdrop = _ShapeNode(shape: Rectangle(), paint: _Paint(r: 0, g: 0, b: 0, a: 0.25), eoFill: false, stroke: nil,
                              environment: inputs.environment)
    let over = _ZStackNode(alignment: .center, environment: inputs.environment,
                           children: [_FillNode(content: backdrop, environment: inputs.environment), card])
    return _ViewOutputs(_LayeredNode(primary: content, layer: _FillNode(content: over, environment: inputs.environment),
                                     alignment: .center, behind: false, environment: inputs.environment))
  }
}

/// Takes all of the space it is placed in.
internal final class _FillNode: _ViewNode {
  init(content: _ViewNode, environment: EnvironmentValues) { super.init(environment: environment, children: [content]) }
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { return proposal.replacingUnspecifiedDimensions() }
  override func place(in rect: CGRect) {
    frame = rect
    children[0].place(in: rect)
  }
}

struct _AfterButtonTapKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
extension EnvironmentValues {
  /// Run after a button's action (alerts close when any button is used).
  internal var _afterButtonTap: (() -> Void)? {
    get { return self[_AfterButtonTapKey.self] }
    set { self[_AfterButtonTapKey.self] = newValue }
  }
}

public struct Visibility_Placeholder {}

extension View {
  public func alert<A: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>,
                             @ViewBuilder actions: () -> A) -> some View {
    let a = actions()
    return modifier(_PresentationModifier(isPresented: isPresented, title: Text(titleKey)._string, presented: { a },
                                          onDismiss: nil, style: .alert))
  }
  public func alert<A: View, M: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>,
                                      @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View {
    let a = actions(), msg = message()
    return modifier(_PresentationModifier(isPresented: isPresented, title: Text(titleKey)._string,
                                          presented: { VStack(spacing: 10) { msg; a } }, onDismiss: nil, style: .alert))
  }
  public func alert<S: StringProtocol, A: View, M: View, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?,
                                                           @ViewBuilder actions: (T) -> A,
                                                           @ViewBuilder message: (T) -> M) -> some View {
    let content: AnyView = data.map { d in AnyView(VStack(spacing: 10) { message(d); actions(d) }) } ?? AnyView(EmptyView())
    return modifier(_PresentationModifier(isPresented: isPresented, title: String(title), presented: { content },
                                          onDismiss: nil, style: .alert))
  }
  public func alert<A: View, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?,
                                @ViewBuilder actions: (T) -> A) -> some View {
    let content: AnyView = data.map { AnyView(actions($0)) } ?? AnyView(EmptyView())
    return modifier(_PresentationModifier(isPresented: isPresented, title: Text(titleKey)._string, presented: { content },
                                          onDismiss: nil, style: .alert))
  }
  public func confirmationDialog<A: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>,
                                          titleVisibility: Visibility = .automatic,
                                          @ViewBuilder actions: () -> A) -> some View {
    let a = actions()
    return modifier(_PresentationModifier(isPresented: isPresented, title: Text(titleKey)._string, presented: { a },
                                          onDismiss: nil, style: .alert))
  }
  public func confirmationDialog<A: View>(_ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
                                          @ViewBuilder actions: () -> A) -> some View {
    let a = actions()
    return modifier(_PresentationModifier(isPresented: isPresented, title: title._string, presented: { a },
                                          onDismiss: nil, style: .alert))
  }
  public func confirmationDialog<S: StringProtocol, A: View>(_ title: S, isPresented: Binding<Bool>,
                                                             titleVisibility: Visibility = .automatic,
                                                             @ViewBuilder actions: () -> A) -> some View {
    let a = actions()
    return modifier(_PresentationModifier(isPresented: isPresented, title: String(title), presented: { a },
                                          onDismiss: nil, style: .alert))
  }
  public func confirmationDialog<A: View, M: View>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>,
                                                   titleVisibility: Visibility = .automatic, @ViewBuilder actions: () -> A,
                                                   @ViewBuilder message: () -> M) -> some View {
    let a = actions(), m = message()
    return modifier(_PresentationModifier(isPresented: isPresented, title: Text(titleKey)._string,
                                          presented: { VStack(spacing: 10) { m; a } }, onDismiss: nil, style: .alert))
  }
  public func sheet<C: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                             @ViewBuilder content: @escaping () -> C) -> some View {
    return modifier(_PresentationModifier(isPresented: isPresented, title: nil, presented: content, onDismiss: onDismiss,
                                          style: .sheet))
  }
  public func sheet<Item: Identifiable, C: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                 @ViewBuilder content: @escaping (Item) -> C) -> some View {
    let shown = Binding<Bool>(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    return modifier(_PresentationModifier(isPresented: shown, title: nil, presented: {
      item.wrappedValue.map { AnyView(content($0)) } ?? AnyView(EmptyView())
    }, onDismiss: onDismiss, style: .sheet))
  }
  public func popover<C: View>(isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                               arrowEdge: Edge = .top, @ViewBuilder content: @escaping () -> C) -> some View {
    return modifier(_PresentationModifier(isPresented: isPresented, title: nil, presented: content, onDismiss: nil,
                                          style: .popover))
  }
  public func inspector<V: View>(isPresented: Binding<Bool>, @ViewBuilder content: () -> V) -> some View {
    let side = content()
    return _InspectorView(content: self, inspector: side, isPresented: isPresented.wrappedValue)
  }
  public func inspectorColumnWidth(min: CGFloat? = nil, ideal: CGFloat, max: CGFloat? = nil) -> some View { return self }
  public func interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View { return self }
  public func presentationSizing<S: PresentationSizing>(_ sizing: S) -> some View { return self }
  public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType],
                           onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View {
    return modifier(_FileImporterModifier(isPresented: isPresented, multiple: false) { urls in
      if let u = urls.first { onCompletion(.success(u)) }
    })
  }
  public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool,
                           onCompletion: @escaping (Result<[URL], Error>) -> Void) -> some View {
    return modifier(_FileImporterModifier(isPresented: isPresented, multiple: allowsMultipleSelection) { urls in
      onCompletion(.success(urls))
    })
  }
  public func fileDialogBrowserOptions(_ options: FileDialogBrowserOptions) -> some View { return self }
  public func fileDialogDefaultDirectory(_ defaultDirectory: URL?) -> some View { return self }
}

/// File importers: there is no file panel in the container; $BITTEN_PICK
/// (newline-separated paths) stands in for the user's choice, else the
/// import is cancelled.
internal struct _FileImporterModifier: ViewModifier {
  var isPresented: Binding<Bool>
  var multiple: Bool
  var completion: ([URL]) -> Void
  typealias Body = Never
  func body(content: Content) -> Never { fatalError("no body") }
  static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let m = modifier.value
    if m.isPresented.wrappedValue {
      DispatchQueue.main.async {
        m.isPresented.wrappedValue = false
        let picked = (ProcessInfo.processInfo.environment["BITTEN_PICK"] ?? "").split(separator: "\n")
          .map { URL(fileURLWithPath: String($0)) }
        if !picked.isEmpty { m.completion(m.multiple ? picked : [picked[0]]) }
      }
    }
    return body(_Graph(), inputs)
  }
}

internal struct _InspectorView<Content: View, Inspector: View>: View {
  let content: Content, inspector: Inspector, isPresented: Bool
  typealias Body = Never
  var body: Never { return fatalError("no body") }
  nonisolated static func _makeView(view: _GraphValue<_InspectorView>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    let main = _makeNode(v.content, inputs: inputs.named("content"))
    guard v.isPresented else { return _ViewOutputs(main) }
    let side = _FrameNode(minW: 220, idealW: 260, maxW: 260, minH: nil, idealH: nil, maxH: .infinity, alignment: .topLeading,
                          environment: inputs.environment, children: [_makeNode(v.inspector, inputs: inputs.named("inspector"))])
    return _ViewOutputs(_StackNode(axis: .horizontal, alignment: .center, spacing: 0, environment: inputs.environment,
                                   children: [main, _DividerNode(environment: inputs.environment), side]))
  }
}

public enum PopoverAttachmentAnchor: Sendable {
  case rect(Anchor<CGRect>.Source)
  case point(UnitPoint)
}
public struct Anchor<Value> {
  public struct Source: Sendable {
    let id: Int
    public static var bounds: Source { return Source(id: 0) }
  }
}
public protocol PresentationSizing {}
public struct FittedPresentationSizing: PresentationSizing { public init() {} }
public struct AutomaticPresentationSizing: PresentationSizing { public init() {} }
public struct FormPresentationSizing: PresentationSizing { public init() {} }
extension PresentationSizing where Self == FittedPresentationSizing { public static var fitted: FittedPresentationSizing { return .init() } }
extension PresentationSizing where Self == AutomaticPresentationSizing {
  public static var automatic: AutomaticPresentationSizing { return .init() }
}
extension PresentationSizing where Self == FormPresentationSizing { public static var form: FormPresentationSizing { return .init() } }
public struct FileDialogBrowserOptions: OptionSet, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let enumeratePackages = FileDialogBrowserOptions(rawValue: 1)
  public static let includeHiddenFiles = FileDialogBrowserOptions(rawValue: 2)
  public static let displayFileExtensions = FileDialogBrowserOptions(rawValue: 4)
}

// MARK: - gestures

public struct GestureMask: OptionSet, Sendable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  public static let none = GestureMask([])
  public static let gesture = GestureMask(rawValue: 1)
  public static let subviews = GestureMask(rawValue: 2)
  public static let all = GestureMask(rawValue: 3)
}

/// What a gesture does with clicks and drags on its view's node.
public struct _GestureHandlers {
  var tap: ((CGPoint) -> Void)?
  var changed: ((CGPoint, CGPoint) -> Void)?
  var ended: ((CGPoint, CGPoint) -> Void)?
  init(tap: ((CGPoint) -> Void)? = nil, changed: ((CGPoint, CGPoint) -> Void)? = nil,
       ended: ((CGPoint, CGPoint) -> Void)? = nil) {
    self.tap = tap
    self.changed = changed
    self.ended = ended
  }
}

public protocol Gesture {
  associatedtype Value
  associatedtype Body: Gesture
  var body: Body { get }
  func _handlers() -> _GestureHandlers
}
extension Gesture {
  public var body: Never { fatalError("primitive gesture") }
  public func _handlers() -> _GestureHandlers { return _GestureHandlers() }
}
extension Never: Gesture {
  public typealias Value = Never
}

public struct TapGesture: Gesture {
  public var count: Int
  var action: (() -> Void)?
  public init(count: Int = 1) {
    self.count = count
    action = nil
  }
  public typealias Value = ()
  public typealias Body = Never
  public func _handlers() -> _GestureHandlers {
    let a = action
    return _GestureHandlers(tap: { _ in a?() })
  }
}

public struct DragGesture: Gesture {
  public struct Value: Equatable, Sendable {
    public var time: Date
    public var location: CGPoint
    public var startLocation: CGPoint
    public var translation: CGSize {
      return CGSize(width: location.x - startLocation.x, height: location.y - startLocation.y)
    }
    public var velocity: CGSize { return CGSize(width: 0, height: 0) }
    public var predictedEndLocation: CGPoint { return location }
    public var predictedEndTranslation: CGSize { return translation }
    public static func == (a: Value, b: Value) -> Bool {
      return a.location.x == b.location.x && a.location.y == b.location.y && a.startLocation.x == b.startLocation.x &&
        a.startLocation.y == b.startLocation.y
    }
  }
  public var minimumDistance: CGFloat
  public init(minimumDistance: CGFloat = 10) { self.minimumDistance = minimumDistance }
  public init<C: CoordinateSpaceProtocol>(minimumDistance: CGFloat = 10, coordinateSpace: C) {
    self.minimumDistance = minimumDistance
  }
  public typealias Body = Never
}

public struct _ChangedGesture<Content: Gesture>: Gesture where Content.Value: Equatable {
  let content: Content
  let action: (Content.Value) -> Void
  public typealias Value = Content.Value
  public typealias Body = Never
  public func _handlers() -> _GestureHandlers {
    var h = content._handlers()
    if Content.self == DragGesture.self {
      let a = action
      h.changed = { start, p in a(DragGesture.Value(time: Date(), location: p, startLocation: start) as! Content.Value) }
    }
    return h
  }
}
public struct _EndedGesture<Content: Gesture>: Gesture {
  let content: Content
  let action: (Content.Value) -> Void
  public typealias Value = Content.Value
  public typealias Body = Never
  public func _handlers() -> _GestureHandlers {
    var h = content._handlers()
    let a = action
    if Content.self == DragGesture.self {
      h.ended = { start, p in a(DragGesture.Value(time: Date(), location: p, startLocation: start) as! Content.Value) }
    } else if Content.Value.self == Void.self {
      let prior = h.tap
      h.tap = { p in
        prior?(p)
        a(() as! Content.Value)
      }
    }
    return h
  }
}
public struct _MapGesture<Content: Gesture, Value>: Gesture {
  let content: Content
  let transform: (Content.Value) -> Value
  public typealias Body = Never
  public func _handlers() -> _GestureHandlers { return content._handlers() }
}
public struct AnyGesture<Value>: Gesture {
  let handlers: () -> _GestureHandlers
  public init<T: Gesture>(_ gesture: T) where Value == T.Value { handlers = { gesture._handlers() } }
  public typealias Body = Never
  public func _handlers() -> _GestureHandlers { return handlers() }
}
extension Gesture {
  public func onEnded(_ action: @escaping (Value) -> Void) -> _EndedGesture<Self> {
    return _EndedGesture(content: self, action: action)
  }
  public func map<T>(_ body: @escaping (Value) -> T) -> _MapGesture<Self, T> {
    return _MapGesture(content: self, transform: body)
  }
}
extension Gesture where Value: Equatable {
  public func onChanged(_ action: @escaping (Value) -> Void) -> _ChangedGesture<Self> {
    return _ChangedGesture(content: self, action: action)
  }
}

internal struct _GestureModifier<G: Gesture>: ViewModifier {
  var gesture: G
  typealias Body = Never
  func body(content: Content) -> Never { fatalError("no body") }
  static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let h = modifier.value.gesture._handlers()
    let node = _ControlNode(environment: inputs.environment, children: [body(_Graph(), inputs).node])
    if let t = h.tap { node.onTap = t }
    if h.changed != nil || h.ended != nil {
      node.onDrag = { start, p, ended in
        if ended { h.ended?(start, p) } else { h.changed?(start, p) }
      }
    }
    return _ViewOutputs(node)
  }
}

extension View {
  public func gesture<G: Gesture>(_ gesture: G, including mask: GestureMask = .all) -> some View {
    return modifier(_GestureModifier(gesture: gesture))
  }
  public func simultaneousGesture<G: Gesture>(_ gesture: G, including mask: GestureMask = .all) -> some View {
    return modifier(_GestureModifier(gesture: gesture))
  }
  public func highPriorityGesture<G: Gesture>(_ gesture: G, including mask: GestureMask = .all) -> some View {
    return modifier(_GestureModifier(gesture: gesture))
  }
  public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View {
    var g = TapGesture(count: count)
    g.action = action
    return modifier(_GestureModifier(gesture: g))
  }
  public func onTapGesture<C: CoordinateSpaceProtocol>(count: Int = 1, coordinateSpace: C,
                                                       perform action: @escaping (CGPoint) -> Void) -> some View {
    return modifier(_PointTapModifier(action: action))
  }
  public func onLongPressGesture(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10,
                                 perform action: @escaping () -> Void,
                                 onPressingChanged: ((Bool) -> Void)? = nil) -> some View {
    return onTapGesture(perform: action)
  }
}
internal struct _PointTapModifier: ViewModifier {
  var action: (CGPoint) -> Void
  typealias Body = Never
  func body(content: Content) -> Never { fatalError("no body") }
  static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let a = modifier.value.action
    let node = _ControlNode(environment: inputs.environment, children: [body(_Graph(), inputs).node])
    node.onTap = { [unowned node] p in a(CGPoint(x: p.x - node.frame._minX, y: p.y - node.frame._minY)) }
    return _ViewOutputs(node)
  }
}

// MARK: - keys and commands

public struct KeyPress: Sendable {
  public enum Result: Sendable { case handled, ignored }
  public enum Phases: Sendable { case down, `repeat`, up, all }
  public let key: KeyEquivalent
  public let characters: String
  public let modifiers: EventModifiers
}
public enum MoveCommandDirection: Hashable, Sendable { case up, down, left, right }

/// Keys the hosting view's focused tree did not use.
internal struct _KeyHandlerModifier: ViewModifier {
  var handle: (String, UInt16) -> Bool
  typealias Body = Never
  func body(content: Content) -> Never { fatalError("no body") }
  static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    return _ViewOutputs(_KeyNode(handle: modifier.value.handle, content: body(_Graph(), inputs).node,
                                 environment: inputs.environment))
  }
}
internal final class _KeyNode: _ViewNode {
  let handle: (String, UInt16) -> Bool
  init(handle: @escaping (String, UInt16) -> Bool, content: _ViewNode, environment: EnvironmentValues) {
    self.handle = handle
    super.init(environment: environment, children: [content])
  }
  override func key(_ characters: String, keyCode: UInt16) -> Bool {
    if super.key(characters, keyCode: keyCode) { return true }
    return handle(characters, keyCode)
  }
}

extension View {
  public func onKeyPress(_ key: KeyEquivalent, action: @escaping () -> KeyPress.Result) -> some View {
    let want = key.character
    return modifier(_KeyHandlerModifier { chars, code in
      let c: Character? = code == 36 ? "\r" : code == 53 ? "\u{1B}" : chars.first
      return c == want && action() == .handled
    })
  }
  public func onExitCommand(perform action: (() -> Void)?) -> some View {
    return modifier(_KeyHandlerModifier { _, code in
      guard code == 53, let a = action else { return false }
      a()
      return true
    })
  }
  public func onMoveCommand(perform action: ((MoveCommandDirection) -> Void)?) -> some View {
    return modifier(_KeyHandlerModifier { _, code in
      let dir: MoveCommandDirection? = code == 126 ? .up : code == 125 ? .down : code == 123 ? .left : code == 124 ? .right : nil
      guard let d = dir, let a = action else { return false }
      a(d)
      return true
    })
  }
  public func modifierKeyAlternate<V: View>(_ modifiers: EventModifiers, @ViewBuilder _ alternate: () -> V) -> some View {
    return self
  }
  public func help(_ textKey: LocalizedStringKey) -> some View { return self }
  public func help<S: StringProtocol>(_ text: S) -> some View { return self }
  public func help(_ text: Text) -> some View { return self }
}

// MARK: - hover and pointer

public enum HoverPhase: Equatable, Sendable {
  case active(CGPoint)
  case ended
}
public struct PointerStyle: Sendable {
  let id: Int
  public static let `default` = PointerStyle(id: 0)
  public static let link = PointerStyle(id: 1)
  public static let horizontalText = PointerStyle(id: 2)
  public static let grabIdle = PointerStyle(id: 3)
  public static let grabActive = PointerStyle(id: 4)
  public static func frameResize(position: FrameResizePosition, directions: FrameResizeDirection.Set = .all) -> PointerStyle {
    return PointerStyle(id: 5)
  }
}
public enum FrameResizePosition: Int8, Sendable { case top, leading, bottom, trailing, topLeading, topTrailing, bottomLeading, bottomTrailing }
public enum FrameResizeDirection: Int8, Sendable {
  case inward, outward
  public struct Set: OptionSet, Sendable {
    public let rawValue: Int8
    public init(rawValue: Int8) { self.rawValue = rawValue }
    public static let inward = Set(rawValue: 1)
    public static let outward = Set(rawValue: 2)
    public static let all: Set = [.inward, .outward]
  }
}
extension View {
  public func onHover(perform action: @escaping (Bool) -> Void) -> some View { return self }
  public func onContinuousHover<C: CoordinateSpaceProtocol>(coordinateSpace: C,
                                                            perform action: @escaping (HoverPhase) -> Void) -> some View {
    return self
  }
  public func onContinuousHover(coordinateSpace: CoordinateSpace = .local, perform action: @escaping (HoverPhase) -> Void) -> some View {
    return self
  }
  public func pointerStyle(_ style: PointerStyle?) -> some View { return self }
}
public enum CoordinateSpace: Hashable, Sendable {
  case global, local
  case named(AnyHashable)
}

// MARK: - scrolling hints

public struct ScrollIndicatorVisibility: Equatable, Sendable {
  let id: Int
  public static let automatic = ScrollIndicatorVisibility(id: 0)
  public static let visible = ScrollIndicatorVisibility(id: 1)
  public static let hidden = ScrollIndicatorVisibility(id: 2)
  public static let never = ScrollIndicatorVisibility(id: 3)
}
public struct ScrollBounceBehavior: Sendable {
  let id: Int
  public static let automatic = ScrollBounceBehavior(id: 0)
  public static let always = ScrollBounceBehavior(id: 1)
  public static let basedOnSize = ScrollBounceBehavior(id: 2)
}
public struct ScrollAnchorRole: Hashable, Sendable {
  let id: Int
  public static let initialOffset = ScrollAnchorRole(id: 0)
  public static let sizeChanges = ScrollAnchorRole(id: 1)
  public static let alignment = ScrollAnchorRole(id: 2)
}
public struct ContentMarginPlacement: Sendable {
  let id: Int
  public static let automatic = ContentMarginPlacement(id: 0)
  public static let scrollContent = ContentMarginPlacement(id: 1)
  public static let scrollIndicators = ContentMarginPlacement(id: 2)
}
public struct ScrollPosition: Equatable, Sendable {
  public var edge: Edge?
  public var point: CGPoint?
  public var isPositionedByUser: Bool { return false }
  public init(edge: Edge? = nil) { self.edge = edge }
  public init(idType: Any.Type = Never.self) {}
  public mutating func scrollTo(edge: Edge) { self.edge = edge }
  public mutating func scrollTo(point: CGPoint) { self.point = point }
  public static func == (a: ScrollPosition, b: ScrollPosition) -> Bool { return a.edge == b.edge }
}
public struct ScrollGeometry: Equatable, Sendable {
  public var contentOffset: CGPoint
  public var contentSize: CGSize
  public var contentInsets: EdgeInsets
  public var containerSize: CGSize
  public var visibleRect: CGRect { return CGRect(origin: contentOffset, size: containerSize) }
  public var bounds: CGRect { return visibleRect }
  public static func == (a: ScrollGeometry, b: ScrollGeometry) -> Bool {
    return a.contentOffset.x == b.contentOffset.x && a.contentOffset.y == b.contentOffset.y &&
      a.contentSize.width == b.contentSize.width && a.contentSize.height == b.contentSize.height
  }
}
public enum ScrollPhase: Equatable, Sendable {
  case idle, tracking, interacting, decelerating, animating
  public var isScrolling: Bool { return self != .idle }
}
extension View {
  public func scrollIndicators(_ visibility: ScrollIndicatorVisibility, axes: Axis.Set = [.vertical, .horizontal]) -> some View {
    return self
  }
  public func scrollBounceBehavior(_ behavior: ScrollBounceBehavior, axes: Axis.Set = [.vertical]) -> some View { return self }
  public func scrollClipDisabled(_ disabled: Bool = true) -> some View { return self }
  public func scrollContentBackground(_ visibility: Visibility) -> some View { return self }
  public func scrollTargetLayout(isEnabled: Bool = true) -> some View { return self }
  public func scrollPosition(_ position: Binding<ScrollPosition>, anchor: UnitPoint? = nil) -> some View { return self }
  public func scrollPosition<ID: Hashable>(id: Binding<ID?>, anchor: UnitPoint? = nil) -> some View { return self }
  public func defaultScrollAnchor(_ anchor: UnitPoint?) -> some View { return self }
  public func defaultScrollAnchor(_ anchor: UnitPoint?, for role: ScrollAnchorRole) -> some View { return self }
  public func contentMargins(_ edges: Edge.Set = .all, _ length: CGFloat?, for placement: ContentMarginPlacement = .automatic) -> some View {
    return padding(edges, length)
  }
  public func onScrollGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (ScrollGeometry) -> T,
                                                   action: @escaping (T, T) -> Void) -> some View {
    return self
  }
  public func onScrollPhaseChange(_ action: @escaping (ScrollPhase, ScrollPhase) -> Void) -> some View { return self }
  public func safeAreaInset<V: View>(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                                     @ViewBuilder content: () -> V) -> some View {
    let inset = content()
    return _SafeAreaInsetView(content: self, inset: inset, top: edge == .top, spacing: spacing ?? 0)
  }
  public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> some View { return self }
}
internal struct _SafeAreaInsetView<Content: View, Inset: View>: View {
  let content: Content, inset: Inset, top: Bool, spacing: CGFloat
  typealias Body = Never
  var body: Never { return fatalError("no body") }
  nonisolated static func _makeView(view: _GraphValue<_SafeAreaInsetView>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    let main = _makeNode(v.content, inputs: inputs.named("content"))
    let bar = _makeNode(v.inset, inputs: inputs.named("inset"))
    return _ViewOutputs(_StackNode(axis: .vertical, alignment: .center, spacing: v.spacing, environment: inputs.environment,
                                   children: v.top ? [bar, main] : [main, bar]))
  }
}
@frozen
public struct SafeAreaRegions: OptionSet, Sendable {
  public let rawValue: UInt
  @inlinable public init(rawValue: UInt) { self.rawValue = rawValue }
  public static let container = SafeAreaRegions(rawValue: 1)
  public static let keyboard = SafeAreaRegions(rawValue: 2)
  public static let all = SafeAreaRegions(rawValue: ~0)
}
@frozen
public struct _SafeAreaRegionsIgnoringLayout: _NodeModifier {
  public var regions: SafeAreaRegions
  public var edges: Edge.Set
  @inlinable public init(regions: SafeAreaRegions, edges: Edge.Set) {
    self.regions = regions
    self.edges = edges
  }
  func makeNode(content: _ViewNode, environment: EnvironmentValues) -> _ViewNode { return content }
}

// MARK: - lists, symbols, selection

public protocol ListStyle {}
public struct SidebarListStyle: ListStyle { public init() {} }
public struct PlainListStyle: ListStyle { public init() {} }
public struct InsetListStyle: ListStyle { public init() {} }
public struct BorderedListStyle: ListStyle { public init() {} }
public struct DefaultListStyle: ListStyle { public init() {} }
extension ListStyle where Self == SidebarListStyle { public static var sidebar: SidebarListStyle { return .init() } }
extension ListStyle where Self == PlainListStyle { public static var plain: PlainListStyle { return .init() } }
extension ListStyle where Self == InsetListStyle { public static var inset: InsetListStyle { return .init() } }
extension ListStyle where Self == BorderedListStyle { public static var bordered: BorderedListStyle { return .init() } }
extension ListStyle where Self == DefaultListStyle { public static var automatic: DefaultListStyle { return .init() } }

public struct SymbolVariants: Hashable, Sendable {
  let id: Int
  public static let none = SymbolVariants(id: 0)
  public static let circle = SymbolVariants(id: 1)
  public static let square = SymbolVariants(id: 2)
  public static let fill = SymbolVariants(id: 3)
  public static let slash = SymbolVariants(id: 4)
  public static let rectangle = SymbolVariants(id: 5)
}

public protocol TextSelectability {}
public struct EnabledTextSelectability: TextSelectability { public init() {} }
public struct DisabledTextSelectability: TextSelectability { public init() {} }
extension TextSelectability where Self == EnabledTextSelectability { public static var enabled: EnabledTextSelectability { return .init() } }
extension TextSelectability where Self == DisabledTextSelectability { public static var disabled: DisabledTextSelectability { return .init() } }

extension View {
  public func listStyle<S: ListStyle>(_ style: S) -> some View { return self }
  public func listRowSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View { return self }
  public func symbolVariant(_ variant: SymbolVariants) -> some View { return self }
  public func textSelection<S: TextSelectability>(_ selectability: S) -> some View { return self }
  public func monospacedDigit() -> some View { return self }
  public func toolbarBackgroundVisibility(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View { return self }
  public func toolbar(removing defaultItemKind: ToolbarDefaultItemKind?) -> some View { return self }
  public func toolbar(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View { return self }
  public func contextMenu<M: View>(@ViewBuilder menuItems: () -> M) -> some View { return self }
  public func colorEffect(_ shader: Shader, isEnabled: Bool = true) -> some View { return self }
  public func visualEffect(_ effect: @escaping @Sendable (EmptyVisualEffect, GeometryProxy) -> some VisualEffect) -> some View {
    return self
  }
  public func keyframeAnimator<Value, K: Keyframes, C: View>(initialValue: Value, repeating: Bool = true,
                                                           @ViewBuilder content: @escaping @Sendable (PlaceholderContentView<Self>, Value) -> C,
                                                           @KeyframesBuilder<Value> keyframes: @escaping (Value) -> K) -> some View
    where Value == K.Value {
    return content(PlaceholderContentView(content: self), initialValue)
  }
}
extension VerticalEdge {
  public struct Set: OptionSet, Sendable {
    public let rawValue: Int8
    public init(rawValue: Int8) { self.rawValue = rawValue }
    public static let top = Set(rawValue: 1)
    public static let bottom = Set(rawValue: 2)
    public static let all: Set = [.top, .bottom]
  }
}

public protocol VisualEffect: Sendable {}
public struct EmptyVisualEffect: VisualEffect { public init() {} }
public struct Shader: Equatable, Sendable {
  public struct Argument: Equatable, Sendable {
    public static func float(_ x: Double) -> Argument { return Argument() }
    public static func color(_ c: Color) -> Argument { return Argument() }
  }
  let name: String
  public static func == (a: Shader, b: Shader) -> Bool { return a.name == b.name }
}
@dynamicMemberLookup
public struct ShaderFunction: Equatable, Sendable {
  public let name: String
  public subscript(dynamicMember name: String) -> (Shader.Argument...) -> Shader { return { _ in Shader(name: name) } }
  public func callAsFunction(_ arguments: Shader.Argument...) -> Shader { return Shader(name: name) }
}
@dynamicMemberLookup
public struct ShaderLibrary: Equatable, Sendable {
  let id: Int
  public static let `default` = ShaderLibrary(id: 0)
  public static subscript(dynamicMember name: String) -> ShaderFunction { return ShaderFunction(name: name) }
  public subscript(dynamicMember name: String) -> ShaderFunction { return ShaderFunction(name: name) }
}

public protocol Keyframes {
  associatedtype Value
}
@resultBuilder
public struct KeyframesBuilder<Value> {
  public static func buildBlock<K: Keyframes>(_ k: K) -> K { return k }
  public static func buildExpression<K: Keyframes>(_ k: K) -> K { return k }
}
public struct KeyframeTrack<Root, Value: Animatable, Content>: Keyframes {
  public init(_ keyPath: WritableKeyPath<Root, Value>, @KeyframeTrackContentBuilder<Value> content: () -> Content) {}
}
@resultBuilder
public struct KeyframeTrackContentBuilder<Value> {
  public static func buildBlock(_ c: Any...) -> Int { return 0 }
}
public struct LinearKeyframe<Value: Animatable> {
  public init(_ to: Value, duration: TimeInterval, timingCurve: UnitCurve = .linear) {}
}
public struct SpringKeyframe<Value: Animatable> {
  public init(_ to: Value, duration: TimeInterval? = nil, spring: Spring = Spring(), startVelocity: Value? = nil) {}
}
public struct UnitCurve: Hashable, Sendable {
  let id: Int
  public static let linear = UnitCurve(id: 0)
  public static let easeIn = UnitCurve(id: 1)
  public static let easeOut = UnitCurve(id: 2)
  public static let easeInOut = UnitCurve(id: 3)
  public static func bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint) -> UnitCurve { return UnitCurve(id: 4) }
}
public struct Spring: Hashable, Sendable {
  public init(duration: TimeInterval = 0.5, bounce: Double = 0) {}
  public init(response: Double, dampingRatio: Double) {}
}

// MARK: - toolbars

internal struct _ToolbarModifier<Content: ToolbarContent>: ViewModifier {
  var content: Content
  typealias Body = Never
  func body(content: Self.Content) -> Never { fatalError("no body") }
  static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    let main = body(_Graph(), inputs).node
    var list = _ToolbarItemList()
    let tc = modifier.value.content
    Content._makeContent(content: _GraphValue({ tc }), inputs: inputs.base, resolved: &list)
    guard !list.items.isEmpty else { return _ViewOutputs(main) }
    let items = list.items.enumerated().map { i, e in _makeNode(e.make(), inputs: inputs.named("toolbar\(i)")) }
    var bar: [_ViewNode] = [_SpacerNode(minLength: 0, environment: inputs.environment)]
    bar += items
    let row = _PaddingNode(insets: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8), environment: inputs.environment,
                           children: [_StackNode(axis: .horizontal, alignment: .center, spacing: 8,
                                                 environment: inputs.environment, children: bar)])
    return _ViewOutputs(_StackNode(axis: .vertical, alignment: .center, spacing: 0, environment: inputs.environment,
                                   children: [row, _DividerNode(environment: inputs.environment), main]))
  }
}
extension View {
  public func toolbar<C: ToolbarContent>(@ToolbarContentBuilder content: () -> C) -> some View {
    return modifier(_ToolbarModifier(content: content()))
  }
  public func toolbar<C: View>(@ViewBuilder content: () -> C) -> some View {
    let c = content()
    return modifier(_ToolbarModifier(content: ToolbarItem(placement: .automatic) { c }))
  }
}

// MARK: - accessibility (kept, not acted on)

public struct AccessibilityTraits: SetAlgebra, Sendable {
  var bits: UInt64
  public init() { bits = 0 }
  init(bits: UInt64) { self.bits = bits }
  public static let isButton = AccessibilityTraits(bits: 1)
  public static let isHeader = AccessibilityTraits(bits: 2)
  public static let isSelected = AccessibilityTraits(bits: 4)
  public static let isLink = AccessibilityTraits(bits: 8)
  public static let isSearchField = AccessibilityTraits(bits: 16)
  public static let isImage = AccessibilityTraits(bits: 32)
  public static let playsSound = AccessibilityTraits(bits: 64)
  public static let isKeyboardKey = AccessibilityTraits(bits: 128)
  public static let isStaticText = AccessibilityTraits(bits: 256)
  public static let isSummaryElement = AccessibilityTraits(bits: 512)
  public static let updatesFrequently = AccessibilityTraits(bits: 1024)
  public static let startsMediaSession = AccessibilityTraits(bits: 2048)
  public static let allowsDirectInteraction = AccessibilityTraits(bits: 4096)
  public static let causesPageTurn = AccessibilityTraits(bits: 8192)
  public static let isModal = AccessibilityTraits(bits: 16384)
  public static let isToggle = AccessibilityTraits(bits: 32768)
  public func contains(_ m: AccessibilityTraits) -> Bool { return bits & m.bits == m.bits }
  public func union(_ o: AccessibilityTraits) -> AccessibilityTraits { return AccessibilityTraits(bits: bits | o.bits) }
  public func intersection(_ o: AccessibilityTraits) -> AccessibilityTraits { return AccessibilityTraits(bits: bits & o.bits) }
  public func symmetricDifference(_ o: AccessibilityTraits) -> AccessibilityTraits { return AccessibilityTraits(bits: bits ^ o.bits) }
  public mutating func insert(_ m: AccessibilityTraits) -> (inserted: Bool, memberAfterInsert: AccessibilityTraits) {
    let had = contains(m)
    bits |= m.bits
    return (!had, m)
  }
  public mutating func remove(_ m: AccessibilityTraits) -> AccessibilityTraits? {
    let had = contains(m)
    bits &= ~m.bits
    return had ? m : nil
  }
  public mutating func update(with m: AccessibilityTraits) -> AccessibilityTraits? {
    let had = contains(m)
    bits |= m.bits
    return had ? m : nil
  }
  public mutating func formUnion(_ o: AccessibilityTraits) { bits |= o.bits }
  public mutating func formIntersection(_ o: AccessibilityTraits) { bits &= o.bits }
  public mutating func formSymmetricDifference(_ o: AccessibilityTraits) { bits ^= o.bits }
  public static func == (a: AccessibilityTraits, b: AccessibilityTraits) -> Bool { return a.bits == b.bits }
}
public struct AccessibilityChildBehavior: Hashable, Sendable {
  let id: Int
  public static let ignore = AccessibilityChildBehavior(id: 0)
  public static let contain = AccessibilityChildBehavior(id: 1)
  public static let combine = AccessibilityChildBehavior(id: 2)
}
public enum AccessibilityAdjustmentDirection: Hashable, Sendable { case increment, decrement }
public struct AccessibilityActionKind: Equatable, Sendable {
  let id: Int
  public static let `default` = AccessibilityActionKind(id: 0)
  public static let escape = AccessibilityActionKind(id: 1)
  public static let magicTap = AccessibilityActionKind(id: 2)
  public init(named name: Text) { id = 3 }
  init(id: Int) { self.id = id }
}

/// Accessibility attributes are accepted and dropped: nothing reads them.
public struct AccessibilityAttachmentModifier: ViewModifier {
  public typealias Body = Never
  public func body(content: Content) -> Never { fatalError("no body") }
  public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                               body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
    return body(_Graph(), inputs)
  }
}

extension View {
  public func accessibilityLabel(_ label: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
    return modifier(AccessibilityAttachmentModifier())
  }
  public func accessibilityLabel(_ label: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
    return modifier(AccessibilityAttachmentModifier())
  }
  public func accessibilityLabel<S: StringProtocol>(_ label: S) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
    return modifier(AccessibilityAttachmentModifier())
  }
  public func accessibilityHint(_ hint: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
    return modifier(AccessibilityAttachmentModifier())
  }
  public func accessibilityHint(_ hint: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
    return modifier(AccessibilityAttachmentModifier())
  }
  public func accessibilityValue(_ value: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
    return modifier(AccessibilityAttachmentModifier())
  }
  public func accessibilityValue(_ value: LocalizedStringKey) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
    return modifier(AccessibilityAttachmentModifier())
  }
  public func accessibilityIdentifier(_ identifier: String) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
    return modifier(AccessibilityAttachmentModifier())
  }
  public func accessibilityHidden(_ hidden: Bool) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
    return modifier(AccessibilityAttachmentModifier())
  }
  public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
    return modifier(AccessibilityAttachmentModifier())
  }
  public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
    return modifier(AccessibilityAttachmentModifier())
  }
  public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View { return self }
  public func accessibilityActions<C: View>(@ViewBuilder _ content: () -> C) -> some View { return self }
  public func accessibilityAction(_ actionKind: AccessibilityActionKind = .default, _ handler: @escaping () -> Void)
    -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
    return modifier(AccessibilityAttachmentModifier())
  }
}
extension ModifiedContent where Modifier == AccessibilityAttachmentModifier {
  public func accessibilityLabel(_ label: Text) -> ModifiedContent<Content, Modifier> { return self }
  public func accessibilityLabel(_ label: LocalizedStringKey) -> ModifiedContent<Content, Modifier> { return self }
  public func accessibilityHint(_ hint: Text) -> ModifiedContent<Content, Modifier> { return self }
  public func accessibilityHint(_ hint: LocalizedStringKey) -> ModifiedContent<Content, Modifier> { return self }
  public func accessibilityValue(_ value: Text) -> ModifiedContent<Content, Modifier> { return self }
  public func accessibilityValue(_ value: LocalizedStringKey) -> ModifiedContent<Content, Modifier> { return self }
  public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> ModifiedContent<Content, Modifier> { return self }
  public func accessibilityHidden(_ hidden: Bool) -> ModifiedContent<Content, Modifier> { return self }
  public func accessibilityIdentifier(_ identifier: String) -> ModifiedContent<Content, Modifier> { return self }
  public func accessibilityAdjustableAction(_ handler: @escaping (AccessibilityAdjustmentDirection) -> Void)
    -> ModifiedContent<Content, Modifier> { return self }
  public func accessibilityAction(_ actionKind: AccessibilityActionKind = .default, _ handler: @escaping () -> Void)
    -> ModifiedContent<Content, Modifier> { return self }
}
