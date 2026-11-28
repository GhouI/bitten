// JSONEncoder and JSONDecoder: Codable values to and from JSON text. Values
// pass through a small tree (_JSONValue); numbers keep their text so
// integers round-trip exactly.

internal enum _JSONValue {
  case null
  case bool(Bool)
  case number(String)
  case string(String)
  case array([_JSONValue])
  case object([(String, _JSONValue)])

  internal var debugKind: String {
    switch self {
    case .null: return "null"
    case .bool: return "bool"
    case .number: return "number"
    case .string: return "string"
    case .array: return "array"
    case .object: return "dictionary"
    }
  }
}

/// A coding key made from a string or an index.
internal struct _JSONKey: CodingKey {
  var stringValue: String
  var intValue: Int?
  init(stringValue: String) { self.stringValue = stringValue; intValue = nil }
  init(intValue: Int) { stringValue = "Index \(intValue)"; self.intValue = intValue }
  init(index: Int) { self.init(intValue: index) }
  static let `super` = _JSONKey(stringValue: "super")
}

/// [CodingUserInfoKey: any Sendable] as [CodingUserInfoKey: Any], built
/// entry by entry.
internal func _anyUserInfo(_ info: [CodingUserInfoKey: any Sendable]) -> [CodingUserInfoKey: Any] {
  var out: [CodingUserInfoKey: Any] = [:]
  for (k, v) in info { out[k] = v as Any }
  return out
}

// MARK: - key conversion

internal func _convertToSnakeCase(_ key: String) -> String {
  if key.isEmpty { return key }
  var out = ""
  var previousWasLowerOrDigit = false
  let chars = Array(key)
  for (i, c) in chars.enumerated() {
    let isUpper = c.isUppercaseASCIILetter
    if isUpper {
      let nextIsLower = i + 1 < chars.count && chars[i + 1].isLowercaseASCIILetter
      if i > 0 && (previousWasLowerOrDigit || (nextIsLower && out.last != "_")) { out.append("_") }
      out += c.lowercased()
    } else {
      out.append(c)
    }
    previousWasLowerOrDigit = !isUpper && c != "_"
  }
  return out
}

internal func _convertFromSnakeCase(_ key: String) -> String {
  if key.isEmpty { return key }
  let chars = Array(key)
  var lead = 0
  while lead < chars.count && chars[lead] == "_" { lead += 1 }
  if lead == chars.count { return key }
  var trail = chars.count
  while trail > lead && chars[trail - 1] == "_" { trail -= 1 }
  let words = String(chars[lead..<trail]).split(separator: "_", omittingEmptySubsequences: true)
  if words.count <= 1 { return key }
  var out = String(chars[0..<lead]) + String(words[0])
  for w in words.dropFirst() {
    out += w.prefix(1).uppercased() + w.dropFirst().lowercased()
  }
  return out + String(chars[trail..<chars.count])
}

extension Character {
  internal var isUppercaseASCIILetter: Bool { return asciiValue.map { $0 >= 65 && $0 <= 90 } ?? false }
  internal var isLowercaseASCIILetter: Bool { return asciiValue.map { $0 >= 97 && $0 <= 122 } ?? false }
}

// MARK: - ISO 8601 (used by the .iso8601 strategies)

internal func _iso8601String(_ date: Date) -> String {
  var t = time_t(date.timeIntervalSince1970.rounded(.down))
  var p = tm()
  gmtime_r(&t, &p)
  func pad(_ v: Int32, _ w: Int) -> String {
    let s = String(v)
    return String(repeating: "0", count: Swift.max(0, w - s.count)) + s
  }
  return "\(pad(p.tm_year + 1900, 4))-\(pad(p.tm_mon + 1, 2))-\(pad(p.tm_mday, 2))T"
    + "\(pad(p.tm_hour, 2)):\(pad(p.tm_min, 2)):\(pad(p.tm_sec, 2))Z"
}

/// Parses "YYYY-MM-DDTHH:MM:SS[.fff](Z|±HH:MM|±HHMM)".
internal func _iso8601Date(_ s: String) -> Date? {
  let b = Array(s.utf8)
  var i = 0
  func num(_ n: Int) -> Int? {
    guard i + n <= b.count else { return nil }
    var v = 0
    for k in 0..<n {
      let c = b[i + k]
      guard c >= 48 && c <= 57 else { return nil }
      v = v * 10 + Int(c - 48)
    }
    i += n
    return v
  }
  func expect(_ c: UInt8) -> Bool {
    guard i < b.count && b[i] == c else { return false }
    i += 1
    return true
  }
  guard let year = num(4), expect(45), let month = num(2), expect(45), let day = num(2) else { return nil }
  guard i < b.count, b[i] == 84 || b[i] == 116 || b[i] == 32 else { return nil }
  i += 1
  guard let hour = num(2), expect(58), let minute = num(2), expect(58), let second = num(2) else { return nil }
  var fraction = 0.0
  if i < b.count && (b[i] == 46 || b[i] == 44) {
    i += 1
    var scale = 0.1
    while i < b.count && b[i] >= 48 && b[i] <= 57 {
      fraction += Double(b[i] - 48) * scale
      scale /= 10
      i += 1
    }
  }
  var offset = 0
  if i < b.count {
    if b[i] == 90 || b[i] == 122 {
      i += 1
    } else if b[i] == 43 || b[i] == 45 {
      let sign = b[i] == 45 ? -1 : 1
      i += 1
      guard let oh = num(2) else { return nil }
      _ = expect(58)
      let om = num(2) ?? 0
      offset = sign * (oh * 3600 + om * 60)
    } else {
      return nil
    }
  }
  if i != b.count { return nil }
  var p = tm()
  p.tm_year = Int32(year - 1900)
  p.tm_mon = Int32(month - 1)
  p.tm_mday = Int32(day)
  p.tm_hour = Int32(hour)
  p.tm_min = Int32(minute)
  p.tm_sec = Int32(second)
  let t = timegm(&p)
  return Date(timeIntervalSince1970: Double(t) - Double(offset) + fraction)
}

// MARK: - JSONEncoder

