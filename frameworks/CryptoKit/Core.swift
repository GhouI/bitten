// CryptoKit, written for bitten: hashing, symmetric keys, AES-GCM, and the
// public-key types in NIST.swift and Curve25519.swift. The arithmetic lives
// in mrun (src/frameworks/cryptokit/ec.c, and CommonCrypto's SHA and AES);
// these types give it the API and the symbol names Mac apps link against.
import Foundation

// ---- the C core ---------------------------------------------------------

@_silgen_name("bitten_ck_hash_init")
func _ck_hash_init(_ alg: Int32, _ ctx: UnsafeMutableRawPointer) -> Int32
@_silgen_name("bitten_ck_hash_update")
func _ck_hash_update(_ alg: Int32, _ ctx: UnsafeMutableRawPointer, _ data: UnsafeRawPointer?, _ len: Int) -> Int32
@_silgen_name("bitten_ck_hash_final")
func _ck_hash_final(_ alg: Int32, _ ctx: UnsafeMutableRawPointer, _ out: UnsafeMutableRawPointer) -> Int32
@_silgen_name("bitten_ck_gcm")
func _ck_gcm(_ op: Int32, _ argv: UnsafePointer<Int>) -> Int32
@_silgen_name("bitten_ck_random")
func _ck_random(_ p: UnsafeMutableRawPointer, _ n: Int) -> Int32

func _bytes<D: DataProtocol>(of data: D) -> [UInt8] {
  var out = [UInt8]()
  out.reserveCapacity(data.count)
  for b in data { out.append(b) }
  return out
}

func _bytes<B: ContiguousBytes>(contiguous b: B) -> [UInt8] {
  return b.withUnsafeBytes { Array($0) }
}

func _randomBytes(_ n: Int) -> [UInt8] {
  var out = [UInt8](repeating: 0, count: n)
  out.withUnsafeMutableBytes { _ = _ck_random($0.baseAddress!, n) }
  return out
}

let _hexDigits: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]

func _hex(_ bytes: [UInt8]) -> String {
  var s = ""
  for b in bytes {
    s.append(_hexDigits[Int(b >> 4)])
    s.append(_hexDigits[Int(b & 15)])
  }
  return s
}

// ---- errors -------------------------------------------------------------

public enum CryptoKitError: Error {
  case underlyingCoreCryptoError(error: Int32)
  case unwrapFailure
  case incorrectKeySize
  case incorrectParameterSize
  case authenticationFailure
  case wrapFailure
  case invalidParameter
}

// ---- digests and hash functions -----------------------------------------

public protocol Digest: Hashable, ContiguousBytes, CustomStringConvertible, Sequence where Element == UInt8 {
  static var byteCount: Int { get }
}

public protocol HashFunction {
  static var blockByteCount: Int { get }
  associatedtype Digest: CryptoKit.Digest
  init()
  mutating func update(bufferPointer: UnsafeRawBufferPointer)
  func finalize() -> Self.Digest
}

extension HashFunction {
  public mutating func update<D: DataProtocol>(data: D) {
    let bytes = _bytes(of: data)
    bytes.withUnsafeBytes { update(bufferPointer: $0) }
  }

  public static func hash<D: DataProtocol>(data: D) -> Self.Digest {
    var h = Self()
    h.update(data: data)
    return h.finalize()
  }
}

/// The context of a CommonCrypto digest, kept as bytes so that copying a
/// hash function copies its state.
struct _HashState {
  let alg: Int32
  var ctx: [UInt8]

  init(alg: Int32) {
    self.alg = alg
    ctx = [UInt8](repeating: 0, count: 256)
    ctx.withUnsafeMutableBytes { _ = _ck_hash_init(alg, $0.baseAddress!) }
  }

  mutating func update(_ buf: UnsafeRawBufferPointer) {
    let alg = self.alg
    ctx.withUnsafeMutableBytes { _ = _ck_hash_update(alg, $0.baseAddress!, buf.baseAddress, buf.count) }
  }

