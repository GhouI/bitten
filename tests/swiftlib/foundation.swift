// Foundation's Swift overlay: UUID, CharacterSet, String extensions,
// format strings, Locale, the Synchronization module's Mutex.
import Foundation
import Synchronization

@_silgen_name("swl_foundation_uuid") public func uuid() -> Int {
  var bad = 0
  let a = UUID(), b = UUID()
  if a == b { bad |= 1 }
  let s = a.uuidString
  if s.count != 36 || UUID(uuidString: s) != a { bad |= 2 }
  if UUID(uuidString: "not-a-uuid") != nil { bad |= 4 }
  let fixed = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
  if fixed.uuid.0 != 0xE6 || fixed.uuid.15 != 0x5F || fixed.uuidString != "E621E1F8-C36C-495A-93FC-0C247A3E6E5F" { bad |= 8 }
  if UUID(uuidString: "e621e1f8-c36c-495a-93fc-0c247a3e6e5f") != fixed { bad |= 16 }
  return bad
}

@_silgen_name("swl_foundation_charset") public func charset() -> Int {
  var bad = 0
  let ws = CharacterSet.whitespaces
  if !ws.contains(" ") || ws.contains("a") { bad |= 1 }
  if !CharacterSet.letters.contains("é") || CharacterSet.letters.contains("1") { bad |= 2 }
  if !CharacterSet.decimalDigits.contains("7") { bad |= 4 }
  let abc = CharacterSet(charactersIn: "abc")
  if !abc.contains("b") || abc.contains("d") || abc.inverted.contains("a") || !abc.inverted.contains("z") { bad |= 8 }
  let range = CharacterSet(charactersIn: "a"..<"e")
  if !abc.isSubset(of: range) || range.isSubset(of: abc) { bad |= 16 }
  if abc.union(CharacterSet(charactersIn: "xyz")).intersection(range) != abc { bad |= 32 }
  var m = abc
  m.insert("q")
  m.remove("a")
  if !m.contains("q") || m.contains("a") { bad |= 64 }
  if CharacterSet.alphanumerics.inverted.inverted != CharacterSet.alphanumerics { bad |= 128 }
  return bad
}

@_silgen_name("swl_foundation_strings") public func strings() -> Int {
  var bad = 0
  if "  hi there \n".trimmingCharacters(in: .whitespacesAndNewlines) != "hi there" { bad |= 1 }
  if "a,b;c".components(separatedBy: CharacterSet(charactersIn: ",;")) != ["a", "b", "c"] { bad |= 2 }
  if "one--two--".components(separatedBy: "--") != ["one", "two", ""] { bad |= 4 }
  if "Hello World".replacingOccurrences(of: "o", with: "0") != "Hell0 W0rld" { bad |= 8 }
  if "Hello".replacingOccurrences(of: "L", with: "_", options: .caseInsensitive) != "He__o" { bad |= 16 }
  if "abc".caseInsensitiveCompare("ABC") != .orderedSame { bad |= 32 }
  if "file10".localizedStandardCompare("file9") != .orderedDescending { bad |= 64 }
  if !"Hello".localizedCaseInsensitiveContains("ELL") { bad |= 128 }
  if "a%20b%C3%A9".removingPercentEncoding != "a bé" || "%zz".removingPercentEncoding != nil { bad |= 256 }
  if "a b".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) != "a%20b" { bad |= 512 }
  if let r = "abc1".rangeOfCharacter(from: .decimalDigits), "abc1"[r] != "1" { bad |= 1024 }
  if let r = "xyzzy".range(of: "zz"), "xyzzy".distance(from: "xyzzy".startIndex, to: r.lowerBound) != 2 { bad |= 2048 }
  if "xyzzy".range(of: "y", options: .backwards).map({ "xyzzy".distance(from: "xyzzy".startIndex, to: $0.lowerBound) }) != 4 { bad |= 4096 }
  if "hello world".capitalized != "Hello World" { bad |= 8192 }
  return bad
}

@_silgen_name("swl_foundation_format") public func format() -> Int {
  var bad = 0
  if String(format: "%d-%@", 42, "x") != "42-x" { bad |= 1 }
  if String(format: "%d", 42) != "42" { bad |= 2 }
  if String(format: "%.2f|%5d|%x", 3.14159, 7, 255) != "3.14|    7|ff" { bad |= 4 }
  if String(format: "%d %d %d %d %d %d %d %d", 1, 2, 3, 4, 5, 6, 7, 8) != "1 2 3 4 5 6 7 8" { bad |= 8 }
  if String.Encoding.utf8.rawValue != 4 { bad |= 16 }
  return bad
}

