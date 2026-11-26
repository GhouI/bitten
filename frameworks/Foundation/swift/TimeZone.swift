// TimeZone: an identifier ("Europe/Paris", "GMT+0100"...) and the offsets
// it has over time. Named zones read their transitions from the system's
// TZif files (/usr/share/zoneinfo); fixed-offset zones are what they say.
// The current zone is TZ, else /etc/localtime's target, else GMT.
// (Minimal for now, agreed with the Foundation side, which extends it.)
import Darwin

internal final class _TimeZoneBox: @unchecked Sendable {
  let identifier: String
  let fixedOffset: Int?
  /// From the TZif file: transition times, the type index after each, and
  /// per type (offset, is DST, abbreviation).
  var transitions: [Int64] = []
  var transitionTypes: [UInt8] = []
  var types: [(offset: Int, dst: Bool, abbreviation: String)] = []

  init(identifier: String, fixedOffset: Int?) {
    self.identifier = identifier
    self.fixedOffset = fixedOffset
  }

  func type(at t: Double) -> (offset: Int, dst: Bool, abbreviation: String) {
    if let f = fixedOffset { return (f, false, _TimeZoneBox.gmtName(f)) }
    guard !types.isEmpty else { return (0, false, "GMT") }
    let when = Int64(t.rounded(.down))
    var lo = 0, hi = transitions.count
    while lo < hi {
      let mid = (lo + hi) / 2
      if transitions[mid] <= when { lo = mid + 1 } else { hi = mid }
    }
    if lo == 0 {
      // Before the first transition: the first standard-time type.
      return types.first(where: { !$0.dst }) ?? types[0]
    }
    let index = Int(transitionTypes[lo - 1])
    return index < types.count ? types[index] : types[0]
  }

  static func gmtName(_ offset: Int) -> String {
    if offset == 0 { return "GMT" }
    let a = Swift.abs(offset), h = a / 3600, m = (a % 3600) / 60
    let hh = h < 10 ? "0\(h)" : "\(h)", mm = m < 10 ? "0\(m)" : "\(m)"
    return "GMT\(offset < 0 ? "-" : "+")\(hh)\(mm)"
  }

  /// Reads a TZif file's version 1 data block (32-bit transition times).
  static func load(_ id: String) -> _TimeZoneBox? {
    guard !id.contains(".."), !id.hasPrefix("/") else { return nil }
    let path = "/usr/share/zoneinfo/" + id
    guard let f = fopen(path, "rb") else { return nil }
    defer { fclose(f) }
    var bytes: [UInt8] = []
    var buf = [UInt8](repeating: 0, count: 4096)
    while true {
      let n = fread(&buf, 1, buf.count, f)
      if n <= 0 { break }
      bytes += buf[0..<n]
    }
    guard bytes.count >= 44, bytes[0] == 0x54, bytes[1] == 0x5A, bytes[2] == 0x69, bytes[3] == 0x66 else { return nil }
    func be32(_ i: Int) -> Int32 {
      return Int32(bitPattern: UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3]))
    }
    let isutc = Int(be32(20)), isstd = Int(be32(24)), leap = Int(be32(28))
    let timecnt = Int(be32(32)), typecnt = Int(be32(36)), charcnt = Int(be32(40))
    var p = 44
    guard bytes.count >= p + timecnt * 5 + typecnt * 6 + charcnt + leap * 8 + isstd + isutc else { return nil }
    let box = _TimeZoneBox(identifier: id, fixedOffset: nil)
    for i in 0..<timecnt { box.transitions.append(Int64(be32(p + i * 4))) }
    p += timecnt * 4
    box.transitionTypes = Array(bytes[p..<(p + timecnt)])
    p += timecnt
    var raw: [(Int, Bool, Int)] = []
    for i in 0..<typecnt {
      raw.append((Int(be32(p + i * 6)), bytes[p + i * 6 + 4] != 0, Int(bytes[p + i * 6 + 5])))
    }
    p += typecnt * 6
    let chars = Array(bytes[p..<(p + charcnt)])
    for (off, dst, idx) in raw {
      var name = ""
      var j = idx
      while j < chars.count, chars[j] != 0 {
        name.append(Character(Unicode.Scalar(chars[j])))
        j += 1
      }
      box.types.append((off, dst, name))
    }
    return box
  }
}

public struct TimeZone: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, Codable {
  internal let _box: _TimeZoneBox

  internal init(_box: _TimeZoneBox) { self._box = _box }

  /// A zone from the TZ database ("America/New_York"), or "GMT", "UTC",
  /// "GMT+0100" and the like.
  public init?(identifier: __shared String) {
    if identifier == "GMT" || identifier == "UTC" || identifier == "Etc/UTC" || identifier == "Etc/GMT" {
      _box = _TimeZoneBox(identifier: identifier == "UTC" ? "UTC" : "GMT", fixedOffset: 0)
      return
    }
    if let offset = TimeZone._parseOffset(identifier) {
      _box = _TimeZoneBox(identifier: _TimeZoneBox.gmtName(offset), fixedOffset: offset)
      return
    }
    guard let box = _TimeZoneBox.load(identifier) else { return nil }
    _box = box
  }

