// AppKit's Swift part, linked into the framework with the Objective-C
// objects (as Foundation's is): Swift-only API over the Objective-C
// classes.

@_exported import AppKit
@_exported import Foundation
import CoreGraphics

// MARK: - drawing helpers

extension CGRect {
  /// Fills the rectangle with the current fill colour.
  public func fill(using operation: NSCompositingOperation = .sourceOver) {
    NSRectFillUsingOperation(self, operation)
  }
  /// Intersects the current clip with the rectangle.
  public func clip() {
    NSRectClip(self)
  }
  public func frame(withWidth width: CGFloat = 1.0, using operation: NSCompositingOperation = .sourceOver) {
    NSFrameRectWithWidth(self, width)
  }
}

extension NSGradient {
  public convenience init?(colorsAndLocations objects: (NSColor, CGFloat)...) {
    self.init(colors: objects.map { $0.0 }, locations: objects.map { NSNumber(value: Double($0.1)) })
  }
}

extension NSSound {
  /// The system alert sound (silent here).
  public static func beep() {
    NSBeep()
  }
}

extension NSMenuItem {
  /// A non-selectable item titling the items after it.
  public static func sectionHeader(title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }
}

// MARK: - resize cursors

public enum NSHorizontalDirection: Int, Sendable {
  case left, right
  public struct Set: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static var left: Set { return Set(rawValue: 1) }
    public static var right: Set { return Set(rawValue: 2) }
    public static var all: Set { return [.left, .right] }
  }
}

public enum NSVerticalDirection: Int, Sendable {
  case up, down
  public struct Set: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static var up: Set { return Set(rawValue: 1) }
    public static var down: Set { return Set(rawValue: 2) }
    public static var all: Set { return [.up, .down] }
  }
}

extension NSCursor {
  public enum FrameResizeDirection: Int, Sendable {
    case inward, outward
    public struct Set: OptionSet, Sendable, Hashable {
      public let rawValue: Int
      public init(rawValue: Int) { self.rawValue = rawValue }
      public static var inward: Set { return Set(rawValue: 1) }
      public static var outward: Set { return Set(rawValue: 2) }
      public static var all: Set { return [.inward, .outward] }
    }
  }
  public static func columnResize(directions: NSHorizontalDirection.Set = .all) -> NSCursor {
    let c: NSCursor = NSCursor.columnResize
    return c
  }
  public static func rowResize(directions: NSVerticalDirection.Set = .all) -> NSCursor {
    let c: NSCursor = NSCursor.rowResize
    return c
  }
  /// Edges resize along their axis; corners get the crosshair.
  public static func frameResize(position: NSCursorFrameResizePosition,
                                 directions: FrameResizeDirection.Set = .all) -> NSCursor {
    let horizontal = position.contains(.left) || position.contains(.right)
    let vertical = position.contains(.top) || position.contains(.bottom)
    if horizontal && vertical { return NSCursor.crosshair }
    return horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown
  }
}

extension NSCursorFrameResizePosition {
  private static func flip(_ p: NSCursorFrameResizePosition, _ d: NSUserInterfaceLayoutDirection) -> NSCursorFrameResizePosition {
    guard d == .rightToLeft else { return p }
    var r = p
    if p.contains(.left) { r.remove(.left); r.insert(.right) } else if p.contains(.right) { r.remove(.right); r.insert(.left) }
    return r
  }
  public static func topLeading(relativeTo direction: NSUserInterfaceLayoutDirection) -> NSCursorFrameResizePosition {
    return flip([.top, .left], direction)
  }
  public static func topTrailing(relativeTo direction: NSUserInterfaceLayoutDirection) -> NSCursorFrameResizePosition {
    return flip([.top, .right], direction)
  }
  public static func bottomLeading(relativeTo direction: NSUserInterfaceLayoutDirection) -> NSCursorFrameResizePosition {
    return flip([.bottom, .left], direction)
  }
  public static func bottomTrailing(relativeTo direction: NSUserInterfaceLayoutDirection) -> NSCursorFrameResizePosition {
    return flip([.bottom, .right], direction)
  }
}
