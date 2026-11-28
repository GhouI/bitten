// Swift's Regex: regex literals and Regex(_:) parsed into a tree and run by
// a backtracking matcher over Characters (grapheme clusters, as Swift's
// default semantics). The syntax: literals and escapes, ., character
// classes with ranges and negation, \d \w \s \h \v \b \B (and capitals),
// anchors ^ $ \A \z \Z, groups (capturing, (?:), named (?<n>)), (?i) and
// (?-i), alternation, greedy, lazy (?) and possessive (+) quantifiers *,
// +, ?, {n}, {n,}, {n,m}.
//
// A regex's Output is decided by the compiler (Substring, or a tuple of the
// whole match and each capture, a capture under ?, * or | being optional).
// Matches build it from the tuple type's own elements: Substrings, values
// captured components make (a number format style's Double), or optionals
// of either, each at the offset the type gives it.

// ---- the tree --------------------------------------------------------------

internal indirect enum _RNode {
  case empty
  case char(Character)
  case any                                   // .
  case set(_RSet)
  case sequence([_RNode])
  case alternation([_RNode])
  case group(_RNode, capture: Int?)          // capture index from 1
  case quantified(_RNode, min: Int, max: Int?, mode: _RQuant)
  case start, end, textStart, textEnd, textEndNewline
  case wordBoundary(negated: Bool)
  case caseInsensitive(_RNode, Bool)
}

internal enum _RQuant { case greedy, lazy, possessive }

internal struct _RSet {
  var negated = false
  var chars: [Character] = []
  var ranges: [(Character, Character)] = []
  var classes: [_RClass] = []

  func matches(_ c: Character, ignoreCase: Bool) -> Bool {
    func plain(_ c: Character) -> Bool {
      if chars.contains(c) { return true }
      for (lo, hi) in ranges where lo <= c && c <= hi { return true }
      for k in classes where k.matches(c) { return true }
      return false
    }
    var hit = plain(c)
    if !hit && ignoreCase {
      let lower = Character(c.lowercased()), upper = Character(c.uppercased())
      hit = plain(lower) || plain(upper)
    }
    return hit != negated
  }
}

internal enum _RClass {
  case digit, word, space, horizontalSpace, verticalSpace, newline
  case notDigit, notWord, notSpace, notHorizontalSpace, notVerticalSpace
  case any

  func matches(_ c: Character) -> Bool {
    switch self {
    case .digit: return c.isNumber
    case .word: return c.isLetter || c.isNumber || c == "_" || c.isConnectorPunctuation
    case .space: return c.isWhitespace
    case .horizontalSpace: return c.isWhitespace && !c.isNewline
    case .verticalSpace, .newline: return c.isNewline
    case .notDigit: return !c.isNumber
    case .notWord: return !_RClass.word.matches(c)
    case .notSpace: return !c.isWhitespace
    case .notHorizontalSpace: return !_RClass.horizontalSpace.matches(c)
    case .notVerticalSpace: return !c.isNewline
    case .any: return true
    }
  }
}

extension Character {
  internal var isConnectorPunctuation: Bool {
    return unicodeScalars.first.map { $0.properties.generalCategory == .connectorPunctuation } ?? false
  }
  internal var isNewline: Bool {
    switch self {
    case "\n", "\r", "\r\n", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}": return true
    default: return false
    }
  }
}

// ---- parsing -----------------------------------------------------------------

public struct _RegexParseError: Error, CustomStringConvertible {
  public let description: String
}

internal struct _RParser {
  var chars: [Character]
  var i = 0
  var captureCount = 0
  var names: [String: Int] = [:]

  init(_ pattern: String) { chars = Array(pattern) }

  var atEnd: Bool { return i >= chars.count }
  func peek(_ k: Int = 0) -> Character? { return i + k < chars.count ? chars[i + k] : nil }
  mutating func next() -> Character { defer { i += 1 }; return chars[i] }
  mutating func eat(_ c: Character) -> Bool {
    if peek() == c { i += 1; return true }
    return false
  }

  mutating func parse() throws -> _RNode {
    let n = try alternation()
    if !atEnd { throw _RegexParseError(description: "unbalanced ')' at \(i)") }
    return n
  }

  mutating func alternation() throws -> _RNode {
    var branches = [try sequence()]
    while eat("|") { branches.append(try sequence()) }
    return branches.count == 1 ? branches[0] : .alternation(branches)
  }