  func finalize(_ n: Int) -> [UInt8] {
    var copy = ctx
    var out = [UInt8](repeating: 0, count: n)
    let alg = self.alg
    copy.withUnsafeMutableBytes { c in
      out.withUnsafeMutableBytes { o in _ = _ck_hash_final(alg, c.baseAddress!, o.baseAddress!) }
    }
    return out
  }
}

public struct SHA256Digest: Digest {
  let bytes: [UInt8]
  public static var byteCount: Int { return 32 }
  public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    return try bytes.withUnsafeBytes(body)
  }
  public func makeIterator() -> Array<UInt8>.Iterator { return bytes.makeIterator() }
  public var description: String { return "SHA256 digest: " + _hex(bytes) }
}

public struct SHA384Digest: Digest {
  let bytes: [UInt8]
  public static var byteCount: Int { return 48 }
  public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    return try bytes.withUnsafeBytes(body)
  }
  public func makeIterator() -> Array<UInt8>.Iterator { return bytes.makeIterator() }
  public var description: String { return "SHA384 digest: " + _hex(bytes) }
}

public struct SHA512Digest: Digest {
  let bytes: [UInt8]
  public static var byteCount: Int { return 64 }
  public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    return try bytes.withUnsafeBytes(body)
  }
  public func makeIterator() -> Array<UInt8>.Iterator { return bytes.makeIterator() }
  public var description: String { return "SHA512 digest: " + _hex(bytes) }
}

public struct SHA256: HashFunction {
  var state = _HashState(alg: 0)
  public static var blockByteCount: Int { return 64 }
  public static var byteCount: Int { return 32 }
  public typealias Digest = SHA256Digest
  public init() {}
  public mutating func update(bufferPointer: UnsafeRawBufferPointer) { state.update(bufferPointer) }
  public func finalize() -> SHA256Digest { return SHA256Digest(bytes: state.finalize(32)) }
}

public struct SHA384: HashFunction {
  var state = _HashState(alg: 1)
  public static var blockByteCount: Int { return 128 }
  public static var byteCount: Int { return 48 }
  public typealias Digest = SHA384Digest
  public init() {}
  public mutating func update(bufferPointer: UnsafeRawBufferPointer) { state.update(bufferPointer) }
  public func finalize() -> SHA384Digest { return SHA384Digest(bytes: state.finalize(48)) }
}

public struct SHA512: HashFunction {
  var state = _HashState(alg: 2)
  public static var blockByteCount: Int { return 128 }
  public static var byteCount: Int { return 64 }
  public typealias Digest = SHA512Digest
  public init() {}
  public mutating func update(bufferPointer: UnsafeRawBufferPointer) { state.update(bufferPointer) }
  public func finalize() -> SHA512Digest { return SHA512Digest(bytes: state.finalize(64)) }
}

public enum Insecure {
  public struct SHA1Digest: Digest {
    let bytes: [UInt8]
    public static var byteCount: Int { return 20 }
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
      return try bytes.withUnsafeBytes(body)
    }
    public func makeIterator() -> Array<UInt8>.Iterator { return bytes.makeIterator() }
    public var description: String { return "SHA1 digest: " + _hex(bytes) }
  }

  public struct MD5Digest: Digest {
    let bytes: [UInt8]
    public static var byteCount: Int { return 16 }
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
      return try bytes.withUnsafeBytes(body)
    }
    public func makeIterator() -> Array<UInt8>.Iterator { return bytes.makeIterator() }
    public var description: String { return "MD5 digest: " + _hex(bytes) }
  }

  public struct SHA1: HashFunction {
    var state = _HashState(alg: 3)
    public static var blockByteCount: Int { return 64 }
    public static var byteCount: Int { return 20 }
    public typealias Digest = SHA1Digest
    public init() {}
    public mutating func update(bufferPointer: UnsafeRawBufferPointer) { state.update(bufferPointer) }
    public func finalize() -> SHA1Digest { return SHA1Digest(bytes: state.finalize(20)) }
  }

  public struct MD5: HashFunction {
    var state = _HashState(alg: 4)
    public static var blockByteCount: Int { return 64 }
    public static var byteCount: Int { return 16 }
    public typealias Digest = MD5Digest
    public init() {}
    public mutating func update(bufferPointer: UnsafeRawBufferPointer) { state.update(bufferPointer) }
    public func finalize() -> MD5Digest { return MD5Digest(bytes: state.finalize(16)) }
  }
}

