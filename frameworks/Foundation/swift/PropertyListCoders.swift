// PropertyListEncoder and PropertyListDecoder: Codable values to and from
// property lists (through PropertyListSerialization), plus FileManager's
// replaceItemAt and NSNotFound for Swift.

/// NSNotFound as Swift sees it.
public var NSNotFound: Int { return Int.max }

// MARK: - encoding

open class PropertyListEncoder {
  open var outputFormat: PropertyListSerialization.PropertyListFormat = .binary
  open var userInfo: [CodingUserInfoKey: Any] = [:]
  public init() {}

  open func encode<Value: Encodable>(_ value: Value) throws -> Data {
    let tree = try encodeToTopLevelContainer(value)
    return try PropertyListSerialization.data(withPropertyList: tree, format: outputFormat, options: 0)
  }
  internal func encodeToTopLevelContainer<Value: Encodable>(_ value: Value) throws -> Any {
    let e = _PlistEncoder(userInfo: userInfo)
    guard let tree = try e.box(value, path: []) else {
      throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Top-level value encoded no value"))
    }
    return tree
  }
}

/// Where encoded values accumulate: a reference so nested containers can
/// fill their parent's slot.
private final class _PlistBox {
  enum Kind { case none, value(Any), dict(NSMutableDictionary), array(NSMutableArray) }
  var kind: Kind = .none
  var object: Any? {
    switch kind {
    case .none: return nil
    case .value(let v): return v
    case .dict(let d): return d
    case .array(let a): return a
    }
  }
}

private final class _PlistEncoder: Encoder {
  var codingPath: [CodingKey]
  let userInfo: [CodingUserInfoKey: Any]
  let box: _PlistBox
  init(userInfo: [CodingUserInfoKey: Any], path: [CodingKey] = [], box: _PlistBox = _PlistBox()) {
    self.userInfo = userInfo
    codingPath = path
    self.box = box
  }
  /// The property-list object for a value: primitives directly, Date and
  /// Data as themselves, everything else through its encode(to:).
  func box<T: Encodable>(_ value: T, path: [CodingKey]) throws -> Any? {
    switch value {
    case let v as String: return v as NSString
    case let v as Bool: return NSNumber(value: v)
    case let v as Int: return NSNumber(value: v)
    case let v as Int8: return NSNumber(value: v)
    case let v as Int16: return NSNumber(value: v)
    case let v as Int32: return NSNumber(value: v)
    case let v as Int64: return NSNumber(value: v)
    case let v as UInt: return NSNumber(value: v)
    case let v as UInt8: return NSNumber(value: v)
    case let v as UInt16: return NSNumber(value: v)
    case let v as UInt32: return NSNumber(value: v)
    case let v as UInt64: return NSNumber(value: v)
    case let v as Double: return NSNumber(value: v)
    case let v as Float: return NSNumber(value: v)
    case let v as Date: return v as NSDate
    case let v as Data: return v as NSData
    case let v as URL: return v.absoluteString as NSString
    default:
      let e = _PlistEncoder(userInfo: userInfo, path: path)
      try value.encode(to: e)
      return e.box.object ?? NSDictionary()
    }
  }
  func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    let d: NSMutableDictionary
    if case .dict(let existing) = box.kind {
      d = existing
    } else {
      d = NSMutableDictionary()
      box.kind = .dict(d)
    }
    return KeyedEncodingContainer(_PlistKeyedEncoder<Key>(encoder: self, dict: d, path: codingPath))
  }
  func unkeyedContainer() -> UnkeyedEncodingContainer {
    let a: NSMutableArray
    if case .array(let existing) = box.kind {
      a = existing
    } else {
      a = NSMutableArray()
      box.kind = .array(a)
    }
    return _PlistUnkeyedEncoder(encoder: self, array: a, path: codingPath)
  }
  func singleValueContainer() -> SingleValueEncodingContainer { return _PlistSingleEncoder(encoder: self) }
}

private struct _PlistKeyedEncoder<Key: CodingKey>: KeyedEncodingContainerProtocol {
  let encoder: _PlistEncoder
  let dict: NSMutableDictionary
  let path: [CodingKey]
  var codingPath: [CodingKey] { return path }
  mutating func encodeNil(forKey key: Key) throws {}
  mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
    if let v = try encoder.box(value, path: path + [key]) { dict.setObject(v, forKey: key.stringValue as NSString) }
  }
  mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key)
    -> KeyedEncodingContainer<NestedKey> {
    let d = NSMutableDictionary()
    dict.setObject(d, forKey: key.stringValue as NSString)
    let b = _PlistBox()
    b.kind = .dict(d)
    return _PlistEncoder(userInfo: encoder.userInfo, path: path + [key], box: b).container(keyedBy: keyType)
  }
  mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
    let a = NSMutableArray()
    dict.setObject(a, forKey: key.stringValue as NSString)
    let b = _PlistBox()
    b.kind = .array(a)
    return _PlistEncoder(userInfo: encoder.userInfo, path: path + [key], box: b).unkeyedContainer()
  }
  mutating func superEncoder() -> Encoder { return superEncoder(forKey: Key(stringValue: "super")!) }
  mutating func superEncoder(forKey key: Key) -> Encoder {
    let d = NSMutableDictionary()
    dict.setObject(d, forKey: key.stringValue as NSString)
    let b = _PlistBox()
    b.kind = .dict(d)
    return _PlistEncoder(userInfo: encoder.userInfo, path: path + [key], box: b)
  }
}

