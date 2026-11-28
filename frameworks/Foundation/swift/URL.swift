// URL: a value type over NSURL. Parsing and the components come from the
// Objective-C NSURL; path manipulation is done here on the string form.

public struct URL: Equatable, Hashable, Sendable {
  nonisolated(unsafe) internal let _url: NSURL // immutable once made

  internal init(_nsurl: NSURL) { _url = _nsurl }

  public enum DirectoryHint: Sendable, Hashable {
    case isDirectory
    case notDirectory
    case checkFileSystem
    case inferFromPath
  }

  // ---- creating ----------------------------------------------------------------

  public init?(string: __shared String) {
    guard !string.isEmpty, let u = NSURL(string: string) else { return nil }
    _url = u
  }
  public init?(string: __shared String, encodingInvalidCharacters: Bool) {
    self.init(string: encodingInvalidCharacters ? URL._percentEncodeInvalid(string) : string)
  }
  /// The reference resolved against the base as RFC 3986 says ("../x?y"
  /// against https://h.com/a/b/c is https://h.com/a/x?y).
  public init?(string: __shared String, relativeTo url: __shared URL?) {
    guard let base = url else {
      self.init(string: string)
      return
    }
    guard let u = NSURL(string: string, relativeTo: base) else { return nil }
    self = u as URL
  }
  public init(fileURLWithPath path: __shared String) {
    _url = NSURL(fileURLWithPath: URL._absolutePath(path))
  }
  public init(fileURLWithPath path: __shared String, isDirectory: Bool) {
    var p = URL._absolutePath(path)
    if isDirectory && !p.hasSuffix("/") { p += "/" }
    _url = NSURL(fileURLWithPath: p)
  }
  public init(fileURLWithPath path: __shared String, relativeTo base: __shared URL?) {
    if path.hasPrefix("/") || base == nil {
      self.init(fileURLWithPath: path)
    } else {
      self.init(fileURLWithPath: base!.path + "/" + path)
    }
  }
  public init(filePath path: String, directoryHint: DirectoryHint = .inferFromPath, relativeTo base: URL? = nil) {
    var full = path
    if !path.hasPrefix("/"), let b = base { full = b.path + "/" + path }
    switch directoryHint {
    case .isDirectory: self.init(fileURLWithPath: full, isDirectory: true)
    case .notDirectory: self.init(fileURLWithPath: full, isDirectory: false)
    case .checkFileSystem: self.init(fileURLWithPath: full, isDirectory: URL._isDirectoryOnDisk(full))
    case .inferFromPath: self.init(fileURLWithPath: full, isDirectory: full.hasSuffix("/"))
    }
  }
  public init?(fileURLWithFileSystemRepresentation path: UnsafePointer<Int8>, isDirectory: Bool, relativeTo base: URL?) {
    self.init(fileURLWithPath: String(cString: path), relativeTo: base)
  }

  // ---- reading ------------------------------------------------------------------

  public var absoluteString: String { return _url.absoluteString ?? "" }
  public var absoluteURL: URL { return self }
  public var baseURL: URL? { return nil }
  public var relativeString: String { return absoluteString }
  public var scheme: String? { return _url.scheme }
  public var host: String? { return _url.host }
  public func host(percentEncoded: Bool = true) -> String? { return _url.host }
  public var port: Int? { return _url.port?.integerValue }
  public var user: String? { return nil }
  public var password: String? { return nil }
  public var query: String? { return _url.query }
  public func query(percentEncoded: Bool = true) -> String? { return _url.query }
  public var fragment: String? { return _url.fragment }
  public func fragment(percentEncoded: Bool = true) -> String? { return _url.fragment }
  public var isFileURL: Bool { return _url.isFileURL }
  public var hasDirectoryPath: Bool { return absoluteString.hasSuffix("/") }

  /// The path, percent-decoded, without a trailing slash (except "/").
  public var path: String {
    let p = URL._percentDecode(_url.path ?? "")
    if p.count > 1 && p.hasSuffix("/") { return String(p.dropLast()) }
    return p
  }
  public func path(percentEncoded: Bool = true) -> String {
    return percentEncoded ? (_url.path ?? "") : path
  }
  public var relativePath: String { return path }
  public var lastPathComponent: String {
    let p = path
    if p == "/" { return "/" }
    if let slash = p.lastIndex(of: "/") { return String(p[p.index(after: slash)...]) }
    return p
  }
  public var pathExtension: String {
    let last = lastPathComponent
    guard let dot = last.lastIndex(of: "."), dot != last.startIndex else { return "" }
    return String(last[last.index(after: dot)...])
  }
  public var pathComponents: [String] {
    let p = path
    var parts: [String] = []
    if p.hasPrefix("/") { parts.append("/") }
    for c in p.split(separator: "/") { parts.append(String(c)) }
    return parts
  }

