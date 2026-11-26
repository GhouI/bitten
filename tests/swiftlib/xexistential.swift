// Constrained existentials (`any P<T>`): their metadata comes from
// extended existential shapes, made at run time from a mangled name or
// by the compiler's direct calls.

protocol Source<Item> {
  associatedtype Item
  func next() -> Item
}
struct Counter: Source {
  var n: Int
  func next() -> Int { return n + 1 }
}
struct Word: Source {
  func next() -> String { return "word" }
}
final class Ref: Source {
  func next() -> Int { return 7 }
}

func boxed<T>(_ v: T) -> Any { return v }
func make<T>(_ t: T.Type) -> [T] { return [] }

@_silgen_name("swl_xexistential") public func xexistential() -> Int {
  var bad = 0
  let sources: [any Source<Int>] = [Counter(n: 1), Ref(), Counter(n: 41)]
  if sources.map({ $0.next() }) != [2, 7, 42] { bad |= 1 }
  // Generic code sees the existential through its metadata.
  let anyed = boxed(sources[0])
  if let s = anyed as? any Source<Int>, s.next() != 2 { bad |= 2 }
  if (anyed as? any Source<String>) != nil { bad |= 4 }
  let seq: any Sequence<Int> = [3, 4, 5]
  var total = 0
  for x in seq { total += x }
  if total != 12 { bad |= 8 }
  // A generic type instantiated with an extended existential.
  let arr = make((any Source<Int>).self)
  if !arr.isEmpty { bad |= 16 }
  if "\(type(of: arr))".isEmpty { bad |= 32 }
  let w: any Source<String> = Word()
  if w.next() != "word" { bad |= 64 }
  return bad
}
