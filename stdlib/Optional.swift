// Optional. Its layout (payload, then the tag in extra inhabitants or a
// trailing byte) is decided by the compiler from this declaration.

@frozen public enum Optional<Wrapped: ~Copyable>: ~Copyable {
  case none
  case some(Wrapped)
}
extension Optional: Copyable where Wrapped: Copyable {}
extension Optional: Sendable where Wrapped: ~Copyable & Sendable {}

extension Optional: ExpressibleByNilLiteral where Wrapped: ~Copyable {
  @_transparent public init(nilLiteral: ()) { self = .none }
}
extension Optional where Wrapped: ~Copyable {
  @_transparent public init(_ some: consuming Wrapped) { self = .some(some) }
}

extension Optional: Equatable where Wrapped: Equatable {
  @inlinable public static func == (lhs: Wrapped?, rhs: Wrapped?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?): return l == r
    case (nil, nil): return true
    default: return false
    }
  }
}

@_transparent
public func ?? <T>(optional: T?, defaultValue: @autoclosure () throws -> T) rethrows -> T {
  switch optional {
  case .some(let value): return value
  case .none: return try defaultValue()
  }
}

extension Optional {
  @inlinable
  public func map<U>(_ transform: (Wrapped) throws -> U) rethrows -> U? {
    switch self {
    case .some(let y): return .some(try transform(y))
    case .none: return .none
    }
  }
  @inlinable
  public func flatMap<U>(_ transform: (Wrapped) throws -> U?) rethrows -> U? {
    switch self {
    case .some(let y): return try transform(y)
    case .none: return .none
    }
  }
  @inlinable public var unsafelyUnwrapped: Wrapped {
    switch self {
    case .some(let x): return x
    case .none: Builtin.int_trap()
    }
  }
}

// ---- comparison with nil --------------------------------------------------------
// `x == nil` and `x != nil` for any Optional, Equatable or not: nil converts
// to this type, which has the operators.

@frozen
public struct _OptionalNilComparisonType: ExpressibleByNilLiteral {
  @_transparent public init(nilLiteral: ()) {}
}

extension Optional {
  @_transparent
  public static func ~= (lhs: _OptionalNilComparisonType, rhs: Wrapped?) -> Bool {
    switch rhs {
    case .some: return false
    case .none: return true
    }
  }

  @_transparent
  public static func == (lhs: Wrapped?, rhs: _OptionalNilComparisonType) -> Bool {
    switch lhs {
    case .some: return false
    case .none: return true
    }
  }

  @_transparent
  public static func != (lhs: Wrapped?, rhs: _OptionalNilComparisonType) -> Bool {
    switch lhs {
    case .some: return true
    case .none: return false
    }
  }

  @_transparent
  public static func == (lhs: _OptionalNilComparisonType, rhs: Wrapped?) -> Bool {
    switch rhs {
    case .some: return false
    case .none: return true
    }
  }

  @_transparent
  public static func != (lhs: _OptionalNilComparisonType, rhs: Wrapped?) -> Bool {
    switch rhs {
    case .some: return true
    case .none: return false
    }
  }
}
