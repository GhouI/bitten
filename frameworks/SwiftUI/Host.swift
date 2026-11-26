// The application host: runs the App, opens its windows, keeps the graph
// up to date, and hosts views in AppKit (NSHostingView/Controller).

@MainActor
final class _AppHost {
  static let shared = _AppHost()

  var delegate: NSObject?
  var windows: [NSWindow] = []
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

  func openWindow<V: View>(title: String, id: String?, content: @escaping () -> V) {
    let frame = NSScreen.main?.visibleFrame ?? NSMakeRect(0, 0, 1440, 875)
    let w = NSWindow(contentRect: NSMakeRect(0, 0, min(900, frame.size.width), min(600, frame.size.height)),
                     styleMask: [.titled, .closable, .resizable, .miniaturizable],
                     backing: .buffered, defer: false)
    w.title = title
    w.contentView = NSHostingView(rootView: content())
    w.center()
    w.makeKeyAndOrderFront(nil)
    windows.append(w)
  }

  func registerWindow<V: View>(id: String, title: String, content: @escaping () -> V) {
    registered[id] = (title, { NSHostingView(rootView: content()) })
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

  override public init(frame: NSRect) {
    super.init(frame: frame)
    _context.invalidate = { _GraphHost.invalidate() }
    _GraphHost.hosts.append(_WeakHost(self))
  }

  func _makeRoot() -> _ViewNode { fatalError("abstract") }

  func _bn_invalidate() {
    _root = nil
    needsDisplay = true
  }

  /// The tree, built (and laid out in the bounds) on demand.
  func _layout() -> _ViewNode {
    if let r = _root, r.frame.size.width == bounds.size.width, r.frame.size.height == bounds.size.height { return r }
    let r = _root ?? _makeRoot()
    _root = r
    r.place(in: CGRect(origin: CGPoint(x: 0, y: 0), size: bounds.size))
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
    return _makeNode(rootView, inputs: inputs)
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
