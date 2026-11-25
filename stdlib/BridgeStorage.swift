// References with extra bits: Builtin.BridgeObject and _BridgeStorage, the
// one-word representation of Array, Dictionary and Set on Darwin. The word
// is either a native Swift object (possibly with a flag in a low spare
// bit), an Objective-C object (bit 62 set), or a tagged value (bit 63).
// The compiler tests these bits inline (Builtin.classifyBridgeObject), so
// the values below are the x86-64 Darwin ABI.
//
// Also the uniqueness tests behind copy-on-write, and swap.

// ---- pointer bits ------------------------------------------------------------------

@inlinable internal var _bridgeObjectTaggedPointerBits: UInt {
  @inline(__always) get { return 0x8000_0000_0000_0000 }
}
@inlinable internal var _objCTaggedPointerBits: UInt {
  @inline(__always) get { return 0x8000_0000_0000_0001 }
}
/// Bits of an object pointer that are free for flags: the top byte and the
/// alignment bits, minus the tag bit.
@inlinable internal var _objectPointerSpareBits: UInt {
  @inline(__always) get { return 0x7F00_0000_0000_0007 }
}
/// Objective-C reserves bit 0, so native flags start at bit 1.
@inlinable internal var _objectPointerLowSpareBitShift: UInt {
  @inline(__always) get { return 1 }
}
@inlinable internal var _objectPointerIsObjCBit: UInt {
  @inline(__always) get { return 0x4000_0000_0000_0000 }
}

@inlinable @inline(__always)
internal func _bitPattern(_ x: Builtin.BridgeObject) -> UInt {
  return UInt(Builtin.castBitPatternFromBridgeObject(x))
}
@inlinable @inline(__always)
internal func _nonPointerBits(_ x: Builtin.BridgeObject) -> UInt {
  return _bitPattern(x) & _objectPointerSpareBits
}
@inlinable @inline(__always)
internal func _isObjCTaggedPointer(_ x: AnyObject) -> Bool {
  let bits: UInt = Builtin.reinterpretCast(x)
  return bits & _objCTaggedPointerBits != 0
}
@inlinable @inline(__always)
internal func _isObjCTaggedPointer(_ x: UInt) -> Bool {
  return x & _objCTaggedPointerBits != 0
}
@inlinable @inline(__always)
public func _isTaggedObject(_ x: Builtin.BridgeObject) -> Bool {
  return _bitPattern(x) & _bridgeObjectTaggedPointerBits != 0
}
@inlinable @inline(__always)
public func _isNativePointer(_ x: Builtin.BridgeObject) -> Bool {
  return _bitPattern(x) & (_bridgeObjectTaggedPointerBits | _objectPointerIsObjCBit) == 0
}
@inlinable @inline(__always)
public func _isNonTaggedObjCPointer(_ x: Builtin.BridgeObject) -> Bool {
  return !_isTaggedObject(x) && !_isNativePointer(x)
}

@inlinable @inline(__always)
internal func _makeBridgeObject(_ object: AnyObject, _ bits: UInt) -> Builtin.BridgeObject {
  return Builtin.castToBridgeObject(object, bits._builtinWordValue)
}
@inlinable @inline(__always)
internal func _makeNativeBridgeObject(_ nativeObject: AnyObject, _ bits: UInt) -> Builtin.BridgeObject {
  return _makeBridgeObject(nativeObject, bits)
}
@inlinable @inline(__always)
public func _makeObjCBridgeObject(_ objCObject: AnyObject) -> Builtin.BridgeObject {
  return _makeBridgeObject(objCObject, _isObjCTaggedPointer(objCObject) ? 0 : _objectPointerIsObjCBit)
}

@inlinable @inline(__always)
public func _bridgeObject(fromNative x: AnyObject) -> Builtin.BridgeObject {
  return Builtin.castToBridgeObject(x, 0._builtinWordValue)
}
@inlinable @inline(__always)
public func _bridgeObject(fromNonTaggedObjC x: AnyObject) -> Builtin.BridgeObject {
  return _makeObjCBridgeObject(x)
}
@inlinable @inline(__always)
public func _bridgeObject(fromTagged x: UInt) -> Builtin.BridgeObject {
  return Builtin.valueToBridgeObject(x._value)
}
@inlinable @inline(__always)
public func _bridgeObject(taggingPayload x: UInt) -> Builtin.BridgeObject {
  return _bridgeObject(fromTagged: (x &<< _objectPointerLowSpareBitShift) | _bridgeObjectTaggedPointerBits)
}
@inlinable @inline(__always)
public func _bridgeObject(toNative x: Builtin.BridgeObject) -> AnyObject {
  return Builtin.castReferenceFromBridgeObject(x)
}
@inlinable @inline(__always)
public func _bridgeObject(toNonTaggedObjC x: Builtin.BridgeObject) -> AnyObject {
  return Builtin.castReferenceFromBridgeObject(x)
}
@inlinable @inline(__always)
public func _bridgeObject(toTagged x: Builtin.BridgeObject) -> UInt {
  return _bitPattern(x)
}
@inlinable @inline(__always)
public func _bridgeObject(toTagPayload x: Builtin.BridgeObject) -> UInt {
  return (_bitPattern(x) & ~_bridgeObjectTaggedPointerBits) &>> _objectPointerLowSpareBitShift
}

