// FormatStyle and the styles built on it: numbers (integers, floating
// point, percentages; precision, grouping, the locale's separators), lists
// ("a, b, and c"), and dates (Date.FormatStyle's date and time styles in
// the local time zone). Formatting follows ICU's output for the common
// locales closely enough for display; locales outside the separator table
// use the en_US separators.
import Darwin
import _StringProcessing

public protocol FormatStyle: Decodable, Encodable, Hashable {
  associatedtype FormatInput
  associatedtype FormatOutput
  func format(_ value: FormatInput) -> FormatOutput
  func locale(_ locale: Locale) -> Self
}
extension FormatStyle {
  public func locale(_ locale: Locale) -> Self { return self }
}

public protocol ParseStrategy: Decodable, Encodable, Hashable {
  associatedtype ParseInput
  associatedtype ParseOutput
  func parse(_ value: ParseInput) throws -> ParseOutput
}
public protocol ParseableFormatStyle: FormatStyle {
  associatedtype Strategy: ParseStrategy where Strategy.ParseInput == FormatOutput, Strategy.ParseOutput == FormatInput
  var parseStrategy: Strategy { get }
}

internal struct _FormatError: Error, CustomStringConvertible {
  let description: String
}

// ---- the locale's separators ----

extension Locale {
  internal var _language: String { return languageCode ?? "en" }
  public var decimalSeparator: String? {
    switch _language {
    case "de", "fr", "es", "it", "pt", "nl", "ru", "sv", "nb", "da", "fi", "pl", "cs", "tr", "id", "uk": return ","
    default: return "."
    }
  }
  public var groupingSeparator: String? {
    switch _language {
    case "de", "es", "it", "pt", "nl", "da", "tr", "id": return "."
    case "fr": return "\u{202F}"
    case "ru", "sv", "nb", "fi", "pl", "cs", "uk": return "\u{00A0}"
    default: return ","
    }
  }
}

// ---- numbers ----

public enum NumberFormatStyleConfiguration {
  public struct Precision: Codable, Hashable, Sendable {
    internal var minFraction: Int? = nil
    internal var maxFraction: Int? = nil
    internal var minSignificant: Int? = nil
    internal var maxSignificant: Int? = nil
    internal var minInteger: Int? = nil

    public static func significantDigits<R: RangeExpression>(_ limits: R) -> Precision where R.Bound == Int {
      let r = limits.relative(to: 1..<18)
      return Precision(minSignificant: r.lowerBound, maxSignificant: r.upperBound - 1)
    }
    public static func significantDigits(_ digits: Int) -> Precision {
      return Precision(minSignificant: digits, maxSignificant: digits)
    }
    public static func fractionLength<R: RangeExpression>(_ limits: R) -> Precision where R.Bound == Int {
      let r = limits.relative(to: 0..<16)
      return Precision(minFraction: r.lowerBound, maxFraction: r.upperBound - 1)
    }
    public static func fractionLength(_ length: Int) -> Precision {
      return Precision(minFraction: length, maxFraction: length)
    }
    public static func integerLength(_ length: Int) -> Precision { return Precision(minInteger: length) }
  }

  public struct Grouping: Codable, Hashable, Sendable {
    internal let on: Bool
    public static var automatic: Grouping { return Grouping(on: true) }
    public static var never: Grouping { return Grouping(on: false) }
  }

  public enum SignDisplayStrategy: Int, Codable, Hashable, Sendable { case automatic, never, always }
}

/// Digits of |value| with `fraction` digits after the point, rounded.
internal func _digits(_ value: Double, fraction: Int) -> (integer: String, fraction: String) {
  var buf = [CChar](repeating: 0, count: 400)
  let fmt = "%.\(Swift.max(0, Swift.min(fraction, 17)))f"
  _ = buf.withUnsafeMutableBufferPointer { p in
    withVaList([Swift.abs(value)]) { vsnprintf(p.baseAddress!, 400, fmt, $0) }
  }
  let s = String(cString: buf)
  if let dot = s.firstIndex(of: ".") {
    return (String(s[..<dot]), String(s[s.index(after: dot)...]))
  }
  return (s, "")
}