  mutating func sequence() throws -> _RNode {
    var items: [_RNode] = []
    while let c = peek(), c != "|", c != ")" {
      // (?i) and (?-i) apply to the rest of the sequence.
      if c == "(", peek(1) == "?", let flag = peek(2), flag == "i" || flag == "-", peek(flag == "-" ? 4 : 3) == ")" {
        let on = flag == "i"
        i += on ? 4 : 5
        let rest = try sequence()
        items.append(.caseInsensitive(rest, on))
        break
      }
      var atom = try self.atom()
      atom = try quantifier(atom)
      items.append(atom)
    }
    return items.count == 1 ? items[0] : .sequence(items)
  }

  mutating func quantifier(_ atom: _RNode) throws -> _RNode {
    var min = 0, max: Int? = nil
    guard let c = peek() else { return atom }
    switch c {
    case "*": i += 1
    case "+": i += 1; min = 1
    case "?": i += 1; max = 1
    case "{":
      let save = i
      i += 1
      var lo = "", hi = ""
      while let d = peek(), d.isWholeNumber { lo.append(next()) }
      var sawComma = false
      if eat(",") {
        sawComma = true
        while let d = peek(), d.isWholeNumber { hi.append(next()) }
      }
      guard eat("}"), let l = Int(lo) else { i = save; return atom }
      min = l
      max = sawComma ? Int(hi) : l
    default: return atom
    }
    var mode = _RQuant.greedy
    if eat("?") { mode = .lazy } else if eat("+") { mode = .possessive }
    return .quantified(atom, min: min, max: max, mode: mode)
  }

  mutating func atom() throws -> _RNode {
    let c = next()
    switch c {
    case ".": return .any
    case "^": return .start
    case "$": return .end
    case "[": return .set(try set())
    case "(":
      if eat("?") {
        if eat(":") {
          let inner = try alternation()
          guard eat(")") else { throw _RegexParseError(description: "missing ')'") }
          return .group(inner, capture: nil)
        }
        if peek() == "<" || peek() == "P" || peek() == "'" {
          if peek() == "P" { i += 1 }
          let close: Character = next() == "'" ? "'" : ">"
          var name = ""
          while let d = peek(), d != close { name.append(next()) }
          guard eat(close) else { throw _RegexParseError(description: "bad group name") }
          captureCount += 1
          let index = captureCount
          names[name] = index
          let inner = try alternation()
          guard eat(")") else { throw _RegexParseError(description: "missing ')'") }
          return .group(inner, capture: index)
        }
        throw _RegexParseError(description: "unsupported group at \(i)")
      }
      captureCount += 1
      let index = captureCount
      let inner = try alternation()
      guard eat(")") else { throw _RegexParseError(description: "missing ')'") }
      return .group(inner, capture: index)
    case "\\": return try escape(inSet: false).node
    default: return .char(c)
    }
  }

  /// An escape: a node, or (in a set) a character or class.
  mutating func escape(inSet: Bool) throws -> (node: _RNode, char: Character?, cls: _RClass?) {
    guard !atEnd else { throw _RegexParseError(description: "trailing backslash") }
    let c = next()
    func cls(_ k: _RClass) -> (_RNode, Character?, _RClass?) {
      var s = _RSet()
      s.classes = [k]
      return (.set(s), nil, k)
    }
    func lit(_ ch: Character) -> (_RNode, Character?, _RClass?) { return (.char(ch), ch, nil) }
    switch c {
    case "d": return cls(.digit)
    case "D": return cls(.notDigit)
    case "w": return cls(.word)
    case "W": return cls(.notWord)
    case "s": return cls(.space)
    case "S": return cls(.notSpace)
    case "h": return cls(.horizontalSpace)
    case "H": return cls(.notHorizontalSpace)
    case "v": return cls(.verticalSpace)
    case "V": return cls(.notVerticalSpace)
    case "R": return cls(.newline)
    case "N": return cls(.notVerticalSpace)
    case "n": return lit("\n")
    case "t": return lit("\t")
    case "r": return lit("\r")
    case "f": return lit("\u{0C}")
    case "e": return lit("\u{1B}")
    case "0": return lit("\0")
    case "b": return inSet ? lit("\u{08}") : (.wordBoundary(negated: false), nil, nil)
    case "B": return (.wordBoundary(negated: true), nil, nil)
    case "A": return (.textStart, nil, nil)
    case "z": return (.textEnd, nil, nil)
    case "Z": return (.textEndNewline, nil, nil)
    case "u", "x":
      var hex = ""
      if eat("{") {
        while let d = peek(), d != "}" { hex.append(next()) }
        _ = eat("}")
      } else {
        for _ in 0..<(c == "u" ? 4 : 2) where peek()?.isHexDigit == true { hex.append(next()) }
      }
      guard let v = UInt32(hex, radix: 16), let s = Unicode.Scalar(v) else {
        throw _RegexParseError(description: "bad \\\(c) escape")
      }
      return lit(Character(s))
    default: return lit(c)
    }
  }

