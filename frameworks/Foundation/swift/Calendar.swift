// Calendar and DateComponents: the Gregorian calendar (ISO 8601's too,
// which differs only in the first weekday and minimum days in the first
// week), in a time zone, by civil-date arithmetic on days since the epoch.

public struct Calendar: Hashable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  public enum Identifier: Hashable, Codable, Sendable {
    case gregorian, buddhist, chinese, coptic, ethiopicAmeteMihret, ethiopicAmeteAlem, hebrew, iso8601, indian,
      islamic, islamicCivil, japanese, persian, republicOfChina, islamicTabular, islamicUmmAlQura
  }

  public enum Component: Hashable, Sendable {
    case era, year, month, day, hour, minute, second, weekday, weekdayOrdinal, quarter, weekOfMonth, weekOfYear,
      yearForWeekOfYear, nanosecond, calendar, timeZone, isLeapMonth, dayOfYear, isRepeatedDay
  }

  public enum SearchDirection: Hashable, Sendable { case forward, backward }
  public enum RepeatedTimePolicy: Hashable, Sendable { case first, last }
  public enum MatchingPolicy: Hashable, Sendable { case nextTime, nextTimePreservingSmallerComponents, previousTimePreservingSmallerComponents, strict }

  public let identifier: Identifier
  public var timeZone: TimeZone
  public var locale: Locale?
  public var firstWeekday: Int
  public var minimumDaysInFirstWeek: Int

  public init(identifier: Identifier) {
    self.identifier = identifier
    timeZone = TimeZone.current
    locale = Locale.current
    firstWeekday = identifier == .iso8601 ? 2 : 1
    minimumDaysInFirstWeek = identifier == .iso8601 ? 4 : 1
  }
  public static var current: Calendar { return Calendar(identifier: .gregorian) }
  public static var autoupdatingCurrent: Calendar { return current }

  public var description: String { return "\(identifier) (\(timeZone.identifier))" }
  public var debugDescription: String { return description }

  public var eraSymbols: [String] { return ["BC", "AD"] }
  public var monthSymbols: [String] {
    return ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
            "November", "December"]
  }
  public var shortMonthSymbols: [String] { return monthSymbols.map { String($0.prefix(3)) } }
  public var veryShortMonthSymbols: [String] { return monthSymbols.map { String($0.prefix(1)) } }
  public var weekdaySymbols: [String] {
    return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
  }
  public var shortWeekdaySymbols: [String] { return weekdaySymbols.map { String($0.prefix(3)) } }
  public var veryShortWeekdaySymbols: [String] { return weekdaySymbols.map { String($0.prefix(1)) } }
  public var amSymbol: String { return "AM" }
  public var pmSymbol: String { return "PM" }

  // MARK: civil dates

  /// Days since 1970-01-01 for a proleptic Gregorian date (month 1...12).
  internal static func days(year y0: Int, month m: Int, day d: Int) -> Int {
    let y = m <= 2 ? y0 - 1 : y0
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let mp = (m + 9) % 12
    let doy = (153 * mp + 2) / 5 + d - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe - 719468
  }
  /// The Gregorian (year, month, day) of a count of days since 1970-01-01.
  internal static func civil(_ z0: Int) -> (year: Int, month: Int, day: Int) {
    let z = z0 + 719468
    let era = (z >= 0 ? z : z - 146096) / 146097
    let doe = z - era * 146097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    let y = yoe + era * 400
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let d = doy - (153 * mp + 2) / 5 + 1
    let m = mp < 10 ? mp + 3 : mp - 9
    return (m <= 2 ? y + 1 : y, m, d)
  }
  internal static func isLeap(_ y: Int) -> Bool { return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }
  internal static func daysIn(year: Int, month: Int) -> Int {
    switch month {
    case 2: return isLeap(year) ? 29 : 28
    case 4, 6, 9, 11: return 30
    default: return 31
    }
  }

  /// Local seconds since 1970 for a date in this calendar's zone.
  private func local(_ date: Date) -> Double {
    return date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
  }
  /// The date for local seconds since 1970 (zone offsets near transitions
  /// are taken at the result).
  private func date(local seconds: Double) -> Date {
    var guess = Date(timeIntervalSince1970: seconds - Double(timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: seconds))))
    let off = timeZone.secondsFromGMT(for: guess)
    guess = Date(timeIntervalSince1970: seconds - Double(off))
    return guess
  }

  private struct Fields {
    var year = 0, month = 0, day = 0, hour = 0, minute = 0, second = 0, nanosecond = 0, weekday = 0, dayOfYear = 0
  }
  private func fields(_ date: Date) -> Fields {
    let t = local(date)
    let secs = t.rounded(.down)
    let dayIndex = Int((secs / 86400).rounded(.down))
    let sod = Int(secs) - dayIndex * 86400
    let c = Calendar.civil(dayIndex)
    var f = Fields()
    f.year = c.year
    f.month = c.month
    f.day = c.day
    f.hour = sod / 3600
    f.minute = sod / 60 % 60
    f.second = sod % 60
    f.nanosecond = Int(((t - secs) * 1e9).rounded())
    // 1970-01-01 was a Thursday (weekday 5, Sunday = 1).
    f.weekday = ((dayIndex % 7) + 7 + 4) % 7 + 1
    f.dayOfYear = dayIndex - Calendar.days(year: c.year, month: 1, day: 1) + 1
    return f
  }

  // MARK: components

  public func component(_ component: Component, from date: Date) -> Int {
    return dateComponents([component], from: date).value(for: component) ?? 0
  }
  public func dateComponents(_ components: Set<Component>, from date: Date) -> DateComponents {
    let f = fields(date)
    var dc = DateComponents()
    for c in components {
      switch c {
      case .era: dc.era = f.year > 0 ? 1 : 0
      case .year: dc.year = f.year
      case .month: dc.month = f.month
      case .day: dc.day = f.day
      case .hour: dc.hour = f.hour
      case .minute: dc.minute = f.minute
      case .second: dc.second = f.second
      case .nanosecond: dc.nanosecond = f.nanosecond
      case .weekday: dc.weekday = f.weekday
      case .weekdayOrdinal: dc.weekdayOrdinal = (f.day - 1) / 7 + 1
      case .quarter: dc.quarter = (f.month - 1) / 3 + 1
      case .weekOfMonth: dc.weekOfMonth = weekOf(day: f.day, weekday: f.weekday)
      case .weekOfYear: dc.weekOfYear = weekOf(day: f.dayOfYear, weekday: f.weekday)
      case .yearForWeekOfYear: dc.yearForWeekOfYear = f.year
      case .dayOfYear: dc.dayOfYear = f.dayOfYear
      case .calendar: dc.calendar = self
      case .timeZone: dc.timeZone = timeZone
      case .isLeapMonth: dc.isLeapMonth = false
      case .isRepeatedDay: break
      }
    }
    return dc
  }
  /// The week (1-based) of a day `n` days into a period, given its weekday.
  private func weekOf(day n: Int, weekday: Int) -> Int {
    let firstWeekdayOfPeriod = ((weekday - 1 - (n - 1)) % 7 + 7) % 7 + 1
    let offset = (firstWeekdayOfPeriod - firstWeekday + 7) % 7
    return (n - 1 + offset) / 7 + 1
  }
  public func dateComponents(in timeZone: TimeZone, from date: Date) -> DateComponents {
    var c = self
    c.timeZone = timeZone
    var dc = c.dateComponents([.era, .year, .month, .day, .hour, .minute, .second, .nanosecond, .weekday,
                               .weekdayOrdinal, .quarter, .weekOfMonth, .weekOfYear, .yearForWeekOfYear, .dayOfYear],
                              from: date)
    dc.calendar = c
    dc.timeZone = timeZone
    return dc
  }
  public func dateComponents(_ components: Set<Component>, from start: Date, to end: Date) -> DateComponents {
    var dc = DateComponents()
    var cursor = start
    let ordered: [Component] = [.era, .year, .month, .weekOfYear, .weekOfMonth, .day, .hour, .minute, .second, .nanosecond]
    for c in ordered where components.contains(c) {
      switch c {
      case .year, .month:
        var n = 0
        let forward = end >= cursor
        while let next = date(byAdding: c, value: forward ? n + 1 : n - 1, to: cursor),
              forward ? next <= end : next >= end {
          n += forward ? 1 : -1
          if abs(n) > 100000 { break }
        }
        if c == .year { dc.year = n } else { dc.month = n }
        cursor = date(byAdding: c, value: n, to: cursor) ?? cursor
      case .weekOfYear, .weekOfMonth:
        let n = Int((end.timeIntervalSince(cursor) / 604800).rounded(.towardZero))
        if c == .weekOfYear { dc.weekOfYear = n } else { dc.weekOfMonth = n }
        cursor = cursor.addingTimeInterval(Double(n) * 604800)
      case .day:
        let n = Int((end.timeIntervalSince(cursor) / 86400).rounded(.towardZero))
        dc.day = n
        cursor = date(byAdding: .day, value: n, to: cursor) ?? cursor
      case .hour:
        let n = Int((end.timeIntervalSince(cursor) / 3600).rounded(.towardZero))
        dc.hour = n
        cursor = cursor.addingTimeInterval(Double(n) * 3600)
      case .minute:
        let n = Int((end.timeIntervalSince(cursor) / 60).rounded(.towardZero))
        dc.minute = n
        cursor = cursor.addingTimeInterval(Double(n) * 60)
      case .second:
        let n = Int(end.timeIntervalSince(cursor).rounded(.towardZero))
        dc.second = n
        cursor = cursor.addingTimeInterval(Double(n))
      case .nanosecond:
        dc.nanosecond = Int((end.timeIntervalSince(cursor) * 1e9).rounded(.towardZero))
      default: break
      }
    }
    return dc
  }

  public func date(from components: DateComponents) -> Date? {
    var c = self
    if let tz = components.timeZone { c.timeZone = tz }
    var year = components.year ?? 2001
    var month = components.month ?? 1
    // Normalize months outside 1...12 into years.
    year += (month - 1 >= 0 ? (month - 1) / 12 : (month - 12) / 12)
    month = ((month - 1) % 12 + 12) % 12 + 1
    var dayIndex: Int
    if let doy = components.dayOfYear, components.day == nil {
      dayIndex = Calendar.days(year: year, month: 1, day: 1) + doy - 1
    } else {
      dayIndex = Calendar.days(year: year, month: month, day: 1) + (components.day ?? 1) - 1
    }
    if let wd = components.weekday, components.day == nil {
      // The weekdayOrdinal-th (default first) `wd` of the month.
      let firstWeekday = ((dayIndex % 7) + 7 + 4) % 7 + 1
      let ordinal = components.weekdayOrdinal ?? 1
      dayIndex += (wd - firstWeekday + 7) % 7 + (ordinal - 1) * 7
    }
    let seconds = Double(dayIndex) * 86400 + Double(components.hour ?? 0) * 3600 + Double(components.minute ?? 0) * 60 +
      Double(components.second ?? 0) + Double(components.nanosecond ?? 0) / 1e9
    return c.date(local: seconds)
  }

  public func startOfDay(for date: Date) -> Date {
    let f = fields(date)
    return self.date(local: Double(Calendar.days(year: f.year, month: f.month, day: f.day)) * 86400)
  }

  // MARK: arithmetic

  public func date(byAdding component: Component, value: Int, to date: Date, wrappingComponents: Bool = false) -> Date? {
    var dc = DateComponents()
    dc.setValue(value, for: component)
    return self.date(byAdding: dc, to: date, wrappingComponents: wrappingComponents)
  }
  public func date(byAdding components: DateComponents, to date: Date, wrappingComponents: Bool = false) -> Date? {
    var f = fields(date)
    if components.era == nil, components.year == nil, components.month == nil, components.day == nil,
       components.weekOfYear == nil, components.weekOfMonth == nil, components.weekday == nil {
      // Only time units: absolute seconds.
      let secs = Double(components.hour ?? 0) * 3600 + Double(components.minute ?? 0) * 60 +
        Double(components.second ?? 0) + Double(components.nanosecond ?? 0) / 1e9
      return date.addingTimeInterval(secs)
    }
    var months = f.month - 1 + (components.month ?? 0) + 12 * (components.year ?? 0)
    f.year += months >= 0 ? months / 12 : (months - 11) / 12
    months = (months % 12 + 12) % 12
    f.month = months + 1
    f.day = min(f.day, Calendar.daysIn(year: f.year, month: f.month))
    var dayIndex = Calendar.days(year: f.year, month: f.month, day: f.day)
    dayIndex += (components.day ?? 0) + 7 * ((components.weekOfYear ?? 0) + (components.weekOfMonth ?? 0)) +
      (components.weekday ?? 0)
    let seconds = Double(dayIndex) * 86400 + Double(f.hour) * 3600 + Double(f.minute) * 60 + Double(f.second) +
      Double(f.nanosecond) / 1e9 + Double(components.hour ?? 0) * 3600 + Double(components.minute ?? 0) * 60 +
      Double(components.second ?? 0) + Double(components.nanosecond ?? 0) / 1e9
    return self.date(local: seconds)
  }

  public func isDate(_ a: Date, inSameDayAs b: Date) -> Bool { return startOfDay(for: a) == startOfDay(for: b) }
  public func isDateInToday(_ date: Date) -> Bool { return isDate(date, inSameDayAs: Date()) }
  public func isDateInYesterday(_ date: Date) -> Bool {
    return self.date(byAdding: .day, value: 1, to: date).map { isDateInToday($0) } ?? false
  }
  public func isDateInTomorrow(_ date: Date) -> Bool {
    return self.date(byAdding: .day, value: -1, to: date).map { isDateInToday($0) } ?? false
  }
  public func isDateInWeekend(_ date: Date) -> Bool {
    let w = component(.weekday, from: date)
    return w == 1 || w == 7
  }
  public func isDate(_ a: Date, equalTo b: Date, toGranularity component: Component) -> Bool {
    return compare(a, to: b, toGranularity: component) == .orderedSame
  }
  public func compare(_ a: Date, to b: Date, toGranularity component: Component) -> ComparisonResult {
    let units: [Component]
    switch component {
    case .era, .year: units = [.year]
    case .month, .quarter: units = [.year, .month]
    case .day, .weekday, .dayOfYear: units = [.year, .month, .day]
    case .hour: units = [.year, .month, .day, .hour]
    case .minute: units = [.year, .month, .day, .hour, .minute]
    case .second: units = [.year, .month, .day, .hour, .minute, .second]
    case .weekOfYear, .weekOfMonth, .yearForWeekOfYear:
      let sa = startOfWeek(a), sb = startOfWeek(b)
      return sa == sb ? .orderedSame : (sa < sb ? .orderedAscending : .orderedDescending)
    default: return a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
    }
    let ca = dateComponents(Set(units), from: a), cb = dateComponents(Set(units), from: b)
    for u in units {
      let x = ca.value(for: u) ?? 0, y = cb.value(for: u) ?? 0
      if x != y { return x < y ? .orderedAscending : .orderedDescending }
    }
    return .orderedSame
  }
  private func startOfWeek(_ date: Date) -> Date {
    let w = component(.weekday, from: date)
    let back = (w - firstWeekday + 7) % 7
    return startOfDay(for: self.date(byAdding: .day, value: -back, to: date) ?? date)
  }

  public func range(of smaller: Component, in larger: Component, for date: Date) -> Range<Int>? {
    let f = fields(date)
    switch (smaller, larger) {
    case (.day, .month): return 1..<(Calendar.daysIn(year: f.year, month: f.month) + 1)
    case (.day, .year), (.dayOfYear, .year): return 1..<(Calendar.isLeap(f.year) ? 367 : 366)
    case (.month, .year): return 1..<13
    case (.hour, .day): return 0..<24
    case (.minute, .hour): return 0..<60
    case (.second, .minute): return 0..<60
    case (.weekday, .weekOfYear), (.weekday, .weekOfMonth): return 1..<8
    case (.weekOfMonth, .month):
      let last = Calendar.daysIn(year: f.year, month: f.month)
      let lastDate = self.date(from: DateComponents(year: f.year, month: f.month, day: last)) ?? date
      return 1..<(component(.weekOfMonth, from: lastDate) + 1)
    default: return nil
    }
  }
  public func minimumRange(of component: Component) -> Range<Int>? {
    switch component {
    case .month: return 1..<13
    case .day: return 1..<29
    case .hour: return 0..<24
    case .minute, .second: return 0..<60
    case .weekday: return 1..<8
    default: return nil
    }
  }
  public func maximumRange(of component: Component) -> Range<Int>? {
    if component == .day { return 1..<32 }
    return minimumRange(of: component)
  }

  public func dateInterval(of component: Component, for date: Date) -> DateInterval? {
    let f = fields(date)
    let start: Date?
    let end: Date?
    switch component {
    case .day:
      start = startOfDay(for: date)
      end = start.flatMap { self.date(byAdding: .day, value: 1, to: $0) }
    case .month:
      start = self.date(from: DateComponents(year: f.year, month: f.month, day: 1))
      end = start.flatMap { self.date(byAdding: .month, value: 1, to: $0) }
    case .year:
      start = self.date(from: DateComponents(year: f.year, month: 1, day: 1))
      end = start.flatMap { self.date(byAdding: .year, value: 1, to: $0) }
    case .weekOfYear, .weekOfMonth:
      start = startOfWeek(date)
      end = start.flatMap { self.date(byAdding: .day, value: 7, to: $0) }
    case .hour:
      start = self.date(from: DateComponents(year: f.year, month: f.month, day: f.day, hour: f.hour))
      end = start?.addingTimeInterval(3600)
    case .minute:
      start = self.date(from: DateComponents(year: f.year, month: f.month, day: f.day, hour: f.hour, minute: f.minute))
      end = start?.addingTimeInterval(60)
    default: return nil
    }
    guard let s = start, let e = end else { return nil }
    return DateInterval(start: s, end: e)
  }

  /// The next date after `start` whose components match `components`.
  public func nextDate(after start: Date, matching components: DateComponents, matchingPolicy: MatchingPolicy,
                       repeatedTimePolicy: RepeatedTimePolicy = .first, direction: SearchDirection = .forward) -> Date? {
    let step: Double = direction == .forward ? 60 : -60
    var t = start.addingTimeInterval(step)
    for _ in 0..<(366 * 24 * 60) {
      if self.date(t, matchesComponents: components) { return t }
      t = t.addingTimeInterval(step)
    }
    return nil
  }
  public func date(_ date: Date, matchesComponents components: DateComponents) -> Bool {
    let units: [Component] = [.year, .month, .day, .hour, .minute, .second, .weekday]
    let dc = dateComponents(Set(units), from: date)
    for u in units {
      if let want = components.value(for: u), dc.value(for: u) != want { return false }
    }
    return true
  }
  public func date(bySettingHour hour: Int, minute: Int, second: Int, of date: Date,
                   matchingPolicy: MatchingPolicy = .nextTime, repeatedTimePolicy: RepeatedTimePolicy = .first,
                   direction: SearchDirection = .forward) -> Date? {
    let f = fields(date)
    return self.date(from: DateComponents(year: f.year, month: f.month, day: f.day, hour: hour, minute: minute,
                                          second: second))
  }

  public static func == (a: Calendar, b: Calendar) -> Bool {
    return a.identifier == b.identifier && a.timeZone == b.timeZone && a.firstWeekday == b.firstWeekday &&
      a.minimumDaysInFirstWeek == b.minimumDaysInFirstWeek
  }
  public func hash(into h: inout Hasher) {
    h.combine(identifier)
    h.combine(timeZone)
    h.combine(firstWeekday)
  }
}

