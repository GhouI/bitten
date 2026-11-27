// Scene modifiers (commands, default size, resizability, window styles,
// launch behaviour), the actions that open windows, and the main menu built
// from the app's commands.

import CoreGraphics

/// What modifiers set on the scenes inside them.
struct _SceneConfig {
  var defaultSize: CGSize?
  var defaultPosition: UnitPoint?
  var resizability: WindowResizability = .automatic
  var hiddenTitleBar = false
  var launchBehavior: SceneLaunchBehavior = .automatic
}

/// A scene with a modifier applied: visiting it visits the content with
/// the modifier's settings.
@MainActor
public struct _SceneModifierScene<Content: Scene>: Scene {
  let content: Content
  let modify: (inout _SceneConfig) -> Void
  let commands: ((inout _ResolvedCommands) -> Void)?
  public typealias Body = Never
  public var body: Never { return fatalError("no body") }
}
extension _SceneModifierScene: _PrimitiveScene {
  func _makeWindows(_ host: _AppHost) {
    commands?(&host.commands)
    host.withConfig(modify) { host.visit(content) }
  }
}

extension Scene {
  func _modified(_ modify: @escaping (inout _SceneConfig) -> Void) -> _SceneModifierScene<Self> {
    return _SceneModifierScene(content: self, modify: modify, commands: nil)
  }
  public func commands<C: Commands>(@CommandsBuilder content: () -> C) -> some Scene {
    let c = content()
    return _SceneModifierScene(content: self, modify: { _ in }, commands: { c._resolve(into: &$0) })
  }
  public func commandsRemoved() -> some Scene { return _modified { _ in } }
  public func commandsReplaced<C: Commands>(@CommandsBuilder content: () -> C) -> some Scene {
    return commands(content: content)
  }
  public func defaultSize(_ size: CGSize) -> some Scene { return _modified { $0.defaultSize = size } }
  public func defaultSize(width: CGFloat, height: CGFloat) -> some Scene {
    return _modified { $0.defaultSize = CGSize(width: width, height: height) }
  }
  public func defaultPosition(_ position: UnitPoint) -> some Scene { return _modified { $0.defaultPosition = position } }
  public func windowResizability(_ resizability: WindowResizability) -> some Scene {
    return _modified { $0.resizability = resizability }
  }
  public func windowStyle<S: WindowStyle>(_ style: S) -> some Scene {
    let hidden = style is HiddenTitleBarWindowStyle
    return _modified { $0.hiddenTitleBar = hidden }
  }
  public func windowToolbarStyle<S: WindowToolbarStyle>(_ style: S) -> some Scene { return _modified { _ in } }
  public func defaultLaunchBehavior(_ behavior: SceneLaunchBehavior) -> some Scene {
    return _modified { $0.launchBehavior = behavior }
  }
  public func restorationBehavior(_ behavior: SceneRestorationBehavior) -> some Scene { return _modified { _ in } }
  public func handlesExternalEvents(matching conditions: Set<String>) -> some Scene { return _modified { _ in } }
  public func windowBackgroundDragBehavior(_ behavior: WindowInteractionBehavior) -> some Scene {
    return _modified { _ in }
  }
  public func windowManagerRole(_ role: WindowManagerRole) -> some Scene { return _modified { _ in } }
  public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some Scene {
    return _modified { _ in }
  }
}

public struct WindowResizability: Sendable, Equatable {
  let id: Int
  public static let automatic = WindowResizability(id: 0)
  public static let contentSize = WindowResizability(id: 1)
  public static let contentMinSize = WindowResizability(id: 2)
}
public struct SceneLaunchBehavior: Sendable, Equatable {
  let id: Int
  public static let automatic = SceneLaunchBehavior(id: 0)
  public static let presented = SceneLaunchBehavior(id: 1)
  public static let suppressed = SceneLaunchBehavior(id: 2)
}
public struct SceneRestorationBehavior: Sendable, Equatable {
  let id: Int
  public static let automatic = SceneRestorationBehavior(id: 0)
  public static let disabled = SceneRestorationBehavior(id: 1)
}
public struct WindowInteractionBehavior: Sendable, Equatable {
  let id: Int
  public static let automatic = WindowInteractionBehavior(id: 0)
  public static let enabled = WindowInteractionBehavior(id: 1)
  public static let disabled = WindowInteractionBehavior(id: 2)
}
public struct WindowManagerRole: Sendable, Equatable {
  let id: Int
  public static let automatic = WindowManagerRole(id: 0)
  public static let principal = WindowManagerRole(id: 1)
  public static let associated = WindowManagerRole(id: 2)
}
public struct WindowToolbarFullScreenVisibility: Sendable, Equatable {
  let id: Int
  public static let automatic = WindowToolbarFullScreenVisibility(id: 0)
  public static let visible = WindowToolbarFullScreenVisibility(id: 1)
  public static let onHover = WindowToolbarFullScreenVisibility(id: 2)
}