  mutating func set() throws -> _RSet {
    var s = _RSet()
    if eat("^") { s.negated = true }
    var first = true
    while let c = peek(), c != "]" || first {
      first = false
      var lo: Character
      if c == "\\" {
        i += 1
        let e = try escape(inSet: true)
        if let k = e.cls { s.classes.append(k); continue }
        lo = e.char ?? "\\"
      } else if c == "[", peek(1) == ":" {
        // POSIX classes: [:alpha:] and friends.
        i += 2
        var name = ""
        while let d = peek(), d != ":" { name.append(next()) }
        i += 2
        switch name {
        case "digit": s.classes.append(.digit)
        case "space": s.classes.append(.space)
        case "word", "alnum": s.classes.append(.word)
        case "alpha": s.ranges += [("a", "z"), ("A", "Z")]
        case "upper": s.ranges.append(("A", "Z"))
        case "lower": s.ranges.append(("a", "z"))
        default: break
        }
        continue
      } else {
        lo = next()
      }
      if peek() == "-", let hiChar = peek(1), hiChar != "]" {
        i += 1
        var hi = next()
        if hi == "\\" { hi = try escape(inSet: true).char ?? hi }
        s.ranges.append((lo, hi))
      } else {
        s.chars.append(lo)
      }
    }
    guard eat("]") else { throw _RegexParseError(description: "missing ']'") }
    return s
  }
}

// ---- matching --------------------------------------------------------------------

internal final class _RMatcher {
  let input: [Character]
  var caps: [Range<Int>?]
  var steps = 0

  init(_ input: [Character], captures: Int) {
    self.input = input
    self.caps = Array(repeating: nil, count: captures + 1)
  }

  func isWord(_ i: Int) -> Bool { return i >= 0 && i < input.count && _RClass.word.matches(input[i]) }

  /// Match `n` at `i`, then the continuation `k`.
  func m(_ n: _RNode, _ i: Int, _ ic: Bool, _ k: (Int) -> Bool) -> Bool {
    steps += 1
    switch n {
    case .empty: return k(i)
    case let .char(c):
      guard i < input.count else { return false }
      let hit = ic ? input[i].lowercased() == c.lowercased() : input[i] == c
      return hit && k(i + 1)
    case .any:
      return i < input.count && !input[i].isNewline && k(i + 1)
    case let .set(s):
      return i < input.count && s.matches(input[i], ignoreCase: ic) && k(i + 1)
    case let .sequence(items):
      return seq(items, 0, i, ic, k)
    case let .alternation(branches):
      for b in branches {
        let saved = caps
        if m(b, i, ic, k) { return true }
        caps = saved
      }
      return false
    case let .group(inner, capture):
      guard let index = capture else { return m(inner, i, ic, k) }
      let old = caps[index]
      if m(inner, i, ic, { j in
        let prev = self.caps[index]
        self.caps[index] = i..<j
        if k(j) { return true }
        self.caps[index] = prev
        return false
      }) { return true }
      caps[index] = old
      return false
    case let .quantified(inner, min, max, mode):
      if mode == .possessive {
        var pos = i, count = 0
        while max.map({ count < $0 }) ?? true {
          var end = -1
          if !m(inner, pos, ic, { j in end = j; return true }) || end == pos { break }
          pos = end
          count += 1
        }
        return count >= min && k(pos)
      }
      return rep(inner, min, max, mode == .lazy, 0, i, ic, k)
    case .start: return (i == 0 || input[i - 1].isNewline) && k(i)
    case .end: return (i == input.count || input[i].isNewline) && k(i)
    case .textStart: return i == 0 && k(i)
    case .textEnd: return i == input.count && k(i)
    case .textEndNewline: return (i == input.count || (i == input.count - 1 && input[i].isNewline)) && k(i)
    case let .wordBoundary(negated):
      return ((isWord(i - 1) != isWord(i)) != negated) && k(i)
    case let .caseInsensitive(inner, on): return m(inner, i, on, k)
    }
  }

  func seq(_ items: [_RNode], _ idx: Int, _ i: Int, _ ic: Bool, _ k: (Int) -> Bool) -> Bool {
    if idx == items.count { return k(i) }
    // A case-insensitivity switch covers the rest of the sequence.
    return m(items[idx], i, ic) { j in self.seq(items, idx + 1, j, ic, k) }
  }