extension Calendar: Codable {
  private enum CodingKeys: String, CodingKey { case identifier, timeZone, firstWeekday, minimumDaysInFirstWeek }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(identifier: try c.decode(Identifier.self, forKey: .identifier))
    timeZone = try c.decodeIfPresent(TimeZone.self, forKey: .timeZone) ?? timeZone
    firstWeekday = try c.decodeIfPresent(Int.self, forKey: .firstWeekday) ?? firstWeekday
    minimumDaysInFirstWeek = try c.decodeIfPresent(Int.self, forKey: .minimumDaysInFirstWeek) ?? minimumDaysInFirstWeek
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(identifier, forKey: .identifier)
    try c.encode(timeZone, forKey: .timeZone)
    try c.encode(firstWeekday, forKey: .firstWeekday)
    try c.encode(minimumDaysInFirstWeek, forKey: .minimumDaysInFirstWeek)
  }
}

// MARK: - DateComponents

public struct DateComponents: Hashable, Equatable, Sendable, Codable, CustomStringConvertible {
  public var calendar: Calendar?
  public var timeZone: TimeZone?
  public var era: Int?
  public var year: Int?
  public var month: Int?
  public var day: Int?
  public var hour: Int?
  public var minute: Int?
  public var second: Int?
  public var nanosecond: Int?
  public var weekday: Int?
  public var weekdayOrdinal: Int?
  public var quarter: Int?
  public var weekOfMonth: Int?
  public var weekOfYear: Int?
  public var yearForWeekOfYear: Int?
  public var dayOfYear: Int?
  public var isLeapMonth: Bool?

