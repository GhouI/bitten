// Actors on custom serial executors: the runtime reaches the executor's
// Swift enqueue through _Concurrency's exported helper, and the actor's
// jobs run there, one at a time.
import Dispatch
@_silgen_name("swl_check") func check(_ ok: Bool, _ line: Int)
@_silgen_name("swl_done") func done() -> Never

final class QueueExecutor: SerialExecutor, @unchecked Sendable {
  let queue = DispatchQueue(label: "test.executor")
  var enqueued = 0  // only touched on `queue` or after the work is done
  func enqueue(_ job: consuming ExecutorJob) {
    let unowned = UnownedJob(job)
    let me = asUnownedSerialExecutor()
    queue.async {
      self.enqueued += 1
      unowned.runSynchronously(on: me)
    }
  }
  func asUnownedSerialExecutor() -> UnownedSerialExecutor { UnownedSerialExecutor(ordinary: self) }
}

actor Counter {
  let executor: QueueExecutor
  init(_ e: QueueExecutor) { executor = e }
  nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
  var n = 0
  var busy = false
  func bump() -> Int {
    check(!busy, #line)  // serial: never two at once
    busy = true
    n += 1
    busy = false
    return n
  }
}

@_silgen_name("swl_executors_start") public func start() {
  Task.detached {
    let ex = QueueExecutor()
    let c = Counter(ex)
    await withTaskGroup(of: Int.self) { g in
      for _ in 0..<200 { g.addTask { await c.bump() } }
      var seen = Set<Int>()
      for await v in g { seen.insert(v) }
      check(seen == Set(1...200), #line)
    }
    check(await c.n == 200, #line)
    let count = ex.queue.sync { ex.enqueued }
    check(count >= 200, #line)
    done()
  }
}
