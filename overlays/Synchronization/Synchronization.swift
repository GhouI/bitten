// Synchronization: Mutex and Atomic. These types are @frozen and their
// operations are inlined into programs, so only the type metadata lives
// here; the stored layouts are the ones Apple declares (a raw-layout
// _Cell holding the value, an os_unfair_lock for the mutex).

import Builtin
import os

// ---- _Cell: storage with a stable address, laid out like Value ----------

@frozen
@usableFromInline
@_rawLayout(like: Value, movesAsLike)
internal struct _Cell<Value: ~Copyable>: ~Copyable {
  @_alwaysEmitIntoClient @_transparent
  internal var _rawAddress: Builtin.RawPointer {
    Builtin.addressOfRawLayout(self)
  }

  @_alwaysEmitIntoClient @_transparent
  internal init(_ initialValue: consuming Value) {
    Builtin.initialize(initialValue, Builtin.addressOfRawLayout(self))
  }

  @_alwaysEmitIntoClient @inlinable
  deinit {
    Builtin.destroy(Value.self, _rawAddress)
  }
}

extension _Cell where Value: Copyable {
  @_alwaysEmitIntoClient @_transparent
  internal var _address: UnsafeMutablePointer<Value> {
    UnsafeMutablePointer<Value>(_rawAddress)
  }
}

// ---- Mutex -------------------------------------------------------------------

@frozen
@usableFromInline
@_staticExclusiveOnly
internal struct _MutexHandle: ~Copyable {
  @usableFromInline
  let value: _Cell<os_unfair_lock>

  @_alwaysEmitIntoClient @_transparent
  init() { value = _Cell(os_unfair_lock()) }

  @_alwaysEmitIntoClient @_transparent
  internal borrowing func _lock() { os_unfair_lock_lock(value._address) }

  @_alwaysEmitIntoClient @_transparent
  internal borrowing func _tryLock() -> Bool { os_unfair_lock_trylock(value._address) }

  @_alwaysEmitIntoClient @_transparent
  internal borrowing func _unlock() { os_unfair_lock_unlock(value._address) }
}

@frozen
@_staticExclusiveOnly
public struct Mutex<Value: ~Copyable>: ~Copyable {
  @usableFromInline
  let handle: _MutexHandle

  @usableFromInline
  let value: _Cell<Value>

  @_alwaysEmitIntoClient @_transparent
  public init(_ initialValue: consuming sending Value) {
    value = _Cell(initialValue)
    handle = _MutexHandle()
  }
}

extension Mutex: @unchecked Sendable where Value: ~Copyable {}

// (Apple's withLock takes any Value; this stdlib's pointers need Copyable
// pointees. Programs built against Apple's SDK inline Apple's version.)
extension Mutex {
  @_alwaysEmitIntoClient @_transparent
  public borrowing func withLock<Result: ~Copyable, E: Error>(
    _ body: (inout sending Value) throws(E) -> sending Result
  ) throws(E) -> sending Result {
    handle._lock()
    defer { handle._unlock() }
    return try body(&value._address.pointee)
  }

  @_alwaysEmitIntoClient @_transparent
  public borrowing func withLockIfAvailable<Result: ~Copyable, E: Error>(
    _ body: (inout sending Value) throws(E) -> sending Result
  ) throws(E) -> sending Result? {
    guard handle._tryLock() else { return nil }
    defer { handle._unlock() }
    return try body(&value._address.pointee)
  }
}

// ---- Atomic --------------------------------------------------------------------

public protocol AtomicRepresentable {
  associatedtype AtomicRepresentation: BitwiseCopyable
  static func encodeAtomicRepresentation(_ value: consuming Self) -> AtomicRepresentation
  static func decodeAtomicRepresentation(_ storage: consuming AtomicRepresentation) -> Self
}

@frozen
@_rawLayout(like: Value.AtomicRepresentation)
@_staticExclusiveOnly
public struct Atomic<Value: AtomicRepresentable>: ~Copyable {
  @_alwaysEmitIntoClient @_transparent
  var _rawAddress: Builtin.RawPointer { Builtin.addressOfRawLayout(self) }

  @_alwaysEmitIntoClient @_transparent
  public init(_ initialValue: consuming Value) {
    Builtin.initialize(Value.encodeAtomicRepresentation(initialValue), Builtin.addressOfRawLayout(self))
  }
}

extension Atomic: @unchecked Sendable where Value: Sendable {}
