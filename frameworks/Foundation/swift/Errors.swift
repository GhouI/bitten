// Foundation's error protocols and types: LocalizedError, CustomNSError,
// the stored-NSError structs (CocoaError, POSIXError, URLError) with their
// Code types, and `Error.localizedDescription`. Declarations are Apple's
// (programs conform to these protocols and match on these codes).

// MARK: - protocols

public protocol LocalizedError: Error {
  var errorDescription: String? { get }
  var failureReason: String? { get }
  var recoverySuggestion: String? { get }
  var helpAnchor: String? { get }
}

extension LocalizedError {
  public var errorDescription: String? { return nil }
  public var failureReason: String? { return nil }
  public var recoverySuggestion: String? { return nil }
  public var helpAnchor: String? { return nil }
}

public protocol CustomNSError: Error {
  static var errorDomain: String { get }
  var errorCode: Int { get }
  var errorUserInfo: [String: Any] { get }
}

extension CustomNSError {
  public static var errorDomain: String { return String(reflecting: self) }
  public var errorCode: Int { return _code }
  public var errorUserInfo: [String: Any] { return [:] }
}

public protocol RecoverableError: Error {
  var recoveryOptions: [String] { get }
  func attemptRecovery(optionIndex recoveryOptionIndex: Int, resultHandler handler: @escaping (_ recovered: Bool) -> Void)
  func attemptRecovery(optionIndex recoveryOptionIndex: Int) -> Bool
}

extension RecoverableError {
  public func attemptRecovery(optionIndex recoveryOptionIndex: Int, resultHandler handler: @escaping (_ recovered: Bool) -> Void) {
    handler(attemptRecovery(optionIndex: recoveryOptionIndex))
  }
}

public protocol _ObjectiveCBridgeableError: Error {
  init?(_bridgedNSError: NSError)
}

public protocol _ErrorCodeProtocol: Equatable {
  associatedtype _ErrorType: _BridgedStoredNSError where _ErrorType.Code == Self
}

extension _ErrorCodeProtocol {
  /// Lets `catch CocoaError.fileNoSuchFile` match a thrown error.
  public static func ~= (match: Self, error: Error) -> Bool {
    guard let specific = error as? Self._ErrorType else { return false }
    return match == specific.code
  }
}

public protocol _BridgedStoredNSError: CustomNSError, _ObjectiveCBridgeableError, Hashable {
  associatedtype Code: _ErrorCodeProtocol, RawRepresentable where Code.RawValue: FixedWidthInteger
  var _nsError: NSError { get }
  init(_nsError error: NSError)
}

extension _BridgedStoredNSError {
  public init?(_bridgedNSError error: NSError) {
    guard error.domain == Self.errorDomain else { return nil }
    self.init(_nsError: error)
  }
  public init(_ code: Code, userInfo: [String: Any] = [:]) {
    self.init(_nsError: NSError._bn_error(withDomain: Self.errorDomain, code: numericCast(code.rawValue),
                                           filePath: userInfo[NSFilePathErrorKey] as? String, underlyingPOSIX: 0) as NSError)
  }
  public var code: Code { return Code(rawValue: numericCast(_nsError.code))! }
  public var errorCode: Int { return _nsError.code }
  public var errorUserInfo: [String: Any] {
    var out: [String: Any] = [:]
    if let info = _nsError.userInfo {
      for (k, v) in info { if let key = k as? String { out[key] = v } }
    }
    return out
  }
  public var userInfo: [String: Any] { return errorUserInfo }
  public var localizedDescription: String { return _nsError.localizedDescription }
  public var _domain: String { return Self.errorDomain }
  public var _code: Int { return _nsError.code }
  public func _getEmbeddedNSError() -> AnyObject? { return _nsError }
  public static func == (a: Self, b: Self) -> Bool { return a._nsError.isEqual(b._nsError) }
  public func hash(into hasher: inout Hasher) { hasher.combine(_nsError.code) }
}

extension Error {
  public var localizedDescription: String {
    if let e = self as? LocalizedError, let d = e.errorDescription { return d }
    return _convertErrorToNSError(self).localizedDescription
  }
}

