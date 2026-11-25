// Codable with compiler-synthesized conformances, round-tripped through a
// small tree encoder/decoder written here: keyed, unkeyed and single-value
// containers, nesting, optionals, arrays, dictionaries, raw-value enums.

indirect enum Node {
  case null
  case value(String)
  case list([Node])
  case map([String: Node])
}

final class TreeEncoder: Encoder {
  var codingPath: [any CodingKey] = []
  var userInfo: [CodingUserInfoKey: Any] = [:]
  var result: Node = .null

  struct Keyed<K: CodingKey>: KeyedEncodingContainerProtocol {
    let enc: TreeEncoder
    var codingPath: [any CodingKey] { return [] }
    func put(_ n: Node, _ key: K) {
      if case .map(var m) = enc.result { m[key.stringValue] = n; enc.result = .map(m) }
    }
    mutating func encodeNil(forKey key: K) throws { put(.null, key) }
    mutating func encode(_ value: Bool, forKey key: K) throws { put(.value("\(value)"), key) }
    mutating func encode(_ value: String, forKey key: K) throws { put(.value(value), key) }
    mutating func encode(_ value: Double, forKey key: K) throws { put(.value("\(value)"), key) }
    mutating func encode(_ value: Float, forKey key: K) throws { put(.value("\(value)"), key) }
    mutating func encode(_ value: Int, forKey key: K) throws { put(.value("\(value)"), key) }
    mutating func encode(_ value: Int8, forKey key: K) throws { put(.value("\(value)"), key) }
    mutating func encode(_ value: Int16, forKey key: K) throws { put(.value("\(value)"), key) }
    mutating func encode(_ value: Int32, forKey key: K) throws { put(.value("\(value)"), key) }
    mutating func encode(_ value: Int64, forKey key: K) throws { put(.value("\(value)"), key) }
    mutating func encode(_ value: UInt, forKey key: K) throws { put(.value("\(value)"), key) }
    mutating func encode(_ value: UInt8, forKey key: K) throws { put(.value("\(value)"), key) }
    mutating func encode(_ value: UInt16, forKey key: K) throws { put(.value("\(value)"), key) }
    mutating func encode(_ value: UInt32, forKey key: K) throws { put(.value("\(value)"), key) }
    mutating func encode(_ value: UInt64, forKey key: K) throws { put(.value("\(value)"), key) }
    mutating func encode<T: Encodable>(_ value: T, forKey key: K) throws { put(try TreeEncoder.tree(value), key) }
    mutating func nestedContainer<N: CodingKey>(keyedBy keyType: N.Type, forKey key: K) -> KeyedEncodingContainer<N> { fatalError() }
    mutating func nestedUnkeyedContainer(forKey key: K) -> any UnkeyedEncodingContainer { fatalError() }
    mutating func superEncoder() -> any Encoder { fatalError() }
    mutating func superEncoder(forKey key: K) -> any Encoder { fatalError() }
  }
  struct Unkeyed: UnkeyedEncodingContainer {
    let enc: TreeEncoder
    var codingPath: [any CodingKey] { return [] }
    var count: Int { if case .list(let l) = enc.result { return l.count }; return 0 }
    func add(_ n: Node) { if case .list(var l) = enc.result { l.append(n); enc.result = .list(l) } }
    mutating func encodeNil() throws { add(.null) }
    mutating func encode(_ value: Bool) throws { add(.value("\(value)")) }
    mutating func encode(_ value: String) throws { add(.value(value)) }
    mutating func encode(_ value: Double) throws { add(.value("\(value)")) }
    mutating func encode(_ value: Float) throws { add(.value("\(value)")) }
    mutating func encode(_ value: Int) throws { add(.value("\(value)")) }
    mutating func encode(_ value: Int8) throws { add(.value("\(value)")) }
    mutating func encode(_ value: Int16) throws { add(.value("\(value)")) }
    mutating func encode(_ value: Int32) throws { add(.value("\(value)")) }
    mutating func encode(_ value: Int64) throws { add(.value("\(value)")) }
    mutating func encode(_ value: UInt) throws { add(.value("\(value)")) }
    mutating func encode(_ value: UInt8) throws { add(.value("\(value)")) }
    mutating func encode(_ value: UInt16) throws { add(.value("\(value)")) }
    mutating func encode(_ value: UInt32) throws { add(.value("\(value)")) }
    mutating func encode(_ value: UInt64) throws { add(.value("\(value)")) }
    mutating func encode<T: Encodable>(_ value: T) throws { add(try TreeEncoder.tree(value)) }
    mutating func nestedContainer<N: CodingKey>(keyedBy keyType: N.Type) -> KeyedEncodingContainer<N> { fatalError() }
    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer { fatalError() }
    mutating func superEncoder() -> any Encoder { fatalError() }
  }
  struct Single: SingleValueEncodingContainer {
    let enc: TreeEncoder
    var codingPath: [any CodingKey] { return [] }
    mutating func encodeNil() throws { enc.result = .null }
    mutating func encode(_ value: Bool) throws { enc.result = .value("\(value)") }
    mutating func encode(_ value: String) throws { enc.result = .value(value) }
    mutating func encode(_ value: Double) throws { enc.result = .value("\(value)") }
    mutating func encode(_ value: Float) throws { enc.result = .value("\(value)") }
    mutating func encode(_ value: Int) throws { enc.result = .value("\(value)") }
    mutating func encode(_ value: Int8) throws { enc.result = .value("\(value)") }
    mutating func encode(_ value: Int16) throws { enc.result = .value("\(value)") }
    mutating func encode(_ value: Int32) throws { enc.result = .value("\(value)") }
    mutating func encode(_ value: Int64) throws { enc.result = .value("\(value)") }
    mutating func encode(_ value: UInt) throws { enc.result = .value("\(value)") }
    mutating func encode(_ value: UInt8) throws { enc.result = .value("\(value)") }
    mutating func encode(_ value: UInt16) throws { enc.result = .value("\(value)") }
    mutating func encode(_ value: UInt32) throws { enc.result = .value("\(value)") }
    mutating func encode(_ value: UInt64) throws { enc.result = .value("\(value)") }
    mutating func encode<T: Encodable>(_ value: T) throws { enc.result = try TreeEncoder.tree(value) }
  }

