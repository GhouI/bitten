// Number printing and arithmetic, string algorithms, Character and
// Unicode.Scalar properties, sorting and Codable synthesis (enums with
// payloads, integer-keyed dictionaries, nested optionals, decoding errors),
// against Swift 6.3 run on Linux (expected strings made by running the
// same cases there).
import Foundation
import _StringProcessing

enum Event: Codable, Equatable { case start(at: Int), stop, rename(String, to: String) }
struct Config: Codable { var limits: [Int: String]; var nested: [String: [Double?]]; var opt: Int??; var flag: Bool? }
struct Strict: Codable { var a: Int; var b: [String] }

func stdlibCases() -> [String] {
  var out: [String] = []
  func add(_ s: String) { out.append(s) }
  // floating point printing
  let doubles: [Double] = [0.1, 0.2, 0.3, 1.0 / 3, 2.0 / 3, 100, 1e15, 1e16, 1e17, 123456789012345678, 5e-324, 2.2250738585072014e-308,
    1.7976931348623157e308, 0.000001, 0.0000001, 12345.6789, -1.5, 3.141592653589793, 2.718281828459045, 9007199254740993, 4.35, 0.15, 1e-5, 6.02214076e23]
  add(doubles.map { $0.description }.joined(separator: " "))
  let floats: [Float] = [0.1, 1.0 / 3, 16777217, 1e10, 1e-10, 3.4028235e38, 1.17549435e-38, 100.5]
  add(floats.map { $0.description }.joined(separator: " "))
  add("\(Double.pi) \(Float.pi) \(-Double.zero) \(Double.ulpOfOne) \(Double.leastNonzeroMagnitude)")
  add("\(Int8.min) \(UInt16.max) \(Int32.max &* 2) \(Int.min.dividedReportingOverflow(by: Int("-1")!))")
  add("\(0b1011 & 0b0110) \(0b1011 | 0b0110) \(0b1011 ^ 0b0110) \(~0 as Int8) \(1 << 62) \(-8 >> 1) \(UInt8(200) &+ 100) \((-7).signum()) \(abs(Int64(-5)))")
  add("\((255).leadingZeroBitCount) \((12).trailingZeroBitCount) \((0xF0F0).nonzeroBitCount) \(Int(exactly: 2.5) as Any) \(Int(2.9)) \(Int(-2.9)) \((7).quotientAndRemainder(dividingBy: -2))")
  add("\(Double(7).truncatingRemainder(dividingBy: 2.5)) \(Double(7).remainder(dividingBy: 2.5)) \((2.5).rounded(.toNearestOrEven)) \((-0.5).rounded(.awayFromZero)) \(sqrt(2.0)) \(pow(2.0, 0.5))")
  add("\(Int("+12") as Any) \(Int("-0") as Any) \(Int("") as Any) \(Int("9223372036854775808") as Any) \(UInt8("256") as Any) \(Double("inf") as Any) \(Double("-nan")?.isNaN as Any) \(Double("0x1p-2") as Any)")
  // strings
  let csv = "a,,b,c,"
  add(csv.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false).description)
  add(csv.split(separator: ",").description); add(csv.split(whereSeparator: { $0 == "," || $0 == "b" }).description)
  add("hello world".replacing("o", with: "0")); add("aaa".replacing("aa", with: "b"))
  add(String("  pre".trimmingPrefix(" "))); add("abcabc".ranges(of: "bc").map { "abcabc".distance(from: "abcabc".startIndex, to: $0.lowerBound) }.description)
  add("\("abc".firstIndex(of: "c").map { "abc".distance(from: "abc".startIndex, to: $0) } as Any) \("abcb".lastIndex(of: "b").map { "abcb".distance(from: "abcb".startIndex, to: $0) } as Any)")
  add("\("swift".starts(with: "sw")) \("swift".hasSuffix("ft")) \("swift".contains("if")) \("swift".contains { $0 == "z" })")
  add(String("hello".map { $0.uppercased() }.joined())); add("ab".flatMap { [$0, $0] }.description)
  let s = "Héllo, 世界! 🇺🇸👍🏽"
  add("\(s.count) \(s.utf8.count) \(s.utf16.count) \(s.unicodeScalars.count)")
  add(s.map { c in c.isLetter ? "L" : c.isPunctuation ? "P" : c.isWhitespace ? "W" : c.isNumber ? "N" : "?" }.joined())
  add("\(Character("7").wholeNumberValue as Any) \(Character("F").hexDigitValue as Any) \(Character("٣").wholeNumberValue as Any) \(Character("ß").uppercased()) \(Character("ǅ").isUppercase) \(Character("a").asciiValue as Any)")
  add("\(Unicode.Scalar("👍").properties.isEmoji) \(Unicode.Scalar("A").properties.isAlphabetic) \(Unicode.Scalar(" ").properties.isWhitespace) \(Unicode.Scalar("é").properties.generalCategory) \(Unicode.Scalar("٣").properties.numericType as Any)")
  add(String(s.reversed())); add(s.lowercased() + "|" + s.uppercased())
  add(Array(s.indices.prefix(3)).map { s.distance(from: s.startIndex, to: $0) }.description)
  add(String(s.dropFirst(2).prefix(4))); add(String(s[s.index(s.startIndex, offsetBy: 7)...]))
  add("tab\tnew\nquote\"back\\".debugDescription); add(String(reflecting: Character("\n")))
  add(["b", "a", "c"].sorted().joined(separator: "") + [10, 9, 100].sorted().description + ["B", "a"].sorted().description)
  add(String(describing: [3, 1, 2].sorted { $0 > $1 }.firstIndex(of: 1)))
  add([("b", 1), ("a", 1), ("c", 0)].sorted { $0.1 < $1.1 }.map { $0.0 }.joined())
  // Codable synthesis
  let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
  add(String(decoding: try! enc.encode([Event.start(at: 3), .stop, .rename("a", to: "b")]), as: UTF8.self))
  let evs = try! JSONDecoder().decode([Event].self, from: try! enc.encode([Event.start(at: 3), .stop, .rename("a", to: "b")]))
  add(String(describing: evs))
  add(String(decoding: try! enc.encode(Config(limits: [2: "two", 1: "one"], nested: ["x": [1.5, nil]], opt: .some(nil), flag: nil)), as: UTF8.self))
  add(String(decoding: try! enc.encode([1: "a"]), as: UTF8.self)); add(String(decoding: try! enc.encode(["k": nil as Int?]), as: UTF8.self))
  for bad in [#"{"a":"1","b":[]}"#, #"{"b":[]}"#, #"{"a":1,"b":[1]}"#, #"{"a":1,"b":"#, #"[]"#] {
    do { _ = try JSONDecoder().decode(Strict.self, from: Data(bad.utf8)); add("ok") }
    catch let DecodingError.typeMismatch(t, ctx) { add("typeMismatch \(t) \(ctx.codingPath.map { $0.stringValue })") }
    catch let DecodingError.keyNotFound(k, ctx) { add("keyNotFound \(k.stringValue) \(ctx.codingPath.map { $0.stringValue })") }
    catch let DecodingError.dataCorrupted(ctx) { add("dataCorrupted \(ctx.codingPath.map { $0.stringValue })") }
    catch let DecodingError.valueNotFound(t, ctx) { add("valueNotFound \(t) \(ctx.codingPath.map { $0.stringValue })") }
    catch { add("other") }
  }
  add(String(decoding: try! enc.encode(Double.pi), as: UTF8.self) + " " + String(decoding: try! enc.encode(Float(0.1)), as: UTF8.self) + " " + String(decoding: try! enc.encode(Int64.max), as: UTF8.self))
  let nonConforming = JSONEncoder(); nonConforming.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
  add(String(decoding: try! nonConforming.encode([Double.infinity, -.infinity]), as: UTF8.self))
  do { _ = try JSONEncoder().encode(Double.nan); add("encoded nan") } catch { add("nan error \(error is EncodingError)") }
  return out
}

