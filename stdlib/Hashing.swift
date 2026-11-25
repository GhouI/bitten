// Hashable and Hasher.
//
// Hasher is SipHash-1-3 keyed with a per-process random seed (all zeros when
// the environment variable SWIFT_DETERMINISTIC_HASHING is set to a true
// value, as on macOS). Its layout is @frozen in the ABI, because programs
// keep Hashers on their own stacks: a tail buffer word followed by eight
// state words, of which SipHash uses four (72 bytes in all).

public protocol Hashable: Equatable {
  var hashValue: Int { get }
  func hash(into hasher: inout Hasher)
  func _rawHashValue(seed: Int) -> Int
}

extension Hashable {
  @inlinable @inline(__always)
  public func _rawHashValue(seed: Int) -> Int {
    var hasher = Hasher(_seed: seed)
    hasher.combine(self)
    return hasher._finalize()
  }
}

// Called by the hashValue the compiler synthesizes.
@inlinable @inline(__always)
public func _hashValue<H: Hashable>(for value: H) -> Int {
  return value._rawHashValue(seed: 0)
}

// ---- layout ----------------------------------------------------------------------

extension Hasher {
  /// Bytes not yet compressed, in the low seven bytes, and the total number
  /// of bytes combined so far (modulo 256) in the top byte: exactly the
  /// final SipHash block once the hash is finalized.
  @usableFromInline @frozen
  internal struct _TailBuffer {
    internal var value: UInt64
  }

  @usableFromInline @frozen
  internal struct _State {
    private var v0: UInt64 = 0x736f6d6570736575
    private var v1: UInt64 = 0x646f72616e646f6d
    private var v2: UInt64 = 0x6c7967656e657261
    private var v3: UInt64 = 0x7465646279746573
    // Reserved; part of the layout.
    private var v4: UInt64 = 0
    private var v5: UInt64 = 0
    private var v6: UInt64 = 0
    private var v7: UInt64 = 0

    internal init(rawSeed: (UInt64, UInt64)) {
      v0 ^= rawSeed.0
      v1 ^= rawSeed.1
      v2 ^= rawSeed.0
      v3 ^= rawSeed.1
    }

    @inline(__always)
    private static func rotl(_ x: UInt64, _ n: UInt64) -> UInt64 {
      return (x &<< n) | (x &>> (64 &- n))
    }

    @inline(__always)
    private mutating func round() {
      v0 = v0 &+ v1; v1 = _State.rotl(v1, 13); v1 ^= v0; v0 = _State.rotl(v0, 32)
      v2 = v2 &+ v3; v3 = _State.rotl(v3, 16); v3 ^= v2
      v0 = v0 &+ v3; v3 = _State.rotl(v3, 21); v3 ^= v0
      v2 = v2 &+ v1; v1 = _State.rotl(v1, 17); v1 ^= v2; v2 = _State.rotl(v2, 32)
    }

    internal mutating func compress(_ m: UInt64) {
      v3 ^= m
      round()          // one compression round
      v0 ^= m
    }

    internal mutating func finalize(tailAndByteCount: UInt64) -> UInt64 {
      compress(tailAndByteCount)
      v2 ^= 0xff
      round(); round(); round()   // three finalization rounds
      return v0 ^ v1 ^ v2 ^ v3
    }
  }

  @usableFromInline @frozen
  internal struct _Core {
    private var _buffer: _TailBuffer
    private var _state: _State

    internal init(seed: (UInt64, UInt64)) {
      _buffer = _TailBuffer(value: 0)
      _state = _State(rawSeed: seed)
    }

    /// Appends the low `count` bytes of `bytes` (1...8; the bytes above
    /// them are zero).
    internal mutating func combine(bytes: UInt64, count: Int) {
      let total = _buffer.value &>> 56
      let pendingBits = (total & 7) &<< 3
      let pending = _buffer.value & 0x00ff_ffff_ffff_ffff
      let newTotal = (total &+ UInt64(truncatingIfNeeded: count)) & 0xff
      let filled = pendingBits &+ (UInt64(truncatingIfNeeded: count) &<< 3)
      if filled < 64 {
        _buffer.value = pending | (bytes &<< pendingBits) | (newTotal &<< 56)
        return
      }
      // A full block: the pending bytes, then as many of the new ones as fit.
      _state.compress(pending | (bytes &<< pendingBits))
      let rest = pendingBits == 0 ? 0 : bytes &>> (64 &- pendingBits)
      _buffer.value = rest | (newTotal &<< 56)
    }

    internal mutating func finalize() -> UInt64 {
      return _state.finalize(tailAndByteCount: _buffer.value)
    }
  }
}