private struct _PlistIndexKey: CodingKey {
  var stringValue: String
  var intValue: Int?
  init(_ i: Int) {
    stringValue = "Index \(i)"
    intValue = i
  }
  init?(stringValue: String) { return nil }
  init?(intValue: Int) { self.init(intValue) }
}

private struct _PlistUnkeyedEncoder: UnkeyedEncodingContainer {
  let encoder: _PlistEncoder
  let array: NSMutableArray
  let path: [CodingKey]
  var codingPath: [CodingKey] { return path }
  var count: Int { return array.count }
  mutating func encodeNil() throws {}
  mutating func encode<T: Encodable>(_ value: T) throws {
    if let v = try encoder.box(value, path: path + [_PlistIndexKey(count)]) { array.add(v) }
  }
  mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
    let d = NSMutableDictionary()
    array.add(d)
    let b = _PlistBox()
    b.kind = .dict(d)
    return _PlistEncoder(userInfo: encoder.userInfo, path: path, box: b).container(keyedBy: keyType)
  }
  mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
    let a = NSMutableArray()
    array.add(a)
    let b = _PlistBox()
    b.kind = .array(a)
    return _PlistEncoder(userInfo: encoder.userInfo, path: path, box: b).unkeyedContainer()
  }
  mutating func superEncoder() -> Encoder {
    let d = NSMutableDictionary()
    array.add(d)
    let b = _PlistBox()
    b.kind = .dict(d)
    return _PlistEncoder(userInfo: encoder.userInfo, path: path, box: b)
  }
}

private struct _PlistSingleEncoder: SingleValueEncodingContainer {
  let encoder: _PlistEncoder
  var codingPath: [CodingKey] { return encoder.codingPath }
  mutating func encodeNil() throws {}
  mutating func encode<T: Encodable>(_ value: T) throws {
    if let v = try encoder.box(value, path: codingPath) { encoder.box.kind = .value(v) }
  }
}

// MARK: - decoding

open class PropertyListDecoder {
  open var userInfo: [CodingUserInfoKey: Any] = [:]
  public init() {}

  open func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    var format = PropertyListSerialization.PropertyListFormat.binary
    return try decode(type, from: data, format: &format)
  }
  open func decode<T: Decodable>(_ type: T.Type, from data: Data,
                                 format: inout PropertyListSerialization.PropertyListFormat) throws -> T {
    let tree: Any
    do {
      tree = try PropertyListSerialization.propertyList(with: data, options: [], format: &format)
    } catch {
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The given data was not a valid property list.",
                                              underlyingError: error))
    }
    return try _PlistDecoder(value: tree, path: [], userInfo: userInfo).unbox(type)
  }
}

private final class _PlistDecoder: Decoder {
  let value: Any
  var codingPath: [CodingKey]
  let userInfo: [CodingUserInfoKey: Any]
  init(value: Any, path: [CodingKey], userInfo: [CodingUserInfoKey: Any]) {
    self.value = value
    codingPath = path
    self.userInfo = userInfo
  }
  func mismatch<T>(_ t: T.Type) -> DecodingError {
    return .typeMismatch(t, .init(codingPath: codingPath, debugDescription: "Expected \(t), found \(type(of: value))"))
  }
  func unbox<T: Decodable>(_ type: T.Type) throws -> T {
    func number() throws -> NSNumber {
      if let n = value as? NSNumber { return n }
      if let s = value as? String, let d = Double(s) { return NSNumber(value: d) }
      throw mismatch(type)
    }
    switch type {
    case is String.Type:
      guard let s = value as? String else { throw mismatch(type) }
      return s as! T
    case is Bool.Type: return try number().boolValue as! T
    case is Int.Type: return try number().integerValue as! T
    case is Int8.Type: return Int8(truncatingIfNeeded: try number().integerValue) as! T
    case is Int16.Type: return Int16(truncatingIfNeeded: try number().integerValue) as! T
    case is Int32.Type: return Int32(truncatingIfNeeded: try number().integerValue) as! T
    case is Int64.Type: return Int64(try number().integerValue) as! T
    case is UInt.Type: return UInt(bitPattern: try number().integerValue) as! T
    case is UInt8.Type: return UInt8(truncatingIfNeeded: try number().integerValue) as! T
    case is UInt16.Type: return UInt16(truncatingIfNeeded: try number().integerValue) as! T
    case is UInt32.Type: return UInt32(truncatingIfNeeded: try number().integerValue) as! T
    case is UInt64.Type: return UInt64(bitPattern: Int64(try number().integerValue)) as! T
    case is Double.Type: return try number().doubleValue as! T
    case is Float.Type: return try number().floatValue as! T
    case is Date.Type:
      guard let d = value as? Date else { throw mismatch(type) }
      return d as! T
    case is Data.Type:
      guard let d = value as? Data else { throw mismatch(type) }
      return d as! T
    case is URL.Type:
      guard let s = value as? String, let u = URL(string: s) else { throw mismatch(type) }
      return u as! T
    default:
      return try T(from: self)
    }
  }
  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    guard let d = value as? [String: Any] else { throw mismatch([String: Any].self) }
    return KeyedDecodingContainer(_PlistKeyedDecoder<Key>(decoder: self, dict: d))
  }
  func unkeyedContainer() throws -> UnkeyedDecodingContainer {
    guard let a = value as? [Any] else { throw mismatch([Any].self) }
    return _PlistUnkeyedDecoder(decoder: self, array: a)
  }
  func singleValueContainer() throws -> SingleValueDecodingContainer { return _PlistSingleDecoder(decoder: self) }
}