// ---- keys and secrets ---------------------------------------------------

public struct SymmetricKeySize {
  public let bitCount: Int
  public init(bitCount: Int) { self.bitCount = bitCount }
  public static var bits128: SymmetricKeySize { return SymmetricKeySize(bitCount: 128) }
  public static var bits192: SymmetricKeySize { return SymmetricKeySize(bitCount: 192) }
  public static var bits256: SymmetricKeySize { return SymmetricKeySize(bitCount: 256) }
}

public struct SymmetricKey: ContiguousBytes {
  let bytes: [UInt8]

  public init<D: ContiguousBytes>(data: D) { bytes = _bytes(contiguous: data) }
  public init(size: SymmetricKeySize) { bytes = _randomBytes(size.bitCount / 8) }
  public var bitCount: Int { return bytes.count * 8 }

  public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    return try bytes.withUnsafeBytes(body)
  }
}

extension SymmetricKey: Equatable {
  public static func == (lhs: SymmetricKey, rhs: SymmetricKey) -> Bool {
    if lhs.bytes.count != rhs.bytes.count { return false }
    var diff: UInt8 = 0
    for i in 0..<lhs.bytes.count { diff |= lhs.bytes[i] ^ rhs.bytes[i] }
    return diff == 0
  }
}

public struct SharedSecret: ContiguousBytes {
  let bytes: [UInt8]

  public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    return try bytes.withUnsafeBytes(body)
  }
}

// ---- AES-GCM --------------------------------------------------------------

public enum AES {
  public enum GCM {
    public struct Nonce: ContiguousBytes, Sequence {
      let bytes: [UInt8]

      public init() { bytes = _randomBytes(12) }

      init(bytes: [UInt8]) { self.bytes = bytes }

      public init<D: DataProtocol>(data: D) throws {
        let b = _bytes(of: data)
        if b.count < 12 { throw CryptoKitError.incorrectParameterSize }
        bytes = b
      }

      public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        return try bytes.withUnsafeBytes(body)
      }

      public func makeIterator() -> Array<UInt8>.Iterator { return bytes.makeIterator() }
    }

    public struct SealedBox {
      public let nonce: AES.GCM.Nonce
      public let ciphertext: Data
      public let tag: Data

      /// nonce || ciphertext || tag, when the nonce is the standard 12 bytes.
      public var combined: Data? {
        if nonce.bytes.count != 12 { return nil }
        var d = Data(nonce.bytes)
        d.append(ciphertext)
        d.append(tag)
        return d
      }

      /// Not throwing, as in Apple's declaration: input too short to hold a
      /// nonce and a tag gives a box that fails authentication when opened.
      public init(combined: Data) {
        let b = _bytes(of: combined)
        if b.count < 28 {
          nonce = AES.GCM.Nonce(bytes: [UInt8](repeating: 0, count: 12))
          ciphertext = Data()
          tag = Data()
          return
        }
        nonce = AES.GCM.Nonce(bytes: Array(b[0..<12]))
        ciphertext = Data(b[12..<(b.count - 16)])
        tag = Data(b[(b.count - 16)...])
      }

