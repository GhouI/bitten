// _NativeDictionary: a Dictionary backed by our own hash table storage (as
// opposed to a bridged NSDictionary). A struct around the storage
// reference; copy-on-write is decided by the caller, which passes
// `isUnique` in.

@usableFromInline @frozen
internal struct _NativeDictionary<Key: Hashable, Value> {
  @usableFromInline internal typealias Element = (key: Key, value: Value)

  @usableFromInline
  internal var _storage: __RawDictionaryStorage

  @inlinable
  internal init() {
    self._storage = __RawDictionaryStorage.empty
  }

  @inlinable
  internal init(_ storage: __owned __RawDictionaryStorage) {
    self._storage = storage
  }

  @inlinable
  internal init(capacity: Int) {
    if capacity == 0 {
      self._storage = __RawDictionaryStorage.empty
    } else {
      self._storage = _DictionaryStorage<Key, Value>.allocate(capacity: capacity)
    }
  }
}

extension _NativeDictionary {
  @usableFromInline internal typealias Bucket = _HashTable.Bucket

  @inlinable internal var capacity: Int {
    @inline(__always) get { return _assumeNonNegative(_storage._capacity) }
  }
  @inlinable internal var hashTable: _HashTable {
    @inline(__always) get { return _storage._hashTable }
  }
  @inlinable internal var age: Int32 {
    @inline(__always) get { return _storage._age }
  }
  // Not inlined by every client: Rex calls these two.
  @inlinable internal var _keys: UnsafeMutablePointer<Key> {
    return _storage._rawKeys.assumingMemoryBound(to: Key.self)
  }
  @inlinable internal var _values: UnsafeMutablePointer<Value> {
    return _storage._rawValues.assumingMemoryBound(to: Value.self)
  }

  @inlinable @inline(__always)
  internal func invalidateIndices() {
    _storage._age &+= 1
  }
}

extension _NativeDictionary {
  @inlinable @inline(__always)
  internal func uncheckedKey(at bucket: Bucket) -> Key {
    defer { _fixLifetime(self) }
    return _keys[bucket.offset]
  }
  @inlinable @inline(__always)
  internal func uncheckedValue(at bucket: Bucket) -> Value {
    defer { _fixLifetime(self) }
    return _values[bucket.offset]
  }
  @inlinable @inline(__always)
  internal func uncheckedInitialize(at bucket: Bucket, toKey key: __owned Key, value: __owned Value) {
    defer { _fixLifetime(self) }
    (_keys + bucket.offset).initialize(to: key)
    (_values + bucket.offset).initialize(to: value)
  }
  @inlinable @inline(__always)
  internal func uncheckedDestroy(at bucket: Bucket) {
    defer { _fixLifetime(self) }
    (_keys + bucket.offset).deinitialize(count: 1)
    (_values + bucket.offset).deinitialize(count: 1)
  }
}

extension _NativeDictionary {
  @inlinable @inline(__always)
  internal func hashValue(for key: Key) -> Int {
    return key._rawHashValue(seed: _storage._seed)
  }
  @inlinable @inline(__always)
  internal func find(_ key: Key) -> (bucket: Bucket, found: Bool) {
    return _storage.find(key)
  }
  @inlinable @inline(__always)
  internal func find(_ key: Key, hashValue: Int) -> (bucket: Bucket, found: Bool) {
    return _storage.find(key, hashValue: hashValue)
  }
}

// ---- growing and copying -----------------------------------------------------------------

extension _NativeDictionary {
  /// Replaces the storage with a new one for `capacity` elements, moving
  /// the elements (when this is the only reference) or copying them.
  @_alwaysEmitIntoClient @inline(never)
  internal mutating func _copyOrMoveAndResize(capacity: Int, moveElements: Bool) {
    let newCapacity = capacity > self.capacity ? capacity : self.capacity
    let target = _NativeDictionary(
      _DictionaryStorage<Key, Value>.resize(original: _storage, capacity: newCapacity,
                                            move: moveElements))
    if count > 0 {
      for bucket in hashTable {
        if moveElements {
          target._unsafeInsertNew(key: (_keys + bucket.offset).move(),
                                  value: (_values + bucket.offset).move())
        } else {
          target._unsafeInsertNew(key: uncheckedKey(at: bucket), value: uncheckedValue(at: bucket))
        }
      }
      if moveElements {
        // The old storage no longer owns anything.
        _storage._hashTable.clear()
        _storage._count = 0
      }
    }
    _storage = target._storage
  }

  @inlinable
  internal mutating func resize(capacity: Int) {
    _copyOrMoveAndResize(capacity: capacity, moveElements: true)
  }