open class JSONEncoder {
  public struct OutputFormatting: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let prettyPrinted = OutputFormatting(rawValue: 1 << 0)
    public static let sortedKeys = OutputFormatting(rawValue: 1 << 1)
    public static let withoutEscapingSlashes = OutputFormatting(rawValue: 1 << 3)
  }

  public enum DateEncodingStrategy: @unchecked Sendable {
    case deferredToDate
    case secondsSince1970
    case millisecondsSince1970
    case iso8601
    case custom((Date, any Encoder) throws -> Void)
  }

  public enum DataEncodingStrategy: @unchecked Sendable {
    case deferredToData
    case base64
    case custom((Data, any Encoder) throws -> Void)
  }

  public enum NonConformingFloatEncodingStrategy: Sendable {
    case `throw`
    case convertToString(positiveInfinity: String, negativeInfinity: String, nan: String)
  }

  public enum KeyEncodingStrategy: @unchecked Sendable {
    case useDefaultKeys
    case convertToSnakeCase
    case custom((_ codingPath: [any CodingKey]) -> any CodingKey)
  }

  open var outputFormatting: OutputFormatting = []
  open var dateEncodingStrategy: DateEncodingStrategy = .deferredToDate
  open var dataEncodingStrategy: DataEncodingStrategy = .base64
  open var nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy = .throw
  open var keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys
  open var userInfo: [CodingUserInfoKey: any Sendable] = [:]

  public init() {}

  open func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = _JSONEncoderImpl(options: self, codingPath: [])
    let tree = try encoder.box(value)
    var out: [UInt8] = []
    _writeJSON(tree, into: &out, options: outputFormatting, indent: 0)
    if _jsonDebug { _jsonLog("encode \(T.self) to \(out.count) bytes") }
    return Data(out)
  }
}

/// Mutable tree nodes while encoding (containers write into them later).
internal final class _JSONNode {
  enum Kind { case value(_JSONValue), array([_JSONNode]), object([(String, _JSONNode)]), unset }
  var kind: Kind = .unset
  init() {}
  init(_ v: _JSONValue) { kind = .value(v) }

  var resolved: _JSONValue {
    switch kind {
    case .value(let v): return v
    case .array(let a): return .array(a.map { $0.resolved })
    case .object(let o): return .object(o.map { ($0.0, $0.1.resolved) })
    case .unset: return .object([])
    }
  }
  /// Where each key is, once an object has many (a dictionary encoded
  /// with its keys): a repeated key replaces its value, and looking for it
  /// shouldn't be a walk through all the others.
  private var index: [String: Int]?
  func set(_ key: String, _ node: _JSONNode) {
    guard case .object(var o) = kind else {
      kind = .object([(key, node)])
      index = nil
      return
    }
    // The enum lets go of the array first, so it grows in place instead of
    // being copied for every member.
    kind = .unset
    // (an index left from before kind was reset elsewhere doesn't match)
    if let idx = index, idx.count == o.count {
      if let i = idx[key] { o[i].1 = node } else { index![key] = o.count; o.append((key, node)) }
    } else if let i = o.firstIndex(where: { $0.0 == key }) {
      o[i].1 = node
    } else {
      o.append((key, node))
      if o.count > 16 {
        var idx: [String: Int] = [:]
        for (k, (name, _)) in o.enumerated() { idx[name] = k }
        index = idx
      }
    }
    kind = .object(o)
  }
  func append(_ node: _JSONNode) {
    guard case .array(var a) = kind else { kind = .array([node]); return }
    kind = .unset
    a.append(node)
    kind = .array(a)
  }
  var arrayCount: Int { if case .array(let a) = kind { return a.count } else { return 0 } }
}

internal final class _JSONEncoderImpl: Encoder {
  let options: JSONEncoder
  /// Where this value is: a path set outright, or its parent and key (the
  /// path made only when asked for: encoding builds no arrays on the way).
  private var stored: [any CodingKey]?
  private let parent: _JSONEncoderImpl?
  private let parentKey: (any CodingKey)?
  var codingPath: [any CodingKey] {
    get {
      if let s = stored { return s }
      guard let p = parent else { return [] }
      return parentKey.map { p.codingPath + [$0] } ?? p.codingPath
    }
    set { stored = newValue }
  }
  var userInfo: [CodingUserInfoKey: Any] { return _anyUserInfo(options.userInfo) }
  let node = _JSONNode()

  init(options: JSONEncoder, codingPath: [any CodingKey]) {
    self.options = options
    self.stored = codingPath
    self.parent = nil
    self.parentKey = nil
  }
  init(options: JSONEncoder, parent: _JSONEncoderImpl, key: (any CodingKey)?) {
    self.options = options
    self.stored = nil
    self.parent = parent
    self.parentKey = key
  }

  func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    if case .unset = node.kind { node.kind = .object([]) }
    return KeyedEncodingContainer(_JSONKeyedEncoder<Key>(encoder: self, node: node, explicitPath: nil))
  }
  func unkeyedContainer() -> any UnkeyedEncodingContainer {
    if case .unset = node.kind { node.kind = .array([]) }
    return _JSONUnkeyedEncoder(encoder: self, node: node, explicitPath: nil)
  }
  func singleValueContainer() -> any SingleValueEncodingContainer {
    return _JSONSingleEncoder(encoder: self)
  }

  func boxDouble(_ d: Double) throws -> _JSONValue {
    if d.isNaN || d.isInfinite {
      guard case let .convertToString(pos, neg, nan) = options.nonConformingFloatEncodingStrategy else {
        throw EncodingError.invalidValue(d, EncodingError.Context(codingPath: codingPath,
          debugDescription: "Unable to encode Double.\(d) directly in JSON."))
      }
      return .string(d.isNaN ? nan : d > 0 ? pos : neg)
    }
    var s = d.description
    if s.hasSuffix(".0") { s.removeLast(2) }
    return .number(s)
  }
  /// A Float written with its own shortest digits (0.1, not the Double
  /// 0.10000000149011612 it widens to).
  func boxFloat(_ f: Float) throws -> _JSONValue {
    if f.isNaN || f.isInfinite { return try boxDouble(Double(f)) }
    var s = f.description
    if s.hasSuffix(".0") { s.removeLast(2) }
    return .number(s)
  }

  /// Encodes any value into a tree, applying the date and data strategies.
  func box<T: Encodable>(_ value: T, at key: (any CodingKey)? = nil) throws -> _JSONValue {
    // Plain values (most of them) by their type: no casts, no encoder.
    if T.self == String.self { return .string(unsafeBitCast(value, to: String.self)) }
    if T.self == Int.self { return .number(String(unsafeBitCast(value, to: Int.self))) }
    if T.self == Bool.self { return .bool(unsafeBitCast(value, to: Bool.self)) }
    if T.self == Double.self { return try boxDouble(unsafeBitCast(value, to: Double.self)) }
    if T.self == Float.self { return try boxFloat(unsafeBitCast(value, to: Float.self)) }
    if T.self == Int64.self { return .number(String(unsafeBitCast(value, to: Int64.self))) }
    if T.self == Int32.self { return .number(String(unsafeBitCast(value, to: Int32.self))) }
    if T.self == UInt.self { return .number(String(unsafeBitCast(value, to: UInt.self))) }
    if T.self == UInt64.self { return .number(String(unsafeBitCast(value, to: UInt64.self))) }
    func path() -> [any CodingKey] { return key.map { codingPath + [$0] } ?? codingPath }
    if T.self == Date.self || T.self == NSDate.self, let date = value as? Date {
      switch options.dateEncodingStrategy {
      case .deferredToDate: break
      case .secondsSince1970: return try boxDouble(date.timeIntervalSince1970)
      case .millisecondsSince1970: return try boxDouble(date.timeIntervalSince1970 * 1000)
      case .iso8601: return .string(_iso8601String(date))
      case .custom(let f):
        let sub = _JSONEncoderImpl(options: options, codingPath: path())
        try f(date, sub)
        return sub.node.resolved
      }
    } else if T.self == Data.self || T.self == NSData.self, let data = value as? Data {
      switch options.dataEncodingStrategy {
      case .deferredToData: break
      case .base64: return .string(data.base64EncodedString())
      case .custom(let f):
        let sub = _JSONEncoderImpl(options: options, codingPath: path())
        try f(data, sub)
        return sub.node.resolved
      }
    } else if T.self == URL.self || T.self == NSURL.self, let url = value as? URL {
      return .string(url.absoluteString)
    }
    let sub = _JSONEncoderImpl(options: options, parent: self, key: key)
    try value.encode(to: sub)
    if case .unset = sub.node.kind {
      // Apple encodes a value that encoded nothing as an empty object.
      return .object([])
    }
    return sub.node.resolved
  }

  func key(_ k: any CodingKey) -> String {
    switch options.keyEncodingStrategy {
    case .useDefaultKeys: return k.stringValue
    case .convertToSnakeCase: return _convertToSnakeCase(k.stringValue)
    case .custom(let f): return f(codingPath + [k]).stringValue
    }
  }
}

