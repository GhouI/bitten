// Native storage of Dictionary: one object holding the header, then (tail
// allocated) the occupancy bitmap, the keys and the values.
//
//   +0   isa, reference count        (Swift object header)
//   +16  _count          Int
//   +24  _capacity       Int         elements that fit before resizing
//   +32  _scale          Int8        2^scale buckets
//   +33  _reservedScale  Int8        scale requested by reserveCapacity
//   +34  _extra          Int16
//   +36  _age            Int32       changes when indices are invalidated
//   +40  _seed           Int         per-storage hash seed
//   +48  _rawKeys        pointer to 2^scale keys
//   +56  _rawValues      pointer to 2^scale values
//   +64  bitmap words, then the keys, then the values
//
// Programs read all of these fields directly (lookups and iteration are
// inlined), so the layout is ABI. It is checked against the Rex binary's
// inlined lookups (scale at +32, keys at +48, bitmap at +64).

@usableFromInline @_fixed_layout
internal class __SwiftNativeNSDictionary {
  @inlinable internal init() {}
  @inlinable deinit {}
}

@usableFromInline @_fixed_layout @_objc_non_lazy_realization
internal class __RawDictionaryStorage: __SwiftNativeNSDictionary {
  @usableFromInline @nonobjc internal final var _count: Int
  @usableFromInline @nonobjc internal final var _capacity: Int
  @usableFromInline @nonobjc internal final var _scale: Int8
  @usableFromInline @nonobjc internal final var _reservedScale: Int8
  @nonobjc internal final var _extra: Int16
  @usableFromInline @nonobjc internal final var _age: Int32
  @usableFromInline internal final var _seed: Int
  @usableFromInline @nonobjc internal final var _rawKeys: UnsafeMutableRawPointer
  @usableFromInline @nonobjc internal final var _rawValues: UnsafeMutableRawPointer

  // Storage objects are created by Builtin.allocWithTailElems and filled
  // in field by field; this initializer only exists to satisfy the
  // language.
  @nonobjc internal init(_doNotCallMe: ()) {
    Builtin.int_trap()
  }

  @usableFromInline deinit {}

  @inlinable @nonobjc internal final var _bucketCount: Int {
    @inline(__always) get { return 1 &<< Int(_scale) }
  }

  @inlinable @nonobjc internal final var _metadata: UnsafeMutablePointer<_HashTable.Word> {
    @inline(__always) get {
      return UnsafeMutablePointer(Builtin.projectTailElems(self, _HashTable.Word.self))
    }
  }

  @inlinable @nonobjc internal final var _hashTable: _HashTable {
    @inline(__always) get {
      return _HashTable(words: _metadata, bucketCount: _bucketCount)
    }
  }
}

/// The class of the statically allocated empty storage (GlobalObjects.c).
/// No instance is ever created or destroyed.
@usableFromInline @_fixed_layout @_objc_non_lazy_realization
internal class __EmptyDictionarySingleton: __RawDictionaryStorage {
  @nonobjc override internal init(_doNotCallMe: ()) {
    Builtin.int_trap()
  }
  @usableFromInline deinit {}
}

@usableFromInline @_silgen_name("_swift_bitten_emptyDictionarySingleton")
internal func _emptyDictionarySingletonAddress() -> Builtin.RawPointer

extension __RawDictionaryStorage {
  @inlinable @nonobjc
  internal static var empty: __EmptyDictionarySingleton {
    return Builtin.bridgeFromRawPointer(_emptyDictionarySingletonAddress())
  }

  @_alwaysEmitIntoClient @inline(__always)
  internal final func uncheckedKey<Key: Hashable>(at bucket: _HashTable.Bucket) -> Key {
    defer { _fixLifetime(self) }
    return _rawKeys.assumingMemoryBound(to: Key.self)[bucket.offset]
  }

  @_alwaysEmitIntoClient @inline(never)
  internal final func find<Key: Hashable>(_ key: Key) -> (bucket: _HashTable.Bucket, found: Bool) {
    return find(key, hashValue: key._rawHashValue(seed: _seed))
  }

