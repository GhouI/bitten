// The environment, proposed sizes, and animatable data.

import CoreGraphics

// MARK: - environment

public protocol EnvironmentKey {
  associatedtype Value
  static var defaultValue: Value { get }
  static func _valuesEqual(_ lhs: Value, _ rhs: Value) -> Bool
}
extension EnvironmentKey {
  /// Values of unknown equality compare unequal (so views update).
  public static func _valuesEqual(_ lhs: Value, _ rhs: Value) -> Bool { return false }
}
extension EnvironmentKey where Value: Equatable {
  public static func _valuesEqual(_ lhs: Value, _ rhs: Value) -> Bool { return lhs == rhs }
}

public struct EnvironmentValues: CustomStringConvertible {
  internal var _values: [ObjectIdentifier: Any] = [:]
  internal var _named: [String: Any] = [:]
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

// MARK: - observable objects in the environment

extension EnvironmentValues {
  /// The `@Observable` object of type `T` put in the environment with
  /// `.environment(object)`.
  public subscript<T: AnyObject & Observable>(objectType: T.Type) -> T? {
    get { return _values[ObjectIdentifier(T.self)] as? T }
    set { _values[ObjectIdentifier(T.self)] = newValue }
  }
}

/// Indexes key paths to environment objects by type.
struct _ObjectTypeKey<T: AnyObject & Observable>: Hashable {
  init() {}
  static func == (a: _ObjectTypeKey, b: _ObjectTypeKey) -> Bool { return true }
  func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(T.self)) }
}
extension EnvironmentValues {
  internal subscript<T: AnyObject & Observable>(_object key: _ObjectTypeKey<T>) -> T? {
    get { return self[T.self] }
    set { self[T.self] = newValue }
  }
  internal subscript<T: AnyObject & Observable>(_forcedObject key: _ObjectTypeKey<T>) -> T {
    guard let o = self[T.self] else {
      fatalError("No Observable object of type \(T.self) found. A View.environment(_:) for \(T.self) may be missing.")
    }
    return o
  }
}

extension Environment {
  public init(_ objectType: Value.Type) where Value: AnyObject & Observable {
    content = .keyPath(\EnvironmentValues[_forcedObject: _ObjectTypeKey<Value>()])
  }
  public init<T: AnyObject & Observable>(_ objectType: T.Type) where Value == T? {
    content = .keyPath(\EnvironmentValues[_object: _ObjectTypeKey<T>()])
  }
}

extension View {
  public func environment<T: AnyObject & Observable>(_ object: T?) -> some View {
    return modifier(_EnvironmentKeyWritingModifier(keyPath: \EnvironmentValues[_object: _ObjectTypeKey<T>()], value: object))
  }
}

// MARK: - more environment values

public enum ColorSchemeContrast: Hashable, CaseIterable, Sendable { case standard, increased }
public enum ControlActiveState: Hashable, CaseIterable, Sendable { case key, active, inactive }
public enum ControlSize: Hashable, CaseIterable, Sendable { case mini, small, regular, large, extraLarge }
public enum DynamicTypeSize: Hashable, Comparable, CaseIterable, Sendable {
  case xSmall, small, medium, large, xLarge, xxLarge, xxxLarge, accessibility1, accessibility2, accessibility3,
    accessibility4, accessibility5
  public var isAccessibilitySize: Bool { return self >= .accessibility1 }
}
public enum Visibility: Hashable, CaseIterable, Sendable { case automatic, visible, hidden }
public struct ButtonBorderShape: Equatable, Sendable {
  let kind: Int
  let radius: CGFloat
  public static let automatic = ButtonBorderShape(kind: 0, radius: 0)
  public static let capsule = ButtonBorderShape(kind: 1, radius: 0)
  public static let roundedRectangle = ButtonBorderShape(kind: 2, radius: 6)
  public static let circle = ButtonBorderShape(kind: 3, radius: 0)
  public static func roundedRectangle(radius: CGFloat) -> ButtonBorderShape { return ButtonBorderShape(kind: 2, radius: radius) }
}

@MainActor @preconcurrency
public struct DismissAction: Sendable {
  /// Inside a sheet or popover: closes it; elsewhere the key window.
  nonisolated(unsafe) let action: (() -> Void)?
  init(action: (() -> Void)? = nil) { self.action = action }
  public func callAsFunction() {
    if let a = action { a() } else { NSApp.keyWindow?.performClose(nil) }
  }
  public var isPresented: Bool { return action != nil }
}
struct _DismissKey: EnvironmentKey { static let defaultValue: DismissAction? = nil }

