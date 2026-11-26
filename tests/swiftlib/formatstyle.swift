// FormatStyle: numbers (grouping, precision, percent, locales, parsing,
// in a regex), lists, ISO 8601 (format and parse), date styles, TimeZone.
import Foundation
import _StringProcessing

@_silgen_name("swl_fmt_numbers") public func numbers() -> Int {
  var bad = 0
  let us = Locale(identifier: "en_US"), de = Locale(identifier: "de_DE")
  if 1234567.formatted(.number.locale(us)) != "1,234,567" { bad |= 1 }
  if 12345.6789.formatted(.number.locale(us)) != "12,345.679" { bad |= 2 }
  if 12345.6789.formatted(.number.locale(de)) != "12.345,679" { bad |= 4 }
  if 3.14159.formatted(FloatingPointFormatStyle<Double>(locale: us).precision(.fractionLength(2))) != "3.14" { bad |= 8 }
  if 2.0.formatted(FloatingPointFormatStyle<Double>(locale: us).precision(.fractionLength(1...3))) != "2.0" { bad |= 0x10 }
  if 1234.5.formatted(FloatingPointFormatStyle<Double>(locale: us).grouping(.never)) != "1234.5" { bad |= 0x20 }
  if 0.256.formatted(FloatingPointFormatStyle<Double>.Percent(locale: us)) != "25.6%" { bad |= 0x40 }
  if 0.5.formatted(FloatingPointFormatStyle<Double>.Percent(locale: us).precision(.fractionLength(0))) != "50%" { bad |= 0x80 }
  if 98765.4321.formatted(FloatingPointFormatStyle<Double>(locale: us).precision(.significantDigits(3))) != "98,765" { bad |= 0x100 }
  if (try? Double("1.234,5", format: FloatingPointFormatStyle<Double>(locale: de))) != 1234.5 { bad |= 0x200 }
  if (try? Double("x", format: FloatingPointFormatStyle<Double>(locale: us))) != nil { bad |= 0x400 }
  if (-42).formatted(IntegerFormatStyle<Int>(locale: us)) != "-42" { bad |= 0x800 }
  if us.decimalSeparator != "." || de.groupingSeparator != "." { bad |= 0x1000 }
  // A localized number inside a regex gives its value.
  if let m = try? Regex<Double>(_bittenPattern: "x", transform: { _ in nil }).firstMatch(in: "x"), m != nil { bad |= 0x2000 }
  let style = FloatingPointFormatStyle<Double>.localizedDouble(locale: us)
  if (try? style.regex.firstMatch(in: "Total: 1,250.75 USD"))??.output != 1250.75 { bad |= 0x4000 }
  return bad
}

@_silgen_name("swl_fmt_lists_dates") public func listsAndDates() -> Int {
  var bad = 0
  if ["a", "b", "c"].formatted(.list(type: .and)) != "a, b, and c" { bad |= 1 }
  if ["a", "b"].formatted(.list(type: .or)) != "a or b" { bad |= 2 }
  if ["x", "y", "z"].formatted(.list(type: .and, width: .narrow)) != "x, y, z" { bad |= 4 }
  if ["solo"].formatted() != "solo" { bad |= 8 }
  let date = Date(timeIntervalSince1970: 1_764_133_443.25)   // 2025-11-26T05:04:03.25Z
  if date.formatted(.iso8601) != "2025-11-26T05:04:03Z" { bad |= 0x10 }
  let frac = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  if frac.format(date) != "2025-11-26T05:04:03.250Z" { bad |= 0x20 }
  let paris = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: TimeZone(secondsFromGMT: 3600)!)
  if paris.format(date) != "2025-11-26T06:04:03+01:00" { bad |= 0x40 }
  let compact = Date.ISO8601FormatStyle(dateSeparator: .omitted, timeSeparator: .omitted)
  if compact.format(date) != "20251126T050403Z" { bad |= 0x80 }
  if (try? Date.ISO8601FormatStyle().parse("2025-11-26T05:04:03Z")) != Date(timeIntervalSince1970: 1_764_133_443) { bad |= 0x100 }
  if (try? Date.ISO8601FormatStyle().parse("2025-11-26T06:04:03.5+01:00"))?.timeIntervalSince1970 != 1_764_133_443.5 { bad |= 0x200 }
  if (try? Date.ISO8601FormatStyle().parse("not a date")) != nil { bad |= 0x400 }
  // Date styles render in the local zone: GMT here (TZ=UTC set by the driver).
  if date.formatted(date: .abbreviated, time: .omitted) != "Nov 26, 2025" { bad |= 0x800 }
  if date.formatted(date: .numeric, time: .shortened) != "11/26/2025, 5:04\u{202F}AM" { bad |= 0x1000 }
  if date.formatted(date: .omitted, time: .standard) != "5:04:03\u{202F}AM" { bad |= 0x2000 }
  // Time zones.
  if TimeZone(identifier: "GMT")?.secondsFromGMT() != 0 || TimeZone(identifier: "GMT+0530")?.secondsFromGMT() != 19800 { bad |= 0x4000 }
  if let ny = TimeZone(identifier: "America/New_York") {
    let winter = Date(timeIntervalSince1970: 1_767_225_600)   // 2026-01-01
    let summer = Date(timeIntervalSince1970: 1_782_864_000)   // 2026-07-01
    if ny.secondsFromGMT(for: winter) != -18000 || ny.secondsFromGMT(for: summer) != -14400 { bad |= 0x8000 }
    if !ny.isDaylightSavingTime(for: summer) || ny.abbreviation(for: winter) != "EST" { bad |= 0x10000 }
  }
  if TimeZone(identifier: "Not/AZone") != nil { bad |= 0x20000 }
  return bad
}
