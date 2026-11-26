// AsyncStream and AsyncThrowingStream: a buffer of elements yielded by a
// continuation and read by one consumer (or several, each element going to
// one of them). The storage below is shared by both; it holds an
// os_unfair_lock, the buffer, parked readers, and the termination handler.

import Swift

@_silgen_name("os_unfair_lock_lock") internal func _bitten_lock(_ l: UnsafeMutablePointer<UInt32>)
@_silgen_name("os_unfair_lock_unlock") internal func _bitten_unlock(_ l: UnsafeMutablePointer<UInt32>)

internal enum _StreamTermination {
  case finished
  case cancelled
}

/// Element/failure storage common to both streams. `Failure` is Never for
/// AsyncStream.
internal final class _StreamStorage<Element, Failure: Error>: @unchecked Sendable {
  enum Policy {
    case unbounded
    case oldest(Int)
    case newest(Int)
  }
  enum Yield {
    case enqueued(Int)
    case dropped(Element)
    case terminated
  }

  private let lock = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
  private var buffer: [Element] = []
  private var readers: [UnsafeContinuation<Element?, Error>] = []
  private var finished = false
  private var failure: Failure? = nil
  private let policy: Policy
  var onTermination: ((_StreamTermination) -> Void)?

  init(policy: Policy) {
    self.policy = policy
    lock.initialize(to: 0)
  }
  deinit { lock.deallocate() }

  private func withLock<R>(_ body: () -> R) -> R {
    _bitten_lock(lock)
    defer { _bitten_unlock(lock) }
    return body()
  }

  func yield(_ value: Element) -> Yield {
    _bitten_lock(lock)
    if finished {
      _bitten_unlock(lock)
      return .terminated
    }
    if !readers.isEmpty {
      let r = readers.removeFirst()
      _bitten_unlock(lock)
      r.resume(returning: value)
      return .enqueued(remainingAfterEnqueue())
    }
    let result: Yield
    switch policy {
    case .unbounded:
      buffer.append(value)
      result = .enqueued(Int.max)
    case .oldest(let limit):
      if buffer.count < limit {
        buffer.append(value)
        result = .enqueued(limit - buffer.count)
      } else {
        result = .dropped(value)
      }
    case .newest(let limit):
      if limit == 0 {
        result = .dropped(value)
      } else if buffer.count < limit {
        buffer.append(value)
        result = .enqueued(limit - buffer.count)
      } else {
        let old = buffer.removeFirst()
        buffer.append(value)
        result = .dropped(old)
      }
    }
    _bitten_unlock(lock)
    return result
  }

  private func remainingAfterEnqueue() -> Int {
    switch policy {
    case .unbounded: return Int.max
    case .oldest(let l), .newest(let l): return withLock { l - buffer.count }
    }
  }

  func finish(throwing error: Failure?, reason: _StreamTermination = .finished) {
    _bitten_lock(lock)
    if finished {
      _bitten_unlock(lock)
      return
    }
    finished = true
    if failure == nil { failure = error }
    let waiting = readers
    readers.removeAll()
    let handler = onTermination
    onTermination = nil
    let bufferEmpty = buffer.isEmpty
    let f = failure
    if bufferEmpty { failure = nil }
    _bitten_unlock(lock)
    for r in waiting {
      if let e = f, bufferEmpty { r.resume(throwing: e) } else { r.resume(returning: nil) }
    }
    handler?(reason)
  }