internal struct _JSONKeyedEncoder<Key: CodingKey>: KeyedEncodingContainerProtocol {
  let encoder: _JSONEncoderImpl
  let node: _JSONNode
  /// A nested container's own path; nil: its encoder's.
  let explicitPath: [any CodingKey]?
  var codingPath: [any CodingKey] { return explicitPath ?? encoder.codingPath }

  mutating func encodeNil(forKey key: Key) throws { node.set(encoder.key(key), _JSONNode(.null)) }
  mutating func encode(_ value: Bool, forKey key: Key) throws { node.set(encoder.key(key), _JSONNode(.bool(value))) }
  mutating func encode(_ value: String, forKey key: Key) throws { node.set(encoder.key(key), _JSONNode(.string(value))) }
  mutating func encode(_ value: Double, forKey key: Key) throws { node.set(encoder.key(key), _JSONNode(try encoder.boxDouble(value))) }
  mutating func encode(_ value: Float, forKey key: Key) throws { node.set(encoder.key(key), _JSONNode(try encoder.boxFloat(value))) }
  mutating func encode(_ value: Int, forKey key: Key) throws { node.set(encoder.key(key), _JSONNode(.number(String(value)))) }
  mutating func encode(_ value: Int8, forKey key: Key) throws { node.set(encoder.key(key), _JSONNode(.number(String(value)))) }
  mutating func encode(_ value: Int16, forKey key: Key) throws { node.set(encoder.key(key), _JSONNode(.number(String(value)))) }
  mutating func encode(_ value: Int32, forKey key: Key) throws { node.set(encoder.key(key), _JSONNode(.number(String(value)))) }
  mutating func encode(_ value: Int64, forKey key: Key) throws { node.set(encoder.key(key), _JSONNode(.number(String(value)))) }
  mutating func encode(_ value: UInt, forKey key: Key) throws { node.set(encoder.key(key), _JSONNode(.number(String(value)))) }
  mutating func encode(_ value: UInt8, forKey key: Key) throws { node.set(encoder.key(key), _JSONNode(.number(String(value)))) }
  mutating func encode(_ value: UInt16, forKey key: Key) throws { node.set(encoder.key(key), _JSONNode(.number(String(value)))) }
  mutating func encode(_ value: UInt32, forKey key: Key) throws { node.set(encoder.key(key), _JSONNode(.number(String(value)))) }
  mutating func encode(_ value: UInt64, forKey key: Key) throws { node.set(encoder.key(key), _JSONNode(.number(String(value)))) }
  mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
    guard let p = explicitPath else {
      node.set(encoder.key(key), _JSONNode(try encoder.box(value, at: key)))
      return
    }
    let saved = encoder.codingPath
    encoder.codingPath = p
    defer { encoder.codingPath = saved }
    node.set(encoder.key(key), _JSONNode(try encoder.box(value, at: key)))
  }
  mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
    let child = _JSONNode()
    child.kind = .object([])
    node.set(encoder.key(key), child)
    return KeyedEncodingContainer(_JSONKeyedEncoder<NestedKey>(encoder: encoder, node: child, explicitPath: codingPath + [key]))
  }
  mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
    let child = _JSONNode()
    child.kind = .array([])
    node.set(encoder.key(key), child)
    return _JSONUnkeyedEncoder(encoder: encoder, node: child, explicitPath: codingPath + [key])
  }
  mutating func superEncoder() -> any Encoder { return _JSONReferencingEncoder(parent: encoder, node: node, key: _JSONKey.super.stringValue, codingPath: codingPath + [_JSONKey.super]) }
  mutating func superEncoder(forKey key: Key) -> any Encoder {
    return _JSONReferencingEncoder(parent: encoder, node: node, key: encoder.key(key), codingPath: codingPath + [key])
  }
}

internal struct _JSONUnkeyedEncoder: UnkeyedEncodingContainer {
  let encoder: _JSONEncoderImpl
  let node: _JSONNode
  let explicitPath: [any CodingKey]?
  var codingPath: [any CodingKey] { return explicitPath ?? encoder.codingPath }
  var count: Int { return node.arrayCount }

  mutating func encodeNil() throws { node.append(_JSONNode(.null)) }
  mutating func encode(_ value: Bool) throws { node.append(_JSONNode(.bool(value))) }
  mutating func encode(_ value: String) throws { node.append(_JSONNode(.string(value))) }
  mutating func encode(_ value: Double) throws { node.append(_JSONNode(try encoder.boxDouble(value))) }
  mutating func encode(_ value: Float) throws { node.append(_JSONNode(try encoder.boxFloat(value))) }
  mutating func encode(_ value: Int) throws { node.append(_JSONNode(.number(String(value)))) }
  mutating func encode(_ value: Int8) throws { node.append(_JSONNode(.number(String(value)))) }
  mutating func encode(_ value: Int16) throws { node.append(_JSONNode(.number(String(value)))) }
  mutating func encode(_ value: Int32) throws { node.append(_JSONNode(.number(String(value)))) }
  mutating func encode(_ value: Int64) throws { node.append(_JSONNode(.number(String(value)))) }
  mutating func encode(_ value: UInt) throws { node.append(_JSONNode(.number(String(value)))) }
  mutating func encode(_ value: UInt8) throws { node.append(_JSONNode(.number(String(value)))) }
  mutating func encode(_ value: UInt16) throws { node.append(_JSONNode(.number(String(value)))) }
  mutating func encode(_ value: UInt32) throws { node.append(_JSONNode(.number(String(value)))) }
  mutating func encode(_ value: UInt64) throws { node.append(_JSONNode(.number(String(value)))) }
  mutating func encode<T: Encodable>(_ value: T) throws {
    guard let p = explicitPath else {
      node.append(_JSONNode(try encoder.box(value, at: _JSONKey(index: count))))
      return
    }
    let saved = encoder.codingPath
    encoder.codingPath = p
    defer { encoder.codingPath = saved }
    node.append(_JSONNode(try encoder.box(value, at: _JSONKey(index: count))))
  }
  mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
    let child = _JSONNode()
    child.kind = .object([])
    let key = _JSONKey(index: count)
    node.append(child)
    return KeyedEncodingContainer(_JSONKeyedEncoder<NestedKey>(encoder: encoder, node: child, explicitPath: codingPath + [key]))
  }
  mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
    let child = _JSONNode()
    child.kind = .array([])
    let key = _JSONKey(index: count)
    node.append(child)
    return _JSONUnkeyedEncoder(encoder: encoder, node: child, explicitPath: codingPath + [key])
  }
  mutating func superEncoder() -> any Encoder {
    let child = _JSONNode()
    let key = _JSONKey(index: count)
    node.append(child)
    let sub = _JSONEncoderImpl(options: encoder.options, codingPath: codingPath + [key])
    return _JSONNodeEncoder(inner: sub, target: child)
  }
}

