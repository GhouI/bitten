// The representation of String: _StringGuts wrapping _StringObject, and the
// native storage class.
//
// The layout is Apple's x86-64 one, because programs inline against it
// (literal construction, isEmpty, utf8.count, small-string checks, direct
// reads of the UTF-8 bytes). It was taken from the ABI as compiled code
// shows it, not from Apple's sources. A String is two words:
//
//   word 0 (_countAndFlagsBits)       word 1 (_object, a Builtin.BridgeObject)
//
// Small strings (up to 15 UTF-8 bytes) are stored inline: bytes 0-7 in word
// 0, bytes 8-14 in the low seven bytes of word 1, and the top byte of word 1
// is the discriminator: 1 (immortal), isASCII, 1 (small), 0, then the count
// in the low nibble. The empty string is (0, 0xE000_0000_0000_0000).
//
// Large strings keep the count and flags in word 0:
//   b63 isASCII, b62 isNFC, b61 isNativelyStored, b60 isTailAllocated,
//   b59-b48 reserved, b47-b0 the UTF-8 count;
// and in word 1 a discriminator nibble (b63 immortal, b62 bridged, b61
// small = 0, b60 foreign) above the address of an object whose UTF-8 bytes
// start 32 bytes in. Native strings point at a __StringStorage (nibble 0);
// literals are immortal (nibble 8) and point 32 bytes before their constant
// bytes, so the same "+32" finds the bytes of both. A literal of 25 ASCII
// bytes is (0xD000_0000_0000_0019, 0x8000_0000_0000_0000 | (address - 32)).
// Shared (b61 = b60 = 0 in word 0, not native) and foreign or bridged
// (Objective-C) strings are not created here; the accessors that would need
// them trap.

@frozen @usableFromInline
internal struct _StringObject {
  @usableFromInline internal var _countAndFlagsBits: UInt64
  @usableFromInline internal var _object: Builtin.BridgeObject

  @inlinable @inline(__always)
  internal init(_rawBits w0: UInt64, _ w1: UInt64) {
    _countAndFlagsBits = w0
    _object = Builtin.valueToBridgeObject(w1._value)
  }

  @inlinable @inline(__always)
  internal init(empty: ()) {
    self.init(_rawBits: 0, 0xE000_0000_0000_0000)
  }

  internal init(native storage: __StringStorage, countAndFlags: UInt64) {
    _countAndFlagsBits = countAndFlags
    _object = Builtin.castToBridgeObject(storage, (0 as UInt)._builtinWordValue)
  }
}

extension _StringObject {
  @usableFromInline internal typealias RawBitPattern = (UInt64, UInt64)

  @inlinable @inline(__always)
  internal var rawBits: RawBitPattern {
    return (_countAndFlagsBits, discriminatedObjectRawBits)
  }

  @inlinable @inline(__always)
  internal var discriminatedObjectRawBits: UInt64 {
    return UInt64(Builtin.zextOrBitCast_Word_Int64(Builtin.castBitPatternFromBridgeObject(_object)))
  }

  @inlinable @inline(__always)
  internal var isImmortal: Bool { return discriminatedObjectRawBits & 0x8000_0000_0000_0000 != 0 }
  @inlinable @inline(__always)
  internal var isSmall: Bool { return discriminatedObjectRawBits & 0x2000_0000_0000_0000 != 0 }
  @inlinable @inline(__always)
  internal var isForeign: Bool {
    return !isSmall && discriminatedObjectRawBits & 0x1000_0000_0000_0000 != 0
  }
  @inlinable @inline(__always)
  internal var isBridged: Bool {
    return !isSmall && discriminatedObjectRawBits & 0x4000_0000_0000_0000 != 0
  }
  /// Native and literal strings (and shared ones) have their UTF-8 bytes in
  /// memory; foreign ones do not.
  @inlinable @inline(__always)
  internal var providesFastUTF8: Bool { return discriminatedObjectRawBits & 0x1000_0000_0000_0000 == 0 }

  @inlinable @inline(__always)
  internal var smallCount: Int {
    return Int(truncatingIfNeeded: (discriminatedObjectRawBits &>> 56) & 0xF)
  }
  @inlinable @inline(__always)
  internal var largeCount: Int {
    return Int(truncatingIfNeeded: _countAndFlagsBits & 0x0000_FFFF_FFFF_FFFF)
  }
  @inlinable @inline(__always)
  internal var count: Int { return isSmall ? smallCount : largeCount }