/// A number as the style shows it: grouping, precision, separators.
internal func _formatNumber(_ value: Double, precision: NumberFormatStyleConfiguration.Precision?,
                            grouping: Bool, locale: Locale, defaultMaxFraction: Int, suffix: String = "") -> String {
  if value.isNaN { return "NaN" }
  if value.isInfinite { return value < 0 ? "-∞" : "∞" }
  var minF = precision?.minFraction ?? 0
  var maxF = precision?.maxFraction ?? defaultMaxFraction
  if let maxS = precision?.maxSignificant {
    // Significant digits: as many fraction digits as the magnitude leaves.
    let mag = value == 0 ? 1 : Int(log10(Swift.abs(value)).rounded(.down)) + 1
    maxF = Swift.max(0, maxS - mag)
    minF = Swift.max(0, (precision?.minSignificant ?? 1) - mag)
  }
  var (int, frac) = _digits(value, fraction: maxF)
  while frac.count > minF, frac.last == "0" { frac.removeLast() }
  if let minI = precision?.minInteger, int.count < minI {
    int = String(repeating: "0", count: minI - int.count) + int
  }
  if grouping, int.count > 3 {
    let sep = locale.groupingSeparator ?? ","
    var out = ""
    for (i, c) in int.enumerated() {
      if i > 0 && (int.count - i) % 3 == 0 { out += sep }
      out.append(c)
    }
    int = out
  }
  let negative = value < 0 && (int.contains { $0 != "0" && $0 != "," && $0 != "." } || frac.contains { $0 != "0" })
  let body = frac.isEmpty ? int : int + (locale.decimalSeparator ?? ".") + frac
  return (negative ? "-" : "") + body + suffix
}

/// A number written with the locale's separators, back to a Double.
internal func _parseNumber(_ s: String, locale: Locale, lenient: Bool) -> Double? {
  var t = s.trimmingCharacters(in: .whitespaces)
  let group = locale.groupingSeparator ?? ",", dec = locale.decimalSeparator ?? "."
  t = t.replacingOccurrences(of: group, with: "")
  if dec != "." { t = t.replacingOccurrences(of: dec, with: ".") }
  if lenient { t = t.replacingOccurrences(of: " ", with: "") }
  var percent = false
  if t.hasSuffix("%") { percent = true; t.removeLast() }
  guard let v = Double(t) else { return nil }
  return percent ? v / 100 : v
}

public struct IntegerFormatStyle<Value: BinaryInteger>: FormatStyle, Sendable {
  public var locale: Locale
  internal var _precision: NumberFormatStyleConfiguration.Precision? = nil
  internal var _grouping = true

  public init(locale: Locale = .autoupdatingCurrent) { self.locale = locale }

  public func format(_ value: Value) -> String {
    return _formatNumber(Double(value), precision: _precision, grouping: _grouping, locale: locale, defaultMaxFraction: 0)
  }
  public func precision(_ p: NumberFormatStyleConfiguration.Precision) -> IntegerFormatStyle {
    var s = self
    s._precision = p
    return s
  }
  public func grouping(_ g: NumberFormatStyleConfiguration.Grouping) -> IntegerFormatStyle {
    var s = self
    s._grouping = g.on
    return s
  }
  public func locale(_ locale: Locale) -> IntegerFormatStyle {
    var s = self
    s.locale = locale
    return s
  }

  public struct Percent: FormatStyle, Sendable {
    public var locale: Locale
    public init(locale: Locale = .autoupdatingCurrent) { self.locale = locale }
    public func format(_ value: Value) -> String {
      return _formatNumber(Double(value), precision: nil, grouping: true, locale: locale, defaultMaxFraction: 0, suffix: "%")
    }
    public func locale(_ locale: Locale) -> Percent { return Percent(locale: locale) }
  }
}

public struct FloatingPointFormatStyle<Value: BinaryFloatingPoint>: FormatStyle, Sendable {
  public var locale: Locale
  internal var _precision: NumberFormatStyleConfiguration.Precision? = nil
  internal var _grouping = true

  public init(locale: Locale = .autoupdatingCurrent) { self.locale = locale }

  public func format(_ value: Value) -> String {
    return _formatNumber(Double(value), precision: _precision, grouping: _grouping, locale: locale, defaultMaxFraction: 3)
  }
  public func precision(_ p: NumberFormatStyleConfiguration.Precision) -> FloatingPointFormatStyle {
    var s = self
    s._precision = p
    return s
  }
  public func grouping(_ g: NumberFormatStyleConfiguration.Grouping) -> FloatingPointFormatStyle {
    var s = self
    s._grouping = g.on
    return s
  }
  public func locale(_ locale: Locale) -> FloatingPointFormatStyle {
    var s = self
    s.locale = locale
    return s
  }

