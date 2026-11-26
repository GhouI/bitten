// Calendar and DateComponents: civil dates in a time zone, components,
// arithmetic with month-end clamping, intervals, comparisons; and the
// NotificationCenter async sequence.
import Foundation

struct Settings: Codable, Equatable {
  var name: String
  var size: Int
  var ratio: Double
  var tags: [String]
  var nested: [String: Int]
  var on: Bool
}

@_silgen_name("swl_calendar") public func calendar() -> Int {
  var bad = 0
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = TimeZone(identifier: "UTC")!
  // 2024-02-29 12:34:56 UTC = 1709210096.
  let d = Date(timeIntervalSince1970: 1709210096)
  let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday, .dayOfYear], from: d)
  if c.year != 2024 || c.month != 2 || c.day != 29 { bad |= 1 }
  if c.hour != 12 || c.minute != 34 || c.second != 56 { bad |= 2 }
  if c.weekday != 5 || c.dayOfYear != 60 { bad |= 4 }  // a Thursday, the 60th day
  if cal.date(from: DateComponents(year: 2024, month: 2, day: 29, hour: 12, minute: 34, second: 56)) != d { bad |= 8 }
  if cal.startOfDay(for: d).timeIntervalSince1970 != 1709164800 { bad |= 16 }
  // Adding a year to Feb 29 clamps to Feb 28; a month to Jan 31 clamps too.
  let next = cal.date(byAdding: .year, value: 1, to: d)!
  if cal.component(.day, from: next) != 28 || cal.component(.month, from: next) != 2 { bad |= 32 }
  let jan31 = cal.date(from: DateComponents(year: 2023, month: 1, day: 31))!
  if cal.component(.day, from: cal.date(byAdding: .month, value: 1, to: jan31)!) != 28 { bad |= 64 }
  if cal.range(of: .day, in: .month, for: d) != 1..<30 { bad |= 128 }
  let diff = cal.dateComponents([.day], from: jan31, to: d)
  if diff.day != 394 { bad |= 256 }
  if !cal.isDate(d, inSameDayAs: d.addingTimeInterval(3600)) { bad |= 512 }
  if cal.dateInterval(of: .month, for: d)?.duration != 29 * 86400 { bad |= 1024 }
  // A zone east of UTC moves the civil day.
  var tokyo = cal
  tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? TimeZone(secondsFromGMT: 9 * 3600)!
  if tokyo.component(.hour, from: d) != 21 { bad |= 2048 }
  // Dates before 1970.
  let old = cal.date(from: DateComponents(year: 1969, month: 7, day: 20))!
  if old.timeIntervalSince1970 != -14256000 { bad |= 4096 }
  // Property lists round-trip Codable values, in XML and binary.
  let v = Settings(name: "term", size: 13, ratio: 1.5, tags: ["a", "b"], nested: ["x": 1], on: true)
  for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
    let enc = PropertyListEncoder()
    enc.outputFormat = format
    guard let data = try? enc.encode(v), let back = try? PropertyListDecoder().decode(Settings.self, from: data) else {
      bad |= 8192
      continue
    }
    if back != v { bad |= 16384 }
  }
  // NSRange and String ranges in UTF-16.
  let str = "héllo wörld"
  let r = str.range(of: "wörld")!
  let ns = NSRange(r, in: str)
  if ns.location != 6 || ns.length != 5 { bad |= 32768 }
  if Range(ns, in: str) != r { bad |= 65536 }
  return bad
}
