// CryptoKit: hashes, AES-GCM, the NIST curves and Curve25519, against
// published test vectors and round trips.
import Foundation
import CryptoKit

func hex(_ s: String) -> [UInt8] {
  var out = [UInt8](), cur: UInt8 = 0, half = false
  for c in s.utf8 {
    let v: UInt8 = c >= 97 ? c - 87 : c - 48
    if half { out.append(cur << 4 | v) } else { cur = v }
    half.toggle()
  }
  return out
}

func bytes<B: ContiguousBytes>(_ b: B) -> [UInt8] { return b.withUnsafeBytes { Array($0) } }

@_silgen_name("swl_ck_hashes") public func hashes() -> Int {
  var bad = 0
  let abc: [UInt8] = [97, 98, 99]
  if bytes(SHA256.hash(data: abc)) != hex("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") { bad |= 1 }
  if bytes(SHA384.hash(data: abc)) != hex("cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7") { bad |= 2 }
  if bytes(SHA512.hash(data: abc)) != hex("ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f") { bad |= 4 }
  var h = SHA256()
  h.update(data: [97] as [UInt8])
  let copy = h                                   // value semantics
  h.update(data: [98, 99] as [UInt8])
  if h.finalize() != SHA256.hash(data: abc) { bad |= 8 }
  if copy.finalize() != SHA256.hash(data: [97] as [UInt8]) { bad |= 16 }
  if !SHA256.hash(data: abc).description.hasPrefix("SHA256 digest: ba7816bf") { bad |= 32 }
  if SHA256Digest.byteCount != 32 || Array(SHA512.hash(data: abc)).count != 64 { bad |= 64 }
  return bad
}

@_silgen_name("swl_ck_aes") public func aes() -> Int {
  var bad = 0
  do {
    // GCM test case 2 (McGrew & Viega): zero key, nonce and plaintext.
    let key = SymmetricKey(data: [UInt8](repeating: 0, count: 16))
    let box = try AES.GCM.seal([UInt8](repeating: 0, count: 16), using: key,
                               nonce: try AES.GCM.Nonce(data: [UInt8](repeating: 0, count: 12)))
    if Array(box.ciphertext) != hex("0388dace60b6a392f328c2b971b2fe78") { bad |= 1 }
    if Array(box.tag) != hex("ab6e47d42cec13bdf53a67b21257bddf") { bad |= 2 }
    let k2 = SymmetricKey(size: .bits256)
    if k2.bitCount != 256 || k2 == key { bad |= 4 }
    let msg = Array("hello, mac app".utf8), aad: [UInt8] = [1, 2, 3]
    let sealed = try AES.GCM.seal(msg, using: k2, authenticating: aad)
    let combined = sealed.combined!
    if combined.count != 12 + msg.count + 16 { bad |= 8 }
    let reopened = AES.GCM.SealedBox(combined: combined)
    if Array(try AES.GCM.open(reopened, using: k2, authenticating: aad)) != msg { bad |= 16 }
    var tampered = Array(combined)
    tampered[14] ^= 1
    if (try? AES.GCM.open(AES.GCM.SealedBox(combined: Data(tampered)), using: k2, authenticating: aad)) != nil { bad |= 32 }
    if (try? AES.GCM.open(reopened, using: k2, authenticating: [9] as [UInt8])) != nil { bad |= 64 }
    if (try? AES.GCM.open(AES.GCM.SealedBox(combined: Data([1, 2, 3])), using: k2)) != nil { bad |= 128 }
  } catch {
    bad |= 0x100
  }
  return bad
}

