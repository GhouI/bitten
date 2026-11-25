// Set: one word, a _BridgeStorage of native storage (__RawSetStorage) or a
// bridged NSSet (__CocoaSet, not implemented). Built on _NativeSet, with
// copy-on-write like Dictionary.
//
// The SetAlgebra conformance and array literals come with Array (the
// protocol refines ExpressibleByArrayLiteral); the methods are all here.

@frozen @_eagerMove
public struct Set<Element: Hashable> {
  @usableFromInline
  internal var _variant: _Variant

  public init(minimumCapacity: Int) {
    _variant = _Variant(native: _NativeSet(capacity: minimumCapacity))
  }

  @inlinable
  internal init(_native: __owned _NativeSet<Element>) {
    _variant = _Variant(native: _native)
  }

  @inlinable
  internal init(_cocoa: __owned __CocoaSet) {
    _variant = _Variant(cocoa: _cocoa)
  }
}

// ---- the variant ---------------------------------------------------------------------------

extension Set {
  @usableFromInline @frozen
  internal struct _Variant {
    @usableFromInline
    internal var object: _BridgeStorage<__RawSetStorage>

    @inlinable @inline(__always)
    internal init(dummy: ()) {
      self.object = _BridgeStorage(taggedPayload: 0)
    }

    @inlinable @inline(__always)
    internal init(native: __owned _NativeSet<Element>) {
      self.object = _BridgeStorage(native: native._storage)
    }

    @inlinable @inline(__always)
    internal init(cocoa: __owned __CocoaSet) {
      self.object = _BridgeStorage(objC: cocoa.object)
    }
  }
}

extension Set._Variant {
  @usableFromInline @_transparent
  internal var guaranteedNative: Bool {
    return _canBeClass(Element.self) == 0
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
  internal var asNative: _NativeSet<Element> {
    get {
      return _NativeSet(object.unflaggedNativeInstance)
    }
    set {
      self = .init(native: newValue)
    }
    _modify {
      var native = _NativeSet<Element>(object.unflaggedNativeInstance)
      self = .init(dummy: ())
      defer { object = .init(native: native._storage) }
      yield &native
    }
  }

  @inlinable
  internal var asCocoa: __CocoaSet {
    return __CocoaSet(object.objCInstance)
  }

  internal mutating func reserveCapacity(_ capacity: Int) {
    if !isNative {
      _cocoaSetUnsupported()
    }
    let isUnique = isUniquelyReferenced()
    asNative.reserveCapacity(capacity, isUnique: isUnique)
  }

  @inlinable
  internal var capacity: Int {
    return asNative.capacity
  }
}

extension Set._Variant {
  @usableFromInline internal typealias Index = Set<Element>.Index

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
  internal func index(for element: Element) -> Index? {
    return asNative.index(for: element)
  }

  @inlinable internal var count: Int {
    @inline(__always) get { return asNative.count }
  }

  @inlinable @inline(__always)
  internal func contains(_ member: Element) -> Bool {
    return asNative.contains(member)
  }

  @inlinable @inline(__always)
  internal func element(at index: Index) -> Element {
    return asNative.element(at: index)
  }
}

extension Set._Variant {
  @inlinable
  internal mutating func update(with value: __owned Element) -> Element? {
    let isUnique = isUniquelyReferenced()
    return asNative.update(with: value, isUnique: isUnique)
  }

  @inlinable
  internal mutating func insert(_ element: __owned Element) -> (inserted: Bool, memberAfterInsert: Element) {
    let (bucket, found) = asNative.find(element)
    if found {
      return (false, asNative.uncheckedElement(at: bucket))
    }
    let isUnique = isUniquelyReferenced()
    asNative.insertNew(element, at: bucket, isUnique: isUnique)
    return (true, element)
  }

  @inlinable
  internal mutating func remove(at index: Index) -> Element {
    let isUnique = isUniquelyReferenced()
    let bucket = asNative.validatedBucket(for: index)
    return asNative.uncheckedRemove(at: bucket, isUnique: isUnique)
  }