internal struct _JSONSingleEncoder: SingleValueEncodingContainer {
  let encoder: _JSONEncoderImpl
  var codingPath: [any CodingKey] { return encoder.codingPath }

  func put(_ v: _JSONValue) { encoder.node.kind = .value(v) }
  mutating func encodeNil() throws { put(.null) }
  mutating func encode(_ value: Bool) throws { put(.bool(value)) }
  mutating func encode(_ value: String) throws { put(.string(value)) }
  mutating func encode(_ value: Double) throws { put(try encoder.boxDouble(value)) }
  mutating func encode(_ value: Float) throws { put(try encoder.boxFloat(value)) }
  mutating func encode(_ value: Int) throws { put(.number(String(value))) }
  mutating func encode(_ value: Int8) throws { put(.number(String(value))) }
  mutating func encode(_ value: Int16) throws { put(.number(String(value))) }
  mutating func encode(_ value: Int32) throws { put(.number(String(value))) }
  mutating func encode(_ value: Int64) throws { put(.number(String(value))) }
  mutating func encode(_ value: UInt) throws { put(.number(String(value))) }
  mutating func encode(_ value: UInt8) throws { put(.number(String(value))) }
  mutating func encode(_ value: UInt16) throws { put(.number(String(value))) }
  mutating func encode(_ value: UInt32) throws { put(.number(String(value))) }
  mutating func encode(_ value: UInt64) throws { put(.number(String(value))) }
  mutating func encode<T: Encodable>(_ value: T) throws { put(try encoder.box(value)) }
}

/// An encoder whose result lands in a given node (for superEncoder).
internal final class _JSONNodeEncoder: Encoder {
  let inner: _JSONEncoderImpl
  let target: _JSONNode
  init(inner: _JSONEncoderImpl, target: _JSONNode) {
    self.inner = inner
    self.target = target
    target.kind = .unset
  }
  var codingPath: [any CodingKey] { return inner.codingPath }
  var userInfo: [CodingUserInfoKey: Any] { return inner.userInfo }
  func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    if case .unset = target.kind { target.kind = .object([]) }
    return KeyedEncodingContainer(_JSONKeyedEncoder<Key>(encoder: inner, node: target, explicitPath: codingPath))
  }
  func unkeyedContainer() -> any UnkeyedEncodingContainer {
    if case .unset = target.kind { target.kind = .array([]) }
    return _JSONUnkeyedEncoder(encoder: inner, node: target, explicitPath: codingPath)
  }
  func singleValueContainer() -> any SingleValueEncodingContainer {
    return _JSONNodeSingleEncoder(encoder: inner, target: target, codingPath: codingPath)
  }
}

internal struct _JSONNodeSingleEncoder: SingleValueEncodingContainer {
  let encoder: _JSONEncoderImpl
  let target: _JSONNode
  var codingPath: [any CodingKey]
  func put(_ v: _JSONValue) { target.kind = .value(v) }
  mutating func encodeNil() throws { put(.null) }
  mutating func encode(_ value: Bool) throws { put(.bool(value)) }
  mutating func encode(_ value: String) throws { put(.string(value)) }
  mutating func encode(_ value: Double) throws { put(try encoder.boxDouble(value)) }
  mutating func encode(_ value: Float) throws { put(try encoder.boxFloat(value)) }
  mutating func encode(_ value: Int) throws { put(.number(String(value))) }
  mutating func encode(_ value: Int8) throws { put(.number(String(value))) }
  mutating func encode(_ value: Int16) throws { put(.number(String(value))) }
  mutating func encode(_ value: Int32) throws { put(.number(String(value))) }
  mutating func encode(_ value: Int64) throws { put(.number(String(value))) }
  mutating func encode(_ value: UInt) throws { put(.number(String(value))) }
  mutating func encode(_ value: UInt8) throws { put(.number(String(value))) }
  mutating func encode(_ value: UInt16) throws { put(.number(String(value))) }
  mutating func encode(_ value: UInt32) throws { put(.number(String(value))) }
  mutating func encode(_ value: UInt64) throws { put(.number(String(value))) }
  mutating func encode<T: Encodable>(_ value: T) throws { put(try encoder.box(value)) }
}

/// superEncoder(forKey:) of a keyed container: writes into that key.
internal func _JSONReferencingEncoder(parent: _JSONEncoderImpl, node: _JSONNode, key: String,
                                      codingPath: [any CodingKey]) -> any Encoder {
  let child = _JSONNode()
  node.set(key, child)
  let sub = _JSONEncoderImpl(options: parent.options, codingPath: codingPath)
  return _JSONNodeEncoder(inner: sub, target: child)
}

// MARK: - writing

internal func _writeJSONString(_ s: String, into out: inout [UInt8], escapeSlashes: Bool) {
  out.append(34)
  let hex: [UInt8] = Array("0123456789abcdef".utf8)
  for b in s.utf8 {
    switch b {
    case 34: out.append(92); out.append(34)
    case 92: out.append(92); out.append(92)
    case 47: if escapeSlashes { out.append(92) }; out.append(47)
    case 10: out.append(92); out.append(110)
    case 13: out.append(92); out.append(114)
    case 9: out.append(92); out.append(116)
    case 8: out.append(92); out.append(98)
    case 12: out.append(92); out.append(102)
    case 0..<32:
      out.append(contentsOf: [92, 117, 48, 48])
      out.append(hex[Int(b >> 4)])
      out.append(hex[Int(b & 15)])
    default: out.append(b)
    }
  }
  out.append(34)
}