  func rep(_ n: _RNode, _ min: Int, _ max: Int?, _ lazy: Bool, _ count: Int, _ i: Int, _ ic: Bool,
           _ k: (Int) -> Bool) -> Bool {
    let canMore = max.map { count < $0 } ?? true
    func more() -> Bool {
      guard canMore else { return false }
      return m(n, i, ic) { j in
        j == i && count >= min ? false : self.rep(n, min, max, lazy, count + 1, j, ic, k)
      }
    }
    if count < min { return more() }
    if lazy { return k(i) || more() }
    return more() || k(i)
  }

  /// The end of a match of `n` starting at `i`, with the captures set.
  func match(_ n: _RNode, at i: Int, whole: Bool) -> Int? {
    for c in caps.indices { caps[c] = nil }
    var end: Int? = nil
    _ = m(n, i, false) { j in
      if whole && j != self.input.count { return false }
      end = j
      return true
    }
    return end
  }
}

// ---- the public API ----------------------------------------------------------------

public protocol RegexComponent<RegexOutput> {
  associatedtype RegexOutput
  var regex: Regex<RegexOutput> { get }
}

/// The parsed pattern every Regex shares, whatever its Output type.
internal final class _RProgram: @unchecked Sendable {
  let root: _RNode
  let captures: Int
  /// For regexes whose Output is a value made from the match (a parsed
  /// number...): nil rejects the match.
  let transform: ((Substring) -> Any?)?
  /// Captures whose value is made from their text (a capture of a regex
  /// component with an Output of its own, such as a parsed number), by
  /// capture number.
  let captureTransforms: [Int: (Substring) -> Any?]
  init(_ root: _RNode, captures: Int, transform: ((Substring) -> Any?)? = nil,
       captureTransforms: [Int: (Substring) -> Any?] = [:]) {
    self.root = root
    self.captures = captures
    self.transform = transform
    self.captureTransforms = captureTransforms
  }
  /// The capture transforms with their numbers moved up by `by`.
  func transforms(movedBy by: Int) -> [Int: (Substring) -> Any?] {
    var out: [Int: (Substring) -> Any?] = [:]
    for (k, v) in captureTransforms { out[k + by] = v }
    return out
  }
}
internal func _merged(_ a: [Int: (Substring) -> Any?], _ b: [Int: (Substring) -> Any?]) -> [Int: (Substring) -> Any?] {
  return a.merging(b) { x, _ in x }
}

public struct Regex<Output>: RegexComponent, @unchecked Sendable {
  internal let _program: _RProgram

  internal init(_program: _RProgram) { self._program = _program }

  /// What regex literals compile to: the literal's source text, its
  /// delimiters (/.../, #/.../#, ##/.../##) included.
  public init(_regexString literal: String, version: Int) {
    let pattern = Self._stripDelimiters(literal)
    do {
      var p = _RParser(pattern)
      let root = try p.parse()
      _program = _RProgram(root, captures: p.captureCount)
    } catch {
      fatalError("Regex: \(error) in /\(pattern)/")
    }
  }
  public init(_regexString pattern: String) { self.init(_regexString: pattern, version: 1) }

  /// A regex whose match becomes a value (Foundation's format styles as
  /// regex components): the pattern finds the text, `transform` makes the
  /// Output or rejects the match.
  public init(_bittenPattern pattern: String, transform: @escaping (Substring) -> Output?) {
    var p = _RParser(pattern)
    let root = (try? p.parse()) ?? .empty
    _program = _RProgram(root, captures: p.captureCount, transform: { transform($0) })
  }

  internal static func _stripDelimiters(_ literal: String) -> String {
    var s = Substring(literal)
    var hashes = 0
    while s.first == "#" { s.removeFirst(); hashes += 1 }
    guard s.first == "/" else { return literal }
    s.removeFirst()
    var trailing = 0
    while trailing < hashes, s.last == "#" { s.removeLast(); trailing += 1 }
    guard trailing == hashes, s.last == "/" else { return literal }
    s.removeLast()
    return String(s)
  }

  internal init(_parsing pattern: String) throws {
    var p = _RParser(pattern)
    let root = try p.parse()
    _program = _RProgram(root, captures: p.captureCount)
  }
  /// A pattern known at run time, with the Output the caller expects.
  public init(_ pattern: String, as: Output.Type) throws { try self.init(_parsing: pattern) }

  public var regex: Regex<Output> { return self }

  @dynamicMemberLookup
  public struct Match {
    public let range: Range<String.Index>
    public let output: Output
    internal let _input: Substring
    internal let _captures: [Range<String.Index>?]

    public subscript<T>(dynamicMember keyPath: KeyPath<Output, T>) -> T { return output[keyPath: keyPath] }
  }

