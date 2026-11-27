// The application host: runs the App, opens its windows, keeps the graph
// up to date, and hosts views in AppKit (NSHostingView/Controller).

@MainActor
final class _AppHost {
  static let shared = _AppHost()

  var delegate: NSObject?
  var windows: [NSWindow] = []
  let undoManager = UndoManager()
  var registered: [String: (title: String, make: () -> NSView)] = [:]

  var appName: String {
    return ProcessInfo.processInfo.processName
  }

  /// The delegate type an adaptor names; the delegate itself is made when
  /// the app launches (or first asked for), not while the App value is
  /// being initialized.
  var delegateType: (NSObject & NSApplicationDelegate).Type?
  func installDelegate(_ type: (NSObject & NSApplicationDelegate).Type) {
    if delegateType == nil { delegateType = type }
  }
  func makeDelegate() -> NSObject? {
    if delegate == nil, let type = delegateType {
      let d = type.init()
      delegate = d
      NSApplication.shared.delegate = d
    }
    return delegate
  }

  /// State in the App value (`@State`, `@StateObject`, ...) lives here,
  /// for as long as the app runs.
  let appContext = _RenderContext()
  var app: Any?

  func start<A: App>(_ app: A) {
    let nsapp = NSApplication.shared
    _ = makeDelegate()
    var a = app
    let inputs = _ViewInputs(_GraphInputs(environment: EnvironmentValues(), context: appContext, path: "app"))
    _installDynamicProperties(&a, inputs: inputs)
    self.app = a
    visit(a.body)
    _installMainMenu(commands)
    nsapp.run()
  }

  /// Walks a scene tree down to its primitive scenes.
  func visit(_ scene: any Scene) {
    if let primitive = scene as? any _PrimitiveScene {
      primitive._makeWindows(self)
      return
    }
    _visitBody(scene)
  }
  private func _visitBody<S: Scene>(_ scene: S) {
    if S.Body.self == Never.self { return }
    visit(scene.body)
  }

  /// The settings scene modifiers have applied to the scenes being visited.
  var config = _SceneConfig()
  /// Commands from every scene, applied to the main menu once all are in.
  var commands = _ResolvedCommands()
  var launchSuppressed = false

  /// Visits `scene` with the configuration changed by `modify`.
  func withConfig(_ modify: (inout _SceneConfig) -> Void, _ body: () -> Void) {
    let saved = config
    modify(&config)
    body()
    config = saved
  }

  func makeWindow(title: String, view: NSView) -> NSWindow {
    let screen = NSScreen.main?.visibleFrame ?? NSMakeRect(0, 0, 1440, 875)
    var size = config.defaultSize ?? CGSize(width: 900, height: 600)
    let fitting = (view as? _HostingViewBase)?.fittingContentSize
    if config.defaultSize == nil, let f = fitting, f.width > 0, f.height > 0 {
      size = CGSize(width: max(f.width, 300), height: max(f.height, 200))
    }
    if config.resizability == .contentSize, let f = fitting, f.width > 0, f.height > 0 { size = f }
    if getenv("BITTEN_WINDOW_DEBUG") != nil {
      _dbg("bitten: swiftui window '\(title)' default \(String(describing: config.defaultSize)) resizability \(config.resizability) fitting \(String(describing: fitting)) -> \(size)")
    }
    var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
    if config.resizability != .contentSize { style.insert(.resizable) }
    if config.hiddenTitleBar { style.insert(.fullSizeContentView) }
    let w = NSWindow(contentRect: NSMakeRect(0, 0, min(size.width, screen.size.width), min(size.height, screen.size.height)),
                     styleMask: style, backing: .buffered, defer: false)
    w.title = title
    if config.hiddenTitleBar {
      w.titleVisibility = .hidden
      w.titlebarAppearsTransparent = true
    }
    w.contentView = view
    if let f = fitting, config.resizability == .contentMinSize { w.contentMinSize = f }
    w.center()
    return w
  }

  func openWindow<V: View>(title: String, id: String?, content: @escaping () -> V) {
    if let id = id { registerWindow(id: id, title: title, content: content) }
    if config.launchBehavior == .suppressed { return }
    show(makeWindow(title: title, view: NSHostingView(rootView: content())))
  }

