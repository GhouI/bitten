// AttributedString: a String and runs of attributes over its characters.
// Attributes are keyed by AttributedStringKey types (their `name`), grouped
// in scopes (AttributeScopes.foundation here; SwiftUI adds its own) and
// reached by dynamic member lookup: `s.foregroundColor = .red`,
// `s.swiftUI.font = ...`, `s[range].link = url`. Adjacent runs with equal
// attributes merge.
// (Taken over from the Foundation side; NSAttributedString bridging is
// theirs.)

// ---- keys and scopes ---------------------------------------------------------

public protocol AttributedStringKey {
  associatedtype Value: Hashable
  static var name: String { get }
}

public protocol AttributeScope {}

/// Where scopes live: `AttributeScopes.foundation`, `.swiftUI`...
@frozen public enum AttributeScopes {}

public struct InlinePresentationIntent: OptionSet, Hashable, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }
  public static let emphasized = InlinePresentationIntent(rawValue: 1 << 0)
  public static let stronglyEmphasized = InlinePresentationIntent(rawValue: 1 << 1)
  public static let code = InlinePresentationIntent(rawValue: 1 << 2)
  public static let strikethrough = InlinePresentationIntent(rawValue: 1 << 5)
  public static let softBreak = InlinePresentationIntent(rawValue: 1 << 6)
  public static let lineBreak = InlinePresentationIntent(rawValue: 1 << 7)
  public static let inlineHTML = InlinePresentationIntent(rawValue: 1 << 8)
  public static let blockHTML = InlinePresentationIntent(rawValue: 1 << 9)
}

extension AttributeScopes {
  public struct FoundationAttributes: AttributeScope {
    public enum LinkAttribute: AttributedStringKey {
      public typealias Value = URL
      public static var name: String { return "NSLink" }
    }
    public enum InlinePresentationIntentAttribute: AttributedStringKey {
      public typealias Value = InlinePresentationIntent
      public static var name: String { return "NSInlinePresentationIntent" }
    }
    public enum LanguageIdentifierAttribute: AttributedStringKey {
      public typealias Value = String
      public static var name: String { return "NSLanguage" }
    }
    public enum AlternateDescriptionAttribute: AttributedStringKey {
      public typealias Value = String
      public static var name: String { return "NSAlternateDescription" }
    }
    public let link: LinkAttribute
    public let inlinePresentationIntent: InlinePresentationIntentAttribute
    public let languageIdentifier: LanguageIdentifierAttribute
    public let alternateDescription: AlternateDescriptionAttribute
  }
  public var foundation: FoundationAttributes.Type { return FoundationAttributes.self }
}

// ---- containers --------------------------------------------------------------

/// Attributes by key name.
internal typealias _Attributes = [String: AnyHashable]

@dynamicMemberLookup
public struct AttributeContainer: Equatable, Hashable, CustomStringConvertible {
  internal var _storage: _Attributes = [:]

  public init() {}

  public subscript<K: AttributedStringKey>(_ key: K.Type) -> K.Value? {
    get { return _storage[K.name]?.base as? K.Value }
    set { _storage[K.name] = newValue.map { AnyHashable($0) } }
  }
  public subscript<K: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.FoundationAttributes, K>) -> K.Value? {
    get { return self[K.self] }
    set { self[K.self] = newValue }
  }
  public subscript<S: AttributeScope>(dynamicMember keyPath: KeyPath<AttributeScopes, S.Type>) -> ScopedAttributeContainer<S> {
    get { return ScopedAttributeContainer(_storage) }
    set { _storage = newValue._storage }
  }

  public mutating func merge(_ other: AttributeContainer) {
    for (k, v) in other._storage { _storage[k] = v }
  }
  public func merging(_ other: AttributeContainer) -> AttributeContainer {
    var c = self
    c.merge(other)
    return c
  }

  public var description: String { return _describe(_storage) }
}

