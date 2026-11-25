// The Swift overlay of the Objective-C runtime (libswiftObjectiveC.dylib):
// ObjCBool and Selector, which the compiler maps BOOL and SEL to, the
// conversions it calls by name, and NSObject's Equatable and Hashable
// conformances through -isEqual: and -hash.
@_exported import ObjectiveC

// ---- ObjCBool ---------------------------------------------------------------

/// The Objective-C BOOL type. On x86-64 macOS BOOL is a signed char, so
/// this is a one-byte integer; in function signatures the compiler bridges
/// it to Bool.
@frozen
public struct ObjCBool: ExpressibleByBooleanLiteral, Sendable {
  @usableFromInline var _value: Int8

  @_transparent
  public init(_ value: Bool) {
    self._value = value ? 1 : 0
  }

  /// The value as a Bool.
  public var boolValue: Bool {
    @_transparent get { return _value != 0 }
  }

  @_transparent
  public init(booleanLiteral value: Bool) {
    self.init(value)
  }
}

@_transparent
public func _convertBoolToObjCBool(_ x: Bool) -> ObjCBool {
  return ObjCBool(x)
}

@_transparent
public func _convertObjCBoolToBool(_ x: ObjCBool) -> Bool {
  return x.boolValue
}

// ---- Selector ---------------------------------------------------------------

/// An Objective-C selector (SEL): a registered method name.
@frozen
public struct Selector: Sendable {
  var ptr: OpaquePointer

  /// The selector registered for a C string.
  public init(_cString name: UnsafePointer<CChar>) {
    self = sel_registerName(name)
  }
}

extension Selector: Equatable, Hashable {
  public static func == (lhs: Selector, rhs: Selector) -> Bool {
    return lhs.ptr == rhs.ptr
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(ptr)
  }
}

// ---- NSZone -----------------------------------------------------------------

@frozen
public struct NSZone {
  var pointer: OpaquePointer
}

// ---- NSObject ---------------------------------------------------------------

extension NSObject: Equatable, Hashable {
  /// Objects are equal when -isEqual: says so.
  public static func == (lhs: NSObject, rhs: NSObject) -> Bool {
    return lhs.isEqual(rhs)
  }

  /// The object's -hash.
  @nonobjc
  open var hashValue: Int {
    return hash
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(hashValue)
  }

  public func _rawHashValue(seed: Int) -> Int {
    return self.hash._rawHashValue(seed: seed)
  }
}