// ---- the per-process seed -----------------------------------------------------

@_silgen_name("getenv")
internal func _bitten_getenv(_ name: Builtin.RawPointer) -> UInt
@_silgen_name("arc4random")
internal func _bitten_arc4random() -> UInt32

internal struct _HashingParameters {
  internal var seed0: UInt64
  internal var seed1: UInt64
  internal var deterministic: Bool
}

internal func _environmentFlag(_ name: StaticString) -> Bool {
  let p = _bitten_getenv(name.unsafeRawPointer)
  if p == 0 { return false }
  let first: UInt8 = Builtin.load(Builtin.inttoptr_Word(p._builtinWordValue))
  // "1", "true", "yes" (any case) turn it on.
  return first == 0x31 || first == 0x74 || first == 0x54 || first == 0x79 || first == 0x59
}

internal func _makeHashingParameters() -> _HashingParameters {
  if _environmentFlag("SWIFT_DETERMINISTIC_HASHING") {
    return _HashingParameters(seed0: 0, seed1: 0, deterministic: true)
  }
  let a = UInt64(_bitten_arc4random()) &<< 32 | UInt64(_bitten_arc4random())
  let b = UInt64(_bitten_arc4random()) &<< 32 | UInt64(_bitten_arc4random())
  return _HashingParameters(seed0: a, seed1: b, deterministic: false)
}

internal let _hashingParameters: _HashingParameters = _makeHashingParameters()

// ---- Hasher -----------------------------------------------------------------------

@frozen public struct Hasher {
  internal var _core: _Core

  @_effects(releasenone)
  public init() {
    _core = _Core(seed: Hasher._executionSeed)
  }

  @usableFromInline @_effects(releasenone)
  internal init(_seed: Int) {
    let s = Hasher._executionSeed
    _core = _Core(seed: (s.0 ^ UInt64(truncatingIfNeeded: _seed), s.1))
  }

  @usableFromInline @_effects(releasenone)
  internal init(_rawSeed: (UInt64, UInt64)) {
    _core = _Core(seed: _rawSeed)
  }

  internal static var _isDeterministic: Bool {
    return _hashingParameters.deterministic
  }
  internal static var _executionSeed: (UInt64, UInt64) {
    let p = _hashingParameters
    return (p.seed0, p.seed1)
  }

  @inlinable @inline(__always)
  public mutating func combine<H: Hashable>(_ value: H) {
    value.hash(into: &self)
  }

  @usableFromInline @_effects(releasenone)
  internal mutating func _combine(_ value: UInt) {
    _core.combine(bytes: UInt64(truncatingIfNeeded: value), count: 8)
  }
  @usableFromInline @_effects(releasenone)
  internal mutating func _combine(_ value: UInt64) {
    _core.combine(bytes: value, count: 8)
  }
  @usableFromInline @_effects(releasenone)
  internal mutating func _combine(_ value: UInt32) {
    _core.combine(bytes: UInt64(truncatingIfNeeded: value), count: 4)
  }
  @usableFromInline @_effects(releasenone)
  internal mutating func _combine(_ value: UInt16) {
    _core.combine(bytes: UInt64(truncatingIfNeeded: value), count: 2)
  }
  @usableFromInline @_effects(releasenone)
  internal mutating func _combine(_ value: UInt8) {
    _core.combine(bytes: UInt64(truncatingIfNeeded: value), count: 1)
  }
  @usableFromInline @_effects(releasenone)
  internal mutating func _combine(bytes value: UInt64, count: Int) {
    _precondition(count >= 0 && count <= 8)
    if count == 0 { return }
    _core.combine(bytes: count == 8 ? value : value & ((1 &<< UInt64(truncatingIfNeeded: count &* 8)) &- 1),
                  count: count)
  }

  @usableFromInline @_effects(releasenone)
  internal mutating func _finalize() -> Int {
    return Int(truncatingIfNeeded: _core.finalize())
  }

  @_effects(releasenone)
  public __consuming func finalize() -> Int {
    var core = _core
    return Int(truncatingIfNeeded: core.finalize())
  }

  @usableFromInline @_effects(readnone)
  internal static func _hash(seed: Int, _ value: UInt64) -> Int {
    var h = Hasher(_seed: seed)
    h._core.combine(bytes: value, count: 8)
    return h._finalize()
  }
  @usableFromInline @_effects(readnone)
  internal static func _hash(seed: Int, _ value: UInt) -> Int {
    return _hash(seed: seed, UInt64(truncatingIfNeeded: value))
  }
  @usableFromInline @_effects(readnone)
  internal static func _hash(seed: Int, bytes value: UInt64, count: Int) -> Int {
    var h = Hasher(_seed: seed)
    h._combine(bytes: value, count: count)
    return h._finalize()
  }
}

