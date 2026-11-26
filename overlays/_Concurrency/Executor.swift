// Actors, executors and jobs.
//
// An executor reference (Builtin.Executor, two words) is {identity,
// implementation}: identity nil is the global concurrent ("generic")
// executor; implementation 0 with an identity is a default actor (the
// runtime keeps its queue inside the object); otherwise the implementation
// is the SerialExecutor witness table of the identity object. The runtime
// (src/frameworks/concurrency) runs and enqueues jobs; this file is the
// Swift face of it.

import Swift

public protocol Actor: AnyObject, Sendable {
  nonisolated var unownedExecutor: UnownedSerialExecutor { get }
}

@_silgen_name("swift_defaultActor_initialize")
public func _defaultActorInitialize(_ actor: AnyObject)

@_silgen_name("swift_defaultActor_destroy")
public func _defaultActorDestroy(_ actor: AnyObject)

@_silgen_name("swift_task_enqueueMainExecutor")
@usableFromInline
internal func _enqueueOnMain(_ job: UnownedJob)

@freestanding(expression) public macro isolation<T>() -> T = Builtin.IsolationMacro

@_alwaysEmitIntoClient
public func extractIsolation<each Arg, Result>(
  _ fn: @escaping @isolated(any) (repeat each Arg) async throws -> Result
) -> (any Actor)? {
  return Builtin.extractFunctionIsolation(fn)
}

public protocol Executor: AnyObject, Sendable {
  func enqueue(_ job: UnownedJob)
  func enqueue(_ job: consuming Job)
  func enqueue(_ job: consuming ExecutorJob)
}

public protocol SerialExecutor: Executor {
  @_nonoverride func enqueue(_ job: UnownedJob)
  @_nonoverride func enqueue(_ job: consuming Job)
  @_nonoverride func enqueue(_ job: consuming ExecutorJob)
  func asUnownedSerialExecutor() -> UnownedSerialExecutor
  func isSameExclusiveExecutionContext(other: Self) -> Bool
  func checkIsolated()
}

public protocol TaskExecutor: Executor {
  @_nonoverride func enqueue(_ job: UnownedJob)
  @_nonoverride func enqueue(_ job: consuming Job)
  @_nonoverride func enqueue(_ job: consuming ExecutorJob)
  func asUnownedTaskExecutor() -> UnownedTaskExecutor
}

// Each enqueue forwards to the next form, so implementing any one of them
// is enough.
extension Executor {
  public func enqueue(_ job: UnownedJob) {
    self.enqueue(ExecutorJob(job))
  }
  public func enqueue(_ job: consuming ExecutorJob) {
    self.enqueue(Job(job))
  }
  public func enqueue(_ job: consuming Job) {
    self.enqueue(UnownedJob(job))
  }
}

extension SerialExecutor {
  public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
    return UnownedSerialExecutor(ordinary: self)
  }
  public func isSameExclusiveExecutionContext(other: Self) -> Bool {
    return self === other
  }
  public func checkIsolated() {
    _bitten_concurrencyFailure(_isolationFailureMessage)
  }
}

extension TaskExecutor {
  public func asUnownedTaskExecutor() -> UnownedTaskExecutor {
    return UnownedTaskExecutor(ordinary: self)
  }
}

@frozen
public struct UnownedSerialExecutor: Sendable {
  @usableFromInline
  internal var executor: Builtin.Executor

  public var _executor: Builtin.Executor { return executor }

  @inlinable
  public init(_ executor: Builtin.Executor) {
    self.executor = executor
  }

  @inlinable
  public init<E: SerialExecutor>(ordinary executor: __shared E) {
    self.executor = Builtin.buildOrdinarySerialExecutorRef(executor)
  }

  @inlinable
  public init<E: SerialExecutor>(complexEquality executor: __shared E) {
    self.executor = Builtin.buildComplexEqualitySerialExecutorRef(executor)
  }

  public var _isComplexEquality: Bool {
    return _executor_isComplexEquality(self)
  }
}