@_silgen_name("swl_foundation_misc") public func misc() -> Int {
  var bad = 0
  if Locale(identifier: "en-US.UTF-8").identifier != "en_US" { bad |= 1 }
  if Locale(identifier: "fr_CA").languageCode != "fr" || Locale(identifier: "fr_CA").regionCode != "CA" { bad |= 2 }
  let counter = Mutex(0)
  for _ in 0..<10 { counter.withLock { $0 += 1 } }
  if counter.withLock({ $0 }) != 10 { bad |= 4 }
  if counter.withLockIfAvailable({ $0 }) != 10 { bad |= 8 }
  return bad
}

@_silgen_name("swl_foundation_data") public func data() -> Int {
  var bad = 0
  // Apple's layout: 16 bytes, tag in spare bits.
  if MemoryLayout<Data>.size != 16 || MemoryLayout<Data.Iterator>.size != 64 { bad |= 1 }
  var d = Data([1, 2, 3])
  if d.count != 3 || d[1] != 2 || Array(d) != [1, 2, 3] { bad |= 2 }
  d.append(contentsOf: [UInt8](repeating: 7, count: 40)) // goes out of line
  if d.count != 43 || d[42] != 7 || d[0] != 1 { bad |= 4 }
  let slice = d[2..<5]
  if slice.startIndex != 2 || slice.count != 3 || slice[2] != 3 || slice[3] != 7 { bad |= 8 }
  var copy = d
  copy[0] = 99
  if d[0] != 1 || copy[0] != 99 { bad |= 16 } // value semantics
  d.replaceSubrange(0..<3, with: Data([9]))
  if d.count != 41 || d[0] != 9 || d[1] != 7 { bad |= 32 }
  if Data("hello".utf8).base64EncodedString() != "aGVsbG8=" { bad |= 64 }
  if Data(base64Encoded: "aGVsbG8=").map({ Array($0) }) != Array("hello".utf8) { bad |= 128 }
  if Data(base64Encoded: "@@") != nil { bad |= 256 }
  if Data([1, 2, 3, 4, 2, 3]).range(of: Data([2, 3]), options: .backwards) != 4..<6 { bad |= 512 }
  var sum = 0
  for b in Data(repeating: 1, count: 100) { sum += Int(b) }
  if sum != 100 { bad |= 1024 }
  let url = URL(fileURLWithPath: "/tmp/bitten-swl-data")
  do {
    try Data("file contents".utf8).write(to: url, options: .atomic)
    let back = try Data(contentsOf: url)
    if String(data: back, encoding: .utf8) != "file contents" { bad |= 2048 }
  } catch { bad |= 4096 }
  do {
    _ = try Data(contentsOf: URL(fileURLWithPath: "/nonexistent/bitten"))
    bad |= 8192
  } catch { if (error as NSError).code != 260 { bad |= 16384 } }
  let ns = d as NSData
  if ns.length != 41 || (ns as Data) != d { bad |= 32768 }
  if "é".data(using: .utf8) != Data([0xC3, 0xA9]) || "é".data(using: .ascii) != nil { bad |= 65536 }
  var big = Data(count: 20)
  big.withUnsafeMutableBytes { $0[19] = 5 }
  if big[19] != 5 || big.count != 20 { bad |= 131072 }
  return bad
}

struct Person: Codable, Equatable {
  var firstName: String
  var age: Int
  var score: Double
  var tags: [String]
  var nickname: String?
  var born: Date
  var blob: Data
}