private struct _PlistKeyedDecoder<Key: CodingKey>: KeyedDecodingContainerProtocol {
  let decoder: _PlistDecoder
  let dict: [String: Any]
  var codingPath: [CodingKey] { return decoder.codingPath }
  var allKeys: [Key] { return dict.keys.compactMap { Key(stringValue: $0) } }
  func contains(_ key: Key) -> Bool { return dict[key.stringValue] != nil }
  func child(_ key: Key) throws -> _PlistDecoder {
    guard let v = dict[key.stringValue] else {
      throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "No value for \(key.stringValue)"))
    }
    return _PlistDecoder(value: v, path: codingPath + [key], userInfo: decoder.userInfo)
  }
  func decodeNil(forKey key: Key) throws -> Bool { return dict[key.stringValue] == nil }
  func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { return try child(key).unbox(type) }
  func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws
    -> KeyedDecodingContainer<NestedKey> {
    return try child(key).container(keyedBy: type)
  }
  func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer { return try child(key).unkeyedContainer() }
  func superDecoder() throws -> Decoder { return try child(Key(stringValue: "super")!) }
  func superDecoder(forKey key: Key) throws -> Decoder { return try child(key) }
}

private struct _PlistUnkeyedDecoder: UnkeyedDecodingContainer {
  let decoder: _PlistDecoder
  let array: [Any]
  var currentIndex = 0
  init(decoder: _PlistDecoder, array: [Any]) {
    self.decoder = decoder
    self.array = array
  }
  var codingPath: [CodingKey] { return decoder.codingPath }
  var count: Int? { return array.count }
  var isAtEnd: Bool { return currentIndex >= array.count }
  mutating func next() throws -> _PlistDecoder {
    guard !isAtEnd else {
      throw DecodingError.valueNotFound(Any.self, .init(codingPath: codingPath, debugDescription: "Unkeyed container is at end."))
    }
    let d = _PlistDecoder(value: array[currentIndex], path: codingPath + [_PlistIndexKey(currentIndex)],
                          userInfo: decoder.userInfo)
    currentIndex += 1
    return d
  }
  mutating func decodeNil() throws -> Bool { return false }
  mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { return try next().unbox(type) }
  mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
    return try next().container(keyedBy: type)
  }
  mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer { return try next().unkeyedContainer() }
  mutating func superDecoder() throws -> Decoder { return try next() }
}

private struct _PlistSingleDecoder: SingleValueDecodingContainer {
  let decoder: _PlistDecoder
  var codingPath: [CodingKey] { return decoder.codingPath }
  func decodeNil() -> Bool { return false }
  func decode<T: Decodable>(_ type: T.Type) throws -> T { return try decoder.unbox(type) }
}

// MARK: - FileManager.replaceItemAt

extension FileManager {
  /// Replaces the item at `originalItemURL` with the one at `newItemURL`
  /// (which is moved), keeping a backup under `backupItemName` if asked.
  @discardableResult
  public func replaceItemAt(_ originalItemURL: URL, withItemAt newItemURL: URL, backupItemName: String? = nil,
                            options: FileManager.ItemReplacementOptions = []) throws -> URL? {
    let original = originalItemURL.path
    if fileExists(atPath: original) {
      if let backup = backupItemName {
        let backupPath = String((original as NSString).deletingLastPathComponent) + "/" + backup
        if fileExists(atPath: backupPath) { try removeItem(atPath: backupPath) }
        try moveItem(atPath: original, toPath: backupPath)
      } else {
        try removeItem(atPath: original)
      }
    }
    try moveItem(atPath: newItemURL.path, toPath: original)
    return originalItemURL
  }
}
