// Combine: publishers, subscribers and the observable-object machinery
// SwiftUI is built on. Declarations follow Apple's documented API (their
// mangled names are what programs bind to); the implementation is ours and
// synchronous: values are delivered on the sender's thread unless a
// scheduler is involved.

// ---- core protocols ----------------------------------------------------------

public protocol Cancellable {
  func cancel()
}

public protocol Publisher<Output, Failure> {
  associatedtype Output
  associatedtype Failure: Error
  func receive<S: Subscriber>(subscriber: S) where Self.Failure == S.Failure, Self.Output == S.Input
}

public protocol Subscriber<Input, Failure>: CustomCombineIdentifierConvertible {
  associatedtype Input
  associatedtype Failure: Error
  func receive(subscription: Subscription)
  func receive(_ input: Self.Input) -> Subscribers.Demand
  func receive(completion: Subscribers.Completion<Self.Failure>)
}

public protocol Subscription: Cancellable, CustomCombineIdentifierConvertible {
  func request(_ demand: Subscribers.Demand)
}

public protocol CustomCombineIdentifierConvertible {
  var combineIdentifier: CombineIdentifier { get }
}
extension CustomCombineIdentifierConvertible where Self: AnyObject {
  public var combineIdentifier: CombineIdentifier { return CombineIdentifier(self) }
}

public struct CombineIdentifier: Hashable, CustomStringConvertible {
  private let value: UInt64
  private static var next: UInt64 = 0
  public init() {
    CombineIdentifier.next += 1
    value = CombineIdentifier.next
  }
  public init(_ obj: AnyObject) { value = UInt64(UInt(bitPattern: ObjectIdentifier(obj).hashValue)) }
  public var description: String { return "0x\(String(value, radix: 16))" }
}

public protocol ConnectablePublisher<Output, Failure>: Publisher {
  func connect() -> Cancellable
}

public protocol Subject<Output, Failure>: AnyObject, Publisher {
  func send(_ value: Self.Output)
  func send(completion: Subscribers.Completion<Self.Failure>)
  func send(subscription: Subscription)
}
extension Subject where Output == Void {
  public func send() { send(()) }
}

// ---- Subscribers ---------------------------------------------------------------------

public enum Subscribers {}

extension Subscribers {
  @frozen public enum Completion<Failure: Error> {
    case finished
    case failure(Failure)
  }

  /// How many more values a subscriber wants.
  @frozen public struct Demand: Equatable, Comparable, Hashable, CustomStringConvertible {
    @usableFromInline internal let rawValue: UInt
    @inlinable internal init(rawValue: UInt) { self.rawValue = min(UInt(Int.max) + 1, rawValue) }
    public static let unlimited = Demand(rawValue: UInt(Int.max) + 1)
    public static let none = Demand(rawValue: 0)
    @inlinable public static func max(_ value: Int) -> Demand { return Demand(rawValue: UInt(value)) }
    public var max: Int? { return self == .unlimited ? nil : Int(rawValue) }
    public var description: String { return self == .unlimited ? "unlimited" : "max(\(rawValue))" }
    public static func + (lhs: Demand, rhs: Demand) -> Demand {
      if lhs == .unlimited || rhs == .unlimited { return .unlimited }
      return Demand(rawValue: lhs.rawValue + rhs.rawValue)
    }
    public static func += (lhs: inout Demand, rhs: Demand) { lhs = lhs + rhs }
    public static func - (lhs: Demand, rhs: Demand) -> Demand {
      if lhs == .unlimited { return .unlimited }
      if rhs == .unlimited { return .none }
      return lhs.rawValue >= rhs.rawValue ? Demand(rawValue: lhs.rawValue - rhs.rawValue) : .none
    }
    public static func -= (lhs: inout Demand, rhs: Demand) { lhs = lhs - rhs }
    public static func < (lhs: Demand, rhs: Demand) -> Bool { return lhs.rawValue < rhs.rawValue }
  }