  public func wholeMatch(in s: Substring) throws -> Match? { return _search(s, whole: true, from: 0, anywhere: false) }
  public func wholeMatch(in s: String) throws -> Match? { return try wholeMatch(in: s[...]) }
  public func firstMatch(in s: Substring) throws -> Match? { return _search(s, whole: false, from: 0, anywhere: true) }
  public func firstMatch(in s: String) throws -> Match? { return try firstMatch(in: s[...]) }
  public func prefixMatch(in s: Substring) throws -> Match? { return _search(s, whole: false, from: 0, anywhere: false) }
  public func prefixMatch(in s: String) throws -> Match? { return try prefixMatch(in: s[...]) }

  public func ignoresCase(_ on: Bool = true) -> Regex<Output> {
    return Regex(_program: _RProgram(.caseInsensitive(_program.root, on), captures: _program.captures,
                                     transform: _program.transform, captureTransforms: _program.captureTransforms))
  }

  internal func _search(_ s: Substring, whole: Bool, from: Int, anywhere: Bool) -> Match? {
    let chars = Array(s)
    var indices: [String.Index] = []
    indices.reserveCapacity(chars.count + 1)
    var idx = s.startIndex
    for _ in chars {
      indices.append(idx)
      idx = s.index(after: idx)
    }
    indices.append(s.endIndex)
    let matcher = _RMatcher(chars, captures: _program.captures)
    var start = from
    while start <= chars.count {
      if let end = matcher.match(_program.root, at: start, whole: whole) {
        let caps = matcher.caps.dropFirst().map { r in r.map { indices[$0.lowerBound]..<indices[$0.upperBound] } }
        let range = indices[start]..<indices[end]
        if let transform = _program.transform {
          if let value = transform(s[range]) as? Output {
            return Match(range: range, output: value, _input: s, _captures: caps)
          }
        } else {
          // Captures that make a value: a capture whose transform finds no
          // value (text a number style can't parse) fails the match.
          var values: [Int: Any] = [:]
          var ok = true
          for (n, t) in _program.captureTransforms where n - 1 < caps.count {
            guard let r = caps[n - 1] else { continue }
            if let v = t(s[r]) { values[n] = v } else { ok = false; break }
          }
          if ok {
            return Match(range: range, output: Self._output(s, range, caps, values), _input: s, _captures: caps)
          }
        }
      }
      if !anywhere { break }
      start += 1
    }
    return nil
  }

  internal func _all(_ s: Substring) -> [Match] {
    var out: [Match] = []
    var from = 0
    let count = s.count
    while from <= count, let m = _search(s, whole: false, from: from, anywhere: true) {
      out.append(m)
      let lower = s.distance(from: s.startIndex, to: m.range.lowerBound)
      let upper = s.distance(from: s.startIndex, to: m.range.upperBound)
      from = upper > lower ? upper : upper + 1
    }
    return out
  }

  /// The Output value: Substring, or a tuple of the match and its captures
  /// (each written as its element's type: a Substring, a value a capture
  /// made, or an optional of either).
  internal static func _output(_ s: Substring, _ range: Range<String.Index>, _ caps: [Range<String.Index>?],
                               _ values: [Int: Any] = [:]) -> Output {
    if Output.self == Substring.self { return unsafeBitCast(s[range], to: Output.self) }
    if Output.self == AnyRegexOutput.self {
      let any = AnyRegexOutput(_elements: [s[range]] + caps.map { r in r.map { s[$0] } })
      return unsafeBitCast(any, to: Output.self)
    }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Swift.max(MemoryLayout<Output>.size, 1),
                                               alignment: MemoryLayout<Output>.alignment)
    defer { raw.deallocate() }
    let count = _rx_fieldCount(raw, Output.self)
    for n in 0..<count {
      var name: UnsafePointer<CChar>? = nil
      var type: Any.Type? = nil
      guard let at = _rx_field(raw, Output.self, n, &name, &type), let elementType = type else { continue }
      let value: Any? = n == 0 ? s[range]
        : (values[n] ?? (n - 1 < caps.count ? caps[n - 1].map { s[$0] as Any } : nil))
      _rx_write(elementType, value, UnsafeMutableRawPointer(mutating: at), s[s.startIndex..<s.startIndex])
    }
    return raw.assumingMemoryBound(to: Output.self).move()
  }

}

