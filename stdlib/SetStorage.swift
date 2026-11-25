// Native storage of Set: the same header as Dictionary's storage with one
// element array instead of keys and values.
//
//   +16 _count, +24 _capacity, +32 _scale, +33 _reservedScale, +34 _extra,
//   +36 _age, +40 _seed, +48 _rawElements, +56 bitmap words, then elements.

@usableFromInline @_fixed_layout
internal class __SwiftNativeNSSet {
  @inlinable internal init() {}
  @inlinable deinit {}
}

@usableFromInline @_fixed_layout @_objc_non_lazy_realization
internal class __RawSetStorage: __SwiftNativeNSSet {
  @usableFromInline @nonobjc internal final var _count: Int
  @usableFromInline @nonobjc internal final var _capacity: Int
  @usableFromInline @nonobjc internal final var _scale: Int8
  @usableFromInline @nonobjc internal final var _reservedScale: Int8
  @nonobjc internal final var _extra: Int16
  @usableFromInline @nonobjc internal final var _age: Int32
  @usableFromInline internal final var _seed: Int
  @usableFromInline @nonobjc internal final var _rawElements: UnsafeMutableRawPointer

  // Created by Builtin.allocWithTailElems, never by an initializer.
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
@usableFromInline @_fixed_layout @_objc_non_lazy_realization
internal class __EmptySetSingleton: __RawSetStorage {
  @nonobjc override internal init(_doNotCallMe: ()) {
    Builtin.int_trap()
  }
  @usableFromInline deinit {}
}

@usableFromInline @_silgen_name("_swift_bitten_emptySetSingleton")
internal func _emptySetSingletonAddress() -> Builtin.RawPointer

extension __RawSetStorage {
  @inlinable @nonobjc
  internal static var empty: __EmptySetSingleton {
    return Builtin.bridgeFromRawPointer(_emptySetSingletonAddress())
  }
}

@usableFromInline
final internal class _SetStorage<Element: Hashable>: __RawSetStorage {
  deinit {
    if !_isPOD(Element.self) {
      for bucket in _hashTable {
        (_elements + bucket.offset).deinitialize(count: 1)
      }
    }
    _fixLifetime(self)
  }

  @inlinable final internal var _elements: UnsafeMutablePointer<Element> {
    @inline(__always) get { return _rawElements.assumingMemoryBound(to: Element.self) }
  }
}

extension _SetStorage {
  /// Same scale, age and seed as `original`: every element keeps its bucket.
  @usableFromInline @_effects(releasenone)
  internal static func copy(original: __RawSetStorage) -> _SetStorage {
    let storage = allocate(scale: original._scale, age: original._age, seed: original._seed)
    storage._reservedScale = original._reservedScale
    return storage
  }

  /// New, empty storage for at least `capacity` elements.
  @usableFromInline @_effects(releasenone)
  internal static func resize(original: __RawSetStorage, capacity: Int, move: Bool) -> _SetStorage {
    var scale = _HashTable.scale(forCapacity: capacity)
    if scale < original._reservedScale { scale = original._reservedScale }
    let storage = allocate(scale: scale, age: nil, seed: nil)
    storage._reservedScale = original._reservedScale
    return storage
  }

  @usableFromInline @_effects(releasenone)
  internal static func allocate(capacity: Int) -> _SetStorage {
    return allocate(scale: _HashTable.scale(forCapacity: capacity), age: nil, seed: nil)
  }

  internal static func allocate(scale: Int8, age: Int32?, seed: Int?) -> _SetStorage {
    let bucketCount = 1 &<< Int(scale)
    let wordCount = _UnsafeBitset.wordCount(forCapacity: bucketCount)
    let storage = Builtin.allocWithTailElems_2(
      _SetStorage<Element>.self,
      wordCount._builtinWordValue, _HashTable.Word.self,
      bucketCount._builtinWordValue, Element.self)
    let words = Builtin.projectTailElems(storage, _HashTable.Word.self)
    let elements = Builtin.getTailAddr_Word(words, wordCount._builtinWordValue,
                                            _HashTable.Word.self, Element.self)
    storage._count = 0
    storage._capacity = _HashTable.capacity(forScale: scale)
    storage._scale = scale
    storage._reservedScale = 0
    storage._extra = 0
    storage._age = age ?? _HashTable.initialAge(for: storage)
    storage._seed = seed ?? _HashTable.hashSeed(for: storage, scale: scale)
    storage._rawElements = UnsafeMutableRawPointer(elements)
    storage._hashTable.clear()
    return storage
  }
}