  @inlinable
  internal mutating func remove(_ member: Element) -> Element? {
    let (bucket, found) = asNative.find(member)
    if !found { return nil }
    let isUnique = isUniquelyReferenced()
    return asNative.uncheckedRemove(at: bucket, isUnique: isUnique)
  }

  @inlinable
  internal mutating func removeAll(keepingCapacity keepCapacity: Bool) {
    if !keepCapacity {
      self = .init(native: _NativeSet<Element>())
      return
    }
    if count == 0 { return }
    let isUnique = isUniquelyReferenced()
    asNative.removeAll(isUnique: isUnique)
  }

  @inlinable @inline(__always)
  internal __consuming func makeIterator() -> Set<Element>.Iterator {
    return Set.Iterator(_native: asNative.makeIterator())
  }

  @_alwaysEmitIntoClient
  internal __consuming func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> _NativeSet<Element> {
    return try asNative.filter(isIncluded)
  }

  @_alwaysEmitIntoClient
  internal __consuming func intersection(_ other: Set<Element>) -> _NativeSet<Element> {
    return asNative.intersection(other._variant.asNative)
  }
}

// ---- Sequence and Collection ---------------------------------------------------------------

extension Set: Sequence {
  @inlinable @inline(__always)
  public __consuming func makeIterator() -> Iterator {
    return _variant.makeIterator()
  }

  @inlinable
  public func contains(_ member: Element) -> Bool {
    return _variant.contains(member)
  }

  @inlinable @inline(__always)
  public func _customContainsEquatableElement(_ member: Element) -> Bool? {
    return contains(member)
  }
}

extension Set {
  @inlinable
  public __consuming func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> Set {
    return Set(_native: try _variant.filter(isIncluded))
  }
}

extension Set: Collection {
  public typealias Indices = DefaultIndices<Set<Element>>
  public typealias SubSequence = Slice<Set<Element>>

  @inlinable public var startIndex: Index { return _variant.startIndex }
  @inlinable public var endIndex: Index { return _variant.endIndex }

  @inlinable
  public subscript(position: Index) -> Element {
    return _variant.element(at: position)
  }

  @inlinable
  public func index(after i: Index) -> Index {
    return _variant.index(after: i)
  }
  @inlinable
  public func formIndex(after i: inout Index) {
    _variant.formIndex(after: &i)
  }

  @inlinable
  public func firstIndex(of member: Element) -> Index? {
    return _variant.index(for: member)
  }

  @inlinable @inline(__always)
  public func _customIndexOfEquatableElement(_ member: Element) -> Index?? {
    return Optional(firstIndex(of: member))
  }
  @inlinable @inline(__always)
  public func _customLastIndexOfEquatableElement(_ member: Element) -> Index?? {
    return _customIndexOfEquatableElement(member)
  }

  @inlinable public var count: Int { return _variant.count }
  @inlinable public var isEmpty: Bool { return count == 0 }
}

extension Set: Equatable {
  @inlinable
  public static func == (lhs: Set<Element>, rhs: Set<Element>) -> Bool {
    return lhs._variant.asNative.isEqual(to: rhs._variant.asNative)
  }
}

extension Set: Hashable {
  /// Order-independent: the members' hashes (each from the same starting
  /// state) combined with XOR.
  @inlinable
  public func hash(into hasher: inout Hasher) {
    var combined = 0
    for member in self {
      var elementHasher = hasher
      elementHasher.combine(member)
      combined ^= elementHasher._finalize()
    }
    hasher.combine(combined)
  }

  public var hashValue: Int {
    return _hashValue(for: self)
  }
}

extension Set: _HasCustomAnyHashableRepresentation {
  public __consuming func _toCustomAnyHashable() -> AnyHashable? {
    return AnyHashable(_usingDefaultRepresentationOf: self)
  }
}

// ---- the SetAlgebra operations ------------------------------------------------------------

extension Set {
  @inlinable @discardableResult
  public mutating func insert(_ newMember: __owned Element) -> (inserted: Bool, memberAfterInsert: Element) {
    return _variant.insert(newMember)
  }