public protocol WindowStyle {}
public struct DefaultWindowStyle: WindowStyle { public init() {} }
public struct HiddenTitleBarWindowStyle: WindowStyle { public init() {} }
public struct TitleBarWindowStyle: WindowStyle { public init() {} }
public struct PlainWindowStyle: WindowStyle { public init() {} }
extension WindowStyle where Self == DefaultWindowStyle { public static var automatic: DefaultWindowStyle { return .init() } }
extension WindowStyle where Self == HiddenTitleBarWindowStyle {
  public static var hiddenTitleBar: HiddenTitleBarWindowStyle { return .init() }
}
extension WindowStyle where Self == TitleBarWindowStyle { public static var titleBar: TitleBarWindowStyle { return .init() } }
extension WindowStyle where Self == PlainWindowStyle { public static var plain: PlainWindowStyle { return .init() } }

public protocol WindowToolbarStyle {}
public struct DefaultWindowToolbarStyle: WindowToolbarStyle { public init() {} }
public struct ExpandedWindowToolbarStyle: WindowToolbarStyle { public init() {} }
public struct UnifiedWindowToolbarStyle: WindowToolbarStyle {
  let showsTitle: Bool
  public init() { showsTitle = true }
  public init(showsTitle: Bool) { self.showsTitle = showsTitle }
}
public struct UnifiedCompactWindowToolbarStyle: WindowToolbarStyle {
  public init() {}
  public init(showsTitle: Bool) {}
}
extension WindowToolbarStyle where Self == DefaultWindowToolbarStyle {
  public static var automatic: DefaultWindowToolbarStyle { return .init() }
}
extension WindowToolbarStyle where Self == ExpandedWindowToolbarStyle {
  public static var expanded: ExpandedWindowToolbarStyle { return .init() }
}
extension WindowToolbarStyle where Self == UnifiedWindowToolbarStyle {
  public static var unified: UnifiedWindowToolbarStyle { return .init() }
  public static func unified(showsTitle: Bool) -> UnifiedWindowToolbarStyle { return .init(showsTitle: showsTitle) }
}
extension WindowToolbarStyle where Self == UnifiedCompactWindowToolbarStyle {
  public static var unifiedCompact: UnifiedCompactWindowToolbarStyle { return .init() }
}

extension View {
  public func windowMinimizeBehavior(_ behavior: WindowInteractionBehavior) -> some View { return self }
  public func windowResizeBehavior(_ behavior: WindowInteractionBehavior) -> some View { return self }
  public func windowDismissBehavior(_ behavior: WindowInteractionBehavior) -> some View { return self }
  public func windowFullScreenBehavior(_ behavior: WindowInteractionBehavior) -> some View { return self }
  public func windowToolbarFullScreenVisibility(_ visibility: WindowToolbarFullScreenVisibility) -> some View {
    return self
  }
}

// MARK: - opening windows

@MainActor @preconcurrency
public struct OpenWindowAction: Sendable {
  public func callAsFunction(id: String) { _AppHost.shared.open(id: id) }
  public func callAsFunction<D: Decodable & Encodable & Hashable>(id: String, value: D) {
    _AppHost.shared.presentedValues[id] = value
    _AppHost.shared.open(id: id)
  }
  public func callAsFunction<D: Decodable & Encodable & Hashable>(value: D) {
    if let id = _AppHost.shared.presentedTypes[ObjectIdentifier(D.self)] { callAsFunction(id: id, value: value) }
  }
}
@MainActor @preconcurrency
public struct DismissWindowAction: Sendable {
  public func callAsFunction() { NSApp.keyWindow?.performClose(nil) }
  public func callAsFunction(id: String) {
    for w in NSApp.windows where w.identifier?.rawValue == id { w.performClose(nil) }
  }
}
@MainActor @preconcurrency
public struct OpenSettingsAction: Sendable {
  public func callAsFunction() { _AppHost.shared.open(id: "settings") }
}

