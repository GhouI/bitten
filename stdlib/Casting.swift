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

/// The dynamic type of a value. The type checker resolves every call to
/// this function itself; the declaration only has to exist.
@_transparent
@_semantics("typechecker.type(of:)")
public func type<T, Metatype>(of value: T) -> Metatype {
  Builtin.unreachable()
}

/// Calls `body` with the value inside an existential (or the type inside
/// an existential metatype) as its own static type. Resolved by the type
/// checker, like type(of:).
@_transparent
@_semantics("typechecker._openExistential(_:do:)")
public func _openExistential<ExistentialType, ContainedType, ResultType>(
  _ existential: ExistentialType,
  do body: (_ escapingClosure: ContainedType) throws -> ResultType
) rethrows -> ResultType {
  Builtin.unreachable()
}

// Metatype identity (`T.self == Int.self`).
@inlinable
public func == (t0: Any.Type?, t1: Any.Type?) -> Bool {
  switch (t0, t1) {
  case (.none, .none): return true
  case let (.some(a), .some(b)): return Bool(Builtin.is_same_metatype(a, b))
  default: return false
  }
}
@inlinable
public func != (t0: Any.Type?, t1: Any.Type?) -> Bool { return !(t0 == t1) }

// `#available` checks: whether the running system is at least the given
// macOS version. bitten presents itself as macOS 15.0, the same answer as
// libSystem's __isOSVersionAtLeast gives C code.
@_silgen_name("__isOSVersionAtLeast")
internal func _bitten_isOSVersionAtLeast(_ major: Int32, _ minor: Int32, _ patch: Int32) -> Int32

@_semantics("availability.osversion")
public func _stdlib_isOSVersionAtLeast(_ major: Builtin.Word, _ minor: Builtin.Word, _ patch: Builtin.Word) -> Builtin.Int1 {
  let ok = _bitten_isOSVersionAtLeast(Int32(truncatingIfNeeded: Int(major)), Int32(truncatingIfNeeded: Int(minor)),
                                      Int32(truncatingIfNeeded: Int(patch))) != 0
  return ok._value
}
