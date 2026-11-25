// Tasks: creation, results, cancellation, priorities.
//
// A Task value holds a strong reference to the runtime's task object
// (swift_task_create). Tasks are futures: awaiting `value` parks the
// waiting task on the task (swift_task_future_wait*) until it completes.

import Swift

@frozen
public struct Task<Success: Sendable, Failure: Error>: Sendable {
  @usableFromInline
  internal let _task: Builtin.NativeObject

  @_alwaysEmitIntoClient
  internal init(_ task: Builtin.NativeObject) {
    self._task = task
  }
}

extension Task {
  public var value: Success {
    get async throws {
      return try await _taskFutureGetThrowing(_task)
    }
  }

  public var result: Result<Success, Failure> {
    get async {
      do {
        return .success(try await _taskFutureGetThrowing(_task))
      } catch {
        return .failure(error as! Failure)
      }
    }
  }

  public func cancel() {
    _taskCancel(_task)
  }

  @_transparent
  public var isCancelled: Bool {
    @_transparent get { _taskIsCancelled(_task) }
  }
}

extension Task where Failure == Never {
  public var value: Success {
    get async {
      return await _taskFutureGet(_task)
    }
  }
}

extension Task: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(_taskAddress(_task))
  }
  public var hashValue: Int {
    return _hashValue(for: self)
  }
}

extension Task: Equatable {
  public static func == (lhs: Task, rhs: Task) -> Bool {
    return _taskAddress(lhs._task) == _taskAddress(rhs._task)
  }
}

@usableFromInline
internal func _taskAddress(_ task: Builtin.NativeObject) -> UInt {
  return UInt(Builtin.ptrtoint_Word(Builtin.bridgeToRawPointer(task)))
}

// ---- priorities --------------------------------------------------------------------------

// RawRepresentable (and Codable, description) come with those protocols.
public struct TaskPriority: Sendable {
  public typealias RawValue = UInt8
  public var rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let high: TaskPriority = .init(rawValue: 0x19)

  @_alwaysEmitIntoClient
  public static var medium: TaskPriority {
    .init(rawValue: 0x15)
  }

  public static let low: TaskPriority = .init(rawValue: 0x11)
  public static let userInitiated: TaskPriority = high
  public static let utility: TaskPriority = low
  public static let background: TaskPriority = .init(rawValue: 0x09)

  @available(*, deprecated, renamed: "medium")
  public static let `default`: TaskPriority = .init(rawValue: 0x15)
}

extension TaskPriority: Equatable {
  public static func == (lhs: TaskPriority, rhs: TaskPriority) -> Bool { lhs.rawValue == rhs.rawValue }
  public static func != (lhs: TaskPriority, rhs: TaskPriority) -> Bool { lhs.rawValue != rhs.rawValue }
}

extension TaskPriority: Comparable {
  public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool { lhs.rawValue < rhs.rawValue }
  public static func <= (lhs: TaskPriority, rhs: TaskPriority) -> Bool { lhs.rawValue <= rhs.rawValue }
  public static func > (lhs: TaskPriority, rhs: TaskPriority) -> Bool { lhs.rawValue > rhs.rawValue }
  public static func >= (lhs: TaskPriority, rhs: TaskPriority) -> Bool { lhs.rawValue >= rhs.rawValue }
}

extension Task where Success == Never, Failure == Never {
  public static var currentPriority: TaskPriority {
    if let task = _currentTask() {
      return TaskPriority(rawValue: UInt8(truncatingIfNeeded: _taskCurrentPriority(task)))
    }
    return TaskPriority(rawValue: UInt8(truncatingIfNeeded: _getCurrentThreadPriority()))
  }

  public static var basePriority: TaskPriority? {
    if let task = _currentTask() {
      return TaskPriority(rawValue: UInt8(truncatingIfNeeded: _taskBasePriority(task)))
    }
    return nil
  }
}

// ---- creating tasks ----------------------------------------------------------------------

// Bits of the flags word swift_task_create takes (TaskCreateFlags).
@_alwaysEmitIntoClient
internal func taskCreateFlags(priority: TaskPriority?, isChildTask: Bool, copyTaskLocals: Bool,
                              inheritContext: Bool, enqueueJob: Bool,
                              addPendingGroupTaskUnconditionally: Bool,
                              isDiscardingTask: Bool, isSynchronousStart: Bool) -> Int {
  var bits = Int(priority?.rawValue ?? 0)
  if isChildTask { bits |= 1 << 8 }
  if copyTaskLocals { bits |= 1 << 10 }
  if inheritContext { bits |= 1 << 11 }
  if enqueueJob { bits |= 1 << 12 }
  if addPendingGroupTaskUnconditionally { bits |= 1 << 13 }
  if isDiscardingTask { bits |= 1 << 14 }
  if isSynchronousStart { bits |= 1 << 16 }
  return bits
}

