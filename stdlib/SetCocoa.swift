// The Objective-C half of Set's representation (a bridged NSSet). As with
// __CocoaDictionary, the entry points exist and stop with a report until
// bridging is implemented.

@usableFromInline @inline(never)
internal func _cocoaSetUnsupported() -> Never {
  _fatalErrorMessage("Fatal error", "Set bridged from NSSet is not supported yet",
                     file: #file, line: #line, flags: 0)
}

@usableFromInline @frozen
internal struct __CocoaSet {
  @usableFromInline internal let object: AnyObject

  @inlinable
  internal init(_ object: __owned AnyObject) {
    self.object = object
  }
}

extension __CocoaSet {
  @usableFromInline
  internal var count: Int {
    _cocoaSetUnsupported()
  }

  @usableFromInline
  internal func contains(_ element: AnyObject) -> Bool {
    _cocoaSetUnsupported()
  }

  @usableFromInline
  internal func member(for element: AnyObject) -> AnyObject? {
    _cocoaSetUnsupported()
  }

  @usableFromInline
  internal func element(at index: Index) -> AnyObject {
    _cocoaSetUnsupported()
  }

  @usableFromInline
  internal var startIndex: Index {
    _cocoaSetUnsupported()
  }

  @usableFromInline
  internal var endIndex: Index {
    _cocoaSetUnsupported()
  }

  @usableFromInline
  internal func index(after index: Index) -> Index {
    _cocoaSetUnsupported()
  }

  @usableFromInline
  internal func formIndex(after index: inout Index, isUnique: Bool) {
    _cocoaSetUnsupported()
  }

  @usableFromInline
  internal func index(for element: AnyObject) -> Index? {
    _cocoaSetUnsupported()
  }

  @usableFromInline
  internal func makeIterator() -> Iterator {
    _cocoaSetUnsupported()
  }
}

extension __CocoaSet {
  /// A position in a bridged set: a shared snapshot of its members (held as
  /// a BridgeObject) and an offset into it.
  @usableFromInline @frozen
  internal struct Index {
    internal var _storage: Builtin.BridgeObject
    internal var _offset: Int
  }
}

extension __CocoaSet.Index {
  @usableFromInline
  internal var handleBitPattern: UInt {
    @_effects(readonly) get { return _bitPattern(_storage) }
  }

  @usableFromInline @nonobjc
  internal var element: AnyObject {
    _cocoaSetUnsupported()
  }

  @usableFromInline @nonobjc
  internal var age: Int32 {
    _cocoaSetUnsupported()
  }
}

extension __CocoaSet.Index: Equatable {
  @usableFromInline
  internal static func == (lhs: __CocoaSet.Index, rhs: __CocoaSet.Index) -> Bool {
    return lhs._offset == rhs._offset
  }
}

extension __CocoaSet.Index: Comparable {
  @usableFromInline
  internal static func < (lhs: __CocoaSet.Index, rhs: __CocoaSet.Index) -> Bool {
    return lhs._offset < rhs._offset
  }
}

extension __CocoaSet {
  @usableFromInline
  final internal class Iterator {
    internal init() {}

    @usableFromInline
    internal func next() -> AnyObject? {
      _cocoaSetUnsupported()
    }
  }
}

extension _NativeSet {
  @inlinable
  internal init(_ cocoa: __owned __CocoaSet) {
    self.init(cocoa, capacity: cocoa.count)
  }

  @inlinable
  internal init(_ cocoa: __owned __CocoaSet, capacity: Int) {
    if capacity == 0 {
      self.init()
      return
    }
    self.init(_SetStorage<Element>.convert(cocoa, capacity: capacity))
    _cocoaSetUnsupported()
  }
}

extension _SetStorage {
  @usableFromInline @_effects(releasenone)
  internal static func convert(_ cocoa: __CocoaSet, capacity: Int) -> _SetStorage {
    _cocoaSetUnsupported()
  }
}