let expectedStdlib: [String] = [
  "0.1 0.2 0.3 0.3333333333333333 0.6666666666666666 100.0 1000000000000000.0 1e+16 1e+17 1.2345678901234568e+17 5e-324 2.2250738585072014e-308 1.7976931348623157e+308 1e-06 1e-07 12345.6789 -1.5 3.141592653589793 2.718281828459045 9007199254740992.0 4.35 0.15 1e-05 6.02214076e+23",
  "0.1 0.33333334 16777216.0 1e+10 1e-10 3.4028235e+38 1.1754944e-38 100.5",
  "3.141592653589793 3.1415925 -0.0 2.220446049250313e-16 5e-324",
  "-128 65535 -2 (partialValue: -9223372036854775808, overflow: true)",
  "2 15 13 -1 4611686018427387904 -4 44 -1 5",
  "56 2 8 nil 2 -2 (quotient: -3, remainder: 1)",
  "2.0 -0.5 2.0 -1.0 1.4142135623730951 1.4142135623730951",
  "Optional(12) Optional(0) nil nil nil Optional(inf) Optional(true) Optional(0.25)",
  "[\"a\", \"\", \"b,c,\"]",
  "[\"a\", \"b\", \"c\"]",
  "[\"a\", \"c\"]",
  "hell0 w0rld",
  "ba",
  " pre",
  "[1, 4]",
  "Optional(2) Optional(3)",
  "true true true false",
  "HELLO",
  "[\"a\", \"a\", \"b\", \"b\"]",
  "13 32 19 15",
  "LLLLLPWLLPW??",
  "Optional(7) Optional(15) Optional(3) SS false Optional(97)",
  "true true true lowercaseLetter Optional(Swift.Unicode.NumericType.decimal)",
  "👍🏽🇺🇸 !界世 ,olléH",
  "héllo, 世界! 🇺🇸👍🏽|HÉLLO, 世界! 🇺🇸👍🏽",
  "[0, 1, 2]",
  "llo,",
  "世界! 🇺🇸👍🏽",
  "\"tab\\tnew\\nquote\\\"back\\\\\"",
  "\"\\n\"",
  "abc[9, 10, 100][\"B\", \"a\"]",
  "Optional(2)",
  "cba",
  "[{\"start\":{\"at\":3}},{\"stop\":{}},{\"rename\":{\"_0\":\"a\",\"to\":\"b\"}}]",
  "[stdbehaviour.Event.start(at: 3), stdbehaviour.Event.stop, stdbehaviour.Event.rename(\"a\", to: \"b\")]",
  "{\"limits\":{\"1\":\"one\",\"2\":\"two\"},\"nested\":{\"x\":[1.5,null]},\"opt\":null}",
  "{\"1\":\"a\"}",
  "{\"k\":null}",
  "typeMismatch Int [\"a\"]",
  "keyNotFound a []",
  "typeMismatch String [\"b\", \"Index 0\"]",
  "dataCorrupted []",
  "typeMismatch Dictionary<String, Any> []",
  "3.141592653589793 0.1 9223372036854775807",
  "[\"inf\",\"-inf\"]",
  "nan error true",
]

@_silgen_name("swl_stdbehaviour_all") public func stdlibAll() -> Int {
  let got = stdlibCases()
  if got.count != expectedStdlib.count {
    print("stdbehaviour: \(got.count) cases, \(expectedStdlib.count) expected")
    for (i, g) in got.enumerated() { print(i, g.debugDescription) }
    return 1
  }
  var bad = 0
  for (i, (g, e)) in zip(got, expectedStdlib).enumerated() where g != e {
    print("stdbehaviour case \(i): \(g.debugDescription), want \(e.debugDescription)")
    bad += 1
  }
  return bad
}
