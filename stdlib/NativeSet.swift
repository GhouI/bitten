// _NativeSet: a Set backed by our own hash table storage. Mirrors
// _NativeDictionary with a single element array.

@usableFromInline @frozen
internal struct _NativeSet<Element: Hashable> {
  @usableFromInline
  internal var _storage: __RawSetStorage

  @inlinable @inline(__always)
  internal init() {
    self._storage = __RawSetStorage.empty
  }

  @inlinable @inline(__always)
  internal init(_ storage: __owned __RawSetStorage) {
    self._storage = storage
  }

  @inlinable
  internal init(capacity: Int) {
    if capacity == 0 {
      self._storage = __RawSetStorage.empty
    } else {
      self._storage = _SetStorage<Element>.allocate(capacity: capacity)
    }
  }
}

extension _NativeSet {
  @usableFromInline internal typealias Bucket = _HashTable.Bucket

  @inlinable internal var capacity: Int {
    @inline(__always) get { return _assumeNonNegative(_storage._capacity) }
  }
  @_alwaysEmitIntoClient @inline(__always)
  internal var bucketCount: Int {
    return _assumeNonNegative(_storage._bucketCount)
  }
  @inlinable internal var hashTable: _HashTable {
    @inline(__always) get { return _storage._hashTable }
  }
  @inlinable internal var age: Int32 {
    @inline(__always) get { return _storage._age }
  }
  @inlinable internal var _elements: UnsafeMutablePointer<Element> {
    return _storage._rawElements.assumingMemoryBound(to: Element.self)
  }
  @inlinable @inline(__always)
  internal func invalidateIndices() {
    _storage._age &+= 1
  }
}

extension _NativeSet {
  @inlinable @inline(__always)
  internal func uncheckedElement(at bucket: Bucket) -> Element {
    defer { _fixLifetime(self) }
    return _elements[bucket.offset]
  }
  @inlinable @inline(__always)
  internal func uncheckedInitialize(at bucket: Bucket, to element: __owned Element) {
    defer { _fixLifetime(self) }
    (_elements + bucket.offset).initialize(to: element)
  }
  @_alwaysEmitIntoClient @inlinable @inline(__always)
  internal func uncheckedAssign(at bucket: Bucket, to element: __owned Element) {
    defer { _fixLifetime(self) }
    (_elements + bucket.offset).pointee = element
  }
}

extension _NativeSet {
  @inlinable @inline(__always)
  internal func hashValue(for element: Element) -> Int {
    return element._rawHashValue(seed: _storage._seed)
  }

  @inlinable @inline(__always)
  internal func find(_ element: Element) -> (bucket: Bucket, found: Bool) {
    return find(element, hashValue: hashValue(for: element))
  }

  @inlinable @inline(__always)
  internal func find(_ element: Element, hashValue: Int) -> (bucket: Bucket, found: Bool) {
    let table = hashTable
    var bucket = table.idealBucket(forHashValue: hashValue)
    while table._isOccupied(bucket) {
      if uncheckedElement(at: bucket) == element {
        return (bucket, true)
      }
      bucket = table.bucket(wrappedAfter: bucket)
    }
    return (bucket, false)
  }
}

// ---- growing and copying -----------------------------------------------------------------

extension _NativeSet {
  @inlinable
  internal mutating func resize(capacity: Int) {
    let newCapacity = capacity > self.capacity ? capacity : self.capacity
    let target = _NativeSet(_SetStorage<Element>.resize(original: _storage, capacity: newCapacity,
                                                        move: true))
    if count > 0 {
      for bucket in hashTable {
        target._unsafeInsertNew((_elements + bucket.offset).move())
      }
      // The old storage no longer owns anything.
      _storage._hashTable.clear()
      _storage._count = 0
    }
    _storage = target._storage
  }

  @inlinable
  internal mutating func copyAndResize(capacity: Int) {
    let newCapacity = capacity > self.capacity ? capacity : self.capacity
    let target = _NativeSet(_SetStorage<Element>.resize(original: _storage, capacity: newCapacity,
                                                        move: false))
    if count > 0 {
      for bucket in hashTable {
        target._unsafeInsertNew(uncheckedElement(at: bucket))
      }
    }
    _storage = target._storage
  }

  @inlinable
  internal mutating func copy() {
    let target = _NativeSet(_SetStorage<Element>.copy(original: _storage))
    if count > 0 {
      target.hashTable.copyContents(of: hashTable)
      target._storage._count = count
      for bucket in hashTable {
        target.uncheckedInitialize(at: bucket, to: uncheckedElement(at: bucket))
      }
    }
    _storage = target._storage
  }