  public struct Percent: FormatStyle, Sendable {
    public var locale: Locale
    internal var _precision: NumberFormatStyleConfiguration.Precision? = nil
    public init(locale: Locale = .autoupdatingCurrent) { self.locale = locale }
    public func format(_ value: Value) -> String {
      return _formatNumber(Double(value) * 100, precision: _precision, grouping: true, locale: locale,
                           defaultMaxFraction: 3, suffix: "%")
    }
    public func precision(_ p: NumberFormatStyleConfiguration.Precision) -> Percent {
      var s = self
      s._precision = p
      return s
    }
    public func locale(_ locale: Locale) -> Percent {
      var s = self
      s.locale = locale
      return s
    }
  }
}

extension FloatingPointFormatStyle: ParseableFormatStyle {
  public struct Strategy: ParseStrategy, Sendable {
    public let locale: Locale
    public let lenient: Bool
    public func parse(_ value: String) throws -> Value {
      guard let v = _parseNumber(value, locale: locale, lenient: lenient) else {
        throw _FormatError(description: "Cannot parse \(value) as a number")
      }
      return Value(v)
    }
  }
  public var parseStrategy: Strategy { return Strategy(locale: locale, lenient: true) }
}

/// A localized number inside a regex: digits with the locale's grouping and
/// decimal separators, giving the value.
extension FloatingPointFormatStyle: RegexComponent {
  public var regex: Regex<Value> {
    let group = locale.groupingSeparator ?? ",", dec = locale.decimalSeparator ?? "."
    func esc(_ s: String) -> String { return s.map { "\\" + String($0) }.joined() }
    let pattern = "[-+]?[0-9](?:[0-9]|\(esc(group)))*(?:\(esc(dec))[0-9]+)?"
    let loc = locale
    return Regex(_bittenPattern: pattern) { text in _parseNumber(String(text), locale: loc, lenient: true).map { Value($0) } }
  }
}

extension RegexComponent where Self == FloatingPointFormatStyle<Double> {
  public static func localizedDouble(locale: Locale) -> FloatingPointFormatStyle<Double> {
    return FloatingPointFormatStyle(locale: locale)
  }
}

extension FormatStyle where Self == FloatingPointFormatStyle<Double> {
  public static var number: FloatingPointFormatStyle<Double> { return FloatingPointFormatStyle() }
}
extension FormatStyle where Self == FloatingPointFormatStyle<Double>.Percent {
  public static var percent: FloatingPointFormatStyle<Double>.Percent { return .init() }
}
extension FormatStyle where Self == IntegerFormatStyle<Int> {
  public static var number: IntegerFormatStyle<Int> { return IntegerFormatStyle() }
}
extension FormatStyle where Self == IntegerFormatStyle<Int>.Percent {
  public static var percent: IntegerFormatStyle<Int>.Percent { return .init() }
}

extension BinaryInteger {
  public func formatted() -> String { return IntegerFormatStyle<Self>().format(self) }
  public func formatted<S: FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == Self { return style.format(self) }
}
extension BinaryFloatingPoint {
  public func formatted() -> String { return FloatingPointFormatStyle<Self>().format(self) }
  public func formatted<S: FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == Self { return style.format(self) }
  public init(_ value: String, format: FloatingPointFormatStyle<Self>, lenient: Bool = true) throws {
    guard let v = _parseNumber(value, locale: format.locale, lenient: lenient) else {
      throw _FormatError(description: "Cannot parse \(value) as a number")
    }
    self.init(v)
  }
}

// ---- lists ----

public struct StringStyle: FormatStyle, Sendable {
  public init() {}
  public func format(_ value: String) -> String { return value }
}

