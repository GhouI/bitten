// SetAlgebra and OptionSet: a Swift option set, an option set used through
// generic SetAlgebra code, and Set as a SetAlgebra.

struct Perm: OptionSet, Hashable {
  let rawValue: UInt8
  static let read = Perm(rawValue: 1)
  static let write = Perm(rawValue: 2)
  static let exec = Perm(rawValue: 4)
  static let all: Perm = [.read, .write, .exec]
}

@inline(never) func opaque<T>(_ x: T) -> T { return x }

@inline(never) func generic<S: SetAlgebra>(_ a: S, _ b: S, _ m: S.Element) -> Int {
  var bad = 0
  var u = a.union(b)
  if !u.contains(m) || u.isEmpty { bad |= 1 }
  if !a.isSubset(of: u) || !u.isSuperset(of: b) { bad |= 2 }
  u.subtract(b)
  if u != a.subtracting(b) { bad |= 4 }
  if !a.symmetricDifference(a).isEmpty { bad |= 8 }
  return bad
}

@_silgen_name("swl_optionsets_run") public func run() -> Int {
  var bad = 0
  var p: Perm = opaque([.read])
  if !p.contains(.read) || p.contains(.write) || p.rawValue != 1 { bad |= 1 }
  let r = p.insert(.write)
  if !r.inserted || p.rawValue != 3 || p.insert(.write).inserted { bad |= 2 }
  if p.remove(.read) != .read || p.remove(.read) != nil || p != .write { bad |= 4 }
  if Perm.all.rawValue != 7 || !Perm.all.isSuperset(of: p) || !p.isDisjoint(with: [.exec]) { bad |= 8 }
  if Perm.all.subtracting(.write) != [.read, .exec] || Perm().isEmpty == false { bad |= 16 }
  if p.update(with: .exec) != nil || p.rawValue != 6 { bad |= 32 }
  if Perm.all.intersection([.exec, .write]) != [.write, .exec] || Perm.read.symmetricDifference(.all).rawValue != 6 { bad |= 64 }
  bad |= generic(opaque(Perm.read), opaque(Perm.exec), .exec) << 8
  bad |= generic(opaque(Set([1, 2])), opaque(Set([3])), 3) << 12
  let s: Set = opaque([1, 2, 3])
  if !s.isSuperset(of: [1]) || s.intersection(Set([2, 9])) != [2] || s.union(Set([4])).count != 4 { bad |= 1 << 16 }
  return bad
}
