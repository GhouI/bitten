// Dictionary: one word, a _BridgeStorage of either native storage
// (__RawDictionaryStorage, see DictionaryStorage.swift) or a bridged
// NSDictionary (__CocoaDictionary, which needs Foundation and is not
// implemented yet; see DictionaryCocoa.swift). Everything below is built
// on _NativeDictionary. Mutations check uniqueness first and copy shared
// storage (copy-on-write).

@frozen @_eagerMove
public struct Dictionary<Key: Hashable, Value> {
  public typealias Element = (key: Key, value: Value)

  @usableFromInline
  internal var _variant: _Variant

  @inlinable
  internal init(_native: __owned _NativeDictionary<Key, Value>) {
    _variant = _Variant(native: _native)
  }

  @inlinable
  internal init(_cocoa: __owned __CocoaDictionary) {
    _variant = _Variant(cocoa: _cocoa)
  }

  @inlinable
  public init() {
    self.init(_native: _NativeDictionary())
  }

  public init(minimumCapacity: Int) {
    _variant = _Variant(native: _NativeDictionary(capacity: minimumCapacity))
  }

  @inlinable
  public init<S: Sequence>(uniqueKeysWithValues keysAndValues: __owned S)
    where S.Element == (Key, Value) {
    if let d = keysAndValues as? Dictionary<Key, Value> {
      self = d
      return
    }
    var native = _NativeDictionary<Key, Value>(capacity: keysAndValues.underestimatedCount)
    for (key, value) in keysAndValues {
      let (bucket, found) = native.mutatingFind(key, isUnique: true)
      _precondition(!found, "Dictionary init(uniqueKeysWithValues:) found duplicate keys")
      native._insert(at: bucket, key: key, value: value)
    }
    self.init(_native: native)
  }

  @inlinable
  public init<S: Sequence>(
    _ keysAndValues: __owned S,
    uniquingKeysWith combine: (Value, Value) throws -> Value
  ) rethrows where S.Element == (Key, Value) {
    var native = _NativeDictionary<Key, Value>(capacity: keysAndValues.underestimatedCount)
    try native.merge(keysAndValues, isUnique: true, uniquingKeysWith: combine)
    self.init(_native: native)
  }
}

// ---- the variant ---------------------------------------------------------------------------

extension Dictionary {
  @usableFromInline @frozen
  internal struct _Variant {
    @usableFromInline
    internal var object: _BridgeStorage<__RawDictionaryStorage>

    @inlinable @inline(__always)
    internal init(native: __owned _NativeDictionary<Key, Value>) {
      self.object = _BridgeStorage(native: native._storage)
    }

    /// A placeholder that owns nothing, for while the real value is
    /// borrowed out during a mutation.
    @inlinable @inline(__always)
    internal init(dummy: Void) {
      self.object = _BridgeStorage(taggedPayload: 0)
    }

    @inlinable @inline(__always)
    internal init(cocoa: __owned __CocoaDictionary) {
      self.object = _BridgeStorage(objC: cocoa.object)
    }
  }
}

extension Dictionary._Variant {
  /// True when neither type can be a class, so the dictionary can never
  /// be a bridged NSDictionary.
  @usableFromInline @_transparent
  internal var guaranteedNative: Bool {
    return _canBeClass(Key.self) == 0 || _canBeClass(Value.self) == 0
  }

  @inlinable
  internal mutating func isUniquelyReferenced() -> Bool {
    return object.isUniquelyReferencedUnflaggedNative()
  }

  @usableFromInline @_transparent
  internal var isNative: Bool {
    if guaranteedNative { return true }
    return object.isUnflaggedNative
  }

  @usableFromInline @_transparent
  internal var asNative: _NativeDictionary<Key, Value> {
    get {
      return _NativeDictionary<Key, Value>(object.unflaggedNativeInstance)
    }
    set {
      self = .init(native: newValue)
    }
    _modify {
      var native = _NativeDictionary<Key, Value>(object.unflaggedNativeInstance)
      self = .init(dummy: ())
      defer { object = .init(native: native._storage) }
      yield &native
    }
  }

