// Key paths: the class hierarchy AnyKeyPath > PartialKeyPath<Root> >
// KeyPath<Root, Value> > WritableKeyPath > ReferenceWritableKeyPath, and
// the entry points the compiler calls to project through one
// (`root[keyPath: kp]`).
//
// A key path object is an instance of one of these classes with a
// tail-allocated buffer of instantiated components after the Swift header.
// The buffer is private to the runtime (src/frameworks/swift/keypath.c):
// swift_getKeyPath builds it from the pattern the compiler emits, and every
// operation here hands the object back to the runtime. Clients never look
// inside.

// Runtime side (keypath.c).
@usableFromInline @_silgen_name("_swift_kp_destroy")
internal func _kpDestroy(_ kp: UnsafeRawPointer)
@usableFromInline @_silgen_name("_swift_kp_equal")
internal func _kpEqual(_ a: UnsafeRawPointer, _ b: UnsafeRawPointer) -> Bool
@usableFromInline @_silgen_name("_swift_kp_hash")
internal func _kpHash(_ kp: UnsafeRawPointer) -> Int
@usableFromInline @_silgen_name("_swift_kp_types")
internal func _kpTypes(_ kp: UnsafeRawPointer,
                       _ root: UnsafeMutablePointer<UnsafeRawPointer>,
                       _ value: UnsafeMutablePointer<UnsafeRawPointer>)
@usableFromInline @_silgen_name("_swift_kp_kvc_string")
internal func _kpKVCString(_ kp: UnsafeRawPointer) -> UnsafePointer<CChar>?
/// Reads the value at the end of the path into `out` (uninitialized).
@usableFromInline @_silgen_name("_swift_kp_get")
internal func _kpGet(_ root: UnsafeRawPointer, _ kp: UnsafeRawPointer, _ out: UnsafeMutableRawPointer)
/// Starts a mutating access: returns the address of the value; `token`
/// receives what `_kpEndAccess` needs to write back and clean up.
@usableFromInline @_silgen_name("_swift_kp_begin_modify")
internal func _kpBeginModify(_ root: UnsafeRawPointer, _ kp: UnsafeRawPointer,
                             _ token: UnsafeMutablePointer<UnsafeRawPointer?>) -> UnsafeMutableRawPointer
@usableFromInline @_silgen_name("_swift_kp_end_access")
internal func _kpEndAccess(_ token: UnsafeRawPointer?, _ writeBack: Bool)
/// A new key path of class `cls` that applies `root`, then `leaf`.
@usableFromInline @_silgen_name("_swift_kp_append")
internal func _kpAppend(_ root: AnyKeyPath, _ leaf: AnyKeyPath, _ cls: UnsafeRawPointer) -> AnyKeyPath

@inline(__always)
internal func _kpRef(_ kp: AnyKeyPath) -> UnsafeRawPointer {
  return UnsafeRawPointer(Builtin.bridgeToRawPointer(kp))
}

public protocol _AppendKeyPath {}

public class AnyKeyPath: _AppendKeyPath {
  @inlinable public static var rootType: Any.Type { return _rootAndValueType.root }
  @inlinable public static var valueType: Any.Type { return _rootAndValueType.value }

  @usableFromInline
  internal class var _rootAndValueType: (root: Any.Type, value: Any.Type) {
    _preconditionFailure("AnyKeyPath has no root or value type of its own")
  }

  // Never called: instances are made by the runtime.
  @usableFromInline internal init() {}

  deinit { _kpDestroy(_kpRef(self)) }

  /// The Objective-C key path string of a path made of @objc properties
  /// (what KVO observes), or nil.
  final public var _kvcKeyPathString: String? {
    guard let s = _kpKVCString(_kpRef(self)) else { return nil }
    return String(cString: s)
  }

  final public var hashValue: Int { return _hashValue(for: self) }

  final public func hash(into hasher: inout Hasher) {
    hasher.combine(_kpHash(_kpRef(self)))
  }

  public static func ==(a: AnyKeyPath, b: AnyKeyPath) -> Bool {
    if a === b { return true }
    return _kpEqual(_kpRef(a), _kpRef(b))
  }
}

extension AnyKeyPath: Hashable {}

public class PartialKeyPath<Root>: AnyKeyPath {}

public class KeyPath<Root, Value>: PartialKeyPath<Root> {
  @usableFromInline
  internal final override class var _rootAndValueType: (root: Any.Type, value: Any.Type) {
    return (Root.self, Value.self)
  }
}

