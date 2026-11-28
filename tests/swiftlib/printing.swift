// print, debugPrint, string interpolation, String(describing:/reflecting:),
// and the descriptions of numbers, Bool, Optional, collections and text.

@inline(never) func opaque<T>(_ x: T) -> T { return x }

struct Point { var x = 1, y = 2 }
final class Box {}
struct Named: CustomStringConvertible { var description: String { return "named!" } }
struct Debuggable: CustomDebugStringConvertible { var debugDescription: String { return "dbg" } }

var failures = 0
@inline(never) func expect(_ got: String, _ want: String, _ bit: Int, _ bad: inout Int) {
  if got != want {
    bad |= bit
    print("  got <\(got)> want <\(want)>")
  }
}

@_silgen_name("swl_printing_integers") public func integers() -> Int {
  var bad = 0
  expect(opaque(42).description, "42", 1, &bad)
  expect(String(opaque(-9_223_372_036_854_775_807 - 1)), "-9223372036854775808", 2, &bad)
  expect(String(opaque(UInt64.max)), "18446744073709551615", 4, &bad)
  expect(String(opaque(Int8(-128))), "-128", 8, &bad)
  expect(String(opaque(255), radix: 16), "ff", 16, &bad)
  expect(String(opaque(255), radix: 16, uppercase: true), "FF", 32, &bad)
  expect(String(opaque(-5), radix: 2), "-101", 64, &bad)
  if Int(opaque("123")) != 123 || Int(opaque("-42")) != -42 || Int(opaque("+7")) != 7 { bad |= 128 }
  if Int(opaque("12a")) != nil || Int(opaque("")) != nil || Int8(opaque("128")) != nil || UInt(opaque("-1")) != nil { bad |= 256 }
  if Int8(opaque("-128")) != -128 || UInt8(opaque("255")) != 255 { bad |= 512 }
  return bad
}

@_silgen_name("swl_printing_floats") public func floats() -> Int {
  var bad = 0
  expect(opaque(1.0).description, "1.0", 1, &bad)
  expect(opaque(0.1).description, "0.1", 2, &bad)
  expect(opaque(-2.5).description, "-2.5", 4, &bad)
  expect(opaque(1e16).description, "1e+16", 8, &bad)
  expect(opaque(9007199254740992.0).description, "9007199254740992.0", 16, &bad)
  expect(opaque(0.0001).description, "0.0001", 32, &bad)
  expect(opaque(0.00001).description, "1e-05", 64, &bad)
  expect(opaque(5e-324).description, "5e-324", 128, &bad)
  expect(opaque(1.0 / 3.0).description, "0.3333333333333333", 256, &bad)
  expect(opaque(Double.infinity).description, "inf", 512, &bad)
  expect(opaque(-Double.infinity).description, "-inf", 1024, &bad)
  expect(opaque(Double.nan).description, "nan", 2048, &bad)
  expect(opaque(-0.0).description, "-0.0", 4096, &bad)
  expect(opaque(Float(0.1)).description, "0.1", 8192, &bad)
  expect(opaque(Float(16777216)).description, "16777216.0", 16384, &bad)
  expect(opaque(Float(1e8)).description, "1e+08", 32768, &bad)
  expect(opaque(123456.789).description, "123456.789", 65536, &bad)
  expect(opaque(Float80(0.5)).description, "0.5", 1 << 17, &bad)
  if Double(opaque("2.5")) != 2.5 || Double(opaque("1e3")) != 1000 || Double(opaque(" 1")) != nil || Double(opaque("1x")) != nil { bad |= 1 << 18 }
  if Float(opaque("0.25")) != 0.25 || Double(opaque("inf")) != .infinity || Double(Substring(opaque("-4"))) != -4 { bad |= 1 << 19 }
  return bad
}

