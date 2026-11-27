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


// async let, actors, cancellation handlers, sleeps, throwing streams.
struct Small: Sendable { var a: String; var b: [String] }
@inline(never) func makeSmall(_ i: Int) async -> Small {
  await Task.yield()
  return Small(a: "alpha-\(i)-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", b: ["b-\(i)-yyyyyyyyyyyyyyyyyyyyyyyyy", "c"])
}
@inline(never) func asyncLetPair(_ i: Int) async -> Int {
  async let x = makeSmall(i)
  async let y = makeSmall(i + 1)
  let (p, q) = await (x, y)
  return p.a.count + q.b.joined().count
}
@inline(never) func asyncLetUnread(_ i: Int) async -> Int {
  async let x = makeSmall(i)
  return i
}
@inline(never) func asyncLetThrowing(_ i: Int) async throws -> Int {
  async let x: Small = { if i % 3 == 0 { throw CancellationError() }; return await makeSmall(i) }()
  return try await x.a.count
}
actor Library {
  var items: [String: Small] = [:]
  func put(_ s: Small) { items[s.a] = s }
  func all() -> [Small] { Array(items.values) }
  func take(_ k: String) -> Small? { items.removeValue(forKey: k) }
}

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
    // A property read inside nested tracking is watched by the enclosing
    // tracking too (Observation merges the inner accesses outward).
    final class Flag: @unchecked Sendable { var fired = false }
    let outer = Flag(), inner = Flag()
    let nested = Counter()
    withObservationTracking({
      _ = withObservationTracking({ nested.n }, onChange: { inner.fired = true })
    }, onChange: { outer.fired = true })
    nested.n += 1
    check(inner.fired && outer.fired, #line)
    var more = 0
    let lib = Library()
    for i in 0..<60 {
      more += await asyncLetPair(i) + (await asyncLetUnread(i)) + ((try? await asyncLetThrowing(i)) ?? 0)
      let s = await makeSmall(i)
      await lib.put(s)
      if let back = await lib.take(s.a) { more += back.b.count }
      await lib.put(s)
      more += await lib.all().count
      let r = await withTaskCancellationHandler { () -> Int in
        try? await Task.sleep(nanoseconds: 1000)
        return (await makeSmall(i)).a.count
      } onCancel: { }
      more += r
      let st = AsyncThrowingStream<Small, Error> { c in
        Task { for j in 0..<3 { c.yield(await makeSmall(j)) }; c.finish(throwing: i % 2 == 0 ? CancellationError() : nil) }
      }
      do { for try await x in st { more += x.a.count } } catch {}
      let g = await withThrowingTaskGroup(of: Small.self) { group -> Int in
        for j in 0..<4 { group.addTask { if j == 2 { throw CancellationError() }; return await makeSmall(j) } }
        var n = 0
        do { for try await x in group { n += x.a.count } } catch { group.cancelAll() }
        return n
      }
      more += g
    }
    check(more > 0, #line)
    done()
  }
}
