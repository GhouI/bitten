// NSString-style path and comparison operations, normalization, Scanner,
// ByteCountFormatter, Measurement and collection algorithms, against the
// Linux toolchain's Foundation (expected strings made by running the same
// cases there; formatters Linux lacks are left out).
import Foundation

func moreFoundationCases() -> [String] {
  var out: [String] = []
  func add(_ s: String) { out.append(s) }
  func addAny(_ v: Any?) { out.append(String(describing: v)) }
  let posix = Locale(identifier: "en_US_POSIX"), us = Locale(identifier: "en_US")
  // NSString-style operations
  let p = "/usr/local/lib/libfoo.dylib" as NSString
  add("\(p.lastPathComponent) \(p.pathExtension) \(p.deletingLastPathComponent) \(p.deletingPathExtension) \(p.pathComponents)")
  add(("a/b" as NSString).appendingPathComponent("c/d.txt")); add(("/x/./y/../z" as NSString).standardizingPath)
  add(("x" as NSString).appendingPathExtension("tar.gz") ?? "nil")
  add(["file10.txt", "file2.txt", "File1.txt", "file1.txt"].sorted { $0.localizedStandardCompare($1) == .orderedAscending }.description)
  add(String("a10".compare("a9", options: .numeric).rawValue)); add(String("ABC".caseInsensitiveCompare("abd").rawValue))
  add(String("café".compare("cafe", options: .diacriticInsensitive).rawValue))
  add("abc".padding(toLength: 6, withPad: "xy", startingAt: 0)); add("abcdef".padding(toLength: 3, withPad: " ", startingAt: 0))
  add("e\u{301}".precomposedStringWithCanonicalMapping.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: ","))
  add("\u{e9}".decomposedStringWithCanonicalMapping.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: ","))
  add("ﬁ".precomposedStringWithCompatibilityMapping)
  add("Hello, World".components(separatedBy: CharacterSet(charactersIn: ", ")).description)
  add("line1\nline2\r\nline3".components(separatedBy: .newlines).description)
  var lines: [String] = []; "a\nb\n\nc".enumerateLines { l, _ in lines.append(l) }; add(lines.description)
  add(String(describing: "abc".range(of: "B", options: .caseInsensitive).map { "abc".distance(from: "abc".startIndex, to: $0.lowerBound) }))
  add(String(describing: "hello world".range(of: "o", options: .backwards).map { "hello world".distance(from: "hello world".startIndex, to: $0.lowerBound) }))
  add("ÀÉÎ".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: posix))
  add(String(describing: "x=1;y=2".components(separatedBy: ";").map { $0.split(separator: "=").map(String.init) }))
  // Scanner
  let sc = Scanner(string: "  42 apples, 3.5 kg")
  addAny(sc.scanInt()); addAny(sc.scanCharacters(from: .letters)); addAny(sc.scanString(","))
  addAny(sc.scanDouble()); addAny(sc.scanUpToString("z")); add(String(sc.isAtEnd))
  // formatters
  let bc = ByteCountFormatter()
  add(bc.string(fromByteCount: 0) + "|" + bc.string(fromByteCount: 999) + "|" + bc.string(fromByteCount: 1_500_000) + "|" + bc.string(fromByteCount: 3_000_000_000))
  bc.countStyle = .binary; add(bc.string(fromByteCount: 1_048_576) + "|" + bc.string(fromByteCount: 1536))
  bc.allowedUnits = [.useKB]; add(bc.string(fromByteCount: 123_456))
  add(String(Measurement(value: 1, unit: UnitLength.miles).converted(to: .kilometers).value))
  // collections
  add([3, 1, 2].sorted(by: >).description); add(Array([1, 2, 3, 4, 5].reversed().prefix(2)).description)
  add([1, 2, 3, 4, 5, 6].chunked3().description)
  add(Dictionary(grouping: ["apple", "avocado", "banana"], by: { $0.first! }).sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: " "))
  add(Array(zip([1, 2, 3], ["a", "b"])).description); add([[1, 2], [3]].flatMap { $0 }.description)
  add([1, nil, 3].compactMap { $0 }.description); add(Set([1, 2, 3]).intersection([2, 3, 4]).sorted().description)
  add(["b": 2, "a": 1].mapValues { $0 * 10 }.sorted { $0.key < $1.key }.description)
  add([5, 3, 9].min()!.description + " " + [5, 3, 9].max()!.description); add([1, 2, 3].reduce(into: "") { $0 += String($1) })
  add(Array("hello".enumerated().map { "\($0.offset)\($0.element)" }).joined())
  add([1, 2, 3, 4].partitionPointDemo())
  return out
}
extension Array {
  func chunked3() -> [[Element]] { stride(from: 0, to: count, by: 3).map { Array(self[$0..<Swift.min($0 + 3, count)]) } }
}
extension Array where Element == Int {
  func partitionPointDemo() -> String { var a = self; let i = a.partition { $0 > 2 }; return "\(i) \(a[i...].sorted())" }
}

let expectedMoreFoundation: [String] = [
  "libfoo.dylib dylib /usr/local/lib /usr/local/lib/libfoo [\"/\", \"usr\", \"local\", \"lib\", \"libfoo.dylib\"]",
  "a/b/c/d.txt",
  "/x/z",
  "x.tar.gz",
  "[\"file1.txt\", \"File1.txt\", \"file2.txt\", \"file10.txt\"]",
  "1",
  "-1",
  "0",
  "abcxyx",
  "abc",
  "e9",
  "65,301",
  "fi",
  "[\"Hello\", \"\", \"World\"]",
  "[\"line1\", \"line2\", \"\", \"line3\"]",
  "[\"a\", \"b\", \"\", \"c\"]",
  "Optional(1)",
  "Optional(7)",
  "aei",
  "[[\"x\", \"1\"], [\"y\", \"2\"]]",
  "Optional(42)",
  "Optional(\"apples\")",
  "Optional(\",\")",
  "Optional(3.5)",
  "Optional(\"kg\")",
  "true",
  "Zero KB|999 bytes|1.5 MB|3 GB",
  "1 MB|2 KB",
  "121 KB",
  "1.60934",
  "[3, 2, 1]",
  "[5, 4]",
  "[[1, 2, 3], [4, 5, 6]]",
  "a:[\"apple\", \"avocado\"] b:[\"banana\"]",
  "[(1, \"a\"), (2, \"b\")]",
  "[1, 2, 3]",
  "[1, 3]",
  "[2, 3]",
  "[(key: \"a\", value: 10), (key: \"b\", value: 20)]",
  "3 9",
  "123",
  "0h1e2l3l4o",
  "2 [3, 4]",
]

@_silgen_name("swl_mfbehaviour_all") public func moreFoundationAll() -> Int {
  let got = moreFoundationCases()
  if got.count != expectedMoreFoundation.count {
    print("mfbehaviour: \(got.count) cases, \(expectedMoreFoundation.count) expected")
    for (i, g) in got.enumerated() { print(i, g.debugDescription) }
    return 1
  }
  var bad = 0
  for (i, (g, e)) in zip(got, expectedMoreFoundation).enumerated() where g != e {
    print("mfbehaviour case \(i): \(g.debugDescription), want \(e.debugDescription)")
    bad += 1
  }
  return bad
}