extension Task where Failure == Never {
  @discardableResult
  @_alwaysEmitIntoClient
  public init(priority: TaskPriority? = nil,
              @_inheritActorContext @_implicitSelfCapture
              operation: sending @escaping @isolated(any) () async -> Success) {
    let flags = taskCreateFlags(priority: priority, isChildTask: false, copyTaskLocals: true,
                                inheritContext: true, enqueueJob: true,
                                addPendingGroupTaskUnconditionally: false,
                                isDiscardingTask: false, isSynchronousStart: false)
    let executor = Builtin.extractFunctionIsolation(operation)?.unownedExecutor.executor
    let (task, _) = Builtin.createTask(flags: flags, initialSerialExecutor: executor,
                                       operation: operation)
    self._task = task
  }

  @discardableResult
  @_alwaysEmitIntoClient
  public static func detached(priority: TaskPriority? = nil,
                              operation: sending @escaping @isolated(any) () async -> Success)
    -> Task<Success, Never> {
    let flags = taskCreateFlags(priority: priority, isChildTask: false, copyTaskLocals: false,
                                inheritContext: false, enqueueJob: true,
                                addPendingGroupTaskUnconditionally: false,
                                isDiscardingTask: false, isSynchronousStart: false)
    let executor = Builtin.extractFunctionIsolation(operation)?.unownedExecutor.executor
    let (task, _) = Builtin.createTask(flags: flags, initialSerialExecutor: executor,
                                       operation: operation)
    return Task(task)
  }
}

extension Task where Failure == any Error {
  @discardableResult
  @_alwaysEmitIntoClient
  public init(priority: TaskPriority? = nil,
              @_inheritActorContext @_implicitSelfCapture
              operation: sending @escaping @isolated(any) () async throws -> Success) {
    let flags = taskCreateFlags(priority: priority, isChildTask: false, copyTaskLocals: true,
                                inheritContext: true, enqueueJob: true,
                                addPendingGroupTaskUnconditionally: false,
                                isDiscardingTask: false, isSynchronousStart: false)
    let executor = Builtin.extractFunctionIsolation(operation)?.unownedExecutor.executor
    let (task, _) = Builtin.createTask(flags: flags, initialSerialExecutor: executor,
                                       operation: operation)
    self._task = task
  }

  @discardableResult
  @_alwaysEmitIntoClient
  public static func detached(priority: TaskPriority? = nil,
                              operation: sending @escaping @isolated(any) () async throws -> Success)
    -> Task<Success, any Error> {
    let flags = taskCreateFlags(priority: priority, isChildTask: false, copyTaskLocals: false,
                                inheritContext: false, enqueueJob: true,
                                addPendingGroupTaskUnconditionally: false,
                                isDiscardingTask: false, isSynchronousStart: false)
    let executor = Builtin.extractFunctionIsolation(operation)?.unownedExecutor.executor
    let (task, _) = Builtin.createTask(flags: flags, initialSerialExecutor: executor,
                                       operation: operation)
    return Task(task)
  }
}

// ---- yielding and cancellation -----------------------------------------------------------

extension Task where Success == Never, Failure == Never {
  /// Suspends the current task and lets other work run: the task is
  /// enqueued again on the executor it was running on.
  public static func yield() async {
    let _: () = await Builtin.withUnsafeContinuation { (c: Builtin.RawUnsafeContinuation) -> () in
      _bitten_resumeLater(c)
    }
  }

  public static var isCancelled: Bool {
    if let task = _currentTask() {
      return _taskIsCancelled(task)
    }
    return false
  }

  public static func checkCancellation() throws {
    if Task<Never, Never>.isCancelled {
      throw CancellationError()
    }
  }
}

public struct CancellationError: Error {
  public init() {}
}

public func withTaskCancellationHandler<T>(
  operation: () async throws -> T,
  onCancel handler: @Sendable () -> Void,
  isolation: isolated (any Actor)? = #isolation
) async rethrows -> T {
  let record = _taskAddCancellationHandler(handler: handler)
  defer { _taskRemoveCancellationHandler(record: record) }
  return try await operation()
}

// ---- the current task --------------------------------------------------------------------

public func withUnsafeCurrentTask<T>(body: (UnsafeCurrentTask?) throws -> T) rethrows -> T {
  guard let task = _currentTask() else {
    return try body(nil)
  }
  return try body(UnsafeCurrentTask(task))
}

public func withUnsafeCurrentTask<T>(body: (UnsafeCurrentTask?) async throws -> T) async rethrows -> T {
  guard let task = _currentTask() else {
    return try await body(nil)
  }
  return try await body(UnsafeCurrentTask(task))
}

public struct UnsafeCurrentTask {
  internal let _task: Builtin.NativeObject

  internal init(_ task: Builtin.NativeObject) {
    self._task = task
  }

