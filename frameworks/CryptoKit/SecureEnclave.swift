// The Secure Enclave: there is none here. isAvailable is false, and making
// or loading an enclave key throws, as it does on a Mac without one.
import Foundation
import Security
import LocalAuthentication

public enum SecureEnclave {
  public static var isAvailable: Bool { return false }

  public enum P256 {
    public enum Signing {
      public struct PrivateKey {
        let key: CryptoKit.P256.Signing.PrivateKey
        let data: [UInt8]

        public var publicKey: CryptoKit.P256.Signing.PublicKey { return key.publicKey }
        public var dataRepresentation: Data { return Data(data) }

        public init(compactRepresentable: Bool = true, accessControl: SecAccessControl,
                    authenticationContext: LAContext? = nil) throws {
          throw CryptoKitError.underlyingCoreCryptoError(error: -4)   // errSecUnimplemented
        }
        public init(dataRepresentation: Data, authenticationContext: LAContext? = nil) throws {
          throw CryptoKitError.underlyingCoreCryptoError(error: -4)
        }

        public func signature<D: DataProtocol>(for data: D) throws -> CryptoKit.P256.Signing.ECDSASignature {
          return try key.signature(for: data)
        }
      }
    }
  }
}