  @inlinable
  internal var asCocoa: __CocoaDictionary {
    return __CocoaDictionary(object.objCInstance)
  }

  internal mutating func reserveCapacity(_ capacity: Int) {
    if !isNative {
      _cocoaDictionaryUnsupported()
    }
    let isUnique = isUniquelyReferenced()
    asNative.reserveCapacity(capacity, isUnique: isUnique)
  }

  @inlinable
  internal var capacity: Int {
    return asNative.capacity
  }
}

extension Dictionary._Variant {
  @usableFromInline internal typealias Element = (key: Key, value: Value)
  @usableFromInline internal typealias Index = Dictionary<Key, Value>.Index

  @inlinable internal var startIndex: Index { return asNative.startIndex }
  @inlinable internal var endIndex: Index { return asNative.endIndex }

  @inlinable
  internal func index(after index: Index) -> Index {
    return asNative.index(after: index)
  }
  @inlinable
  internal func formIndex(after index: inout Index) {
    index = asNative.index(after: index)
  }
  @inlinable @inline(__always)
  internal func index(forKey key: Key) -> Index? {
    return asNative.index(forKey: key)
  }

  @inlinable internal var count: Int {
    @inline(__always) get { return asNative.count }
  }

  @inlinable @inline(__always)
  internal func contains(_ key: Key) -> Bool {
    return asNative.contains(key)
  }
  @inlinable @inline(__always)
  internal func lookup(_ key: Key) -> Value? {
    return asNative.lookup(key)
  }
  @inlinable @inline(__always)
  internal func lookup(_ index: Index) -> (key: Key, value: Value) {
    return asNative.lookup(index)
  }
  @inlinable @inline(__always)
  internal func key(at index: Index) -> Key {
    return asNative.key(at: index)
  }
  @inlinable @inline(__always)
  internal func value(at index: Index) -> Value {
    return asNative.value(at: index)
  }
}

extension Dictionary._Variant {
  @inlinable
  internal subscript(key: Key) -> Value? {
    @inline(__always) get {
      return lookup(key)
    }
    @inline(__always) _modify {
      let isUnique = isUniquelyReferenced()
      yield &asNative[key, isUnique: isUnique]
    }
  }

  @inlinable @inline(__always)
  internal mutating func mutatingFind(_ key: Key) -> (bucket: _NativeDictionary<Key, Value>.Bucket, found: Bool) {
    let isUnique = isUniquelyReferenced()
    return asNative.mutatingFind(key, isUnique: isUnique)
  }

  @inlinable @inline(__always)
  internal mutating func ensureUniqueNative() -> _NativeDictionary<Key, Value> {
    if !isUniquelyReferenced() {
      asNative.copy()
    }
    return asNative
  }

  @inlinable
  internal mutating func updateValue(_ value: __owned Value, forKey key: Key) -> Value? {
    let isUnique = isUniquelyReferenced()
    return asNative.updateValue(value, forKey: key, isUnique: isUnique)
  }

  @inlinable
  internal mutating func setValue(_ value: __owned Value, forKey key: Key) {
    let isUnique = isUniquelyReferenced()
    asNative.setValue(value, forKey: key, isUnique: isUnique)
  }

  @inlinable
  internal mutating func remove(at index: Index) -> Element {
    let native = ensureUniqueNative()
    let bucket = native.validatedBucket(for: index)
    return asNative.uncheckedRemove(at: bucket, isUnique: true)
  }

  @inlinable
  internal mutating func removeValue(forKey key: Key) -> Value? {
    let (bucket, found) = asNative.find(key)
    if !found { return nil }
    let isUnique = isUniquelyReferenced()
    return asNative.uncheckedRemove(at: bucket, isUnique: isUnique).value
  }

  @inlinable
  internal mutating func removeAll(keepingCapacity keepCapacity: Bool) {
    if !keepCapacity {
      self = .init(native: _NativeDictionary())
      return
    }
    if count == 0 { return }
    let isUnique = isUniquelyReferenced()
    asNative.removeAll(isUnique: isUnique)
  }

