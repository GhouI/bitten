// Task groups: TaskGroup, ThrowingTaskGroup, DiscardingTaskGroup and the
// with...TaskGroup functions. Each group is the runtime's group object
// (src/frameworks/concurrency/group.c); children are tasks created into it.
// Frozen like Apple's: one raw pointer.

import Swift

@_silgen_name("swift_taskGroup_wait_next_throwing")
@usableFromInline
func _taskGroupWaitNext<T>(group: Builtin.RawPointer) async throws -> T?

@_silgen_name("swift_taskGroup_cancelAll")
@usableFromInline
func _taskGroupCancelAll(group: Builtin.RawPointer)

@_silgen_name("swift_taskGroup_isCancelled")
@usableFromInline
func _taskGroupIsCancelled(group: Builtin.RawPointer) -> Bool

@_silgen_name("swift_taskGroup_isEmpty")
@usableFromInline
func _taskGroupIsEmpty(_ group: Builtin.RawPointer) -> Bool

/// TaskGroupFlags: results are discarded as children finish.
@usableFromInline let _taskGroupDiscardResults = 1 << 8

// MARK: - TaskGroup

@frozen
public struct TaskGroup<ChildTaskResult: Sendable> {
  @usableFromInline internal let _group: Builtin.RawPointer

  @inlinable init(group: Builtin.RawPointer) { self._group = group }

  @_alwaysEmitIntoClient
  public mutating func addTask(priority: TaskPriority? = nil,
                               operation: sending @escaping @isolated(any) () async -> ChildTaskResult) {
    let flags = taskCreateFlags(priority: priority, isChildTask: true, copyTaskLocals: false,
                                inheritContext: false, enqueueJob: true,
                                addPendingGroupTaskUnconditionally: true,
                                isDiscardingTask: false, isSynchronousStart: false)
    let executor = Builtin.extractFunctionIsolation(operation)?.unownedExecutor.executor
    _ = Builtin.createTask(flags: flags, initialSerialExecutor: executor, taskGroup: _group, operation: operation)
  }

  @_alwaysEmitIntoClient
  public mutating func addTaskUnlessCancelled(priority: TaskPriority? = nil,
                                              operation: sending @escaping @isolated(any) () async -> ChildTaskResult)
    -> Bool {
    if isCancelled { return false }
    addTask(priority: priority, operation: operation)
    return true
  }

  public mutating func next(isolation: isolated (any Actor)? = #isolation) async -> ChildTaskResult? {
    return try! await _taskGroupWaitNext(group: _group)
  }

  @usableFromInline
  internal mutating func awaitAllRemainingTasks(isolation: isolated (any Actor)? = #isolation) async {
    while let _ = await next(isolation: isolation) {}
  }

  public mutating func waitForAll(isolation: isolated (any Actor)? = #isolation) async {
    await awaitAllRemainingTasks(isolation: isolation)
  }

  public var isEmpty: Bool { return _taskGroupIsEmpty(_group) }
  public func cancelAll() { _taskGroupCancelAll(group: _group) }
  public var isCancelled: Bool { return _taskGroupIsCancelled(group: _group) }
}

extension TaskGroup: AsyncSequence {
  public typealias AsyncIterator = Iterator
  public typealias Element = ChildTaskResult
  public typealias Failure = Never

  public func makeAsyncIterator() -> Iterator { return Iterator(group: self) }

  public struct Iterator: AsyncIteratorProtocol {
    public typealias Element = ChildTaskResult
    public typealias Failure = Never
    @usableFromInline var group: TaskGroup<ChildTaskResult>
    @usableFromInline var finished: Bool = false
    init(group: TaskGroup<ChildTaskResult>) { self.group = group }