  /// The subscriber behind `sink`.
  public final class Sink<Input, Failure: Error>: Subscriber, Cancellable {
    public let receiveValue: (Input) -> Void
    public let receiveCompletion: (Subscribers.Completion<Failure>) -> Void
    private var subscription: Subscription?
    public init(receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
                receiveValue: @escaping (Input) -> Void) {
      self.receiveCompletion = receiveCompletion
      self.receiveValue = receiveValue
    }
    public func receive(subscription: Subscription) {
      self.subscription = subscription
      subscription.request(.unlimited)
    }
    public func receive(_ value: Input) -> Subscribers.Demand {
      receiveValue(value)
      return .none
    }
    public func receive(completion: Subscribers.Completion<Failure>) {
      receiveCompletion(completion)
      subscription = nil
    }
    public func cancel() {
      subscription?.cancel()
      subscription = nil
    }
  }
}

// ---- AnyCancellable -------------------------------------------------------------------

public final class AnyCancellable: Cancellable, Hashable {
  private var cancelBlock: (() -> Void)?
  public init(_ cancel: @escaping () -> Void) { cancelBlock = cancel }
  public init<C: Cancellable>(_ canceller: C) { cancelBlock = { canceller.cancel() } }
  deinit { cancel() }
  public func cancel() {
    let block = cancelBlock
    cancelBlock = nil
    block?()
  }
  public func store<C: RangeReplaceableCollection>(in collection: inout C) where C.Element == AnyCancellable {
    collection.append(self)
  }
  public func store(in set: inout Set<AnyCancellable>) { set.insert(self) }
  public static func == (lhs: AnyCancellable, rhs: AnyCancellable) -> Bool { return lhs === rhs }
  public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

// ---- a subject used by the concrete publishers below ----------------------------------

/// Fans values out to its current subscribers. Subscribers get unlimited
/// demand semantics: Combine's demand is honoured only by `Sink`-style
/// subscribers here, which ask for unlimited.
final class _Broadcast<Output, Failure: Error> {
  private final class Conduit: Subscription {
    weak var owner: _Broadcast?
    let send: (Output) -> Void
    let complete: (Subscribers.Completion<Failure>) -> Void
    init(owner: _Broadcast, send: @escaping (Output) -> Void,
         complete: @escaping (Subscribers.Completion<Failure>) -> Void) {
      self.owner = owner
      self.send = send
      self.complete = complete
    }
    func request(_ demand: Subscribers.Demand) {}
    func cancel() { owner?.remove(self) }
  }
  private var conduits: [Conduit] = []
  private var completion: Subscribers.Completion<Failure>?