  // ---- deriving -----------------------------------------------------------------------

  private func _withPath(_ newPath: String, directory: Bool) -> URL {
    if isFileURL { return URL(fileURLWithPath: newPath, isDirectory: directory) }
    var s = absoluteString
    let oldPath = _url.path ?? ""
    if let r = s.range(of: oldPath) {
      s = String(s[..<r.lowerBound]) + newPath + String(s[r.upperBound...])
    }
    return URL(string: s) ?? self
  }
  public func appendingPathComponent(_ component: String) -> URL {
    return appendingPathComponent(component, isDirectory: component.hasSuffix("/"))
  }
  public func appendingPathComponent(_ component: String, isDirectory: Bool) -> URL {
    var base = path
    if !base.hasSuffix("/") { base += "/" }
    var c = component
    while c.hasPrefix("/") { c = String(c.dropFirst()) }
    return _withPath(base + c, directory: isDirectory)
  }
  public func appending<S: StringProtocol>(path: S, directoryHint: DirectoryHint = .inferFromPath) -> URL {
    let s = String(path)
    switch directoryHint {
    case .isDirectory: return appendingPathComponent(s, isDirectory: true)
    case .notDirectory: return appendingPathComponent(s, isDirectory: false)
    default: return appendingPathComponent(s)
    }
  }
  public func appending<S: StringProtocol>(component: S, directoryHint: DirectoryHint = .inferFromPath) -> URL {
    return appending(path: String(component).replacingOccurrences_("/", with: "%2F"), directoryHint: directoryHint)
  }
  public func appendingPathExtension(_ pathExtension: String) -> URL {
    if pathExtension.isEmpty { return self }
    return _withPath(path + "." + pathExtension, directory: false)
  }
  public func deletingLastPathComponent() -> URL {
    let p = path
    guard let slash = p.lastIndex(of: "/") else { return _withPath("./", directory: true) }
    let parent = slash == p.startIndex ? "/" : String(p[..<slash]) + "/"
    return _withPath(parent, directory: true)
  }
  public func deletingPathExtension() -> URL {
    let ext = pathExtension
    if ext.isEmpty { return self }
    return _withPath(String(path.dropLast(ext.count + 1)), directory: false)
  }
  public mutating func appendPathComponent(_ component: String) { self = appendingPathComponent(component) }
  public mutating func appendPathComponent(_ component: String, isDirectory: Bool) {
    self = appendingPathComponent(component, isDirectory: isDirectory)
  }
  public mutating func append<S: StringProtocol>(path: S, directoryHint: DirectoryHint = .inferFromPath) {
    self = appending(path: path, directoryHint: directoryHint)
  }
  public mutating func appendPathExtension(_ pathExtension: String) { self = appendingPathExtension(pathExtension) }
  public mutating func deleteLastPathComponent() { self = deletingLastPathComponent() }
  public mutating func deletePathExtension() { self = deletingPathExtension() }

  /// Removes "." and ".." components.
  public var standardized: URL {
    var out: [String] = []
    for c in path.split(separator: "/") {
      if c == "." { continue }
      if c == ".." {
        if !out.isEmpty { out.removeLast() }
        continue
      }
      out.append(String(c))
    }
    return _withPath("/" + out.joined(separator: "/"), directory: hasDirectoryPath)
  }
  public var standardizedFileURL: URL { return isFileURL ? standardized : self }
  public func resolvingSymlinksInPath() -> URL {
    guard isFileURL else { return self }
    return path.withCString { p -> URL in
      guard let resolved = realpath(p, nil) else { return standardized }
      defer { free(resolved) }
      return URL(fileURLWithPath: String(cString: resolved))
    }
  }
  public mutating func resolveSymlinksInPath() { self = resolvingSymlinksInPath() }
  public mutating func standardize() { self = standardized }

  public func withUnsafeFileSystemRepresentation<ResultType>(_ block: (UnsafePointer<Int8>?) throws -> ResultType) rethrows -> ResultType {
    return try path.withCString { try block($0) }
  }

  // Security-scoped resources do not exist outside the macOS sandbox.
  public func startAccessingSecurityScopedResource() -> Bool { return true }
  public func stopAccessingSecurityScopedResource() {}

  // ---- well-known directories --------------------------------------------------------------