@_silgen_name("swl_ck_curve25519") public func curve25519() -> Int {
  var bad = 0
  do {
    // RFC 8032, test 1.
    let sk = try Curve25519.Signing.PrivateKey(rawRepresentation: hex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"))
    if Array(sk.publicKey.rawRepresentation) != hex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a") { bad |= 1 }
    let rfcSig = hex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
    if Array(try sk.signature(for: [UInt8]())) != rfcSig { bad |= 2 }
    let pk = try Curve25519.Signing.PublicKey(rawRepresentation: sk.publicKey.rawRepresentation)
    if !pk.isValidSignature(rfcSig, for: [UInt8]()) { bad |= 4 }
    if pk.isValidSignature(rfcSig, for: [0] as [UInt8]) { bad |= 8 }
    let fresh = Curve25519.Signing.PrivateKey()
    let msg = Array("signed".utf8)
    if !fresh.publicKey.isValidSignature(try fresh.signature(for: msg), for: msg) { bad |= 16 }
    // RFC 7748, section 5.2.
    let a = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: hex("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4"))
    let u = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: hex("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c"))
    if bytes(try a.sharedSecretFromKeyAgreement(with: u)) != hex("c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552") { bad |= 32 }
    let x = Curve25519.KeyAgreement.PrivateKey(), y = Curve25519.KeyAgreement.PrivateKey()
    if bytes(try x.sharedSecretFromKeyAgreement(with: y.publicKey)) != bytes(try y.sharedSecretFromKeyAgreement(with: x.publicKey)) { bad |= 64 }
    if (try? Curve25519.Signing.PublicKey(rawRepresentation: [1, 2, 3] as [UInt8])) != nil { bad |= 128 }
  } catch {
    bad |= 0x100
  }
  return bad
}

@_silgen_name("swl_ck_nist") public func nist() -> Int {
  var bad = 0
  do {
    let msg = Array("message".utf8)
    let k256 = P256.Signing.PrivateKey()
    let s256 = try k256.signature(for: msg)
    if s256.rawRepresentation.count != 64 || !k256.publicKey.isValidSignature(s256, for: msg) { bad |= 1 }
    if k256.publicKey.isValidSignature(s256, for: [1] as [UInt8]) { bad |= 2 }
    let again = try P256.Signing.PublicKey(x963Representation: k256.publicKey.x963Representation)
    if !again.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: s256.rawRepresentation), for: msg) { bad |= 4 }
    let same = try P256.Signing.PrivateKey(rawRepresentation: k256.rawRepresentation)
    if same.publicKey.rawRepresentation != k256.publicKey.rawRepresentation { bad |= 8 }
    let k384 = P384.Signing.PrivateKey(), k521 = P521.Signing.PrivateKey()
    if !k384.publicKey.isValidSignature(try k384.signature(for: msg), for: msg) { bad |= 16 }
    if !k521.publicKey.isValidSignature(try k521.signature(for: msg), for: msg) { bad |= 32 }
    if k521.publicKey.x963Representation.count != 133 { bad |= 64 }
    // ECDH both ways.
    let a = P384.KeyAgreement.PrivateKey(), b = P384.KeyAgreement.PrivateKey()
    let pubA = try P384.KeyAgreement.PublicKey(x963Representation: a.publicKey.x963Representation)
    if bytes(try a.sharedSecretFromKeyAgreement(with: b.publicKey)) != bytes(try b.sharedSecretFromKeyAgreement(with: pubA)) { bad |= 128 }
    // PEM (SEC 1) with d = 1: the public key is the generator.
    let pem = "-----BEGIN EC PRIVATE KEY-----\nMCUCAQEEIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB\n-----END EC PRIVATE KEY-----\n"
    let one = try P256.Signing.PrivateKey(pemRepresentation: pem)
    if Array(one.publicKey.x963Representation) != hex("046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5") { bad |= 256 }
    // Not on the curve.
    if (try? P256.Signing.PublicKey(x963Representation: [4] + [UInt8](repeating: 1, count: 64))) != nil { bad |= 512 }
    if (try? P256.Signing.ECDSASignature(rawRepresentation: [UInt8](repeating: 1, count: 10))) != nil { bad |= 1024 }
    if SecureEnclave.isAvailable { bad |= 2048 }
  } catch {
    bad |= 0x1000
  }
  return bad
}
