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