public struct ListFormatStyle<Style: FormatStyle, Base: Sequence>: FormatStyle
  where Style.FormatInput == Base.Element, Style.FormatOutput == String
{
  public enum Width: Int, Codable, Hashable, Sendable { case standard, short, narrow }
  public enum ListType: Int, Codable, Hashable, Sendable { case and, or }

  public var width: Width
  public var listType: ListType
  public var locale: Locale
  internal let memberStyle: Style

  public init(memberStyle: Style) {
    self.memberStyle = memberStyle
    width = .standard
    listType = .and
    locale = .autoupdatingCurrent
  }

  public func format(_ value: Base) -> String {
    let items = value.map { memberStyle.format($0) }
    let word = listType == .and ? (width == .standard ? "and" : width == .short ? "&" : "") : "or"
    switch items.count {
    case 0: return ""
    case 1: return items[0]
    case 2: return word.isEmpty ? "\(items[0]), \(items[1])" : "\(items[0]) \(word) \(items[1])"
    default:
      let head = items.dropLast().joined(separator: ", ")
      return word.isEmpty ? "\(head), \(items.last!)" : "\(head), \(word) \(items.last!)"
    }
  }
  public func locale(_ locale: Locale) -> ListFormatStyle {
    var s = self
    s.locale = locale
    return s
  }

  // FormatStyle is Codable and Hashable: lists compare and code by their settings.
  public static func == (a: ListFormatStyle, b: ListFormatStyle) -> Bool {
    return a.width == b.width && a.listType == b.listType && a.locale == b.locale
  }
  public func hash(into h: inout Hasher) {
    h.combine(width)
    h.combine(listType)
  }
  enum CodingKeys: String, CodingKey { case width, listType }
  public init(from decoder: Decoder) throws {
    throw _FormatError(description: "ListFormatStyle cannot be decoded here")
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(width, forKey: .width)
    try c.encode(listType, forKey: .listType)
  }
}

extension FormatStyle {
  public static func list<Base: Sequence>(type: ListFormatStyle<StringStyle, Base>.ListType,
                                          width: ListFormatStyle<StringStyle, Base>.Width = .standard)
    -> ListFormatStyle<StringStyle, Base> where Self == ListFormatStyle<StringStyle, Base>, Base.Element == String
  {
    var s = ListFormatStyle<StringStyle, Base>(memberStyle: StringStyle())
    s.listType = type
    s.width = width
    return s
  }
  public static func list<MemberStyle: FormatStyle, Base: Sequence>(memberStyle: MemberStyle,
                                                                   type: ListFormatStyle<MemberStyle, Base>.ListType,
                                                                   width: ListFormatStyle<MemberStyle, Base>.Width = .standard)
    -> ListFormatStyle<MemberStyle, Base> where Self == ListFormatStyle<MemberStyle, Base>
  {
    var s = ListFormatStyle<MemberStyle, Base>(memberStyle: memberStyle)
    s.listType = type
    s.width = width
    return s
  }
}

extension Sequence {
  public func formatted<S: FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == Self {
    return style.format(self)
  }
}
extension Sequence where Element == String {
  public func formatted() -> String {
    return ListFormatStyle<StringStyle, Self>(memberStyle: StringStyle()).format(self)
  }
}

// ---- dates ----

extension Date {
  public struct FormatStyle: Foundation.FormatStyle, Sendable {
    public struct DateStyle: Codable, Hashable, Sendable {
      internal let rawValue: Int
      public static var omitted: DateStyle { return DateStyle(rawValue: 0) }
      public static var numeric: DateStyle { return DateStyle(rawValue: 1) }
      public static var abbreviated: DateStyle { return DateStyle(rawValue: 2) }
      public static var long: DateStyle { return DateStyle(rawValue: 3) }
      public static var complete: DateStyle { return DateStyle(rawValue: 4) }
    }
    public struct TimeStyle: Codable, Hashable, Sendable {
      internal let rawValue: Int
      public static var omitted: TimeStyle { return TimeStyle(rawValue: 0) }
      public static var shortened: TimeStyle { return TimeStyle(rawValue: 1) }
      public static var standard: TimeStyle { return TimeStyle(rawValue: 2) }
      public static var complete: TimeStyle { return TimeStyle(rawValue: 3) }
    }

    public var date: DateStyle?
    public var time: TimeStyle?
    public var locale: Locale

    public init(date: DateStyle? = nil, time: TimeStyle? = nil, locale: Locale = .autoupdatingCurrent) {
      self.date = date
      self.time = time
      self.locale = locale
    }

    public func format(_ value: Date) -> String {
      let d = date ?? (time == nil ? .numeric : .omitted)
      let t = time ?? (date == nil ? .shortened : .omitted)
      return _formatDate(value, date: d, time: t)
    }
    public func locale(_ locale: Locale) -> FormatStyle {
      var s = self
      s.locale = locale
      return s
    }
  }