/// The attributes of one scope, by member: `container.swiftUI.font`.
@dynamicMemberLookup
public struct ScopedAttributeContainer<S: AttributeScope> {
  internal var _storage: _Attributes
  internal init(_ storage: _Attributes) { _storage = storage }

  public subscript<K: AttributedStringKey>(dynamicMember keyPath: KeyPath<S, K>) -> K.Value? {
    get { return _storage[K.name]?.base as? K.Value }
    set { _storage[K.name] = newValue.map { AnyHashable($0) } }
  }
}

internal func _describe(_ a: _Attributes) -> String {
  return a.keys.sorted().map { "\t\($0) = \(a[$0]!)" }.joined(separator: "\n")
}

// ---- the string --------------------------------------------------------------

public protocol AttributedStringProtocol: CustomStringConvertible {
  var startIndex: AttributedString.Index { get }
  var endIndex: AttributedString.Index { get }
  /// The underlying string (whole, for substrings too) its indices refer to.
  var _bnBase: String { get }
}

@dynamicMemberLookup
public struct AttributedString: AttributedStringProtocol, Equatable, Hashable, ExpressibleByStringLiteral,
  CustomStringConvertible, @unchecked Sendable
{
  public struct Index: Comparable, Hashable, Sendable {
    internal let _i: String.Index
    internal init(_ i: String.Index) { _i = i }
    public static func < (a: Index, b: Index) -> Bool { return a._i < b._i }

    /// The index of a String index within an attributed string, if it is
    /// one of its character boundaries.
    public init?<S: AttributedStringProtocol>(_ i: String.Index, within s: S) {
      let base = s._bnBase
      guard i >= s.startIndex._i, i <= s.endIndex._i, i == base.endIndex || base.indices.contains(i) else { return nil }
      _i = i
    }
  }

  /// One run: so many characters with these attributes.
  internal struct _Run: Hashable {
    var count: Int
    var attributes: _Attributes
  }

  internal var _string: String
  internal var _runs: [_Run]

  public init() {
    _string = ""
    _runs = []
  }
  public init(_ string: String, attributes: AttributeContainer = AttributeContainer()) {
    _string = string
    let n = string.count
    _runs = n > 0 ? [_Run(count: n, attributes: attributes._storage)] : []
  }
  public init<S: StringProtocol>(_ string: S, attributes: AttributeContainer = AttributeContainer()) {
    self.init(String(string), attributes: attributes)
  }
  public init(stringLiteral value: String) { self.init(value) }
  public init(_ substring: AttributedSubstring) {
    self = substring._materialize()
  }

  public var startIndex: Index { return Index(_string.startIndex) }
  public var endIndex: Index { return Index(_string.endIndex) }
  public var _bnBase: String { return _string }

  public var characters: CharacterView { return CharacterView(_string, _string.startIndex, _string.endIndex) }

  // -- whole-string attributes --

  public subscript<K: AttributedStringKey>(_ key: K.Type) -> K.Value? {
    get { return _uniform(K.name, 0, _string.count) }
    set { _set(K.name, newValue.map { AnyHashable($0) }, 0, _string.count) }
  }
  public subscript<K: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.FoundationAttributes, K>) -> K.Value? {
    get { return self[K.self] }
    set { self[K.self] = newValue }
  }
  public subscript<S: AttributeScope>(dynamicMember keyPath: KeyPath<AttributeScopes, S.Type>) -> ScopedAttributeContainer<S> {
    get { return ScopedAttributeContainer(_attributes(0, _string.count)) }
    set { _apply(newValue._storage, from: ScopedAttributeContainer<S>(_attributes(0, _string.count))._storage, 0, _string.count) }
  }

  public mutating func setAttributes(_ attributes: AttributeContainer) {
    let n = _string.count
    _runs = n > 0 ? [_Run(count: n, attributes: attributes._storage)] : []
  }
  public mutating func mergeAttributes(_ attributes: AttributeContainer) {
    for (k, v) in attributes._storage { _set(k, v, 0, _string.count) }
  }

  // -- ranges --

  public subscript<R: RangeExpression>(bounds: R) -> AttributedSubstring where R.Bound == Index {
    get {
      let r = bounds.relative(to: characters)
      return AttributedSubstring(self, r)
    }
    set {
      let r = bounds.relative(to: characters)
      replaceSubrange(r, with: newValue)
    }
  }

  public mutating func replaceSubrange<R: RangeExpression, S: AttributedStringProtocol>(_ range: R, with s: S)
    where R.Bound == Index
  {
    let r = range.relative(to: characters)
    let replacement = (s as? AttributedSubstring)?._materialize() ?? (s as? AttributedString) ?? AttributedString(s.description)
    let lo = _offset(r.lowerBound), hi = _offset(r.upperBound)
    var head = _slice(0, lo), tail = _slice(hi, _string.count)
    head._append(replacement)
    head._append(tail)
    tail = AttributedString()
    self = head
  }

  public mutating func append<S: AttributedStringProtocol>(_ s: S) {
    let other = (s as? AttributedSubstring)?._materialize() ?? (s as? AttributedString) ?? AttributedString(s.description)
    _append(other)
  }
  public mutating func insert<S: AttributedStringProtocol>(_ s: S, at index: Index) {
    replaceSubrange(index..<index, with: s)
  }
  public mutating func removeSubrange<R: RangeExpression>(_ range: R) where R.Bound == Index {
    replaceSubrange(range, with: AttributedString())
  }

  public static func + (a: AttributedString, b: AttributedString) -> AttributedString {
    var r = a
    r._append(b)
    return r
  }
  public static func += (a: inout AttributedString, b: AttributedString) { a._append(b) }

  /// The range of the first occurrence of a string.
  public func range<T: StringProtocol>(of s: T) -> Range<Index>? {
    guard let r = _string.range(of: String(s)) else { return nil }
    return Index(r.lowerBound)..<Index(r.upperBound)
  }

  public var description: String { return _describeRuns(_string, _runs) }

  // -- runs --

  /// Runs with their attributes, as text and containers.
  public var _bnRuns: [(String, AttributeContainer)] {
    var out: [(String, AttributeContainer)] = []
    var i = _string.startIndex
    for run in _runs {
      let j = _string.index(i, offsetBy: run.count)
      var c = AttributeContainer()
      c._storage = run.attributes
      out.append((String(_string[i..<j]), c))
      i = j
    }
    return out
  }

  // -- internals: offsets in characters --

  internal func _offset(_ i: Index) -> Int { return _string.distance(from: _string.startIndex, to: i._i) }

  internal func _attributes(_ lo: Int, _ hi: Int) -> _Attributes {
    var pos = 0
    for run in _runs {
      if pos + run.count > lo { return run.attributes }
      pos += run.count
    }
    return [:]
  }
  internal func _uniform<V>(_ name: String, _ lo: Int, _ hi: Int) -> V? {
    var pos = 0
    var value: AnyHashable? = nil
    var first = true
    for run in _runs {
      defer { pos += run.count }
      if pos + run.count <= lo || pos >= hi { continue }
      let v = run.attributes[name]
      if first { value = v; first = false } else if v != value { return nil }
    }
    return value?.base as? V
  }

  /// Split runs so lo and hi fall on run boundaries; returns the run range.
  internal mutating func _splitRuns(_ lo: Int, _ hi: Int) -> Range<Int> {
    func split(at x: Int) {
      var pos = 0
      for (k, run) in _runs.enumerated() {
        if x > pos && x < pos + run.count {
          _runs[k].count = x - pos
          _runs.insert(_Run(count: pos + run.count - x, attributes: run.attributes), at: k + 1)
          return
        }
        pos += run.count
      }
    }
    split(at: lo)
    split(at: hi)
    var pos = 0, a = _runs.count, b = _runs.count
    for (k, run) in _runs.enumerated() {
      if pos == lo && a == _runs.count { a = k }
      if pos == hi { b = k; break }
      pos += run.count
    }
    if a > b { a = b }
    return a..<b
  }

  internal mutating func _set(_ name: String, _ value: AnyHashable?, _ lo: Int, _ hi: Int) {
    guard lo < hi else { return }
    for k in _splitRuns(lo, hi) {
      if let v = value { _runs[k].attributes[name] = v } else { _runs[k].attributes.removeValue(forKey: name) }
    }
    _coalesce()
  }
  /// Apply a scope's edits: keys added, changed or removed relative to `old`.
  internal mutating func _apply(_ new: _Attributes, from old: _Attributes, _ lo: Int, _ hi: Int) {
    for (k, v) in new where old[k] != v { _set(k, v, lo, hi) }
    for k in old.keys where new[k] == nil { _set(k, nil, lo, hi) }
  }

  internal mutating func _coalesce() {
    var out: [_Run] = []
    for run in _runs where run.count > 0 {
      if let last = out.last, last.attributes == run.attributes {
        out[out.count - 1].count += run.count
      } else {
        out.append(run)
      }
    }
    _runs = out
  }

  internal func _slice(_ lo: Int, _ hi: Int) -> AttributedString {
    var r = AttributedString()
    let a = _string.index(_string.startIndex, offsetBy: lo), b = _string.index(_string.startIndex, offsetBy: hi)
    r._string = String(_string[a..<b])
    var pos = 0
    for run in _runs {
      let s = Swift.max(pos, lo), e = Swift.min(pos + run.count, hi)
      if s < e { r._runs.append(_Run(count: e - s, attributes: run.attributes)) }
      pos += run.count
    }
    return r
  }

  internal mutating func _append(_ other: AttributedString) {
    _string += other._string
    _runs += other._runs
    _coalesce()
  }

  public static func == (a: AttributedString, b: AttributedString) -> Bool {
    return a._string == b._string && a._runs == b._runs
  }
  public func hash(into h: inout Hasher) {
    h.combine(_string)
    h.combine(_runs)
  }
}