internal func _writeJSON(_ v: _JSONValue, into out: inout [UInt8], options: JSONEncoder.OutputFormatting, indent: Int) {
  let pretty = options.contains(.prettyPrinted)
  let escapeSlashes = !options.contains(.withoutEscapingSlashes)
  func newline(_ level: Int) {
    out.append(10)
    for _ in 0..<(level * 2) { out.append(32) }
  }
  switch v {
  case .null: out.append(contentsOf: Array("null".utf8))
  case .bool(let b): out.append(contentsOf: Array((b ? "true" : "false").utf8))
  case .number(let n): out.append(contentsOf: Array(n.utf8))
  case .string(let s): _writeJSONString(s, into: &out, escapeSlashes: escapeSlashes)
  case .array(let items):
    out.append(91)
    if items.isEmpty { out.append(93); return }
    for (i, item) in items.enumerated() {
      if i > 0 { out.append(44) }
      if pretty { newline(indent + 1) }
      _writeJSON(item, into: &out, options: options, indent: indent + 1)
    }
    if pretty { newline(indent) }
    out.append(93)
  case .object(var members):
    out.append(123)
    if members.isEmpty { out.append(125); return }
    if options.contains(.sortedKeys) { members.sort { $0.0 < $1.0 } }
    for (i, (k, item)) in members.enumerated() {
      if i > 0 { out.append(44) }
      if pretty { newline(indent + 1) }
      _writeJSONString(k, into: &out, escapeSlashes: escapeSlashes)
      if pretty { out.append(contentsOf: [32, 58, 32]) } else { out.append(58) }
      _writeJSON(item, into: &out, options: options, indent: indent + 1)
    }
    if pretty { newline(indent) }
    out.append(125)
  }
}

// MARK: - parsing

/// BITTEN_JSON_DEBUG: each decode and encode, with its type and size.
internal let _jsonDebug = _bitten_json_getenv("BITTEN_JSON_DEBUG") != nil
@_silgen_name("getenv") internal func _bitten_json_getenv(_ name: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
@_silgen_name("write") internal func _bitten_json_write(_ fd: Int32, _ p: UnsafeRawPointer?, _ n: Int) -> Int
internal func _jsonLog(_ s: String) {
  let line = "bitten: json " + s + "\n"
  var copy = line
  copy.withUTF8 { _ = _bitten_json_write(2, $0.baseAddress, $0.count) }
}

internal struct _JSONParser {
  let bytes: [UInt8]
  var i = 0
  init(_ bytes: [UInt8]) { self.bytes = bytes }

  struct Failure: Error { let message: String }

  mutating func skipSpace() {
    while i < bytes.count, bytes[i] == 32 || bytes[i] == 9 || bytes[i] == 10 || bytes[i] == 13 { i += 1 }
  }

  mutating func parseDocument() throws -> _JSONValue {
    // A UTF-8 byte order mark is allowed.
    if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF { i = 3 }
    skipSpace()
    let v = try parseValue(depth: 0)
    skipSpace()
    if i != bytes.count { throw Failure(message: "Garbage at end around character \(i).") }
    return v
  }

  mutating func literal(_ word: String, _ v: _JSONValue) throws -> _JSONValue {
    let w = Array(word.utf8)
    guard i + w.count <= bytes.count, Array(bytes[i..<(i + w.count)]) == w else {
      throw Failure(message: "Invalid value around character \(i).")
    }
    i += w.count
    return v
  }

  mutating func parseValue(depth: Int) throws -> _JSONValue {
    guard depth < 512 else { throw Failure(message: "Too many nested arrays or dictionaries.") }
    guard i < bytes.count else { throw Failure(message: "Unexpected end of file.") }
    switch bytes[i] {
    case 110: return try literal("null", .null)
    case 116: return try literal("true", .bool(true))
    case 102: return try literal("false", .bool(false))
    case 34: return .string(try parseString())
    case 91:
      i += 1
      var items: [_JSONValue] = []
      skipSpace()
      if i < bytes.count && bytes[i] == 93 { i += 1; return .array(items) }
      while true {
        skipSpace()
        items.append(try parseValue(depth: depth + 1))
        skipSpace()
        guard i < bytes.count else { throw Failure(message: "Unexpected end of file in array.") }
        if bytes[i] == 44 { i += 1; continue }
        if bytes[i] == 93 { i += 1; return .array(items) }
        throw Failure(message: "Badly formed array around character \(i).")
      }
    case 123:
      i += 1
      var members: [(String, _JSONValue)] = []
      skipSpace()
      if i < bytes.count && bytes[i] == 125 { i += 1; return .object(members) }
      while true {
        skipSpace()
        guard i < bytes.count, bytes[i] == 34 else { throw Failure(message: "No string key in object around character \(i).") }
        let key = try parseString()
        skipSpace()
        guard i < bytes.count, bytes[i] == 58 else { throw Failure(message: "No value for key in object around character \(i).") }
        i += 1
        skipSpace()
        members.append((key, try parseValue(depth: depth + 1)))
        skipSpace()
        guard i < bytes.count else { throw Failure(message: "Unexpected end of file in object.") }
        if bytes[i] == 44 { i += 1; continue }
        if bytes[i] == 125 { i += 1; return .object(members) }
        throw Failure(message: "Badly formed object around character \(i).")
      }
    case 45, 48...57:
      let start = i
      if bytes[i] == 45 { i += 1 }
      var digits = 0
      while i < bytes.count, bytes[i] >= 48 && bytes[i] <= 57 { i += 1; digits += 1 }
      if digits == 0 { throw Failure(message: "Invalid number around character \(start).") }
      if i < bytes.count && bytes[i] == 46 {
        i += 1
        var frac = 0
        while i < bytes.count, bytes[i] >= 48 && bytes[i] <= 57 { i += 1; frac += 1 }
        if frac == 0 { throw Failure(message: "Invalid number around character \(start).") }
      }
      if i < bytes.count && (bytes[i] == 101 || bytes[i] == 69) {
        i += 1
        if i < bytes.count && (bytes[i] == 43 || bytes[i] == 45) { i += 1 }
        var exp = 0
        while i < bytes.count, bytes[i] >= 48 && bytes[i] <= 57 { i += 1; exp += 1 }
        if exp == 0 { throw Failure(message: "Invalid number around character \(start).") }
      }
      return .number(String(decoding: bytes[start..<i], as: UTF8.self))
    default:
      throw Failure(message: "Invalid value around character \(i).")
    }
  }

  mutating func hex4() throws -> UInt32 {
    guard i + 4 <= bytes.count else { throw Failure(message: "Invalid escape sequence around character \(i).") }
    var v: UInt32 = 0
    for _ in 0..<4 {
      let c = bytes[i]
      let d: UInt32
      switch c {
      case 48...57: d = UInt32(c - 48)
      case 65...70: d = UInt32(c - 55)
      case 97...102: d = UInt32(c - 87)
      default: throw Failure(message: "Invalid escape sequence around character \(i).")
      }
      v = v << 4 | d
      i += 1
    }
    return v
  }

  mutating func parseString() throws -> String {
    i += 1 // opening quote
    // Most strings have no escapes: decoded from the input in place.
    var j = i
    while j < bytes.count, bytes[j] != 34, bytes[j] != 92, bytes[j] >= 32 { j += 1 }
    if j < bytes.count, bytes[j] == 34 {
      let s = String(decoding: bytes[i..<j], as: UTF8.self)
      i = j + 1
      return s
    }
    var out: [UInt8] = []
    while true {
      guard i < bytes.count else { throw Failure(message: "Unterminated string.") }
      let c = bytes[i]
      if c == 34 { i += 1; break }
      if c < 32 { throw Failure(message: "Unescaped control character around character \(i).") }
      if c != 92 { out.append(c); i += 1; continue }
      i += 1
      guard i < bytes.count else { throw Failure(message: "Unterminated string.") }
      let e = bytes[i]
      i += 1
      switch e {
      case 34: out.append(34)
      case 92: out.append(92)
      case 47: out.append(47)
      case 98: out.append(8)
      case 102: out.append(12)
      case 110: out.append(10)
      case 114: out.append(13)
      case 116: out.append(9)
      case 117:
        var v = try hex4()
        if v >= 0xD800 && v < 0xDC00 {
          // A high surrogate must be followed by \u low surrogate.
          if i + 6 <= bytes.count && bytes[i] == 92 && bytes[i + 1] == 117 {
            i += 2
            let lo = try hex4()
            if lo >= 0xDC00 && lo < 0xE000 { v = 0x10000 + ((v - 0xD800) << 10) + (lo - 0xDC00) } else { v = 0xFFFD }
          } else {
            v = 0xFFFD
          }
        } else if v >= 0xDC00 && v < 0xE000 {
          v = 0xFFFD
        }
        out.append(contentsOf: String(Unicode.Scalar(v) ?? "\u{FFFD}").utf8)
      default:
        throw Failure(message: "Invalid escape sequence around character \(i - 1).")
      }
    }
    return String(decoding: out, as: UTF8.self)
  }
}

// MARK: - JSONDecoder

open class JSONDecoder {
  public enum DateDecodingStrategy: @unchecked Sendable {
    case deferredToDate
    case secondsSince1970
    case millisecondsSince1970
    case iso8601
    case custom((_ decoder: any Decoder) throws -> Date)
  }

  public enum DataDecodingStrategy: @unchecked Sendable {
    case deferredToData
    case base64
    case custom((_ decoder: any Decoder) throws -> Data)
  }

  public enum NonConformingFloatDecodingStrategy: Sendable {
    case `throw`
    case convertFromString(positiveInfinity: String, negativeInfinity: String, nan: String)
  }

  public enum KeyDecodingStrategy: @unchecked Sendable {
    case useDefaultKeys
    case convertFromSnakeCase
    case custom((_ codingPath: [any CodingKey]) -> any CodingKey)
  }

  open var dateDecodingStrategy: DateDecodingStrategy = .deferredToDate
  open var dataDecodingStrategy: DataDecodingStrategy = .base64
  open var nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy = .throw
  open var keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys
  open var userInfo: [CodingUserInfoKey: any Sendable] = [:]
  open var allowsJSON5: Bool = false
  open var assumesTopLevelDictionary: Bool = false

  public init() {}

  open func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    if _jsonDebug { _jsonLog("decode \(T.self) from \(data.count) bytes") }
    var parser = _JSONParser(Array(data))
    let tree: _JSONValue
    do {
      tree = try parser.parseDocument()
    } catch let f as _JSONParser.Failure {
      throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [],
        debugDescription: "The given data was not valid JSON.",
        underlyingError: _JSONParserError(message: f.message)))
    }
    let decoder = _JSONDecoderImpl(options: self, value: tree, codingPath: [])
    return try decoder.unbox(tree, as: T.self)
  }
}