  @inlinable @inline(__always)
  internal __consuming func makeIterator() -> Dictionary<Key, Value>.Iterator {
    return Dictionary.Iterator(_native: asNative.makeIterator())
  }

  @inlinable
  internal func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> _NativeDictionary<Key, T> {
    return try asNative.mapValues(transform)
  }

  @inlinable
  internal mutating func merge<S: Sequence>(
    _ keysAndValues: __owned S,
    uniquingKeysWith combine: (Value, Value) throws -> Value
  ) rethrows where S.Element == (Key, Value) {
    let isUnique = isUniquelyReferenced()
    try asNative.merge(keysAndValues, isUnique: isUnique, uniquingKeysWith: combine)
  }
}

// ---- Sequence and Collection ---------------------------------------------------------------

extension Dictionary: Sequence {
  @inlinable @inline(__always)
  public __consuming func makeIterator() -> Iterator {
    return _variant.makeIterator()
  }
}

extension Dictionary {
  @inlinable
  public __consuming func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> [Key: Value] {
    return Dictionary(_native: try _variant.asNative.filter(isIncluded))
  }
}

extension Dictionary: Collection {
  public typealias SubSequence = Slice<Dictionary>
  public typealias Indices = DefaultIndices<Dictionary>

  @inlinable public var startIndex: Index { return _variant.startIndex }
  @inlinable public var endIndex: Index { return _variant.endIndex }

  @inlinable
  public func index(after i: Index) -> Index {
    return _variant.index(after: i)
  }
  @inlinable
  public func formIndex(after i: inout Index) {
    _variant.formIndex(after: &i)
  }

  @inlinable @inline(__always)
  public func index(forKey key: Key) -> Index? {
    return _variant.index(forKey: key)
  }

  @inlinable
  public subscript(position: Index) -> Element {
    return _variant.lookup(position)
  }

  @inlinable public var count: Int { return _variant.count }
  @inlinable public var isEmpty: Bool { return count == 0 }
}

extension Dictionary {
  @inlinable
  public subscript(key: Key) -> Value? {
    get {
      return _variant.lookup(key)
    }
    set(newValue) {
      if let x = newValue {
        _variant.setValue(x, forKey: key)
      } else {
        removeValue(forKey: key)
      }
    }
    _modify {
      defer { _fixLifetime(self) }
      yield &_variant[key]
    }
  }
}

extension Dictionary {
  @inlinable
  public subscript(key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
    @inline(__always) get {
      return _variant.lookup(key) ?? defaultValue()
    }
    @inline(__always) _modify {
      let (bucket, found) = _variant.mutatingFind(key)
      let native = _variant.asNative
      if !found {
        native._insert(at: bucket, key: key, value: defaultValue())
      }
      let address = native._values + bucket.offset
      defer { _fixLifetime(self) }
      yield &address.pointee
    }
  }

  @inlinable
  public func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> Dictionary<Key, T> {
    return try Dictionary<Key, T>(_native: _variant.mapValues(transform))
  }

  @inlinable
  public func compactMapValues<T>(_ transform: (Value) throws -> T?) rethrows -> Dictionary<Key, T> {
    var result = _NativeDictionary<Key, T>()
    for (key, value) in self {
      if let newValue = try transform(value) {
        result.insertNew(key: key, value: newValue)
      }
    }
    return Dictionary<Key, T>(_native: result)
  }

  @inlinable @discardableResult
  public mutating func updateValue(_ value: __owned Value, forKey key: Key) -> Value? {
    return _variant.updateValue(value, forKey: key)
  }

  @inlinable
  public mutating func merge<S: Sequence>(
    _ other: __owned S,
    uniquingKeysWith combine: (Value, Value) throws -> Value
  ) rethrows where S.Element == (Key, Value) {
    try _variant.merge(other, uniquingKeysWith: combine)
  }