/// The Output of a regex made at run time: the match and each capture.
public struct AnyRegexOutput: RandomAccessCollection, @unchecked Sendable {
  public struct Element {
    public let substring: Substring?
    public var range: Range<String.Index>? { return substring.map { $0.startIndex..<$0.endIndex } }
  }
  internal let _elements: [Substring?]
  internal init(_elements: [Substring?]) { self._elements = _elements }
  public var startIndex: Int { return 0 }
  public var endIndex: Int { return _elements.count }
  public subscript(index: Int) -> Element { return Element(substring: _elements[index]) }
}

extension Regex where Output == AnyRegexOutput {
  public init(_ pattern: String) throws { try self.init(_parsing: pattern) }
}

extension Substring {
  internal func trimmingSpaces() -> String {
    var s = self[...]
    while s.first == " " { s.removeFirst() }
    while s.last == " " { s.removeLast() }
    return String(s)
  }
}

extension Regex.Match: @unchecked Sendable {}

// Strings and characters are regexes that match themselves.
extension String: RegexComponent {
  public var regex: Regex<Substring> { return Regex(_program: _RProgram(_literal(self), captures: 0)) }
}
extension Substring: RegexComponent {
  public var regex: Regex<Substring> { return Regex(_program: _RProgram(_literal(String(self)), captures: 0)) }
}
extension Character: RegexComponent {
  public var regex: Regex<Substring> { return Regex(_program: _RProgram(.char(self), captures: 0)) }
}
internal func _literal(_ s: String) -> _RNode {
  let items = s.map { _RNode.char($0) }
  return items.count == 1 ? items[0] : .sequence(items)
}

/// Character classes for RegexBuilder (One(.digit), .whitespace...).
public struct CharacterClass: RegexComponent, Sendable {
  internal let _set: _RSet
  internal init(_ set: _RSet) { _set = set }
  internal init(_ k: _RClass) {
    var s = _RSet()
    s.classes = [k]
    _set = s
  }
  public var regex: Regex<Substring> { return Regex(_program: _RProgram(.set(_set), captures: 0)) }
  public var inverted: CharacterClass {
    var s = _set
    s.negated.toggle()
    return CharacterClass(s)
  }
  public static var any: CharacterClass { return CharacterClass(.any) }
  public static var anyNonNewline: CharacterClass { return CharacterClass(.notVerticalSpace) }
  public static var digit: CharacterClass { return CharacterClass(.digit) }
  public static var word: CharacterClass { return CharacterClass(.word) }
  public static var whitespace: CharacterClass { return CharacterClass(.space) }
  public static var horizontalWhitespace: CharacterClass { return CharacterClass(.horizontalSpace) }
  public static var verticalWhitespace: CharacterClass { return CharacterClass(.verticalSpace) }
  public static var newlineSequence: CharacterClass { return CharacterClass(.newline) }
  public static func anyOf<S: Sequence>(_ s: S) -> CharacterClass where S.Element == Character {
    var set = _RSet()
    set.chars = Array(s)
    return CharacterClass(set)
  }
  public static func noneOf<S: Sequence>(_ s: S) -> CharacterClass where S.Element == Character {
    return anyOf(s).inverted
  }
}
extension RegexComponent where Self == CharacterClass {
  public static var any: CharacterClass { return .init(.any) }
  public static var digit: CharacterClass { return .init(.digit) }
  public static var word: CharacterClass { return .init(.word) }
  public static var whitespace: CharacterClass { return .init(.space) }
  public static var horizontalWhitespace: CharacterClass { return .init(.horizontalSpace) }
  public static var verticalWhitespace: CharacterClass { return .init(.verticalSpace) }
  public static func anyOf<S: Sequence>(_ s: S) -> CharacterClass where S.Element == Character {
    return CharacterClass.anyOf(s)
  }
}

// ---- RegexBuilder's hooks -----------------------------------------------------------