  static func tree<T: Encodable>(_ v: T) throws -> Node {
    let e = TreeEncoder()
    try v.encode(to: e)
    return e.result
  }
  func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    result = .map([:])
    return KeyedEncodingContainer(Keyed<Key>(enc: self))
  }
  func unkeyedContainer() -> any UnkeyedEncodingContainer {
    result = .list([])
    return Unkeyed(enc: self)
  }
  func singleValueContainer() -> any SingleValueEncodingContainer { return Single(enc: self) }
}

struct TreeDecoder: Decoder {
  let node: Node
  var codingPath: [any CodingKey] { return [] }
  var userInfo: [CodingUserInfoKey: Any] { return [:] }
  struct Bad: Error {}

  static func scalar(_ n: Node) throws -> String {
    guard case .value(let s) = n else { throw Bad() }
    return s
  }
  static func decodeScalar<T>(_ s: String, _ t: T.Type) throws -> T {
    if T.self == String.self { return s as! T }
    if T.self == Bool.self { return (s == "true") as! T }
    if T.self == Double.self, let d = Double(s) { return d as! T }
    if T.self == Int.self, let i = Int(s) { return i as! T }
    if T.self == Int64.self, let i = Int64(s) { return i as! T }
    if T.self == UInt32.self, let i = UInt32(s) { return i as! T }
    throw Bad()
  }

