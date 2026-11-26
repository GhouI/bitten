// Values (decoded JSON holding strings, arrays, dictionaries) handed from
// background tasks to the main actor through every route the concurrency
// runtime offers, then read through key paths; and Observation's tables
// used from many threads at once. Run under valgrind to see ownership bugs.
import Foundation
import Observation
@_silgen_name("swl_check") func check(_ ok: Bool, _ line: Int)
@_silgen_name("swl_done") func done() -> Never

struct Model: Codable, Sendable { var a: String; var b: String; var c: [String]; var d: [String: String] }
func make(_ i: Int) -> Model {
  let json = "{\"a\":\"alpha-\(i)-xxxxxxxxxxxxxxxxxxxxxxxx\",\"b\":\"beta-\(i)-yyyyyyyyyyyyyyyyyyyyyy\",\"c\":[\"c1-\(i)-zzzzzzzzzzzzzzzzzzz\",\"c2\"],\"d\":{\"k-\(i)-kkkkkkkkkkkkkkkkkkkkk\":\"v-\(i)-vvvvvvvvvvvvvvvvvvvvvvvvvvv\"}}"
  return try! JSONDecoder().decode(Model.self, from: json.data(using: .utf8)!)
}
func use(_ m: Model) -> Int { return m.a.count + m.b.count + m.c.joined().count + m.d.keys.joined().count }

@MainActor final class Store { var models: [String: Model] = [:]; var list: [Model] = [] }

@_silgen_name("swl_handoff_start") public func start() {
  Task { @MainActor in
    let store = Store()
    var total = 0
    for i in 0..<30 {
      // task value
      let m1 = await Task.detached { make(i) }.value
      store.models[m1.a] = m1
      // async stream from a background task
      let s = AsyncStream<Model> { cont in Task.detached { for j in 0..<3 { cont.yield(make(i * 10 + j)) }; cont.finish() } }
      for await m in s { store.list.append(m) }
      // continuation
      let m3: Model = await withCheckedContinuation { c in Task.detached { c.resume(returning: make(i + 1000)) } }
      store.models[m3.b] = m3
      // task group
      let ms = await withTaskGroup(of: Model.self) { g in
        for j in 0..<3 { g.addTask { make(j + 2000) } }
        var out: [Model] = []
        for await m in g { out.append(m) }
        return out
      }
      store.list += ms
      // async let
      // MainActor.run from background
      await Task.detached { let m = make(i + 4000); await MainActor.run { store.list.append(m) } }.value
      if store.list.count > 20 { store.list.removeFirst(10) }
      total += store.models.values.reduce(0) { $0 + use($1) } + store.list.reduce(0) { $0 + use($1) }
    }
    // key paths over string-holding values
    struct Outer { var m: Model; var opt: Model?; var arr: [Model] }
    final class Box { var o: Outer; init(_ o: Outer) { self.o = o } }
    var o = Outer(m: make(1), opt: make(2), arr: [make(3), make(4)])
    let box = Box(o)
    let kps: [KeyPath<Outer, String>] = [\Outer.m.a, \Outer.m.b, \Outer.arr[1].a]
    let wk: WritableKeyPath<Outer, String> = \Outer.m.a
    let ck: ReferenceWritableKeyPath<Box, String> = \Box.o.m.b
    let any: AnyKeyPath = \Outer.m
    let optk: KeyPath<Outer, String?> = \Outer.opt?.a
    for i in 0..<200 {
      for k in kps { total += o[keyPath: k].count }
      o[keyPath: wk] = "written-\(i)-wwwwwwwwwwwwwwwwwwwwwwwwwww"
      box[keyPath: ck] = "class-\(i)-ccccccccccccccccccccccccccccc"
      total += box[keyPath: ck].count + (o[keyPath: optk]?.count ?? 0)
      if let m = o[keyPath: any] as? Model { total += m.a.count }
      let appended = (\Outer.m).appending(path: \Model.c)
      total += o[keyPath: appended].count
    }
    check(total > 0, #line)
    // Observation from many threads: tracking on this one while background
    // tasks write (the app mutates models off the main thread).
    final class Counter: Observable, @unchecked Sendable {
      let registrar = ObservationRegistrar()
      var _n = 0
      var n: Int {
        get { registrar.access(self, keyPath: \.n); return _n }
        set { registrar.withMutation(of: self, keyPath: \.n) { _n = newValue } }
      }
    }
    let counter = Counter()
    await withTaskGroup(of: Void.self) { g in
      for _ in 0..<8 { g.addTask { for _ in 0..<500 { counter.n += 1 } } }
      for _ in 0..<500 { _ = withObservationTracking({ counter.n }, onChange: {}) }
    }
    check(counter.n > 0, #line)
    done()
  }
}
