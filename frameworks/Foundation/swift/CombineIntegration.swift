// Foundation's Combine integration: NotificationCenter and timer
// publishers, key-value-observing publishers, and RunLoop as a Scheduler.
//
// Key-value observing itself is not implemented, so a KVO publisher sends
// the current value (with .initial) and then only what -willChange/-didChange
// style notifications would have produced: nothing.

import Combine

/// A subscription that hands values to one subscriber as demand allows.
internal final class _FoundationSubscription<Input, Failure: Error>: Subscription {
  private var lock = NSLock()
  private var deliver: ((Input) -> Subscribers.Demand)?
  private var complete: ((Subscribers.Completion<Failure>) -> Void)?
  private var demand: Subscribers.Demand = .none
  internal var onCancel: (() -> Void)?

  init<S: Subscriber>(_ s: S) where S.Input == Input, S.Failure == Failure {
    deliver = { s.receive($0) }
    complete = { s.receive(completion: $0) }
  }

  func request(_ d: Subscribers.Demand) {
    lock.lock()
    demand += d
    lock.unlock()
  }
  func cancel() {
    lock.lock()
    let c = onCancel
    onCancel = nil
    deliver = nil
    complete = nil
    lock.unlock()
    c?()
  }
  func send(_ value: Input) {
    lock.lock()
    guard let d = deliver, demand > .none else { lock.unlock(); return }
    demand -= .max(1)
    lock.unlock()
    let more = d(value)
    lock.lock()
    demand += more
    lock.unlock()
  }
  func finish(_ completion: Subscribers.Completion<Failure>) {
    lock.lock()
    let c = complete
    deliver = nil
    complete = nil
    lock.unlock()
    c?(completion)
  }
}

// MARK: - NotificationCenter

extension NotificationCenter {
  public struct Publisher: Combine.Publisher {
    public typealias Output = Notification
    public typealias Failure = Never
    public let center: NotificationCenter
    public let name: Notification.Name
    public let object: AnyObject?

    public init(center: NotificationCenter, name: Notification.Name, object: AnyObject? = nil) {
      self.center = center
      self.name = name
      self.object = object
    }

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Notification, S.Failure == Never {
      let sub = _FoundationSubscription<Notification, Never>(subscriber)
      let token = center.addObserver(forName: name, object: object, queue: nil) { note in sub.send(note) }
      let center = self.center
      sub.onCancel = { center.removeObserver(token) }
      subscriber.receive(subscription: sub)
    }
  }

  public func publisher(for name: Notification.Name, object: AnyObject? = nil) -> NotificationCenter.Publisher {
    return Publisher(center: self, name: name, object: object)
  }
}

// MARK: - key-value observing publishers

public protocol _KeyValueCodingAndObservingPublishing {}
extension NSObject: _KeyValueCodingAndObservingPublishing {}

extension _KeyValueCodingAndObservingPublishing where Self: NSObject {
  public func publisher<Value>(for keyPath: KeyPath<Self, Value>,
                               options: NSKeyValueObservingOptions = [.initial, .new])
    -> NSObject.KeyValueObservingPublisher<Self, Value> {
    return NSObject.KeyValueObservingPublisher(object: self, keyPath: keyPath, options: options)
  }
}

extension NSObject {
  public struct KeyValueObservingPublisher<Subject: NSObject, Value>: Combine.Publisher {
    public typealias Output = Value
    public typealias Failure = Never
    public let object: Subject
    public let keyPath: KeyPath<Subject, Value>
    public let options: NSKeyValueObservingOptions

    public init(object: Subject, keyPath: KeyPath<Subject, Value>, options: NSKeyValueObservingOptions) {
      self.object = object
      self.keyPath = keyPath
      self.options = options
    }

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Value, S.Failure == Never {
      let sub = _FoundationSubscription<Value, Never>(subscriber)
      subscriber.receive(subscription: sub)
      if options.contains(.initial) { sub.send(object[keyPath: keyPath]) }
    }
  }
}

// MARK: - RunLoop as a Scheduler

extension RunLoop: Scheduler {
  public struct SchedulerTimeType: Strideable, Codable, Hashable {
    public var date: Date
    public init(_ date: Date) { self.date = date }

    public func distance(to other: SchedulerTimeType) -> Stride {
      return Stride(floatLiteral: other.date.timeIntervalSince(date))
    }
    public func advanced(by n: Stride) -> SchedulerTimeType { return SchedulerTimeType(date.addingTimeInterval(n.timeInterval)) }
    public static func < (a: SchedulerTimeType, b: SchedulerTimeType) -> Bool { return a.date < b.date }