  @inlinable
  public mutating func merge(
    _ other: __owned [Key: Value],
    uniquingKeysWith combine: (Value, Value) throws -> Value
  ) rethrows {
    try _variant.merge(_DictionaryPairs(other), uniquingKeysWith: combine)
  }

  @inlinable
  public __consuming func merging<S: Sequence>(
    _ other: __owned S,
    uniquingKeysWith combine: (Value, Value) throws -> Value
  ) rethrows -> [Key: Value] where S.Element == (Key, Value) {
    var result = self
    try result._variant.merge(other, uniquingKeysWith: combine)
    return result
  }

  @inlinable
  public __consuming func merging(
    _ other: __owned [Key: Value],
    uniquingKeysWith combine: (Value, Value) throws -> Value
  ) rethrows -> [Key: Value] {
    var result = self
    try result.merge(other, uniquingKeysWith: combine)
    return result
  }

  @inlinable @discardableResult
  public mutating func remove(at index: Index) -> Element {
    return _variant.remove(at: index)
  }

  @inlinable @discardableResult
  public mutating func removeValue(forKey key: Key) -> Value? {
    return _variant.removeValue(forKey: key)
  }

  @inlinable
  public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
    _variant.removeAll(keepingCapacity: keepCapacity)
  }
}

/// A dictionary's elements as unlabeled (key, value) tuples, the element
/// type merge takes.
@usableFromInline @frozen
internal struct _DictionaryPairs<Key: Hashable, Value>: Sequence, IteratorProtocol {
  @usableFromInline internal var _base: Dictionary<Key, Value>.Iterator

  @inlinable
  internal init(_ base: __owned Dictionary<Key, Value>) {
    _base = base.makeIterator()
  }

  @inlinable
  internal mutating func next() -> (Key, Value)? {
    guard let (key, value) = _base.next() else { return nil }
    return (key, value)
  }
}

extension Dictionary {
  @inlinable @discardableResult
  public mutating func popFirst() -> Element? {
    if isEmpty { return nil }
    return remove(at: startIndex)
  }

  @inlinable
  public var capacity: Int {
    return _variant.capacity
  }

  public mutating func reserveCapacity(_ minimumCapacity: Int) {
    _variant.reserveCapacity(minimumCapacity)
  }
}

// ---- keys and values ------------------------------------------------------------------------

extension Dictionary {
  @inlinable
  public var keys: Keys {
    get { return Keys(_dictionary: self) }
  }

  @inlinable
  public var values: Values {
    get {
      return Values(_dictionary: self)
    }
    _modify {
      // Move the storage into the view so mutating it does not copy.
      var values = Values(_variant: _Variant(dummy: ()))
      swap(&values._variant, &_variant)
      defer { self._variant = values._variant }
      yield &values
    }
  }

  @frozen
  public struct Keys: Collection, Equatable {
    public typealias Element = Key
    public typealias SubSequence = Slice<Dictionary.Keys>
    public typealias Index = Dictionary<Key, Value>.Index
    public typealias Indices = DefaultIndices<Dictionary.Keys>

    @usableFromInline
    internal var _variant: Dictionary<Key, Value>._Variant

    @inlinable
    internal init(_dictionary: __owned Dictionary) {
      self._variant = _dictionary._variant
    }

    @inlinable public var startIndex: Index { return _variant.startIndex }
    @inlinable public var endIndex: Index { return _variant.endIndex }

    @inlinable
    public func index(after i: Index) -> Index {
      return _variant.index(after: i)
    }
    @inlinable
    public func formIndex(after i: inout Index) {
      _variant.formIndex(after: &i)
    }

    @inlinable
    public subscript(position: Index) -> Element {
      return _variant.key(at: position)
    }

    @inlinable public var count: Int { return _variant.count }
    @inlinable public var isEmpty: Bool { return count == 0 }

    @inlinable @inline(__always)
    public func _customContainsEquatableElement(_ element: Element) -> Bool? {
      return _variant.contains(element)
    }
    @inlinable @inline(__always)
    public func _customIndexOfEquatableElement(_ element: Element) -> Index?? {
      return Optional(_variant.index(forKey: element))
    }
    @inlinable @inline(__always)
    public func _customLastIndexOfEquatableElement(_ element: Element) -> Index?? {
      return _customIndexOfEquatableElement(element)
    }

