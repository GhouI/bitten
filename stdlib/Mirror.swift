// Mirror and the types around it: CustomReflectable, KeyValuePairs, and the
// type-erased AnyCollection that holds a mirror's children. Reflection of
// stored properties comes from the runtime (src/frameworks/swift/
// reflection.c); custom mirrors come from CustomReflectable.

// MARK: - runtime reflection

@_silgen_name("_bitten_mirror_display_style")
internal func _bitten_mirror_display_style(_ type: Any.Type) -> Int32
@_silgen_name("_bitten_mirror_count")
internal func _bitten_mirror_count(_ value: UnsafeRawPointer, _ type: Any.Type) -> Int
@_silgen_name("_bitten_mirror_child")
internal func _bitten_mirror_child(_ value: UnsafeRawPointer, _ type: Any.Type, _ index: Int,
                                   _ name: UnsafeMutablePointer<UnsafePointer<CChar>?>,
                                   _ childType: UnsafeMutablePointer<Any.Type?>) -> UnsafeRawPointer?

/// A copy of the value of type `type` at `address`, as Any.
internal func _loadAny(_ address: UnsafeRawPointer, _ type: Any.Type) -> Any {
  func load<T>(_: T.Type) -> Any { return address.assumingMemoryBound(to: T.self).pointee }
  return _openExistential(type, do: load)
}

// MARK: - KeyValuePairs

@frozen
public struct KeyValuePairs<Key, Value>: ExpressibleByDictionaryLiteral {
  @usableFromInline internal let _elements: [(Key, Value)]
  @inlinable public init(dictionaryLiteral elements: (Key, Value)...) { self._elements = elements }
}

extension KeyValuePairs: RandomAccessCollection {
  public typealias Element = (key: Key, value: Value)
  public typealias Index = Int
  public typealias Indices = Range<Int>
  public typealias SubSequence = Slice<KeyValuePairs>
  @inlinable public var startIndex: Index { return 0 }
  @inlinable public var endIndex: Index { return _elements.endIndex }
  @inlinable public subscript(position: Index) -> Element {
    let r = _elements[position]
    return (key: r.0, value: r.1)
  }
}

// MARK: - AnyCollection

@usableFromInline
internal protocol _AnyIndexBox: AnyObject {
  var _typeID: ObjectIdentifier { get }
  func _unbox<T: Comparable>() -> T?
  func _isEqual(to rhs: _AnyIndexBox) -> Bool
  func _isLess(than rhs: _AnyIndexBox) -> Bool
}

@_fixed_layout
@usableFromInline
internal final class _IndexBox<BaseIndex: Comparable>: _AnyIndexBox {
  @usableFromInline internal var _base: BaseIndex
  @inlinable internal init(_base: BaseIndex) { self._base = _base }
  @inlinable internal func _unsafeUnbox(_ other: _AnyIndexBox) -> BaseIndex {
    return unsafeDowncast(other, to: _IndexBox.self)._base
  }
  @inlinable internal var _typeID: ObjectIdentifier { return ObjectIdentifier(type(of: self)) }
  @inlinable internal func _unbox<T: Comparable>() -> T? { return (self as _AnyIndexBox as? _IndexBox<T>)?._base }
  @inlinable internal func _isEqual(to rhs: _AnyIndexBox) -> Bool { return _base == _unsafeUnbox(rhs) }
  @inlinable internal func _isLess(than rhs: _AnyIndexBox) -> Bool { return _base < _unsafeUnbox(rhs) }
}

@frozen
public struct AnyIndex {
  @usableFromInline internal var _box: _AnyIndexBox
  @inlinable public init<BaseIndex: Comparable>(_ base: BaseIndex) { self._box = _IndexBox(_base: base) }
  @inlinable internal init(_box: _AnyIndexBox) { self._box = _box }
  @inlinable internal var _typeID: ObjectIdentifier { return _box._typeID }
}

extension AnyIndex: Comparable {
  @inlinable public static func == (lhs: AnyIndex, rhs: AnyIndex) -> Bool {
    _precondition(lhs._typeID == rhs._typeID, "Base index types differ")
    return lhs._box._isEqual(to: rhs._box)
  }
  @inlinable public static func < (lhs: AnyIndex, rhs: AnyIndex) -> Bool {
    _precondition(lhs._typeID == rhs._typeID, "Base index types differ")
    return lhs._box._isLess(than: rhs._box)
  }
}