@_silgen_name("swl_foundation_json") public func json() -> Int {
  var bad = 0
  let p = Person(firstName: "Ada", age: 36, score: 1.5, tags: ["a", "b/c"], nickname: nil,
                 born: Date(timeIntervalSince1970: 0), blob: Data([1, 2, 3]))
  let enc = JSONEncoder()
  enc.outputFormatting = [.sortedKeys]
  enc.dateEncodingStrategy = .iso8601
  guard let data = try? enc.encode(p), let text = String(data: data, encoding: .utf8) else { return 1 }
  let expected = #"{"age":36,"blob":"AQID","born":"1970-01-01T00:00:00Z","firstName":"Ada","score":1.5,"tags":["a","b\/c"]}"#
  if text != expected { print(text); bad |= 2 }
  let dec = JSONDecoder()
  dec.dateDecodingStrategy = .iso8601
  if (try? dec.decode(Person.self, from: data)) != p { bad |= 4 }
  // snake case both ways
  enc.keyEncodingStrategy = .convertToSnakeCase
  enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  if let d = try? enc.encode(["x": p]), let s = String(data: d, encoding: .utf8) {
    if !s.contains("\"first_name\":\"Ada\"") || !s.contains("b/c") { print(s); bad |= 8 }
    dec.keyDecodingStrategy = .convertFromSnakeCase
    if (try? dec.decode([String: Person].self, from: d))?["x"] != p { bad |= 16 }
  } else { bad |= 32 }
  // pretty printing
  enc.outputFormatting = [.prettyPrinted, .sortedKeys]
  enc.keyEncodingStrategy = .useDefaultKeys
  if let d = try? enc.encode([1, 2]), String(data: d, encoding: .utf8) != "[\n  1,\n  2\n]" { bad |= 64 }
  // errors
  do { _ = try JSONDecoder().decode([Int].self, from: Data("[1,".utf8)); bad |= 128 } catch {}
  do { _ = try JSONDecoder().decode(Int.self, from: Data("\"x\"".utf8)); bad |= 256 } catch DecodingError.typeMismatch {} catch { bad |= 512 }
  if (try? JSONDecoder().decode(String.self, from: Data(#""é😀\n""#.utf8))) != "é😀\n" { bad |= 1024 }
  if (try? JSONDecoder().decode(Int64.self, from: Data("9007199254740993".utf8))) != 9007199254740993 { bad |= 2048 }
  // dates
  let d1 = Date(timeIntervalSince1970: 1700000000)
  if d1.timeIntervalSinceReferenceDate != 1700000000 - 978307200 || d1.addingTimeInterval(5) <= d1 { bad |= 4096 }
  if Date() < Date(timeIntervalSince1970: 1700000000) { bad |= 8192 }
  if d1.description != "2023-11-14 22:13:20 +0000" { print(d1.description); bad |= 16384 }
  return bad
}

enum Suit: CaseIterable { case hearts, spades, clubs }
struct Item: Identifiable { let id: Int }

@_silgen_name("swl_foundation_decimal") public func decimal() -> Int {
  var bad = 0
  if MemoryLayout<Decimal>.size != 20 { bad |= 1 }
  let a = Decimal(string: "12.345")!, b = Decimal(string: "0.655")!
  if (a + b).description != "13" { print((a + b).description); bad |= 2 }
  if (a - b).description != "11.69" { bad |= 4 }
  if (a * b).description != "8.085975" { bad |= 8 }
  if (Decimal(1) / Decimal(4)).description != "0.25" { bad |= 16 }
  if !((Decimal(1) / Decimal(3)).description.hasPrefix("0.3333333333")) { bad |= 32 }
  if !(b < a) || a == b || Decimal(string: "1.50")! != Decimal(string: "1.5")! { bad |= 64 }
  if (-a).description != "-12.345" || Decimal(string: "abc") != nil { bad |= 128 }
  var x = Decimal(string: "2.675")!, r = Decimal()
  NSDecimalRound(&r, &x, 2, .plain)
  if r.description != "2.68" { print(r.description); bad |= 256 }
  let lit: Decimal = 42
  if lit.description != "42" || Decimal(string: "1e3")!.description != "1000" { bad |= 512 }
  if let d = try? JSONEncoder().encode(a), let back = try? JSONDecoder().decode(Decimal.self, from: d), back != a { bad |= 1024 }
  // stdlib protocols the target app needs
  if Suit.allCases.count != 3 || Item(id: 4).id != 4 { bad |= 2048 }
  if #available(macOS 15, *) {} else { bad |= 4096 }
  if #available(macOS 99, *) { bad |= 8192 }
  return bad
}

final class Watched: NSObject { var level = 7 }

@_silgen_name("swl_foundation_combine") public func combine() -> Int {
  var bad = 0
  // NotificationCenter publisher
  var got: [String] = []
  let name = Notification.Name("org.example.ping")
  let c1 = NotificationCenter.default.publisher(for: name).sink { note in got.append(note.name.rawValue) }
  NotificationCenter.default.post(name: name, object: nil)
  if got != ["org.example.ping"] { bad |= 1 }
  c1.cancel()
  NotificationCenter.default.post(name: name, object: nil)
  if got.count != 1 { bad |= 2 }
  // Timer publisher on the main run loop
  var ticks = 0
  let c2 = Timer.publish(every: 0.01, on: .main, in: .default).autoconnect().sink { _ in ticks += 1 }
  RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
  c2.cancel()
  if ticks < 3 { print("ticks", ticks); bad |= 4 }
  // RunLoop as a scheduler, and plain timers
  var scheduled = false
  RunLoop.main.schedule { scheduled = true }
  var fired = 0
  let t = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in fired += 1 }
  RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
  if !scheduled || fired != 1 || t.isValid { bad |= 8 }
  // KVO publisher: the initial value
  let w = Watched()
  var levels: [Int] = []
  let c3 = w.publisher(for: \.level).sink { levels.append($0) }
  if levels != [7] { bad |= 16 }
  c3.cancel()
  // Notification bridging
  let n = Notification(name: name, object: w, userInfo: ["k": 1])
  let ns = n as NSNotification
  if ns.name != name || ns.object as AnyObject? !== w || (ns as Notification).name != name { bad |= 32 }
  return bad
}
