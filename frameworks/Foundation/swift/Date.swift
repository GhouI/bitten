// Date: a point in time, as seconds since 2001-01-01 00:00:00 UTC (the
// reference date). Not frozen, so the representation is ours.

public struct Date: Comparable, Hashable, Equatable, Sendable {
  internal var _time: TimeInterval

  public static let timeIntervalBetween1970AndReferenceDate: TimeInterval = 978307200.0

  internal static var _currentTime: TimeInterval {
    var tv = timeval()
    gettimeofday(&tv, nil)
    return TimeInterval(tv.tv_sec) - timeIntervalBetween1970AndReferenceDate + TimeInterval(tv.tv_usec) / 1e6
  }

  public init() { _time = Date._currentTime }
  public init(timeIntervalSinceNow: TimeInterval) { _time = Date._currentTime + timeIntervalSinceNow }
  public init(timeIntervalSince1970: TimeInterval) {
    _time = timeIntervalSince1970 - Date.timeIntervalBetween1970AndReferenceDate
  }
  public init(timeInterval: TimeInterval, since date: Date) { _time = date._time + timeInterval }
  public init(timeIntervalSinceReferenceDate ti: TimeInterval) { _time = ti }

  public static var now: Date { return Date() }
  public static let distantFuture = Date(timeIntervalSinceReferenceDate: 63113904000.0)
  public static let distantPast = Date(timeIntervalSinceReferenceDate: -63114076800.0)

  public var timeIntervalSinceReferenceDate: TimeInterval { return _time }
  public var timeIntervalSince1970: TimeInterval { return _time + Date.timeIntervalBetween1970AndReferenceDate }
  public var timeIntervalSinceNow: TimeInterval { return _time - Date._currentTime }
  public static var timeIntervalSinceReferenceDate: TimeInterval { return _currentTime }

  public func timeIntervalSince(_ date: Date) -> TimeInterval { return _time - date._time }
  public func addingTimeInterval(_ timeInterval: TimeInterval) -> Date { return Date(timeIntervalSinceReferenceDate: _time + timeInterval) }
  public mutating func addTimeInterval(_ timeInterval: TimeInterval) { _time += timeInterval }

  public static func == (lhs: Date, rhs: Date) -> Bool { return lhs._time == rhs._time }
  public static func < (lhs: Date, rhs: Date) -> Bool { return lhs._time < rhs._time }
  public static func > (lhs: Date, rhs: Date) -> Bool { return lhs._time > rhs._time }
  public static func <= (lhs: Date, rhs: Date) -> Bool { return lhs._time <= rhs._time }
  public static func >= (lhs: Date, rhs: Date) -> Bool { return lhs._time >= rhs._time }
  public static func + (lhs: Date, rhs: TimeInterval) -> Date { return lhs.addingTimeInterval(rhs) }
  public static func - (lhs: Date, rhs: TimeInterval) -> Date { return lhs.addingTimeInterval(-rhs) }
  public static func += (lhs: inout Date, rhs: TimeInterval) { lhs._time += rhs }
  public static func -= (lhs: inout Date, rhs: TimeInterval) { lhs._time -= rhs }

  public func hash(into hasher: inout Hasher) { hasher.combine(_time) }

  /// "2001-01-01 00:00:00 +0000"
  internal var _utcDescription: String {
    var t = time_t(timeIntervalSince1970.rounded(.down))
    var parts = tm()
    gmtime_r(&t, &parts)
    func pad(_ v: Int32, _ width: Int) -> String {
      let s = String(v)
      return String(repeating: "0", count: Swift.max(0, width - s.count)) + s
    }
    return "\(pad(parts.tm_year + 1900, 4))-\(pad(parts.tm_mon + 1, 2))-\(pad(parts.tm_mday, 2)) "
      + "\(pad(parts.tm_hour, 2)):\(pad(parts.tm_min, 2)):\(pad(parts.tm_sec, 2)) +0000"
  }
}

extension Date: Strideable {
  public func distance(to other: Date) -> TimeInterval { return other._time - _time }
  public func advanced(by n: TimeInterval) -> Date { return addingTimeInterval(n) }
}

extension Date: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String { return _utcDescription }
  public var debugDescription: String { return _utcDescription }
  public func description(with locale: Locale?) -> String { return _utcDescription }
}

extension Date: Codable {
  // Encoded as its seconds since the reference date, as Apple's is.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    _time = try c.decode(Double.self)
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    try c.encode(_time)
  }
}

extension Date: _ObjectiveCBridgeable {
  public func _bridgeToObjectiveC() -> NSDate { return NSDate(timeIntervalSinceReferenceDate: _time) }
  public static func _forceBridgeFromObjectiveC(_ x: NSDate, result: inout Date?) {
    result = Date(timeIntervalSinceReferenceDate: x.timeIntervalSinceReferenceDate)
  }
  public static func _conditionallyBridgeFromObjectiveC(_ x: NSDate, result: inout Date?) -> Bool {
    result = Date(timeIntervalSinceReferenceDate: x.timeIntervalSinceReferenceDate)
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSDate?) -> Date {
    return Date(timeIntervalSinceReferenceDate: source?.timeIntervalSinceReferenceDate ?? 0)
  }
}