  public init(calendar: Calendar? = nil, timeZone: TimeZone? = nil, era: Int? = nil, year: Int? = nil,
              month: Int? = nil, day: Int? = nil, hour: Int? = nil, minute: Int? = nil, second: Int? = nil,
              nanosecond: Int? = nil, weekday: Int? = nil, weekdayOrdinal: Int? = nil, quarter: Int? = nil,
              weekOfMonth: Int? = nil, weekOfYear: Int? = nil, yearForWeekOfYear: Int? = nil) {
    self.calendar = calendar
    self.timeZone = timeZone
    self.era = era
    self.year = year
    self.month = month
    self.day = day
    self.hour = hour
    self.minute = minute
    self.second = second
    self.nanosecond = nanosecond
    self.weekday = weekday
    self.weekdayOrdinal = weekdayOrdinal
    self.quarter = quarter
    self.weekOfMonth = weekOfMonth
    self.weekOfYear = weekOfYear
    self.yearForWeekOfYear = yearForWeekOfYear
  }

  public var date: Date? { return (calendar ?? Calendar.current).date(from: self) }
  public var isValidDate: Bool { return isValidDate(in: calendar ?? Calendar.current) }
  public func isValidDate(in calendar: Calendar) -> Bool {
    if let m = month, !(1...12).contains(m) { return false }
    if let d = day {
      let y = year ?? 2001
      let m = month ?? 1
      if !(1...Calendar.daysIn(year: y, month: m)).contains(d) { return false }
    }
    if let h = hour, !(0..<24).contains(h) { return false }
    if let mi = minute, !(0..<60).contains(mi) { return false }
    if let s = second, !(0..<60).contains(s) { return false }
    return true
  }

