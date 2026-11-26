// Sorting with comparators: SortComparator, SortOrder, KeyPathComparator
// and the sort(using:)/sorted(using:) entry points.

public enum SortOrder: Hashable, Codable, Sendable {
  case forward
  case reverse
}

public protocol SortComparator<Compared>: Hashable {
  associatedtype Compared
  func compare(_ lhs: Compared, _ rhs: Compared) -> ComparisonResult
  var order: SortOrder { get set }
}

extension ComparisonResult {
  internal func _ordered(_ order: SortOrder) -> ComparisonResult {
    guard order == .reverse else { return self }
    switch self {
    case .orderedAscending: return .orderedDescending
    case .orderedDescending: return .orderedAscending
    default: return self
    }
  }
}

/// Compares values by the Comparable value at a key path.
public struct KeyPathComparator<Compared>: SortComparator {
  public let keyPath: PartialKeyPath<Compared>
  public var order: SortOrder
  private let _compare: (Compared, Compared) -> ComparisonResult
  public init<Value: Comparable>(_ keyPath: KeyPath<Compared, Value>, order: SortOrder = .forward) {
    self.keyPath = keyPath
    self.order = order
    _compare = { a, b in
      let x = a[keyPath: keyPath], y = b[keyPath: keyPath]
      return x < y ? .orderedAscending : (y < x ? .orderedDescending : .orderedSame)
    }
  }
  public init<Value: Comparable>(_ keyPath: KeyPath<Compared, Value?>, order: SortOrder = .forward) {
    self.keyPath = keyPath
    self.order = order
    _compare = { a, b in
      switch (a[keyPath: keyPath], b[keyPath: keyPath]) {
      case let (x?, y?): return x < y ? .orderedAscending : (y < x ? .orderedDescending : .orderedSame)
      case (nil, nil): return .orderedSame
      case (nil, _): return .orderedAscending
      case (_, nil): return .orderedDescending
      }
    }
  }
  public func compare(_ lhs: Compared, _ rhs: Compared) -> ComparisonResult {
    return _compare(lhs, rhs)._ordered(order)
  }
  public static func == (a: KeyPathComparator, b: KeyPathComparator) -> Bool {
    return a.keyPath == b.keyPath && a.order == b.order
  }
  public func hash(into h: inout Hasher) {
    h.combine(keyPath)
    h.combine(order)
  }
}

extension Sequence {
  public func sorted<C: SortComparator>(using comparator: C) -> [Element] where C.Compared == Element {
    return sorted { comparator.compare($0, $1) == .orderedAscending }
  }
  public func sorted<S: Sequence, C: SortComparator>(using comparators: S) -> [Element]
    where S.Element == C, C.Compared == Element {
    let cs = Array(comparators)
    return sorted { a, b in
      for c in cs {
        let r = c.compare(a, b)
        if r != .orderedSame { return r == .orderedAscending }
      }
      return false
    }
  }
}

extension MutableCollection where Self: RandomAccessCollection {
  public mutating func sort<C: SortComparator>(using comparator: C) where C.Compared == Element {
    sort { comparator.compare($0, $1) == .orderedAscending }
  }
  public mutating func sort<S: Sequence, C: SortComparator>(using comparators: S)
    where S.Element == C, C.Compared == Element {
    let cs = Array(comparators)
    sort { a, b in
      for c in cs {
        let r = c.compare(a, b)
        if r != .orderedSame { return r == .orderedAscending }
      }
      return false
    }
  }
}
