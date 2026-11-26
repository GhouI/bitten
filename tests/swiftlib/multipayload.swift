// Values of generic multi-payload enums made by compiled code (static
// layout) and taken apart by generic code (the runtime's layout).
final class Box { let s: String; init(_ s: String) { self.s = s }; deinit { boxes -= 1 } }
nonisolated(unsafe) var boxes = 0
func box(_ s: String) -> Box { boxes += 1; return Box(s) }
struct Model { var a: String; var b: [String]; var c: Box }
enum E<T> { case one(T); case two(String, Box); case three; case four(Int) }
enum P<T> { case some(T), err(any Error), none }
struct Err: Error { let b: Box }

@inline(never) func gcopy<T>(_ v: T) -> [T] { var out = [v, v]; out.append(v); out.removeFirst(); return out }
@inline(never) func gtag<T>(_ v: E<T>) -> Int {
  switch v { case .one: return 1; case .two: return 2; case .three: return 3; case .four: return 4 }
}
@inline(never) func gtagP<T>(_ v: P<T>) -> Int { switch v { case .some: return 1; case .err: return 2; case .none: return 3 } }
@_silgen_name("swl_multipayload") public func mpe() -> Int {
  var bad = 0
  do {
    let m = Model(a: "a-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", b: ["b"], c: box("c"))
    let vals: [E<Model>] = [.one(m), .two("two-yyyyyyyyyyyyyyyyyyyyyyyy", box("t")), .three, .four(7)]
    for (i, v) in vals.enumerated() {
      if gtag(v) != i + 1 { bad |= 1 << i }
      let c = gcopy(v)
      if gtag(c[1]) != i + 1 { bad |= 16 << i }
    }
    let r: [Result<Model, any Error>] = [.success(m), .failure(Err(b: box("e")))]
    for (i, v) in r.enumerated() {
      let c = gcopy(v)
      switch c[0] { case .success(let x): if i != 0 || x.c.s != "c" { bad |= 256 }; case .failure: if i != 1 { bad |= 512 } }
    }
    let ps: [P<Model>] = [.some(m), .err(Err(b: box("f"))), .none]
    for (i, v) in ps.enumerated() { if gtagP(gcopy(v)[0]) != i + 1 { bad |= 1024 << i } }
    let opt: [Model?] = [m, nil]
    for (i, v) in opt.enumerated() { if (gcopy(v)[0] == nil) != (i == 1) { bad |= 8192 << i } }
  }
  if boxes != 0 { bad |= 1 << 20 }
  return bad
}
