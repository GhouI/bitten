// AsyncSequence and AsyncIteratorProtocol, with Apple's requirements (the
// typed-throws `next(isolation:)` and the Failure associated type), and a
// few of the standard algorithms over them.

import Swift

public protocol AsyncIteratorProtocol<Element, Failure> {
  associatedtype Element
  associatedtype Failure: Error = any Error
  mutating func next() async throws -> Element?
  mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element?
}

extension AsyncIteratorProtocol {
  /// The default forwards to next() (whose error is then this Failure).
  public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
    do {
      return try await next()
    } catch {
      throw error as! Failure
    }
  }
}

extension AsyncIteratorProtocol where Failure == Never {
  public mutating func next() async -> Element? {
    return await next(isolation: nil)
  }
}

public protocol AsyncSequence<Element, Failure> {
  associatedtype AsyncIterator: AsyncIteratorProtocol
  associatedtype Element where AsyncIterator.Element == Element
  associatedtype Failure = AsyncIterator.Failure where AsyncIterator.Failure == Failure
  __consuming func makeAsyncIterator() -> AsyncIterator
}

// MARK: - algorithms

extension AsyncSequence {
  public func contains(where predicate: (Element) async throws -> Bool) async rethrows -> Bool {
    var it = makeAsyncIterator()
    while let e = try await it.next() {
      if try await predicate(e) { return true }
    }
    return false
  }
  public func first(where predicate: (Element) async throws -> Bool) async rethrows -> Element? {
    var it = makeAsyncIterator()
    while let e = try await it.next() {
      if try await predicate(e) { return e }
    }
    return nil
  }
  public func reduce<Result>(_ initialResult: Result,
                             _ nextPartialResult: (_ partialResult: Result, Element) async throws -> Result)
    async rethrows -> Result {
    var result = initialResult
    var it = makeAsyncIterator()
    while let e = try await it.next() { result = try await nextPartialResult(result, e) }
    return result
  }
  public func allSatisfy(_ predicate: (Element) async throws -> Bool) async rethrows -> Bool {
    return try await !contains { try await !predicate($0) }
  }
}

extension AsyncSequence where Element: Equatable {
  public func contains(_ search: Element) async rethrows -> Bool {
    return try await contains { $0 == search }
  }
}

// MARK: - dropFirst

@frozen
public struct AsyncDropFirstSequence<Base: AsyncSequence> {
  @usableFromInline let base: Base
  @usableFromInline let count: Int
  @usableFromInline init(_ base: Base, dropping count: Int) {
    self.base = base
    self.count = count
  }
}

extension AsyncDropFirstSequence: AsyncSequence {
  public typealias Element = Base.Element
  public typealias Failure = Base.Failure

  @frozen
  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline var baseIterator: Base.AsyncIterator
    @usableFromInline var count: Int
    @usableFromInline init(_ baseIterator: Base.AsyncIterator, count: Int) {
      self.baseIterator = baseIterator
      self.count = count
    }
    @inlinable
    public mutating func next() async rethrows -> Base.Element? {
      var remaining = count
      if remaining > 0 {
        count = 0
        while remaining > 0 {
          guard try await baseIterator.next() != nil else { return nil }
          remaining -= 1
        }
      }
      return try await baseIterator.next()
    }
  }

  @inlinable public __consuming func makeAsyncIterator() -> Iterator {
    return Iterator(base.makeAsyncIterator(), count: count)
  }
}

extension AsyncSequence {
  @inlinable
  public __consuming func dropFirst(_ count: Int = 1) -> AsyncDropFirstSequence<Self> {
    precondition(count >= 0, "Can't drop a negative number of elements from an async sequence")
    return AsyncDropFirstSequence(self, dropping: count)
  }
}

// MARK: - clocks as values

extension Clock where Self == ContinuousClock {
  public static var continuous: ContinuousClock { return ContinuousClock() }
}
extension Clock where Self == SuspendingClock {
  public static var suspending: SuspendingClock { return SuspendingClock() }
}
