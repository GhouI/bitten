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

/// What is currently being tracked on this thread (a stack, because
/// tracking can nest).
nonisolated(unsafe) private var trackingStack: [_Tracking] = []

/// Registrations waiting for a change, by observed property.
nonisolated(unsafe) private var waiting: [_Key: [_Tracking]] = [:]

public struct ObservationRegistrar: Sendable {
  public init() {}

  public func access<Subject: Observable, Member>(_ subject: Subject, keyPath: KeyPath<Subject, Member>) {
    guard let current = trackingStack.last else { return }
    guard let object = subject as? AnyObject else { return }
    current.observed.insert(_Key(object: ObjectIdentifier(object), keyPath: keyPath))
  }

  public func willSet<Subject: Observable, Member>(_ subject: Subject, keyPath: KeyPath<Subject, Member>) {
    guard let object = subject as? AnyObject else { return }
    let key = _Key(object: ObjectIdentifier(object), keyPath: keyPath)
    guard let list = waiting.removeValue(forKey: key) else { return }
    for t in list {
      // Fire once, and stop listening to the other properties it read.
      for other in t.observed where other != key {
        waiting[other]?.removeAll { $0 === t }
      }
      let change = t.onChange
      t.onChange = nil
      change?()
    }
  }

  public func didSet<Subject: Observable, Member>(_ subject: Subject, keyPath: KeyPath<Subject, Member>) {}

  public func withMutation<Subject: Observable, Member, T>(of subject: Subject, keyPath: KeyPath<Subject, Member>,
                                                           _ mutation: () throws -> T) rethrows -> T {
    willSet(subject, keyPath: keyPath)
    defer { didSet(subject, keyPath: keyPath) }
    return try mutation()
  }
}

extension ObservationRegistrar: Hashable {
  public static func == (lhs: ObservationRegistrar, rhs: ObservationRegistrar) -> Bool { return true }
  public func hash(into hasher: inout Hasher) {}
}

public func withObservationTracking<T>(_ apply: () -> T, onChange: @autoclosure () -> @Sendable () -> Void) -> T {
  let t = _Tracking()
  trackingStack.append(t)
  let result = apply()
  trackingStack.removeLast()
  if !t.observed.isEmpty {
    t.onChange = onChange()
    for key in t.observed { waiting[key, default: []].append(t) }
  }
  return result
}
