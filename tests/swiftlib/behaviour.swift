// Strings, numbers, formatting and JSON coding, against what Swift 6.3's
// standard library and swift-foundation (the Foundation macOS ships) do:
// the expected strings came from running the same cases on Linux.
import Foundation

struct Item: Codable { var id: Int; var name: String; var tags: [String]; var score: Double?; var on: Bool }
struct Nested: Codable { var items: [Item]; var meta: [String: Int]; var when: Date; var blob: Data; var link: URL }
enum Kind: String, Codable { case a, b }
struct WithEnum: Codable { var kind: Kind; var maybe: Kind? }

func behaviourCases() -> [String] {
  var out: [String] = []
  func add(_ s: String) { out.append(s) }
  // strings
  add("Hello World".lowercased()); add("straße".uppercased()); add("ǅungla".capitalized)
  add(String(reflecting: ["ǆx", "ﬁne", "ᾳ"].map { $0.capitalized }))
  add(String("e\u{301}" == "\u{e9}")); add(String("e\u{301}".count)); add(String("👨‍👩‍👧".count)); add(String("👨‍👩‍👧".unicodeScalars.count))
  add(String("abc" < "abd")); add(String("Z" < "a")); add(String("é" < "f"))
  add("a,b,,c".split(separator: ",").joined(separator: "|")); add("a,b,,c".components(separatedBy: ",").joined(separator: "|"))
  add("  trim me \n".trimmingCharacters(in: .whitespacesAndNewlines)); add("x-y-z".replacingOccurrences(of: "-", with: "+"))
  add(String("hello".hasPrefix("he"))); add(String("Hello".localizedCaseInsensitiveContains("ELL")))
  add(String(reflecting: "tab\there".split(separator: "\t")))
  add(String(repeating: "ab", count: 3)); add(String("abcdef".reversed())); add(String("abcdef".prefix(2)) + String("abcdef".suffix(2)))
  add(String(Int("42") ?? -1)); add(String(describing: Int("4x"))); add(String(describing: Double("1e3"))); add(String(describing: Double(" 1")))
  add(String(255, radix: 16)); add(String(255, radix: 2, uppercase: false)); add(String(Int("ff", radix: 16)!))
  // numbers
  add(String(0.1 + 0.2)); add(String(1.0 / 3)); add(String(Float(1) / 3)); add(String(2.5.rounded())); add(String((-2.5).rounded()))
  add(String(7 / -2)); add(String(7 % -2)); add(String(Int.max &+ 1)); add(String(Double(Int64.max)))
  add(String(format: "%.2f|%5d|%x|%@", 3.14159, 42, 255, "obj"))
  add(String(format: "%03d %+.1e %g %g", 7, 12345.678, 0.0001, 1e10))
  add(String((1...5).reduce(0, +))); add([3, 1, 2].sorted().description); add(["b", "A", "a"].sorted().description)
  add([1, 2, 3, 4].filter { $0 % 2 == 0 }.map { $0 * 10 }.description)
  add(String(describing: [1, 2, 3].firstIndex(of: 2))); add(String(describing: Array(stride(from: 0, to: 10, by: 3))))
  // JSON
  let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
  let item = Item(id: 1, name: "a \"q\" / é", tags: ["x", "y"], score: 0.5, on: true)
  add(String(decoding: try! enc.encode(item), as: UTF8.self))
  add(String(decoding: try! enc.encode(Item(id: 2, name: "", tags: [], score: nil, on: false)), as: UTF8.self))
  enc.outputFormatting = [.sortedKeys, .prettyPrinted]
  add(String(decoding: try! enc.encode(item), as: UTF8.self))
  enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  add(String(decoding: try! enc.encode(item), as: UTF8.self))
  enc.outputFormatting = [.sortedKeys]
  let n = Nested(items: [item], meta: ["z": 1, "a": 2], when: Date(timeIntervalSince1970: 1_000_000_000), blob: Data([0, 255, 16]),
                 link: URL(string: "https://e.com/p?q=1")!)
  add(String(decoding: try! enc.encode(n), as: UTF8.self))
  enc.dateEncodingStrategy = .iso8601; enc.dataEncodingStrategy = .base64
  add(String(decoding: try! enc.encode(n), as: UTF8.self))
  enc.dateEncodingStrategy = .secondsSince1970; enc.keyEncodingStrategy = .convertToSnakeCase
  struct Camel: Codable { var someValue: Int; var URLString: String; var a1B: Int }
  add(String(decoding: try! enc.encode(Camel(someValue: 1, URLString: "u", a1B: 2)), as: UTF8.self))
  add(String(decoding: try! JSONEncoder().encode([1.0, 0.1, 1e20, 100.0, -0.0]), as: UTF8.self))
  add(String(decoding: try! JSONEncoder().encode(WithEnum(kind: .b, maybe: nil)), as: UTF8.self))
  add(String(decoding: try! JSONEncoder().encode("é\u{1}\n\u{2028}"), as: UTF8.self))
  // decoding
  let dec = JSONDecoder()
  let back = try! dec.decode(Item.self, from: Data(#"{"id":3,"name":"n","tags":[],"on":true,"extra":1}"#.utf8))
  add("\(back.id) \(back.name) \(back.score as Any) \(back.on)")
  do { _ = try dec.decode(Item.self, from: Data(#"{"id":"x"}"#.utf8)); add("no error") } catch { add(String(describing: type(of: error))) }
  dec.keyDecodingStrategy = .convertFromSnakeCase
  struct Snake: Codable { var someValue: Int; var urlString: String }
  let sn = try! dec.decode(Snake.self, from: Data(#"{"some_value":5,"url_string":"s"}"#.utf8))
  add("\(sn.someValue) \(sn.urlString)")
  add(String(describing: try? JSONDecoder().decode([Double].self, from: Data("[1, 2.5, -3e2]".utf8))))
  add(String(describing: try? JSONDecoder().decode([String: Int?].self, from: Data(#"{"a":null}"#.utf8))))
  return out
}

let expectedBehaviour: [String] = [
  "hello world",
  "STRASSE",
  "ǅungla",
  "[\"ǅx\", \"Fine\", \"ᾼ\"]",
  "true",
  "1",
  "1",
  "5",
  "true",
  "true",
  "false",
  "a|b|c",
  "a|b||c",
  "trim me",
  "x+y+z",
  "true",
  "true",
  "[\"tab\", \"here\"]",
  "ababab",
  "fedcba",
  "abef",
  "42",
  "nil",
  "Optional(1000.0)",
  "nil",
  "ff",
  "11111111",
  "255",
  "0.30000000000000004",
  "0.3333333333333333",
  "0.33333334",
  "3.0",
  "-3.0",
  "-3",
  "1",
  "-9223372036854775808",
  "9.223372036854776e+18",
  "3.14|   42|ff|obj",
  "007 +1.2e+04 0.0001 1e+10",
  "15",
  "[1, 2, 3]",
  "[\"A\", \"a\", \"b\"]",
  "[20, 40]",
  "Optional(1)",
  "[0, 3, 6, 9]",
  "{\"id\":1,\"name\":\"a \\\"q\\\" \\/ é\",\"on\":true,\"score\":0.5,\"tags\":[\"x\",\"y\"]}",
  "{\"id\":2,\"name\":\"\",\"on\":false,\"tags\":[]}",
  "{\n  \"id\" : 1,\n  \"name\" : \"a \\\"q\\\" \\/ é\",\n  \"on\" : true,\n  \"score\" : 0.5,\n  \"tags\" : [\n    \"x\",\n    \"y\"\n  ]\n}",
  "{\"id\":1,\"name\":\"a \\\"q\\\" / é\",\"on\":true,\"score\":0.5,\"tags\":[\"x\",\"y\"]}",
  "{\"blob\":\"AP8Q\",\"items\":[{\"id\":1,\"name\":\"a \\\"q\\\" \\/ é\",\"on\":true,\"score\":0.5,\"tags\":[\"x\",\"y\"]}],\"link\":\"https:\\/\\/e.com\\/p?q=1\",\"meta\":{\"a\":2,\"z\":1},\"when\":21692800}",
  "{\"blob\":\"AP8Q\",\"items\":[{\"id\":1,\"name\":\"a \\\"q\\\" \\/ é\",\"on\":true,\"score\":0.5,\"tags\":[\"x\",\"y\"]}],\"link\":\"https:\\/\\/e.com\\/p?q=1\",\"meta\":{\"a\":2,\"z\":1},\"when\":\"2001-09-09T01:46:40Z\"}",
  // (swift-foundation on Linux writes "u_rl_string"; Foundation on macOS
  // writes "url_string", which is what this matches)
  "{\"a1_b\":2,\"some_value\":1,\"url_string\":\"u\"}",
  "[1,0.1,1e+20,100,-0]",
  "{\"kind\":\"b\"}",
  "\"é\\u0001\\n\u{2028}\"",
  "3 n nil true",
  "DecodingError",
  "5 s",
  "Optional([1.0, 2.5, -300.0])",
  "Optional([\"a\": nil])",
]

@_silgen_name("swl_behaviour_all") public func behaviourAll() -> Int {
  let got = behaviourCases()
  if got.count != expectedBehaviour.count { print("behaviour: \(got.count) cases, \(expectedBehaviour.count) expected"); return 1 }
  var bad = 0
  for (i, (g, e)) in zip(got, expectedBehaviour).enumerated() where g != e {
    print("behaviour case \(i): \(g.debugDescription), want \(e.debugDescription)")
    bad += 1
  }
  return bad
}
