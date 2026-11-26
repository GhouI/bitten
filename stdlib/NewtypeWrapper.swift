// _SwiftNewtypeWrapper: what the importer makes C string-constant types
// (NS_TYPED_EXTENSIBLE_ENUM: NSNotification.Name, RunLoop.Mode, ...)
// conform to. Its extensions give them hashing, AnyHashable behaviour and
// Objective-C bridging through their raw value.

public protocol _SwiftNewtypeWrapper: RawRepresentable, _HasCustomAnyHashableRepresentation {}

extension _SwiftNewtypeWrapper where Self: Hashable, Self.RawValue: Hashable {
  public var hashValue: Int { return rawValue.hashValue }
  public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }
  public func _rawHashValue(seed: Int) -> Int { return rawValue._rawHashValue(seed: seed) }
}

extension _SwiftNewtypeWrapper {
  public __consuming func _toCustomAnyHashable() -> AnyHashable? { return nil }
}

extension _SwiftNewtypeWrapper where Self: Hashable, Self.RawValue: Hashable {
  /// Hashes and compares as its raw value (so a name equals the string it
  /// wraps), and unboxes as either.
  public __consuming func _toCustomAnyHashable() -> AnyHashable? {
    var h = AnyHashable(_usingDefaultRepresentationOf: rawValue)
    h._box = _NewtypeWrapperAnyHashableBox(self)
    return h
  }
}

internal struct _NewtypeWrapperAnyHashableBox<Base>: _AnyHashableBox
where Base: _SwiftNewtypeWrapper & Hashable, Base.RawValue: Hashable {
  var _value: Base
  init(_ value: Base) { _value = value }

  var _canonicalBox: _AnyHashableBox { return AnyHashable(_value.rawValue)._box._canonicalBox }
  func _isEqual(to other: _AnyHashableBox) -> Bool? { return _canonicalBox._isEqual(to: other) }
  var _hashValue: Int { return _canonicalBox._hashValue }
  func _hash(into hasher: inout Hasher) { _canonicalBox._hash(into: &hasher) }
  func _rawHashValue(_seed: Int) -> Int { return _canonicalBox._rawHashValue(_seed: _seed) }
  var _base: Any { return _value }
  func _unbox<T: Hashable>() -> T? { return (_value as Any) as? T ?? (_value.rawValue as Any) as? T }
}

extension _SwiftNewtypeWrapper where Self.RawValue: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = Self.RawValue._ObjectiveCType

  public func _bridgeToObjectiveC() -> Self.RawValue._ObjectiveCType { return rawValue._bridgeToObjectiveC() }

  public static func _forceBridgeFromObjectiveC(_ source: Self.RawValue._ObjectiveCType, result: inout Self?) {
    var inner: Self.RawValue?
    Self.RawValue._forceBridgeFromObjectiveC(source, result: &inner)
    result = inner.flatMap { Self(rawValue: $0) }
  }

  public static func _conditionallyBridgeFromObjectiveC(_ source: Self.RawValue._ObjectiveCType,
                                                        result: inout Self?) -> Bool {
    var inner: Self.RawValue?
    let ok = Self.RawValue._conditionallyBridgeFromObjectiveC(source, result: &inner)
    result = inner.flatMap { Self(rawValue: $0) }
    return ok
  }

  public static func _unconditionallyBridgeFromObjectiveC(_ source: Self.RawValue._ObjectiveCType?) -> Self {
    return Self(rawValue: Self.RawValue._unconditionallyBridgeFromObjectiveC(source))!
  }
}

extension _SwiftNewtypeWrapper where Self.RawValue: AnyObject {
  public func _bridgeToObjectiveC() -> Self.RawValue { return rawValue }

  public static func _forceBridgeFromObjectiveC(_ source: Self.RawValue, result: inout Self?) {
    result = Self(rawValue: source)
  }

  public static func _conditionallyBridgeFromObjectiveC(_ source: Self.RawValue, result: inout Self?) -> Bool {
    result = Self(rawValue: source)
    return result != nil
  }

  public static func _unconditionallyBridgeFromObjectiveC(_ source: Self.RawValue?) -> Self {
    return Self(rawValue: source!)!
  }
}