  func show(_ w: NSWindow) {
    w.makeKeyAndOrderFront(nil)
    windows.append(w)
    // A window that closes is let go, as SwiftUI releases the windows it
    // closes (Settings opened again gets a new one).
    let closing = ObjectIdentifier(w)
    var token: NSObjectProtocol?
    token = NotificationCenter.default.addObserver(forName: NSNotification.Name("NSWindowWillCloseNotification"), object: w, queue: nil) { _ in
      MainActor.assumeIsolated {
        _AppHost.shared.windows.removeAll { ObjectIdentifier($0) == closing }
        if let t = token { NotificationCenter.default.removeObserver(t) }
        token = nil
      }
    }
  }

  func registerWindow<V: View>(id: String, title: String, content: @escaping () -> V) {
    let saved = config
    registered[id] = (title, { NSHostingView(rootView: content()) })
    configs[id] = saved
  }
  var configs: [String: _SceneConfig] = [:]

  /// `openWindow(id:)`: brings the window forward, or makes it.
  func open(id: String) {
    if let w = windows.first(where: { $0.identifier?.rawValue == id && $0.isVisible }) {
      w.makeKeyAndOrderFront(nil)
      return
    }
    guard let entry = registered[id] else { return }
    let saved = config
    config = configs[id] ?? _SceneConfig()
    let w = makeWindow(title: entry.title, view: entry.make())
    config = saved
    w.identifier = NSUserInterfaceItemIdentifier(id)
    show(w)
  }
}

/// Re-renders after state changes, once per main-queue turn.
@MainActor
enum _GraphHost {
  static var scheduled = false
  static var hosts: [_WeakHost] = []
  nonisolated static func invalidate() {
    Task { @MainActor in
      if scheduled {
        if _debugTree { _dbg("bitten: invalidate: already scheduled") }
        return
      }
      scheduled = true
      if _debugTree { _dbg("bitten: invalidate: scheduled") }
      await Task.yield()
      if _debugTree { _dbg("bitten: invalidate: running") }
      scheduled = false
      hosts.removeAll { $0.view == nil }
      for h in hosts { h.view?._bn_invalidate() }
    }
  }
}
final class _WeakHost {
  weak var view: _HostingViewBase?
  init(_ v: _HostingViewBase) { view = v }
}

/// `area` grown to take in `r` (itself grown by `margin`).
func _bn_addArea(_ area: inout CGRect?, _ r: CGRect, margin: CGFloat) {
  let grown = CGRect(_x: r._minX - margin, y: r._minY - margin, width: r._width + 2 * margin, height: r._height + 2 * margin)
  guard let a = area else {
    area = grown
    return
  }
  let x0 = min(a._minX, grown._minX), y0 = min(a._minY, grown._minY)
  let x1 = max(a._maxX, grown._maxX), y1 = max(a._maxY, grown._maxY)
  area = CGRect(_x: x0, y: y0, width: x1 - x0, height: y1 - y0)
}

