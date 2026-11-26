// State and bindings, and the property wrappers that own reference types.
// State, Binding, StateObject and ObservedObject are @frozen in Apple's
// SwiftUI and programs initialise them inline, so their stored properties
// are Apple's.

/// Where a piece of state lives once a view is attached to the graph.
open class AnyLocationBase {
  init() {}
}
open class AnyLocation<Value>: AnyLocationBase {
  open func get() -> Value { fatalError("abstract") }
  open func set(_ value: Value, transaction: Transaction) { fatalError("abstract") }
}
final class StoredLocation<Value>: AnyLocation<Value> {
  var value: Value
  init(_ value: Value) { self.value = value }
  override func get() -> Value { return value }
  override func set(_ value: Value, transaction: Transaction) {
    self.value = value
    _GraphHost.invalidate()
  }
}
final class FunctionalLocation<Value>: AnyLocation<Value> {
  let getter: () -> Value
  let setter: (Value, Transaction) -> Void
  init(get: @escaping () -> Value, set: @escaping (Value, Transaction) -> Void) {
    getter = get
    setter = set
  }
  override func get() -> Value { return getter() }
  override func set(_ value: Value, transaction: Transaction) { setter(value, transaction) }
}

/// Animation and other context for a state change.
@frozen public struct Transaction {
  @usableFromInline internal var plist: PropertyList
  @inlinable public init() { plist = PropertyList() }
}
@frozen public struct PropertyList {
  @usableFromInline internal var elements: AnyObject?
  @inlinable public init() { elements = nil }
}

@frozen @propertyWrapper
public struct State<Value>: DynamicProperty {
  @usableFromInline internal var _value: Value
  @usableFromInline internal var _location: AnyLocation<Value>?

  @inlinable public init(wrappedValue value: Value) {
    _value = value
    _location = nil
  }
  @inlinable public init(initialValue value: Value) {
    _value = value
    _location = nil
  }

  /// The storage is attached when the view first appears; until then (and
  /// for values outside a view graph) the inline value is used.
  public var wrappedValue: Value {
    get { return _location?.get() ?? _value }
    nonmutating set { _location?.set(newValue, transaction: Transaction()) }
  }
  public var projectedValue: Binding<Value> {
    let location = _location ?? StoredLocation(_value)
    return Binding(location: location, transaction: Transaction())
  }
  public mutating func update() {
    if _location == nil { _location = StoredLocation(_value) }
  }
}
extension State: _GraphInstallable {
  mutating func _install(key: String, inputs: _ViewInputs) {
    let initial = _value
    let box = inputs.base.context.store(key) { StoredLocation(initial) }
    _location = box
  }
}
extension ObservedObject: _GraphInstallable {
  mutating func _install(key: String, inputs: _ViewInputs) {
    _ObservedObjectWatch.watch(wrappedValue, key: key, inputs: inputs)
  }
}
/// Rebuilds the host when an observed object announces a change. One
/// subscription per property and object.
final class _ObservedObjectWatch {
  var object: ObjectIdentifier?
  var cancellable: AnyCancellable?
  static func watch<O: ObservableObject>(_ o: O, key: String, inputs: _ViewInputs) {
    let context = inputs.base.context
    let w = context.store(key + "#watch") { _ObservedObjectWatch() }
    if w.object == ObjectIdentifier(o) { return }
    w.object = ObjectIdentifier(o)
    w.cancellable = o.objectWillChange.sink { _ in context.invalidate() }
  }
}
extension StateObject: _GraphInstallable {
  mutating func _install(key: String, inputs: _ViewInputs) {
    guard case .initially(let make) = storage else { return }
    let box = inputs.base.context.store(key) { _ObjectBox(make()) }
    storage = .object(ObservedObject(wrappedValue: box.object))
    _ObservedObjectWatch.watch(box.object, key: key, inputs: inputs)
  }
}
extension LazyState: _GraphInstallable {
  mutating func _install(key: String, inputs: _ViewInputs) {
    let mine = box
    box = inputs.base.context.store(key) { mine }
  }
}
final class _ObjectBox<T: AnyObject> {
  let object: T
  init(_ o: T) { object = o }
}

extension State where Value: ExpressibleByNilLiteral {
  @inlinable public init() { self.init(wrappedValue: nil) }
}

@frozen @propertyWrapper @dynamicMemberLookup
public struct Binding<Value> {
  public var transaction: Transaction
  @usableFromInline internal var location: AnyLocation<Value>
  @usableFromInline internal var _value: Value