internal func _describeRuns(_ s: String, _ runs: [AttributedString._Run]) -> String {
  var out = ""
  var i = s.startIndex
  for run in runs {
    let j = s.index(i, offsetBy: run.count)
    out += "\(s[i..<j]) {\n\(_describe(run.attributes))\n}\n"
    i = j
  }
  return out
}

// ---- characters ----------------------------------------------------------------

extension AttributedString {
  public struct CharacterView: BidirectionalCollection, RangeReplaceableCollection, Hashable {
    public typealias Element = Character
    public typealias Index = AttributedString.Index
    internal var _s: String
    internal var _lo: String.Index, _hi: String.Index

    internal init(_ s: String, _ lo: String.Index, _ hi: String.Index) {
      _s = s
      _lo = lo
      _hi = hi
    }
    public init() {
      _s = ""
      _lo = _s.startIndex
      _hi = _s.endIndex
    }
    public var startIndex: Index { return Index(_lo) }
    public var endIndex: Index { return Index(_hi) }
    public func index(after i: Index) -> Index { return Index(_s.index(after: i._i)) }
    public func index(before i: Index) -> Index { return Index(_s.index(before: i._i)) }
    public subscript(i: Index) -> Character { return _s[i._i] }
    public mutating func replaceSubrange<C: Collection>(_ r: Range<Index>, with c: C) where C.Element == Character {
      let lo = _s.distance(from: _s.startIndex, to: _lo), n = _s.distance(from: _lo, to: _hi)
      let removed = _s.distance(from: r.lowerBound._i, to: r.upperBound._i)
      _s.replaceSubrange(r.lowerBound._i..<r.upperBound._i, with: c)
      _lo = _s.index(_s.startIndex, offsetBy: lo)
      _hi = _s.index(_lo, offsetBy: n - removed + c.count)
    }
    public static func == (a: CharacterView, b: CharacterView) -> Bool { return String(a._s[a._lo..<a._hi]) == String(b._s[b._lo..<b._hi]) }
    public func hash(into h: inout Hasher) { h.combine(String(_s[_lo..<_hi])) }
  }
}

