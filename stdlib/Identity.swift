// Identifiable and CaseIterable.

public protocol Identifiable<ID> {
  associatedtype ID: Hashable
  var id: ID { get }
}

extension Identifiable where Self: AnyObject {
  public var id: ObjectIdentifier { return ObjectIdentifier(self) }
}

/// The compiler synthesizes allCases for enums without associated values.
public protocol CaseIterable {
  associatedtype AllCases: Collection = [Self] where AllCases.Element == Self
  static var allCases: AllCases { get }
}
