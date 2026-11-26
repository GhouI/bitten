// Bridging between Swift values and Objective-C objects. The protocol is
// what makes the importer present NSString as String, NSArray as [T] and so
// on (Foundation's overlay supplies the conformances); the functions are
// the compiler's entry points for `as` conversions and for `id`/`Any`.

public protocol _ObjectiveCBridgeable {
  associatedtype _ObjectiveCType: AnyObject
  func _bridgeToObjectiveC() -> _ObjectiveCType
  static func _forceBridgeFromObjectiveC(_ source: _ObjectiveCType, result: inout Self?)
  @discardableResult
  static func _conditionallyBridgeFromObjectiveC(_ source: _ObjectiveCType, result: inout Self?) -> Bool
  static func _unconditionallyBridgeFromObjectiveC(_ source: _ObjectiveCType?) -> Self
}

@inlinable
public func _forceBridgeFromObjectiveC_bridgeable<T: _ObjectiveCBridgeable>(_ x: T._ObjectiveCType, _: T.Type) -> T {
  var result: T?
  T._forceBridgeFromObjectiveC(x, result: &result)
  return result!
}

@inlinable
public func _conditionallyBridgeFromObjectiveC_bridgeable<T: _ObjectiveCBridgeable>(_ x: T._ObjectiveCType, _: T.Type) -> T? {
  var result: T?
  T._conditionallyBridgeFromObjectiveC(x, result: &result)
  return result
}

/// Holds a Swift value that has no Objective-C counterpart when it has to
/// travel as `id` (Apple calls it __SwiftValue too).
public final class __SwiftValue {
  public let value: Any
  public init(_ value: Any) { self.value = value }
}

/// `T` as an Objective-C object: bridged when T is bridgeable, itself when
/// it is a class instance, boxed otherwise.
public func _bridgeAnythingToObjectiveC<T>(_ x: T) -> AnyObject {
  if let b = x as? any _ObjectiveCBridgeable { return _bridgeOpened(b) }
  if T.self is AnyClass || type(of: x as Any) is AnyClass { return unsafeBitCast(x as Any as! AnyObject?, to: AnyObject.self) }
  return __SwiftValue(x)
}
private func _bridgeOpened<B: _ObjectiveCBridgeable>(_ b: B) -> AnyObject { return b._bridgeToObjectiveC() }

/// An `id` coming in from Objective-C, as Any (unboxing boxed Swift values).
public func _bridgeAnyObjectToAny(_ possiblyNullObject: AnyObject?) -> Any {
  guard let object = possiblyNullObject else { return Optional<AnyObject>.none as Any }
  if let boxed = object as? __SwiftValue { return boxed.value }
  return object
}

/// Like _bridgeAnythingToObjectiveC, for values known not to be classes.
public func _bridgeAnythingNonVerbatimToObjectiveC<T>(_ x: __owned T) -> AnyObject {
  return _bridgeAnythingToObjectiveC(x)
}

/// An Objective-C object bridged to T (trapping when it cannot be).
public func _forceBridgeFromObjectiveC<T>(_ x: AnyObject, _: T.Type) -> T {
  if let b = T.self as? any _ObjectiveCBridgeable.Type {
    func open<B: _ObjectiveCBridgeable>(_ type: B.Type) -> T {
      return B._unconditionallyBridgeFromObjectiveC(x as? B._ObjectiveCType) as! T
    }
    return open(b)
  }
  if let boxed = x as? __SwiftValue { return boxed.value as! T }
  return x as! T
}

/// An NSArray as [T].
public func _bridgeCocoaArray<T>(_ value: AnyObject) -> [T] {
  return _forceBridgeFromObjectiveC(value, [T].self)
}

/// Called by the runtime's dynamic casts (casts.c) for `object as? T` when
/// T bridges from Objective-C (`nsString as? String`).
@_silgen_name("_bitten_bridgeFromObjectiveCConditional")
public func _bitten_bridgeFromObjectiveCConditional<T>(_ object: AnyObject, _ target: UnsafeMutablePointer<T>) -> Bool {
  guard let b = T.self as? any _ObjectiveCBridgeable.Type else { return false }
  func open<B: _ObjectiveCBridgeable>(_ type: B.Type) -> T? {
    guard let source = object as? B._ObjectiveCType else { return nil }
    var result: B?
    B._conditionallyBridgeFromObjectiveC(source, result: &result)
    return result.map { $0 as! T }
  }
  guard let value = open(b) else { return false }
  target.initialize(to: value)
  return true
}
