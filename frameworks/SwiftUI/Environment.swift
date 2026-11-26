// The environment, proposed sizes, and animatable data.

import CoreGraphics

// MARK: - environment

public protocol EnvironmentKey {
  associatedtype Value
  static var defaultValue: Value { get }
}

public struct EnvironmentValues: CustomStringConvertible {
  internal var _values: [ObjectIdentifier: Any] = [:]
  public init() {}

  public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
    get { return (_values[ObjectIdentifier(key)] as? K.Value) ?? K.defaultValue }
    set { _values[ObjectIdentifier(key)] = newValue }
  }
  public var description: String { return "EnvironmentValues(\(_values.count) values)" }
}

@frozen @propertyWrapper
public struct Environment<Value>: DynamicProperty {
  @usableFromInline @frozen
  internal enum Content {
    case keyPath(KeyPath<EnvironmentValues, Value>)
    case value(Value)
  }
  @usableFromInline internal var content: Content

  @inlinable public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { content = .keyPath(keyPath) }

  @inlinable public var wrappedValue: Value {
    switch content {
    case .value(let v): return v
    case .keyPath(let kp): return EnvironmentValues()[keyPath: kp]
    }
  }
}

extension Environment: _GraphInstallable {
  mutating func _install(key: String, inputs: _ViewInputs) {
    if case .keyPath(let kp) = content { content = .value(inputs.environment[keyPath: kp]) }
  }
}

// MARK: - sizes

@frozen
public struct ProposedViewSize: Equatable, Sendable {
  public var width: CGFloat?
  public var height: CGFloat?
  @inlinable public init(width: CGFloat?, height: CGFloat?) {
    self.width = width
    self.height = height
  }
  @inlinable public init(_ size: CGSize) {
    width = size.width
    height = size.height
  }
  public static let zero = ProposedViewSize(width: 0, height: 0)
  public static let unspecified = ProposedViewSize(width: nil, height: nil)
  public static let infinity = ProposedViewSize(width: .infinity, height: .infinity)
  public func replacingUnspecifiedDimensions(by size: CGSize = CGSize(width: 10, height: 10)) -> CGSize {
    return CGSize(width: width ?? size.width, height: height ?? size.height)
  }
}

// MARK: - animatable data

public protocol VectorArithmetic: AdditiveArithmetic {
  mutating func scale(by rhs: Double)
  var magnitudeSquared: Double { get }
}

extension Double: VectorArithmetic {
  public mutating func scale(by rhs: Double) { self *= rhs }
  public var magnitudeSquared: Double { return self * self }
}
extension Float: VectorArithmetic {
  public mutating func scale(by rhs: Double) { self *= Float(rhs) }
  public var magnitudeSquared: Double { return Double(self * self) }
}
extension CGFloat: VectorArithmetic {
  public mutating func scale(by rhs: Double) { self *= CGFloat(rhs) }
  public var magnitudeSquared: Double { return Double(self * self) }
}

@frozen
public struct EmptyAnimatableData: VectorArithmetic {
  @inlinable public init() {}
  @inlinable public static var zero: EmptyAnimatableData { return .init() }
  @inlinable public static func += (lhs: inout EmptyAnimatableData, rhs: EmptyAnimatableData) {}
  @inlinable public static func -= (lhs: inout EmptyAnimatableData, rhs: EmptyAnimatableData) {}
  @inlinable public static func + (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData { return .zero }
  @inlinable public static func - (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData { return .zero }
  @inlinable public mutating func scale(by rhs: Double) {}
  @inlinable public var magnitudeSquared: Double { return 0 }
  public static func == (a: EmptyAnimatableData, b: EmptyAnimatableData) -> Bool { return true }
}

@frozen
public struct AnimatablePair<First: VectorArithmetic, Second: VectorArithmetic>: VectorArithmetic {
  public var first: First
  public var second: Second
  @inlinable public init(_ first: First, _ second: Second) {
    self.first = first
    self.second = second
  }
  public static var zero: AnimatablePair { return AnimatablePair(.zero, .zero) }
  public static func + (a: AnimatablePair, b: AnimatablePair) -> AnimatablePair { return AnimatablePair(a.first + b.first, a.second + b.second) }
  public static func - (a: AnimatablePair, b: AnimatablePair) -> AnimatablePair { return AnimatablePair(a.first - b.first, a.second - b.second) }
  public static func += (a: inout AnimatablePair, b: AnimatablePair) { a = a + b }
  public static func -= (a: inout AnimatablePair, b: AnimatablePair) { a = a - b }
  public mutating func scale(by rhs: Double) {
    first.scale(by: rhs)
    second.scale(by: rhs)
  }
  public var magnitudeSquared: Double { return first.magnitudeSquared + second.magnitudeSquared }
  public static func == (a: AnimatablePair, b: AnimatablePair) -> Bool { return a.first == b.first && a.second == b.second }
}

public protocol Animatable {
  associatedtype AnimatableData: VectorArithmetic
  var animatableData: AnimatableData { get set }
  static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs)
}

extension Animatable where AnimatableData == EmptyAnimatableData {
  public var animatableData: EmptyAnimatableData {
    @inlinable get { return EmptyAnimatableData() }
    @inlinable set {}
  }
  public static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs) {}
}

extension Animatable {
  public static func _makeAnimatable(value: inout _GraphValue<Self>, inputs: _GraphInputs) {}
}
