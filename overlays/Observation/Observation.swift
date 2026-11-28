// Observation (libswiftObservation): the machinery behind @Observable.
// The macro expands each stored property into accessors that report reads
// (`access`) and writes (`withMutation`) to the object's registrar;
// `withObservationTracking` collects the reads made while it runs and calls
// `onChange` once, on the first write to any of them.

public protocol Observable {}

/// One `withObservationTracking` call in progress (or waiting for its
/// change): the properties it read and what to do when one changes.
final class _Tracking {
  var observed: Set<_Key> = []
  var onChange: (() -> Void)?
  /// Fired or cancelled: no longer waits on any property (lists drop it
  /// lazily).
  var done = false
  /// The lists it joined (a registrar that goes drops its lists, and a
  /// new one at the same address makes new ones: only these are its).
  /// (Weakly: a list holds its trackings.)
  var joined: [_Joined] = []
  init() {}
}
struct _Joined {
  let key: _Key
  weak var waiters: _Waiters?
}

/// The trackings waiting on one property, in the order they began. A
/// tracking that stops is counted out here and dropped from the list when
/// the dead outnumber the live, so cancelling the many trackings of a
/// rebuilt tree is not quadratic in how many watch the same property.
final class _Waiters {
  var list: [_Tracking] = []
  var dead = 0
  var live: Int { return list.count - dead }
}

struct _Key: Hashable {
  let object: ObjectIdentifier
  let keyPath: AnyKeyPath
}

@_silgen_name("os_unfair_lock_lock") internal func _bitten_lock(_ l: UnsafeMutablePointer<UInt32>)
@_silgen_name("os_unfair_lock_unlock") internal func _bitten_unlock(_ l: UnsafeMutablePointer<UInt32>)
@_silgen_name("pthread_self") internal func _bitten_thread() -> UInt

/// Shared by every thread: observable objects are read and written from
/// any of them (models mutated by background tasks while views track them
/// on the main thread), so the tables below are only touched under this
/// lock, and callbacks run outside it.
nonisolated(unsafe) private let lock: UnsafeMutablePointer<UInt32> = {
  let l = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
  l.initialize(to: 0)
  return l
}()
@inline(__always) private func locked<R>(_ body: () -> R) -> R {
  _bitten_lock(lock)
  defer { _bitten_unlock(lock) }
  return body()
}