  @inlinable @inline(__always)
  internal var isASCII: Bool {
    if isSmall { return discriminatedObjectRawBits & 0x4000_0000_0000_0000 != 0 }
    return _countAndFlagsBits & 0x8000_0000_0000_0000 != 0
  }
  @inlinable @inline(__always)
  internal var isNFC: Bool {
    if isSmall { return discriminatedObjectRawBits & 0x4000_0000_0000_0000 != 0 }
    return _countAndFlagsBits & 0x4000_0000_0000_0000 != 0
  }
  @inlinable @inline(__always)
  internal var hasNativeStorage: Bool {
    return !isSmall && _countAndFlagsBits & 0x2000_0000_0000_0000 != 0
  }
  @inlinable @inline(__always)
  internal var isTailAllocated: Bool {
    return _countAndFlagsBits & 0x1000_0000_0000_0000 != 0
  }
  @inlinable @inline(__always)
  internal var largeAddressBits: UInt64 { return discriminatedObjectRawBits & 0x0FFF_FFFF_FFFF_FFFF }

  /// The UTF-8 bytes of a large string that provides them.
  @inlinable @inline(__always)
  internal var largeFastUTF8Start: UnsafePointer<UInt8> {
    if _fastPath(isTailAllocated) {
      return UnsafePointer(Builtin.inttoptr_Word((largeAddressBits &+ 32)._builtinWordValue))
    }
    return sharedUTF8.baseAddress._unsafelyUnwrappedUnchecked
  }

  /// The bytes of a shared string: one whose storage points at UTF-8 owned
  /// by another object (Foundation's, for bridged strings). Not created here.
  @usableFromInline
  internal var sharedUTF8: UnsafeBufferPointer<UInt8> {
    _preconditionFailure("shared (bridged) String storage is not supported")
  }

  internal var nativeStorage: __StringStorage {
    return Builtin.castReferenceFromBridgeObject(_object)
  }
}

extension UInt64 {
  @inlinable @inline(__always)
  internal var _builtinWordValue: Builtin.Word { return Builtin.truncOrBitCast_Int64_Word(_value) }
}
extension Optional {
  @inlinable @inline(__always)
  internal var _unsafelyUnwrappedUnchecked: Wrapped {
    if let x = self { return x }
    Builtin.unreachable()
  }
}

// ---- native storage -------------------------------------------------------------
// A class instance with the header (metadata, reference counts), the real
// capacity and flags (capacity in the low 48 bits), the count and flags as in
// the String, then the UTF-8 bytes at offset 32 followed by a NUL, so that
// native strings, like literals, can be passed to C without a copy.

final internal class __StringStorage {
  internal var _realCapacityAndFlags: UInt64
  internal var _countAndFlags: UInt64

  private init(_doNotCall: ()) { Builtin.int_trap() }

  internal var capacity: Int { return Int(truncatingIfNeeded: _realCapacityAndFlags & 0x0000_FFFF_FFFF_FFFF) }
  internal var count: Int { return Int(truncatingIfNeeded: _countAndFlags & 0x0000_FFFF_FFFF_FFFF) }
  internal var start: UnsafeMutablePointer<UInt8> {
    return UnsafeMutablePointer(Builtin.projectTailElems(self, UInt8.self))
  }

  /// Storage for at least `capacity` bytes, with `count` of them to be
  /// written by the caller.
  internal static func create(capacity: Int, count: Int, isASCII: Bool) -> __StringStorage {
    // Room for the header, the bytes and the NUL, rounded to 16 bytes.
    let total = (32 + capacity + 1 + 15) & ~15
    let real = total - 33
    let s: __StringStorage = Builtin.allocWithTailElems_1(
      __StringStorage.self, (real + 1)._builtinWordValue, UInt8.self)
    s._realCapacityAndFlags = UInt64(truncatingIfNeeded: real)
    s._countAndFlags = 0
    s.setCount(count, isASCII: isASCII)
    return s
  }

  internal func setCount(_ n: Int, isASCII: Bool) {
    _countAndFlags = _StringGuts._nativeCountAndFlags(n, isASCII: isASCII)
    start[n] = 0
  }
}

// ---- _StringGuts ------------------------------------------------------------------

@frozen
public struct _StringGuts {
  @usableFromInline internal var _object: _StringObject

  @inlinable @inline(__always)
  internal init(_ object: _StringObject) { _object = object }

  @inlinable @inline(__always)
  internal init() { self.init(_StringObject(empty: ())) }
}

extension _StringGuts {
  @inlinable @inline(__always)
  internal var rawBits: _StringObject.RawBitPattern { return _object.rawBits }
  @inlinable @inline(__always)
  internal var count: Int { return _object.count }
  @inlinable @inline(__always)
  internal var isEmpty: Bool { return count == 0 }
  @inlinable @inline(__always)
  internal var isSmall: Bool { return _object.isSmall }
  @inlinable @inline(__always)
  internal var isASCII: Bool { return _object.isASCII }
  @inlinable @inline(__always)
  internal var isNFC: Bool { return _object.isNFC }
  @inlinable @inline(__always)
  internal var isFastUTF8: Bool { return _fastPath(_object.providesFastUTF8) }
  @inlinable @inline(__always)
  internal var isForeign: Bool { return _slowPath(_object.isForeign) }
  @inlinable @inline(__always)
  internal var hasNativeStorage: Bool { return _object.hasNativeStorage }

