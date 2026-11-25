// RawRepresentable: enums with raw values conform to it (the compiler
// synthesizes init?(rawValue:) and rawValue), and so do the structs the
// Clang importer makes from C enums and option sets.

public protocol RawRepresentable<RawValue> {
  associatedtype RawValue
  init?(rawValue: RawValue)
  var rawValue: RawValue { get }
}

@inlinable
public func == <T: RawRepresentable>(lhs: T, rhs: T) -> Bool where T.RawValue: Equatable {
  return lhs.rawValue == rhs.rawValue
}

@inlinable
public func != <T: RawRepresentable>(lhs: T, rhs: T) -> Bool where T.RawValue: Equatable {
  return lhs.rawValue != rhs.rawValue
}

@inlinable
public func != <T: Equatable>(lhs: T, rhs: T) -> Bool where T: RawRepresentable, T.RawValue: Equatable {
  return lhs.rawValue != rhs.rawValue
}

extension RawRepresentable where RawValue: Hashable, Self: Hashable {
  @inlinable
  public var hashValue: Int {
    return rawValue.hashValue
  }

  @inlinable
  public func hash(into hasher: inout Hasher) {
    hasher.combine(rawValue)
  }

  @inlinable
  public func _rawHashValue(seed: Int) -> Int {
    return rawValue._rawHashValue(seed: seed)
  }
}
