// Continuations: suspending a task until other code resumes it.
//
// Builtin.withUnsafeContinuation parks the current task in a continuation
// context in its own frame (swift_continuation_init) and suspends
// (swift_continuation_await); the raw continuation is the task itself.
// Resuming stores the value through the context and reschedules the task
// on the executor it suspended on (swift_continuation_resume*).

import Swift

@frozen
public struct UnsafeContinuation<T, E: Error>: Sendable {
  @usableFromInline
  internal var context: Builtin.RawUnsafeContinuation

  @_alwaysEmitIntoClient
  internal init(_ context: Builtin.RawUnsafeContinuation) {
    self.context = context
  }

  @_alwaysEmitIntoClient
  public func resume(returning value: sending T) where E == Never {
    Builtin.resumeNonThrowingContinuationReturning(context, value)
  }

  @_alwaysEmitIntoClient
  public func resume(returning value: sending T) {
    Builtin.resumeThrowingContinuationReturning(context, value)
  }

  @_alwaysEmitIntoClient
  public func resume(throwing error: consuming E) {
    Builtin.resumeThrowingContinuationThrowing(context, error)
  }
}

extension UnsafeContinuation {
  @_alwaysEmitIntoClient
  public func resume<Er: Error>(with result: __shared sending Result<T, Er>) where E == any Error {
    switch result {
    case .success(let val): self.resume(returning: val)
    case .failure(let err): self.resume(throwing: err)
    }
  }

  @_alwaysEmitIntoClient
  public func resume(with result: __shared sending Result<T, E>) {
    switch result {
    case .success(let val): self.resume(returning: val)
    case .failure(let err): self.resume(throwing: err)
    }
  }

  @_alwaysEmitIntoClient
  public func resume() where T == () {
    self.resume(returning: ())
  }
}

@available(*, deprecated, message: "please use UnsafeContinuation<..., Error>")
public typealias UnsafeThrowingContinuation<T> = UnsafeContinuation<T, any Error>

@_alwaysEmitIntoClient
public func withUnsafeContinuation<T>(
  isolation: isolated (any Actor)? = #isolation,
  _ fn: (UnsafeContinuation<T, Never>) -> Void
) async -> sending T {
  return await Builtin.withUnsafeContinuation {
    fn(UnsafeContinuation<T, Never>($0))
  }
}

@_alwaysEmitIntoClient
public func withUnsafeThrowingContinuation<T>(
  isolation: isolated (any Actor)? = #isolation,
  _ fn: (UnsafeContinuation<T, any Error>) -> Void
) async throws -> sending T {
  return try await Builtin.withUnsafeThrowingContinuation {
    fn(UnsafeContinuation<T, Error>($0))
  }
}

/// Its presence tells the compiler that the runtime has
/// swift_continuation_await (rather than the older inline protocol).
@_alwaysEmitIntoClient
public func _abiEnableAwaitContinuation() {
  Builtin.int_trap()
}

// ---- checked continuations ---------------------------------------------------------------

/// Owns the raw continuation of a CheckedContinuation. The runtime keeps
/// the task pointer in a cell that is taken exactly once; a second resume
/// is reported, and so is a continuation dropped without being resumed.
internal final class CheckedContinuationCanary: @unchecked Sendable {
  internal let cell: Builtin.RawPointer

  internal init(_ continuation: Builtin.RawUnsafeContinuation) {
    cell = _bitten_continuationCellCreate(continuation)
  }

  internal func take() -> Builtin.RawUnsafeContinuation {
    return _bitten_continuationCellTake(cell)
  }

  deinit {
    _bitten_continuationCellDestroy(cell)
  }
}

@_silgen_name("swift_bitten_continuationCellCreate")
internal func _bitten_continuationCellCreate(_ c: Builtin.RawUnsafeContinuation) -> Builtin.RawPointer
@_silgen_name("swift_bitten_continuationCellTake")
internal func _bitten_continuationCellTake(_ cell: Builtin.RawPointer) -> Builtin.RawUnsafeContinuation
@_silgen_name("swift_bitten_continuationCellDestroy")
internal func _bitten_continuationCellDestroy(_ cell: Builtin.RawPointer)

public struct CheckedContinuation<T, E: Error>: Sendable {
  private let canary: CheckedContinuationCanary

  public init(continuation: UnsafeContinuation<T, E>, function: String = #function) {
    canary = CheckedContinuationCanary(continuation.context)
  }

  public func resume(returning value: sending T) {
    Builtin.resumeThrowingContinuationReturning(canary.take(), value)
  }

  public func resume(throwing error: __owned E) {
    Builtin.resumeThrowingContinuationThrowing(canary.take(), error)
  }
}

extension CheckedContinuation {
  @_alwaysEmitIntoClient
  public func resume<Er: Error>(with result: __shared sending Result<T, Er>) where E == any Error {
    switch result {
    case .success(let val): self.resume(returning: val)
    case .failure(let err): self.resume(throwing: err)
    }
  }

  @_alwaysEmitIntoClient
  public func resume(with result: __shared sending Result<T, E>) {
    switch result {
    case .success(let val): self.resume(returning: val)
    case .failure(let err): self.resume(throwing: err)
    }
  }

  @_alwaysEmitIntoClient
  public func resume() where T == () {
    self.resume(returning: ())
  }
}

@inlinable
public func withCheckedContinuation<T>(
  isolation: isolated (any Actor)? = #isolation,
  _ body: (CheckedContinuation<T, Never>) -> Void
) async -> sending T {
  return await Builtin.withUnsafeContinuation {
    body(CheckedContinuation(continuation: UnsafeContinuation<T, Never>($0)))
  }
}

@inlinable
public func withCheckedThrowingContinuation<T>(
  isolation: isolated (any Actor)? = #isolation,
  _ body: (CheckedContinuation<T, any Error>) -> Void
) async throws -> sending T {
  return try await Builtin.withUnsafeThrowingContinuation {
    body(CheckedContinuation(continuation: UnsafeContinuation<T, Error>($0)))
  }
}