internal struct _JSONParserError: Error { let message: String }

internal final class _JSONDecoderImpl: Decoder {
  let options: JSONDecoder
  let value: _JSONValue
  /// Where this value is: its parent and key, or a path given outright.
  /// The path is only made when asked for (errors, and programs that read
  /// it): decoding builds no arrays on the way down.
  private let parent: _JSONDecoderImpl?
  private let key: (any CodingKey)?
  private var given: [any CodingKey]
  /// Made once when first asked for (programs that try one type after
  /// another ask on every mismatch); a decoder's place never changes.
  private var madePath: [any CodingKey]?
  var codingPath: [any CodingKey] {
    if let m = madePath { return m }
    let made: [any CodingKey]
    if let p = parent {
      made = key.map { p.codingPath + [$0] } ?? p.codingPath
    } else {
      made = key.map { given + [$0] } ?? given
    }
    madePath = made
    return made
  }
  var userInfo: [CodingUserInfoKey: Any] { return _anyUserInfo(options.userInfo) }

  init(options: JSONDecoder, value: _JSONValue, codingPath: [any CodingKey]) {
    self.options = options
    self.value = value
    self.parent = nil
    self.key = nil
    self.given = codingPath
  }
  init(options: JSONDecoder, value: _JSONValue, parent: _JSONDecoderImpl, key: (any CodingKey)?) {
    self.options = options
    self.value = value
    self.parent = parent
    self.key = key
    self.given = []
  }

