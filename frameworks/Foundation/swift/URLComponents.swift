// URLComponents and URLQueryItem: a URL string taken apart per RFC 3986
// (scheme, user, password, host, port, path, query, fragment), with
// percent-encoded and decoded views of each part.

public struct URLQueryItem: Hashable, Equatable, Sendable, CustomStringConvertible {
  public var name: String
  public var value: String?
  public init(name: __shared String, value: __shared String?) {
    self.name = name
    self.value = value
  }
  public var description: String { return value.map { "\(name)=\($0)" } ?? name }
}

public struct URLComponents: Hashable, Equatable, Sendable, CustomStringConvertible {
  // Parts as they appear in the URL (percent-encoded).
  internal var _scheme: String?
  internal var _user: String?
  internal var _password: String?
  internal var _host: String?
  internal var _port: Int?
  internal var _path: String = ""
  internal var _query: String?
  internal var _fragment: String?

  public init() {}

  public init?(string: __shared String) {
    guard let parsed = URLComponents._parse(string) else { return nil }
    self = parsed
  }
  public init?(string: __shared String, encodingInvalidCharacters: Bool) {
    self.init(string: string)
  }
  public init?(url: __shared URL, resolvingAgainstBaseURL resolve: Bool) {
    self.init(string: url.absoluteString)
  }