  public init?(secondsFromGMT seconds: Int) {
    guard Swift.abs(seconds) <= 18 * 3600 else { return nil }
    _box = _TimeZoneBox(identifier: _TimeZoneBox.gmtName(seconds), fixedOffset: seconds)
  }

  public init?(abbreviation: String) {
    switch abbreviation.uppercased() {
    case "GMT", "UTC": self.init(identifier: "GMT")
    case "EST", "EDT": self.init(identifier: "America/New_York")
    case "CST", "CDT": self.init(identifier: "America/Chicago")
    case "MST", "MDT": self.init(identifier: "America/Denver")
    case "PST", "PDT": self.init(identifier: "America/Los_Angeles")
    case "CET", "CEST": self.init(identifier: "Europe/Paris")
    case "BST": self.init(identifier: "Europe/London")
    case "JST": self.init(identifier: "Asia/Tokyo")
    default: return nil
    }
  }

  /// "GMT+0100", "GMT-05:30", "+0100", "UTC+1".
  internal static func _parseOffset(_ s: String) -> Int? {
    var t = Substring(s)
    if t.hasPrefix("GMT") || t.hasPrefix("UTC") { t = t.dropFirst(3) }
    guard let sign = t.first, sign == "+" || sign == "-" else { return nil }
    t = t.dropFirst()
    let digits = String(t.filter { $0 != ":" })
    guard !digits.isEmpty, digits.count <= 4, digits.allSatisfy({ $0.isNumber }) else { return nil }
    var h = 0, m = 0
    if digits.count <= 2 { h = Int(digits) ?? 0 } else {
      h = Int(String(digits.prefix(digits.count - 2))) ?? 0
      m = Int(String(digits.suffix(2))) ?? 0
    }
    let total = h * 3600 + m * 60
    return sign == "-" ? -total : total
  }

  public static var current: TimeZone {
    if let tz = getenv("TZ") {
      var id = String(cString: tz)
      if id.hasPrefix(":") { id.removeFirst() }
      if let z = TimeZone(identifier: id) { return z }
    }
    var buf = [CChar](repeating: 0, count: 1024)
    let n = readlink("/etc/localtime", &buf, 1023)
    if n > 0 {
      let target = String(cString: buf)
      if let r = target.range(of: "zoneinfo/"), let z = TimeZone(identifier: String(target[r.upperBound...])) {
        return z
      }
    }
    return .gmt
  }
  public static var autoupdatingCurrent: TimeZone { return current }
  public static var gmt: TimeZone { return TimeZone(identifier: "GMT")! }

  public var identifier: String { return _box.identifier }
  public func secondsFromGMT(for date: Date = Date()) -> Int { return _box.type(at: date.timeIntervalSince1970).offset }
  public func abbreviation(for date: Date = Date()) -> String? { return _box.type(at: date.timeIntervalSince1970).abbreviation }
  public func isDaylightSavingTime(for date: Date = Date()) -> Bool { return _box.type(at: date.timeIntervalSince1970).dst }
  public func daylightSavingTimeOffset(for date: Date = Date()) -> TimeInterval {
    let t = _box.type(at: date.timeIntervalSince1970)
    guard t.dst else { return 0 }
    let std = _box.types.first(where: { !$0.dst })?.offset ?? t.offset
    return TimeInterval(t.offset - std)
  }

  public var description: String { return identifier }
  public var debugDescription: String { return "\(identifier) (fixed: \(_box.fixedOffset != nil))" }

  public static func == (a: TimeZone, b: TimeZone) -> Bool { return a.identifier == b.identifier }
  public func hash(into h: inout Hasher) { h.combine(identifier) }

  public init(from decoder: Decoder) throws {
    let id = try decoder.singleValueContainer().decode(String.self)
    self = TimeZone(identifier: id) ?? .gmt
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    try c.encode(identifier)
  }
}

extension TimeZone: _ObjectiveCBridgeable {
  public func _bridgeToObjectiveC() -> NSTimeZone {
    return NSTimeZone(name: identifier) ?? NSTimeZone(forSecondsFromGMT: secondsFromGMT())
  }
  public static func _forceBridgeFromObjectiveC(_ source: NSTimeZone, result: inout TimeZone?) {
    result = TimeZone(identifier: source.name) ?? TimeZone(secondsFromGMT: source.secondsFromGMT)
  }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSTimeZone, result: inout TimeZone?) -> Bool {
    _forceBridgeFromObjectiveC(source, result: &result)
    return result != nil
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSTimeZone?) -> TimeZone {
    var r: TimeZone? = nil
    if let s = source { _forceBridgeFromObjectiveC(s, result: &r) }
    return r ?? .gmt
  }
}
