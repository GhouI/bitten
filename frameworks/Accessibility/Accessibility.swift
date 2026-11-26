// Accessibility notifications: posted to assistive technologies, of which
// there are none here, so posting does nothing.

public protocol _AccessibilityNotifications {}

extension _AccessibilityNotifications {
  public func post() {}
}

public enum AccessibilityNotification {
  public struct Announcement: _AccessibilityNotifications, Sendable {
    public let text: String
    public init(_ announcement: String) { text = announcement }
  }
  public struct LayoutChanged: _AccessibilityNotifications, Sendable {
    public init() {}
  }
  public struct ScreenChanged: _AccessibilityNotifications, Sendable {
    public init() {}
  }
  public struct PageScrolled: _AccessibilityNotifications, Sendable {
    public let text: String
    public init(_ text: String) { self.text = text }
  }
}
