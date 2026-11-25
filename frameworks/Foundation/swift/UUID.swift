// UUID: 16 bytes, random (version 4) by default, written as
// "E621E1F8-C36C-495A-93FC-0C247A3E6E5F".

public typealias uuid_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

@_silgen_name("arc4random_buf")
internal func _bitten_arc4random_buf(_ buf: UnsafeMutableRawPointer, _ count: Int)

public struct UUID: Hashable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  public private(set) var uuid: uuid_t

  public init(uuid: uuid_t) { self.uuid = uuid }

  public init() {
    var u: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    withUnsafeMutableBytes(of: &u) { _bitten_arc4random_buf($0.baseAddress!, 16) }
    u.6 = (u.6 & 0x0F) | 0x40 // version 4
    u.8 = (u.8 & 0x3F) | 0x80 // RFC 4122 variant
    uuid = u
  }

  public init?(uuidString string: __shared String) {
    var bytes: [UInt8] = []
    var high: UInt8? = nil
    var index = 0
    for c in string.utf8 {
      if index == 8 || index == 13 || index == 18 || index == 23 {
        if c != UInt8(ascii: "-") { return nil }
        index += 1
        continue
      }
      let v: UInt8
      switch c {
      case UInt8(ascii: "0")...UInt8(ascii: "9"): v = c - 48
      case UInt8(ascii: "a")...UInt8(ascii: "f"): v = c - 87
      case UInt8(ascii: "A")...UInt8(ascii: "F"): v = c - 55
      default: return nil
      }
      if let h = high {
        bytes.append(h << 4 | v)
        high = nil
      } else {
        high = v
      }
      index += 1
    }
    if index != 36 || bytes.count != 16 { return nil }
    var u: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    withUnsafeMutableBytes(of: &u) { raw in
      for i in 0..<16 { raw[i] = bytes[i] }
    }
    uuid = u
  }

  internal var _bytes: [UInt8] {
    var u = uuid
    return withUnsafeBytes(of: &u) { Array($0) }
  }

  public var uuidString: String {
    let hex: [UInt8] = Array("0123456789ABCDEF".utf8)
    var out: [UInt8] = []
    out.reserveCapacity(36)
    for (i, b) in _bytes.enumerated() {
      if i == 4 || i == 6 || i == 8 || i == 10 { out.append(UInt8(ascii: "-")) }
      out.append(hex[Int(b >> 4)])
      out.append(hex[Int(b & 0xF)])
    }
    return String(decoding: out, as: UTF8.self)
  }

  public var description: String { return uuidString }
  public var debugDescription: String { return uuidString }

  public static func == (lhs: UUID, rhs: UUID) -> Bool { return lhs._bytes == rhs._bytes }
  public func hash(into hasher: inout Hasher) {
    for b in _bytes { hasher.combine(b) }
  }
}

extension UUID: Comparable {
  public static func < (lhs: UUID, rhs: UUID) -> Bool {
    let a = lhs._bytes, b = rhs._bytes
    for i in 0..<16 where a[i] != b[i] { return a[i] < b[i] }
    return false
  }
}

extension UUID: Codable {
  public init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    let s = try c.decode(String.self)
    guard let u = UUID(uuidString: s) else {
      throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath,
                                                              debugDescription: "Attempted to decode UUID from invalid UUID string."))
    }
    self = u
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    try c.encode(uuidString)
  }
}