/// What RegexBuilder's inlined code asks to combine components.
public struct _RegexFactory {
  public init() {}
  public func capture<W, R: RegexComponent>(_ r: R) -> Regex<W> {
    let p = r.regex._program
    // The new group is number 1; the component's own groups follow it. A
    // component that makes its own value (a number format style) makes the
    // capture's value.
    var transforms = p.transforms(movedBy: 1)
    if let t = p.transform { transforms[1] = t }
    return Regex(_program: _RProgram(.group(_renumber(p.root, by: 1), capture: 1), captures: p.captures + 1,
                                     captureTransforms: transforms))
  }
  public func accumulate<W, R0: RegexComponent, R1: RegexComponent>(_ a: R0, _ b: R1) -> Regex<W> {
    let pa = a.regex._program, pb = b.regex._program
    return Regex(_program: _RProgram(.sequence([pa.root, _renumber(pb.root, by: pa.captures)]),
                                     captures: pa.captures + pb.captures,
                                     captureTransforms: _merged(pa.captureTransforms, pb.transforms(movedBy: pa.captures))))
  }
  public func oneOrMore<W, R: RegexComponent>(_ r: R, _ lazy: Bool = false) -> Regex<W> {
    let p = r.regex._program
    return Regex(_program: _RProgram(.quantified(p.root, min: 1, max: nil, mode: lazy ? .lazy : .greedy), captures: p.captures, captureTransforms: p.captureTransforms))
  }
  public func zeroOrMore<W, R: RegexComponent>(_ r: R, _ lazy: Bool = false) -> Regex<W> {
    let p = r.regex._program
    return Regex(_program: _RProgram(.quantified(p.root, min: 0, max: nil, mode: lazy ? .lazy : .greedy), captures: p.captures, captureTransforms: p.captureTransforms))
  }
  public func optionally<W, R: RegexComponent>(_ r: R) -> Regex<W> {
    let p = r.regex._program
    return Regex(_program: _RProgram(.quantified(p.root, min: 0, max: 1, mode: .greedy), captures: p.captures, captureTransforms: p.captureTransforms))
  }
  public func repeating<W, R: RegexComponent>(_ r: R, min: Int, max: Int?) -> Regex<W> {
    let p = r.regex._program
    return Regex(_program: _RProgram(.quantified(p.root, min: min, max: max, mode: .greedy), captures: p.captures, captureTransforms: p.captureTransforms))
  }
  public func orderedChoice<W, R0: RegexComponent, R1: RegexComponent>(_ a: R0, _ b: R1) -> Regex<W> {
    let pa = a.regex._program, pb = b.regex._program
    return Regex(_program: _RProgram(.alternation([pa.root, _renumber(pb.root, by: pa.captures)]),
                                     captures: pa.captures + pb.captures,
                                     captureTransforms: _merged(pa.captureTransforms, pb.transforms(movedBy: pa.captures))))
  }
}

/// A tree with its capture numbers moved up by `by`.
internal func _renumber(_ n: _RNode, by: Int) -> _RNode {
  if by == 0 { return n }
  switch n {
  case let .sequence(items): return .sequence(items.map { _renumber($0, by: by) })
  case let .alternation(items): return .alternation(items.map { _renumber($0, by: by) })
  case let .group(inner, capture): return .group(_renumber(inner, by: by), capture: capture.map { $0 + by })
  case let .quantified(inner, min, max, mode): return .quantified(_renumber(inner, by: by), min: min, max: max, mode: mode)
  case let .caseInsensitive(inner, on): return .caseInsensitive(_renumber(inner, by: by), on)
  default: return n
  }
}

// ---- collections -----------------------------------------------------------------------

