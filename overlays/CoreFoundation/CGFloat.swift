// CGFloat lives in this library on current macOS but keeps the mangled
// module name it was first defined in, CoreGraphics.

@frozen
@available(macOS 10.15, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 14.0)
public struct CGFloat: Sendable {
  public typealias NativeType = Double
  public var native: NativeType
  @_transparent public init() { native = 0.0 }
  @_transparent public init(_ value: Float) { native = Double(value) }
  @_transparent public init(_ value: Double) { native = value }
  @_transparent public init(_ value: CGFloat) { native = value.native }
  @_transparent public init(_ value: Int) { native = Double(value) }
}

@available(macOS 10.15, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 14.0)
extension CGFloat: Equatable {
  @_transparent public static func == (lhs: CGFloat, rhs: CGFloat) -> Bool { return lhs.native == rhs.native }
}