  internal static func _nativeCountAndFlags(_ n: Int, isASCII: Bool) -> UInt64 {
    let flags: UInt64 = isASCII ? 0xF000_0000_0000_0000 : 0x3000_0000_0000_0000
    return flags | UInt64(truncatingIfNeeded: n)
  }

  /// A small string from up to 15 bytes.
  @inlinable
  internal init(_small p: UnsafePointer<UInt8>, count n: Int, isASCII: Bool) {
    var w0: UInt64 = 0, w1: UInt64 = 0
    var i = 0
    while i < n {
      let b = UInt64(truncatingIfNeeded: p[i])
      if i < 8 { w0 |= b &<< UInt64(truncatingIfNeeded: i &* 8) }
      else { w1 |= b &<< UInt64(truncatingIfNeeded: (i &- 8) &* 8) }
      i &+= 1
    }
    let disc: UInt64 = (isASCII ? 0xE0 : 0xA0) | UInt64(truncatingIfNeeded: n)
    self.init(_StringObject(_rawBits: w0, w1 | (disc &<< 56)))
  }

  /// An immortal string over constant UTF-8 that outlives the program.
  @inlinable
  internal init(_immortal p: UnsafePointer<UInt8>, count n: Int, isASCII: Bool) {
    let flags: UInt64 = isASCII ? 0xD000_0000_0000_0000 : 0x1000_0000_0000_0000
    let address = UInt64(truncatingIfNeeded: Int(Builtin.ptrtoint_Word(p._rawValue)))
    self.init(_StringObject(_rawBits: flags | UInt64(truncatingIfNeeded: n),
                            0x8000_0000_0000_0000 | (address &- 32)))
  }

  /// A string holding a copy of the bytes: small when they fit, native
  /// otherwise. The bytes must be valid UTF-8.
  @usableFromInline
  internal init(_copying p: UnsafePointer<UInt8>, count n: Int, isASCII: Bool) {
    if n <= 15 {
      self.init(_small: p, count: n, isASCII: isASCII)
      return
    }
    let s = __StringStorage.create(capacity: n, count: n, isASCII: isASCII)
    s.start.update(from: p, count: n)
    self.init(_StringObject(native: s, countAndFlags: s._countAndFlags))
  }

  internal init(_storage s: __StringStorage) {
    self.init(_StringObject(native: s, countAndFlags: s._countAndFlags))
  }

  /// An empty string with room for `capacity` bytes.
  @usableFromInline
  internal init(_initialCapacity capacity: Int) {
    if capacity <= 15 { self.init(); return }
    self.init(_storage: __StringStorage.create(capacity: capacity, count: 0, isASCII: true))
  }

  // ---- reading the bytes ----

