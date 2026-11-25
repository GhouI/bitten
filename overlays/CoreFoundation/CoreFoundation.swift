// The Swift overlay of CoreFoundation (libswiftCoreFoundation.dylib): the C
// module re-exported, plus the Swift-only API programs bind to.
@_exported import CoreFoundation

/// CF types imported into Swift conform to this, so that they are Hashable
/// and Equatable through CFHash and CFEqual.
public protocol _CFObject: AnyObject, Hashable {}

extension _CFObject {
  public var hashValue: Int {
    return Int(bitPattern: CFHash(unsafeBitCast(self, to: CFTypeRef.self)))
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(hashValue)
  }
  public static func == (left: Self, right: Self) -> Bool {
    return CFEqual(unsafeBitCast(left, to: CFTypeRef.self), unsafeBitCast(right, to: CFTypeRef.self)) != 0
  }
}