  @inlinable
  internal mutating func copyAndResize(capacity: Int) {
    _copyOrMoveAndResize(capacity: capacity, moveElements: false)
  }

  /// Replaces shared storage with a private copy of the same shape: every
  /// element lands in the same bucket.
  @inlinable
  internal mutating func copy() {
    let target = _NativeDictionary(_DictionaryStorage<Key, Value>.copy(original: _storage))
    if count > 0 {
      target.hashTable.copyContents(of: hashTable)
      target._storage._count = count
      for bucket in hashTable {
        target.uncheckedInitialize(at: bucket, toKey: uncheckedKey(at: bucket),
                                   value: uncheckedValue(at: bucket))
      }
    }
    _storage = target._storage
  }

  /// Makes the storage unique and able to hold `capacity` elements.
  /// Returns true if the elements moved to different buckets (so buckets
  /// found before are stale).
  @inlinable
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
    if _storage !== __RawDictionaryStorage.empty {
      let scale = _HashTable.scale(forCapacity: capacity)
      if scale > _storage._reservedScale { _storage._reservedScale = scale }
    }
  }
}

// ---- indices and lookup ---------------------------------------------------------------------

extension _NativeDictionary {
  @inlinable @inline(__always)
  internal func validatedBucket(for index: _HashTable.Index) -> Bucket {
    _precondition(hashTable.isOccupied(index.bucket) && index.age == age,
                  "Attempting to access Dictionary elements using an invalid index")
    return index.bucket
  }

  @inlinable @inline(__always)
  internal func validatedBucket(for index: Dictionary<Key, Value>.Index) -> Bucket {
    guard index._isNative else {
      // Indices of a bridged NSDictionary are never valid in native storage
      // here: bridging is not implemented.
      _preconditionFailure("Attempting to access Dictionary elements using an invalid index")
    }
    return validatedBucket(for: index._asNative)
  }
}

extension _NativeDictionary {
  @usableFromInline internal typealias Index = Dictionary<Key, Value>.Index

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
  @inlinable
  internal func index(forKey key: Key) -> Index? {
    if count == 0 { return nil }
    let (bucket, found) = find(key)
    if !found { return nil }
    return Index(_native: _HashTable.Index(bucket: bucket, age: age))
  }

  @inlinable internal var count: Int {
    @inline(__always) get { return _assumeNonNegative(_storage._count) }
  }

  @inlinable @inline(__always)
  internal func contains(_ key: Key) -> Bool {
    if count == 0 { return false }
    return find(key).found
  }

  @inlinable @inline(__always)
  internal func lookup(_ key: Key) -> Value? {
    if count == 0 { return nil }
    let (bucket, found) = find(key)
    if !found { return nil }
    return uncheckedValue(at: bucket)
  }

  @inlinable @inline(__always)
  internal func lookup(_ index: Index) -> (key: Key, value: Value) {
    let bucket = validatedBucket(for: index)
    return (uncheckedKey(at: bucket), uncheckedValue(at: bucket))
  }

  @inlinable @inline(__always)
  internal func key(at index: Index) -> Key {
    return uncheckedKey(at: validatedBucket(for: index))
  }

  @inlinable @inline(__always)
  internal func value(at index: Index) -> Value {
    return uncheckedValue(at: validatedBucket(for: index))
  }
}

extension _NativeDictionary {
  @inlinable
  internal subscript(key: Key, isUnique isUnique: Bool) -> Value? {
    @inline(__always) get {
      return lookup(key)
    }
    @inline(__always) _modify {
      let (bucket, found) = mutatingFind(key, isUnique: isUnique)
      var value: Value? = found ? (_values + bucket.offset).move() : nil
      defer {
        switch (value, found) {
        case (let newValue?, true):
          (_values + bucket.offset).initialize(to: newValue)
        case (let newValue?, false):
          _insert(at: bucket, key: key, value: newValue)
        case (nil, true):
          // The value was moved out above; drop the key and close the gap.
          (_keys + bucket.offset).deinitialize(count: 1)
          _delete(at: bucket)
        case (nil, false):
          break
        }
      }
      yield &value
    }
  }
}

// ---- insertion -----------------------------------------------------------------------------

extension _NativeDictionary {
  /// Inserts a key known not to be present into storage known to have room.
  @inlinable
  internal func _unsafeInsertNew(key: __owned Key, value: __owned Value) {
    let hashValue = self.hashValue(for: key)
    let bucket: Bucket
    if _isDebugAssertConfiguration() {
      let (hole, found) = find(key, hashValue: hashValue)
      if found {
        KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTS(Key.self)
      }
      hashTable.insert(hole)
      bucket = hole
    } else {
      bucket = hashTable.insertNew(hashValue: hashValue)
    }
    uncheckedInitialize(at: bucket, toKey: key, value: value)
    _storage._count &+= 1
  }