  /// Makes the storage unique and able to hold `capacity` elements;
  /// true if elements moved to other buckets.
  @inlinable @inline(__always)
  internal mutating func ensureUnique(isUnique: Bool, capacity: Int) -> Bool {
    if _fastPath(isUnique && capacity <= self.capacity) {
      return false
    }
    if isUnique {
      resize(capacity: capacity)
      return true
    }
    if capacity <= self.capacity {
      copy()
      return false
    }
    copyAndResize(capacity: capacity)
    return true
  }

  internal mutating func reserveCapacity(_ capacity: Int, isUnique: Bool) {
    _ = ensureUnique(isUnique: isUnique, capacity: capacity)
    if _storage !== __RawSetStorage.empty {
      let scale = _HashTable.scale(forCapacity: capacity)
      if scale > _storage._reservedScale { _storage._reservedScale = scale }
    }
  }
}

// ---- indices and lookup ---------------------------------------------------------------------

extension _NativeSet {
  @inlinable @inline(__always)
  internal func validatedBucket(for index: _HashTable.Index) -> Bucket {
    _precondition(hashTable.isOccupied(index.bucket) && index.age == age,
                  "Attempting to access Set elements using an invalid index")
    return index.bucket
  }

  @inlinable @inline(__always)
  internal func validatedBucket(for index: Set<Element>.Index) -> Bucket {
    guard index._isNative else {
      _preconditionFailure("Attempting to access Set elements using an invalid index")
    }
    return validatedBucket(for: index._asNative)
  }
}

extension _NativeSet {
  @usableFromInline internal typealias Index = Set<Element>.Index

  @inlinable internal var startIndex: Index {
    return Index(_native: _HashTable.Index(bucket: hashTable.startBucket, age: age))
  }
  @inlinable internal var endIndex: Index {
    return Index(_native: _HashTable.Index(bucket: hashTable.endBucket, age: age))
  }
  @inlinable
  internal func index(after index: Index) -> Index {
    let bucket = validatedBucket(for: index._asNative)
    return Index(_native: _HashTable.Index(bucket: hashTable.occupiedBucket(after: bucket), age: age))
  }
  @inlinable @inline(__always)
  internal func index(for element: Element) -> Index? {
    if count == 0 { return nil }
    let (bucket, found) = find(element)
    if !found { return nil }
    return Index(_native: _HashTable.Index(bucket: bucket, age: age))
  }

  @inlinable internal var count: Int {
    @inline(__always) get { return _assumeNonNegative(_storage._count) }
  }

  @inlinable @inline(__always)
  internal func contains(_ member: Element) -> Bool {
    if count == 0 { return false }
    return find(member).found
  }

  @inlinable @inline(__always)
  internal func element(at index: Index) -> Element {
    return uncheckedElement(at: validatedBucket(for: index))
  }
}

// ---- insertion -----------------------------------------------------------------------------

extension _NativeSet {
  /// Inserts an element known not to be present into storage with room.
  @inlinable
  internal func _unsafeInsertNew(_ element: __owned Element) {
    let hashValue = self.hashValue(for: element)
    let bucket: Bucket
    if _isDebugAssertConfiguration() {
      let (hole, found) = find(element, hashValue: hashValue)
      if found {
        ELEMENT_TYPE_OF_SET_VIOLATES_HASHABLE_REQUIREMENTS(Element.self)
      }
      hashTable.insert(hole)
      bucket = hole
    } else {
      bucket = hashTable.insertNew(hashValue: hashValue)
    }
    uncheckedInitialize(at: bucket, to: element)
    _storage._count &+= 1
  }

  @inlinable
  internal mutating func insertNew(_ element: __owned Element, isUnique: Bool) {
    _ = ensureUnique(isUnique: isUnique, capacity: count &+ 1)
    _unsafeInsertNew(element)
  }

  /// Fills the hole `bucket` (from a failed find).
  @inlinable
  internal func _unsafeInsertNew(_ element: __owned Element, at bucket: Bucket) {
    hashTable.insert(bucket)
    uncheckedInitialize(at: bucket, to: element)
    _storage._count &+= 1
  }

  /// Inserts at the hole `bucket` found before growing: if the storage
  /// has to grow first, the element goes wherever it lands.
  @inlinable
  internal mutating func insertNew(_ element: __owned Element, at bucket: Bucket, isUnique: Bool) {
    var bucket = bucket
    if ensureUnique(isUnique: isUnique, capacity: count &+ 1) {
      let (newBucket, found) = find(element)
      if found {
        ELEMENT_TYPE_OF_SET_VIOLATES_HASHABLE_REQUIREMENTS(Element.self)
      }
      bucket = newBucket
    }
    _unsafeInsertNew(element, at: bucket)
  }

