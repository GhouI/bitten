// Swift's Regex: literals (as the compiler lowers them), captures and
// optional captures, quantifiers, classes, anchors, case-insensitivity,
// matches(of:), contains, split, and RegexBuilder.
import _StringProcessing
import RegexBuilder

@_silgen_name("swl_rx_literals") public func literals() -> Int {
  var bad = 0
  let s = "Version 12.4 released 2026-11-26"
  if let m = try? #/(\d+)\.(\d+)/#.firstMatch(in: s[...]) {
    if m.output.0 != "12.4" || m.output.1 != "12" || m.output.2 != "4" { bad |= 1 }
  } else { bad |= 2 }
  if let m = try? #/(?<y>\d{4})-(?<m>\d\d)-(?<d>\d\d)/#.firstMatch(in: s[...]) {
    if m.y != "2026" || m.m != "11" || m.d != "26" { bad |= 4 }
  } else { bad |= 8 }
  // An optional capture that did not take part.
  if let m = try? #/(a)?(b)/#.wholeMatch(in: "b"[...]) {
    if m.output.1 != nil || m.output.2 != "b" { bad |= 0x10 }
  } else { bad |= 0x20 }
  if (try? #/\d+/#.wholeMatch(in: "12a"[...])) != nil { bad |= 0x40 }
  if (try? #/^\s*\w+\s*$/#.wholeMatch(in: "  hello "[...])) == nil { bad |= 0x80 }
  if (try? #/(?i)HELLO/#.firstMatch(in: "say hello"[...])) == nil { bad |= 0x100 }
  if (try? #/colou?r/#.firstMatch(in: "color"[...]))?.output != "color" { bad |= 0x200 }
  if (try? #/a.*?b/#.firstMatch(in: "aXbYb"[...]))?.output != "aXb" { bad |= 0x400 }   // lazy
  if (try? #/[^aeiou ]+/#.firstMatch(in: "aa bcd"[...]))?.output != "bcd" { bad |= 0x800 }
  if (try? #/\bcat\b/#.firstMatch(in: "concat cat"[...]))?.range.lowerBound != "concat cat".index("concat cat".startIndex, offsetBy: 7) { bad |= 0x1000 }
  if (try? #/x{2,3}/#.firstMatch(in: "xxxxx"[...]))?.output != "xxx" { bad |= 0x2000 }
  if (try? #/(foo|bar)+/#.wholeMatch(in: "foobarfoo"[...]))?.output.1 != "foo" { bad |= 0x4000 }
  let r = try? Regex("[a-c]+")
  if r == nil || (try? r!.firstMatch(in: "xxabcay"[...]))?.output[0].substring != "abca" { bad |= 0x8000 }
  let typed = try? Regex("(\\w+)@(\\w+)", as: (Substring, Substring, Substring).self)
  if (try? typed?.firstMatch(in: "mail bob@example now"[...]))??.output.2 != "example" { bad |= 0x20000 }
  if (try? Regex("(unclosed")) != nil { bad |= 0x10000 }
  return bad
}

@_silgen_name("swl_rx_collections") public func collections() -> Int {
  var bad = 0
  let text = "a1 b22 c333"
  if text.matches(of: #/\d+/#).map({ $0.output }) != ["1", "22", "333"] { bad |= 1 }
  if !text.contains(#/b\d/#) || text.contains(#/z/#) { bad |= 2 }
  if text.split(separator: " ") != ["a1", "b22", "c333"] { bad |= 4 }
  if "a, b,,c".split(separator: ", ") != ["a", "b,,c"] { bad |= 8 }
  if text.replacing(#/\d/#, with: "#") != "a# b## c###" { bad |= 0x10 }
  if text.ranges(of: #/[a-z]/#).count != 3 { bad |= 0x20 }
  return bad
}

@_silgen_name("swl_rx_builder") public func builder() -> Int {
  var bad = 0
  let r = Regex {
    Capture {
      OneOrMore(.digit)
    }
  }
  if let m = try? r.firstMatch(in: "abc 4096 def"[...]) {
    if m.output.0 != "4096" || m.output.1 != "4096" { bad |= 1 }
  } else { bad |= 2 }
  let word = Regex { One(.word) }
  if (try? word.firstMatch(in: "  x"[...]))?.output != "x" { bad |= 4 }
  let kv = Regex {
    Capture { OneOrMore(.word) }
    "="
  }
  if let m = try? kv.firstMatch(in: "key=value"[...]), m.output.1 != "key" { bad |= 8 }
  return bad
}