  func subscribe<S: Subscriber>(_ subscriber: S) where S.Input == Output, S.Failure == Failure {
    let c = Conduit(owner: self, send: { _ = subscriber.receive($0) },
                    complete: { subscriber.receive(completion: $0) })
    if let done = completion {
      subscriber.receive(subscription: c)
      subscriber.receive(completion: done)
      return
    }
    conduits.append(c)
    subscriber.receive(subscription: c)
  }
  func send(_ value: Output) {
    for c in conduits { c.send(value) }
  }
  func send(completion: Subscribers.Completion<Failure>) {
    self.completion = completion
    let all = conduits
    conduits = []
    for c in all { c.complete(completion) }
  }
  private func remove(_ c: Conduit) { conduits.removeAll { $0 === c } }
}

// ---- subjects --------------------------------------------------------------------------

public final class PassthroughSubject<Output, Failure: Error>: Subject {
  private let hub = _Broadcast<Output, Failure>()
  public init() {}
  public func send(_ input: Output) { hub.send(input) }
  public func send(completion: Subscribers.Completion<Failure>) { hub.send(completion: completion) }
  public func send(subscription: Subscription) { subscription.request(.unlimited) }
  public func receive<S: Subscriber>(subscriber: S) where Output == S.Input, Failure == S.Failure {
    hub.subscribe(subscriber)
  }
}

public final class CurrentValueSubject<Output, Failure: Error>: Subject {
  private let hub = _Broadcast<Output, Failure>()
  public var value: Output {
    didSet { hub.send(value) }
  }
  public init(_ value: Output) { self.value = value }
  public func send(_ input: Output) { value = input }
  public func send(completion: Subscribers.Completion<Failure>) { hub.send(completion: completion) }
  public func send(subscription: Subscription) { subscription.request(.unlimited) }
  public func receive<S: Subscriber>(subscriber: S) where Output == S.Input, Failure == S.Failure {
    hub.subscribe(subscriber)
    _ = subscriber.receive(value)
  }
}

// ---- sink and assign -------------------------------------------------------------------

extension Publisher {
  public func sink(receiveCompletion: @escaping (Subscribers.Completion<Self.Failure>) -> Void,
                   receiveValue: @escaping (Self.Output) -> Void) -> AnyCancellable {
    let s = Subscribers.Sink<Output, Failure>(receiveCompletion: receiveCompletion, receiveValue: receiveValue)
    receive(subscriber: s)
    return AnyCancellable(s)
  }
}
extension Publisher where Self.Failure == Never {
  public func sink(receiveValue: @escaping (Self.Output) -> Void) -> AnyCancellable {
    return sink(receiveCompletion: { _ in }, receiveValue: receiveValue)
  }
  public func assign<Root>(to keyPath: ReferenceWritableKeyPath<Root, Self.Output>, on object: Root) -> AnyCancellable {
    return sink { object[keyPath: keyPath] = $0 }
  }
  /// Republishes into a `@Published` property's publisher; lives as long as
  /// the property.
  public func assign(to published: inout Published<Self.Output>.Publisher) {
    let target = published.subject
    let c = sink { target.value = $0 }
    published.subject.retained.append(c)
  }
}

// ---- type erasure ------------------------------------------------------------------------

@frozen public struct AnyPublisher<Output, Failure: Error>: Publisher, CustomStringConvertible {
  @usableFromInline internal let box: (AnySubscriberBox<Output, Failure>) -> Void
  public init<P: Publisher>(_ publisher: P) where Output == P.Output, Failure == P.Failure {
    box = { publisher.receive(subscriber: $0) }
  }
  public var description: String { return "AnyPublisher" }
  public func receive<S: Subscriber>(subscriber: S) where Output == S.Input, Failure == S.Failure {
    box(AnySubscriberBox(subscriber))
  }
}
public final class AnySubscriberBox<Input, Failure: Error>: Subscriber {
  private let onSubscription: (Subscription) -> Void
  private let onValue: (Input) -> Subscribers.Demand
  private let onCompletion: (Subscribers.Completion<Failure>) -> Void
  init<S: Subscriber>(_ s: S) where S.Input == Input, S.Failure == Failure {
    onSubscription = { s.receive(subscription: $0) }
    onValue = { s.receive($0) }
    onCompletion = { s.receive(completion: $0) }
  }
  public func receive(subscription: Subscription) { onSubscription(subscription) }
  public func receive(_ input: Input) -> Subscribers.Demand { return onValue(input) }
  public func receive(completion: Subscribers.Completion<Failure>) { onCompletion(completion) }
}
extension Publisher {
  public func eraseToAnyPublisher() -> AnyPublisher<Self.Output, Self.Failure> { return AnyPublisher(self) }
}

// ---- simple publishers ----------------------------------------------------------------------

public struct Just<Output>: Publisher {
  public typealias Failure = Never
  public let output: Output
  public init(_ output: Output) { self.output = output }
  public func receive<S: Subscriber>(subscriber: S) where Output == S.Input, S.Failure == Never {
    let subject = CurrentValueSubject<Output, Never>(output)
    subject.receive(subscriber: subscriber)
    subject.send(completion: .finished)
  }
}

public enum Publishers {}

extension Publishers {
  public struct Map<Upstream: Publisher, Output>: Publisher {
    public typealias Failure = Upstream.Failure
    public let upstream: Upstream
    public let transform: (Upstream.Output) -> Output
    public func receive<S: Subscriber>(subscriber: S) where Output == S.Input, S.Failure == Upstream.Failure {
      let subject = PassthroughSubject<Output, Failure>()
      subject.receive(subscriber: subscriber)
      let t = transform
      let c = upstream.sink(receiveCompletion: { subject.send(completion: $0) },
                            receiveValue: { subject.send(t($0)) })
      _keepAlive.append(c)
    }
  }