  public func formatted() -> String { return FormatStyle(date: .numeric, time: .shortened).format(self) }
  public func formatted(date: FormatStyle.DateStyle, time: FormatStyle.TimeStyle) -> String {
    return FormatStyle(date: date, time: time).format(self)
  }
  public func formatted<S: Foundation.FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == Date {
    return style.format(self)
  }
}

private let _monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                           "October", "November", "December"]
private let _dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

/// en_US's patterns, in the local time zone: "11/26/2026", "Nov 26, 2026",
/// "November 26, 2026", "Thursday, November 26, 2026"; "3:05 PM",
/// "3:05:09 PM", "3:05:09 PM GMT+1".
internal func _formatDate(_ value: Date, date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
  var t = time_t(value.timeIntervalSince1970.rounded(.down))
  var tmv = tm()
  localtime_r(&t, &tmv)
  let year = Int(tmv.tm_year) + 1900, month = Int(tmv.tm_mon), day = Int(tmv.tm_mday)
  var parts: [String] = []
  switch date.rawValue {
  case 1: parts.append("\(month + 1)/\(day)/\(year)")
  case 2: parts.append("\(_monthNames[month].prefix(3)) \(day), \(year)")
  case 3: parts.append("\(_monthNames[month]) \(day), \(year)")
  case 4: parts.append("\(_dayNames[Int(tmv.tm_wday)]), \(_monthNames[month]) \(day), \(year)")
  default: break
  }
  if time.rawValue > 0 {
    let h24 = Int(tmv.tm_hour), h = h24 % 12 == 0 ? 12 : h24 % 12
    let mm = Int(tmv.tm_min) < 10 ? "0\(tmv.tm_min)" : "\(tmv.tm_min)"
    let ss = Int(tmv.tm_sec) < 10 ? "0\(tmv.tm_sec)" : "\(tmv.tm_sec)"
    var s = time.rawValue == 1 ? "\(h):\(mm)" : "\(h):\(mm):\(ss)"
    s += h24 < 12 ? "\u{202F}AM" : "\u{202F}PM"
    if time.rawValue == 3 {
      let off = Int(tmv.tm_gmtoff) / 60
      s += off == 0 ? " GMT" : " GMT\(off < 0 ? "-" : "+")\(Swift.abs(off) / 60)\(Swift.abs(off) % 60 == 0 ? "" : ":\(Swift.abs(off) % 60)")"
    }
    parts.append(s)
  }
  return parts.joined(separator: ", ")
}

// ---- ISO 8601 ----

extension Date {
  /// "2026-11-26T05:04:03Z": the date, time and zone with the chosen
  /// separators; parsing takes the same shape.
  public struct ISO8601FormatStyle: Foundation.FormatStyle, Sendable {
    public enum DateSeparator: String, Codable, Hashable, Sendable { case dash = "-", omitted = "" }
    public enum DateTimeSeparator: String, Codable, Hashable, Sendable { case standard = "'T'", space = "' '" }
    public enum TimeSeparator: String, Codable, Hashable, Sendable { case colon = ":", omitted = "" }
    public enum TimeZoneSeparator: String, Codable, Hashable, Sendable { case colon = ":", omitted = "" }

    public var dateSeparator: DateSeparator
    public var dateTimeSeparator: DateTimeSeparator
    public var timeSeparator: TimeSeparator
    public var timeZoneSeparator: TimeZoneSeparator
    public var includingFractionalSeconds: Bool
    public var timeZone: TimeZone

    public init(dateSeparator: DateSeparator = .dash, dateTimeSeparator: DateTimeSeparator = .standard,
                timeSeparator: TimeSeparator = .colon, timeZoneSeparator: TimeZoneSeparator = .omitted,
                includingFractionalSeconds: Bool = false, timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) {
      self.dateSeparator = dateSeparator
      self.dateTimeSeparator = dateTimeSeparator
      self.timeSeparator = timeSeparator
      self.timeZoneSeparator = timeZoneSeparator
      self.includingFractionalSeconds = includingFractionalSeconds
      self.timeZone = timeZone
    }

    internal var _dateTimeSeparator: String { return dateTimeSeparator == .standard ? "T" : " " }