extension String {
  public init(_characters: AttributedString.CharacterView) {
    self = String(_characters._s[_characters._lo..<_characters._hi])
  }
  public init(_ characters: Slice<AttributedString.CharacterView>) {
    let base = characters.base
    self = String(base._s[characters.startIndex._i..<characters.endIndex._i])
  }
}

extension Range where Bound == AttributedString.Index {
  /// A String range as attributed string indices, if they are its boundaries.
  public init?<R: RangeExpression, S: AttributedStringProtocol>(_ range: R, in s: S) where R.Bound == String.Index {
    let base = s._bnBase
    let r = range.relative(to: base)
    guard let lo = AttributedString.Index(r.lowerBound, within: s),
          let hi = AttributedString.Index(r.upperBound, within: s) else { return nil }
    self = lo..<hi
  }
}

// ---- substrings ------------------------------------------------------------------

@dynamicMemberLookup
public struct AttributedSubstring: AttributedStringProtocol, Hashable, @unchecked Sendable {
  internal var _base: AttributedString
  internal var _range: Range<AttributedString.Index>

  internal init(_ base: AttributedString, _ range: Range<AttributedString.Index>) {
    _base = base
    _range = range
  }
  public init() { self.init(AttributedString(), AttributedString().startIndex..<AttributedString().endIndex) }