  public struct Drop<Upstream: Publisher>: Publisher {
    public typealias Output = Upstream.Output
    public typealias Failure = Upstream.Failure
    public let upstream: Upstream
    public let count: Int
    public init(upstream: Upstream, count: Int) {
      self.upstream = upstream
      self.count = count
    }
    public func receive<S: Subscriber>(subscriber: S) where Upstream.Failure == S.Failure, Upstream.Output == S.Input {
      let subject = PassthroughSubject<Output, Failure>()
      subject.receive(subscriber: subscriber)
      var remaining = count
      let c = upstream.sink(receiveCompletion: { subject.send(completion: $0) },
                            receiveValue: { v in if remaining > 0 { remaining -= 1 } else { subject.send(v) } })
      _keepAlive.append(c)
    }
  }

  public struct ReceiveOn<Upstream: Publisher, Context: Scheduler>: Publisher {
    public typealias Output = Upstream.Output
    public typealias Failure = Upstream.Failure
    public let upstream: Upstream
    public let scheduler: Context
    public let options: Context.SchedulerOptions?
    public init(upstream: Upstream, scheduler: Context, options: Context.SchedulerOptions?) {
      self.upstream = upstream
      self.scheduler = scheduler
      self.options = options
    }
    public func receive<S: Subscriber>(subscriber: S) where Upstream.Failure == S.Failure, Upstream.Output == S.Input {
      let subject = PassthroughSubject<Output, Failure>()
      subject.receive(subscriber: subscriber)
      let sched = scheduler
      let opts = options
      let c = upstream.sink(receiveCompletion: { done in sched.schedule(options: opts) { subject.send(completion: done) } },
                            receiveValue: { v in sched.schedule(options: opts) { subject.send(v) } })
      _keepAlive.append(c)
    }
  }

  public struct MergeMany<Upstream: Publisher>: Publisher {
    public typealias Output = Upstream.Output
    public typealias Failure = Upstream.Failure
    public let publishers: [Upstream]
    public init(_ upstream: Upstream...) { publishers = upstream }
    public init<S: Sequence>(_ upstream: S) where Upstream == S.Element { publishers = Array(upstream) }
    public func receive<S: Subscriber>(subscriber: S) where Upstream.Failure == S.Failure, Upstream.Output == S.Input {
      let subject = PassthroughSubject<Output, Failure>()
      subject.receive(subscriber: subscriber)
      for p in publishers {
        _keepAlive.append(p.sink(receiveCompletion: { _ in }, receiveValue: { subject.send($0) }))
      }
    }
  }

