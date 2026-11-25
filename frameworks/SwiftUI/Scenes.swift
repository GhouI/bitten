// Scenes: windows, window groups and the settings window.

/// Scenes the host knows how to open. The public scene types conform.
@MainActor protocol _PrimitiveScene {
  func _makeWindows(_ host: _AppHost)
}

public struct WindowGroup<Content: View>: Scene {
  let title: String?
  let id: String?
  let content: () -> Content
  public init(@ViewBuilder content: @escaping () -> Content) {
    title = nil
    id = nil
    self.content = content
  }
  public init(id: String, @ViewBuilder content: @escaping () -> Content) {
    title = nil
    self.id = id
    self.content = content
  }
  public init<S: StringProtocol>(_ title: S, @ViewBuilder content: @escaping () -> Content) {
    self.title = String(title)
    id = nil
    self.content = content
  }
  public init<S: StringProtocol>(_ title: S, id: String, @ViewBuilder content: @escaping () -> Content) {
    self.title = String(title)
    self.id = id
    self.content = content
  }
  public typealias Body = Never
  public var body: Never { fatalError("WindowGroup has no body") }
}
extension WindowGroup: _PrimitiveScene {
  func _makeWindows(_ host: _AppHost) { host.openWindow(title: title ?? host.appName, id: id, content: content) }
}

public struct Window<Content: View>: Scene {
  let title: String
  let id: String
  let content: () -> Content
  public init<S: StringProtocol>(_ title: S, id: String, @ViewBuilder content: () -> Content) {
    self.title = String(title)
    self.id = id
    let made = content()
    self.content = { made }
  }
  public typealias Body = Never
  public var body: Never { fatalError("Window has no body") }
}
extension Window: _PrimitiveScene {
  /// A single window, opened on request (`openWindow(id:)`), not at launch.
  func _makeWindows(_ host: _AppHost) { host.registerWindow(id: id, title: title, content: content) }
}

public struct Settings<Content: View>: Scene {
  let content: () -> Content
  public init(@ViewBuilder content: () -> Content) {
    let made = content()
    self.content = { made }
  }
  public typealias Body = Never
  public var body: Never { fatalError("Settings has no body") }
}
extension Settings: _PrimitiveScene {
  func _makeWindows(_ host: _AppHost) { host.registerWindow(id: "settings", title: "Settings", content: content) }
}

extension _TupleScene: _PrimitiveScene {
  func _makeWindows(_ host: _AppHost) {
    _forEachTupleElement(value) { element in
      if let scene = element as? any Scene { host.visit(scene) }
    }
  }
}

/// Calls `body` with each element of the tuple `value` (or with `value`
/// itself when it is not a tuple), read through the tuple's metadata.
func _forEachTupleElement<T>(_ value: T, _ body: (Any) -> Void) {
  let md = unsafeBitCast(T.self as Any.Type, to: UnsafeRawPointer.self)
  // Tuple metadata: kind 0x301, number of elements, labels, then
  // {type, offset} per element.
  guard md.load(as: UInt.self) == 0x301 else {
    body(value)
    return
  }
  let n = md.load(fromByteOffset: 8, as: Int.self)
  withUnsafePointer(to: value) { p in
    let base = UnsafeRawPointer(p)
    for i in 0..<n {
      let entry = md + 24 + i * 16
      let type = entry.load(as: Any.Type.self)
      let offset = Int(entry.load(fromByteOffset: 8, as: UInt32.self))
      body(_load(type, from: base + offset))
    }
  }
}

/// Copies a value of a dynamically known type out of memory into an Any.
private func _load(_ type: Any.Type, from p: UnsafeRawPointer) -> Any {
  func open<E>(_: E.Type) -> Any { return p.assumingMemoryBound(to: E.self).pointee }
  return _openExistential(type, do: open)
}