      public init<C: DataProtocol, T: DataProtocol>(nonce: AES.GCM.Nonce, ciphertext: C, tag: T) throws {
        let t = _bytes(of: tag)
        if t.count != 16 { throw CryptoKitError.incorrectParameterSize }
        self.nonce = nonce
        self.ciphertext = Data(_bytes(of: ciphertext))
        self.tag = Data(t)
      }

      init(nonce: AES.GCM.Nonce, ciphertextBytes: [UInt8], tagBytes: [UInt8]) {
        self.nonce = nonce
        ciphertext = Data(ciphertextBytes)
        tag = Data(tagBytes)
      }
    }

    static func _run(_ op: Int32, key: SymmetricKey, nonce: [UInt8], aad: [UInt8], input: [UInt8],
                     tag: inout [UInt8]) throws -> [UInt8] {
      let kc = key.bytes.count
      if kc != 16 && kc != 24 && kc != 32 { throw CryptoKitError.incorrectKeySize }
      var out = [UInt8](repeating: 0, count: input.count)
      var rc: Int32 = 0
      key.bytes.withUnsafeBytes { k in
        nonce.withUnsafeBytes { n in
          aad.withUnsafeBytes { a in
            input.withUnsafeBytes { i in
              out.withUnsafeMutableBytes { o in
                tag.withUnsafeMutableBytes { t in
                  // C never reads through an empty buffer's pointer.
                  let dummy = UnsafeRawPointer(bitPattern: 16)!
                  let argv: [Int] = [
                    Int(bitPattern: k.baseAddress!), kc,
                    Int(bitPattern: n.baseAddress!), n.count,
                    Int(bitPattern: a.baseAddress ?? dummy), a.count,
                    Int(bitPattern: i.baseAddress ?? dummy), i.count,
                    Int(bitPattern: o.baseAddress ?? UnsafeMutableRawPointer(mutating: dummy)),
                    Int(bitPattern: t.baseAddress!),
                  ]
                  rc = argv.withUnsafeBufferPointer { _ck_gcm(op, $0.baseAddress!) }
                }
              }
            }
          }
        }
      }
      if rc != 0 { throw CryptoKitError.authenticationFailure }
      return out
    }

    public static func seal<Plaintext: DataProtocol, AuthenticatedData: DataProtocol>(
      _ message: Plaintext, using key: SymmetricKey, nonce: AES.GCM.Nonce? = nil,
      authenticating authenticatedData: AuthenticatedData
    ) throws -> AES.GCM.SealedBox {
      let n = nonce ?? AES.GCM.Nonce()
      var tag = [UInt8](repeating: 0, count: 16)
      let ct = try _run(0, key: key, nonce: n.bytes, aad: _bytes(of: authenticatedData),
                        input: _bytes(of: message), tag: &tag)
      return SealedBox(nonce: n, ciphertextBytes: ct, tagBytes: tag)
    }

    public static func seal<Plaintext: DataProtocol>(
      _ message: Plaintext, using key: SymmetricKey, nonce: AES.GCM.Nonce? = nil
    ) throws -> AES.GCM.SealedBox {
      return try seal(message, using: key, nonce: nonce, authenticating: [UInt8]())
    }

    public static func open<AuthenticatedData: DataProtocol>(
      _ sealedBox: AES.GCM.SealedBox, using key: SymmetricKey,
      authenticating authenticatedData: AuthenticatedData
    ) throws -> Data {
      var tag = _bytes(of: sealedBox.tag)
      if tag.count != 16 { throw CryptoKitError.authenticationFailure }
      let pt = try _run(1, key: key, nonce: sealedBox.nonce.bytes, aad: _bytes(of: authenticatedData),
                        input: _bytes(of: sealedBox.ciphertext), tag: &tag)
      return Data(pt)
    }

    public static func open(_ sealedBox: AES.GCM.SealedBox, using key: SymmetricKey) throws -> Data {
      return try open(sealedBox, using: key, authenticating: [UInt8]())
    }
  }
}