    @inlinable
    public static func == (lhs: Keys, rhs: Keys) -> Bool {
      if lhs._variant.asNative._storage === rhs._variant.asNative._storage { return true }
      if lhs.count != rhs.count { return false }
      for key in lhs {
        if !rhs._variant.contains(key) { return false }
      }
      return true
    }
  }

  @frozen
  public struct Values: MutableCollection {
    public typealias Element = Value
    public typealias Index = Dictionary<Key, Value>.Index
    public typealias Indices = DefaultIndices<Dictionary.Values>
    public typealias SubSequence = Slice<Dictionary.Values>

    @usableFromInline
    internal var _variant: Dictionary<Key, Value>._Variant

    @inlinable
    internal init(_variant: __owned Dictionary<Key, Value>._Variant) {
      self._variant = _variant
    }

    @inlinable
    internal init(_dictionary: __owned Dictionary) {
      self._variant = _dictionary._variant
    }

    @inlinable public var startIndex: Index { return _variant.startIndex }
    @inlinable public var endIndex: Index { return _variant.endIndex }

    @inlinable
    public func index(after i: Index) -> Index {
      return _variant.index(after: i)
    }
    @inlinable
    public func formIndex(after i: inout Index) {
      _variant.formIndex(after: &i)
    }

    @inlinable
    public subscript(position: Index) -> Element {
      get {
        return _variant.value(at: position)
      }
      _modify {
        let native = _variant.ensureUniqueNative()
        let bucket = native.validatedBucket(for: position)
        let address = native._values + bucket.offset
        defer { _fixLifetime(self) }
        yield &address.pointee
      }
    }

    @inlinable public var count: Int { return _variant.count }
    @inlinable public var isEmpty: Bool { return count == 0 }

    @inlinable
    public mutating func swapAt(_ i: Index, _ j: Index) {
      if i == j { return }
      let isUnique = _variant.isUniquelyReferenced()
      let native = _variant.asNative
      let a = native.validatedBucket(for: i)
      let b = native.validatedBucket(for: j)
      _variant.asNative.swapValuesAt(a, b, isUnique: isUnique)
    }
  }
}

extension Dictionary.Keys {
  @frozen
  public struct Iterator: IteratorProtocol {
    public typealias Element = Key

    @usableFromInline
    internal var _base: Dictionary<Key, Value>.Iterator

    @inlinable @inline(__always)
    internal init(_ base: Dictionary<Key, Value>.Iterator) {
      self._base = base
    }

    @inlinable @inline(__always)
    public mutating func next() -> Key? {
      return _base._asNative.nextKey()
    }
  }

  @inlinable @inline(__always)
  public __consuming func makeIterator() -> Iterator {
    return Iterator(_variant.makeIterator())
  }
}

extension Dictionary.Values {
  @frozen
  public struct Iterator: IteratorProtocol {
    public typealias Element = Value

    @usableFromInline
    internal var _base: Dictionary<Key, Value>.Iterator

    @inlinable @inline(__always)
    internal init(_ base: Dictionary<Key, Value>.Iterator) {
      self._base = base
    }

    @inlinable @inline(__always)
    public mutating func next() -> Value? {
      return _base._asNative.nextValue()
    }
  }

  @inlinable @inline(__always)
  public __consuming func makeIterator() -> Iterator {
    return Iterator(_variant.makeIterator())
  }
}

// ---- Equatable and Hashable ---------------------------------------------------------------------

extension Dictionary: Equatable where Value: Equatable {
  @inlinable
  public static func == (lhs: [Key: Value], rhs: [Key: Value]) -> Bool {
    return lhs._variant.asNative.isEqual(to: rhs._variant.asNative)
  }
}