public class WritableKeyPath<Root, Value>: KeyPath<Root, Value> {}

public class ReferenceWritableKeyPath<Root, Value>: WritableKeyPath<Root, Value> {}

// ---- projections: what `root[keyPath: kp]` compiles to ---------------------

@_silgen_name("swift_getAtKeyPath")
public func _getAtKeyPath<Root, Value>(root: Root, keyPath: KeyPath<Root, Value>) -> Value {
  let out = UnsafeMutablePointer<Value>.allocate(capacity: 1)
  _kpGet(UnsafeRawPointer(Builtin.unprotectedAddressOfBorrow(root)), _kpRef(keyPath),
         UnsafeMutableRawPointer(out))
  let v = out.move()
  out.deallocate()
  return v
}

@_silgen_name("swift_setAtWritableKeyPath")
public func _setAtWritableKeyPath<Root, Value>(root: inout Root, keyPath: WritableKeyPath<Root, Value>,
                                              value: __owned Value) {
  var token: UnsafeRawPointer? = nil
  let p = _kpBeginModify(UnsafeRawPointer(Builtin.unprotectedAddressOf(&root)), _kpRef(keyPath), &token)
  p.assumingMemoryBound(to: Value.self).pointee = value
  _kpEndAccess(token, true)
}

@_silgen_name("swift_setAtReferenceWritableKeyPath")
public func _setAtReferenceWritableKeyPath<Root, Value>(root: Root,
                                                       keyPath: ReferenceWritableKeyPath<Root, Value>,
                                                       value: __owned Value) {
  var token: UnsafeRawPointer? = nil
  let p = _kpBeginModify(UnsafeRawPointer(Builtin.unprotectedAddressOfBorrow(root)), _kpRef(keyPath), &token)
  p.assumingMemoryBound(to: Value.self).pointee = value
  _kpEndAccess(token, true)
}

@_silgen_name("swift_getAtPartialKeyPath")
public func _getAtPartialKeyPath<Root>(root: Root, keyPath: PartialKeyPath<Root>) -> Any {
  return _kpGetAny(UnsafeRawPointer(Builtin.unprotectedAddressOfBorrow(root)), keyPath)
}

@_silgen_name("swift_getAtAnyKeyPath")
public func _getAtAnyKeyPath<RootValue>(root: RootValue, keyPath: AnyKeyPath) -> Any? {
  // The root must be of the key path's root type (or a subclass of it).
  func matches<R>(_: R.Type) -> Bool { return root is R }
  if !_openExistential(type(of: keyPath).rootType, do: matches) { return nil }
  return _kpGetAny(UnsafeRawPointer(Builtin.unprotectedAddressOfBorrow(root)), keyPath)
}

internal func _kpGetAny(_ root: UnsafeRawPointer, _ keyPath: AnyKeyPath) -> Any {
  func read<V>(_: V.Type) -> Any {
    let out = UnsafeMutablePointer<V>.allocate(capacity: 1)
    _kpGet(root, _kpRef(keyPath), UnsafeMutableRawPointer(out))
    let v = out.move()
    out.deallocate()
    return v
  }
  return _openExistential(type(of: keyPath).valueType, do: read)
}

// ---- appending -------------------------------------------------------------

// 0 read-only, 1 writable, 2 reference-writable.
internal func _kpKind<R, V>(_ kp: AnyKeyPath, _: R.Type, _: V.Type) -> Int {
  if kp is ReferenceWritableKeyPath<R, V> { return 2 }
  if kp is WritableKeyPath<R, V> { return 1 }
  return 0
}

internal func _kpAppendOpen<R, M, V>(_ root: AnyKeyPath, _ leaf: AnyKeyPath,
                                     _ r: R.Type, _ m: M.Type, _ v: V.Type) -> AnyKeyPath {
  let a = _kpKind(root, r, m), b = _kpKind(leaf, m, v)
  let kind = b == 2 ? 2 : a == 2 ? (b == 1 ? 2 : 0) : (a == 1 && b == 1 ? 1 : 0)
  let cls: AnyClass = kind == 2 ? ReferenceWritableKeyPath<R, V>.self
                    : kind == 1 ? WritableKeyPath<R, V>.self : KeyPath<R, V>.self
  return _kpAppend(root, leaf, unsafeBitCast(cls, to: UnsafeRawPointer.self))
}

