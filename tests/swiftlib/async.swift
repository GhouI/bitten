// Tasks, futures, continuations resumed from other threads, cancellation.
// The C driver (async.c) calls swl_async_start, then dispatch_main; the
// last test ends the process with swl_done.

@_silgen_name("swl_check") func check(_ ok: Bool, _ line: Int)
@_silgen_name("swl_done") func done() -> Never
@_silgen_name("swl_on_main_thread") func onMainThread() -> Bool
// Calls back `fn(ctx)` from another thread (dispatch_async_f on a global queue).
@_silgen_name("swl_call_later") func callLater(_ ctx: UnsafeMutableRawPointer, _ fn: @convention(c) (UnsafeMutableRawPointer) -> Void)

@inline(never) func twice(_ x: Int) async -> Int {
  await Task.yield()
  return x * 2
}

struct Oops: Error { var code: Int }

@inline(never) func failing(_ x: Int) async throws -> Int {
  await Task.yield()
  if x < 0 { throw Oops(code: x) }
  return x + 1
}

// A continuation is one word (the task): it travels through C as a pointer.
func valueFromAnotherThread(_ v: Int) async -> Int {
  let x = await withUnsafeContinuation { (c: UnsafeContinuation<Int, Never>) in
    callLater(unsafeBitCast(c, to: UnsafeMutableRawPointer.self)) { raw in
      let c = unsafeBitCast(raw, to: UnsafeContinuation<Int, Never>.self)
      c.resume(returning: onMainThread() ? -1 : 1000)
    }
  }
  return x + v
}

func errorFromAnotherThread(_ v: Int) async throws -> Int {
  let r = try await withUnsafeThrowingContinuation { (c: UnsafeContinuation<Int, any Error>) in
    let raw = unsafeBitCast(c, to: UnsafeMutableRawPointer.self)
    if v < 0 {
      callLater(raw) { raw in
        unsafeBitCast(raw, to: UnsafeContinuation<Int, any Error>.self).resume(throwing: Oops(code: -3))
      }
    } else {
      callLater(raw) { raw in
        unsafeBitCast(raw, to: UnsafeContinuation<Int, any Error>.self).resume(returning: 9)
      }
    }
  }
  return r
}

func checked(_ v: Int) async -> Int {
  return await withCheckedContinuation { c in
    c.resume(returning: v * 3)
  }
}

actor Counter {
  var count = 0
  func add(_ n: Int) -> Int {
    let before = count
    count = before + n
    return count
  }
}

@MainActor var mainTouches = 0

@MainActor func touchMain() -> Bool {
  mainTouches += 1
  return onMainThread()
}

func tests() async {
  // plain awaits and futures
  check(await twice(21) == 42, #line)
  let t = Task.detached { await twice(5) }
  check(await t.value == 10, #line)
  let tt = Task { try await failing(1) }
  check(try! await tt.value == 2, #line)
  let te = Task { try await failing(-7) }
  do {
    _ = try await te.value
    check(false, #line)
  } catch let e as Oops {
    check(e.code == -7, #line)
  } catch {
    check(false, #line)
  }
  switch await te.result {
  case .success: check(false, #line)
  case .failure(let e): check((e as! Oops).code == -7, #line)
  }

  // many tasks at once
  var sum = 0
  for i in 0..<50 {
    let task = Task.detached { await twice(i) }
    sum += await task.value
  }
  check(sum == 49 * 50, #line)

  // continuations
  check(await valueFromAnotherThread(7) == 1007, #line)
  check(try! await errorFromAnotherThread(9) == 9, #line)
  do {
    _ = try await errorFromAnotherThread(-3)
    check(false, #line)
  } catch {
    check((error as! Oops).code == -3, #line)
  }
  check(await checked(4) == 12, #line)

  // actors serialize access
  let counter = Counter()
  var last = 0
  for _ in 0..<100 {
    let h = Task.detached { await counter.add(1) }
    last = max(last, await h.value)
  }
  check(await counter.count == 100, #line)
  check(last == 100, #line)

  // the main actor runs on the main thread
  check(await touchMain(), #line)
  check(await mainTouches == 1, #line)
  let fromDetached = await Task.detached { await touchMain() }.value
  check(fromDetached, #line)

  // cancellation
  let sleeper = Task.detached { () -> Bool in
    while !Task.isCancelled { await Task.yield() }
    return true
  }
  sleeper.cancel()
  check(await sleeper.value, #line)
  check(sleeper.isCancelled, #line)
  check(!Task.isCancelled, #line)
}

@_silgen_name("swl_async_start")
public func start() {
  Task { @MainActor in
    await tests()
    done()
  }
}