  /// Calls `body` with the UTF-8 bytes. Small strings are copied to the
  /// stack first.
  @inlinable @inline(__always)
  internal func withFastUTF8<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
    if _object.isSmall {
      var raw = (_object._countAndFlagsBits, _object.discriminatedObjectRawBits & 0x00FF_FFFF_FFFF_FFFF)
      let n = _object.smallCount
      return try withUnsafeMutablePointer(to: &raw) { p in
        try body(UnsafeBufferPointer(start: UnsafeRawPointer(p).assumingMemoryBound(to: UInt8.self), count: n))
      }
    }
    if _slowPath(_object.isForeign) { _foreignUTF8Unavailable() }
    return try body(UnsafeBufferPointer(start: _object.largeFastUTF8Start, count: _object.largeCount))
  }

  @inlinable
  internal func withFastUTF8<R>(range: Range<Int>, _ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
    return try withFastUTF8 { all in
      try body(UnsafeBufferPointer(start: all.baseAddress._unsafelyUnwrappedUnchecked + range.lowerBound,
                                   count: range.upperBound &- range.lowerBound))
    }
  }

  /// Byte `i` (no bounds check).
  @inlinable
  internal func utf8Byte(at i: Int) -> UInt8 {
    if _object.isSmall {
      let w = i < 8 ? _object._countAndFlagsBits : _object.discriminatedObjectRawBits
      return UInt8(truncatingIfNeeded: w &>> UInt64(truncatingIfNeeded: (i & 7) &* 8))
    }
    if _slowPath(_object.isForeign) { _foreignUTF8Unavailable() }
    return _object.largeFastUTF8Start[i]
  }

  @usableFromInline @inline(never)
  internal func _foreignUTF8Unavailable() -> Never {
    _preconditionFailure("foreign (bridged) String storage is not supported")
  }

  // ---- mutation ----

  @inlinable
  internal mutating func isUniqueNative() -> Bool {
    guard _object.hasNativeStorage else { return false }
    return Bool(Builtin.isUnique_native(&_object._object))
  }

  /// Bytes the string can hold without reallocating, when it is a uniquely
  /// referenced native string; nil otherwise.
  internal mutating func uniqueNativeCapacity() -> Int? {
    if isUniqueNative() { return _object.nativeStorage.capacity }
    return nil
  }

  /// Makes the string native, uniquely referenced and able to hold at
  /// least `n` bytes.
  @usableFromInline
  internal mutating func grow(_ n: Int) {
    let old = count
    let cap = n > old * 2 ? n : old * 2
    let ascii = isASCII
    let s = __StringStorage.create(capacity: cap, count: old, isASCII: ascii)
    withFastUTF8 { s.start.update(from: $0.baseAddress._unsafelyUnwrappedUnchecked, count: old) }
    self = _StringGuts(_storage: s)
  }

  @usableFromInline
  internal mutating func reserveCapacity(_ n: Int) {
    if n <= 15 && isSmall { return }
    if let cap = uniqueNativeCapacity(), cap >= n { return }
    grow(n)
  }

  /// Appends valid UTF-8 bytes.
  @usableFromInline
  internal mutating func append(utf8 bytes: UnsafeBufferPointer<UInt8>, isASCII: Bool) {
    let n = bytes.count
    if n == 0 { return }
    let old = count
    let total = old + n
    let ascii = self.isASCII && isASCII
    if total <= 15 && (isSmall || old == 0) {
      // Stays small: assemble on the stack.
      var raw: (UInt64, UInt64) = (0, 0)
      withUnsafeMutablePointer(to: &raw) { rp in
        let p = UnsafeMutableRawPointer(rp).assumingMemoryBound(to: UInt8.self)
        withFastUTF8 { p.update(from: $0.baseAddress._unsafelyUnwrappedUnchecked, count: old) }
        (p + old).update(from: bytes.baseAddress._unsafelyUnwrappedUnchecked, count: n)
        self = _StringGuts(_small: UnsafePointer(p), count: total, isASCII: ascii)
      }
      return
    }
    if uniqueNativeCapacity().map({ $0 < total }) ?? true {
      grow(total)
    }
    let s = _object.nativeStorage
    (s.start + old).update(from: bytes.baseAddress._unsafelyUnwrappedUnchecked, count: n)
    s.setCount(total, isASCII: ascii)
    _object._countAndFlagsBits = s._countAndFlags
  }

  internal mutating func append(_ other: _StringGuts) {
    if other.isEmpty { return }
    if isEmpty && !other.isSmall && !hasNativeStorage {
      self = other
      return
    }
    let ascii = other.isASCII
    other.withFastUTF8 { append(utf8: $0, isASCII: ascii) }
  }

  /// Replaces the bytes in `range` with valid UTF-8.
  internal mutating func replace(utf8Range range: Range<Int>, with bytes: UnsafeBufferPointer<UInt8>, isASCII: Bool) {
    let old = count
    let total = old - range.count + bytes.count
    let ascii = isASCII && (self.isASCII || _isAllASCII(range: 0..<range.lowerBound) && _isAllASCII(range: range.upperBound..<old))
    let s = __StringStorage.create(capacity: total, count: total, isASCII: ascii)
    withFastUTF8 { src in
      let b = src.baseAddress._unsafelyUnwrappedUnchecked
      s.start.update(from: b, count: range.lowerBound)
      if bytes.count > 0 {
        (s.start + range.lowerBound).update(from: bytes.baseAddress._unsafelyUnwrappedUnchecked, count: bytes.count)
      }
      (s.start + range.lowerBound + bytes.count).update(from: b + range.upperBound, count: old - range.upperBound)
    }
    if total <= 15 {
      self = _StringGuts(_small: UnsafePointer(s.start), count: total, isASCII: ascii)
    } else {
      self = _StringGuts(_storage: s)
    }
  }

  internal func _isAllASCII(range: Range<Int>) -> Bool {
    if isASCII { return true }
    return withFastUTF8(range: range) { _allASCII($0) }
  }
}

@usableFromInline
internal func _allASCII(_ b: UnsafeBufferPointer<UInt8>) -> Bool {
  var i = 0
  let n = b.count
  let p = b.baseAddress
  while i < n {
    if p._unsafelyUnwrappedUnchecked[i] >= 0x80 { return false }
    i &+= 1
  }
  return true
}

@_silgen_name("memcmp")
internal func _bitten_memcmp(_ a: Builtin.RawPointer, _ b: Builtin.RawPointer, _ n: Int) -> Int32
@_silgen_name("strlen")
internal func _bitten_strlen(_ s: Builtin.RawPointer) -> Int
