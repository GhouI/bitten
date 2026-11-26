// QuartzCore's Swift overlay (libswiftQuartzCore): the frame-rate range's
// optional preferred rate and CATransform3D's bridging to NSValue. Built
// after Foundation's Swift module, so it is not one of overlays/.
@_exported import QuartzCore
import Foundation

extension CAFrameRateRange {
  public init(minimum: Float, maximum: Float, preferred: Float? = nil) {
    self = CAFrameRateRangeMake(minimum, maximum, preferred ?? 0)
  }

  /// nil when no rate is preferred (stored as 0, as Apple stores it).
  public var preferred: Float? {
    return __preferred == 0 ? nil : __preferred
  }
}

extension CATransform3D: _ObjectiveCBridgeable {
  public func _bridgeToObjectiveC() -> NSValue {
    return NSValue(caTransform3D: self)
  }

  public static func _forceBridgeFromObjectiveC(_ source: NSValue, result: inout CATransform3D?) {
    result = source.caTransform3DValue
  }

  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSValue, result: inout CATransform3D?) -> Bool {
    result = source.caTransform3DValue
    return true
  }

  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSValue?) -> CATransform3D {
    return source?.caTransform3DValue ?? CATransform3DIdentity
  }
}