  public var startIndex: AttributedString.Index { return _range.lowerBound }
  public var endIndex: AttributedString.Index { return _range.upperBound }
  public var _bnBase: String { return _base._string }
  public var base: AttributedString { return _base }
  public var characters: Slice<AttributedString.CharacterView> { return _base.characters[_range] }

  internal var _lo: Int { return _base._offset(_range.lowerBound) }
  internal var _hi: Int { return _base._offset(_range.upperBound) }

  internal func _materialize() -> AttributedString { return _base._slice(_lo, _hi) }

  public subscript<K: AttributedStringKey>(_ key: K.Type) -> K.Value? {
    get { return _base._uniform(K.name, _lo, _hi) }
    set { _base._set(K.name, newValue.map { AnyHashable($0) }, _lo, _hi) }
  }
  public subscript<K: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.FoundationAttributes, K>) -> K.Value? {
    get { return self[K.self] }
    set { self[K.self] = newValue }
  }
  public subscript<S: AttributeScope>(dynamicMember keyPath: KeyPath<AttributeScopes, S.Type>) -> ScopedAttributeContainer<S> {
    get { return ScopedAttributeContainer(_base._attributes(_lo, _hi)) }
    set { _base._apply(newValue._storage, from: _base._attributes(_lo, _hi), _lo, _hi) }
  }

  public var description: String { return _materialize().description }
  public static func == (a: AttributedSubstring, b: AttributedSubstring) -> Bool { return a._materialize() == b._materialize() }
  public func hash(into h: inout Hasher) { h.combine(_materialize()) }
}

// ---- localization ------------------------------------------------------------------

extension AttributedString {
  public struct FormattingOptions: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let applyReplacementIndexAttribute = FormattingOptions(rawValue: 1)
  }
  public struct InterpolationOptions: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let insertAttributesWithoutMerging = InterpolationOptions(rawValue: 1)
  }

  public init(localized resource: LocalizedStringResource) {
    self.init(String(localized: resource))
  }
  public init(localized keyAndValue: String.LocalizationValue, options: FormattingOptions = [], table: String? = nil,
              bundle: Bundle? = nil, locale: Locale? = nil, comment: StaticString? = nil) {
    self.init(String(localized: keyAndValue, table: table, bundle: bundle, locale: locale ?? .current, comment: comment))
  }
}

extension String.LocalizationValue.StringInterpolation {
  /// An attributed string's text, as a string argument (its attributes do
  /// not carry into the plain localized string).
  public mutating func appendInterpolation(_ attributedString: AttributedString,
                                           options: AttributedString.InterpolationOptions = []) {
    appendInterpolation(String(_characters: attributedString.characters))
  }
}