/// Adds to `area` where `node`'s tree draws by itself (AppKit views in it
/// draw themselves), with a margin for what draws just outside a frame.
/// False when that can't be told (transforms and effects move or spread
/// what they draw).
@MainActor
func _bn_drawnArea(_ node: _ViewNode, _ area: inout CGRect?) -> Bool {
  if node is _PlatformViewNode { return true }
  if let t = node as? _TransformNode {
    // What its content draws, moved as it is drawn: about the frame's origin.
    var inner: CGRect? = nil
    for c in t.children where !_bn_drawnArea(c, &inner) { return false }
    guard let a = inner else { return true }
    let m = t.transform(t.frame.size), o = t.frame
    var x0 = CGFloat.infinity, y0 = CGFloat.infinity, x1 = -CGFloat.infinity, y1 = -CGFloat.infinity
    for (px, py) in [(a._minX, a._minY), (a._maxX, a._minY), (a._minX, a._maxY), (a._maxX, a._maxY)] {
      let lx = px - o._minX, ly = py - o._minY
      let x = m.a * lx + m.c * ly + m.tx + o._minX, y = m.b * lx + m.d * ly + m.ty + o._minY
      x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
    }
    _bn_addArea(&area, CGRect(_x: x0, y: y0, width: x1 - x0, height: y1 - y0), margin: 0)
    return true
  }
  if let e = node as? _DrawEffectNode {
    // An effect (opacity, clip, shadow, blur) draws its content, spread
    // at most by a shadow or blur.
    var inner: CGRect? = nil
    for c in e.children where !_bn_drawnArea(c, &inner) { return false }
    if let a = inner { _bn_addArea(&area, a, margin: 32) }
    return true
  }
  let drawsOwnFrame = node.children.isEmpty || node is _ScrollNode || node is _ButtonNode || node is _TextFieldNode ||
    node is _SliderNode || node is _ProgressNode || node is _DividerNode || node is _ImageNode || node is _ToggleMarkNode
  if drawsOwnFrame {
    let f = node.frame
    if f.size.width > 0 && f.size.height > 0 { _bn_addArea(&area, f, margin: 12) }
    if node is _ScrollNode { return true }   // its content is clipped to it
  }
  for c in node.children where !_bn_drawnArea(c, &area) { return false }
  return true
}

/// Whether `event` is `shortcut`'s key with its modifiers.
func _matches(_ shortcut: KeyboardShortcut, _ event: NSEvent) -> Bool {
  var want: NSEvent.ModifierFlags = []
  if shortcut.modifiers.contains(.command) { want.insert(.command) }
  if shortcut.modifiers.contains(.shift) { want.insert(.shift) }
  if shortcut.modifiers.contains(.option) { want.insert(.option) }
  if shortcut.modifiers.contains(.control) { want.insert(.control) }
  let have = event.modifierFlags.intersection([.command, .shift, .option, .control])
  let key = String(shortcut.key.character)
  let typed = event.charactersIgnoringModifiers ?? ""
  if key == "\r" && (typed == "\r" || typed == "\u{3}") { return have == want }   // Return or Enter
  if key.lowercased() != typed.lowercased() { return false }
  // An uppercase key implies shift, as in menus.
  if key != key.lowercased() { want.insert(.shift) }
  return have == want
}

/// The enabled button in `node`'s subtree whose keyboard shortcut is
/// `event`'s key (the frontmost, when more than one has it).
func _shortcutButton(_ node: _ViewNode, _ event: NSEvent) -> _ButtonNode? {
  for c in node.children.reversed() {
    if let b = _shortcutButton(c, event) { return b }
  }
  if let b = node as? _ButtonNode, b.environment.isEnabled, let shortcut = b.environment._keyboardShortcut,
     _matches(shortcut, event) {
    return b
  }
  return nil
}

/// What every NSHostingView does, whatever its root view's type.
@MainActor @preconcurrency
open class _HostingViewBase: NSView {
  let _context = _RenderContext()
  var _root: _ViewNode?
  var _environment = EnvironmentValues()
  var _pressed: _ViewNode?
  var _placedIn = CGSize(width: -1, height: -1)

  override public init(frame: NSRect) {
    super.init(frame: frame)
    _context.invalidate = { _GraphHost.invalidate() }
    _context.hostView = self
    _GraphHost.hosts.append(_WeakHost(self))
  }
  /// What the tree watched goes with the view.
  deinit { _context.cancelObservation() }