  struct Keyed<K: CodingKey>: KeyedDecodingContainerProtocol {
    let map: [String: Node]
    var codingPath: [any CodingKey] { return [] }
    var allKeys: [K] { return map.keys.compactMap { K(stringValue: $0) } }
    func contains(_ key: K) -> Bool { return map[key.stringValue] != nil }
    func node(_ key: K) throws -> Node { guard let n = map[key.stringValue] else { throw Bad() }; return n }
    func decodeNil(forKey key: K) throws -> Bool { if case .null = try node(key) { return true }; return false }
    func decode(_ type: Bool.Type, forKey key: K) throws -> Bool { return try decodeScalar(scalar(node(key)), type) }
    func decode(_ type: String.Type, forKey key: K) throws -> String { return try scalar(node(key)) }
    func decode(_ type: Double.Type, forKey key: K) throws -> Double { return try decodeScalar(scalar(node(key)), type) }
    func decode(_ type: Float.Type, forKey key: K) throws -> Float { throw Bad() }
    func decode(_ type: Int.Type, forKey key: K) throws -> Int { return try decodeScalar(scalar(node(key)), type) }
    func decode(_ type: Int8.Type, forKey key: K) throws -> Int8 { throw Bad() }
    func decode(_ type: Int16.Type, forKey key: K) throws -> Int16 { throw Bad() }
    func decode(_ type: Int32.Type, forKey key: K) throws -> Int32 { throw Bad() }
    func decode(_ type: Int64.Type, forKey key: K) throws -> Int64 { return try decodeScalar(scalar(node(key)), type) }
    func decode(_ type: UInt.Type, forKey key: K) throws -> UInt { throw Bad() }
    func decode(_ type: UInt8.Type, forKey key: K) throws -> UInt8 { throw Bad() }
    func decode(_ type: UInt16.Type, forKey key: K) throws -> UInt16 { throw Bad() }
    func decode(_ type: UInt32.Type, forKey key: K) throws -> UInt32 { return try decodeScalar(scalar(node(key)), type) }
    func decode(_ type: UInt64.Type, forKey key: K) throws -> UInt64 { throw Bad() }
    func decode<T: Decodable>(_ type: T.Type, forKey key: K) throws -> T { return try T(from: TreeDecoder(node: node(key))) }
    func nestedContainer<N: CodingKey>(keyedBy type: N.Type, forKey key: K) throws -> KeyedDecodingContainer<N> { throw Bad() }
    func nestedUnkeyedContainer(forKey key: K) throws -> any UnkeyedDecodingContainer { throw Bad() }
    func superDecoder() throws -> any Decoder { throw Bad() }
    func superDecoder(forKey key: K) throws -> any Decoder { throw Bad() }
  }
  struct Unkeyed: UnkeyedDecodingContainer {
    let list: [Node]
    var currentIndex = 0
    var codingPath: [any CodingKey] { return [] }
    var count: Int? { return list.count }
    var isAtEnd: Bool { return currentIndex >= list.count }
    mutating func next() throws -> Node {
      guard !isAtEnd else { throw Bad() }
      currentIndex += 1
      return list[currentIndex - 1]
    }
    mutating func decodeNil() throws -> Bool {
      if case .null = list[currentIndex] { currentIndex += 1; return true }
      return false
    }
    mutating func decode(_ type: Bool.Type) throws -> Bool { return try decodeScalar(scalar(next()), type) }
    mutating func decode(_ type: String.Type) throws -> String { return try scalar(next()) }
    mutating func decode(_ type: Double.Type) throws -> Double { return try decodeScalar(scalar(next()), type) }
    mutating func decode(_ type: Float.Type) throws -> Float { throw Bad() }
    mutating func decode(_ type: Int.Type) throws -> Int { return try decodeScalar(scalar(next()), type) }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { throw Bad() }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { throw Bad() }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { throw Bad() }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { return try decodeScalar(scalar(next()), type) }
    mutating func decode(_ type: UInt.Type) throws -> UInt { throw Bad() }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { throw Bad() }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { throw Bad() }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { return try decodeScalar(scalar(next()), type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { throw Bad() }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { return try T(from: TreeDecoder(node: next())) }
    mutating func nestedContainer<N: CodingKey>(keyedBy type: N.Type) throws -> KeyedDecodingContainer<N> { throw Bad() }
    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer { throw Bad() }
    mutating func superDecoder() throws -> any Decoder { throw Bad() }
  }
  struct Single: SingleValueDecodingContainer {
    let node: Node
    var codingPath: [any CodingKey] { return [] }
    func decodeNil() -> Bool { if case .null = node { return true }; return false }
    func decode(_ type: Bool.Type) throws -> Bool { return try decodeScalar(scalar(node), type) }
    func decode(_ type: String.Type) throws -> String { return try scalar(node) }
    func decode(_ type: Double.Type) throws -> Double { return try decodeScalar(scalar(node), type) }
    func decode(_ type: Float.Type) throws -> Float { throw Bad() }
    func decode(_ type: Int.Type) throws -> Int { return try decodeScalar(scalar(node), type) }
    func decode(_ type: Int8.Type) throws -> Int8 { throw Bad() }
    func decode(_ type: Int16.Type) throws -> Int16 { throw Bad() }
    func decode(_ type: Int32.Type) throws -> Int32 { throw Bad() }
    func decode(_ type: Int64.Type) throws -> Int64 { return try decodeScalar(scalar(node), type) }
    func decode(_ type: UInt.Type) throws -> UInt { throw Bad() }
    func decode(_ type: UInt8.Type) throws -> UInt8 { throw Bad() }
    func decode(_ type: UInt16.Type) throws -> UInt16 { throw Bad() }
    func decode(_ type: UInt32.Type) throws -> UInt32 { return try decodeScalar(scalar(node), type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { throw Bad() }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { return try T(from: TreeDecoder(node: node)) }
  }

  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    guard case .map(let m) = node else { throw Bad() }
    return KeyedDecodingContainer(Keyed<Key>(map: m))
  }
  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    guard case .list(let l) = node else { throw Bad() }
    return Unkeyed(list: l)
  }
  func singleValueContainer() throws -> any SingleValueDecodingContainer { return Single(node: node) }
}

enum Color: String, Codable, Equatable { case red, green }

struct Settings: Codable, Equatable {
  var name: String
  var size: Int
  var scale: Double
  var dark: Bool
  var tags: [String]
  var accent: Color
  var nickname: String?
  var limits: [String: Int]
  var nested: Inner
  struct Inner: Codable, Equatable {
    var id: UInt32
    var big: Int64
  }
}

@_silgen_name("swcod_run") public func run() -> Int {
  var r = 0
  let s = Settings(name: "App", size: 14, scale: 1.5, dark: true, tags: ["a", "b"], accent: .green,
                   nickname: nil, limits: ["x": 1, "y": 2], nested: .init(id: 7, big: -9_000_000_000))
  do {
    let tree = try TreeEncoder.tree(s)
    if case .map(let m) = tree, m.count == 8, case .value("App")? = m["name"], case .value("green")? = m["accent"],
       m["nickname"] == nil { r |= 1 }
    let back = try Settings(from: TreeDecoder(node: tree))
    if back == s { r |= 2 }
    if back.limits["y"] == 2 && back.nested.big == -9_000_000_000 && back.tags == ["a", "b"] { r |= 4 }
  } catch {
    return -1
  }
  do {
    _ = try Color(from: TreeDecoder(node: .value("blue")))
  } catch let DecodingError.dataCorrupted(ctx) {
    if ctx.debugDescription.contains("invalid") { r |= 8 }
  } catch {}
  return r
}