    public mutating func next() async -> Element? {
      guard !finished else { return nil }
      guard let element = await group.next() else {
        finished = true
        return nil
      }
      return element
    }
    public mutating func next(isolation actor: isolated (any Actor)?) async -> Element? {
      guard !finished else { return nil }
      guard let element = await group.next(isolation: actor) else {
        finished = true
        return nil
      }
      return element
    }
    public mutating func cancel() {
      finished = true
      group.cancelAll()
    }
  }
}

public func withTaskGroup<ChildTaskResult, GroupResult>(
  of childTaskResultType: ChildTaskResult.Type = ChildTaskResult.self,
  returning returnType: GroupResult.Type = GroupResult.self,
  isolation: isolated (any Actor)? = #isolation,
  body: (inout TaskGroup<ChildTaskResult>) async -> GroupResult
) async -> GroupResult where ChildTaskResult: Sendable {
  let raw = Builtin.createTaskGroup(ChildTaskResult.self)
  var group = TaskGroup<ChildTaskResult>(group: raw)
  let result = await body(&group)
  await group.awaitAllRemainingTasks(isolation: isolation)
  Builtin.destroyTaskGroup(raw)
  return result
}

// MARK: - ThrowingTaskGroup

@frozen
public struct ThrowingTaskGroup<ChildTaskResult: Sendable, Failure: Error> {
  @usableFromInline internal let _group: Builtin.RawPointer

  @inlinable init(group: Builtin.RawPointer) { self._group = group }

  @_alwaysEmitIntoClient
  public mutating func addTask(priority: TaskPriority? = nil,
                               operation: sending @escaping @isolated(any) () async throws -> ChildTaskResult) {
    let flags = taskCreateFlags(priority: priority, isChildTask: true, copyTaskLocals: false,
                                inheritContext: false, enqueueJob: true,
                                addPendingGroupTaskUnconditionally: true,
                                isDiscardingTask: false, isSynchronousStart: false)
    let executor = Builtin.extractFunctionIsolation(operation)?.unownedExecutor.executor
    _ = Builtin.createTask(flags: flags, initialSerialExecutor: executor, taskGroup: _group, operation: operation)
  }

  @_alwaysEmitIntoClient
  public mutating func addTaskUnlessCancelled(priority: TaskPriority? = nil,
                                              operation: sending @escaping @isolated(any) () async throws -> ChildTaskResult)
    -> Bool {
    if isCancelled { return false }
    addTask(priority: priority, operation: operation)
    return true
  }

  public mutating func next(isolation: isolated (any Actor)? = #isolation) async throws -> ChildTaskResult? {
    return try await _taskGroupWaitNext(group: _group)
  }

  public mutating func nextResult(isolation: isolated (any Actor)? = #isolation) async -> Result<ChildTaskResult, Failure>? {
    do {
      guard let v: ChildTaskResult = try await _taskGroupWaitNext(group: _group) else { return nil }
      return .success(v)
    } catch {
      return .failure(error as! Failure)
    }
  }

  @usableFromInline
  internal mutating func awaitAllRemainingTasks(isolation: isolated (any Actor)? = #isolation) async {
    while true {
      do {
        guard let _ = try await next(isolation: isolation) else { return }
      } catch {}
    }
  }

  public mutating func waitForAll(isolation: isolated (any Actor)? = #isolation) async throws {
    var firstError: Error? = nil
    while true {
      do {
        guard let _ = try await next(isolation: isolation) else { break }
      } catch {
        if firstError == nil { firstError = error }
      }
    }
    if let e = firstError { throw e }
  }

  public var isEmpty: Bool { return _taskGroupIsEmpty(_group) }
  public func cancelAll() { _taskGroupCancelAll(group: _group) }
  public var isCancelled: Bool { return _taskGroupIsCancelled(group: _group) }
}

extension ThrowingTaskGroup: AsyncSequence {
  public typealias AsyncIterator = Iterator
  public typealias Element = ChildTaskResult

  public func makeAsyncIterator() -> Iterator { return Iterator(group: self) }