@frozen
public struct UnownedTaskExecutor: Sendable {
  @usableFromInline
  internal var executor: Builtin.Executor

  public var _executor: Builtin.Executor { return executor }

  @inlinable
  public init(_ executor: Builtin.Executor) {
    self.executor = executor
  }

  @inlinable
  public init<E: TaskExecutor>(ordinary executor: __shared E) {
    self.executor = Builtin.buildOrdinaryTaskExecutorRef(executor)
  }
}

@_silgen_name("swift_task_isOnExecutor")
public func _taskIsOnExecutor<Executor: SerialExecutor>(_ executor: Executor) -> Bool

@_silgen_name("swift_executor_isComplexEquality")
public func _executor_isComplexEquality(_ executor: UnownedSerialExecutor) -> Bool

@_transparent
public func _checkExpectedExecutor(_filenameStart: Builtin.RawPointer,
                                   _filenameLength: Builtin.Word,
                                   _filenameIsASCII: Builtin.Int1,
                                   _line: Builtin.Word,
                                   _executor: Builtin.Executor) {
  if _taskIsCurrentExecutor(_executor) {
    return
  }
  _reportUnexpectedExecutor(_filenameStart, _filenameLength, _filenameIsASCII, _line, _executor)
}

@usableFromInline
@_silgen_name("swift_task_isCurrentExecutor")
internal func _taskIsCurrentExecutor(_ executor: Builtin.Executor) -> Bool

@usableFromInline
@_silgen_name("swift_task_reportUnexpectedExecutor")
internal func _reportUnexpectedExecutor(_ _filenameStart: Builtin.RawPointer,
                                        _ _filenameLength: Builtin.Word,
                                        _ _filenameIsASCII: Builtin.Int1,
                                        _ _line: Builtin.Word,
                                        _ _executor: Builtin.Executor)

@_silgen_name("swift_task_checkIsolated")
@usableFromInline
internal func _taskCheckIsolated(_ executor: Builtin.Executor)

@_silgen_name("swift_task_getMainExecutor")
@usableFromInline
internal func _getMainExecutor() -> Builtin.Executor

@usableFromInline
internal func _getGenericSerialExecutor() -> Builtin.Executor {
  return UnownedSerialExecutor(_bitten_genericExecutor()).executor
}

@_silgen_name("swift_bitten_genericExecutor")
internal func _bitten_genericExecutor() -> Builtin.Executor

// The runtime calls these to reach executors implemented in Swift; it
// finds them by name when a job is first enqueued on such an executor.
@_silgen_name("_swift_task_enqueueOnExecutor")
internal func _enqueueOnExecutor<E: SerialExecutor>(job unownedJob: UnownedJob, executor: E) {
  executor.enqueue(ExecutorJob(unownedJob))
}

@_silgen_name("_task_serialExecutor_checkIsolated")
internal func _task_serialExecutor_checkIsolated<E: SerialExecutor>(executor: E) {
  executor.checkIsolated()
}

@_silgen_name("_task_serialExecutor_isSameExclusiveExecutionContext")
internal func _task_serialExecutor_isSameExclusiveExecutionContext<E: SerialExecutor>(
  current currentExecutor: E, executor: E
) -> Bool {
  return currentExecutor.isSameExclusiveExecutionContext(other: executor)
}

// ---- jobs ------------------------------------------------------------------------------

@_silgen_name("swift_job_run")
@usableFromInline
internal func _swiftJobRun(_ job: UnownedJob, _ executor: UnownedSerialExecutor)

@_silgen_name("swift_job_run_on_task_executor")
@usableFromInline
internal func _swiftJobRunOnTaskExecutor(_ job: UnownedJob, _ executor: UnownedTaskExecutor)

@_silgen_name("swift_job_run_on_serial_and_task_executor")
@usableFromInline
internal func _swiftJobRunOnTaskExecutor(_ job: UnownedJob,
                                         _ serialExecutor: UnownedSerialExecutor,
                                         _ taskExecutor: UnownedTaskExecutor)