  /// The next element, nil when finished; throws the failure once.
  func next() async throws -> Element? {
    _bitten_lock(lock)
    if !buffer.isEmpty {
      let v = buffer.removeFirst()
      _bitten_unlock(lock)
      return v
    }
    if finished {
      let f = failure
      failure = nil
      _bitten_unlock(lock)
      if let e = f { throw e }
      return nil
    }
    _bitten_unlock(lock)
    return try await withTaskCancellationHandler {
      try await withUnsafeThrowingContinuation { (c: UnsafeContinuation<Element?, Error>) in
        _bitten_lock(lock)
        if !buffer.isEmpty {
          let v = buffer.removeFirst()
          _bitten_unlock(lock)
          c.resume(returning: v)
        } else if finished {
          let f = failure
          failure = nil
          _bitten_unlock(lock)
          if let e = f { c.resume(throwing: e) } else { c.resume(returning: nil) }
        } else {
          readers.append(c)
          _bitten_unlock(lock)
        }
      }
    } onCancel: {
      self.finish(throwing: nil, reason: .cancelled)
    }
  }
}

// MARK: - AsyncStream

public struct AsyncStream<Element> {
  internal let _storage: _StreamStorage<Element, Never>?
  internal let _produce: (() async -> Element?)?

  public struct Continuation: Sendable {
    public enum Termination: Sendable {
      case finished
      case cancelled
    }

    public enum YieldResult {
      case enqueued(remaining: Int)
      case dropped(Element)
      case terminated
    }

    public enum BufferingPolicy: Sendable {
      case unbounded
      case bufferingOldest(Int)
      case bufferingNewest(Int)
    }

    internal let _storage: _StreamStorage<Element, Never>

    @discardableResult
    public func yield(_ value: __owned Element) -> YieldResult {
      switch _storage.yield(value) {
      case .enqueued(let n): return .enqueued(remaining: n)
      case .dropped(let e): return .dropped(e)
      case .terminated: return .terminated
      }
    }

    public func finish() { _storage.finish(throwing: nil) }

    public var onTermination: (@Sendable (Termination) -> Void)? {
      get { return nil }
      nonmutating set {
        guard let handler = newValue else { _storage.onTermination = nil; return }
        _storage.onTermination = { reason in handler(reason == .cancelled ? .cancelled : .finished) }
      }
    }
  }

  public init(_ elementType: Element.Type = Element.self,
              bufferingPolicy limit: Continuation.BufferingPolicy = .unbounded,
              _ build: (Continuation) -> Void) {
    let policy: _StreamStorage<Element, Never>.Policy
    switch limit {
    case .unbounded: policy = .unbounded
    case .bufferingOldest(let n): policy = .oldest(n)
    case .bufferingNewest(let n): policy = .newest(n)
    }
    let storage = _StreamStorage<Element, Never>(policy: policy)
    self._storage = storage
    self._produce = nil
    build(Continuation(_storage: storage))
  }

  public init(unfolding produce: @escaping @Sendable () async -> Element?,
              onCancel: (@Sendable () -> Void)? = nil) {
    self._storage = nil
    self._produce = produce
  }

  public static func makeStream(of elementType: Element.Type = Element.self,
                                bufferingPolicy limit: Continuation.BufferingPolicy = .unbounded)
    -> (stream: AsyncStream<Element>, continuation: AsyncStream<Element>.Continuation) {
    var continuation: Continuation! = nil
    let stream = AsyncStream(elementType, bufferingPolicy: limit) { continuation = $0 }
    return (stream: stream, continuation: continuation)
  }
}

extension AsyncStream: AsyncSequence {
  public typealias Failure = Never

  public struct Iterator: AsyncIteratorProtocol {
    public typealias Failure = Never
    internal let _storage: _StreamStorage<Element, Never>?
    internal let _produce: (() async -> Element?)?

    public mutating func next() async -> Element? {
      if let p = _produce { return await p() }
      return try! await _storage!.next()
    }
    public mutating func next(isolation actor: isolated (any Actor)?) async -> Element? {
      return await next()
    }
  }

  public func makeAsyncIterator() -> Iterator { return Iterator(_storage: _storage, _produce: _produce) }
}

extension AsyncStream: @unchecked Sendable where Element: Sendable {}
extension AsyncStream.Continuation.YieldResult: Sendable where Element: Sendable {}