  public var isCancelled: Bool {
    return _taskIsCancelled(_task)
  }

  public var priority: TaskPriority {
    return TaskPriority(rawValue: UInt8(truncatingIfNeeded: _taskCurrentPriority(_task)))
  }

  public var basePriority: TaskPriority {
    return TaskPriority(rawValue: UInt8(truncatingIfNeeded: _taskBasePriority(_task)))
  }

  public func cancel() {
    _taskCancel(_task)
  }
}

extension UnsafeCurrentTask: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(_taskAddress(_task))
  }
  public var hashValue: Int {
    return _hashValue(for: self)
  }
}

extension UnsafeCurrentTask: Equatable {
  public static func == (lhs: UnsafeCurrentTask, rhs: UnsafeCurrentTask) -> Bool {
    return _taskAddress(lhs._task) == _taskAddress(rhs._task)
  }
}

// ---- runtime entry points ----------------------------------------------------------------

// The runtime returns the current task without a reference (+0), but a
// function returning a NativeObject is taken to return one: callers that
// keep the result must add it (_currentTask).
@_silgen_name("swift_task_getCurrent")
public func _getCurrentAsyncTask() -> Builtin.NativeObject?

@usableFromInline
internal func _currentTask() -> Builtin.NativeObject? {
  guard let task = _getCurrentAsyncTask() else { return nil }
  Builtin.retain(task)
  return task
}

@_silgen_name("swift_task_enqueueGlobal")
@usableFromInline
internal func _enqueueJobGlobal(_ task: Builtin.Job)

@_silgen_name("swift_task_enqueueGlobalWithDelay")
@usableFromInline
internal func _enqueueJobGlobalWithDelay(_ delay: UInt64, _ task: Builtin.Job)

@_silgen_name("swift_task_enqueueGlobalWithDeadline")
@usableFromInline
internal func _enqueueJobGlobalWithDeadline(_ seconds: Int64, _ nanoseconds: Int64,
                                            _ toleranceSec: Int64, _ toleranceNSec: Int64,
                                            _ clock: Int32, _ task: UnownedJob)

@usableFromInline
@_silgen_name("swift_task_asyncMainDrainQueue")
internal func _asyncMainDrainQueue() -> Never

/// Runs an async main function: the compiler's entry point for programs
/// whose main is async goes through here.
@usableFromInline
@preconcurrency
internal func _runAsyncMain(_ asyncFun: @escaping @Sendable () async throws -> ()) {
  let flags = taskCreateFlags(priority: nil, isChildTask: false, copyTaskLocals: false,
                              inheritContext: false, enqueueJob: false,
                              addPendingGroupTaskUnconditionally: false,
                              isDiscardingTask: false, isSynchronousStart: false)
  let (task, _) = Builtin.createTask(flags: flags, initialSerialExecutor: _getMainExecutor(),
                                     operation: { @MainActor in
    do {
      try await asyncFun()
    } catch {
      _errorInMain(error)
    }
  })
  _bitten_enqueueOnMainExecutor(task)
  _asyncMainDrainQueue()
}

@_silgen_name("swift_bitten_enqueueTaskOnMain")
internal func _bitten_enqueueOnMainExecutor(_ task: Builtin.NativeObject)

@_silgen_name("swift_task_future_wait")
public func _taskFutureGet<T>(_ task: Builtin.NativeObject) async -> T

@_silgen_name("swift_task_future_wait_throwing")
public func _taskFutureGetThrowing<T>(_ task: Builtin.NativeObject) async throws -> T

@_silgen_name("swift_task_cancel")
public func _taskCancel(_ task: Builtin.NativeObject)

@_silgen_name("swift_task_isCancelled")
@usableFromInline
internal func _taskIsCancelled(_ task: Builtin.NativeObject) -> Bool

@_silgen_name("swift_task_currentPriority")
internal func _taskCurrentPriority(_ task: Builtin.NativeObject) -> UInt

@_silgen_name("swift_task_basePriority")
internal func _taskBasePriority(_ task: Builtin.NativeObject) -> UInt

@_silgen_name("swift_task_getCurrentThreadPriority")
internal func _getCurrentThreadPriority() -> Int

@usableFromInline
@_silgen_name("swift_task_addCancellationHandler")
internal func _taskAddCancellationHandler(handler: () -> Void) -> UnsafeRawPointer

@usableFromInline
@_silgen_name("swift_task_removeCancellationHandler")
internal func _taskRemoveCancellationHandler(record: UnsafeRawPointer)

/// Enqueues a job that resumes the continuation on the global executor.
@_silgen_name("swift_bitten_resumeLater")
internal func _bitten_resumeLater(_ continuation: Builtin.RawUnsafeContinuation)

@_silgen_name("swift_deletedAsyncMethodError")
@usableFromInline
internal func swift_deletedAsyncMethodError() async {
  _bitten_concurrencyFailure(2)
}