@_silgen_name("swift_concurrency_jobPriority")
internal func _getJobPriority(_ job: Builtin.Job) -> UInt8

@frozen
public struct UnownedJob: Sendable {
  private var context: Builtin.Job

  @usableFromInline
  internal init(context: Builtin.Job) {
    self.context = context
  }

  public init(_ job: __owned Job) {
    self.context = job.context
  }

  public init(_ job: __owned ExecutorJob) {
    self.context = job.context
  }

  public var priority: JobPriority {
    return JobPriority(rawValue: _getJobPriority(context))
  }

  @_alwaysEmitIntoClient @inlinable
  public func _runSynchronously(on executor: UnownedSerialExecutor) {
    _swiftJobRun(self, executor)
  }

  @_alwaysEmitIntoClient @inlinable
  public func runSynchronously(on executor: UnownedSerialExecutor) {
    _swiftJobRun(self, executor)
  }

  @_alwaysEmitIntoClient @inlinable
  public func runSynchronously(on executor: UnownedTaskExecutor) {
    _swiftJobRunOnTaskExecutor(self, executor)
  }

  @_alwaysEmitIntoClient @inlinable
  public func runSynchronously(isolatedTo serialExecutor: UnownedSerialExecutor,
                               taskExecutor: UnownedTaskExecutor) {
    _swiftJobRunOnTaskExecutor(self, serialExecutor, taskExecutor)
  }
}

@frozen
public struct Job: Sendable, ~Copyable {
  internal var context: Builtin.Job

  @usableFromInline
  internal init(context: __owned Builtin.Job) {
    self.context = context
  }

  public init(_ job: UnownedJob) {
    self.context = unsafeBitCast(job, to: Builtin.Job.self)
  }

  public init(_ job: __owned ExecutorJob) {
    self.context = job.context
  }

  public var priority: JobPriority {
    return JobPriority(rawValue: _getJobPriority(context))
  }
}

extension Job {
  @_alwaysEmitIntoClient @inlinable
  public __consuming func runSynchronously(on executor: UnownedSerialExecutor) {
    _swiftJobRun(UnownedJob(self), executor)
  }
}

@frozen
public struct ExecutorJob: Sendable, ~Copyable {
  internal var context: Builtin.Job

  @usableFromInline
  internal init(context: __owned Builtin.Job) {
    self.context = context
  }

  public init(_ job: UnownedJob) {
    self.context = unsafeBitCast(job, to: Builtin.Job.self)
  }

  public init(_ job: __owned Job) {
    self.context = job.context
  }

  public var priority: JobPriority {
    return JobPriority(rawValue: _getJobPriority(context))
  }
}

extension ExecutorJob {
  @_alwaysEmitIntoClient @inlinable
  public __consuming func runSynchronously(on executor: UnownedSerialExecutor) {
    _swiftJobRun(UnownedJob(self), executor)
  }

  @_alwaysEmitIntoClient @inlinable
  public __consuming func runSynchronously(on executor: UnownedTaskExecutor) {
    _swiftJobRunOnTaskExecutor(UnownedJob(self), executor)
  }

  @_alwaysEmitIntoClient @inlinable
  public __consuming func runSynchronously(isolatedTo serialExecutor: UnownedSerialExecutor,
                                           taskExecutor: UnownedTaskExecutor) {
    _swiftJobRunOnTaskExecutor(UnownedJob(self), serialExecutor, taskExecutor)
  }
}

@frozen
public struct JobPriority: Sendable {
  public typealias RawValue = UInt8
  public var rawValue: RawValue

  public init(rawValue: RawValue) {
    self.rawValue = rawValue
  }

  public init(_ p: TaskPriority) {
    self.rawValue = p.rawValue
  }
}

extension TaskPriority {
  public init?(_ p: JobPriority) {
    if p.rawValue == 0 { return nil }
    self.init(rawValue: p.rawValue)
  }
}

