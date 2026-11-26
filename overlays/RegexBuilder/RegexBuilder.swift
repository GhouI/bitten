// RegexBuilder: regexes written as Swift values. Components build the same
// trees as regex literals (see _StringProcessing), through _RegexFactory.
@_exported import _StringProcessing

public func makeFactory() -> _RegexFactory { return _RegexFactory() }

@resultBuilder
public enum RegexComponentBuilder {
  public static func buildExpression<R: RegexComponent>(_ r: R) -> R { return r }
  public static func buildPartialBlock<R: RegexComponent>(first: R) -> Regex<R.RegexOutput> { return first.regex }
  public static func buildPartialBlock<R0: RegexComponent, R1: RegexComponent>(accumulated: R0, next: R1)
    -> Regex<Substring> where R0.RegexOutput == Substring, R1.RegexOutput == Substring
  {
    return makeFactory().accumulate(accumulated, next)
  }
  public static func buildPartialBlock<W, R0: RegexComponent, R1: RegexComponent>(accumulated: R0, next: R1)
    -> Regex<(Substring, W)> where R0.RegexOutput == (Substring, W), R1.RegexOutput == Substring
  {
    return makeFactory().accumulate(accumulated, next)
  }
  public static func buildPartialBlock<W, R0: RegexComponent, R1: RegexComponent>(accumulated: R0, next: R1)
    -> Regex<(Substring, W)> where R0.RegexOutput == Substring, R1.RegexOutput == (Substring, W)
  {
    return makeFactory().accumulate(accumulated, next)
  }
  public static func buildPartialBlock<W0, W1, R0: RegexComponent, R1: RegexComponent>(accumulated: R0, next: R1)
    -> Regex<(Substring, W0, W1)> where R0.RegexOutput == (Substring, W0), R1.RegexOutput == (Substring, W1)
  {
    return makeFactory().accumulate(accumulated, next)
  }
  public static func buildBlock() -> Regex<Substring> { return "".regex }
}

extension Regex {
  public init<R: RegexComponent>(@RegexComponentBuilder _ content: () -> R) where R.RegexOutput == Output {
    self = content().regex
  }
}

public struct Capture<Output>: RegexComponent {
  public let regex: Regex<Output>
  public init(_ regex: Regex<Output>) { self.regex = regex }
  public init<R: RegexComponent, W>(_ component: R) where Output == (Substring, W), R.RegexOutput == W {
    self.init(makeFactory().capture(component))
  }
  public init<R: RegexComponent, W>(@RegexComponentBuilder _ component: () -> R)
    where Output == (Substring, W), R.RegexOutput == W
  {
    self.init(makeFactory().capture(component()))
  }
}

public struct One<Output>: RegexComponent {
  public let regex: Regex<Output>
  public init<R: RegexComponent>(_ component: R) where R.RegexOutput == Output { regex = component.regex }
}

public struct OneOrMore<Output>: RegexComponent {
  public let regex: Regex<Output>
  public init<R: RegexComponent>(_ component: R) where Output == Substring { regex = makeFactory().oneOrMore(component) }
  public init<R: RegexComponent>(@RegexComponentBuilder _ component: () -> R) where Output == Substring {
    regex = makeFactory().oneOrMore(component())
  }
}

public struct ZeroOrMore<Output>: RegexComponent {
  public let regex: Regex<Output>
  public init<R: RegexComponent>(_ component: R) where Output == Substring { regex = makeFactory().zeroOrMore(component) }
  public init<R: RegexComponent>(@RegexComponentBuilder _ component: () -> R) where Output == Substring {
    regex = makeFactory().zeroOrMore(component())
  }
}

public struct Optionally<Output>: RegexComponent {
  public let regex: Regex<Output>
  public init<R: RegexComponent>(_ component: R) where Output == Substring { regex = makeFactory().optionally(component) }
  public init<R: RegexComponent>(@RegexComponentBuilder _ component: () -> R) where Output == Substring {
    regex = makeFactory().optionally(component())
  }
}

public struct Repeat<Output>: RegexComponent {
  public let regex: Regex<Output>
  public init<R: RegexComponent>(_ component: R, count: Int) where Output == Substring {
    regex = makeFactory().repeating(component, min: count, max: count)
  }
  public init<R: RegexComponent>(_ component: R, _ range: ClosedRange<Int>) where Output == Substring {
    regex = makeFactory().repeating(component, min: range.lowerBound, max: range.upperBound)
  }
}

extension StringProtocol where SubSequence == Substring {
  /// Split at each occurrence of a string.
  public func split(separator: String, maxSplits: Int = .max, omittingEmptySubsequences: Bool = true) -> [Substring] {
    let whole = self[...]
    guard !separator.isEmpty else { return [whole] }
    var out: [Substring] = []
    var start = whole.startIndex
    var i = whole.startIndex
    let sep = Array(separator)
    while i < whole.endIndex, out.count < maxSplits {
      var j = i, k = 0
      while k < sep.count, j < whole.endIndex, whole[j] == sep[k] {
        j = whole.index(after: j)
        k += 1
      }
      if k == sep.count {
        let piece = whole[start..<i]
        if !(omittingEmptySubsequences && piece.isEmpty) { out.append(piece) }
        start = j
        i = j
      } else {
        i = whole.index(after: i)
      }
    }
    let last = whole[start..<whole.endIndex]
    if !(omittingEmptySubsequences && last.isEmpty) { out.append(last) }
    return out
  }
}