  @inlinable @discardableResult
  public mutating func update(with newMember: __owned Element) -> Element? {
    return _variant.update(with: newMember)
  }

  @inlinable @discardableResult
  public mutating func remove(_ member: Element) -> Element? {
    return _variant.remove(member)
  }

  @inlinable @discardableResult
  public mutating func remove(at position: Index) -> Element {
    return _variant.remove(at: position)
  }

  @inlinable
  public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
    _variant.removeAll(keepingCapacity: keepCapacity)
  }

  @inlinable @discardableResult
  public mutating func removeFirst() -> Element {
    _precondition(!isEmpty, "Can't removeFirst from an empty Set")
    return remove(at: startIndex)
  }

  @inlinable
  public init() {
    self = Set<Element>(_native: _NativeSet())
  }

  @inlinable
  public init<Source: Sequence>(_ sequence: __owned Source) where Source.Element == Element {
    if let s = sequence as? Set<Element> {
      self = s
      return
    }
    var native = _NativeSet<Element>(capacity: sequence.underestimatedCount)
    for member in sequence {
      _ = native.update(with: member, isUnique: true)
    }
    self.init(_native: native)
  }

  @inlinable
  public func isSubset<S: Sequence>(of possibleSuperset: S) -> Bool where S.Element == Element {
    if let s = possibleSuperset as? Set<Element> {
      return isSubset(of: s)
    }
    return _variant.asNative.isSubset(of: possibleSuperset)
  }

  @inlinable
  public func isStrictSubset<S: Sequence>(of possibleStrictSuperset: S) -> Bool
    where S.Element == Element {
    if let s = possibleStrictSuperset as? Set<Element> {
      return isStrictSubset(of: s)
    }
    return _variant.asNative.isStrictSubset(of: possibleStrictSuperset)
  }

  @inlinable
  public func isSuperset<S: Sequence>(of possibleSubset: __owned S) -> Bool
    where S.Element == Element {
    if let s = possibleSubset as? Set<Element> {
      return isSuperset(of: s)
    }
    for member in possibleSubset {
      if !contains(member) { return false }
    }
    return true
  }

  @inlinable
  public func isStrictSuperset<S: Sequence>(of possibleStrictSubset: S) -> Bool
    where S.Element == Element {
    if let s = possibleStrictSubset as? Set<Element> {
      return isStrictSuperset(of: s)
    }
    return _variant.asNative.isStrictSuperset(of: possibleStrictSubset)
  }

  @inlinable
  public func isDisjoint<S: Sequence>(with other: S) -> Bool where S.Element == Element {
    if let s = other as? Set<Element> {
      return isDisjoint(with: s)
    }
    return _isDisjoint(with: other)
  }

  @inlinable
  public __consuming func union<S: Sequence>(_ other: __owned S) -> Set<Element>
    where S.Element == Element {
    var result = self
    result.formUnion(other)
    return result
  }

  @inlinable
  public mutating func formUnion<S: Sequence>(_ other: __owned S) where S.Element == Element {
    for member in other {
      insert(member)
    }
  }

  @inlinable
  public __consuming func subtracting<S: Sequence>(_ other: S) -> Set<Element>
    where S.Element == Element {
    return _subtracting(other)
  }

  @inlinable
  internal __consuming func _subtracting<S: Sequence>(_ other: S) -> Set<Element>
    where S.Element == Element {
    return Set(_native: _variant.asNative.subtracting(other))
  }

  @inlinable
  public mutating func subtract<S: Sequence>(_ other: S) where S.Element == Element {
    _subtract(other)
  }

  @inlinable
  internal mutating func _subtract<S: Sequence>(_ other: S) where S.Element == Element {
    if isEmpty { return }
    for member in other {
      remove(member)
      if isEmpty { return }
    }
  }