// MARK: - CocoaError

public struct CocoaError: _BridgedStoredNSError {
  public let _nsError: NSError
  public init(_nsError error: NSError) { _nsError = error }
  public static var errorDomain: String { return NSCocoaErrorDomain }

  public struct Code: RawRepresentable, Hashable, _ErrorCodeProtocol, Sendable {
    public typealias _ErrorType = CocoaError
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static var fileNoSuchFile: Code { return Code(rawValue: 4) }
    public static var fileLocking: Code { return Code(rawValue: 255) }
    public static var fileReadUnknown: Code { return Code(rawValue: 256) }
    public static var fileReadNoPermission: Code { return Code(rawValue: 257) }
    public static var fileReadInvalidFileName: Code { return Code(rawValue: 258) }
    public static var fileReadCorruptFile: Code { return Code(rawValue: 259) }
    public static var fileReadNoSuchFile: Code { return Code(rawValue: 260) }
    public static var fileReadInapplicableStringEncoding: Code { return Code(rawValue: 261) }
    public static var fileReadUnsupportedScheme: Code { return Code(rawValue: 262) }
    public static var fileReadTooLarge: Code { return Code(rawValue: 263) }
    public static var fileReadUnknownStringEncoding: Code { return Code(rawValue: 264) }
    public static var fileWriteUnknown: Code { return Code(rawValue: 512) }
    public static var fileWriteNoPermission: Code { return Code(rawValue: 513) }
    public static var fileWriteInvalidFileName: Code { return Code(rawValue: 514) }
    public static var fileWriteFileExists: Code { return Code(rawValue: 516) }
    public static var fileWriteInapplicableStringEncoding: Code { return Code(rawValue: 517) }
    public static var fileWriteUnsupportedScheme: Code { return Code(rawValue: 518) }
    public static var fileWriteOutOfSpace: Code { return Code(rawValue: 640) }
    public static var fileWriteVolumeReadOnly: Code { return Code(rawValue: 642) }
    public static var keyValueValidation: Code { return Code(rawValue: 1024) }
    public static var formatting: Code { return Code(rawValue: 2048) }
    public static var userCancelled: Code { return Code(rawValue: 3072) }
    public static var featureUnsupported: Code { return Code(rawValue: 3328) }
    public static var propertyListReadCorrupt: Code { return Code(rawValue: 3840) }
    public static var propertyListReadUnknownVersion: Code { return Code(rawValue: 3841) }
    public static var propertyListReadStream: Code { return Code(rawValue: 3842) }
    public static var propertyListWriteStream: Code { return Code(rawValue: 3851) }
    public static var propertyListWriteInvalid: Code { return Code(rawValue: 3852) }
    public static var executableNotLoadable: Code { return Code(rawValue: 3584) }
    public static var coderReadCorrupt: Code { return Code(rawValue: 4864) }
    public static var coderValueNotFound: Code { return Code(rawValue: 4865) }
    public static var coderInvalidValue: Code { return Code(rawValue: 4866) }
  }

  public static var fileNoSuchFile: Code { return .fileNoSuchFile }
  public static var fileReadNoSuchFile: Code { return .fileReadNoSuchFile }
  public static var fileReadNoPermission: Code { return .fileReadNoPermission }
  public static var fileReadUnknown: Code { return .fileReadUnknown }
  public static var fileReadCorruptFile: Code { return .fileReadCorruptFile }
  public static var fileWriteFileExists: Code { return .fileWriteFileExists }
  public static var fileWriteUnknown: Code { return .fileWriteUnknown }
  public static var fileWriteNoPermission: Code { return .fileWriteNoPermission }
  public static var userCancelled: Code { return .userCancelled }
  public static var featureUnsupported: Code { return .featureUnsupported }
  public static var coderInvalidValue: Code { return .coderInvalidValue }
  public static var coderReadCorrupt: Code { return .coderReadCorrupt }
  public static var coderValueNotFound: Code { return .coderValueNotFound }

  public var filePath: String? { return _nsError.userInfo?[NSFilePathErrorKey] as? String }
  public var underlying: Error? { return _nsError.userInfo?[NSUnderlyingErrorKey] as? NSError }
}

