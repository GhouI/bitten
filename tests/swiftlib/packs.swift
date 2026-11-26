// Parameter packs: variadic generic types and functions, metadata with
// packs (uniqued: one pointer per type), conditional conformances over a
// pack found at run time, and type names.

public protocol Describes { func describe() -> String }
extension Int: Describes { public func describe() -> String { return "i\(self)" } }
extension String: Describes { public func describe() -> String { return "s" + self } }

public struct Group<each T> {
  public let items: (repeat each T)
  public init(_ items: repeat each T) { self.items = (repeat each items) }
}
extension Group: Describes where repeat each T: Describes {
  public func describe() -> String {
    var parts: [String] = []
    for x in repeat each items { parts.append(x.describe()) }
    return parts.joined(separator: ",")
  }
}

@inline(never) func count<each T>(_ v: repeat each T) -> Int {
  var n = 0
  for _ in repeat each v { n += 1 }
  return n
}

@inline(never) func erase(_ x: Any) -> Any { return x }

@_silgen_name("swl_packs") public func packs() -> Int {
  var bad = 0
  let g = Group(1, "x", 3)
  if g.describe() != "i1,sx,i3" { bad |= 1 }
  if count(1, 2.5, "x") != 3 || count() != 0 { bad |= 2 }
  if let d = erase(g) as? Describes {
    if d.describe() != "i1,sx,i3" { bad |= 4 }
  } else {
    bad |= 8
  }
  let name = String(describing: type(of: g))
  if name != "Group<Pack{Int, String, Int}>" { bad |= 0x10 }
  if ObjectIdentifier(type(of: erase(Group(1, "a")))) != ObjectIdentifier(type(of: erase(Group(5, "b")))) { bad |= 0x20 }
  if ObjectIdentifier(type(of: erase(Group(1)))) == ObjectIdentifier(type(of: erase(Group("a")))) { bad |= 0x40 }
  if erase(Group(1, 2.5)) as? Describes != nil { bad |= 0x80 }   // Double does not describe
  if (erase(Group<Int, Int>(1, 2)) as? Describes)?.describe() != "i1,i2" { bad |= 0x100 }
  return bad
}
