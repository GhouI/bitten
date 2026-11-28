// Foundation's dates, numbers, calendars, URLs, data, property lists,
// character sets and regular expressions, against swift-foundation (the
// Foundation macOS ships) run on Linux: the expected strings came from
// running the same cases there, with fixed locales and UTC.
import Foundation
import _StringProcessing

struct PItem: Codable { var name: String; var n: Int; var flags: [Bool]; var d: Double }

func foundationBehaviourCases() -> [String] {
  var out: [String] = []
  func add(_ s: String) { out.append(s) }
  let utc = TimeZone(identifier: "UTC")!
  let posix = Locale(identifier: "en_US_POSIX")
  let when = Date(timeIntervalSince1970: 1_700_000_000.25)
  // DateFormatter
  let df = DateFormatter(); df.locale = posix; df.timeZone = utc
  for f in ["yyyy-MM-dd HH:mm:ss.SSS", "EEE, d MMM yyyy", "EEEE MMMM d", "h:mm a", "yy/M/d HH:mm Z", "D 'day' w", "QQQ G"] {
    df.dateFormat = f; add(df.string(from: when))
  }
  df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
  add(String(describing: df.date(from: "2024-02-29T12:34:56+0200")?.timeIntervalSince1970))
  add(String(describing: df.date(from: "not a date")))
  let iso = ISO8601DateFormatter(); iso.timeZone = utc
  add(iso.string(from: when)); add(String(describing: iso.date(from: "2020-01-02T03:04:05Z")?.timeIntervalSince1970))
  iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; add(iso.string(from: when))
  // NumberFormatter
  let nf = NumberFormatter(); nf.locale = Locale(identifier: "en_US")
  nf.numberStyle = .decimal; add(nf.string(from: 1234567.891)!)
  nf.numberStyle = .percent; add(nf.string(from: 0.256)!)
  nf.numberStyle = .currency; add(nf.string(from: 1234.5)!)
  nf.numberStyle = .decimal; nf.minimumFractionDigits = 2; nf.maximumFractionDigits = 2; add(nf.string(from: 3)!)
  add(String(describing: nf.number(from: "1,234.50")))
  // Calendar
  var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
  let c = cal.dateComponents([.year, .month, .day, .hour, .weekday, .weekOfYear], from: when)
  add("\(c.year!) \(c.month!) \(c.day!) \(c.hour!) \(c.weekday!) \(c.weekOfYear!)")
  add(String(cal.date(byAdding: .month, value: 1, to: Date(timeIntervalSince1970: 1_706_659_200))!.timeIntervalSince1970)) // Jan 31 2024 + 1 month
  add(String(cal.startOfDay(for: when).timeIntervalSince1970))
  add(String(describing: cal.dateComponents([.day], from: Date(timeIntervalSince1970: 0), to: when).day))
  add(String(cal.range(of: .day, in: .month, for: Date(timeIntervalSince1970: 1_709_164_800))!.count)) // Feb 2024
  add(String(cal.isDateInWeekend(when)))
  // URLs
  var uc = URLComponents(string: "https://user:pw@example.com:8080/a/b%20c/?q=1&r=two%20words&q=3#frag")!
  add("\(uc.scheme!) \(uc.user!) \(uc.host!) \(uc.port!) \(uc.path) \(uc.percentEncodedPath) \(uc.fragment!)")
  add(uc.queryItems!.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: ","))
  uc.queryItems = [URLQueryItem(name: "a b", value: "c&d"), URLQueryItem(name: "e", value: nil)]
  add(uc.string!)
  let u = URL(string: "https://example.com/dir/file.tar.gz?x=1")!
  add("\(u.lastPathComponent) \(u.pathExtension) \(u.deletingLastPathComponent().absoluteString) \(u.path) \(u.query!)")
  add(URL(fileURLWithPath: "/tmp/a/../b/./c.txt").standardized.path)
  add(URL(string: "../x?y", relativeTo: URL(string: "https://h.com/a/b/c")!)!.absoluteString)
  add(URL(fileURLWithPath: "/tmp").appendingPathComponent("sub dir").appendingPathExtension("txt").absoluteString)
  add("a b&c/d?é".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)
  add("a%20b%2Fc".removingPercentEncoding!)
  // Data
  let data = Data("hello, world".utf8)
  add(data.base64EncodedString()); add(String(describing: Data(base64Encoded: "aGk=").map { String(decoding: $0, as: UTF8.self) }))
  add(Data([0xde, 0xad, 0xbe, 0xef]).map { String(format: "%02x", $0) }.joined())
  add(String(describing: "héllo".data(using: .isoLatin1)?.count)); add(String(describing: "héllo".data(using: .ascii)))
  add(String(describing: String(data: Data([0x68, 0xe9]), encoding: .isoLatin1)))
  // property lists
  let pe = PropertyListEncoder(); pe.outputFormat = .xml
  add(String(decoding: try! pe.encode(PItem(name: "a<b", n: -3, flags: [true, false], d: 1.5)), as: UTF8.self))
  let back = try! PropertyListDecoder().decode(PItem.self, from: try! pe.encode(PItem(name: "z", n: 7, flags: [], d: 0.25)))
  add("\(back.name) \(back.n) \(back.flags) \(back.d)")
  // character sets and scanning
  add(String("a1 b2_c3".unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
  add("one two  three".components(separatedBy: .whitespaces).description)
  add(String(describing: "  42 abc".trimmingCharacters(in: .whitespaces).rangeOfCharacter(from: .letters).map { _ in "x" }))
  // regular expressions
  let re = try! NSRegularExpression(pattern: "(\\w+)@(\\w+)\\.com")
  let text = "mail bob@example.com and amy@test.com"
  let ms = re.matches(in: text, range: NSRange(text.startIndex..., in: text))
  add(ms.map { (text as NSString).substring(with: $0.range(at: 2)) }.joined(separator: ","))
  add(re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "<$1>"))
  add(text.replacingOccurrences(of: "\\d+|@", with: "#", options: .regularExpression))
  let r2 = try! Regex("(\\d+)-(\\d+)")
  if let m = "range 10-20 end".firstMatch(of: r2) {
    add("\(m.output[1].substring!) \(m.output[2].substring!) \(m.output[0].substring!)")
  }
  add("a1b22c333".matches(of: try! Regex("\\d+")).map { String($0.output[0].substring!) }.joined(separator: "|"))
  return out
}

