// Curve25519: Ed25519 signatures and X25519 key agreement (RFC 8032, RFC
// 7748), computed by mrun (src/frameworks/cryptokit/ec.c).
import Foundation

@_silgen_name("bitten_ck_x25519")
func _ck_x25519(_ scalar: UnsafeRawPointer, _ u: UnsafeRawPointer?, _ out: UnsafeMutableRawPointer) -> Int32
@_silgen_name("bitten_ck_ed25519_pub")
func _ck_ed25519_pub(_ seed: UnsafeRawPointer, _ pub: UnsafeMutableRawPointer) -> Int32
@_silgen_name("bitten_ck_ed25519_sign")
func _ck_ed25519_sign(_ seed: UnsafeRawPointer, _ msg: UnsafeRawPointer?, _ len: Int, _ sig: UnsafeMutableRawPointer) -> Int32
@_silgen_name("bitten_ck_ed25519_verify")
func _ck_ed25519_verify(_ pub: UnsafeRawPointer, _ msg: UnsafeRawPointer?, _ len: Int, _ sig: UnsafeRawPointer) -> Int32

func _x25519(_ scalar: [UInt8], _ u: [UInt8]?) -> [UInt8]? {
  var out = [UInt8](repeating: 0, count: 32)
  var rc: Int32 = 0
  scalar.withUnsafeBytes { s in
    out.withUnsafeMutableBytes { o in
      if let u = u {
        u.withUnsafeBytes { rc = _ck_x25519(s.baseAddress!, $0.baseAddress!, o.baseAddress!) }
      } else {
        rc = _ck_x25519(s.baseAddress!, nil, o.baseAddress!)
      }
    }
  }
  return rc == 0 ? out : nil
}

public enum Curve25519 {
  public enum Signing {
    public struct PublicKey {
      let bytes: [UInt8]

      public init<D: ContiguousBytes>(rawRepresentation data: D) throws {
        let b = _bytes(contiguous: data)
        if b.count != 32 { throw CryptoKitError.incorrectKeySize }
        bytes = b
      }

      init(bytes: [UInt8]) { self.bytes = bytes }

      public var rawRepresentation: Data { return Data(bytes) }

      public func isValidSignature<S: DataProtocol, D: DataProtocol>(_ signature: S, for data: D) -> Bool {
        let sig = _bytes(of: signature), msg = _bytes(of: data)
        if sig.count != 64 { return false }
        var rc: Int32 = -1
        bytes.withUnsafeBytes { p in
          sig.withUnsafeBytes { s in
            msg.withUnsafeBytes { m in
              rc = _ck_ed25519_verify(p.baseAddress!, m.baseAddress, m.count, s.baseAddress!)
            }
          }
        }
        return rc == 0
      }
    }

    public struct PrivateKey {
      let seed: [UInt8]

      public init() { seed = _randomBytes(32) }

      public init<D: ContiguousBytes>(rawRepresentation data: D) throws {
        let b = _bytes(contiguous: data)
        if b.count != 32 { throw CryptoKitError.incorrectKeySize }
        seed = b
      }

      public var rawRepresentation: Data { return Data(seed) }

      public var publicKey: Curve25519.Signing.PublicKey {
        var pub = [UInt8](repeating: 0, count: 32)
        seed.withUnsafeBytes { s in pub.withUnsafeMutableBytes { _ = _ck_ed25519_pub(s.baseAddress!, $0.baseAddress!) } }
        return PublicKey(bytes: pub)
      }

      public func signature<D: DataProtocol>(for data: D) throws -> Data {
        let msg = _bytes(of: data)
        var sig = [UInt8](repeating: 0, count: 64)
        var rc: Int32 = -1
        seed.withUnsafeBytes { s in
          msg.withUnsafeBytes { m in
            sig.withUnsafeMutableBytes { rc = _ck_ed25519_sign(s.baseAddress!, m.baseAddress, m.count, $0.baseAddress!) }
          }
        }
        if rc != 0 { throw CryptoKitError.underlyingCoreCryptoError(error: rc) }
        return Data(sig)
      }
    }
  }

  public enum KeyAgreement {
    public struct PublicKey {
      let bytes: [UInt8]

      public init<D: ContiguousBytes>(rawRepresentation data: D) throws {
        let b = _bytes(contiguous: data)
        if b.count != 32 { throw CryptoKitError.incorrectKeySize }
        bytes = b
      }

      init(bytes: [UInt8]) { self.bytes = bytes }

      public var rawRepresentation: Data { return Data(bytes) }
    }

    public struct PrivateKey {
      let bytes: [UInt8]

      public init() { bytes = _randomBytes(32) }

      public init<D: ContiguousBytes>(rawRepresentation data: D) throws {
        let b = _bytes(contiguous: data)
        if b.count != 32 { throw CryptoKitError.incorrectKeySize }
        bytes = b
      }

      public var rawRepresentation: Data { return Data(bytes) }

      public var publicKey: Curve25519.KeyAgreement.PublicKey {
        return PublicKey(bytes: _x25519(bytes, nil) ?? [UInt8](repeating: 0, count: 32))
      }

      public func sharedSecretFromKeyAgreement(with publicKeyShare: Curve25519.KeyAgreement.PublicKey) throws -> SharedSecret {
        guard let s = _x25519(bytes, publicKeyShare.bytes) else {
          throw CryptoKitError.underlyingCoreCryptoError(error: -1)
        }
        return SharedSecret(bytes: s)
      }
    }
  }
}
