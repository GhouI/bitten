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
  /// The host whose graph keeps this state (none outside a graph).
  weak var owner: _RenderContext?
  init(_ value: Value) { self.value = value }
  override func get() -> Value { return value }
  override func set(_ value: Value, transaction: Transaction) {
    let same = _bn_sameValue(self.value, value)
    self.value = value
    // As SwiftUI: storing the value already there changes nothing on screen.
    if !same { _bn_invalidate(owner) }
  }
}

/// A change to state kept in `owner`'s graph: that host rebuilds (it hands
/// new values on to any it hosts in turn); without one, every host does.
internal func _bn_invalidate(_ owner: _RenderContext?) {
  if let o = owner { o.invalidate() } else { _GraphHost.invalidate() }
}

/// Whether `a` and `b` are the same value, as far as can be told: equal
/// when the type is Equatable (false when it can't be compared).
internal func _bn_sameValue<T>(_ a: T, _ b: T) -> Bool {
  guard let ea = a as? any Equatable else { return false }
  return ea._bn_isEqual(to: b)
}
extension Equatable {
  fileprivate func _bn_isEqual(to other: Any) -> Bool {
    guard let o = other as? Self else { return false }
    return self == o
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
    box.owner = inputs.base.context
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
    // Weakly: the object usually outlives the view, and holding the host's
    // context from its publisher would keep the whole tree alive.
    w.cancellable = o.objectWillChange.sink { [weak context] _ in context?.invalidate() }
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
    let me = self
    let box = inputs.base.context.store(key) { _LazyStateBox(me._resolved()) }
    box.owner = inputs.base.context
    _box = box
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
    return _AppHost.shared.makeDelegate() as! DelegateType
  }
}

/// State whose initial value is computed on first use (`@State var model =
/// Model()` for observable classes). Frozen with its storage first, as
/// Apple's: programs write `.value(...)` storage into it directly.
@frozen @propertyWrapper
public struct LazyState<Value>: DynamicProperty {
  @usableFromInline internal enum Storage {
    case value(Value)
    case initially(() -> Value)
  }
  @usableFromInline internal var storage: Storage
  /// The graph's storage, once the view is installed.
  @usableFromInline internal var _box: _LazyStateBox<Value>?

  public init(wrappedValue thunk: @autoclosure @escaping () -> Value) {
    storage = .initially(thunk)
    _box = nil
  }
  /// The value, made from the initial thunk if needed.
  internal func _resolved() -> Value {
    switch storage {
    case .value(let v): return v
    case .initially(let make): return make()
    }
  }
  internal var _location: _LazyStateBox<Value> {
    if let b = _box { return b }
    return _LazyStateBox(_resolved())
  }
  public var wrappedValue: Value {
    get { return _location.value }
    nonmutating set { _location.value = newValue }
  }
  public var projectedValue: Binding<Value> {
    let b = _location
    return Binding(get: { b.value }, set: { b.value = $0 })
  }
}

@usableFromInline
internal final class _LazyStateBox<Value> {
  var value: Value {
    didSet { if !_bn_sameValue(oldValue, value) { _bn_invalidate(owner) } }
  }
  /// The host whose graph keeps this state.
  weak var owner: _RenderContext?
  init(_ v: Value) { value = v }
}