  public class Autoconnect<Upstream: ConnectablePublisher>: Publisher {
    public typealias Output = Upstream.Output
    public typealias Failure = Upstream.Failure
    public final let upstream: Upstream
    private var connection: Cancellable?
    public init(upstream: Upstream) { self.upstream = upstream }
    public func receive<S: Subscriber>(subscriber: S) where Upstream.Failure == S.Failure, Upstream.Output == S.Input {
      upstream.receive(subscriber: subscriber)
      if connection == nil { connection = upstream.connect() }
    }
  }
}

/// Operator subscriptions are kept alive for the life of the process: our
/// operators are built from subjects, and Combine's semantics (alive while
/// the downstream subscription is) are approximated this way.
nonisolated(unsafe) var _keepAlive: [AnyCancellable] = []

extension Publisher {
  public func map<T>(_ transform: @escaping (Self.Output) -> T) -> Publishers.Map<Self, T> {
    return Publishers.Map(upstream: self, transform: transform)
  }
  public func dropFirst(_ count: Int = 1) -> Publishers.Drop<Self> {
    return Publishers.Drop(upstream: self, count: count)
  }
  public func receive<S: Scheduler>(on scheduler: S, options: S.SchedulerOptions? = nil) -> Publishers.ReceiveOn<Self, S> {
    return Publishers.ReceiveOn(upstream: self, scheduler: scheduler, options: options)
  }
}
extension ConnectablePublisher where Self.Failure == Never {
  public func autoconnect() -> Publishers.Autoconnect<Self> { return Publishers.Autoconnect(upstream: self) }
}
extension ConnectablePublisher {
  public func autoconnect() -> Publishers.Autoconnect<Self> { return Publishers.Autoconnect(upstream: self) }
}

// ---- schedulers ------------------------------------------------------------------------------

public protocol SchedulerTimeIntervalConvertible {
  static func seconds(_ s: Int) -> Self
  static func seconds(_ s: Double) -> Self
  static func milliseconds(_ ms: Int) -> Self
  static func microseconds(_ us: Int) -> Self
  static func nanoseconds(_ ns: Int) -> Self
}

public protocol Scheduler<SchedulerTimeType> {
  associatedtype SchedulerTimeType: Strideable where SchedulerTimeType.Stride: SchedulerTimeIntervalConvertible
  associatedtype SchedulerOptions
  var now: SchedulerTimeType { get }
  var minimumTolerance: SchedulerTimeType.Stride { get }
  func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void)
  func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: SchedulerOptions?,
                _ action: @escaping () -> Void)
  func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, tolerance: SchedulerTimeType.Stride,
                options: SchedulerOptions?, _ action: @escaping () -> Void) -> Cancellable
}

/// Runs actions immediately on the calling thread.
public struct ImmediateScheduler: Scheduler {
  public struct SchedulerTimeType: Strideable {
    public struct Stride: SchedulerTimeIntervalConvertible, Comparable, SignedNumeric, ExpressibleByIntegerLiteral {
      public var magnitude: Int
      public init(_ value: Int) { magnitude = value }
      public init(integerLiteral value: Int) { magnitude = value }
      public init?<T: BinaryInteger>(exactly source: T) {
        guard let v = Int(exactly: source) else { return nil }
        magnitude = v
      }
      public static func seconds(_ s: Int) -> Stride { return Stride(0) }
      public static func seconds(_ s: Double) -> Stride { return Stride(0) }
      public static func milliseconds(_ ms: Int) -> Stride { return Stride(0) }
      public static func microseconds(_ us: Int) -> Stride { return Stride(0) }
      public static func nanoseconds(_ ns: Int) -> Stride { return Stride(0) }
      public static func < (l: Stride, r: Stride) -> Bool { return l.magnitude < r.magnitude }
      public static func + (l: Stride, r: Stride) -> Stride { return Stride(l.magnitude + r.magnitude) }
      public static func - (l: Stride, r: Stride) -> Stride { return Stride(l.magnitude - r.magnitude) }
      public static func * (l: Stride, r: Stride) -> Stride { return Stride(l.magnitude * r.magnitude) }
      public static func += (l: inout Stride, r: Stride) { l = l + r }
      public static func -= (l: inout Stride, r: Stride) { l = l - r }
      public static func *= (l: inout Stride, r: Stride) { l = l * r }
    }
    public static func < (l: SchedulerTimeType, r: SchedulerTimeType) -> Bool { return false }
    public func distance(to other: SchedulerTimeType) -> Stride { return Stride(0) }
    public func advanced(by n: Stride) -> SchedulerTimeType { return self }
  }
  public typealias SchedulerOptions = Never
  public static let shared = ImmediateScheduler()
  public var now: SchedulerTimeType { return SchedulerTimeType() }
  public var minimumTolerance: SchedulerTimeType.Stride { return 0 }
  public func schedule(options: Never?, _ action: @escaping () -> Void) { action() }
  public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: Never?,
                       _ action: @escaping () -> Void) { action() }
  public func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride,
                       tolerance: SchedulerTimeType.Stride, options: Never?,
                       _ action: @escaping () -> Void) -> Cancellable {
    action()
    return AnyCancellable {}
  }
}