  public struct Iterator: AsyncIteratorProtocol {
    public typealias Element = ChildTaskResult
    @usableFromInline var group: ThrowingTaskGroup<ChildTaskResult, Failure>
    @usableFromInline var finished: Bool = false
    init(group: ThrowingTaskGroup<ChildTaskResult, Failure>) { self.group = group }

    public mutating func next() async throws -> Element? {
      guard !finished else { return nil }
      do {
        guard let element = try await group.next() else {
          finished = true
          return nil
        }
        return element
      } catch {
        finished = true
        throw error
      }
    }
    public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
      do {
        return try await next()
      } catch {
        throw error as! Failure
      }
    }
    public mutating func cancel() {
      finished = true
      group.cancelAll()
    }
  }
}

public func withThrowingTaskGroup<ChildTaskResult, GroupResult>(
  of childTaskResultType: ChildTaskResult.Type = ChildTaskResult.self,
  returning returnType: GroupResult.Type = GroupResult.self,
  isolation: isolated (any Actor)? = #isolation,
  body: (inout ThrowingTaskGroup<ChildTaskResult, Error>) async throws -> GroupResult
) async rethrows -> GroupResult where ChildTaskResult: Sendable {
  let raw = Builtin.createTaskGroup(ChildTaskResult.self)
  var group = ThrowingTaskGroup<ChildTaskResult, Error>(group: raw)
  do {
    let result = try await body(&group)
    await group.awaitAllRemainingTasks(isolation: isolation)
    Builtin.destroyTaskGroup(raw)
    return result
  } catch {
    group.cancelAll()
    await group.awaitAllRemainingTasks(isolation: isolation)
    Builtin.destroyTaskGroup(raw)
    throw error
  }
}

// MARK: - DiscardingTaskGroup

@frozen
public struct DiscardingTaskGroup {
  @usableFromInline internal let _group: Builtin.RawPointer

  @inlinable init(group: Builtin.RawPointer) { self._group = group }

  @_alwaysEmitIntoClient
  public mutating func addTask(priority: TaskPriority? = nil,
                               operation: sending @escaping @isolated(any) () async -> Void) {
    let flags = taskCreateFlags(priority: priority, isChildTask: true, copyTaskLocals: false,
                                inheritContext: false, enqueueJob: true,
                                addPendingGroupTaskUnconditionally: true,
                                isDiscardingTask: true, isSynchronousStart: false)
    let executor = Builtin.extractFunctionIsolation(operation)?.unownedExecutor.executor
    _ = Builtin.createTask(flags: flags, initialSerialExecutor: executor, taskGroup: _group, operation: operation)
  }

  @_alwaysEmitIntoClient
  public mutating func addTaskUnlessCancelled(priority: TaskPriority? = nil,
                                              operation: sending @escaping @isolated(any) () async -> Void) -> Bool {
    if isCancelled { return false }
    addTask(priority: priority, operation: operation)
    return true
  }

  public var isEmpty: Bool { return _taskGroupIsEmpty(_group) }
  public func cancelAll() { _taskGroupCancelAll(group: _group) }
  public var isCancelled: Bool { return _taskGroupIsCancelled(group: _group) }

  @usableFromInline
  internal mutating func awaitAllRemainingTasks() async {
    while true {
      let next: Void? = try? await _taskGroupWaitNext(group: _group)
      if next == nil && isEmpty { return }
    }
  }
}

public func withDiscardingTaskGroup<GroupResult>(
  returning returnType: GroupResult.Type = GroupResult.self,
  isolation: isolated (any Actor)? = #isolation,
  body: (inout DiscardingTaskGroup) async -> GroupResult
) async -> GroupResult {
  let raw = Builtin.createTaskGroupWithFlags(_taskGroupDiscardResults, Void.self)
  var group = DiscardingTaskGroup(group: raw)
  let result = await body(&group)
  await group.awaitAllRemainingTasks()
  Builtin.destroyTaskGroup(raw)
  return result
}