extension Dictionary: Hashable where Value: Hashable {
  /// Order-independent: each element is hashed on its own (from the same
  /// starting state) and the results are combined with XOR.
  @inlinable
  public func hash(into hasher: inout Hasher) {
    var combined = 0
    for (key, value) in self {
      var elementHasher = hasher
      elementHasher.combine(key)
      elementHasher.combine(value)
      combined ^= elementHasher._finalize()
    }
    hasher.combine(combined)
  }

  public var hashValue: Int {
    return _hashValue(for: self)
  }
}

extension Dictionary: _HasCustomAnyHashableRepresentation where Value: Hashable {
  public __consuming func _toCustomAnyHashable() -> AnyHashable? {
    return AnyHashable(_usingDefaultRepresentationOf: self)
  }
}

// ---- Index ----------------------------------------------------------------------------------------

extension Dictionary {
  @frozen
  public struct Index {
    @usableFromInline @frozen
    internal enum _Variant {
      case native(_HashTable.Index)
      case cocoa(__CocoaDictionary.Index)
    }

    @usableFromInline
    internal var _variant: _Variant

    @inlinable @inline(__always)
    internal init(_variant: __owned _Variant) {
      self._variant = _variant
    }

    @inlinable @inline(__always)
    internal init(_native index: _HashTable.Index) {
      self.init(_variant: .native(index))
    }

    @inlinable @inline(__always)
    internal init(_cocoa index: __owned __CocoaDictionary.Index) {
      self.init(_variant: .cocoa(index))
    }
  }
}

extension Dictionary.Index {
  @usableFromInline @_transparent
  internal var _guaranteedNative: Bool {
    return _canBeClass(Key.self) == 0 || _canBeClass(Value.self) == 0
  }

  @usableFromInline @_transparent
  internal var _isNative: Bool {
    switch _variant {
    case .native: return true
    case .cocoa: return false
    }
  }

  @usableFromInline @_transparent
  internal var _asNative: _HashTable.Index {
    switch _variant {
    case .native(let nativeIndex):
      return nativeIndex
    case .cocoa:
      _preconditionFailure("Attempting to access Dictionary elements using an invalid index")
    }
  }

  @usableFromInline
  internal var _asCocoa: __CocoaDictionary.Index {
    @_transparent get {
      switch _variant {
      case .native:
        _preconditionFailure("Attempting to access Dictionary elements using an invalid index")
      case .cocoa(let cocoaIndex):
        return cocoaIndex
      }
    }
    _modify {
      guard case .cocoa(var cocoa) = _variant else {
        _preconditionFailure("Attempting to access Dictionary elements using an invalid index")
      }
      // Park a native placeholder so the cocoa index is uniquely held while
      // it is mutated.
      _variant = .native(_HashTable.Index(bucket: _HashTable.Bucket(offset: 0), age: 0))
      defer { _variant = .cocoa(cocoa) }
      yield &cocoa
    }
  }
}

extension Dictionary.Index: Equatable {
  @inlinable
  public static func == (lhs: Dictionary<Key, Value>.Index, rhs: Dictionary<Key, Value>.Index) -> Bool {
    switch (lhs._variant, rhs._variant) {
    case (.native(let l), .native(let r)):
      return l == r
    case (.cocoa(let l), .cocoa(let r)):
      return l == r
    default:
      _preconditionFailure("Comparing indexes from different dictionaries")
    }
  }
}

extension Dictionary.Index: Comparable {
  @inlinable
  public static func < (lhs: Dictionary<Key, Value>.Index, rhs: Dictionary<Key, Value>.Index) -> Bool {
    switch (lhs._variant, rhs._variant) {
    case (.native(let l), .native(let r)):
      return l < r
    case (.cocoa(let l), .cocoa(let r)):
      return l < r
    default:
      _preconditionFailure("Comparing indexes from different dictionaries")
    }
  }
}

extension Dictionary.Index: Hashable {
  public func hash(into hasher: inout Hasher) {
    switch _variant {
    case .native(let index):
      hasher.combine(0 as UInt8)
      hasher.combine(index.bucket.offset)
    case .cocoa(let index):
      hasher.combine(1 as UInt8)
      hasher.combine(index.handleBitPattern)
    }
  }