extension BidirectionalCollection where SubSequence == Substring {
  public func contains<R: RegexComponent>(_ regex: R) -> Bool {
    return (try? regex.regex.firstMatch(in: self[...])) != nil
  }
  public func matches<Output, R: RegexComponent>(of regex: R) -> [Regex<Output>.Match] where R.RegexOutput == Output {
    return regex.regex._all(self[...])
  }
  public func firstMatch<Output, R: RegexComponent>(of regex: R) -> Regex<Output>.Match? where R.RegexOutput == Output {
    return try? regex.regex.firstMatch(in: self[...])
  }
  public func wholeMatch<Output, R: RegexComponent>(of regex: R) -> Regex<Output>.Match? where R.RegexOutput == Output {
    return try? regex.regex.wholeMatch(in: self[...])
  }
  public func prefixMatch<Output, R: RegexComponent>(of regex: R) -> Regex<Output>.Match? where R.RegexOutput == Output {
    return try? regex.regex.prefixMatch(in: self[...])
  }
  public func starts<R: RegexComponent>(with regex: R) -> Bool {
    return (try? regex.regex.prefixMatch(in: self[...])) != nil
  }
  public func ranges<R: RegexComponent>(of regex: R) -> [Range<Index>] {
    return regex.regex._all(self[...]).map { $0.range }
  }
  public func firstRange<R: RegexComponent>(of regex: R) -> Range<Index>? {
    return (try? regex.regex.firstMatch(in: self[...]))?.range
  }
  // Disfavoured, as in Swift: `split(separator: "\n")` is the Character
  // split, not a regex search.
  @_disfavoredOverload
  public func split<R: RegexComponent>(separator: R, maxSplits: Int = .max,
                                       omittingEmptySubsequences: Bool = true) -> [SubSequence] {
    // A literal separator is looked for as text, without building a regex.
    if let lit = separator as? String {
      if !lit.isEmpty { return _splitLiteral(lit[...], maxSplits, omittingEmptySubsequences) }
    } else if let lit = separator as? Substring {
      if !lit.isEmpty { return _splitLiteral(lit, maxSplits, omittingEmptySubsequences) }
    } else if let c = separator as? Character {
      return _splitLiteral(String(c)[...], maxSplits, omittingEmptySubsequences)
    }
    var out: [SubSequence] = []
    var start = startIndex
    for m in regex(separator)._all(self[...]) where out.count < maxSplits {
      if m.range.isEmpty { continue }
      let piece = self[start..<m.range.lowerBound]
      if !(omittingEmptySubsequences && piece.isEmpty) { out.append(piece) }
      start = m.range.upperBound
    }
    let last = self[start..<endIndex]
    if !(omittingEmptySubsequences && last.isEmpty) { out.append(last) }
    return out
  }
  internal func regex<R: RegexComponent>(_ r: R) -> Regex<R.RegexOutput> { return r.regex }
  /// Splits at each occurrence of `lit` (by characters, as a regex of the
  /// literal matches), at most `maxSplits` times.
  internal func _splitLiteral(_ lit: Substring, _ maxSplits: Int, _ omitEmpty: Bool) -> [SubSequence] {
    var out: [SubSequence] = []
    var splits = 0
    var start = startIndex, i = startIndex
    let first = lit.first!
    let single = lit.count == 1
    while i < endIndex && splits < maxSplits {
      if self[i] == first {
        var j = index(after: i)
        var matched = true
        if !single {
          var k = lit.index(after: lit.startIndex)
          while k < lit.endIndex {
            if j == endIndex || self[j] != lit[k] { matched = false; break }
            formIndex(after: &j)
            lit.formIndex(after: &k)
          }
        }
        if matched {
          let piece = self[start..<i]
          if !(omitEmpty && piece.isEmpty) { out.append(piece) }
          splits += 1
          start = j
          i = j
          continue
        }
      }
      formIndex(after: &i)
    }
    let last = self[start..<endIndex]
    if !(omitEmpty && last.isEmpty) { out.append(last) }
    return out
  }
}

extension RangeReplaceableCollection where SubSequence == Substring, Self: BidirectionalCollection {
  public func replacing<R: RegexComponent, Replacement: Collection>(_ regex: R, with replacement: Replacement)
    -> Self where Replacement.Element == Element
  {
    var out = Self()
    var start = startIndex
    for m in regex.regex._all(self[...]) {
      out.append(contentsOf: self[start..<m.range.lowerBound])
      out.append(contentsOf: replacement)
      start = m.range.upperBound
    }
    out.append(contentsOf: self[start..<endIndex])
    return out
  }
  public mutating func replace<R: RegexComponent, Replacement: Collection>(_ regex: R, with replacement: Replacement)
    where Replacement.Element == Element
  {
    self = replacing(regex, with: replacement)
  }
}

// ---- writing an output tuple's elements -------------------------------------

@_silgen_name("_bitten_mirror_count")
internal func _rx_fieldCount(_ value: UnsafeRawPointer, _ type: Any.Type) -> Int
@_silgen_name("_bitten_mirror_child")
internal func _rx_field(_ value: UnsafeRawPointer, _ type: Any.Type, _ index: Int,
                        _ name: UnsafeMutablePointer<UnsafePointer<CChar>?>,
                        _ childType: UnsafeMutablePointer<Any.Type?>) -> UnsafeRawPointer?

internal protocol _RxWriter {
  static func write(_ value: Any?, _ at: UnsafeMutableRawPointer, _ empty: Substring)
}
internal enum _RxWrite<E>: _RxWriter {
  static func write(_ value: Any?, _ at: UnsafeMutableRawPointer, _ empty: Substring) {
    // The value as this element's type (a Double into Double? too); no value
    // makes nil for an optional element, else an empty match.
    if let value = value, let v = value as? E {
      at.initializeMemory(as: E.self, repeating: v, count: 1)
    } else if let none = (Optional<Any>.none as Any) as? E {
      at.initializeMemory(as: E.self, repeating: none, count: 1)
    } else if let v = empty as? E {
      at.initializeMemory(as: E.self, repeating: v, count: 1)
    } else {
      fatalError("Regex: no value for an output element of type \(E.self)")
    }
  }
}
/// Writes `value` at `at` as an element of type `type`.
internal func _rx_write(_ type: Any.Type, _ value: Any?, _ at: UnsafeMutableRawPointer, _ empty: Substring) {
  func writer<E>(_: E.Type) -> _RxWriter.Type { return _RxWrite<E>.self }
  let w = _openExistential(type, do: writer)
  w.write(value, at, empty)
}
