// Notification: the value type NotificationCenter hands Swift code,
// bridged to NSNotification.

public struct Notification: Hashable, Equatable, CustomStringConvertible {
  public typealias Name = NSNotification.Name

  public var name: Name
  public var object: Any?
  public var userInfo: [AnyHashable: Any]?

  public init(name: Name, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
    self.name = name
    self.object = object
    self.userInfo = userInfo
  }

  public static func == (lhs: Notification, rhs: Notification) -> Bool {
    guard lhs.name == rhs.name else { return false }
    switch (lhs.object, rhs.object) {
    case (nil, nil): break
    case let (a?, b?):
      guard (a as AnyObject) === (b as AnyObject) else { return false }
    default: return false
    }
    return (lhs.userInfo == nil) == (rhs.userInfo == nil)
  }
  public func hash(into hasher: inout Hasher) { hasher.combine(name) }
  public var description: String { return "name = \(name.rawValue), object = \(String(describing: object))" }
}

extension Notification: _ObjectiveCBridgeable {
  public func _bridgeToObjectiveC() -> NSNotification {
    return NSNotification(name: name, object: object.map { $0 as AnyObject }, userInfo: userInfo)
  }
  public static func _forceBridgeFromObjectiveC(_ x: NSNotification, result: inout Notification?) {
    result = _unconditionallyBridgeFromObjectiveC(x)
  }
  public static func _conditionallyBridgeFromObjectiveC(_ x: NSNotification, result: inout Notification?) -> Bool {
    result = _unconditionallyBridgeFromObjectiveC(x)
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNotification?) -> Notification {
    guard let n = source else { return Notification(name: Name(rawValue: "")) }
    return Notification(name: n.name, object: n.object, userInfo: n.userInfo)
  }
}

// MARK: - notifications as an asynchronous sequence

import _Concurrency

extension NotificationCenter {
  /// The notifications named `name` (from `object`, if given), from now on.
  public func notifications(named name: Notification.Name, object: AnyObject? = nil) -> Notifications {
    return Notifications(center: self, name: name, object: object)
  }

  public final class Notifications: AsyncSequence, @unchecked Sendable {
    public typealias Element = Notification
    private let stream: AsyncStream<Notification>
    private let center: NotificationCenter
    private var token: NSObjectProtocol?

    internal init(center: NotificationCenter, name: Notification.Name, object: AnyObject?) {
      self.center = center
      var cont: AsyncStream<Notification>.Continuation!
      stream = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
      let continuation = cont!
      token = center.addObserver(forName: name, object: object, queue: nil) { note in continuation.yield(note) }
    }
    deinit {
      if let t = token { center.removeObserver(t) }
    }

    public struct Iterator: AsyncIteratorProtocol {
      internal var base: AsyncStream<Notification>.Iterator
      internal let owner: Notifications
      public mutating func next() async -> Notification? { return await base.next() }
    }
    public func makeAsyncIterator() -> Iterator { return Iterator(base: stream.makeAsyncIterator(), owner: self) }
  }
}