  @inlinable
  public __consuming func intersection<S: Sequence>(_ other: S) -> Set<Element>
    where S.Element == Element {
    if let s = other as? Set<Element> {
      return intersection(s)
    }
    return Set(_native: _variant.asNative.genericIntersection(other))
  }

  @inlinable
  public mutating func formIntersection<S: Sequence>(_ other: S) where S.Element == Element {
    self = intersection(other)
  }

  @inlinable
  public __consuming func symmetricDifference<S: Sequence>(_ other: __owned S) -> Set<Element>
    where S.Element == Element {
    var result = self
    result.formSymmetricDifference(other)
    return result
  }

  @inlinable
  public mutating func formSymmetricDifference<S: Sequence>(_ other: __owned S)
    where S.Element == Element {
    formSymmetricDifference(Set(other))
  }
}

extension Set {
  @inlinable
  public mutating func subtract(_ other: Set<Element>) {
    _subtract(other)
  }

  @inlinable
  public func isSubset(of other: Set<Element>) -> Bool {
    if count > other.count { return false }
    for member in self {
      if !other.contains(member) { return false }
    }
    return true
  }

  @inlinable
  public func isSuperset(of other: Set<Element>) -> Bool {
    return other.isSubset(of: self)
  }

  @inlinable
  public func isDisjoint(with other: Set<Element>) -> Bool {
    // Probe the larger with the members of the smaller.
    return count <= other.count ? _isDisjoint(with: other) : other._isDisjoint(with: self)
  }

  @inlinable
  internal func _isDisjoint<S: Sequence>(with other: S) -> Bool where S.Element == Element {
    if isEmpty { return true }
    for member in other {
      if contains(member) { return false }
    }
    return true
  }

  @inlinable
  public __consuming func subtracting(_ other: Set<Element>) -> Set<Element> {
    return _subtracting(other)
  }

  @inlinable
  public func isStrictSuperset(of other: Set<Element>) -> Bool {
    return count > other.count && other.isSubset(of: self)
  }

  @inlinable
  public func isStrictSubset(of other: Set<Element>) -> Bool {
    return other.isStrictSuperset(of: self)
  }

  @inlinable
  public __consuming func intersection(_ other: Set<Element>) -> Set<Element> {
    return Set(_native: _variant.intersection(other))
  }

  @inlinable
  public mutating func formSymmetricDifference(_ other: __owned Set<Element>) {
    for member in other {
      if remove(member) == nil {
        insert(member)
      }
    }
  }
}

// ---- Index ----------------------------------------------------------------------------------------

extension Set {
  @frozen
  public struct Index {
    @usableFromInline @frozen
    internal enum _Variant {
      case native(_HashTable.Index)
      case cocoa(__CocoaSet.Index)
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
    internal init(_cocoa index: __owned __CocoaSet.Index) {
      self.init(_variant: .cocoa(index))
    }
  }
}

extension Set.Index {
  @usableFromInline @_transparent
  internal var _guaranteedNative: Bool {
    return _canBeClass(Element.self) == 0
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
      _preconditionFailure("Attempting to access Set elements using an invalid index")
    }
  }

  @usableFromInline
  internal var _asCocoa: __CocoaSet.Index {
    @_transparent get {
      switch _variant {
      case .native:
        _preconditionFailure("Attempting to access Set elements using an invalid index")
      case .cocoa(let cocoaIndex):
        return cocoaIndex
      }
    }
    _modify {
      guard case .cocoa(var cocoa) = _variant else {
        _preconditionFailure("Attempting to access Set elements using an invalid index")
      }
      _variant = .native(_HashTable.Index(bucket: _HashTable.Bucket(offset: 0), age: 0))
      defer { _variant = .cocoa(cocoa) }
      yield &cocoa
    }
  }
}

extension Set.Index: Equatable {
  @inlinable
  public static func == (lhs: Set<Element>.Index, rhs: Set<Element>.Index) -> Bool {
    switch (lhs._variant, rhs._variant) {
    case (.native(let l), .native(let r)):
      return l == r
    case (.cocoa(let l), .cocoa(let r)):
      return l == r
    default:
      _preconditionFailure("Comparing indexes from different sets")
    }
  }
}

