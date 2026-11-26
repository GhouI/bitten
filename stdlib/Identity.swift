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

/// Lets a non-escaping closure be passed where an escaping one is needed,
/// for the duration of `body`. The type checker rewrites calls to this.
@_transparent
@_semantics("typechecker.withoutActuallyEscaping(_:do:)")
public func withoutActuallyEscaping<ClosureType, ResultType, Failure>(
  _ closure: ClosureType,
  do body: (_ escapingClosure: ClosureType) throws(Failure) -> ResultType
) throws(Failure) -> ResultType {
  Builtin.unreachable()
}

