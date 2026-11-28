// String(describing:) and String(reflecting:) of many kinds of value,
// against what Swift's own standard library prints (the expected strings
// were made by running the same cases with the Linux toolchain). Programs
// key caches by these strings, so a difference shows as stale UI or leaks.
struct Point { var x: Int; var y: Int }
struct Labeled { var name: String; var size: Double?; var tags: [String] }
struct Wrapper<T> { var value: T }
struct Empty {}
enum Mode { case light, dark }
enum Shape { case circle(radius: Double), rect(Double, Double), none }
indirect enum Tree { case leaf(Int), node(Tree, Tree) }
enum Status: String { case ok = "fine", bad }
enum Code: Int { case one = 1, two }
enum Failure: Error { case broken(String) }
final class Box { var n = 1 }
struct Outer { struct Inner { var v: Int8 }; var inner: Inner }
struct Holder { var mode: Mode; var shape: Shape; var point: Point? }

func describeCases() -> [(String, String)] {
  var out: [(String, String)] = []
  func add<T>(_ v: T) { out.append((String(describing: v), String(reflecting: v))) }
  add(42); add(-7); add(UInt8(255)); add(Int64.min)
  add(1.0); add(0.1); add(1e20); add(1e-7); add(-0.0); add(Double.nan); add(Double.infinity); add(123456789.125)
  add(Float(0.1)); add(Float(3)); add(Float.greatestFiniteMagnitude)
  add(true); add("plain"); add("quote\"tab\tnl\n\u{1F600}"); add(Character("é")); add(Unicode.Scalar(65))
  add(Optional(5)); add(Optional<Int>.none); add(Optional(Optional(1))); add(Optional<String>("s"))
  add([1, 2, 3]); add(["a", "b"]); add([Optional(1), nil]); add([Point(x: 1, y: 2)]); add([String]())
  add(["k": 1]); add(Set([3]))
  add((1, "two")); add((a: 1, b: 2.5)); add(())
  add(Point(x: 1, y: -2)); add(Labeled(name: "n", size: nil, tags: ["t"])); add(Labeled(name: "n", size: 2, tags: []))
  add(Wrapper(value: 3)); add(Wrapper(value: Mode.dark)); add(Empty())
  add(Mode.light); add(Shape.circle(radius: 2)); add(Shape.rect(1, 2)); add(Shape.none)
  add(Tree.node(.leaf(1), .leaf(2))); add(Status.ok); add(Code.two); add(Failure.broken("x"))
  add(Outer(inner: .init(v: 3))); add(Holder(mode: .dark, shape: .rect(3, 4), point: nil))
  add(Holder(mode: .light, shape: .circle(radius: 1), point: Point(x: 0, y: 0)))
  add(1..<3); add(1...3); add("abc".dropFirst()); add(Int.self); add(Point.self); add(Optional<Int>.self)
  add(Result<Int, Failure>.success(1)); add(Result<Int, Failure>.failure(.broken("y")))
  add(AnyHashable(3)); add(AnyHashable("h"))
  let any: Any = Point(x: 5, y: 6); add(any)
  let anyMode: Any = Mode.dark; add(anyMode)
  add([Mode.light: 1]); add(Box())
  add(Wrapper(value: Optional<Mode>.some(.light)))
  return out
}

