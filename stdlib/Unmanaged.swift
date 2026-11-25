// Unmanaged: a class reference with manual reference counting, for passing
// objects through C contexts. @frozen with one unowned(unsafe) reference, as
// programs inline against it.

@frozen
public struct Unmanaged<Instance: AnyObject> {
  @usableFromInline internal unowned(unsafe) var _value: Instance

  @usableFromInline @_transparent
  internal init(_private: Instance) { _value = _private }

  @_transparent
  public static func fromOpaque(_ value: UnsafeRawPointer) -> Unmanaged {
    return Unmanaged(_private: unsafeBitCast(value, to: Instance.self))
  }
  @_transparent
  public static func fromOpaque(_ value: UnsafeMutableRawPointer) -> Unmanaged {
    return Unmanaged(_private: unsafeBitCast(value, to: Instance.self))
  }
  @_transparent
  public func toOpaque() -> UnsafeMutableRawPointer {
    return unsafeBitCast(_value, to: UnsafeMutableRawPointer.self)
  }
  @_transparent
  public static func passRetained(_ value: Instance) -> Unmanaged {
    return Unmanaged(_private: value).retain()
  }
  @_transparent
  public static func passUnretained(_ value: Instance) -> Unmanaged {
    return Unmanaged(_private: value)
  }
  @_transparent public func takeUnretainedValue() -> Instance { return _value }
  @_transparent
  public func takeRetainedValue() -> Instance {
    let result = _value
    release()
    return result
  }
  @inlinable
  public func _withUnsafeGuaranteedRef<Result>(_ body: (Instance) throws -> Result) rethrows -> Result {
    return try body(_value)
  }
  @_transparent @discardableResult
  public func retain() -> Unmanaged {
    Builtin.retain(_value)
    return self
  }
  @_transparent
  public func release() {
    Builtin.release(_value)
  }
  @_transparent @discardableResult
  public func autorelease() -> Unmanaged {
    Builtin.autorelease(_value)
    return self
  }
}

extension Unmanaged: Equatable {
  @_transparent
  public static func == (lhs: Unmanaged, rhs: Unmanaged) -> Bool {
    return lhs.toOpaque() == rhs.toOpaque()
  }
}
extension Unmanaged: Hashable {
  public func hash(into hasher: inout Hasher) { hasher.combine(toOpaque()) }
}
extension Unmanaged: @unchecked Sendable {}