  @_alwaysEmitIntoClient @inlinable
  internal mutating func _unsafeUpdate(key: __owned Key, value: __owned Value) {
    let (bucket, found) = find(key)
    if found {
      (_keys + bucket.offset).pointee = key
      (_values + bucket.offset).pointee = value
    } else {
      _precondition(count < capacity)
      _insert(at: bucket, key: key, value: value)
    }
  }

  @inlinable
  internal mutating func insertNew(key: __owned Key, value: __owned Value) {
    _ = ensureUnique(isUnique: true, capacity: count &+ 1)
    _unsafeInsertNew(key: key, value: value)
  }

  /// Finds `key`, first making the storage unique and (if the key is not
  /// there) big enough for one more element.
  @inlinable
  internal mutating func mutatingFind(_ key: Key, isUnique: Bool) -> (bucket: Bucket, found: Bool) {
    let (bucket, found) = find(key)
    let moved = ensureUnique(isUnique: isUnique, capacity: count &+ (found ? 0 : 1))
    if !moved { return (bucket, found) }
    let (newBucket, stillFound) = find(key)
    if stillFound != found {
      KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTS(Key.self)
    }
    return (newBucket, found)
  }

  /// Fills the hole `bucket` (from a failed find) with a new element.
  @inlinable
  internal func _insert(at bucket: Bucket, key: __owned Key, value: __owned Value) {
    hashTable.insert(bucket)
    uncheckedInitialize(at: bucket, toKey: key, value: value)
    _storage._count += 1
  }

  @inlinable
  internal mutating func updateValue(_ value: __owned Value, forKey key: Key,
                                     isUnique: Bool) -> Value? {
    let (bucket, found) = mutatingFind(key, isUnique: isUnique)
    if !found {
      _insert(at: bucket, key: key, value: value)
      return nil
    }
    let old = (_values + bucket.offset).move()
    (_values + bucket.offset).initialize(to: value)
    return old
  }

  @inlinable
  internal mutating func setValue(_ value: __owned Value, forKey key: Key, isUnique: Bool) {
    let (bucket, found) = mutatingFind(key, isUnique: isUnique)
    if found {
      (_values + bucket.offset).pointee = value
    } else {
      _insert(at: bucket, key: key, value: value)
    }
  }
}

extension _NativeDictionary {
  @inlinable @inline(__always)
  internal mutating func swapValuesAt(_ a: Bucket, _ b: Bucket, isUnique: Bool) {
    _ = ensureUnique(isUnique: isUnique, capacity: capacity)
    let saved = (_values + a.offset).move()
    (_values + a.offset).moveInitialize(from: _values + b.offset, count: 1)
    (_values + b.offset).initialize(to: saved)
  }

  /// A dictionary of the `count` members whose buckets are in `bitset`.
  @_alwaysEmitIntoClient
  internal func extractDictionary(using bitset: _UnsafeBitset, count: Int) -> _NativeDictionary {
    if count == 0 { return _NativeDictionary() }
    if count == self.count { return self }
    let result = _NativeDictionary(capacity: count)
    var remaining = count
    for offset in bitset {
      let bucket = Bucket(offset: offset)
      result._unsafeInsertNew(key: uncheckedKey(at: bucket), value: uncheckedValue(at: bucket))
      remaining -= 1
      if remaining == 0 { break }
    }
    return result
  }
}

extension _NativeDictionary where Value: Equatable {
  @inlinable @inline(__always)
  internal func isEqual(to other: _NativeDictionary) -> Bool {
    if _storage === other._storage { return true }
    if count != other.count { return false }
    for (key, value) in self {
      let (bucket, found) = other.find(key)
      if !found || other.uncheckedValue(at: bucket) != value { return false }
    }
    return true
  }
}

// ---- removal ---------------------------------------------------------------------------------

extension _NativeDictionary: _HashTableDelegate {
  @inlinable @inline(__always)
  internal func hashValue(at bucket: Bucket) -> Int {
    return hashValue(for: uncheckedKey(at: bucket))
  }

  @inlinable @inline(__always)
  internal func moveEntry(from source: Bucket, to target: Bucket) {
    (_keys + target.offset).moveInitialize(from: _keys + source.offset, count: 1)
    (_values + target.offset).moveInitialize(from: _values + source.offset, count: 1)
  }