let expectedFoundationBehaviour: [String] = [
  "2023-11-14 22:13:20.250",
  "Tue, 14 Nov 2023",
  "Tuesday November 14",
  "10:13 PM",
  "23/11/14 22:13 +0000",
  "318 day 46",
  "Q4 AD",
  "Optional(1709202896.0)",
  "nil",
  "2023-11-14T22:13:20Z",
  "Optional(1577934245.0)",
  "2023-11-14T22:13:20.250Z",
  "1,234,567.891",
  "26%",
  "$1,234.50",
  "3.00",
  "Optional(1234.5)",
  "2023 11 14 22 3 46",
  "1709164800.0",
  "1699920000.0",
  "Optional(19675)",
  "29",
  "false",
  "https user example.com 8080 /a/b c/ /a/b%20c/ frag",
  "q=1,r=two words,q=3",
  "https://user:pw@example.com:8080/a/b%20c/?a%20b=c%26d&e#frag",
  "file.tar.gz gz https://example.com/dir/?x=1 /dir/file.tar.gz x=1",
  "/tmp/b/c.txt",
  "https://h.com/a/x?y",
  "file:///tmp/sub%20dir.txt",
  "a%20b&c/d?%C3%A9",
  "a b/c",
  "aGVsbG8sIHdvcmxk",
  "Optional(\"hi\")",
  "deadbeef",
  "Optional(5)",
  "nil",
  "Optional(\"hé\")",
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n\t<key>d</key>\n\t<real>1.5</real>\n\t<key>flags</key>\n\t<array>\n\t\t<true/>\n\t\t<false/>\n\t</array>\n\t<key>n</key>\n\t<integer>-3</integer>\n\t<key>name</key>\n\t<string>a&lt;b</string>\n</dict>\n</plist>\n",
  "z 7 [] 0.25",
  "a1b2c3",
  "[\"one\", \"two\", \"\", \"three\"]",
  "Optional(\"x\")",
  "example,test",
  "mail <bob> and <amy>",
  "mail bob#example.com and amy#test.com",
  "10 20 10-20",
  "1|22|333",
]

@_silgen_name("swl_fbehaviour_all") public func foundationBehaviourAll() -> Int {
  let got = foundationBehaviourCases()
  if got.count != expectedFoundationBehaviour.count {
    print("fbehaviour: \(got.count) cases, \(expectedFoundationBehaviour.count) expected")
    for (i, g) in got.enumerated() { print(i, g.debugDescription) }
    return 1
  }
  var bad = 0
  for (i, (g, e)) in zip(got, expectedFoundationBehaviour).enumerated() where g != e {
    print("fbehaviour case \(i): \(g.debugDescription), want \(e.debugDescription)")
    bad += 1
  }
  return bad
}