@_silgen_name("swl_printing_values") public func values() -> Int {
  var bad = 0
  let n: Int? = opaque(3), none: Int? = opaque(nil)
  expect(String(describing: n), "Optional(3)", 1, &bad)
  expect(String(describing: none), "nil", 2, &bad)
  expect("\(opaque(true)) \(opaque(false))", "true false", 4, &bad)
  expect(opaque([1, 2, 3]).description, "[1, 2, 3]", 8, &bad)
  expect(String(describing: opaque(["a", "b"])), "[\"a\", \"b\"]", 16, &bad)
  expect(String(describing: opaque([Int]())), "[]", 32, &bad)
  expect(String(describing: opaque(["k": 1])), "[\"k\": 1]", 64, &bad)
  expect(String(describing: opaque([String: Int]())), "[:]", 128, &bad)
  expect(String(describing: opaque(Set([7]))), "[7]", 256, &bad)
  expect(String(describing: opaque(0..<5)), "0..<5", 512, &bad)
  expect(String(describing: opaque(1...3)), "1...3", 1024, &bad)
  expect(String(describing: opaque(Named())), "named!", 2048, &bad)
  expect(String(describing: opaque(Debuggable())), "dbg", 4096, &bad)
  expect(String(reflecting: opaque("a\n\"b\"\t\\")), "\"a\\n\\\"b\\\"\\t\\\\\"", 8192, &bad)
  expect(String(reflecting: opaque("é\u{1}")), "\"é\\u{1}\"", 16384, &bad)
  expect(String(describing: opaque(Character("x"))), "x", 32768, &bad)
  expect(String(reflecting: opaque(Character("x"))), "\"x\"", 1 << 16, &bad)
  expect(String(describing: opaque(AnyHashable(5))), "5", 1 << 17, &bad)
  expect(String(reflecting: opaque(AnyHashable(5))), "AnyHashable(5)", 1 << 18, &bad)
  let s: StaticString = "static"
  expect(s.description, "static", 1 << 19, &bad)
  expect(String(describing: opaque(Box())), "printing.Box", 1 << 20, &bad)
  expect(String(describing: opaque(Point())), "Point(x: 1, y: 2)", 1 << 21, &bad)
  expect(String(describing: opaque([Optional(1), nil])), "[Optional(1), nil]", 1 << 22, &bad)
  let any: Any = opaque(4.5)
  expect(String(describing: any), "4.5", 1 << 23, &bad)
  expect(opaque(["x", "y", "z"]).joined(separator: ", "), "x, y, z", 1 << 24, &bad)
  expect(opaque(["x"[...], "y"[...]]).joined(), "xy", 1 << 25, &bad)
  expect(_typeName(type(of: opaque([1]))), "Swift.Array<Swift.Int>", 1 << 26, &bad)
  return bad
}

@_silgen_name("swl_printing_interpolation") public func interpolation() -> Int {
  var bad = 0
  let name = opaque("world"), count = opaque(3), pi = opaque(3.25)
  expect("hello \(name), \(count) times, pi \(pi)", "hello world, 3 times, pi 3.25", 1, &bad)
  expect("\(opaque([1: "one"]))", "[1: \"one\"]", 2, &bad)
  expect("\(Int.self) \(opaque(Optional("s")))", "Int Optional(\"s\")", 4, &bad)
  let sub: Substring = "a\(count)b"
  if sub != "a3b" { bad |= 8 }
  return bad
}

@_silgen_name("swl_printing_print") public func printing() -> Int {
  var bad = 0
  var out = ""
  print(1, "two", 3.0, separator: "-", terminator: "!", to: &out)
  expect(out, "1-two-3.0!", 1, &bad)
  out = ""
  debugPrint("q", 1, to: &out)
  expect(out, "\"q\" 1\n", 2, &bad)
  out = ""
  print(to: &out)
  expect(out, "\n", 4, &bad)
  // To standard output; the driver's output check sees this line.
  print("printed", opaque(42), [true], separator: " ")
  return bad
}

/// Enums print their case, and a single-payload case its payload, as Swift
/// does; Mirror shows the payload labelled with the case.
enum Shade { case light, dark }
enum Load { case none, some(Int), pair(a: Int, b: String) }
enum OnePayload { case empty, value(String) }
enum Wrapped<T> { case nothing, one(T) }
@_silgen_name("swl_printing_enums") public func enums() -> Int {
  var bad = 0
  expect("\(opaque(Shade.dark)) \(opaque(Shade.light))", "dark light", 1, &bad)
  expect(String(describing: opaque(OnePayload.value("x"))), "value(\"x\")", 2, &bad)
  expect(String(describing: opaque(OnePayload.empty)), "empty", 4, &bad)
  expect(String(reflecting: opaque(Shade.dark)), "printing.Shade.dark", 8, &bad)
  let m = Mirror(reflecting: opaque(OnePayload.value("y")))
  if m.displayStyle != .enum || m.children.count != 1 || m.children.first?.label != "value"
    || (m.children.first?.value as? String) != "y" { bad |= 16 }
  if Mirror(reflecting: opaque(Shade.dark)).children.count != 0 { bad |= 32 }
  expect("\(opaque(Wrapped<Int>.one(5)))", "one(5)", 64, &bad)
  // light and dark must not read alike (programs key caches with them)
  if "\(opaque(Shade.light))" == "\(opaque(Shade.dark))" { bad |= 128 }
  // a multi-payload enum still shows its case
  let pairText = "\(opaque(Load.pair(a: 1, b: "z")))"
  if !pairText.hasPrefix("pair") { bad |= 256; print("  got <\(pairText)>") }
  if "\(opaque(Load.none))" != "none" { bad |= 512 }
  return bad
}
