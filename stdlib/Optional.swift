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