public struct OpenURLAction: Sendable {
  public struct Result: Sendable {
    let id: Int
    public static let handled = Result(id: 0)
    public static let discarded = Result(id: 1)
    public static let systemAction = Result(id: 2)
    public static func systemAction(_ url: URL) -> Result { return Result(id: 2) }
  }
  let handler: (URL) -> Result
  public init(handler: @escaping (URL) -> Result) { self.handler = handler }
  @MainActor public func callAsFunction(_ url: URL) {
    if handler(url).id == 2 { NSWorkspace.shared.open(url) }
  }
  @MainActor public func callAsFunction(_ url: URL, completion: @escaping (Bool) -> Void) {
    callAsFunction(url)
    completion(true)
  }
}

/// A stored environment value with a default, by name.
private func _envGet<V>(_ env: EnvironmentValues, _ name: String, _ dflt: V) -> V {
  return (env._named[name] as? V) ?? dflt
}
private func _envSet<V>(_ env: inout EnvironmentValues, _ name: String, _ v: V) { env._named[name] = v }

extension EnvironmentValues {
  public var _buttonBorderShape: ButtonBorderShape {
    get { return _envGet(self, "buttonBorderShape", .automatic) }
    set { _envSet(&self, "buttonBorderShape", newValue) }
  }
  public var accessibilityDifferentiateWithoutColor: Bool { return false }
  public var accessibilityReduceMotion: Bool { return false }
  public var accessibilityReduceTransparency: Bool { return false }
  public var accessibilityVoiceOverEnabled: Bool { return false }
  public var accessibilityInvertColors: Bool { return false }
  public var appearsActive: Bool {
    get { return _envGet(self, "appearsActive", true) }
    set { _envSet(&self, "appearsActive", newValue) }
  }
  public var colorSchemeContrast: ColorSchemeContrast { return .standard }
  public var contentTransition: ContentTransition {
    get { return _envGet(self, "contentTransition", .identity) }
    set { _envSet(&self, "contentTransition", newValue) }
  }
  public var controlActiveState: ControlActiveState {
    get { return _envGet(self, "controlActiveState", .key) }
    set { _envSet(&self, "controlActiveState", newValue) }
  }
  public var controlSize: ControlSize {
    get { return _envGet(self, "controlSize", .regular) }
    set { _envSet(&self, "controlSize", newValue) }
  }
  @MainActor public var dismiss: DismissAction { return self[_DismissKey.self] ?? DismissAction() }
  public var isPresented: Bool { return self[_DismissKey.self] != nil }
  public var displayScale: CGFloat {
    get { return _envGet(self, "displayScale", CGFloat(1)) }
    set { _envSet(&self, "displayScale", newValue) }
  }
  public var dynamicTypeSize: DynamicTypeSize {
    get { return _envGet(self, "dynamicTypeSize", .large) }
    set { _envSet(&self, "dynamicTypeSize", newValue) }
  }
  public var layoutDirection: LayoutDirection {
    get { return _envGet(self, "layoutDirection", .leftToRight) }
    set { _envSet(&self, "layoutDirection", newValue) }
  }
  public var locale: Locale {
    get { return _envGet(self, "locale", Locale.current) }
    set { _envSet(&self, "locale", newValue) }
  }
  public var menuIndicatorVisibility: Visibility {
    get { return _envGet(self, "menuIndicatorVisibility", .automatic) }
    set { _envSet(&self, "menuIndicatorVisibility", newValue) }
  }
  public var openURL: OpenURLAction {
    get { return _envGet(self, "openURL", OpenURLAction { _ in .systemAction }) }
    set { _envSet(&self, "openURL", newValue) }
  }
  public var symbolRenderingMode: SymbolRenderingMode? {
    get { return _envGet(self, "symbolRenderingMode", nil) }
    set { _envSet(&self, "symbolRenderingMode", newValue) }
  }
  @MainActor public var undoManager: UndoManager? { return _AppHost.shared.undoManager }
}

extension View {
  public func controlSize(_ size: ControlSize) -> some View { return environment(\.controlSize, size) }
  public func dynamicTypeSize(_ size: DynamicTypeSize) -> some View { return environment(\.dynamicTypeSize, size) }
}
