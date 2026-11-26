// Symbols: the effects SF Symbols can animate with. bitten draws no SF
// Symbols, so effects are values that describe themselves; SwiftUI's
// symbolEffect modifiers take them and draw the symbol still.

public struct SymbolEffectConfiguration: Hashable, Sendable {
  public var name: String
  public var options: [String]
  public init(name: String, options: [String] = []) {
    self.name = name
    self.options = options
  }
}

public protocol SymbolEffect: Hashable, Sendable {
  var configuration: SymbolEffectConfiguration { get }
}

public protocol IndefiniteSymbolEffect: SymbolEffect {}
public protocol DiscreteSymbolEffect: SymbolEffect {}
public protocol TransitionSymbolEffect: SymbolEffect {}
public protocol ContentTransitionSymbolEffect: SymbolEffect {}

public struct SymbolEffectOptions: Hashable, Sendable {
  public var speed: Double?
  public var repeatCount: Int?
  public var repeats: Bool
  public init() {
    speed = nil
    repeatCount = nil
    repeats = false
  }
  public static var `default`: SymbolEffectOptions { return SymbolEffectOptions() }
  public static var `repeating`: SymbolEffectOptions {
    var o = SymbolEffectOptions()
    o.repeats = true
    return o
  }
  public static var nonRepeating: SymbolEffectOptions { return SymbolEffectOptions() }
  public static func speed(_ speed: Double) -> SymbolEffectOptions { return SymbolEffectOptions().speed(speed) }
  public static func `repeat`(_ count: Int) -> SymbolEffectOptions { return SymbolEffectOptions().repeat(count) }
  public func speed(_ speed: Double) -> SymbolEffectOptions {
    var o = self
    o.speed = speed
    return o
  }
  public func `repeat`(_ count: Int) -> SymbolEffectOptions {
    var o = self
    o.repeatCount = count
    o.repeats = true
    return o
  }
}

public struct VariableColorSymbolEffect: IndefiniteSymbolEffect, DiscreteSymbolEffect {
  internal var _options: [String]
  public init() { _options = [] }
  internal init(_ options: [String]) { _options = options }
  public var configuration: SymbolEffectConfiguration {
    return SymbolEffectConfiguration(name: "variableColor", options: _options)
  }
  public var iterative: VariableColorSymbolEffect { return VariableColorSymbolEffect(_options + ["iterative"]) }
  public var cumulative: VariableColorSymbolEffect { return VariableColorSymbolEffect(_options + ["cumulative"]) }
  public var reversing: VariableColorSymbolEffect { return VariableColorSymbolEffect(_options + ["reversing"]) }
  public var nonReversing: VariableColorSymbolEffect { return VariableColorSymbolEffect(_options + ["nonReversing"]) }
  public var hideInactiveLayers: VariableColorSymbolEffect { return VariableColorSymbolEffect(_options + ["hideInactiveLayers"]) }
  public var dimInactiveLayers: VariableColorSymbolEffect { return VariableColorSymbolEffect(_options + ["dimInactiveLayers"]) }
}

public struct ReplaceSymbolEffect: ContentTransitionSymbolEffect {
  internal var _options: [String]
  public init() { _options = [] }
  internal init(_ options: [String]) { _options = options }
  public var configuration: SymbolEffectConfiguration {
    return SymbolEffectConfiguration(name: "replace", options: _options)
  }
  public var downUp: ReplaceSymbolEffect { return ReplaceSymbolEffect(_options + ["downUp"]) }
  public var upUp: ReplaceSymbolEffect { return ReplaceSymbolEffect(_options + ["upUp"]) }
  public var offUp: ReplaceSymbolEffect { return ReplaceSymbolEffect(_options + ["offUp"]) }
  public var byLayer: ReplaceSymbolEffect { return ReplaceSymbolEffect(_options + ["byLayer"]) }
  public var wholeSymbol: ReplaceSymbolEffect { return ReplaceSymbolEffect(_options + ["wholeSymbol"]) }
}

public struct PulseSymbolEffect: IndefiniteSymbolEffect, DiscreteSymbolEffect {
  public init() {}
  public var configuration: SymbolEffectConfiguration { return SymbolEffectConfiguration(name: "pulse") }
}

public struct BounceSymbolEffect: DiscreteSymbolEffect {
  public init() {}
  public var configuration: SymbolEffectConfiguration { return SymbolEffectConfiguration(name: "bounce") }
}

public struct ScaleSymbolEffect: IndefiniteSymbolEffect {
  public init() {}
  public var configuration: SymbolEffectConfiguration { return SymbolEffectConfiguration(name: "scale") }
}

extension SymbolEffect where Self == VariableColorSymbolEffect {
  public static var variableColor: VariableColorSymbolEffect { return VariableColorSymbolEffect() }
}
extension SymbolEffect where Self == ReplaceSymbolEffect {
  public static var replace: ReplaceSymbolEffect { return ReplaceSymbolEffect() }
}
extension SymbolEffect where Self == PulseSymbolEffect {
  public static var pulse: PulseSymbolEffect { return PulseSymbolEffect() }
}
extension SymbolEffect where Self == BounceSymbolEffect {
  public static var bounce: BounceSymbolEffect { return BounceSymbolEffect() }
}
extension SymbolEffect where Self == ScaleSymbolEffect {
  public static var scale: ScaleSymbolEffect { return ScaleSymbolEffect() }
}
