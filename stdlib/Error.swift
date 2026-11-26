// Error and Result: what `throws` needs from the standard library.
//
// The error existential (`any Error`) is a single reference to a box made
// by the runtime (swift_allocError, src/frameworks/swift/errors.c), which
// the compiler knows by this protocol. The requirements spelled in String
// (`_domain`) come with String; the remaining ones have defaults, as on
// macOS, so conforming types write nothing. The requirements are Apple's,
// in Apple's order: programs send their witnesses keyed by them.

public protocol Error: Sendable {
  var _domain: String { get }
  var _code: Int { get }
  var _userInfo: AnyObject? { get }
  func _getEmbeddedNSError() -> AnyObject?
}

extension Error {
  public var _domain: String { return String(reflecting: type(of: self)) }
  public var _code: Int { return 1 }
  public var _userInfo: AnyObject? { return nil }
  public func _getEmbeddedNSError() -> AnyObject? { return nil }
}

/// The NSError an error wraps, if it is one (Foundation's errors are).
public func _getErrorEmbeddedNSError<T: Error>(_ x: T) -> AnyObject? {
  return x._getEmbeddedNSError()
}

// Entry points the compiler calls: `try!` on an error, and an error thrown
// out of a top-level `main`. Both report and trap (errors.c).
@_silgen_name("swift_unexpectedError")
public func _unexpectedError(_ error: __owned any Error, filenameStart: Builtin.RawPointer,
                             filenameLength: Builtin.Word, filenameIsASCII: Builtin.Int1,
                             line: Builtin.Word)

@_silgen_name("swift_errorInMain")
public func _errorInMain(_ error: any Error)

@_silgen_name("swift_willThrowTypedImpl")
@usableFromInline
internal func _willThrowTypedImpl<E: Error>(_ error: E)

@_silgen_name("swift_willThrowTyped")
@inlinable @_alwaysEmitIntoClient
public func _willThrowTyped<E: Error>(_ error: E) {
  _willThrowTypedImpl(error)
}

@_alwaysEmitIntoClient
public func _unexpectedErrorTyped<E: Error>(_ error: __owned E, filenameStart: Builtin.RawPointer,
                                            filenameLength: Builtin.Word,
                                            filenameIsASCII: Builtin.Int1, line: Builtin.Word) {
  _unexpectedError(error, filenameStart: filenameStart, filenameLength: filenameLength,
                   filenameIsASCII: filenameIsASCII, line: line)
}

@_alwaysEmitIntoClient
public func _errorInMainTyped<Failure: Error>(_ error: Failure) -> Never {
  _errorInMain(error)
  Builtin.int_trap()
}

extension Never: Error {}

/// A value that represents either a success or a failure, including an
/// associated value in each case.
@frozen
public enum Result<Success, Failure: Error> {
  case success(Success)
  case failure(Failure)

  public func map<NewSuccess>(_ transform: (Success) -> NewSuccess) -> Result<NewSuccess, Failure> {
    switch self {
    case let .success(success): return .success(transform(success))
    case let .failure(failure): return .failure(failure)
    }
  }

  public func mapError<NewFailure>(_ transform: (Failure) -> NewFailure) -> Result<Success, NewFailure> {
    switch self {
    case let .success(success): return .success(success)
    case let .failure(failure): return .failure(transform(failure))
    }
  }

  public func flatMap<NewSuccess>(_ transform: (Success) -> Result<NewSuccess, Failure>) -> Result<NewSuccess, Failure> {
    switch self {
    case let .success(success): return transform(success)
    case let .failure(failure): return .failure(failure)
    }
  }

  public func get() throws(Failure) -> Success {
    switch self {
    case let .success(success): return success
    case let .failure(failure): throw failure
    }
  }
}

extension Result where Failure == any Error {
  public init(catching body: () throws -> Success) {
    do {
      self = .success(try body())
    } catch {
      self = .failure(error)
    }
  }
}

extension Result: Sendable where Success: Sendable {}
extension Result: Equatable where Success: Equatable, Failure: Equatable {}
extension Result: Hashable where Success: Hashable, Failure: Hashable {}