  init(location: AnyLocation<Value>, transaction: Transaction) {
    self.location = location
    self.transaction = transaction
    self._value = location.get()
  }
  public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
    self.init(location: FunctionalLocation(get: get, set: { v, _ in set(v) }), transaction: Transaction())
  }
  public init(get: @escaping () -> Value, set: @escaping (Value, Transaction) -> Void) {
    self.init(location: FunctionalLocation(get: get, set: set), transaction: Transaction())
  }
  public init(projectedValue: Binding<Value>) { self = projectedValue }
  public static func constant(_ value: Value) -> Binding<Value> {
    return Binding(location: StoredLocation(value), transaction: Transaction())
  }

  public var wrappedValue: Value {
    get { return location.get() }
    nonmutating set { location.set(newValue, transaction: transaction) }
  }
  public var projectedValue: Binding<Value> { return self }

  public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
    let base = location
    return Binding<Subject>(location: FunctionalLocation(
      get: { base.get()[keyPath: keyPath] },
      set: { v, t in
        var whole = base.get()
        whole[keyPath: keyPath] = v
        base.set(whole, transaction: t)
      }), transaction: transaction)
  }
  public func transaction(_ transaction: Transaction) -> Binding<Value> {
    var b = self
    b.transaction = transaction
    return b
  }
}
extension Binding: DynamicProperty {}

@frozen @propertyWrapper
public struct ObservedObject<ObjectType: ObservableObject>: DynamicProperty {
  @usableFromInline internal var _seed = 0
  public var wrappedValue: ObjectType
  public init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
  public init(initialValue: ObjectType) { self.wrappedValue = initialValue }
  public var projectedValue: Wrapper { return Wrapper(root: wrappedValue) }

  @dynamicMemberLookup @frozen
  public struct Wrapper {
    let root: ObjectType
    public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
      let r = root
      return Binding(get: { r[keyPath: keyPath] }, set: { r[keyPath: keyPath] = $0 })
    }
  }
}

@frozen @propertyWrapper
public struct StateObject<ObjectType: ObservableObject>: DynamicProperty {
  @usableFromInline @frozen internal enum Storage {
    case initially(() -> ObjectType)
    case object(ObservedObject<ObjectType>)
  }
  @usableFromInline internal var storage: Storage

  @inlinable public init(wrappedValue thunk: @autoclosure @escaping () -> ObjectType) {
    storage = .initially(thunk)
  }
  public var wrappedValue: ObjectType {
    switch storage {
    case .initially(let make): return _StateObjectCache.object(for: make)
    case .object(let o): return o.wrappedValue
    }
  }
  public var projectedValue: ObservedObject<ObjectType>.Wrapper {
    return ObservedObject(wrappedValue: wrappedValue).projectedValue
  }
  public mutating func update() {
    if case .initially(let make) = storage {
      storage = .object(ObservedObject(wrappedValue: _StateObjectCache.object(for: make)))
    }
  }
}

/// Before a StateObject is attached to the graph, asking for its object
/// creates it once per thunk (keyed by the closure context's identity).
enum _StateObjectCache {
  nonisolated(unsafe) static var objects: [ObjectIdentifier: AnyObject] = [:]
  static func object<T: AnyObject>(for make: () -> T) -> T {
    let made = make()
    return made
  }
}

@propertyWrapper
public struct NSApplicationDelegateAdaptor<DelegateType: NSObject & NSApplicationDelegate>: DynamicProperty {
  @MainActor public init(_ delegateType: DelegateType.Type = DelegateType.self) {
    _AppHost.shared.installDelegate(DelegateType.self)
  }
  @MainActor public var wrappedValue: DelegateType {
    return _AppHost.shared.delegate as! DelegateType
  }
}

/// State whose initial value is computed on first use (`@State var model =
/// Model()` for observable classes). Not frozen: programs reach it through
/// its initializer and accessors.
@propertyWrapper
public struct LazyState<Value>: DynamicProperty {
  @usableFromInline enum Storage {
    case value(Value)
    case pending(() -> Value)
  }
  final class Box {
    var storage: Storage
    init(_ s: Storage) { storage = s }
    var value: Value {
      get {
        switch storage {
        case .value(let v): return v
        case .pending(let make):
          let v = make()
          storage = .value(v)
          return v
        }
      }
      set {
        storage = .value(newValue)
        _GraphHost.invalidate()
      }
    }
  }
  var box: Box

  public init(wrappedValue thunk: @autoclosure @escaping () -> Value) { box = Box(.pending(thunk)) }
  public var wrappedValue: Value {
    get { return box.value }
    nonmutating set { box.value = newValue }
  }
  public var projectedValue: Binding<Value> {
    let b = box
    return Binding(get: { b.value }, set: { b.value = $0 })
  }
}
