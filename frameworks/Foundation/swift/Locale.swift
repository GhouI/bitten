// Locale: an identifier such as "en_US". The current locale comes from
// LC_ALL / LC_MESSAGES / LANG, defaulting to en_US.

@_silgen_name("getenv")
internal func _bitten_getenv(_ name: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

public struct Locale: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  public typealias LanguageCode = String
  public let identifier: String

  public init(identifier: String) { self.identifier = Locale._canonical(identifier) }

  internal static func _canonical(_ id: String) -> String {
    // "en-US.UTF-8" -> "en_US"
    var s = id
    if let dot = s.firstIndex(of: ".") { s = String(s[..<dot]) }
    if let at = s.firstIndex(of: "@") { s = String(s[..<at]) }
    return s.replacingOccurrences(of: "-", with: "_")
  }

  internal static var _environmentIdentifier: String {
    for name in ["LC_ALL", "LC_MESSAGES", "LANG"] {
      if let v = name.withCString({ _bitten_getenv($0) }) {
        let s = String(cString: v)
        if !s.isEmpty && s != "C" && s != "POSIX" { return s }
      }
    }
    return "en_US"
  }

  public static var current: Locale { return Locale(identifier: _environmentIdentifier) }
  public static var autoupdatingCurrent: Locale { return current }
  public static var preferredLanguages: [String] {
    return [current.identifier.replacingOccurrences(of: "_", with: "-")]
  }

  public var languageCode: String? {
    let parts = identifier.split(separator: "_")
    return parts.first.map(String.init)
  }
  public var regionCode: String? {
    let parts = identifier.split(separator: "_")
    return parts.count > 1 ? String(parts[1]) : nil
  }

  public var description: String { return identifier }
  public var debugDescription: String { return identifier }
}

extension Locale: Codable {
  public init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    self.init(identifier: try c.decode(String.self))
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    try c.encode(identifier)
  }
}