// ---- conformances of the basic types ---------------------------------------------------

extension Bool: Hashable {
  @inlinable public func hash(into hasher: inout Hasher) {
    hasher.combine((self ? 1 : 0) as UInt8)
  }
  public var hashValue: Int { return _hashValue(for: self) }
}

extension Optional: Hashable where Wrapped: Hashable {
  @inlinable public func hash(into hasher: inout Hasher) {
    switch self {
    case .none:
      hasher.combine(0 as UInt8)
    case .some(let wrapped):
      hasher.combine(1 as UInt8)
      hasher.combine(wrapped)
    }
  }
  public var hashValue: Int { return _hashValue(for: self) }
}

extension Never: Equatable, Comparable, Hashable {
  // No values exist, so none of these can be called.
  public static func < (a: Never, b: Never) -> Bool { switch a {} }
  public static func == (a: Never, b: Never) -> Bool { switch a {} }
  public func hash(into hasher: inout Hasher) { switch self {} }
  public var hashValue: Int { switch self {} }
}

extension Unicode.Scalar: Hashable {
  @inlinable public func hash(into hasher: inout Hasher) {
    hasher.combine(self.value)
  }
  public var hashValue: Int { return _hashValue(for: self) }
}

// ---- ObjectIdentifier ------------------------------------------------------------------

@frozen public struct ObjectIdentifier: Sendable {
  @usableFromInline internal let _value: Builtin.RawPointer

  @inlinable public init(_ x: AnyObject) {
    _value = Builtin.bridgeToRawPointer(x)
  }
  @inlinable public init(_ x: Any.Type) {
    _value = Builtin.reinterpretCast(x)
  }
}
extension ObjectIdentifier: Equatable {
  @inlinable public static func == (x: ObjectIdentifier, y: ObjectIdentifier) -> Bool {
    return Bool(Builtin.cmp_eq_RawPointer(x._value, y._value))
  }
}
extension ObjectIdentifier: Comparable {
  @inlinable public static func < (lhs: ObjectIdentifier, rhs: ObjectIdentifier) -> Bool {
    return UInt(bitPattern: lhs) < UInt(bitPattern: rhs)
  }
}
extension ObjectIdentifier: Hashable {
  @inlinable public func hash(into hasher: inout Hasher) {
    hasher.combine(Int(Builtin.ptrtoint_Word(_value)))
  }
  @_alwaysEmitIntoClient public func _rawHashValue(seed: Int) -> Int {
    return Int(Builtin.ptrtoint_Word(_value))._rawHashValue(seed: seed)
  }
  public var hashValue: Int { return _hashValue(for: self) }
}
extension UInt {
  @inlinable public init(bitPattern objectID: ObjectIdentifier) {
    self.init(Builtin.ptrtoint_Word(objectID._value))
  }
}
extension Int {
  @inlinable public init(bitPattern objectID: ObjectIdentifier) {
    self.init(Builtin.ptrtoint_Word(objectID._value))
  }
}

@inlinable public func === (lhs: AnyObject?, rhs: AnyObject?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return ObjectIdentifier(l) == ObjectIdentifier(r)
  case (nil, nil):
    return true
  default:
    return false
  }
}
@inlinable public func !== (lhs: AnyObject?, rhs: AnyObject?) -> Bool {
  return !(lhs === rhs)
}

// ---- diagnostics for Dictionary and Set ---------------------------------------------------

internal func _reportHashableViolation(_ type: Any.Type, _ what: StaticString) -> Never {
  let (name, length) = _bitten_getTypeName(Builtin.reinterpretCast(type) as Builtin.RawPointer, true)
  var b = _ReportBuffer(capacity: 1024)
  b.append("Fatal error: Duplicate ")
  b.append(what)
  b.append(" of type '")
  b.append(bytes: name, count: length)
  b.append("' were found. The type's == and hash(into:) disagree, or a member was mutated after insertion.\n")
  b.writeToStderr()
  Builtin.int_trap()
}

@usableFromInline @inline(never)
internal func KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTS(_ keyType: Any.Type) -> Never {
  _reportHashableViolation(keyType, "keys in a Dictionary")
}
@usableFromInline @inline(never)
internal func ELEMENT_TYPE_OF_SET_VIOLATES_HASHABLE_REQUIREMENTS(_ elementType: Any.Type) -> Never {
  _reportHashableViolation(elementType, "elements in a Set")
}