// ---- ObservableObject and Published ------------------------------------------------------------

public final class ObservableObjectPublisher: Publisher {
  public typealias Output = Void
  public typealias Failure = Never
  private let hub = _Broadcast<Void, Never>()
  public init() {}
  public func receive<S: Subscriber>(subscriber: S) where S.Input == Void, S.Failure == Never {
    hub.subscribe(subscriber)
  }
  public func send() { hub.send(()) }
}

public protocol ObservableObject: AnyObject {
  associatedtype ObjectWillChangePublisher: Publisher = ObservableObjectPublisher
  where Self.ObjectWillChangePublisher.Failure == Never
  var objectWillChange: Self.ObjectWillChangePublisher { get }
}

/// Each observable object's default publisher, created on first use. Kept
/// in a side table keyed by the object's identity (Apple stores it in the
/// object's @Published storage; programs cannot tell the difference).
nonisolated(unsafe) private var objectPublishers: [ObjectIdentifier: ObservableObjectPublisher] = [:]

extension ObservableObject where Self.ObjectWillChangePublisher == ObservableObjectPublisher {
  public var objectWillChange: ObservableObjectPublisher {
    let id = ObjectIdentifier(self)
    if let p = objectPublishers[id] { return p }
    let p = ObservableObjectPublisher()
    objectPublishers[id] = p
    return p
  }
}

@propertyWrapper
public struct Published<Value> {
  /// The value lives in a box shared by the publisher, so that the
  /// enclosing-instance accessors can update both.
  final class Box {
    var value: Value {
      didSet { hub.send(value) }
    }
    let hub = _Broadcast<Value, Never>()
    var retained: [AnyCancellable] = []
    init(_ value: Value) { self.value = value }
  }
  var box: Box

  public init(wrappedValue: Value) { box = Box(wrappedValue) }
  public init(initialValue: Value) { box = Box(initialValue) }

  @available(*, unavailable, message: "@Published is only available on properties of classes")
  public var wrappedValue: Value {
    get { fatalError() }
    set { fatalError() }
  }

  public struct Publisher: Combine.Publisher {
    public typealias Output = Value
    public typealias Failure = Never
    let subject: Box
    init(_ box: Box) { subject = box }
    public func receive<S: Subscriber>(subscriber: S) where Value == S.Input, S.Failure == Never {
      subject.hub.subscribe(subscriber)
      _ = subscriber.receive(subject.value)
    }
  }

  public var projectedValue: Publisher {
    mutating get { return Publisher(box) }
    set { box = newValue.subject }
  }

  public static subscript<EnclosingSelf: AnyObject>(
    _enclosingInstance object: EnclosingSelf,
    wrapped wrappedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Value>,
    storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Published<Value>>
  ) -> Value {
    get { return object[keyPath: storageKeyPath].box.value }
    set {
      if let observable = object as? any ObservableObject { _sendWillChange(observable) }
      object[keyPath: storageKeyPath].box.value = newValue
    }
  }
}

private func _sendWillChange<T: ObservableObject>(_ object: T) {
  if let p = object.objectWillChange as? ObservableObjectPublisher { p.send() }
}