  /// Splits a URL string; nil when it is not a valid URL reference.
  internal static func _parse(_ s: String) -> URLComponents? {
    var c = URLComponents()
    var rest = Substring(s)
    // Reject characters that may not appear unencoded.
    for b in s.utf8 where b <= 0x20 || b == 0x7F || b == 0x22 || b == 0x3C || b == 0x3E || b == 0x5C || b == 0x5E
      || b == 0x60 || b == 0x7B || b == 0x7C || b == 0x7D {
      return nil
    }
    if let hash = rest.firstIndex(of: "#") {
      c._fragment = String(rest[rest.index(after: hash)...])
      rest = rest[..<hash]
    }
    if let q = rest.firstIndex(of: "?") {
      c._query = String(rest[rest.index(after: q)...])
      rest = rest[..<q]
    }
    // scheme: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) ":"
    if let colon = rest.firstIndex(of: ":") {
      let candidate = rest[..<colon]
      if let first = candidate.first, first.isLetter,
         candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }) {
        c._scheme = String(candidate)
        rest = rest[rest.index(after: colon)...]
      }
    }
    if rest.hasPrefix("//") {
      rest = rest.dropFirst(2)
      let end = rest.firstIndex(of: "/") ?? rest.endIndex
      var authority = rest[..<end]
      rest = rest[end...]
      if let at = authority.lastIndex(of: "@") {
        let userinfo = authority[..<at]
        authority = authority[authority.index(after: at)...]
        if let colon = userinfo.firstIndex(of: ":") {
          c._user = String(userinfo[..<colon])
          c._password = String(userinfo[userinfo.index(after: colon)...])
        } else {
          c._user = String(userinfo)
        }
      }
      // host, possibly a bracketed IPv6 literal, then :port
      var hostPart = authority
      if authority.hasPrefix("["), let close = authority.firstIndex(of: "]") {
        hostPart = authority[...close]
        let after = authority[authority.index(after: close)...]
        if after.hasPrefix(":") {
          let portText = after.dropFirst()
          if !portText.isEmpty {
            guard let p = Int(portText), p >= 0 else { return nil }
            c._port = p
          }
        }
      } else if let colon = authority.lastIndex(of: ":") {
        hostPart = authority[..<colon]
        let portText = authority[authority.index(after: colon)...]
        if !portText.isEmpty {
          guard let p = Int(portText), p >= 0 else { return nil }
          c._port = p
        }
      }
      c._host = String(hostPart)
    }
    c._path = String(rest)
    return c
  }

  // MARK: decoded parts

  public var scheme: String? {
    get { return _scheme }
    set { _scheme = newValue }
  }
  public var user: String? {
    get { return _user?.removingPercentEncoding }
    set { _user = newValue?.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) }
  }
  public var password: String? {
    get { return _password?.removingPercentEncoding }
    set { _password = newValue?.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) }
  }
  public var host: String? {
    get { return _host?.removingPercentEncoding }
    set { _host = newValue?.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) }
  }
  public var port: Int? {
    get { return _port }
    set { _port = newValue }
  }
  public var path: String {
    get { return _path.removingPercentEncoding ?? _path }
    set { _path = newValue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? newValue }
  }
  public var query: String? {
    get { return _query?.removingPercentEncoding }
    set { _query = newValue?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) }
  }
  public var fragment: String? {
    get { return _fragment?.removingPercentEncoding }
    set { _fragment = newValue?.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) }
  }

  // MARK: percent-encoded parts

  public var percentEncodedUser: String? {
    get { return _user }
    set { _user = newValue }
  }
  public var percentEncodedPassword: String? {
    get { return _password }
    set { _password = newValue }
  }
  public var percentEncodedHost: String? {
    get { return _host }
    set { _host = newValue }
  }
  public var encodedHost: String? {
    get { return _host }
    set { _host = newValue }
  }
  public var percentEncodedPath: String {
    get { return _path }
    set { _path = newValue }
  }
  public var percentEncodedQuery: String? {
    get { return _query }
    set { _query = newValue }
  }
  public var percentEncodedFragment: String? {
    get { return _fragment }
    set { _fragment = newValue }
  }

  // MARK: query items

  /// Characters a query item's name or value must encode (on top of the
  /// query's own rules): the item separators.
  internal static let _queryItemAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))

  public var queryItems: [URLQueryItem]? {
    get {
      guard let q = _query else { return nil }
      if q.isEmpty { return [] }
      return q.split(separator: "&", omittingEmptySubsequences: false).map { pair in
        if let eq = pair.firstIndex(of: "=") {
          let name = String(pair[..<eq]), value = String(pair[pair.index(after: eq)...])
          return URLQueryItem(name: name.removingPercentEncoding ?? name, value: value.removingPercentEncoding ?? value)
        }
        let name = String(pair)
        return URLQueryItem(name: name.removingPercentEncoding ?? name, value: nil)
      }
    }
    set {
      guard let items = newValue else { _query = nil; return }
      _query = items.map { item -> String in
        let n = item.name.addingPercentEncoding(withAllowedCharacters: URLComponents._queryItemAllowed) ?? item.name
        guard let v = item.value else { return n }
        return n + "=" + (v.addingPercentEncoding(withAllowedCharacters: URLComponents._queryItemAllowed) ?? v)
      }.joined(separator: "&")
    }
  }
  public var percentEncodedQueryItems: [URLQueryItem]? {
    get {
      guard let q = _query else { return nil }
      return q.split(separator: "&").map { pair in
        if let eq = pair.firstIndex(of: "=") {
          return URLQueryItem(name: String(pair[..<eq]), value: String(pair[pair.index(after: eq)...]))
        }
        return URLQueryItem(name: String(pair), value: nil)
      }
    }
    set { _query = newValue?.map { item in item.value.map { "\(item.name)=\($0)" } ?? item.name }.joined(separator: "&") }
  }

  // MARK: assembling

  public var string: String? {
    var out = ""
    if let s = _scheme { out += s + ":" }
    if _host != nil || _user != nil || _password != nil || _port != nil {
      out += "//"
      if let u = _user {
        out += u
        if let p = _password { out += ":" + p }
        out += "@"
      }
      out += _host ?? ""
      if let p = _port { out += ":\(p)" }
      // A path after an authority must start with "/".
      if !_path.isEmpty && !_path.hasPrefix("/") { return nil }
    }
    out += _path
    if let q = _query { out += "?" + q }
    if let f = _fragment { out += "#" + f }
    return out
  }
  public var url: URL? { return string.flatMap { URL(string: $0) } }
  public func url(relativeTo base: URL?) -> URL? {
    guard let s = string else { return nil }
    return URL(string: s, relativeTo: base)
  }

  public var description: String { return string ?? "" }
}
