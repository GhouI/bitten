// Foundation's Swift overlay, part 1: bridging. With these conformances the
// importer presents NSString as String, NSArray as Array, NSDictionary as
// Dictionary, NSSet as Set and NSNumber's values as numbers, everywhere a
// module imports Foundation. The overlay is linked into Foundation.framework
// itself, where macOS keeps it.

@_exported import Foundation
@_exported import Darwin

/// An Objective-C object converted to `T`: by bridging when T is
/// bridgeable, by a cast otherwise.
@inlinable
internal func _bridgeElement<T>(_ object: AnyObject, as: T.Type) -> T? {
  if let b = T.self as? any _ObjectiveCBridgeable.Type { return _openBridge(b, object) as? T }
  if let boxed = object as? __SwiftValue { return boxed.value as? T }
  return object as? T
}
@usableFromInline
internal func _openBridge<B: _ObjectiveCBridgeable>(_ type: B.Type, _ object: AnyObject) -> B? {
  guard let source = object as? B._ObjectiveCType else { return nil }
  var result: B?
  B._conditionallyBridgeFromObjectiveC(source, result: &result)
  return result
}

// ---- String ------------------------------------------------------------------------

extension String: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSString
  public func _bridgeToObjectiveC() -> NSString {
    var copy = self
    return copy.withUTF8 { buf -> NSString in
      let p = buf.baseAddress.map { UnsafeRawPointer($0) } ?? UnsafeRawPointer(bitPattern: 1)!
      return NSString(bytes: p, length: buf.count, encoding: UInt(NSUTF8StringEncoding))!
    }
  }
  public static func _forceBridgeFromObjectiveC(_ source: NSString, result: inout String?) {
    result = _unconditionallyBridgeFromObjectiveC(source)
  }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSString, result: inout String?) -> Bool {
    result = _unconditionallyBridgeFromObjectiveC(source)
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSString?) -> String {
    guard let s = source, let p = s.utf8String else { return "" }
    return String(cString: p)
  }
}

extension Substring: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSString
  public func _bridgeToObjectiveC() -> NSString { return String(self)._bridgeToObjectiveC() }
  public static func _forceBridgeFromObjectiveC(_ source: NSString, result: inout Substring?) {
    result = Substring(String._unconditionallyBridgeFromObjectiveC(source))
  }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSString, result: inout Substring?) -> Bool {
    result = Substring(String._unconditionallyBridgeFromObjectiveC(source))
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSString?) -> Substring {
    return Substring(String._unconditionallyBridgeFromObjectiveC(source))
  }
}

// ---- collections ----------------------------------------------------------------------

extension Array: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSArray
  public func _bridgeToObjectiveC() -> NSArray {
    let out = NSMutableArray(capacity: count)
    for e in self { out.add(_bridgeAnythingToObjectiveC(e)) }
    return out
  }
  public static func _forceBridgeFromObjectiveC(_ source: NSArray, result: inout [Element]?) {
    guard _conditionallyBridgeFromObjectiveC(source, result: &result) else {
      fatalError("NSArray element failed to match the Swift Array Element type")
    }
  }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSArray, result: inout [Element]?) -> Bool {
    var out: [Element] = []
    out.reserveCapacity(source.count)
    var i = 0
    while i < source.count {
      guard let e = _bridgeElement(source.object(at: i) as AnyObject, as: Element.self) else {
        result = nil
        return false
      }
      out.append(e)
      i += 1
    }
    result = out
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSArray?) -> [Element] {
    guard let s = source else { return [] }
    var result: [Element]?
    _forceBridgeFromObjectiveC(s, result: &result)
    return result!
  }
}

// ---- AnyHashable ----------------------------------------------------------------------
// Bridges to the object of its base value; NSDictionary keys come back as
// AnyHashable this way ([AnyHashable: Any] is how untyped dictionaries import).