  /// Inserts or replaces; returns the replaced member.
  @inlinable
  internal mutating func update(with element: __owned Element, isUnique: Bool) -> Element? {
    var (bucket, found) = find(element)
    if ensureUnique(isUnique: isUnique, capacity: count &+ (found ? 0 : 1)) {
      let (newBucket, stillFound) = find(element)
      if stillFound != found {
        ELEMENT_TYPE_OF_SET_VIOLATES_HASHABLE_REQUIREMENTS(Element.self)
      }
      bucket = newBucket
    }
    if found {
      let old = (_elements + bucket.offset).move()
      uncheckedInitialize(at: bucket, to: element)
      return old
    }
    _unsafeInsertNew(element, at: bucket)
    return nil
  }

  @_alwaysEmitIntoClient @inlinable
  internal mutating func _unsafeUpdate(with element: __owned Element) {
    let (bucket, found) = find(element)
    if found {
      uncheckedAssign(at: bucket, to: element)
    } else {
      _precondition(count < capacity)
      _unsafeInsertNew(element, at: bucket)
    }
  }
}

extension _NativeSet {
  @inlinable @inline(__always)
  internal func isEqual(to other: _NativeSet) -> Bool {
    if _storage === other._storage { return true }
    if count != other.count { return false }
    for member in self {
      if !other.find(member).found { return false }
    }
    return true
  }
}

// ---- removal ---------------------------------------------------------------------------------

extension _NativeSet: _HashTableDelegate {
  @inlinable @inline(__always)
  internal func hashValue(at bucket: Bucket) -> Int {
    return hashValue(for: uncheckedElement(at: bucket))
  }

  @inlinable @inline(__always)
  internal func moveEntry(from source: Bucket, to target: Bucket) {
    (_elements + target.offset).moveInitialize(from: _elements + source.offset, count: 1)
  }
}

extension _NativeSet {
  /// Removes the (already moved-out) member at `bucket` from the table.
  @inlinable @_effects(releasenone)
  internal mutating func _delete(at bucket: Bucket) {
    hashTable.delete(at: bucket, with: self)
    _storage._count -= 1
    invalidateIndices()
  }

  @inlinable @inline(__always)
  internal mutating func uncheckedRemove(at bucket: Bucket, isUnique: Bool) -> Element {
    _ = ensureUnique(isUnique: isUnique, capacity: capacity)
    let old = (_elements + bucket.offset).move()
    _delete(at: bucket)
    return old
  }

  @usableFromInline
  internal mutating func removeAll(isUnique: Bool) {
    if !isUnique {
      _storage = _SetStorage<Element>.allocate(scale: _storage._scale, age: nil, seed: nil)
      return
    }
    for bucket in hashTable {
      (_elements + bucket.offset).deinitialize(count: 1)
    }
    hashTable.clear()
    _storage._count = 0
    invalidateIndices()
  }
}

// ---- iteration ----------------------------------------------------------------------------------

extension _NativeSet: Sequence {
  @usableFromInline @frozen
  internal struct Iterator {
    @usableFromInline internal let base: _NativeSet
    @usableFromInline internal var iterator: _HashTable.Iterator

    @inlinable @inline(__always)
    internal init(_ base: __owned _NativeSet) {
      self.base = base
      self.iterator = base.hashTable.makeIterator()
    }
  }

  @inlinable @inline(__always)
  internal __consuming func makeIterator() -> Iterator {
    return Iterator(self)
  }
}

extension _NativeSet.Iterator: IteratorProtocol {
  @inlinable @inline(__always)
  internal mutating func next() -> Element? {
    guard let bucket = iterator.next() else { return nil }
    return base.uncheckedElement(at: bucket)
  }
}

// ---- set operations -------------------------------------------------------------------------------

extension _NativeSet {
  @_alwaysEmitIntoClient
  internal func isSubset<S: Sequence>(of possibleSuperset: S) -> Bool where S.Element == Element {
    // Mark each member of self that the other sequence contains.
    return _UnsafeBitset.withTemporaryBitset(capacity: bucketCount) { seen in
      var seenCount = 0
      if seenCount == count { return true }
      for element in possibleSuperset {
        let (bucket, found) = find(element)
        if found && seen.uncheckedInsert(bucket.offset) {
          seenCount += 1
          if seenCount == count { return true }
        }
      }
      return false
    }
  }

