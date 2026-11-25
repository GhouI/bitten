// SetAlgebra and OptionSet. Imported C option sets (NS_OPTIONS) and Swift
// option sets are OptionSet structs over a FixedWidthInteger raw value; the
// operations come from the default implementations here. Declarations
// follow Apple's, including which arguments are __owned (that is in the
// mangled names programs bind to).

public protocol SetAlgebra<Element>: Equatable, ExpressibleByArrayLiteral {
  associatedtype Element

  init()
  func contains(_ member: Element) -> Bool
  __consuming func union(_ other: __owned Self) -> Self
  __consuming func intersection(_ other: Self) -> Self
  __consuming func symmetricDifference(_ other: __owned Self) -> Self
  @discardableResult
  mutating func insert(_ newMember: __owned Element) -> (inserted: Bool, memberAfterInsert: Element)
  @discardableResult
  mutating func remove(_ member: Element) -> Element?
  @discardableResult
  mutating func update(with newMember: __owned Element) -> Element?
  mutating func formUnion(_ other: __owned Self)
  mutating func formIntersection(_ other: Self)
  mutating func formSymmetricDifference(_ other: __owned Self)
  __consuming func subtracting(_ other: Self) -> Self
  func isSubset(of other: Self) -> Bool
  func isDisjoint(with other: Self) -> Bool
  func isSuperset(of other: Self) -> Bool
  var isEmpty: Bool { get }
  init<S: Sequence>(_ sequence: __owned S) where S.Element == Element
  mutating func subtract(_ other: Self)
}

extension SetAlgebra {
  @inlinable
  public init<S: Sequence>(_ sequence: __owned S) where S.Element == Element {
    self.init()
    for e in sequence { insert(e) }
  }

  @inlinable
  public mutating func subtract(_ other: Self) {
    self.formIntersection(self.symmetricDifference(other))
  }

  @inlinable
  public func isSubset(of other: Self) -> Bool {
    return self.intersection(other) == self
  }

  @inlinable
  public func isSuperset(of other: Self) -> Bool {
    return other.isSubset(of: self)
  }

  @inlinable
  public func isDisjoint(with other: Self) -> Bool {
    return self.intersection(other).isEmpty
  }

  @inlinable
  public func subtracting(_ other: Self) -> Self {
    return self.intersection(self.symmetricDifference(other))
  }

  @inlinable
  public var isEmpty: Bool {
    return self == Self()
  }

  @inlinable
  public func isStrictSuperset(of other: Self) -> Bool {
    return self.isSuperset(of: other) && self != other
  }

  @inlinable
  public func isStrictSubset(of other: Self) -> Bool {
    return other.isStrictSuperset(of: self)
  }
}

extension SetAlgebra where Element == ArrayLiteralElement {
  @inlinable
  public init(arrayLiteral: Element...) {
    self.init(arrayLiteral)
  }
}

extension Set: SetAlgebra {
  public __consuming func union(_ other: __owned Set<Element>) -> Set<Element> {
    var result = self
    result.formUnion(other)
    return result
  }

  public mutating func formUnion(_ other: __owned Set<Element>) {
    for e in other { insert(e) }
  }

  public mutating func formIntersection(_ other: Set<Element>) {
    self = intersection(other)
  }

  public __consuming func symmetricDifference(_ other: __owned Set<Element>) -> Set<Element> {
    var result = self
    result.formSymmetricDifference(other)
    return result
  }
}

// ---- OptionSet --------------------------------------------------------------------

public protocol OptionSet: SetAlgebra, RawRepresentable {
  associatedtype Element = Self
  init(rawValue: RawValue)
}

extension OptionSet {
  @inlinable
  public func union(_ other: Self) -> Self {
    var r: Self = Self(rawValue: self.rawValue)
    r.formUnion(other)
    return r
  }

  @inlinable
  public func intersection(_ other: Self) -> Self {
    var r = Self(rawValue: self.rawValue)
    r.formIntersection(other)
    return r
  }

  @inlinable
  public func symmetricDifference(_ other: Self) -> Self {
    var r = Self(rawValue: self.rawValue)
    r.formSymmetricDifference(other)
    return r
  }
}

extension OptionSet where Element == Self {
  @inlinable
  public func contains(_ member: Self) -> Bool {
    return self.isSuperset(of: member)
  }

  @inlinable
  @discardableResult
  public mutating func insert(_ newMember: Element) -> (inserted: Bool, memberAfterInsert: Element) {
    let oldMember = self.intersection(newMember)
    let shouldInsert = oldMember != newMember
    let result = (inserted: shouldInsert, memberAfterInsert: shouldInsert ? newMember : oldMember)
    if shouldInsert {
      self.formUnion(newMember)
    }
    return result
  }

  @inlinable
  @discardableResult
  public mutating func remove(_ member: Element) -> Element? {
    let intersectionElements = intersection(member)
    guard !intersectionElements.isEmpty else {
      return nil
    }
    self.subtract(member)
    return intersectionElements
  }

  @inlinable
  @discardableResult
  public mutating func update(with newMember: Element) -> Element? {
    let r = self.intersection(newMember)
    self.formUnion(newMember)
    return r.isEmpty ? nil : r
  }
}

extension OptionSet where RawValue: FixedWidthInteger {
  @inlinable
  public init() {
    self.init(rawValue: 0)
  }

  @inlinable
  public mutating func formUnion(_ other: Self) {
    self = Self(rawValue: self.rawValue | other.rawValue)
  }

  @inlinable
  public mutating func formIntersection(_ other: Self) {
    self = Self(rawValue: self.rawValue & other.rawValue)
  }

  @inlinable
  public mutating func formSymmetricDifference(_ other: Self) {
    self = Self(rawValue: self.rawValue ^ other.rawValue)
  }
}
