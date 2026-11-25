// Clocks: ContinuousClock (counts through sleep) and SuspendingClock, their
// Instants, and sleeping until an instant. Time comes from the runtime's
// swift_get_time; sleeping parks the task in a continuation that a
// dispatch timer resumes.

import Swift

public protocol Clock<Duration>: Sendable {
  associatedtype Duration
  associatedtype Instant: InstantProtocol where Self.Instant.Duration == Self.Duration
  var now: Instant { get }
  var minimumResolution: Instant.Duration { get }
  func sleep(until deadline: Instant, tolerance: Instant.Duration?) async throws
}

@_silgen_name("swift_get_time")
internal func _getTime(_ seconds: UnsafeMutablePointer<Int64>, _ nanoseconds: UnsafeMutablePointer<Int64>,
                       _ clock: CInt)

internal func _now(_ clock: CInt) -> Duration {
  var s: Int64 = 0
  var ns: Int64 = 0
  _getTime(&s, &ns, clock)
  return Duration.seconds(s) + Duration.nanoseconds(ns)
}

@_silgen_name("bitten_concurrency_after_f")
internal func _after(_ nanoseconds: UInt64, _ context: UnsafeMutableRawPointer,
                     _ fn: @convention(c) (UnsafeMutableRawPointer) -> Void)

/// Suspends the current task for `nanoseconds`.
internal func _sleep(nanoseconds: UInt64) async {
  await withUnsafeContinuation { (c: UnsafeContinuation<Void, Never>) in
    final class Box {
      let c: UnsafeContinuation<Void, Never>
      init(_ c: UnsafeContinuation<Void, Never>) { self.c = c }
    }
    let ctx = Unmanaged.passRetained(Box(c)).toOpaque()
    _after(nanoseconds, ctx) { raw in
      let box = Unmanaged<Box>.fromOpaque(raw).takeRetainedValue()
      box.c.resume()
    }
  }
}

internal func _nanoseconds(_ d: Duration) -> UInt64 {
  if d <= .zero { return 0 }
  let c = d.components
  return UInt64(c.seconds) &* 1_000_000_000 &+ UInt64(c.attoseconds / 1_000_000_000)
}

public struct ContinuousClock: Clock, Sendable {
  @frozen public struct Instant: Sendable {
    internal var _value: Swift.Duration
    internal init(_value: Swift.Duration) { self._value = _value }
  }
  public init() {}
  public var now: Instant { return ContinuousClock.now }
  public static var now: Instant { return Instant(_value: _now(1)) }
  public var minimumResolution: Swift.Duration { return .nanoseconds(1) }
  public func sleep(until deadline: Instant, tolerance: Swift.Duration? = nil) async throws {
    await _sleep(nanoseconds: _nanoseconds(deadline._value - now._value))
  }
}

extension ContinuousClock.Instant: InstantProtocol {
  public static var now: ContinuousClock.Instant { return ContinuousClock.now }
  public func advanced(by duration: Swift.Duration) -> ContinuousClock.Instant {
    return ContinuousClock.Instant(_value: _value + duration)
  }
  public func duration(to other: ContinuousClock.Instant) -> Swift.Duration { return other._value - _value }
  public static func == (lhs: ContinuousClock.Instant, rhs: ContinuousClock.Instant) -> Bool { return lhs._value == rhs._value }
  public static func < (lhs: ContinuousClock.Instant, rhs: ContinuousClock.Instant) -> Bool { return lhs._value < rhs._value }
  public func hash(into hasher: inout Hasher) { hasher.combine(_value) }
  public static func + (lhs: ContinuousClock.Instant, rhs: Swift.Duration) -> ContinuousClock.Instant { return lhs.advanced(by: rhs) }
  public static func - (lhs: ContinuousClock.Instant, rhs: Swift.Duration) -> ContinuousClock.Instant {
    return lhs.advanced(by: .zero - rhs)
  }
  public static func - (lhs: ContinuousClock.Instant, rhs: ContinuousClock.Instant) -> Swift.Duration {
    return rhs.duration(to: lhs)
  }
}

public struct SuspendingClock: Clock, Sendable {
  @frozen public struct Instant: Sendable {
    internal var _value: Swift.Duration
    internal init(_value: Swift.Duration) { self._value = _value }
  }
  public init() {}
  public var now: Instant { return SuspendingClock.now }
  public static var now: Instant { return Instant(_value: _now(2)) }
  public var minimumResolution: Swift.Duration { return .nanoseconds(1) }
  public func sleep(until deadline: Instant, tolerance: Swift.Duration? = nil) async throws {
    await _sleep(nanoseconds: _nanoseconds(deadline._value - now._value))
  }
}

extension SuspendingClock.Instant: InstantProtocol {
  public static var now: SuspendingClock.Instant { return SuspendingClock.now }
  public func advanced(by duration: Swift.Duration) -> SuspendingClock.Instant {
    return SuspendingClock.Instant(_value: _value + duration)
  }
  public func duration(to other: SuspendingClock.Instant) -> Swift.Duration { return other._value - _value }
  public static func == (lhs: SuspendingClock.Instant, rhs: SuspendingClock.Instant) -> Bool { return lhs._value == rhs._value }
  public static func < (lhs: SuspendingClock.Instant, rhs: SuspendingClock.Instant) -> Bool { return lhs._value < rhs._value }
  public func hash(into hasher: inout Hasher) { hasher.combine(_value) }
  public static func + (lhs: SuspendingClock.Instant, rhs: Swift.Duration) -> SuspendingClock.Instant { return lhs.advanced(by: rhs) }
  public static func - (lhs: SuspendingClock.Instant, rhs: Swift.Duration) -> SuspendingClock.Instant {
    return lhs.advanced(by: .zero - rhs)
  }
  public static func - (lhs: SuspendingClock.Instant, rhs: SuspendingClock.Instant) -> Swift.Duration {
    return rhs.duration(to: lhs)
  }
}

extension Clock {
  public func measure(_ work: () throws -> Void) rethrows -> Instant.Duration {
    let start = now
    try work()
    return start.duration(to: now)
  }
}

extension Task where Success == Never, Failure == Never {
  public static func sleep<C: Clock>(until deadline: C.Instant, tolerance: C.Instant.Duration? = nil,
                                     clock: C = ContinuousClock()) async throws {
    try await clock.sleep(until: deadline, tolerance: tolerance)
  }
  public static func sleep(for duration: Duration) async throws {
    await _sleep(nanoseconds: _nanoseconds(duration))
  }
  public static func sleep(nanoseconds duration: UInt64) async throws {
    await _sleep(nanoseconds: duration)
  }
}