extension JobPriority: Equatable {
  public static func == (lhs: JobPriority, rhs: JobPriority) -> Bool { lhs.rawValue == rhs.rawValue }
  public static func != (lhs: JobPriority, rhs: JobPriority) -> Bool { lhs.rawValue != rhs.rawValue }
}

extension JobPriority: Comparable {
  public static func < (lhs: JobPriority, rhs: JobPriority) -> Bool { lhs.rawValue < rhs.rawValue }
  public static func <= (lhs: JobPriority, rhs: JobPriority) -> Bool { lhs.rawValue <= rhs.rawValue }
  public static func > (lhs: JobPriority, rhs: JobPriority) -> Bool { lhs.rawValue > rhs.rawValue }
  public static func >= (lhs: JobPriority, rhs: JobPriority) -> Bool { lhs.rawValue >= rhs.rawValue }
}

@available(*, deprecated, renamed: "UnownedJob")
public typealias PartialAsyncTask = UnownedJob

// ---- global actors ---------------------------------------------------------------------

public protocol GlobalActor {
  associatedtype ActorType: Actor
  static var shared: ActorType { get }
  static var sharedUnownedExecutor: UnownedSerialExecutor { get }
}

extension GlobalActor {
  public static var sharedUnownedExecutor: UnownedSerialExecutor {
    return shared.unownedExecutor
  }
}

/// The actor of the main thread. Its executor is the main dispatch queue,
/// drained by dispatch_main (swift_task_asyncMainDrainQueue for async
/// main) or the application's run loop.
@globalActor
public final actor MainActor: GlobalActor {
  public static let shared = MainActor()

  @inlinable
  public nonisolated var unownedExecutor: UnownedSerialExecutor {
    return UnownedSerialExecutor(Builtin.buildMainActorExecutorRef())
  }

  @inlinable
  public static var sharedUnownedExecutor: UnownedSerialExecutor {
    return UnownedSerialExecutor(Builtin.buildMainActorExecutorRef())
  }

  @inlinable
  public nonisolated func enqueue(_ job: UnownedJob) {
    _enqueueOnMain(job)
  }
}

extension MainActor {
  @usableFromInline
  internal static func run<T>(resultType: T.Type = T.self,
                              body: @MainActor @Sendable () throws -> T) async rethrows -> T {
    return try await body()
  }

  @_alwaysEmitIntoClient
  public static func run<T: Sendable>(resultType: T.Type = T.self,
                                      body: @MainActor @Sendable () throws -> T) async rethrows -> T {
    return try await body()
  }

}

extension MainActor {
  /// Runs `operation` as if on the main actor; the caller asserts it is on
  /// the main thread.
  @_unavailableFromAsync
  @_alwaysEmitIntoClient
  public static func assumeIsolated<T: Sendable>(_ operation: @MainActor () throws -> T,
                                                 file: StaticString = #fileID, line: UInt = #line) rethrows -> T {
    typealias YesActor = @MainActor () throws -> T
    typealias NoActor = () throws -> T
    return try withoutActuallyEscaping(operation) { (_ fn: @escaping YesActor) throws -> T in
      let raw = unsafeBitCast(fn, to: NoActor.self)
      return try raw()
    }
  }
}

extension Actor {
  @_alwaysEmitIntoClient
  public nonisolated func preconditionIsolated(file: StaticString = #fileID, line: UInt = #line) {
    _taskCheckIsolated(self.unownedExecutor.executor)
  }

  @_alwaysEmitIntoClient
  public nonisolated func assertIsolated(file: StaticString = #fileID, line: UInt = #line) {
    _taskCheckIsolated(self.unownedExecutor.executor)
  }
}

// ---- failures --------------------------------------------------------------------------

// Messages are kept in the runtime (swift_bitten_concurrencyFailure).
@usableFromInline
internal var _isolationFailureMessage: Int { return 1 }

@_silgen_name("swift_bitten_concurrencyFailure")
@usableFromInline
internal func _bitten_concurrencyFailure(_ code: Int) -> Never