  public func value(for component: Calendar.Component) -> Int? {
    switch component {
    case .era: return era
    case .year: return year
    case .month: return month
    case .day: return day
    case .hour: return hour
    case .minute: return minute
    case .second: return second
    case .nanosecond: return nanosecond
    case .weekday: return weekday
    case .weekdayOrdinal: return weekdayOrdinal
    case .quarter: return quarter
    case .weekOfMonth: return weekOfMonth
    case .weekOfYear: return weekOfYear
    case .yearForWeekOfYear: return yearForWeekOfYear
    case .dayOfYear: return dayOfYear
    default: return nil
    }
  }
  public mutating func setValue(_ value: Int?, for component: Calendar.Component) {
    switch component {
    case .era: era = value
    case .year: year = value
    case .month: month = value
    case .day: day = value
    case .hour: hour = value
    case .minute: minute = value
    case .second: second = value
    case .nanosecond: nanosecond = value
    case .weekday: weekday = value
    case .weekdayOrdinal: weekdayOrdinal = value
    case .quarter: quarter = value
    case .weekOfMonth: weekOfMonth = value
    case .weekOfYear: weekOfYear = value
    case .yearForWeekOfYear: yearForWeekOfYear = value
    case .dayOfYear: dayOfYear = value
    default: break
    }
  }
  public var description: String {
    var parts: [String] = []
    if let v = year { parts.append("year: \(v)") }
    if let v = month { parts.append("month: \(v)") }
    if let v = day { parts.append("day: \(v)") }
    if let v = hour { parts.append("hour: \(v)") }
    if let v = minute { parts.append("minute: \(v)") }
    if let v = second { parts.append("second: \(v)") }
    if let v = weekday { parts.append("weekday: \(v)") }
    return parts.joined(separator: " ")
  }
}

// MARK: - DateInterval

public struct DateInterval: Hashable, Comparable, Codable, Sendable {
  public var start: Date
  public var duration: TimeInterval
  public var end: Date {
    get { return start.addingTimeInterval(duration) }
    set { duration = newValue.timeIntervalSince(start) }
  }
  public init() {
    start = Date()
    duration = 0
  }
  public init(start: Date, end: Date) {
    precondition(end >= start, "end must not precede start")
    self.start = start
    duration = end.timeIntervalSince(start)
  }
  public init(start: Date, duration: TimeInterval) {
    self.start = start
    self.duration = duration
  }
  public func contains(_ date: Date) -> Bool { return date >= start && date <= end }
  public func intersects(_ other: DateInterval) -> Bool { return start <= other.end && other.start <= end }
  public func intersection(with other: DateInterval) -> DateInterval? {
    guard intersects(other) else { return nil }
    return DateInterval(start: max(start, other.start), end: min(end, other.end))
  }
  public static func < (a: DateInterval, b: DateInterval) -> Bool {
    return a.start < b.start || (a.start == b.start && a.duration < b.duration)
  }
}