extension AsyncStream.Continuation {
  @discardableResult
  public func yield() -> AsyncStream<Element>.Continuation.YieldResult where Element == Void { return yield(()) }
}

// MARK: - AsyncThrowingStream

public struct AsyncThrowingStream<Element, Failure: Error> {
  internal let _storage: _StreamStorage<Element, Failure>?
  internal let _produce: (() async throws -> Element?)?

  public struct Continuation: Sendable {
    public enum Termination: Sendable {
      case finished(Failure?)
      case cancelled
    }

    public enum YieldResult {
      case enqueued(remaining: Int)
      case dropped(Element)
      case terminated
    }

    public enum BufferingPolicy: Sendable {
      case unbounded
      case bufferingOldest(Int)
      case bufferingNewest(Int)
    }

    internal let _storage: _StreamStorage<Element, Failure>

    @discardableResult
    public func yield(_ value: __owned Element) -> YieldResult {
      switch _storage.yield(value) {
      case .enqueued(let n): return .enqueued(remaining: n)
      case .dropped(let e): return .dropped(e)
      case .terminated: return .terminated
      }
    }

    @discardableResult
    public func yield(with result: Result<Element, Failure>) -> YieldResult {
      switch result {
      case .success(let v): return yield(v)
      case .failure(let e):
        finish(throwing: e)
        return .terminated
      }
    }

    public func finish(throwing error: __owned Failure? = nil) { _storage.finish(throwing: error) }

    public var onTermination: (@Sendable (Termination) -> Void)? {
      get { return nil }
      nonmutating set {
        guard let handler = newValue else { _storage.onTermination = nil; return }
        _storage.onTermination = { reason in handler(reason == .cancelled ? .cancelled : .finished(nil)) }
      }
    }
  }

  internal init(_policy limit: Continuation.BufferingPolicy, _ build: (Continuation) -> Void) {
    let policy: _StreamStorage<Element, Failure>.Policy
    switch limit {
    case .unbounded: policy = .unbounded
    case .bufferingOldest(let n): policy = .oldest(n)
    case .bufferingNewest(let n): policy = .newest(n)
    }
    let storage = _StreamStorage<Element, Failure>(policy: policy)
    self._storage = storage
    self._produce = nil
    build(Continuation(_storage: storage))
  }
}

extension AsyncThrowingStream {
  public init(_ elementType: Element.Type = Element.self,
              bufferingPolicy limit: Continuation.BufferingPolicy = .unbounded,
              _ build: (Continuation) -> Void) where Failure == Error {
    self.init(_policy: limit, build)
  }

  public init(unfolding produce: @escaping () async throws -> Element?) where Failure == Error {
    self._storage = nil
    self._produce = produce
  }

  public static func makeStream(of elementType: Element.Type = Element.self, throwing failureType: Failure.Type = Failure.self,
                                bufferingPolicy limit: Continuation.BufferingPolicy = .unbounded)
    -> (stream: AsyncThrowingStream<Element, Failure>, continuation: AsyncThrowingStream<Element, Failure>.Continuation)
    where Failure == Error {
    var continuation: Continuation! = nil
    let stream = AsyncThrowingStream(elementType, bufferingPolicy: limit) { continuation = $0 }
    return (stream: stream, continuation: continuation)
  }
}

extension AsyncThrowingStream: AsyncSequence {
  public struct Iterator: AsyncIteratorProtocol {
    internal let _storage: _StreamStorage<Element, Failure>?
    internal let _produce: (() async throws -> Element?)?

    public mutating func next() async throws -> Element? {
      if let p = _produce { return try await p() }
      return try await _storage!.next()
    }
    public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
      do {
        return try await next()
      } catch {
        throw error as! Failure
      }
    }
  }

  public func makeAsyncIterator() -> Iterator { return Iterator(_storage: _storage, _produce: _produce) }
}

extension AsyncThrowingStream: @unchecked Sendable where Element: Sendable {}