    public func format(_ value: Date) -> String {
      let offset = timeZone.secondsFromGMT(for: value)
      let t = value.timeIntervalSince1970 + Double(offset)
      var secs = time_t(t.rounded(.down))
      var tmv = tm()
      gmtime_r(&secs, &tmv)
      func two(_ v: Int32) -> String { return v < 10 ? "0\(v)" : "\(v)" }
      let ds = dateSeparator.rawValue, ts = timeSeparator.rawValue
      var s = "\(Int(tmv.tm_year) + 1900)\(ds)\(two(tmv.tm_mon + 1))\(ds)\(two(tmv.tm_mday))"
      s += _dateTimeSeparator
      s += "\(two(tmv.tm_hour))\(ts)\(two(tmv.tm_min))\(ts)\(two(tmv.tm_sec))"
      if includingFractionalSeconds {
        let ms = Int(((t - t.rounded(.down)) * 1000).rounded()) % 1000
        s += "." + (ms < 10 ? "00\(ms)" : ms < 100 ? "0\(ms)" : "\(ms)")
      }
      if offset == 0 {
        s += "Z"
      } else {
        let a = Swift.abs(offset), h = a / 3600, m = (a % 3600) / 60
        s += (offset < 0 ? "-" : "+") + (h < 10 ? "0\(h)" : "\(h)") + timeZoneSeparator.rawValue + (m < 10 ? "0\(m)" : "\(m)")
      }
      return s
    }

    /// Dates in this shape (separators optional where they may be omitted;
    /// Z or an offset; fractional seconds when present).
    public func parse(_ value: String) throws -> Date {
      let chars = Array(value)
      var i = 0
      func number(_ n: Int) -> Int? {
        guard i + n <= chars.count else { return nil }
        var v = 0
        for c in chars[i..<(i + n)] {
          guard let d = c.wholeNumberValue else { return nil }
          v = v * 10 + d
        }
        i += n
        return v
      }
      func skip(_ set: String) { if i < chars.count, set.contains(chars[i]) { i += 1 } }
      guard let y = number(4) else { throw _FormatError(description: "Cannot parse \(value) as an ISO 8601 date") }
      skip("-")
      guard let mo = number(2) else { throw _FormatError(description: "Cannot parse \(value)") }
      skip("-")
      guard let d = number(2) else { throw _FormatError(description: "Cannot parse \(value)") }
      var h = 0, mi = 0, se = 0
      var frac = 0.0
      var offset = 0
      if i < chars.count, chars[i] == "T" || chars[i] == " " || chars[i] == "t" {
        i += 1
        guard let hh = number(2) else { throw _FormatError(description: "Cannot parse \(value)") }
        skip(":")
        guard let mm = number(2) else { throw _FormatError(description: "Cannot parse \(value)") }
        h = hh
        mi = mm
        skip(":")
        if let ss = number(2) { se = ss }
        if i < chars.count, chars[i] == "." || chars[i] == "," {
          i += 1
          var scale = 0.1
          while i < chars.count, let dgt = chars[i].wholeNumberValue {
            frac += Double(dgt) * scale
            scale /= 10
            i += 1
          }
        }
        if i < chars.count {
          if chars[i] == "Z" || chars[i] == "z" {
            i += 1
          } else if chars[i] == "+" || chars[i] == "-" {
            let neg = chars[i] == "-"
            i += 1
            guard let oh = number(2) else { throw _FormatError(description: "Cannot parse \(value)") }
            skip(":")
            let om = number(2) ?? 0
            offset = (oh * 3600 + om * 60) * (neg ? -1 : 1)
          }
        } else {
          offset = timeZone.secondsFromGMT()
        }
      }
      guard i == chars.count, (1...12).contains(mo), (1...31).contains(d), h < 25, mi < 60, se < 61 else {
        throw _FormatError(description: "Cannot parse \(value) as an ISO 8601 date")
      }
      var tmv = tm()
      tmv.tm_year = Int32(y - 1900)
      tmv.tm_mon = Int32(mo - 1)
      tmv.tm_mday = Int32(d)
      tmv.tm_hour = Int32(h)
      tmv.tm_min = Int32(mi)
      tmv.tm_sec = Int32(se)
      let utc = timegm(&tmv)
      return Date(timeIntervalSince1970: Double(utc) - Double(offset) + frac)
    }
  }
}

extension Date.ISO8601FormatStyle: ParseStrategy {
  public typealias ParseInput = String
  public typealias ParseOutput = Date
}

extension FormatStyle where Self == Date.ISO8601FormatStyle {
  public static var iso8601: Date.ISO8601FormatStyle { return Date.ISO8601FormatStyle() }
}