extension AnyHashable: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSObject
  public func _bridgeToObjectiveC() -> NSObject {
    return _bridgeAnythingToObjectiveC(base) as! NSObject
  }
  public static func _forceBridgeFromObjectiveC(_ x: NSObject, result: inout AnyHashable?) {
    result = AnyHashable(x)
  }
  public static func _conditionallyBridgeFromObjectiveC(_ x: NSObject, result: inout AnyHashable?) -> Bool {
    result = AnyHashable(x)
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSObject?) -> AnyHashable {
    return AnyHashable(source ?? NSObject())
  }
}

extension Dictionary: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSDictionary
  public func _bridgeToObjectiveC() -> NSDictionary {
    let out = NSMutableDictionary(capacity: count)
    for (k, v) in self {
      out.setObject(_bridgeAnythingToObjectiveC(v), forKey: _bridgeAnythingToObjectiveC(k) as! NSCopying)
    }
    return out
  }
  public static func _forceBridgeFromObjectiveC(_ source: NSDictionary, result: inout [Key: Value]?) {
    guard _conditionallyBridgeFromObjectiveC(source, result: &result) else {
      fatalError("NSDictionary entry failed to match the Swift Dictionary types")
    }
  }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSDictionary, result: inout [Key: Value]?) -> Bool {
    var out: [Key: Value] = [:]
    for k in source.allKeys {
      let ko = k as AnyObject
      guard let key = _bridgeElement(ko, as: Key.self),
            let v = source.object(forKey: k), let value = _bridgeElement(v as AnyObject, as: Value.self) else {
        result = nil
        return false
      }
      out[key] = value
    }
    result = out
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSDictionary?) -> [Key: Value] {
    guard let s = source else { return [:] }
    var result: [Key: Value]?
    _forceBridgeFromObjectiveC(s, result: &result)
    return result!
  }
}

extension Set: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSSet
  public func _bridgeToObjectiveC() -> NSSet {
    let out = NSMutableSet(capacity: count)
    for e in self { out.add(_bridgeAnythingToObjectiveC(e)) }
    return out
  }
  public static func _forceBridgeFromObjectiveC(_ source: NSSet, result: inout Set<Element>?) {
    guard _conditionallyBridgeFromObjectiveC(source, result: &result) else {
      fatalError("NSSet element failed to match the Swift Set Element type")
    }
  }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSSet, result: inout Set<Element>?) -> Bool {
    var out = Set<Element>()
    for o in source.allObjects {
      guard let e = _bridgeElement(o as AnyObject, as: Element.self) else {
        result = nil
        return false
      }
      out.insert(e)
    }
    result = out
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSSet?) -> Set<Element> {
    guard let s = source else { return [] }
    var result: Set<Element>?
    _forceBridgeFromObjectiveC(s, result: &result)
    return result!
  }
}

// ---- numbers and Bool --------------------------------------------------------------------

extension Int: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSNumber
  public func _bridgeToObjectiveC() -> NSNumber { return NSNumber(integer: self) }
  public static func _forceBridgeFromObjectiveC(_ source: NSNumber, result: inout Int?) { result = source.integerValue }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSNumber, result: inout Int?) -> Bool {
    result = source.integerValue
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Int { return source?.integerValue ?? 0 }
}

extension Double: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSNumber
  public func _bridgeToObjectiveC() -> NSNumber { return NSNumber(double: self) }
  public static func _forceBridgeFromObjectiveC(_ source: NSNumber, result: inout Double?) { result = source.doubleValue }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSNumber, result: inout Double?) -> Bool {
    result = source.doubleValue
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Double { return source?.doubleValue ?? 0 }
}

extension Bool: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSNumber
  public func _bridgeToObjectiveC() -> NSNumber { return NSNumber(bool: self) }
  public static func _forceBridgeFromObjectiveC(_ source: NSNumber, result: inout Bool?) { result = source.boolValue }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSNumber, result: inout Bool?) -> Bool {
    result = source.boolValue
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Bool { return source?.boolValue ?? false }
}