@_silgen_name("getenv") internal func _bitten_getenv(_ name: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
@_silgen_name("write") internal func _bitten_write(_ fd: Int32, _ p: UnsafePointer<UInt8>?, _ n: Int) -> Int
/// BITTEN_OBSERVATION_DEBUG: log each write that fires a tracked change.
private let _debugObservation = _bitten_getenv("BITTEN_OBSERVATION_DEBUG") != nil

/// What each thread is currently tracking (a stack, because tracking can
/// nest).
nonisolated(unsafe) private var trackingStacks: [UInt: [_Tracking]] = [:]

/// Registrations waiting for a change, by observed property (of a
/// registrar), and the properties waited on per registrar.
nonisolated(unsafe) private var waiting: [_Key: _Waiters] = [:]
nonisolated(unsafe) private var waitedOn: [ObjectIdentifier: Set<AnyKeyPath>] = [:]

/// A registrar's identity. Registrations belong to it, as in Observation:
/// when the object (and so its registrar) goes, what waited on its
/// properties is let go, and a new object at the same address doesn't
/// fire it.
final class _RegistrarBox: @unchecked Sendable {
  deinit {
    let me = ObjectIdentifier(self)
    locked {
      guard let paths = waitedOn.removeValue(forKey: me) else { return }
      for p in paths { waiting[_Key(object: me, keyPath: p)] = nil }
    }
  }
}

private func _wait(_ t: _Tracking, _ key: _Key) {
  let w: _Waiters
  if let have = waiting[key] {
    w = have
  } else {
    w = _Waiters()
    waiting[key] = w
    waitedOn[key.object, default: []].insert(key.keyPath)
  }
  w.list.append(t)
  t.joined.append(_Joined(key: key, waiters: w))
}
/// A tracking (already marked done) leaves the list `w` it joined for `key`.
private func _unwait(_ w: _Waiters, _ key: _Key) {
  w.dead += 1
  guard waiting[key] === w else { return }   // dropped with its registrar
  if w.live <= 0 {
    waiting[key] = nil
    waitedOn[key.object]?.remove(key.keyPath)
    if waitedOn[key.object]?.isEmpty == true { waitedOn[key.object] = nil }
  } else if w.dead * 2 > w.list.count {
    w.list.removeAll { $0.done }
    w.dead = 0
  }
}

public struct ObservationRegistrar: Sendable {
  let box = _RegistrarBox()
  public init() {}

  public func access<Subject: Observable, Member>(_ subject: Subject, keyPath: KeyPath<Subject, Member>) {
    let key = _Key(object: ObjectIdentifier(box), keyPath: keyPath)
    let thread = _bitten_thread()
    locked {
      guard let current = trackingStacks[thread]?.last else { return }
      current.observed.insert(key)
    }
  }

  public func willSet<Subject: Observable, Member>(_ subject: Subject, keyPath: KeyPath<Subject, Member>) {
    let key = _Key(object: ObjectIdentifier(box), keyPath: keyPath)
    let changes: [() -> Void] = locked {
      guard let w = waiting.removeValue(forKey: key) else { return [] }
      waitedOn[key.object]?.remove(key.keyPath)
      if waitedOn[key.object]?.isEmpty == true { waitedOn[key.object] = nil }
      var out: [() -> Void] = []
      for t in w.list where !t.done {
        // Fire once, and stop listening to the other properties it read.
        t.done = true
        for j in t.joined { if let o = j.waiters, o !== w { _unwait(o, j.key) } }
        t.joined = []
        if let change = t.onChange { out.append(change) }
        t.onChange = nil
      }
      return out
    }
    if !changes.isEmpty && _debugObservation {
      var line = "bitten: observation: \(keyPath) changed\n"
      line.withUTF8 { _ = _bitten_write(2, $0.baseAddress, $0.count) }
    }
    for change in changes { change() }
  }

  public func didSet<Subject: Observable, Member>(_ subject: Subject, keyPath: KeyPath<Subject, Member>) {}

  public func withMutation<Subject: Observable, Member, T>(of subject: Subject, keyPath: KeyPath<Subject, Member>,
                                                           _ mutation: () throws -> T) rethrows -> T {
    willSet(subject, keyPath: keyPath)
    defer { didSet(subject, keyPath: keyPath) }
    return try mutation()
  }
}

extension ObservationRegistrar: Codable {
  public init(from decoder: any Decoder) throws { self.init() }
  public func encode(to encoder: any Encoder) throws {}
}

extension ObservationRegistrar: Hashable {
  public static func == (lhs: ObservationRegistrar, rhs: ObservationRegistrar) -> Bool { return true }
  public func hash(into hasher: inout Hasher) {}
}

public func withObservationTracking<T>(_ apply: () -> T, onChange: @autoclosure () -> @Sendable () -> Void) -> T {
  return _track(apply, onChange()).0
}

/// For SwiftUI here: tracks as withObservationTracking does, and returns a
/// token that stops the wait for a change (a view's tree rebuilt or gone
/// no longer needs to hear of the properties it read).
public func _bitten_withObservationTracking<T>(_ apply: () -> T,
                                               onChange: @escaping @Sendable () -> Void) -> (T, AnyObject?) {
  return _track(apply, onChange)
}
public func _bitten_cancelObservationTracking(_ token: AnyObject) {
  guard let t = token as? _Tracking else { return }
  locked {
    if t.done { return }
    t.done = true
    for j in t.joined { if let o = j.waiters { _unwait(o, j.key) } }
    t.joined = []
    t.onChange = nil
  }
}

private func _track<T>(_ apply: () -> T, _ onChange: @autoclosure () -> @Sendable () -> Void) -> (T, AnyObject?) {
  let t = _Tracking()
  let thread = _bitten_thread()
  locked { trackingStacks[thread, default: []].append(t) }
  let result = apply()
  let observed: Set<_Key> = locked {
    trackingStacks[thread]?.removeLast()
    if trackingStacks[thread]?.isEmpty == true { trackingStacks[thread] = nil }
    // What the inner tracking read, the enclosing one read too (as Swift's
    // Observation merges a nested access list into the one around it).
    trackingStacks[thread]?.last?.observed.formUnion(t.observed)
    return t.observed
  }
  if observed.isEmpty { return (result, nil) }
  let change = onChange()
  locked {
    t.onChange = change
    for key in observed { _wait(t, key) }
  }
  return (result, t)
}