  @inlinable @inline(__always)
  internal func swapEntry(_ left: Bucket, with right: Bucket) {
    swap(&_keys[left.offset], &_keys[right.offset])
    swap(&_values[left.offset], &_values[right.offset])
  }
}

extension _NativeDictionary {
  /// Removes the member at `bucket` from the table; its key and value have
  /// already been moved out or destroyed.
  @inlinable @_effects(releasenone)
  internal func _delete(at bucket: Bucket) {
    hashTable.delete(at: bucket, with: self)
    _storage._count -= 1
    invalidateIndices()
  }

  @inlinable
  internal mutating func uncheckedRemove(at bucket: Bucket, isUnique: Bool) -> Element {
    _ = ensureUnique(isUnique: isUnique, capacity: capacity)
    let key = (_keys + bucket.offset).move()
    let value = (_values + bucket.offset).move()
    _delete(at: bucket)
    return (key, value)
  }

  @usableFromInline
  internal mutating func removeAll(isUnique: Bool) {
    if !isUnique {
      // Leave the shared storage alone; start over with the same size.
      _storage = _DictionaryStorage<Key, Value>.allocate(scale: _storage._scale, age: nil, seed: nil)
      return
    }
    for bucket in hashTable {
      uncheckedDestroy(at: bucket)
    }
    hashTable.clear()
    _storage._count = 0
    invalidateIndices()
  }
}

// ---- whole-dictionary operations ---------------------------------------------------------------

extension _NativeDictionary {
  @inlinable
  internal func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> _NativeDictionary<Key, T> {
    // Same seed and scale: each key keeps its bucket.
    let result = _NativeDictionary<Key, T>(_DictionaryStorage<Key, T>.copy(original: _storage))
    for bucket in hashTable {
      let newValue = try transform(uncheckedValue(at: bucket))
      result._insert(at: bucket, key: uncheckedKey(at: bucket), value: newValue)
    }
    return result
  }

  @inlinable
  internal mutating func merge<S: Sequence>(
    _ keysAndValues: __owned S, isUnique: Bool,
    uniquingKeysWith combine: (Value, Value) throws -> Value
  ) rethrows where S.Element == (Key, Value) {
    var isUnique = isUnique
    for (key, value) in keysAndValues {
      let (bucket, found) = mutatingFind(key, isUnique: isUnique)
      isUnique = true
      if found {
        let combined = try combine(uncheckedValue(at: bucket), value)
        _values[bucket.offset] = combined
      } else {
        _insert(at: bucket, key: key, value: value)
      }
    }
  }

  @_alwaysEmitIntoClient
  internal func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> _NativeDictionary {
    return try _UnsafeBitset.withTemporaryBitset(capacity: _storage._bucketCount) { bitset in
      var kept = 0
      for bucket in hashTable {
        if try isIncluded((uncheckedKey(at: bucket), uncheckedValue(at: bucket))) {
          bitset.uncheckedInsert(bucket.offset)
          kept += 1
        }
      }
      return extractDictionary(using: bitset, count: kept)
    }
  }
}

// ---- iteration ----------------------------------------------------------------------------------

extension _NativeDictionary: Sequence {
  @usableFromInline @frozen
  internal struct Iterator {
    // Holding the storage keeps it alive (and unchanged: the dictionary
    // copies before mutating) for the whole iteration.
    @usableFromInline internal let base: _NativeDictionary
    @usableFromInline internal var iterator: _HashTable.Iterator

    @inlinable @inline(__always)
    internal init(_ base: __owned _NativeDictionary) {
      self.base = base
      self.iterator = base.hashTable.makeIterator()
    }
  }

  @inlinable
  internal __consuming func makeIterator() -> Iterator {
    return Iterator(self)
  }
}

extension _NativeDictionary.Iterator: IteratorProtocol {
  @usableFromInline internal typealias Element = (key: Key, value: Value)

  @inlinable @inline(__always)
  internal mutating func nextKey() -> Key? {
    guard let bucket = iterator.next() else { return nil }
    return base.uncheckedKey(at: bucket)
  }

  @inlinable @inline(__always)
  internal mutating func nextValue() -> Value? {
    guard let bucket = iterator.next() else { return nil }
    return base.uncheckedValue(at: bucket)
  }

  @inlinable @inline(__always)
  internal mutating func next() -> Element? {
    guard let bucket = iterator.next() else { return nil }
    return (base.uncheckedKey(at: bucket), base.uncheckedValue(at: bucket))
  }
}

// _MergeError (the error init(uniqueKeysWithValues:) throws through merge on
// a duplicate key) comes with the Error protocol, which needs String.
