// The Objective-C half of Dictionary's representation: a Dictionary may
// wrap an NSDictionary that was bridged from Objective-C without copying.
// The representation is here (a Dictionary is a _BridgeStorage, the
// Objective-C bit says which half), and so are the entry points programs
// call on the bridged path, but the operations need Foundation's
// NSDictionary and stop with a report until bridging exists. Nothing in
// bitten creates a bridged dictionary yet.

@usableFromInline @inline(never)
internal func _cocoaDictionaryUnsupported() -> Never {
  _fatalErrorMessage("Fatal error", "Dictionary bridged from NSDictionary is not supported yet",
                     file: #file, line: #line, flags: 0)
}

@usableFromInline @frozen
internal struct __CocoaDictionary {
  @usableFromInline internal let object: AnyObject

  @inlinable
  internal init(_ object: __owned AnyObject) {
    self.object = object
  }
}

extension __CocoaDictionary {
  @usableFromInline
  internal var count: Int {
    _cocoaDictionaryUnsupported()
  }

  @usableFromInline
  internal func lookup(_ key: AnyObject) -> AnyObject? {
    _cocoaDictionaryUnsupported()
  }

  @usableFromInline
  internal func lookup(_ index: Index) -> (key: AnyObject, value: AnyObject) {
    _cocoaDictionaryUnsupported()
  }

  @usableFromInline
  internal var startIndex: Index {
    _cocoaDictionaryUnsupported()
  }

  @usableFromInline
  internal var endIndex: Index {
    _cocoaDictionaryUnsupported()
  }

  @usableFromInline
  internal func index(after index: Index) -> Index {
    _cocoaDictionaryUnsupported()
  }

  @usableFromInline
  internal func formIndex(after index: inout Index, isUnique: Bool) {
    _cocoaDictionaryUnsupported()
  }

  @usableFromInline
  internal func index(forKey key: AnyObject) -> Index? {
    _cocoaDictionaryUnsupported()
  }

  @usableFromInline
  internal func makeIterator() -> Iterator {
    _cocoaDictionaryUnsupported()
  }
}

extension __CocoaDictionary {
  /// A position in a bridged dictionary: a shared snapshot of its keys
  /// (an internal class, held as a BridgeObject so the struct can be
  /// frozen) and an offset into it.
  @usableFromInline @frozen
  internal struct Index {
    internal var _storage: Builtin.BridgeObject
    internal var _offset: Int
  }
}

extension __CocoaDictionary.Index {
  @usableFromInline
  internal var handleBitPattern: UInt {
    @_effects(readonly) get { return _bitPattern(_storage) }
  }

  @usableFromInline
  internal var dictionary: __CocoaDictionary {
    _cocoaDictionaryUnsupported()
  }

  @usableFromInline @nonobjc
  internal var key: AnyObject {
    _cocoaDictionaryUnsupported()
  }

  @usableFromInline @nonobjc
  internal var age: Int32 {
    _cocoaDictionaryUnsupported()
  }
}

extension __CocoaDictionary.Index: Equatable {
  @usableFromInline
  internal static func == (lhs: __CocoaDictionary.Index, rhs: __CocoaDictionary.Index) -> Bool {
    return lhs._offset == rhs._offset
  }
}

extension __CocoaDictionary.Index: Comparable {
  @usableFromInline
  internal static func < (lhs: __CocoaDictionary.Index, rhs: __CocoaDictionary.Index) -> Bool {
    return lhs._offset < rhs._offset
  }
}

extension __CocoaDictionary {
  @usableFromInline
  final internal class Iterator {
    internal init() {}

    @usableFromInline
    internal func next() -> (key: AnyObject, value: AnyObject)? {
      _cocoaDictionaryUnsupported()
    }
  }
}

extension _NativeDictionary {
  @inlinable
  internal init(_ cocoa: __owned __CocoaDictionary) {
    self.init(cocoa, capacity: cocoa.count)
  }

  @inlinable
  internal init(_ cocoa: __owned __CocoaDictionary, capacity: Int) {
    if capacity == 0 {
      self.init()
      return
    }
    self.init(_DictionaryStorage<Key, Value>.convert(cocoa, capacity: capacity))
    _cocoaDictionaryUnsupported()
  }
}

extension _DictionaryStorage {
  @usableFromInline @_effects(releasenone)
  internal static func convert(_ cocoa: __CocoaDictionary, capacity: Int) -> _DictionaryStorage {
    _cocoaDictionaryUnsupported()
  }
}
