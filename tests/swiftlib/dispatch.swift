// The Dispatch overlay: queues, groups, semaphores, timer sources, times,
// queue-specific values and DispatchData, run against bitten's libdispatch.
import Dispatch

struct Failure: Error {}

@_silgen_name("swl_dispatch_queues") public func queues() -> Int {
  var bad = 0
  let q = DispatchQueue(label: "test.serial")
  if q.label != "test.serial" { bad |= 1 }
  // sync returns values and rethrows errors
  if q.sync(execute: { 6 * 7 }) != 42 { bad |= 2 }
  do {
    _ = try q.sync { () throws -> Int in throw Failure() }
    bad |= 4
  } catch {}
  // async + group on a serial and a concurrent queue
  let group = DispatchGroup()
  let c = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
  let lock = DispatchSemaphore(value: 1)
  var total = 0
  for i in 1...100 {
    (i % 2 == 0 ? q : c).async(group: group) {
      lock.wait()
      total += i
      lock.signal()
    }
  }
  group.wait()
  if total != 5050 { bad |= 8 }
  // group.notify on another queue
  let done = DispatchSemaphore(value: 0)
  var notified = false
  group.enter()
  group.notify(queue: c) { notified = true; done.signal() }
  q.async { group.leave() }
  if done.wait(timeout: .now() + .seconds(5)) != .success || !notified { bad |= 16 }
  // global queues and concurrentPerform
  var slots = [Int](repeating: 0, count: 64)
  slots.withUnsafeMutableBufferPointer { buf in
    DispatchQueue.concurrentPerform(iterations: 64) { buf[$0] = $0 * 2 }
  }
  if slots[63] != 126 || slots.reduce(0, +) != 64 * 63 { bad |= 32 }
  let g = DispatchQueue.global(qos: .utility)
  if g.sync(execute: { 1 }) != 1 { bad |= 64 }
  // a semaphore that times out
  if DispatchSemaphore(value: 0).wait(timeout: .now() + .milliseconds(20)) != .timedOut { bad |= 128 }
  return bad
}

@_silgen_name("swl_dispatch_times") public func times() -> Int {
  var bad = 0
  let a = DispatchTime.now()
  let b = a + .milliseconds(5)
  if !(a < b) || b.uptimeNanoseconds - a.uptimeNanoseconds != 5_000_000 { bad |= 1 }
  if (a + 1.5).uptimeNanoseconds - a.uptimeNanoseconds != 1_500_000_000 { bad |= 2 }
  if DispatchTime(uptimeNanoseconds: 1234).uptimeNanoseconds != 1234 { bad |= 4 }
  if !(a < DispatchTime.distantFuture) || a + .never != .distantFuture { bad |= 8 }
  if DispatchTimeInterval.seconds(1) != .milliseconds(1000) || DispatchTimeInterval.never == .seconds(1) { bad |= 16 }
  let w = DispatchWallTime.now()
  if !(w < w + .seconds(1)) || !(w < .distantFuture) { bad |= 32 }
  // asyncAfter waits at least that long
  let q = DispatchQueue(label: "test.after")
  let fired = DispatchSemaphore(value: 0)
  let start = DispatchTime.now()
  var waited: UInt64 = 0
  q.asyncAfter(deadline: .now() + .milliseconds(30)) {
    waited = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
    fired.signal()
  }
  fired.wait()
  if waited < 30_000_000 { bad |= 64 }
  return bad
}

@_silgen_name("swl_dispatch_sources") public func sources() -> Int {
  var bad = 0
  let q = DispatchQueue(label: "test.timer")
  let timer = DispatchSource.makeTimerSource(queue: q)
  let ticks = DispatchSemaphore(value: 0)
  let cancelled = DispatchSemaphore(value: 0)
  var count = 0
  timer.setEventHandler {
    count += 1
    if count == 3 { timer.cancel() }
    ticks.signal()
  }
  timer.setCancelHandler { cancelled.signal() }
  timer.schedule(deadline: .now(), repeating: .milliseconds(5))
  timer.resume()
  for _ in 0..<3 { if ticks.wait(timeout: .now() + .seconds(5)) != .success { bad |= 1 } }
  if cancelled.wait(timeout: .now() + .seconds(5)) != .success { bad |= 2 }
  if count != 3 || !timer.isCancelled { bad |= 4 }
  // user data source
  let adds = DispatchSource.makeUserDataAddSource(queue: q)
  let got = DispatchSemaphore(value: 0)
  var sum: UInt = 0
  adds.setEventHandler { sum += adds.data; got.signal() }
  adds.activate()
  adds.add(data: 7)
  if got.wait(timeout: .now() + .seconds(5)) != .success || sum != 7 { bad |= 8 }
  adds.cancel()
  let events: DispatchSource.FileSystemEvent = [.write, .rename]
  if events.rawValue != 0x22 || !DispatchSource.FileSystemEvent.all.contains(.delete) { bad |= 16 }
  return bad
}

@_silgen_name("swl_dispatch_misc") public func misc() -> Int {
  var bad = 0
  let key = DispatchSpecificKey<String>()
  let q = DispatchQueue(label: "test.specific")
  q.setSpecific(key: key, value: "here")
  if q.sync(execute: { DispatchQueue.getSpecific(key: key) }) != "here" { bad |= 1 }
  if DispatchQueue.getSpecific(key: key) != nil { bad |= 2 }
  if !q.sync(execute: { _dispatchPreconditionTest(.onQueue(q)) }) { bad |= 4 }
  if !_dispatchPreconditionTest(.notOnQueue(q)) { bad |= 8 }
  let bytes: [UInt8] = [1, 2, 3, 4, 5]
  let d = bytes.withUnsafeBytes { DispatchData(bytes: $0) }
  var out = [UInt8](repeating: 0, count: 5)
  out.withUnsafeMutableBytes { d.copyBytes(to: $0, count: 5) }
  if d.count != 5 || out != bytes || d[4] != 5 { bad |= 16 }
  if DispatchQoS.userInitiated.qosClass != .userInitiated || DispatchQoS.QoSClass(rawValue: QOS_CLASS_UTILITY) != .utility { bad |= 32 }
  if !DispatchWorkItemFlags.enforceQoS.isSubset(of: [.enforceQoS, .barrier]) { bad |= 64 }
  // DispatchQueue.main is the main queue object.
  if DispatchQueue.main !== DispatchQueue.main { bad |= 128 }
  return bad
}