  func mismatch<T>(_ type: T.Type, _ v: _JSONValue, path: [any CodingKey]) -> DecodingError {
    if case .null = v {
      return DecodingError.valueNotFound(type, DecodingError.Context(codingPath: path,
        debugDescription: "Cannot get value of type \(type) -- found null value instead"))
    }
    return DecodingError.typeMismatch(type, DecodingError.Context(codingPath: path,
      debugDescription: "Expected to decode \(type) but found \(v.debugKind) instead."))
  }

  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    guard case .object(let members) = value else { throw mismatch([String: Any].self, value, path: codingPath) }
    var list = members
    switch options.keyDecodingStrategy {
    case .useDefaultKeys: break
    case .convertFromSnakeCase: list = members.map { (_convertFromSnakeCase($0.0), $0.1) }
    case .custom(let f): list = members.map { (f(codingPath + [_JSONKey(stringValue: $0.0)]).stringValue, $0.1) }
    }
    return KeyedDecodingContainer(_JSONKeyedDecoder<Key>(decoder: self, members: _JSONMembers(list)))
  }
  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    guard case .array(let items) = value else { throw mismatch([Any].self, value, path: codingPath) }
    return _JSONUnkeyedDecoder(decoder: self, items: items)
  }
  func singleValueContainer() throws -> any SingleValueDecodingContainer {
    return _JSONSingleDecoder(decoder: self, value: value)
  }

  // Primitive conversions.
  func unboxBool(_ v: _JSONValue, path: @autoclosure () -> [any CodingKey]) throws -> Bool {
    guard case .bool(let b) = v else { throw mismatch(Bool.self, v, path: path()) }
    return b
  }
  func unboxString(_ v: _JSONValue, path: @autoclosure () -> [any CodingKey]) throws -> String {
    guard case .string(let s) = v else { throw mismatch(String.self, v, path: path()) }
    return s
  }
  func unboxDouble(_ v: _JSONValue, path: @autoclosure () -> [any CodingKey]) throws -> Double {
    switch v {
    case .number(let n):
      guard let d = Double(n) else { throw mismatch(Double.self, v, path: path()) }
      return d
    case .string(let s):
      if case let .convertFromString(pos, neg, nan) = options.nonConformingFloatDecodingStrategy {
        if s == pos { return .infinity }
        if s == neg { return -.infinity }
        if s == nan { return .nan }
      }
      throw mismatch(Double.self, v, path: path())
    default:
      throw mismatch(Double.self, v, path: path())
    }
  }
  func unboxInteger<T: FixedWidthInteger>(_ v: _JSONValue, as type: T.Type, path: @autoclosure () -> [any CodingKey]) throws -> T {
    guard case .number(let n) = v else { throw mismatch(type, v, path: path()) }
    if let exact = T(n) { return exact }
    // "1.0" or "1e3": accept when the value is an exact integer in range.
    if let d = Double(n), d.rounded() == d, let x = T(exactly: d) { return x }
    throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: path(),
      debugDescription: "Parsed JSON number <\(n)> does not fit in \(type)."))
  }

  func unbox<T: Decodable>(_ v: _JSONValue, as type: T.Type, key: (any CodingKey)? = nil) throws -> T {
    func path() -> [any CodingKey] { return key.map { codingPath + [$0] } ?? codingPath }
    func child() -> _JSONDecoderImpl { return _JSONDecoderImpl(options: options, value: v, parent: self, key: key) }
    if type == Date.self {
      switch options.dateDecodingStrategy {
      case .deferredToDate: break
      case .secondsSince1970: return Date(timeIntervalSince1970: try unboxDouble(v, path: path())) as! T
      case .millisecondsSince1970: return Date(timeIntervalSince1970: try unboxDouble(v, path: path()) / 1000) as! T
      case .iso8601:
        let s = try unboxString(v, path: path())
        guard let d = _iso8601Date(s) else {
          throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: path(), debugDescription: "Expected date string to be ISO8601-formatted."))
        }
        return d as! T
      case .custom(let f):
        return try f(child()) as! T
      }
    } else if type == Data.self {
      switch options.dataDecodingStrategy {
      case .deferredToData: break
      case .base64:
        let s = try unboxString(v, path: path())
        guard let d = Data(base64Encoded: s) else {
          throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: path(), debugDescription: "Encountered Data is not valid Base64."))
        }
        return d as! T
      case .custom(let f):
        return try f(child()) as! T
      }
    } else if type == URL.self {
      let s = try unboxString(v, path: path())
      guard let u = URL(string: s) else {
        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: path(), debugDescription: "Invalid URL string."))
      }
      return u as! T
    }
    return try T(from: child())
  }
}

/// An object's members as decoding looks them up: in order (the first of
/// a repeated key wins), searched directly when there are few, through a
/// dictionary made once when there are many.
internal struct _JSONMembers {
  let list: [(String, _JSONValue)]
  let index: [String: _JSONValue]?
  init(_ list: [(String, _JSONValue)]) {
    self.list = list
    if list.count > 8 {
      var d: [String: _JSONValue] = [:]
      for (k, v) in list where d[k] == nil { d[k] = v }
      index = d
    } else {
      index = nil
    }
  }
  subscript(key: String) -> _JSONValue? {
    if let d = index { return d[key] }
    for (k, v) in list where k == key { return v }
    return nil
  }
  var keys: [String] {
    // a repeated key counts once (rare: checked directly when small)
    if index == nil {
      var out: [String] = []
      out.reserveCapacity(list.count)
      for (k, _) in list where !out.contains(k) { out.append(k) }
      return out
    }
    var seen = Set<String>(minimumCapacity: list.count)
    return list.compactMap { seen.insert($0.0).inserted ? $0.0 : nil }
  }
}

internal struct _JSONKeyedDecoder<Key: CodingKey>: KeyedDecodingContainerProtocol {
  let decoder: _JSONDecoderImpl
  let members: _JSONMembers
  var codingPath: [any CodingKey] { return decoder.codingPath }
  func path(_ key: any CodingKey) -> [any CodingKey] { return decoder.codingPath + [key] }

  var allKeys: [Key] { return members.keys.compactMap { Key(stringValue: $0) } }
  func contains(_ key: Key) -> Bool { return members[key.stringValue] != nil }

  func value(_ key: Key) throws -> _JSONValue {
    guard let v = members[key.stringValue] else {
      throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath,
        debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
    }
    return v
  }
  func decodeNil(forKey key: Key) throws -> Bool {
    if case .null = try value(key) { return true }
    return false
  }
  func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { return try decoder.unboxBool(try value(key), path: path(key)) }
  func decode(_ type: String.Type, forKey key: Key) throws -> String { return try decoder.unboxString(try value(key), path: path(key)) }
  func decode(_ type: Double.Type, forKey key: Key) throws -> Double { return try decoder.unboxDouble(try value(key), path: path(key)) }
  func decode(_ type: Float.Type, forKey key: Key) throws -> Float { return Float(try decoder.unboxDouble(try value(key), path: path(key))) }
  func decode(_ type: Int.Type, forKey key: Key) throws -> Int { return try decoder.unboxInteger(try value(key), as: type, path: path(key)) }
  func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { return try decoder.unboxInteger(try value(key), as: type, path: path(key)) }
  func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { return try decoder.unboxInteger(try value(key), as: type, path: path(key)) }
  func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { return try decoder.unboxInteger(try value(key), as: type, path: path(key)) }
  func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { return try decoder.unboxInteger(try value(key), as: type, path: path(key)) }
  func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { return try decoder.unboxInteger(try value(key), as: type, path: path(key)) }
  func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { return try decoder.unboxInteger(try value(key), as: type, path: path(key)) }
  func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { return try decoder.unboxInteger(try value(key), as: type, path: path(key)) }
  func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { return try decoder.unboxInteger(try value(key), as: type, path: path(key)) }
  func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { return try decoder.unboxInteger(try value(key), as: type, path: path(key)) }
  func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
    return try decoder.unbox(try value(key), as: type, key: key)
  }
  func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
    return try _JSONDecoderImpl(options: decoder.options, value: try value(key), parent: decoder, key: key).container(keyedBy: type)
  }
  func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
    return try _JSONDecoderImpl(options: decoder.options, value: try value(key), parent: decoder, key: key).unkeyedContainer()
  }
  func superDecoder() throws -> any Decoder {
    return _JSONDecoderImpl(options: decoder.options, value: members["super"] ?? .null, parent: decoder, key: _JSONKey.super)
  }
  func superDecoder(forKey key: Key) throws -> any Decoder {
    return _JSONDecoderImpl(options: decoder.options, value: members[key.stringValue] ?? .null, parent: decoder, key: key)
  }
}

