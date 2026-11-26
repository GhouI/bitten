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

  func installDelegate(_ type: (NSObject & NSApplicationDelegate).Type) {
    if delegate != nil { return }
    let d = type.init()
    delegate = d
    NSApplication.shared.delegate = d
  }

  func start<A: App>(_ app: A) {
    let nsapp = NSApplication.shared
    visit(app.body)
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
      if scheduled { return }
      scheduled = true
      await Task.yield()
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

  func _makeRoot() -> _ViewNode { fatalError("abstract") }

  func _bn_invalidate() {
    _root = nil
    needsDisplay = true
  }

  /// The tree, built (and laid out in the bounds) on demand.
  func _layout() -> _ViewNode {
    if let r = _root, _placedIn.width == bounds.size.width, _placedIn.height == bounds.size.height { return r }
    let r = _root ?? _makeRoot()
    _root = r
    // The root takes the size it wants of the bounds, centred in them.
    let want = r.sizeThatFits(ProposedViewSize(bounds.size))
    let size = CGSize(width: min(want.width, bounds.size.width), height: min(want.height, bounds.size.height))
    let origin = CGPoint(x: ((bounds.size.width - size.width) / 2).rounded(.down),
                         y: ((bounds.size.height - size.height) / 2).rounded(.down))
    r.place(in: CGRect(origin: origin, size: size))
    _placedIn = bounds.size
    return r
  }

  override open var isFlipped: Bool { return true }

  override open func draw(_ dirtyRect: NSRect) {
    guard let cg = NSGraphicsContext.current?.cgContext else { return }
    _layout().draw(cg)
  }

  override open func mouseDown(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    _pressed = _layout().hit(p)
  }
  override open func mouseUp(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    if let pressed = _pressed, _layout().hit(p) === pressed { pressed.tap() }
    _pressed = nil
  }

  /// The size the content wants when nothing is proposed.
  public var fittingContentSize: NSSize {
    return _makeRoot().sizeThatFits(.unspecified)
  }
}

/// An AppKit view that hosts a SwiftUI view tree.
@MainActor @preconcurrency
open class NSHostingView<Content: View>: _HostingViewBase {
  public var rootView: Content {
    didSet { _bn_invalidate() }
  }
  public required init(rootView: Content) {
    self.rootView = rootView
    super.init(frame: NSMakeRect(0, 0, 100, 100))
  }
  override func _makeRoot() -> _ViewNode {
    let inputs = _ViewInputs(_GraphInputs(environment: _environment, context: _context, path: ""))
    _context.beginBuild()
    let root = _makeNode(rootView, inputs: inputs)
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
    view = NSHostingView(rootView: rootView)
  }
}