struct _OpenWindowKey: EnvironmentKey { static let defaultValue = OpenWindowAction() }
struct _DismissWindowKey: EnvironmentKey { static let defaultValue = DismissWindowAction() }
struct _OpenSettingsKey: EnvironmentKey { static let defaultValue = OpenSettingsAction() }
extension EnvironmentValues {
  public var openWindow: OpenWindowAction { return self[_OpenWindowKey.self] }
  public var dismissWindow: DismissWindowAction { return self[_DismissWindowKey.self] }
  public var openSettings: OpenSettingsAction { return self[_OpenSettingsKey.self] }
}

extension _AppHost {
  /// Values handed to `openWindow(id:value:)`, by window id.
  var presentedValues: [String: Any] {
    get { return _presentedValues }
    set { _presentedValues = newValue }
  }
}
nonisolated(unsafe) var _presentedValues: [String: Any] = [:]

/// A window group's content for a presented value.
public struct PresentedWindowContent<Data: Decodable & Encodable & Hashable, Content: View>: View {
  let id: String
  let content: (Binding<Data?>) -> Content
  public typealias Body = Never
  public var body: Never { fatalError("no body") }
  public static func _makeView(view: _GraphValue<PresentedWindowContent>, inputs: _ViewInputs) -> _ViewOutputs {
    let v = view.value
    let id = v.id
    let binding = Binding<Data?>(get: { _presentedValues[id] as? Data }, set: { _presentedValues[id] = $0 })
    return _ViewOutputs(_makeNode(v.content(binding), inputs: inputs.named("presented")))
  }
}

extension WindowGroup {
  public init<S: StringProtocol, D, C>(_ title: S, id: String, for type: D.Type,
                                       @ViewBuilder content: @escaping (Binding<D?>) -> C)
    where Content == PresentedWindowContent<D, C>, D: Decodable & Encodable & Hashable, C: View {
    self.init(String(title), id: id) { PresentedWindowContent(id: id, content: content) }
    _AppHost.registerPresented(D.self, id: id)
  }
  public init<D, C>(id: String, for type: D.Type, @ViewBuilder content: @escaping (Binding<D?>) -> C)
    where Content == PresentedWindowContent<D, C>, D: Decodable & Encodable & Hashable, C: View {
    self.init(id: id) { PresentedWindowContent(id: id, content: content) }
    _AppHost.registerPresented(D.self, id: id)
  }
  public init<D, C>(for type: D.Type, @ViewBuilder content: @escaping (Binding<D?>) -> C)
    where Content == PresentedWindowContent<D, C>, D: Decodable & Encodable & Hashable, C: View {
    let id = String(describing: D.self)
    self.init(id: id) { PresentedWindowContent(id: id, content: content) }
    _AppHost.registerPresented(D.self, id: id)
  }
}

nonisolated(unsafe) var _presentedTypes: [ObjectIdentifier: String] = [:]
extension _AppHost {
  var presentedTypes: [ObjectIdentifier: String] { return _presentedTypes }
  nonisolated static func registerPresented<D>(_ type: D.Type, id: String) { _presentedTypes[ObjectIdentifier(type)] = id }
}

extension Window {
  public init(_ titleKey: LocalizedStringKey, id: String, @ViewBuilder content: () -> Content) {
    self.init(Text(titleKey)._string, id: id, content: content)
  }
  public init(_ title: Text, id: String, @ViewBuilder content: () -> Content) {
    self.init(title._string, id: id, content: content)
  }
}

// MARK: - the main menu

/// Sends a menu item's action to a Swift closure.
final class _MenuActionTarget: NSObject {
  let action: () -> Void
  init(_ action: @escaping () -> Void) { self.action = action }
  /// Named apart from NSObject's perform(_:) (-performSelector:), which a
  /// #selector of perform(_:) would pick.
  @objc(performMenuAction:) func performMenuAction(_ sender: Any?) { action() }
}
nonisolated(unsafe) var _menuTargets: [_MenuActionTarget] = []