extension Set.Index: Comparable {
  @inlinable
  public static func < (lhs: Set<Element>.Index, rhs: Set<Element>.Index) -> Bool {
    switch (lhs._variant, rhs._variant) {
    case (.native(let l), .native(let r)):
      return l < r
    case (.cocoa(let l), .cocoa(let r)):
      return l < r
    default:
      _preconditionFailure("Comparing indexes from different sets")
    }
  }
}

extension Set.Index: Hashable {
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

extension Set {
  @frozen
  public struct Iterator {
    @usableFromInline @frozen
    internal enum _Variant {
      case native(_NativeSet<Element>.Iterator)
      case cocoa(__CocoaSet.Iterator)
    }

    @usableFromInline
    internal var _variant: _Variant

    @inlinable
    internal init(_variant: __owned _Variant) {
      self._variant = _variant
    }

    @inlinable
    internal init(_native: __owned _NativeSet<Element>.Iterator) {
      self.init(_variant: .native(_native))
    }

    @inlinable
    internal init(_cocoa: __owned __CocoaSet.Iterator) {
      self.init(_variant: .cocoa(_cocoa))
    }
  }
}

extension Set.Iterator {
  @usableFromInline @_transparent
  internal var _asNative: _NativeSet<Element>.Iterator {
    get {
      switch _variant {
      case .native(let nativeIterator):
        return nativeIterator
      case .cocoa:
        _cocoaSetUnsupported()
      }
    }
    set {
      self._variant = .native(newValue)
    }
  }
}

extension Set.Iterator: IteratorProtocol {
  @inlinable @inline(__always)
  public mutating func next() -> Element? {
    return _asNative.next()
  }
}

extension Set {
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

public typealias SetIndex<Element: Hashable> = Set<Element>.Index
public typealias SetIterator<Element: Hashable> = Set<Element>.Iterator

extension Set: @unchecked Sendable where Element: Sendable {}
extension Set.Index: @unchecked Sendable where Element: Sendable {}
extension Set.Iterator: @unchecked Sendable where Element: Sendable {}

extension Set where Element == AnyHashable {
  @inlinable @discardableResult
  public mutating func insert<ConcreteElement: Hashable>(_ newMember: __owned ConcreteElement)
    -> (inserted: Bool, memberAfterInsert: ConcreteElement) {
    let (inserted, member) = insert(AnyHashable(newMember))
    return (inserted, member.base as! ConcreteElement)
  }

  @inlinable @discardableResult
  public mutating func update<ConcreteElement: Hashable>(with newMember: __owned ConcreteElement)
    -> ConcreteElement? {
    guard let old = update(with: AnyHashable(newMember)) else { return nil }
    return (old.base as! ConcreteElement)
  }

  @inlinable @discardableResult
  public mutating func remove<ConcreteElement: Hashable>(_ member: ConcreteElement) -> ConcreteElement? {
    guard let old = remove(AnyHashable(member)) else { return nil }
    return (old.base as! ConcreteElement)
  }
}

// ---- the builder (used by the Foundation overlay and by bridging) ---------------------------------

@frozen
public struct _SetBuilder<Element: Hashable> {
  @usableFromInline internal var _target: _NativeSet<Element>
  @usableFromInline internal let _requestedCount: Int

  @inlinable
  public init(count: Int) {
    _target = _NativeSet(capacity: count)
    _requestedCount = count
  }

  @inlinable @inline(__always)
  public mutating func add(member: Element) {
    _precondition(_target.count < _requestedCount, "Can't add more members than promised")
    _target._unsafeInsertNew(member)
  }

  @inlinable
  public __consuming func take() -> Set<Element> {
    _precondition(_target.count == _requestedCount,
                  "The number of members added does not match the promised count")
    return Set(_native: _target)
  }
}