  @_alwaysEmitIntoClient @inline(never)
  internal final func find<Key: Hashable>(_ key: Key, hashValue: Int)
    -> (bucket: _HashTable.Bucket, found: Bool) {
    let table = _hashTable
    var bucket = table.idealBucket(forHashValue: hashValue)
    while table._isOccupied(bucket) {
      if uncheckedKey(at: bucket) == key {
        return (bucket, true)
      }
      bucket = table.bucket(wrappedAfter: bucket)
    }
    return (bucket, false)
  }
}

@usableFromInline
final internal class _DictionaryStorage<Key: Hashable, Value>: __RawDictionaryStorage {
  deinit {
    if !_isPOD(Key.self) || !_isPOD(Value.self) {
      for bucket in _hashTable {
        (_keys + bucket.offset).deinitialize(count: 1)
        (_values + bucket.offset).deinitialize(count: 1)
      }
    }
    _fixLifetime(self)
  }

  @inlinable final internal var _keys: UnsafeMutablePointer<Key> {
    @inline(__always) get { return _rawKeys.assumingMemoryBound(to: Key.self) }
  }

  @inlinable final internal var _values: UnsafeMutablePointer<Value> {
    @inline(__always) get { return _rawValues.assumingMemoryBound(to: Value.self) }
  }

  internal var asNative: _NativeDictionary<Key, Value> {
    return _NativeDictionary(self)
  }
}

extension _DictionaryStorage {
  /// New storage with the same scale, age and seed as `original`, so every
  /// element can be copied to the same bucket.
  @usableFromInline @_effects(releasenone)
  internal static func copy(original: __RawDictionaryStorage) -> _DictionaryStorage {
    let storage = allocate(scale: original._scale, age: original._age, seed: original._seed)
    storage._reservedScale = original._reservedScale
    return storage
  }

  /// New, empty storage for at least `capacity` elements (and never fewer
  /// than `original` reserved). The caller moves or copies the elements.
  @usableFromInline @_effects(releasenone)
  internal static func resize(original: __RawDictionaryStorage, capacity: Int,
                              move: Bool) -> _DictionaryStorage {
    var scale = _HashTable.scale(forCapacity: capacity)
    if scale < original._reservedScale { scale = original._reservedScale }
    let storage = allocate(scale: scale, age: nil, seed: nil)
    storage._reservedScale = original._reservedScale
    return storage
  }

  @usableFromInline @_effects(releasenone)
  internal static func allocate(capacity: Int) -> _DictionaryStorage {
    return allocate(scale: _HashTable.scale(forCapacity: capacity), age: nil, seed: nil)
  }

  internal static func allocate(scale: Int8, age: Int32?, seed: Int?) -> _DictionaryStorage {
    let bucketCount = 1 &<< Int(scale)
    let wordCount = _UnsafeBitset.wordCount(forCapacity: bucketCount)
    let storage = Builtin.allocWithTailElems_3(
      _DictionaryStorage<Key, Value>.self,
      wordCount._builtinWordValue, _HashTable.Word.self,
      bucketCount._builtinWordValue, Key.self,
      bucketCount._builtinWordValue, Value.self)
    let words = Builtin.projectTailElems(storage, _HashTable.Word.self)
    let keys = Builtin.getTailAddr_Word(words, wordCount._builtinWordValue, _HashTable.Word.self, Key.self)
    let values = Builtin.getTailAddr_Word(keys, bucketCount._builtinWordValue, Key.self, Value.self)
    storage._count = 0
    storage._capacity = _HashTable.capacity(forScale: scale)
    storage._scale = scale
    storage._reservedScale = 0
    storage._extra = 0
    storage._age = age ?? _HashTable.initialAge(for: storage)
    storage._seed = seed ?? _HashTable.hashSeed(for: storage, scale: scale)
    storage._rawKeys = UnsafeMutableRawPointer(keys)
    storage._rawValues = UnsafeMutableRawPointer(values)
    storage._hashTable.clear()
    return storage
  }
}
