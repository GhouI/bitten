// AnyHashable: a type-erased Hashable value. Its layout is @frozen as one
// existential of the internal box protocol (40 bytes): the box holds the
// value inline or boxed, and its witness table does the hashing and the
// comparison, which needs dynamic casts to find out whether the other side
// holds the same type.
//
// Not yet: the numeric canonicalization that makes AnyHashable(1 as Int8)
// equal AnyHashable(1), boxing class instances as their Hashable base class
// (equality already looks both ways, so this only shows in the box type),
// and description (needs String).

public protocol _HasCustomAnyHashableRepresentation {
  __consuming func _toCustomAnyHashable() -> AnyHashable?
}

@usableFromInline
internal protocol _AnyHashableBox {
  var _canonicalBox: _AnyHashableBox { get }
  /// nil when the other box does not hold a value of this box's type.
  func _isEqual(to box: _AnyHashableBox) -> Bool?
  var _hashValue: Int { get }
  func _hash(into hasher: inout Hasher)
  func _rawHashValue(_seed: Int) -> Int
  var _base: Any { get }
  func _unbox<T: Hashable>() -> T?
}

extension _AnyHashableBox {
  internal var _canonicalBox: _AnyHashableBox { return self }
}

internal struct _ConcreteHashableBox<Base: Hashable>: _AnyHashableBox {
  internal var _baseHashable: Base

  internal init(_ base: Base) { _baseHashable = base }

  internal func _unbox<T: Hashable>() -> T? {
    return (_baseHashable as Any) as? T
  }
  internal func _isEqual(to rhs: _AnyHashableBox) -> Bool? {
    if case .some(let other) = rhs._unbox() as Base? {
      return _baseHashable == other
    }
    return nil
  }
  internal var _hashValue: Int { return _baseHashable.hashValue }
  internal func _hash(into hasher: inout Hasher) { _baseHashable.hash(into: &hasher) }
  internal func _rawHashValue(_seed: Int) -> Int { return _baseHashable._rawHashValue(seed: _seed) }
  internal var _base: Any { return _baseHashable }
}

@frozen public struct AnyHashable {
  internal var _box: _AnyHashableBox

  public init<H: Hashable>(_ base: H) {
    // A value may choose how it is wrapped (an AnyHashable wraps as itself).
    if case .some(let custom) = (base as Any) as? _HasCustomAnyHashableRepresentation,
       case .some(let wrapped) = custom._toCustomAnyHashable() {
      self = wrapped
      return
    }
    // An Optional holding a value is that value: AnyHashable(Optional(5))
    // equals AnyHashable(5).
    if case .some(let optional) = H.self as? _AnyHashableOptional.Type,
       case .some(let unwrapped) = optional._anyHashable(unwrapping: base) {
      self = unwrapped
      return
    }
    _box = _ConcreteHashableBox(base)
  }

  internal init<H: Hashable>(_usingDefaultRepresentationOf base: H) {
    _box = _ConcreteHashableBox(base)
  }

  public var base: Any { return _box._base }
}

extension AnyHashable: Equatable {
  public static func == (lhs: AnyHashable, rhs: AnyHashable) -> Bool {
    let l = lhs._box._canonicalBox, r = rhs._box._canonicalBox
    if case .some(let result) = l._isEqual(to: r) { return result }
    // A subclass on the left: try from the other side.
    if case .some(let result) = r._isEqual(to: l) { return result }
    return false
  }
}

extension AnyHashable: Hashable {
  public var hashValue: Int { return _box._canonicalBox._hashValue }
  public func hash(into hasher: inout Hasher) { _box._canonicalBox._hash(into: &hasher) }
  public func _rawHashValue(seed: Int) -> Int { return _box._canonicalBox._rawHashValue(_seed: seed) }
}

extension AnyHashable: _HasCustomAnyHashableRepresentation {
  @_alwaysEmitIntoClient
  public __consuming func _toCustomAnyHashable() -> AnyHashable? { return self }
}

internal protocol _AnyHashableOptional {
  /// The AnyHashable of the wrapped value, or nil for .none.
  static func _anyHashable(unwrapping value: Any) -> AnyHashable?
}
extension Optional: _AnyHashableOptional where Wrapped: Hashable {
  internal static func _anyHashable(unwrapping value: Any) -> AnyHashable? {
    if case .some(.some(let wrapped)) = value as? Optional<Wrapped> {
      return AnyHashable(wrapped)
    }
    return nil
  }
}

// The compiler converts a Hashable value to AnyHashable through this.
@inlinable
public func _convertToAnyHashable<H: Hashable>(_ value: H) -> AnyHashable {
  return AnyHashable(value)
}

// Called by the runtime's dynamic casts (casts.c) for `x as AnyHashable`
// and `anyHashable as? T`.
@_silgen_name("_swift_convertToAnyHashableIndirect")
public func _convertToAnyHashableIndirect<H: Hashable>(_ value: H, _ target: UnsafeMutablePointer<AnyHashable>) {
  target.initialize(to: AnyHashable(value))
}

@_silgen_name("_swift_anyHashableDownCastConditionalIndirect")
public func _anyHashableDownCastConditionalIndirect<T>(_ value: UnsafePointer<AnyHashable>,
                                                       _ target: UnsafeMutablePointer<T>) -> Bool {
  guard let t = value.pointee.base as? T else { return false }
  target.initialize(to: t)
  return true
}