  public var hashValue: Int {
    return _hashValue(for: self)
  }
}

// ---- Iterator ------------------------------------------------------------------------------------

extension Dictionary {
  @frozen
  public struct Iterator {
    @usableFromInline @frozen
    internal enum _Variant {
      case native(_NativeDictionary<Key, Value>.Iterator)
      case cocoa(__CocoaDictionary.Iterator)
    }

    @usableFromInline
    internal var _variant: _Variant

    @inlinable
    internal init(_variant: __owned _Variant) {
      self._variant = _variant
    }

    @inlinable
    internal init(_native: __owned _NativeDictionary<Key, Value>.Iterator) {
      self.init(_variant: .native(_native))
    }

    @inlinable
    internal init(_cocoa: __owned __CocoaDictionary.Iterator) {
      self.init(_variant: .cocoa(_cocoa))
    }
  }
}

extension Dictionary.Iterator {
  @usableFromInline @_transparent
  internal var _asNative: _NativeDictionary<Key, Value>.Iterator {
    get {
      switch _variant {
      case .native(let nativeIterator):
        return nativeIterator
      case .cocoa:
        _cocoaDictionaryUnsupported()
      }
    }
    set {
      self._variant = .native(newValue)
    }
  }
}

extension Dictionary.Iterator: IteratorProtocol {
  public typealias Element = (key: Key, value: Value)

  @inlinable @inline(__always)
  public mutating func next() -> (key: Key, value: Value)? {
    return _asNative.next()
  }
}

public typealias DictionaryIndex<Key: Hashable, Value> = Dictionary<Key, Value>.Index
public typealias DictionaryIterator<Key: Hashable, Value> = Dictionary<Key, Value>.Iterator

extension Dictionary: @unchecked Sendable where Key: Sendable, Value: Sendable {}
extension Dictionary.Keys: @unchecked Sendable where Key: Sendable, Value: Sendable {}
extension Dictionary.Values: @unchecked Sendable where Key: Sendable, Value: Sendable {}
extension Dictionary.Keys.Iterator: @unchecked Sendable where Key: Sendable, Value: Sendable {}
extension Dictionary.Values.Iterator: @unchecked Sendable where Key: Sendable, Value: Sendable {}
extension Dictionary.Index: @unchecked Sendable where Key: Sendable, Value: Sendable {}
extension Dictionary.Iterator: @unchecked Sendable where Key: Sendable, Value: Sendable {}

// ---- the builder (used by the Foundation overlay and by bridging) ---------------------------------

@frozen
public struct _DictionaryBuilder<Key: Hashable, Value> {
  @usableFromInline internal var _target: _NativeDictionary<Key, Value>
  @usableFromInline internal let _requestedCount: Int

  @inlinable
  public init(count: Int) {
    _target = _NativeDictionary(capacity: count)
    _requestedCount = count
  }

  @inlinable
  public mutating func add(key newKey: Key, value: Value) {
    _precondition(_target.count < _requestedCount, "Can't add more members than promised")
    _target._unsafeInsertNew(key: newKey, value: value)
  }

  @inlinable
  public __consuming func take() -> Dictionary<Key, Value> {
    _precondition(_target.count == _requestedCount,
                  "The number of members added does not match the promised count")
    return Dictionary(_native: _target)
  }
}

// ---- dictionary literals ------------------------------------------------------

public protocol ExpressibleByDictionaryLiteral {
  associatedtype Key
  associatedtype Value
  init(dictionaryLiteral elements: (Key, Value)...)
}

extension Dictionary: ExpressibleByDictionaryLiteral {
  /// A dictionary of the literal's pairs; a key given twice is a fatal error.
  public init(dictionaryLiteral elements: (Key, Value)...) {
    self.init(minimumCapacity: elements.count)
    for (key, value) in elements {
      if updateValue(value, forKey: key) != nil {
        _preconditionFailure("Dictionary literal contains duplicate keys")
      }
    }
  }
}