    public struct Stride: ExpressibleByFloatLiteral, Comparable, SignedNumeric, Codable, SchedulerTimeIntervalConvertible {
      public typealias FloatLiteralType = TimeInterval
      public typealias IntegerLiteralType = TimeInterval
      public typealias Magnitude = TimeInterval
      public var magnitude: TimeInterval
      public var timeInterval: TimeInterval { return magnitude }

      public init(_ timeInterval: TimeInterval) { magnitude = timeInterval }
      public init(floatLiteral value: TimeInterval) { magnitude = value }
      public init(integerLiteral value: TimeInterval) { magnitude = value }
      public init?<T: BinaryInteger>(exactly source: T) {
        guard let v = Double(exactly: source) else { return nil }
        magnitude = v
      }

      public static func < (a: Stride, b: Stride) -> Bool { return a.magnitude < b.magnitude }
      public static func + (a: Stride, b: Stride) -> Stride { return Stride(a.magnitude + b.magnitude) }
      public static func - (a: Stride, b: Stride) -> Stride { return Stride(a.magnitude - b.magnitude) }
      public static func * (a: Stride, b: Stride) -> Stride { return Stride(a.magnitude * b.magnitude) }
      public static func += (a: inout Stride, b: Stride) { a = a + b }
      public static func -= (a: inout Stride, b: Stride) { a = a - b }
      public static func *= (a: inout Stride, b: Stride) { a = a * b }

      public static func seconds(_ s: Int) -> Stride { return Stride(Double(s)) }
      public static func seconds(_ s: Double) -> Stride { return Stride(s) }
      public static func milliseconds(_ ms: Int) -> Stride { return Stride(Double(ms) / 1e3) }
      public static func microseconds(_ us: Int) -> Stride { return Stride(Double(us) / 1e6) }
      public static func nanoseconds(_ ns: Int) -> Stride { return Stride(Double(ns) / 1e9) }
    }
  }

  public struct SchedulerOptions {}

  public var now: SchedulerTimeType { return SchedulerTimeType(Date()) }
  public var minimumTolerance: SchedulerTimeType.Stride { return 0.0 }

  public func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) {
    perform(action)
  }
  public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: SchedulerOptions?,
                       _ action: @escaping () -> Void) {
    let t = Timer(fire: date.date, interval: 0, repeats: false) { _ in action() }
    t.tolerance = tolerance.timeInterval
    add(t, forMode: .default)
  }
  public func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, tolerance: SchedulerTimeType.Stride,
                       options: SchedulerOptions?, _ action: @escaping () -> Void) -> Cancellable {
    let t = Timer(fire: date.date, interval: interval.timeInterval, repeats: true) { _ in action() }
    t.tolerance = tolerance.timeInterval
    add(t, forMode: .default)
    return AnyCancellable { t.invalidate() }
  }
}

// MARK: - Timer publisher

extension Timer {
  public static func publish(every interval: TimeInterval, tolerance: TimeInterval? = nil, on runLoop: RunLoop,
                             in mode: RunLoop.Mode, options: RunLoop.SchedulerOptions? = nil) -> TimerPublisher {
    return TimerPublisher(interval: interval, tolerance: tolerance, runLoop: runLoop, mode: mode, options: options)
  }

  public final class TimerPublisher: ConnectablePublisher {
    public typealias Output = Date
    public typealias Failure = Never
    public let interval: TimeInterval
    public let tolerance: TimeInterval?
    public let runLoop: RunLoop
    public let mode: RunLoop.Mode
    public let options: RunLoop.SchedulerOptions?

    private let lock = NSLock()
    private var subscriptions: [_FoundationSubscription<Date, Never>] = []
    private var timer: Timer?

    public init(interval: TimeInterval, tolerance: TimeInterval? = nil, runLoop: RunLoop, mode: RunLoop.Mode,
                options: RunLoop.SchedulerOptions? = nil) {
      self.interval = interval
      self.tolerance = tolerance
      self.runLoop = runLoop
      self.mode = mode
      self.options = options
    }

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Date, S.Failure == Never {
      let sub = _FoundationSubscription<Date, Never>(subscriber)
      lock.lock()
      subscriptions.append(sub)
      lock.unlock()
      sub.onCancel = { [weak self, weak sub] in
        guard let self = self, let sub = sub else { return }
        self.lock.lock()
        self.subscriptions.removeAll { $0 === sub }
        self.lock.unlock()
      }
      subscriber.receive(subscription: sub)
    }

    public func connect() -> Cancellable {
      let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.fire() }
      if let tol = tolerance { t.tolerance = tol }
      lock.lock()
      timer = t
      lock.unlock()
      runLoop.add(t, forMode: mode)
      return AnyCancellable { t.invalidate() }
    }

    private func fire() {
      lock.lock()
      let subs = subscriptions
      lock.unlock()
      let now = Date()
      for s in subs { s.send(now) }
    }
  }
}