/// The erased collection's operations; _CollectionBox implements them over
/// a concrete collection.
@_fixed_layout
@usableFromInline
internal class _AnyCollectionBox<Element> {
  @inlinable internal init() {}
  @inlinable deinit {}
  @usableFromInline internal var _startIndex: _AnyIndexBox { Builtin.unreachable() }
  @usableFromInline internal var _endIndex: _AnyIndexBox { Builtin.unreachable() }
  @usableFromInline internal subscript(position: _AnyIndexBox) -> Element { Builtin.unreachable() }
  @usableFromInline internal func _index(after i: _AnyIndexBox) -> _AnyIndexBox { Builtin.unreachable() }
  @usableFromInline internal var _count: Int { Builtin.unreachable() }
  @usableFromInline internal func _makeIterator() -> AnyIterator<Element> { Builtin.unreachable() }
}

@usableFromInline
internal final class _CollectionBox<S: Collection>: _AnyCollectionBox<S.Element> {
  @usableFromInline internal var _base: S
  @usableFromInline internal init(_base: S) {
    self._base = _base
    super.init()
  }
  @usableFromInline internal func _unbox(_ position: _AnyIndexBox) -> S.Index {
    return unsafeDowncast(position, to: _IndexBox<S.Index>.self)._base
  }
  @usableFromInline override internal var _startIndex: _AnyIndexBox { return _IndexBox(_base: _base.startIndex) }
  @usableFromInline override internal var _endIndex: _AnyIndexBox { return _IndexBox(_base: _base.endIndex) }
  @usableFromInline override internal subscript(position: _AnyIndexBox) -> S.Element { return _base[_unbox(position)] }
  @usableFromInline override internal func _index(after i: _AnyIndexBox) -> _AnyIndexBox {
    return _IndexBox(_base: _base.index(after: _unbox(i)))
  }
  @usableFromInline override internal var _count: Int { return _base.count }
  @usableFromInline override internal func _makeIterator() -> AnyIterator<S.Element> {
    var it = _base.makeIterator()
    return AnyIterator { it.next() }
  }
}

@frozen
public struct AnyIterator<Element> {
  @usableFromInline internal let _next: () -> Element?
  @inlinable public init(_ body: @escaping () -> Element?) { self._next = body }
  @inlinable public init<I: IteratorProtocol>(_ base: I) where I.Element == Element {
    var b = base
    self._next = { b.next() }
  }
}
extension AnyIterator: IteratorProtocol, Sequence {
  @inlinable public func next() -> Element? { return _next() }
}

@frozen
public struct AnyCollection<Element> {
  @usableFromInline internal let _box: _AnyCollectionBox<Element>
  @inlinable internal init(_box: _AnyCollectionBox<Element>) { self._box = _box }
  public init<C: Collection>(_ base: C) where C.Element == Element { self._box = _CollectionBox(_base: base) }
  public init(_ other: AnyCollection<Element>) { self._box = other._box }
}

extension AnyCollection: Collection {
  public typealias Index = AnyIndex
  public typealias Indices = DefaultIndices<AnyCollection>
  public typealias SubSequence = Slice<AnyCollection>
  public typealias Iterator = AnyIterator<Element>
  @inlinable public var startIndex: Index { return AnyIndex(_box: _box._startIndex) }
  @inlinable public var endIndex: Index { return AnyIndex(_box: _box._endIndex) }
  @inlinable public subscript(position: Index) -> Element { return _box[position._box] }
  @inlinable public func index(after i: Index) -> Index { return AnyIndex(_box: _box._index(after: i._box)) }
  @inlinable public var count: Int { return _box._count }
  @inlinable public __consuming func makeIterator() -> Iterator { return _box._makeIterator() }
}

// MARK: - Mirror

public protocol CustomReflectable {
  var customMirror: Mirror { get }
}
public protocol CustomLeafReflectable: CustomReflectable {}

public protocol MirrorPath {}
extension Int: MirrorPath {}
extension String: MirrorPath {}

public struct Mirror {
  public enum DisplayStyle: Sendable {
    case `struct`, `class`, `enum`, tuple, optional, collection, dictionary, `set`
    case foreignReference
  }

  public enum AncestorRepresentation {
    case generated
    case customized(() -> Mirror)
    case suppressed
  }

  public typealias Child = (label: String?, value: Any)
  public typealias Children = AnyCollection<Child>

  public let subjectType: Any.Type
  public let children: Children
  public let displayStyle: DisplayStyle?
  internal let _superclassMirror: () -> Mirror?

  internal init(subjectType: Any.Type, children: [Child], displayStyle: DisplayStyle?,
                superclassMirror: @escaping () -> Mirror? = { nil }) {
    self.subjectType = subjectType
    self.children = AnyCollection(children)
    self.displayStyle = displayStyle
    self._superclassMirror = superclassMirror
  }

  public init(reflecting subject: Any) {
    if let custom = subject as? CustomReflectable {
      self = custom.customMirror
      return
    }
    self = Mirror._reflect(subject, as: type(of: subject))
  }

