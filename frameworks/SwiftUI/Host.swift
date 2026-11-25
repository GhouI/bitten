// The application host: runs the App, opens its windows, keeps the graph
// up to date, and hosts views in AppKit (NSHostingView/Controller).

@MainActor
final class _AppHost {
  static let shared = _AppHost()

  var delegate: NSObject?
  var windows: [NSWindow] = []
  var registered: [String: (title: String, make: () -> NSView)] = [:]

  var appName: String {
    return NSProcessInfo.processInfo.processName
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
  nonisolated static func invalidate() {
    Task { @MainActor in
      for w in _AppHost.shared.windows { w.contentView?.needsDisplay = true }
    }
  }
}

/// An AppKit view that hosts a SwiftUI view tree.
@MainActor @preconcurrency
open class NSHostingView<Content: View>: NSView {
  public var rootView: Content {
    didSet { needsDisplay = true }
  }
  public required init(rootView: Content) {
    self.rootView = rootView
    super.init(frame: NSMakeRect(0, 0, 100, 100))
  }
}

@MainActor @preconcurrency
open class NSHostingController<Content: View>: NSViewController {
  public var rootView: Content
  public init(rootView: Content) {
    self.rootView = rootView
    super.init()
  }
}
