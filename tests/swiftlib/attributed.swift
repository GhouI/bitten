// AttributedString: runs, attributes by key and by dynamic member (whole
// string, ranges, scopes), merging runs, concatenation, characters, index
// conversion, containers, equality.
import Foundation

enum Tag: AttributedStringKey {
  typealias Value = Int
  static var name: String { return "BittenTag" }
}

@_silgen_name("swl_attributed") public func attributed() -> Int {
  var bad = 0
  var s = AttributedString("Hello, world")
  if String(s.characters) != "Hello, world" || s._bnRuns.count != 1 { bad |= 1 }
  let url = URL(string: "https://example.com")!
  s.link = url
  if s.link != url || s[Tag.self] != nil { bad |= 2 }
  // Attribute part of it: three runs.
  if let r = s.range(of: "world") {
    s[r][Tag.self] = 7
    if s[r][Tag.self] != 7 || s._bnRuns.count != 2 { bad |= 4 }
    if s[Tag.self] != nil { bad |= 8 }                     // not uniform over the whole
  } else { bad |= 0x10 }
  if s._bnRuns.map({ $0.0 }) != ["Hello, ", "world"] { bad |= 0x20 }
  // Setting the same value on the rest merges the runs again.
  s[Tag.self] = 7
  if s._bnRuns.count != 1 || s[Tag.self] != 7 { bad |= 0x40 }
  // Scopes by dynamic member.
  var t = AttributedString("x")
  t.foundation.languageIdentifier = "en"
  if t.languageIdentifier != "en" { bad |= 0x80 }
  // Concatenation keeps each side's attributes.
  var c = AttributeContainer()
  c[Tag.self] = 1
  let joined = AttributedString("ab", attributes: c) + AttributedString("cd")
  if String(joined.characters) != "abcd" || joined._bnRuns.count != 2 { bad |= 0x100 }
  var acc = AttributedString()
  acc += joined
  if acc != joined || acc.hashValue != joined.hashValue { bad |= 0x200 }
  // Index conversion.
  let plain = "abcd"
  if let r = Range(plain.index(plain.startIndex, offsetBy: 1)..<plain.endIndex, in: joined) {
    if String(joined[r].characters) != "bcd" { bad |= 0x400 }
  } else { bad |= 0x800 }
  let lit: AttributedString = "literal"
  if String(_characters: lit.characters) != "literal" { bad |= 0x1000 }
  // NSAttributedString both ways: text, runs, values.
  var rich = AttributedString("héllo ")
  rich.languageIdentifier = "fr"
  rich += AttributedString("world")
  let ns = NSAttributedString(rich)
  if ns.string != "héllo world" || ns.length != 11 { bad |= 0x4000 }
  if (ns.attribute("NSLanguage", at: 0, effectiveRange: nil) as? String) != "fr" { bad |= 0x8000 }
  if ns.attribute("NSLanguage", at: 7, effectiveRange: nil) != nil { bad |= 0x10000 }
  let back = AttributedString(ns)
  if back != rich || back._bnRuns.count != 2 { bad |= 0x20000 }
  let loc = AttributedString(localized: "Plain")
  if String(loc.characters) != "Plain" { bad |= 0x2000 }
  return bad
}