@usableFromInline
internal func _tryToAppendKeyPaths<Result: AnyKeyPath>(root: AnyKeyPath, leaf: AnyKeyPath) -> Result? {
  let (r, m) = type(of: root)._rootAndValueType
  let (m2, v) = type(of: leaf)._rootAndValueType
  if ObjectIdentifier(m) != ObjectIdentifier(m2) { return nil }
  func open3<R>(_ r: R.Type) -> AnyKeyPath {
    func open2<M>(_ m: M.Type) -> AnyKeyPath {
      func open1<V>(_ v: V.Type) -> AnyKeyPath { return _kpAppendOpen(root, leaf, r, m, v) }
      return _openExistential(v, do: open1)
    }
    return _openExistential(m, do: open2)
  }
  return _openExistential(r, do: open3) as? Result
}

@usableFromInline
internal func _appendingKeyPaths<Root, Value, AppendedValue, Result: KeyPath<Root, AppendedValue>>(
  root: KeyPath<Root, Value>, leaf: KeyPath<Value, AppendedValue>
) -> Result {
  let kp = _kpAppendOpen(root, leaf, Root.self, Value.self, AppendedValue.self)
  return unsafeDowncast(kp, to: Result.self)
}

extension _AppendKeyPath where Self == AnyKeyPath {
  @inlinable public func appending(path: AnyKeyPath) -> AnyKeyPath? {
    return _tryToAppendKeyPaths(root: self, leaf: path)
  }
}

extension _AppendKeyPath /* where Self == PartialKeyPath<T> */ {
  @inlinable
  public func appending<Root>(path: AnyKeyPath) -> PartialKeyPath<Root>?
  where Self == PartialKeyPath<Root> {
    return _tryToAppendKeyPaths(root: self, leaf: path)
  }
  @inlinable
  public func appending<Root, AppendedRoot, AppendedValue>(
    path: KeyPath<AppendedRoot, AppendedValue>
  ) -> KeyPath<Root, AppendedValue>? where Self == PartialKeyPath<Root> {
    return _tryToAppendKeyPaths(root: self, leaf: path)
  }
  @inlinable
  public func appending<Root, AppendedRoot, AppendedValue>(
    path: ReferenceWritableKeyPath<AppendedRoot, AppendedValue>
  ) -> ReferenceWritableKeyPath<Root, AppendedValue>? where Self == PartialKeyPath<Root> {
    return _tryToAppendKeyPaths(root: self, leaf: path)
  }
}

extension _AppendKeyPath /* where Self == KeyPath<T,U> */ {
  @inlinable
  public func appending<Root, Value, AppendedValue>(
    path: KeyPath<Value, AppendedValue>
  ) -> KeyPath<Root, AppendedValue> where Self: KeyPath<Root, Value> {
    return _appendingKeyPaths(root: self, leaf: path)
  }
  @inlinable
  public func appending<Root, Value, AppendedValue>(
    path: ReferenceWritableKeyPath<Value, AppendedValue>
  ) -> ReferenceWritableKeyPath<Root, AppendedValue> where Self == KeyPath<Root, Value> {
    return _appendingKeyPaths(root: self, leaf: path)
  }
}

extension _AppendKeyPath /* where Self == WritableKeyPath<T,U> */ {
  @inlinable
  public func appending<Root, Value, AppendedValue>(
    path: WritableKeyPath<Value, AppendedValue>
  ) -> WritableKeyPath<Root, AppendedValue> where Self == WritableKeyPath<Root, Value> {
    return _appendingKeyPaths(root: self, leaf: path)
  }
  @inlinable
  public func appending<Root, Value, AppendedValue>(
    path: ReferenceWritableKeyPath<Value, AppendedValue>
  ) -> ReferenceWritableKeyPath<Root, AppendedValue> where Self == WritableKeyPath<Root, Value> {
    return _appendingKeyPaths(root: self, leaf: path)
  }
}

extension _AppendKeyPath /* where Self == ReferenceWritableKeyPath<T,U> */ {
  @inlinable
  public func appending<Root, Value, AppendedValue>(
    path: WritableKeyPath<Value, AppendedValue>
  ) -> ReferenceWritableKeyPath<Root, AppendedValue> where Self == ReferenceWritableKeyPath<Root, Value> {
    return _appendingKeyPaths(root: self, leaf: path)
  }
}