  static func _home() -> String {
    if let h = getenv("HOME") { return String(cString: h) }
    return "/Users/" + (getenv("USER").map { String(cString: $0) } ?? "user")
  }
  public static var homeDirectory: URL { return URL(fileURLWithPath: _home(), isDirectory: true) }
  public static var temporaryDirectory: URL {
    let t = getenv("TMPDIR").map { String(cString: $0) } ?? "/tmp/"
    return URL(fileURLWithPath: t, isDirectory: true)
  }
  public static var applicationSupportDirectory: URL {
    return URL(fileURLWithPath: _home() + "/Library/Application Support", isDirectory: true)
  }
  public static var cachesDirectory: URL { return URL(fileURLWithPath: _home() + "/Library/Caches", isDirectory: true) }
  public static var documentsDirectory: URL { return URL(fileURLWithPath: _home() + "/Documents", isDirectory: true) }
  public static var libraryDirectory: URL { return URL(fileURLWithPath: _home() + "/Library", isDirectory: true) }
  public static var downloadsDirectory: URL { return URL(fileURLWithPath: _home() + "/Downloads", isDirectory: true) }
  public static var desktopDirectory: URL { return URL(fileURLWithPath: _home() + "/Desktop", isDirectory: true) }
  public static var currentDirectory: URL {
    var buf = [Int8](repeating: 0, count: 4096)
    let p = buf.withUnsafeMutableBufferPointer { getcwd($0.baseAddress, 4096) }
    return URL(fileURLWithPath: p.map { String(cString: $0) } ?? "/", isDirectory: true)
  }

  // ---- equality --------------------------------------------------------------------------------

  public static func == (lhs: URL, rhs: URL) -> Bool { return lhs.absoluteString == rhs.absoluteString }
  public func hash(into hasher: inout Hasher) { hasher.combine(absoluteString) }

  // ---- helpers -----------------------------------------------------------------------------------

  static func _absolutePath(_ path: String) -> String {
    if path.hasPrefix("/") { return path }
    if path.hasPrefix("~") { return _home() + String(path.dropFirst()) }
    return currentDirectory.path + "/" + path
  }
  static func _isDirectoryOnDisk(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
  }
  static func _percentDecode(_ s: String) -> String {
    guard s.contains("%") else { return s }
    var bytes: [UInt8] = []
    var it = Array(s.utf8)[...]
    while let b = it.first {
      it = it.dropFirst()
      if b == UInt8(ascii: "%"), it.count >= 2, let v = UInt8(String(decoding: it.prefix(2), as: UTF8.self), radix: 16) {
        bytes.append(v)
        it = it.dropFirst(2)
      } else {
        bytes.append(b)
      }
    }
    return String(decoding: bytes, as: UTF8.self)
  }
  static func _percentEncodeInvalid(_ s: String) -> String {
    var out = ""
    for b in s.utf8 {
      if b < 0x21 || b > 0x7E || b == UInt8(ascii: "\"") || b == UInt8(ascii: "<") || b == UInt8(ascii: ">")
        || b == UInt8(ascii: "\\") || b == UInt8(ascii: "^") || b == UInt8(ascii: "`") || b == UInt8(ascii: "{")
        || b == UInt8(ascii: "|") || b == UInt8(ascii: "}") {
        let hex = String(b, radix: 16, uppercase: true)
        out += "%" + (hex.count == 1 ? "0" + hex : hex)
      } else {
        out.unicodeScalars.append(Unicode.Scalar(b))
      }
    }
    return out
  }
}

extension String {
  internal func replacingOccurrences_(_ target: String, with replacement: String) -> String {
    var out = ""
    var rest = self[...]
    while let r = rest.range(of: target) {
      out += rest[..<r.lowerBound] + replacement
      rest = rest[r.upperBound...]
    }
    return out + rest
  }
}

extension URL: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSURL
  public func _bridgeToObjectiveC() -> NSURL { return _url }
  public static func _forceBridgeFromObjectiveC(_ source: NSURL, result: inout URL?) { result = URL(_nsurl: source) }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSURL, result: inout URL?) -> Bool {
    result = URL(_nsurl: source)
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSURL?) -> URL {
    return URL(_nsurl: source ?? NSURL(fileURLWithPath: "/"))
  }
}

extension URL: Codable {
  private enum CodingKeys: String, CodingKey { case base, relative }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let relative = try c.decode(String.self, forKey: .relative)
    guard let u = URL(string: relative) else {
      throw DecodingError.dataCorruptedError(forKey: .relative, in: c, debugDescription: "Invalid URL string.")
    }
    self = u
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(absoluteString, forKey: .relative)
  }
}

extension URL: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String { return absoluteString }
  public var debugDescription: String { return absoluteString }
}
