// The formatters and regular expressions from Swift, as the target app
// calls them: Date and TimeInterval bridged, option sets, NSRange/Range.
import Foundation

@_silgen_name("swl_fmt_dates") public func dates() -> Int {
  var bad = 0
  let f = DateFormatter()
  f.timeZone = TimeZone(identifier: "GMT")
  f.dateFormat = "yyyy-MM-dd HH:mm"
  let d = Date(timeIntervalSince1970: 1772719629)
  if f.string(from: d) != "2026-03-05 14:07" { bad |= 1 }
  if f.date(from: "2026-03-05 14:07") != Date(timeIntervalSince1970: 1772719620) { bad |= 2 }
  if f.date(from: "nonsense") != nil { bad |= 4 }
  if ByteCountFormatter.string(fromByteCount: 1_500_000, countStyle: .file) != "1.5 MB" { bad |= 8 }
  let c = DateComponentsFormatter()
  c.allowedUnits = [.minute, .second]
  c.unitsStyle = .positional
  if c.string(from: 65) != "1:05" { bad |= 0x10 }
  let r = RelativeDateTimeFormatter()
  r.unitsStyle = .full
  if r.localizedString(for: d.addingTimeInterval(-120), relativeTo: d) != "2 minutes ago" { bad |= 0x20 }
  return bad
}

@_silgen_name("swl_fmt_regex") public func regex() -> Int {
  var bad = 0
  let text = "v1.2.3 and v10.0.1"
  guard let re = try? NSRegularExpression(pattern: #"v(\d+)\.(\d+)\.(\d+)"#) else { return 1 }
  let matches = re.matches(in: text, range: NSRange(text.startIndex..., in: text))
  if matches.count != 2 { bad |= 2 }
  if let m = matches.last, let r = Range(m.range(at: 1), in: text), text[r] != "10" { bad |= 4 }
  if re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                 withTemplate: "$1") != "1 and 10" { bad |= 8 }
  do {
    _ = try NSRegularExpression(pattern: "(")
    bad |= 0x10
  } catch {
    if (error as NSError).code != 2048 { bad |= 0x20 }
  }
  let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
  let s = "go to https://swift.org now"
  if detector?.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))?.url?.host != "swift.org" { bad |= 0x40 }
  return bad
}