let expected: [(String, String)] = [
  ("42", "42"),
  ("-7", "-7"),
  ("255", "255"),
  ("-9223372036854775808", "-9223372036854775808"),
  ("1.0", "1.0"),
  ("0.1", "0.1"),
  ("1e+20", "1e+20"),
  ("1e-07", "1e-07"),
  ("-0.0", "-0.0"),
  ("nan", "nan"),
  ("inf", "inf"),
  ("123456789.125", "123456789.125"),
  ("0.1", "0.1"),
  ("3.0", "3.0"),
  ("3.4028235e+38", "3.4028235e+38"),
  ("true", "true"),
  ("plain", "\"plain\""),
  ("quote\"tab\tnl\n😀", "\"quote\\\"tab\\tnl\\n😀\""),
  ("é", "\"é\""),
  ("Optional(\"A\")", "Optional(\"A\")"),
  ("Optional(5)", "Optional(5)"),
  ("nil", "nil"),
  ("Optional(Optional(1))", "Optional(Optional(1))"),
  ("Optional(\"s\")", "Optional(\"s\")"),
  ("[1, 2, 3]", "[1, 2, 3]"),
  ("[\"a\", \"b\"]", "[\"a\", \"b\"]"),
  ("[Optional(1), nil]", "[Optional(1), nil]"),
  ("[describe.Point(x: 1, y: 2)]", "[describe.Point(x: 1, y: 2)]"),
  ("[]", "[]"),
  ("[\"k\": 1]", "[\"k\": 1]"),
  ("[3]", "Set([3])"),
  ("(1, \"two\")", "(1, \"two\")"),
  ("(a: 1, b: 2.5)", "(a: 1, b: 2.5)"),
  ("()", "()"),
  ("Point(x: 1, y: -2)", "describe.Point(x: 1, y: -2)"),
  ("Labeled(name: \"n\", size: nil, tags: [\"t\"])", "describe.Labeled(name: \"n\", size: nil, tags: [\"t\"])"),
  ("Labeled(name: \"n\", size: Optional(2.0), tags: [])", "describe.Labeled(name: \"n\", size: Optional(2.0), tags: [])"),
  ("Wrapper<Int>(value: 3)", "describe.Wrapper<Swift.Int>(value: 3)"),
  ("Wrapper<Mode>(value: describe.Mode.dark)", "describe.Wrapper<describe.Mode>(value: describe.Mode.dark)"),
  ("Empty()", "describe.Empty()"),
  ("light", "describe.Mode.light"),
  ("circle(radius: 2.0)", "describe.Shape.circle(radius: 2.0)"),
  ("rect(1.0, 2.0)", "describe.Shape.rect(1.0, 2.0)"),
  ("none", "describe.Shape.none"),
  ("node(describe.Tree.leaf(1), describe.Tree.leaf(2))", "describe.Tree.node(describe.Tree.leaf(1), describe.Tree.leaf(2))"),
  ("ok", "describe.Status.ok"),
  ("two", "describe.Code.two"),
  ("broken(\"x\")", "describe.Failure.broken(\"x\")"),
  ("Outer(inner: describe.Outer.Inner(v: 3))", "describe.Outer(inner: describe.Outer.Inner(v: 3))"),
  ("Holder(mode: describe.Mode.dark, shape: describe.Shape.rect(3.0, 4.0), point: nil)", "describe.Holder(mode: describe.Mode.dark, shape: describe.Shape.rect(3.0, 4.0), point: nil)"),
  ("Holder(mode: describe.Mode.light, shape: describe.Shape.circle(radius: 1.0), point: Optional(describe.Point(x: 0, y: 0)))", "describe.Holder(mode: describe.Mode.light, shape: describe.Shape.circle(radius: 1.0), point: Optional(describe.Point(x: 0, y: 0)))"),
  ("1..<3", "Range(1..<3)"),
  ("1...3", "ClosedRange(1...3)"),
  ("bc", "\"bc\""),
  ("Int", "Swift.Int"),
  ("Point", "describe.Point"),
  ("Optional<Int>", "Swift.Optional<Swift.Int>"),
  ("success(1)", "Swift.Result<Swift.Int, describe.Failure>.success(1)"),
  ("failure(describe.Failure.broken(\"y\"))", "Swift.Result<Swift.Int, describe.Failure>.failure(describe.Failure.broken(\"y\"))"),
  ("3", "AnyHashable(3)"),
  ("h", "AnyHashable(\"h\")"),
  ("Point(x: 5, y: 6)", "describe.Point(x: 5, y: 6)"),
  ("dark", "describe.Mode.dark"),
  ("[describe.Mode.light: 1]", "[describe.Mode.light: 1]"),
  ("describe.Box", "describe.Box"),
  ("Wrapper<Optional<Mode>>(value: Optional(describe.Mode.light))", "describe.Wrapper<Swift.Optional<describe.Mode>>(value: Optional(describe.Mode.light))"),
]

@_silgen_name("swl_describe_all") public func describeAll() -> Int {
  let got = describeCases()
  var bad = 0
  if got.count != expected.count { print("describe: \(got.count) cases, \(expected.count) expected"); return 1 }
  for (i, (g, e)) in zip(got, expected).enumerated() {
    if g.0 != e.0 { print("describe case \(i): describing \(g.0.debugDescription), want \(e.0.debugDescription)"); bad += 1 }
    if g.1 != e.1 { print("describe case \(i): reflecting \(g.1.debugDescription), want \(e.1.debugDescription)"); bad += 1 }
  }
  return bad
}