  /// A button's `keyboardShortcut` (⌘-keys, Return for `.defaultAction`,
  /// Escape for `.cancelAction`) performs it, as SwiftUI does.
  override open func performKeyEquivalent(with event: NSEvent) -> Bool {
    if let root = _root, let button = _shortcutButton(root, event) {
      button.action()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  func _makeRoot() -> _ViewNode { fatalError("abstract") }

  /// An invalidation that arrived while the tree was being placed: the
  /// tree is dropped once placing is done, not under the nodes running.
  var _invalidatedWhilePlacing = false

  /// The colour scheme the view's appearance gives its content, as
  /// SwiftUI's hosting views do (a view's own .colorScheme still wins).
  var _appearanceScheme: ColorScheme {
    return String(describing: effectiveAppearance.name).contains("Dark") ? .dark : .light
  }
  override open func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    if _environment.colorScheme != _appearanceScheme { _bn_invalidate() }
  }

  func _bn_invalidate() {
    if _placing {
      _invalidatedWhilePlacing = true
      return
    }
    // A rebuild already pending covers this one too.
    if _root == nil && _rebuildRepaint { return }
    let old = _root
    _root = nil
    // In a window, a rebuilt tree repaints where the old tree drew and where
    // the new one does (AppKit views in it repaint themselves as they move);
    // the new one is built when the window lays out before drawing.
    var area: CGRect? = nil
    if let w = window, let o = old, _bn_drawnArea(o, &area) {
      _rebuildRepaint = true
      needsLayout = true
      w._bn_invalidateRect(area.map { convert($0, to: nil) } ?? NSZeroRect)
      return
    }
    if getenv("BITTEN_DISPLAY_DEBUG") != nil {
      _dbg("bitten: swiftui host repaints whole: window \(window != nil) old tree \(old != nil) \(type(of: self))".prefix(200).description)
    }
    needsDisplay = true
  }
  /// Set when a rebuild is to repaint only where the trees draw.
  var _rebuildRepaint = false
  override open func layout() {
    super.layout()
    guard _rebuildRepaint else { return }
    _rebuildRepaint = false
    let r = _layout()
    var area: CGRect? = nil
    if let w = window, _bn_drawnArea(r, &area) {
      if let a = area { w._bn_invalidateRect(convert(a, to: nil)) }
    } else {
      needsDisplay = true
    }
  }

  /// The tree, built (and laid out in the bounds) on demand.
  /// Set while the tree is being placed: AppKit views placed in it can
  /// lay themselves out and ask for this host's tree again, which must not
  /// rebuild or re-place the tree being placed.
  var _placing = false

  func _layout() -> _ViewNode {
    _measureGeneration &+= 1
    if let r = _root, _placing || (_placedIn.width == bounds.size.width && _placedIn.height == bounds.size.height) {
      return r
    }
    let r = _root ?? _makeRoot()
    _root = r
    _placing = true
    defer {
      _placing = false
      if _invalidatedWhilePlacing {
        _invalidatedWhilePlacing = false
        // Rebuild on the next pass; this one returns the tree it placed.
        DispatchQueue.main.async { [weak self] in self?._bn_invalidate() }
      }
    }
    // The root takes the size it wants of the bounds, centred in them.
    let want = r.sizeThatFits(ProposedViewSize(bounds.size))
    let size = CGSize(width: min(want.width, bounds.size.width), height: min(want.height, bounds.size.height))
    let origin = CGPoint(x: ((bounds.size.width - size.width) / 2).rounded(.down),
                         y: ((bounds.size.height - size.height) / 2).rounded(.down))
    // Content built while laying out (geometry readers) is watched as well.
    let ctx = _context
    let generation = ctx.generation
    let (_, token) = _bitten_withObservationTracking({ r.place(in: CGRect(origin: origin, size: size)) },
                                                     onChange: { [weak ctx] in
                                                       if let ctx = ctx, generation == ctx.generation { ctx.invalidate() }
                                                     })
    if let t = token { ctx.trackings.append(t) }
    _placedIn = bounds.size
    if _debugTree { _dbg("bitten: swiftui tree in \(bounds.size)"); r._dumpTree() }
    _orderPlatformViews(r)
    return r
  }

  /// Stacks the representables' AppKit views the way SwiftUI draws them
  /// (a background's below the content, an overlay's above), whatever
  /// order layout added them in.
  func _orderPlatformViews(_ root: _ViewNode) {
    var order: [NSView] = []
    root.collectPlatformViews(&order)
    let current = subviews
    let placed = current.filter { v in order.contains { $0 === v } }
    let wanted = order.filter { v in placed.contains { $0 === v } }
    if placed.count < 2 || zip(placed, wanted).allSatisfy({ $0 === $1 }) { return }
    var next = wanted.makeIterator()
    subviews = current.map { v in placed.contains { $0 === v } ? next.next()! : v }
  }

  override open var isFlipped: Bool { return true }
  @objc func _bn_drawsOwnSubviews() -> Bool { return true }

  /// Hit testing in SwiftUI's z-order: an AppKit view of a representable
  /// gets the click only where nothing SwiftUI draws above it takes it
  /// (a representable used as a background stays behind the buttons).
  override open func hitTest(_ point: NSPoint) -> NSView? {
    if isHidden { return nil }
    let p = convert(point, from: superview)
    guard NSPointInRect(p, bounds) else { return nil }
    let node = _layout().hit(CGPoint(x: p.x, y: p.y))
    if getenv("BITTEN_HIT_DEBUG") != nil { _dbg("bitten: hitTest at \(p) -> \(node.map { "\(type(of: $0))" } ?? "nil")") }
    if let platform = node as? _PlatformViewNode { return platform.view.hitTest(p) }
    if node != nil { return self }
    // Nothing of SwiftUI's here: AppKit views the program added itself.
    return super.hitTest(point)
  }

  override open func draw(_ dirtyRect: NSRect) {
    guard let cg = NSGraphicsContext.current?.cgContext else { return }
    _layout().draw(cg)
  }

  // MARK: hover
  /// The hover regions the pointer is in, by path.
  var _hovered = Set<String>()
  override open func updateTrackingAreas() {
    super.updateTrackingAreas()
    for a in trackingAreas where a.owner === self { removeTrackingArea(a) }
    addTrackingArea(NSTrackingArea(rect: NSMakeRect(0, 0, 0, 0), options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways,
                                                          .inVisibleRect], owner: self, userInfo: nil))
  }
  func _hover(at point: CGPoint?) {
    var now: [(String, _HoverNode)] = []
    if let p = point { _layout().collectHover(p, path: "", into: &now) }
    let paths = Set(now.map { $0.0 })
    // Regions left are known by path only: find them in the current tree.
    let left = _hovered.subtracting(paths)
    if !left.isEmpty {
      var byPath: [String: _HoverNode] = [:]
      _collectAllHover(_layout(), path: "", into: &byPath)
      for path in left { byPath[path]?.hover(nil, entering: false) }
    }
    for (path, node) in now { node.hover(point, entering: !_hovered.contains(path)) }
    _hovered = paths
  }
  private func _collectAllHover(_ node: _ViewNode, path: String, into: inout [String: _HoverNode]) {
    if let h = node as? _HoverNode { into[path] = h }
    for (i, c) in node.children.enumerated() { _collectAllHover(c, path: path + "/\(i)", into: &into) }
  }
  override open func mouseMoved(with event: NSEvent) { _hover(at: convert(event.locationInWindow, from: nil)) }
  override open func mouseEntered(with event: NSEvent) { _hover(at: convert(event.locationInWindow, from: nil)) }
  override open func mouseExited(with event: NSEvent) { _hover(at: nil) }

