// Unchecked conversions and lifetime helpers.

@_transparent
public func unsafeBitCast<T, U>(_ x: T, to type: U.Type) -> U {
  if MemoryLayout<T>.size != MemoryLayout<U>.size { Builtin.int_trap() }
  return Builtin.reinterpretCast(x)
}

@_transparent
public func unsafeDowncast<T: AnyObject>(_ x: AnyObject, to type: T.Type) -> T {
  return Builtin.castReference(x)
}

@_transparent
public func numericCast<T: BinaryInteger, U: BinaryInteger>(_ x: T) -> U {
  return U(x)
}

@inlinable
public func withExtendedLifetime<T, Result>(_ x: borrowing T, _ body: () throws -> Result) rethrows -> Result {
  defer { _fixLifetime(x) }
  return try body()
}
@inlinable
public func withExtendedLifetime<T, Result>(_ x: borrowing T, _ body: (borrowing T) throws -> Result) rethrows -> Result {
  defer { _fixLifetime(x) }
  return try body(x)
}

@_transparent
public func _fixLifetime<T>(_ x: borrowing T) {
  Builtin.fixLifetime(x)
}