// ---- uniqueness ----------------------------------------------------------------------

@usableFromInline @_transparent
internal func _isUnique<T>(_ object: inout T) -> Bool {
  return Bool(Builtin.isUnique(&object))
}
/// `object` must be a native Swift reference with no flag bits.
@_transparent
public func _isUnique_native<T>(_ object: inout T) -> Bool {
  return Bool(Builtin.isUnique_native(&object))
}

@_transparent
public func _canBeClass<T>(_: T.Type) -> Int8 {
  return Int8(Builtin.canBeClass(T.self))
}

@_transparent
public func _isPOD<T>(_ type: T.Type) -> Bool {
  return Bool(Builtin.ispod(type))
}

@_transparent
public func _isBitwiseTakable<T>(_ type: T.Type) -> Bool {
  return Bool(Builtin.isbitwisetakable(type))
}

// ---- swap ------------------------------------------------------------------------------

@inlinable
public func swap<T>(_ a: inout T, _ b: inout T) {
  // Distinct inout arguments never alias (exclusivity), so a plain
  // three-way move is enough.
  let pa = UnsafeMutablePointer<T>(Builtin.addressof(&a))
  let pb = UnsafeMutablePointer<T>(Builtin.addressof(&b))
  let saved = pa.move()
  pa.moveInitialize(from: pb, count: 1)
  pb.initialize(to: saved)
}

// ---- _BridgeStorage --------------------------------------------------------------------

@usableFromInline @frozen
internal struct _BridgeStorage<NativeClass: AnyObject> {
  @usableFromInline internal typealias Native = NativeClass
  @usableFromInline internal typealias ObjC = AnyObject

  @usableFromInline
  internal var rawValue: Builtin.BridgeObject

  @inlinable @inline(__always)
  internal init(native: Native, isFlagged flag: Bool) {
    rawValue = _makeNativeBridgeObject(native, flag ? _BridgeStorage.flagMask : 0)
  }
  @inlinable @inline(__always)
  internal init(objC: ObjC) {
    rawValue = _makeObjCBridgeObject(objC)
  }
  @inlinable @inline(__always)
  internal init(native: Native) {
    rawValue = Builtin.reinterpretCast(native)
  }
  @inlinable @inline(__always)
  internal init(taggedPayload: UInt) {
    rawValue = _bridgeObject(taggingPayload: taggedPayload)
  }

  @inlinable @inline(__always)
  internal mutating func isUniquelyReferencedNative() -> Bool {
    return isNative && _isUnique(&rawValue)
  }

  @inlinable
  internal var isNative: Bool {
    @inline(__always) get {
      let kind = Builtin.classifyBridgeObject(rawValue)
      return !Bool(Builtin.or_Int1(kind.isObjCObject, kind.isObjCTaggedPointer))
    }
  }

  @inlinable
  internal static var flagMask: UInt {
    @inline(__always) get { return 1 &<< _objectPointerLowSpareBitShift }
  }

  @inlinable
  internal var isUnflaggedNative: Bool {
    @inline(__always) get {
      let reserved = _bridgeObjectTaggedPointerBits | _objCTaggedPointerBits
        | _objectPointerIsObjCBit | _BridgeStorage.flagMask
      return _bitPattern(rawValue) & reserved == 0
    }
  }

  @inlinable internal var _bits: UInt {
    @inline(__always) get { return _bitPattern(rawValue) }
  }

  @inlinable
  internal var isObjC: Bool {
    @inline(__always) get { return !isNative }
  }

  @inlinable
  internal var nativeInstance: Native {
    @inline(__always) get { return Builtin.castReferenceFromBridgeObject(rawValue) }
  }

  @inlinable
  internal var unflaggedNativeInstance: Native {
    @inline(__always) get { return Builtin.reinterpretCast(rawValue) }
  }

  @inlinable @inline(__always)
  internal mutating func isUniquelyReferencedUnflaggedNative() -> Bool {
    return _isUnique_native(&rawValue)
  }

  @inlinable
  internal var objCInstance: ObjC {
    @inline(__always) get { return Builtin.castReferenceFromBridgeObject(rawValue) }
  }
}