  var _pressedPath: [Int]?
  private func _path(of node: _ViewNode, in root: _ViewNode) -> [Int]? {
    if node === root { return [] }
    for (i, c) in root.children.enumerated() {
      if let p = _path(of: node, in: c) { return [i] + p }
    }
    return nil
  }
  var _pressPoint = CGPoint(x: 0, y: 0)
  var _dragging = false
  override open func mouseDown(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    _pressPoint = p
    _dragging = false
    let root = _layout()
    _pressed = root.hit(p)
    _pressedPath = _pressed.flatMap { _path(of: $0, in: root) }
    if getenv("BITTEN_EVENT_DEBUG") != nil {
      _dbg("bitten: swiftui press at \(p) on \(_pressed.map { String(describing: type(of: $0)) } ?? "nothing")")
    }
    _pressed?.press(at: p)
  }
  override open func mouseDragged(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    guard let pressed = _pressed else { return }
    if !_dragging && Swift.abs(p.x - _pressPoint.x) + Swift.abs(p.y - _pressPoint.y) < 3 { return }
    if pressed.drag(from: _pressPoint, to: p, ended: false) {
      _dragging = true
      needsDisplay = true
    }
  }
  override open func mouseUp(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    if let pressed = _pressed {
      if _dragging {
        _ = pressed.drag(from: _pressPoint, to: p, ended: true)
      } else {
        // The tree may have been rebuilt since the press: the same control
        // is the node at the same place in the new tree.
        let root = _layout()
        if let hit = root.hit(p), hit === pressed || (_pressedPath != nil && _path(of: hit, in: root) == _pressedPath) {
          hit.press(at: p)
          hit.tap()
        }
      }
    }
    _pressed = nil
    _pressedPath = nil
    _dragging = false
  }
  override open func scrollWheel(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    if _layout().scroll(at: p, dx: event.scrollingDeltaX, dy: event.scrollingDeltaY) {
      // Scrolling moves content without rebuilding it.
      _placedIn = CGSize(width: -1, height: -1)
      needsDisplay = true
    }
  }
  override open var acceptsFirstResponder: Bool { return true }
  override open func keyDown(with event: NSEvent) {
    if _layout().key(event.characters ?? "", keyCode: event.keyCode) {
      needsDisplay = true
      return
    }
    // Not the tree's: on along the responder chain (to the window, which
    // offers it as a key equivalent: Escape to a .cancelAction button).
    super.keyDown(with: event)
  }