  /// A mirror from the runtime's view of the value's stored properties.
  internal static func _reflect(_ subject: Any, as subjectType: Any.Type) -> Mirror {
    var value = subject
    let style: DisplayStyle?
    switch _bitten_mirror_display_style(subjectType) {
    case 0x73: style = .struct
    case 0x63: style = .class
    case 0x65: style = .enum
    case 0x6F: style = .optional
    case 0x74: style = .tuple
    default: style = nil
    }
    func children<T>(_: T.Type) -> [Child] {
      return withUnsafeBytes(of: &value) { _ -> [Child] in
        // Copy the value out of the existential to get a stable address.
        var typed = subject as! T
        return withUnsafePointer(to: &typed) { p -> [Child] in
          let raw = UnsafeRawPointer(p)
          var out: [Child] = []
          let n = _bitten_mirror_count(raw, subjectType)
          var i = 0
          while i < n {
            var name: UnsafePointer<CChar>? = nil
            var childType: Any.Type? = nil
            if let addr = _bitten_mirror_child(raw, subjectType, i, &name, &childType), let t = childType {
              out.append((label: name.map { String(cString: $0) }, value: _loadAny(addr, t)))
            } else {
              out.append((label: name.map { String(cString: $0) }, value: ()))
            }
            i += 1
          }
          return out
        }
      }
    }
    if style == .optional {
      // An optional's child is its wrapped value.
      let m = Mirror(subjectType: subjectType, children: [], displayStyle: .optional)
      return m
    }
    let kids = _openExistential(subjectType, do: children)
    return Mirror(subjectType: subjectType, children: kids, displayStyle: style)
  }

  public init<Subject, C: Collection>(_ subject: Subject, children: C, displayStyle: DisplayStyle? = nil,
                                      ancestorRepresentation: AncestorRepresentation = .generated)
  where C.Element == Child {
    self.init(subjectType: Subject.self, children: Array(children), displayStyle: displayStyle,
              superclassMirror: Mirror._ancestor(subject, ancestorRepresentation))
  }

  public init<Subject, C: Collection>(_ subject: Subject, unlabeledChildren: C, displayStyle: DisplayStyle? = nil,
                                      ancestorRepresentation: AncestorRepresentation = .generated) {
    var kids: [Child] = []
    for c in unlabeledChildren { kids.append((label: nil, value: c)) }
    self.init(subjectType: Subject.self, children: kids, displayStyle: displayStyle,
              superclassMirror: Mirror._ancestor(subject, ancestorRepresentation))
  }

  public init<Subject>(_ subject: Subject, children: KeyValuePairs<String, Any>, displayStyle: DisplayStyle? = nil,
                       ancestorRepresentation: AncestorRepresentation = .generated) {
    var kids: [Child] = []
    for (k, v) in children { kids.append((label: k, value: v)) }
    self.init(subjectType: Subject.self, children: kids, displayStyle: displayStyle,
              superclassMirror: Mirror._ancestor(subject, ancestorRepresentation))
  }

  internal static func _ancestor<Subject>(_ subject: Subject, _ rep: AncestorRepresentation) -> () -> Mirror? {
    switch rep {
    case .customized(let make): return { make() }
    case .suppressed, .generated: return { nil }
    }
  }

  public var superclassMirror: Mirror? { return _superclassMirror() }

  public func descendant(_ first: MirrorPath, _ rest: MirrorPath...) -> Any? {
    var current: Any = ()
    var mirror = self
    for (n, step) in ([first] + rest).enumerated() {
      var found: Any? = nil
      if let label = step as? String {
        found = mirror.children.first { $0.label == label }?.value
      } else if let index = step as? Int, index >= 0, index < mirror.children.count {
        var i = mirror.children.startIndex
        for _ in 0..<index { i = mirror.children.index(after: i) }
        found = mirror.children[i].value
      }
      guard let f = found else { return nil }
      current = f
      if n < rest.count { mirror = Mirror(reflecting: f) }
    }
    return current
  }
}

extension Mirror: CustomStringConvertible {
  public var description: String { return "Mirror for \(subjectType)" }
}

// Standard collections describe themselves as collections.
extension Array: CustomReflectable {
  public var customMirror: Mirror { return Mirror(self, unlabeledChildren: self, displayStyle: .collection) }
}
extension Set: CustomReflectable {
  public var customMirror: Mirror { return Mirror(self, unlabeledChildren: self, displayStyle: .set) }
}
extension Dictionary: CustomReflectable {
  public var customMirror: Mirror {
    var kids: [Mirror.Child] = []
    for (k, v) in self { kids.append((label: nil, value: (key: k, value: v))) }
    return Mirror(self, children: kids, displayStyle: .dictionary)
  }
}
extension Optional: CustomReflectable {
  public var customMirror: Mirror {
    switch self {
    case .some(let w): return Mirror(self, children: [(label: "some", value: w)], displayStyle: .optional)
    case .none: return Mirror(self, children: [Mirror.Child](), displayStyle: .optional)
    }
  }
}