internal struct _JSONUnkeyedDecoder: UnkeyedDecodingContainer {
  let decoder: _JSONDecoderImpl
  let items: [_JSONValue]
  var codingPath: [any CodingKey] { return decoder.codingPath }
  var currentIndex = 0
  func path(_ key: any CodingKey) -> [any CodingKey] { return decoder.codingPath + [key] }

  init(decoder: _JSONDecoderImpl, items: [_JSONValue]) {
    self.decoder = decoder
    self.items = items
  }

  var count: Int? { return items.count }
  var isAtEnd: Bool { return currentIndex >= items.count }

  mutating func next<T>(_ type: T.Type) throws -> (_JSONValue, _JSONKey) {
    guard !isAtEnd else {
      throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: path(_JSONKey(index: currentIndex)),
        debugDescription: "Unkeyed container is at end."))
    }
    let v = items[currentIndex]
    let key = _JSONKey(index: currentIndex)
    currentIndex += 1
    return (v, key)
  }

  mutating func decodeNil() throws -> Bool {
    guard !isAtEnd else { throw DecodingError.valueNotFound(Any?.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Unkeyed container is at end.")) }
    if case .null = items[currentIndex] { currentIndex += 1; return true }
    return false
  }
  mutating func decode(_ type: Bool.Type) throws -> Bool { let (v, k) = try next(type); return try decoder.unboxBool(v, path: path(k)) }
  mutating func decode(_ type: String.Type) throws -> String { let (v, k) = try next(type); return try decoder.unboxString(v, path: path(k)) }
  mutating func decode(_ type: Double.Type) throws -> Double { let (v, k) = try next(type); return try decoder.unboxDouble(v, path: path(k)) }
  mutating func decode(_ type: Float.Type) throws -> Float { let (v, k) = try next(type); return Float(try decoder.unboxDouble(v, path: path(k))) }
  mutating func decode(_ type: Int.Type) throws -> Int { let (v, k) = try next(type); return try decoder.unboxInteger(v, as: type, path: path(k)) }
  mutating func decode(_ type: Int8.Type) throws -> Int8 { let (v, k) = try next(type); return try decoder.unboxInteger(v, as: type, path: path(k)) }
  mutating func decode(_ type: Int16.Type) throws -> Int16 { let (v, k) = try next(type); return try decoder.unboxInteger(v, as: type, path: path(k)) }
  mutating func decode(_ type: Int32.Type) throws -> Int32 { let (v, k) = try next(type); return try decoder.unboxInteger(v, as: type, path: path(k)) }
  mutating func decode(_ type: Int64.Type) throws -> Int64 { let (v, k) = try next(type); return try decoder.unboxInteger(v, as: type, path: path(k)) }
  mutating func decode(_ type: UInt.Type) throws -> UInt { let (v, k) = try next(type); return try decoder.unboxInteger(v, as: type, path: path(k)) }
  mutating func decode(_ type: UInt8.Type) throws -> UInt8 { let (v, k) = try next(type); return try decoder.unboxInteger(v, as: type, path: path(k)) }
  mutating func decode(_ type: UInt16.Type) throws -> UInt16 { let (v, k) = try next(type); return try decoder.unboxInteger(v, as: type, path: path(k)) }
  mutating func decode(_ type: UInt32.Type) throws -> UInt32 { let (v, k) = try next(type); return try decoder.unboxInteger(v, as: type, path: path(k)) }
  mutating func decode(_ type: UInt64.Type) throws -> UInt64 { let (v, k) = try next(type); return try decoder.unboxInteger(v, as: type, path: path(k)) }
  mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
    let (v, k) = try next(type)
    return try decoder.unbox(v, as: type, key: k)
  }
  mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
    let (v, k) = try next(type)
    return try _JSONDecoderImpl(options: decoder.options, value: v, parent: decoder, key: k).container(keyedBy: type)
  }
  mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
    let (v, k) = try next([Any].self)
    return try _JSONDecoderImpl(options: decoder.options, value: v, parent: decoder, key: k).unkeyedContainer()
  }
  mutating func superDecoder() throws -> any Decoder {
    let (v, k) = try next(Any.self)
    return _JSONDecoderImpl(options: decoder.options, value: v, parent: decoder, key: k)
  }
}

internal struct _JSONSingleDecoder: SingleValueDecodingContainer {
  let decoder: _JSONDecoderImpl
  let value: _JSONValue
  var codingPath: [any CodingKey] { return decoder.codingPath }

  func decodeNil() -> Bool { if case .null = value { return true }; return false }
  func decode(_ type: Bool.Type) throws -> Bool { return try decoder.unboxBool(value, path: codingPath) }
  func decode(_ type: String.Type) throws -> String { return try decoder.unboxString(value, path: codingPath) }
  func decode(_ type: Double.Type) throws -> Double { return try decoder.unboxDouble(value, path: codingPath) }
  func decode(_ type: Float.Type) throws -> Float { return Float(try decoder.unboxDouble(value, path: codingPath)) }
  func decode(_ type: Int.Type) throws -> Int { return try decoder.unboxInteger(value, as: type, path: codingPath) }
  func decode(_ type: Int8.Type) throws -> Int8 { return try decoder.unboxInteger(value, as: type, path: codingPath) }
  func decode(_ type: Int16.Type) throws -> Int16 { return try decoder.unboxInteger(value, as: type, path: codingPath) }
  func decode(_ type: Int32.Type) throws -> Int32 { return try decoder.unboxInteger(value, as: type, path: codingPath) }
  func decode(_ type: Int64.Type) throws -> Int64 { return try decoder.unboxInteger(value, as: type, path: codingPath) }
  func decode(_ type: UInt.Type) throws -> UInt { return try decoder.unboxInteger(value, as: type, path: codingPath) }
  func decode(_ type: UInt8.Type) throws -> UInt8 { return try decoder.unboxInteger(value, as: type, path: codingPath) }
  func decode(_ type: UInt16.Type) throws -> UInt16 { return try decoder.unboxInteger(value, as: type, path: codingPath) }
  func decode(_ type: UInt32.Type) throws -> UInt32 { return try decoder.unboxInteger(value, as: type, path: codingPath) }
  func decode(_ type: UInt64.Type) throws -> UInt64 { return try decoder.unboxInteger(value, as: type, path: codingPath) }
  func decode<T: Decodable>(_ type: T.Type) throws -> T { return try decoder.unbox(value, as: type) }
}
