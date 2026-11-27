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
  init() {}
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

/// What each thread is currently tracking (a stack, because tracking can
/// nest).
nonisolated(unsafe) private var trackingStacks: [UInt: [_Tracking]] = [:]

/// Registrations waiting for a change, by observed property.
nonisolated(unsafe) private var waiting: [_Key: [_Tracking]] = [:]

public struct ObservationRegistrar: Sendable {
  public init() {}

  public func access<Subject: Observable, Member>(_ subject: Subject, keyPath: KeyPath<Subject, Member>) {
    guard let object = subject as? AnyObject else { return }
    let key = _Key(object: ObjectIdentifier(object), keyPath: keyPath)
    let thread = _bitten_thread()
    locked {
      guard let current = trackingStacks[thread]?.last else { return }
      current.observed.insert(key)
    }
  }

  public func willSet<Subject: Observable, Member>(_ subject: Subject, keyPath: KeyPath<Subject, Member>) {
    guard let object = subject as? AnyObject else { return }
    let key = _Key(object: ObjectIdentifier(object), keyPath: keyPath)
    let changes: [() -> Void] = locked {
      guard let list = waiting.removeValue(forKey: key) else { return [] }
      var out: [() -> Void] = []
      for t in list {
        // Fire once, and stop listening to the other properties it read.
        for other in t.observed where other != key {
          waiting[other]?.removeAll { $0 === t }
        }
        if let change = t.onChange { out.append(change) }
        t.onChange = nil
      }
      return out
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
  if !observed.isEmpty {
    let change = onChange()
    locked {
      t.onChange = change
      for key in observed { waiting[key, default: []].append(t) }
    }
  }
  return result
}