  @_alwaysEmitIntoClient
  internal func isStrictSubset<S: Sequence>(of possibleSuperset: S) -> Bool where S.Element == Element {
    // A subset, and the other sequence has something we lack.
    return _UnsafeBitset.withTemporaryBitset(capacity: bucketCount) { seen in
      var seenCount = 0
      var isStrict = false
      for element in possibleSuperset {
        let (bucket, found) = find(element)
        if !found {
          isStrict = true
          if seenCount == count { return true }
        } else if seen.uncheckedInsert(bucket.offset) {
          seenCount += 1
          if seenCount == count && isStrict { return true }
        }
      }
      return false
    }
  }

  @_alwaysEmitIntoClient
  internal func isStrictSuperset<S: Sequence>(of possibleSubset: S) -> Bool where S.Element == Element {
    // Contains every element of the other sequence, and has more.
    return _UnsafeBitset.withTemporaryBitset(capacity: bucketCount) { seen in
      var seenCount = 0
      for element in possibleSubset {
        let (bucket, found) = find(element)
        if !found { return false }
        if seen.uncheckedInsert(bucket.offset) {
          seenCount += 1
          if seenCount == count { return false }
        }
      }
      return seenCount < count
    }
  }

  /// A set of the `count` members whose buckets are in `bitset`.
  @_alwaysEmitIntoClient
  internal __consuming func extractSubset(using bitset: _UnsafeBitset, count: Int) -> _NativeSet {
    if count == 0 { return _NativeSet() }
    if count == self.count { return self }
    let result = _NativeSet(capacity: count)
    var remaining = count
    for offset in bitset {
      result._unsafeInsertNew(uncheckedElement(at: Bucket(offset: offset)))
      remaining -= 1
      if remaining == 0 { break }
    }
    return result
  }

  @_alwaysEmitIntoClient
  internal __consuming func subtracting<S: Sequence>(_ other: S) -> _NativeSet where S.Element == Element {
    if count == 0 { return _NativeSet() }
    // Mark the members to remove; keep the rest.
    return _UnsafeBitset.withTemporaryBitset(capacity: bucketCount) { removed in
      var removedCount = 0
      for element in other {
        let (bucket, found) = find(element)
        if found && removed.uncheckedInsert(bucket.offset) {
          removedCount += 1
          if removedCount == count { return _NativeSet() }
        }
      }
      if removedCount == 0 { return self }
      // Turn "removed" into "kept".
      var word = 0
      let table = hashTable
      while word < removed.wordCount {
        removed.words[word] = _UnsafeBitset.Word(table.words[word].value & ~removed.words[word].value)
        word += 1
      }
      if bucketCount < 64 {
        removed.words[0] = removed.words[0].intersecting(elementsBelow: bucketCount)
      }
      return extractSubset(using: removed, count: count - removedCount)
    }
  }

  @_alwaysEmitIntoClient
  internal __consuming func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> _NativeSet {
    return try _UnsafeBitset.withTemporaryBitset(capacity: bucketCount) { kept in
      var keptCount = 0
      for bucket in hashTable {
        if try isIncluded(uncheckedElement(at: bucket)) {
          kept.uncheckedInsert(bucket.offset)
          keptCount += 1
        }
      }
      return extractSubset(using: kept, count: keptCount)
    }
  }

  @_alwaysEmitIntoClient
  internal __consuming func intersection(_ other: _NativeSet) -> _NativeSet {
    // Probe the larger set with the members of the smaller one.
    if self.count > other.count { return other.intersection(self) }
    return _UnsafeBitset.withTemporaryBitset(capacity: bucketCount) { kept in
      var keptCount = 0
      for bucket in hashTable {
        if other.find(uncheckedElement(at: bucket)).found {
          kept.uncheckedInsert(bucket.offset)
          keptCount += 1
        }
      }
      return extractSubset(using: kept, count: keptCount)
    }
  }

  @_alwaysEmitIntoClient
  internal __consuming func genericIntersection<S: Sequence>(_ other: S) -> _NativeSet
    where S.Element == Element {
    return _UnsafeBitset.withTemporaryBitset(capacity: bucketCount) { kept in
      var keptCount = 0
      for element in other {
        let (bucket, found) = find(element)
        if found && kept.uncheckedInsert(bucket.offset) {
          keptCount += 1
          if keptCount == count { break }
        }
      }
      return extractSubset(using: kept, count: keptCount)
    }
  }
}