  /// The size the content wants when nothing is proposed.
  public var fittingContentSize: NSSize {
    _measureGeneration &+= 1
    return _makeRoot().sizeThatFits(.unspecified)
  }
}

/// An AppKit view that hosts a SwiftUI view tree.
@MainActor @preconcurrency
open class NSHostingView<Content: View>: _HostingViewBase {
  public var rootView: Content {
    didSet { _bn_invalidate() }
  }
  /// Which content sizes become the view's intrinsic size and constraints.
  public var sizingOptions: NSHostingSizingOptions = .standardBounds
  public var safeAreaRegions: SafeAreaRegions = .all
  public required init(rootView: Content) {
    self.rootView = rootView
    super.init(frame: NSMakeRect(0, 0, 100, 100))
  }
  override func _makeRoot() -> _ViewNode {
    _environment.colorScheme = _appearanceScheme
    let inputs = _ViewInputs(_GraphInputs(environment: _environment, context: _context, path: ""))
    _context.beginBuild()
    // Observable reads made while building but outside any view's body
    // (builder closures run by containers, styles) rebuild the tree too.
    let root = _withObservation(inputs) { _makeNode(rootView, inputs: inputs) }
    _context.endBuild()
    return root
  }
}

@MainActor @preconcurrency
open class NSHostingController<Content: View>: NSViewController {
  public var rootView: Content {
    didSet { (viewIfLoaded as? NSHostingView<Content>)?.rootView = rootView }
  }
  public init(rootView: Content) {
    self.rootView = rootView
    super.init(nibName: nil, bundle: nil)
  }
  override open func loadView() {
    let v = NSHostingView(rootView: rootView)
    v.sizingOptions = sizingOptions
    v.safeAreaRegions = safeAreaRegions
    view = v
  }
  public var sizingOptions: NSHostingSizingOptions = .standardBounds {
    didSet { (viewIfLoaded as? NSHostingView<Content>)?.sizingOptions = sizingOptions }
  }
  public var safeAreaRegions: SafeAreaRegions = .all {
    didSet { (viewIfLoaded as? NSHostingView<Content>)?.safeAreaRegions = safeAreaRegions }
  }
  /// The size the content wants within `size`.
  public func sizeThatFits(in size: CGSize) -> CGSize {
    let host = (viewIfLoaded as? NSHostingView<Content>) ?? NSHostingView(rootView: rootView)
    return host._makeRoot().sizeThatFits(ProposedViewSize(width: size.width, height: size.height))
  }
}

/// The sizes of a hosting view's content it turns into constraints.
public struct NSHostingSizingOptions: OptionSet, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let minSize = NSHostingSizingOptions(rawValue: 1 << 0)
  public static let intrinsicContentSize = NSHostingSizingOptions(rawValue: 1 << 1)
  public static let maxSize = NSHostingSizingOptions(rawValue: 1 << 2)
  public static let preferredContentSize = NSHostingSizingOptions(rawValue: 1 << 3)
  public static let standardBounds: NSHostingSizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
}