// MARK: - POSIXError

public struct POSIXError: _BridgedStoredNSError {
  public let _nsError: NSError
  public init(_nsError error: NSError) { _nsError = error }
  public static var errorDomain: String { return NSPOSIXErrorDomain }
  public typealias Code = POSIXErrorCode
}

extension POSIXErrorCode: _ErrorCodeProtocol {
  public typealias _ErrorType = POSIXError
}

// MARK: - URLError

public struct URLError: _BridgedStoredNSError {
  public let _nsError: NSError
  public init(_nsError error: NSError) { _nsError = error }
  public static var errorDomain: String { return NSURLErrorDomain }

  public struct Code: RawRepresentable, Hashable, _ErrorCodeProtocol, Sendable {
    public typealias _ErrorType = URLError
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static var unknown: Code { return Code(rawValue: -1) }
    public static var cancelled: Code { return Code(rawValue: -999) }
    public static var badURL: Code { return Code(rawValue: -1000) }
    public static var timedOut: Code { return Code(rawValue: -1001) }
    public static var unsupportedURL: Code { return Code(rawValue: -1002) }
    public static var cannotFindHost: Code { return Code(rawValue: -1003) }
    public static var cannotConnectToHost: Code { return Code(rawValue: -1004) }
    public static var networkConnectionLost: Code { return Code(rawValue: -1005) }
    public static var dnsLookupFailed: Code { return Code(rawValue: -1006) }
    public static var httpTooManyRedirects: Code { return Code(rawValue: -1007) }
    public static var resourceUnavailable: Code { return Code(rawValue: -1008) }
    public static var notConnectedToInternet: Code { return Code(rawValue: -1009) }
    public static var redirectToNonExistentLocation: Code { return Code(rawValue: -1010) }
    public static var badServerResponse: Code { return Code(rawValue: -1011) }
    public static var userCancelledAuthentication: Code { return Code(rawValue: -1012) }
    public static var userAuthenticationRequired: Code { return Code(rawValue: -1013) }
    public static var zeroByteResource: Code { return Code(rawValue: -1014) }
    public static var cannotDecodeRawData: Code { return Code(rawValue: -1015) }
    public static var cannotDecodeContentData: Code { return Code(rawValue: -1016) }
    public static var cannotParseResponse: Code { return Code(rawValue: -1017) }
    public static var fileDoesNotExist: Code { return Code(rawValue: -1100) }
    public static var fileIsDirectory: Code { return Code(rawValue: -1101) }
    public static var noPermissionsToReadFile: Code { return Code(rawValue: -1102) }
    public static var dataLengthExceedsMaximum: Code { return Code(rawValue: -1103) }
    public static var secureConnectionFailed: Code { return Code(rawValue: -1200) }
    public static var serverCertificateHasBadDate: Code { return Code(rawValue: -1201) }
    public static var serverCertificateUntrusted: Code { return Code(rawValue: -1202) }
    public static var serverCertificateHasUnknownRoot: Code { return Code(rawValue: -1203) }
    public static var serverCertificateNotYetValid: Code { return Code(rawValue: -1204) }
    public static var clientCertificateRejected: Code { return Code(rawValue: -1205) }
    public static var clientCertificateRequired: Code { return Code(rawValue: -1206) }
    public static var cannotLoadFromNetwork: Code { return Code(rawValue: -2000) }
  }

  public var failingURL: URL? {
    return (_nsError.userInfo?[NSURLErrorFailingURLErrorKey] as? NSURL).map { URL(_nsurl: $0) }
  }
}

/// Called by the runtime's dynamic casts for `nsError as? CocoaError` and
/// the like (a thrown CocoaError travels as its NSError).
@_silgen_name("_bitten_bridgeNSErrorToValue")
public func _bitten_bridgeNSErrorToValue<T>(_ error: NSError, _ target: UnsafeMutablePointer<T>) -> Bool {
  guard let bridgeable = T.self as? _ObjectiveCBridgeableError.Type,
        let value = bridgeable.init(_bridgedNSError: error) else { return false }
  target.initialize(to: value as! T)
  return true
}