@MainActor
private func _item(_ title: String, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command,
                   _ action: @escaping () -> Void) -> NSMenuItem {
  let t = _MenuActionTarget(action)
  _menuTargets.append(t)
  let item = NSMenuItem(title: title, action: #selector(_MenuActionTarget.performMenuAction(_:)), keyEquivalent: key)
  item.target = t
  item.keyEquivalentModifierMask = mods
  return item
}

@MainActor
private func _selectorItem(_ title: String, _ action: Selector, _ key: String = "",
                           _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
  let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
  item.keyEquivalentModifierMask = mods
  return item
}

@MainActor
private func _menuItem(_ e: _MenuItemEntry) -> NSMenuItem {
  if e.isSeparator { return NSMenuItem.separator() }
  var key = ""
  var mods: NSEvent.ModifierFlags = .command
  if let s = e.shortcut {
    key = String(s.key.character)
    mods = []
    if s.modifiers.contains(.command) { mods.insert(.command) }
    if s.modifiers.contains(.shift) { mods.insert(.shift) }
    if s.modifiers.contains(.option) { mods.insert(.option) }
    if s.modifiers.contains(.control) { mods.insert(.control) }
  }
  let action = e.action ?? {}
  let item = _item(e.title, key, mods) { MainActor.assumeIsolated { action() } }
  if let children = e.children {
    let sub = NSMenu(title: e.title)
    for c in children { sub.addItem(_menuItem(c)) }
    item.submenu = sub
  }
  return item
}

/// The standard menus, with the app's command groups placed in them.
@MainActor
func _installMainMenu(_ commands: _ResolvedCommands) {
  let app = NSApplication.shared
  let name = _AppHost.shared.appName
  struct Group { var placement: String; var items: [NSMenuItem] }
  // Each menu is a list of placement groups.
  var menus: [(title: String, groups: [Group])] = [
    (name, [Group(placement: "appInfo", items: [_selectorItem("About \(name)",
                                                              #selector(NSApplication.orderFrontStandardAboutPanel(_:)))]),
            Group(placement: "appSettings", items: _AppHost.shared.registered["settings"] == nil ? [] :
                    [_item("Settings…", ",") { MainActor.assumeIsolated { _AppHost.shared.open(id: "settings") } }]),
            Group(placement: "systemServices", items: []),
            Group(placement: "appVisibility", items: [_selectorItem("Hide \(name)", #selector(NSApplication.hide(_:)), "h")]),
            Group(placement: "appTermination", items: [_selectorItem("Quit \(name)", #selector(NSApplication.terminate(_:)), "q")])]),
    ("File", [Group(placement: "newItem", items: []), Group(placement: "saveItem", items: []),
              Group(placement: "importExport", items: []), Group(placement: "printItem", items: [])]),
    ("Edit", [Group(placement: "undoRedo", items: []), Group(placement: "pasteboard", items: []),
              Group(placement: "textEditing", items: []), Group(placement: "textFormatting", items: [])]),
    ("View", [Group(placement: "toolbar", items: []), Group(placement: "sidebar", items: [])]),
    ("Window", [Group(placement: "windowSize", items: [_selectorItem("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
                                                       _selectorItem("Zoom", #selector(NSWindow.performZoom(_:)))]),
                Group(placement: "windowList", items: []), Group(placement: "singleWindowList", items: []),
                Group(placement: "windowArrangement", items: [])]),
    ("Help", [Group(placement: "help", items: [])]),
  ]
  var extra: [(String, [NSMenuItem])] = []
  for g in commands.groups {
    let items = g.items.map(_menuItem)
    if case .menu(let title) = g.position {
      extra.append((title, items))
      continue
    }
    guard let placement = g.placement?.name else { continue }
    for m in menus.indices {
      guard let gi = menus[m].groups.firstIndex(where: { $0.placement == placement }) else { continue }
      switch g.position {
      case .replacing: menus[m].groups[gi].items = items
      case .before: menus[m].groups[gi].items.insert(contentsOf: items, at: 0)
      default: menus[m].groups[gi].items.append(contentsOf: items)
      }
    }
  }
  let main = NSMenu(title: "Main Menu")
  func add(_ title: String, _ groups: [[NSMenuItem]]) {
    let menu = NSMenu(title: title)
    var first = true
    for items in groups where !items.isEmpty {
      if !first { menu.addItem(NSMenuItem.separator()) }
      first = false
      for i in items { menu.addItem(i) }
    }
    let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    top.submenu = menu
    main.addItem(top)
  }
  for (i, m) in menus.enumerated() {
    if m.title == "Window" { for (t, items) in extra { add(t, [items]) } }
    add(m.title, m.groups.map { $0.items })
    _ = i
  }
  app.mainMenu = main
}
