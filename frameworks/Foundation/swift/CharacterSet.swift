// CharacterSet: a set of Unicode scalars, kept as sorted, disjoint,
// non-adjacent ranges of code points. The predefined sets take their
// Basic Multilingual Plane members from NSCharacterSet.

public struct CharacterSet: Hashable, Sendable {
  public typealias Element = Unicode.Scalar

  /// Sorted, disjoint, non-adjacent closed ranges of code points.
  internal var _ranges: [ClosedRange<UInt32>]

  internal init(_ranges: [ClosedRange<UInt32>]) { self._ranges = _ranges }

  public init() { _ranges = [] }

  public init(charactersIn range: Range<Unicode.Scalar>) {
    let lo = range.lowerBound.value, hi = range.upperBound.value
    _ranges = lo < hi ? [lo...(hi - 1)] : []
  }

  public init(charactersIn range: ClosedRange<Unicode.Scalar>) {
    _ranges = [range.lowerBound.value...range.upperBound.value]
  }

  public init(charactersIn string: __shared String) {
    self.init(_ranges: CharacterSet._normalize(string.unicodeScalars.map { $0.value...$0.value }))
  }

  /// Sorts and merges overlapping or adjacent ranges.
  internal static func _normalize(_ input: [ClosedRange<UInt32>]) -> [ClosedRange<UInt32>] {
    let sorted = input.sorted { $0.lowerBound < $1.lowerBound }
    var out: [ClosedRange<UInt32>] = []
    for r in sorted {
      if let last = out.last, r.lowerBound <= last.upperBound &+ 1 {
        out[out.count - 1] = last.lowerBound...max(last.upperBound, r.upperBound)
      } else {
        out.append(r)
      }
    }
    return out
  }

  internal func _containsValue(_ v: UInt32) -> Bool {
    var lo = 0, hi = _ranges.count
    while lo < hi {
      let mid = (lo + hi) / 2
      let r = _ranges[mid]
      if v < r.lowerBound { hi = mid } else if v > r.upperBound { lo = mid + 1 } else { return true }
    }
    return false
  }

  public var inverted: CharacterSet {
    var out: [ClosedRange<UInt32>] = []
    var next: UInt32 = 0
    for r in _ranges {
      if r.lowerBound > next { out.append(next...(r.lowerBound - 1)) }
      next = r.upperBound &+ 1
    }
    if next <= 0x10FFFF { out.append(next...0x10FFFF) }
    return CharacterSet(_ranges: out)
  }

  public mutating func insert(charactersIn range: Range<Unicode.Scalar>) { formUnion(CharacterSet(charactersIn: range)) }
  public mutating func insert(charactersIn range: ClosedRange<Unicode.Scalar>) { formUnion(CharacterSet(charactersIn: range)) }
  public mutating func insert(charactersIn string: String) { formUnion(CharacterSet(charactersIn: string)) }
  public mutating func remove(charactersIn range: Range<Unicode.Scalar>) { subtract(CharacterSet(charactersIn: range)) }
  public mutating func remove(charactersIn range: ClosedRange<Unicode.Scalar>) { subtract(CharacterSet(charactersIn: range)) }
  public mutating func remove(charactersIn string: String) { subtract(CharacterSet(charactersIn: string)) }
  public mutating func invert() { self = inverted }

  public func hasMember(inPlane plane: UInt8) -> Bool {
    let lo = UInt32(plane) << 16, hi = lo + 0xFFFF
    return _ranges.contains { $0.lowerBound <= hi && $0.upperBound >= lo }
  }
  public var isEmpty: Bool { return _ranges.isEmpty }

  public static func == (lhs: CharacterSet, rhs: CharacterSet) -> Bool {
    guard lhs._ranges.count == rhs._ranges.count else { return false }
    for i in 0..<lhs._ranges.count where lhs._ranges[i] != rhs._ranges[i] { return false }
    return true
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(_ranges.count)
    for r in _ranges {
      hasher.combine(r.lowerBound)
      hasher.combine(r.upperBound)
    }
  }
}

// ---- predefined sets ----

extension CharacterSet {
  /// The BMP members of an NSCharacterSet, as ranges.
  internal static func _fromNS(_ ns: NSCharacterSet, extra: [ClosedRange<UInt32>] = []) -> CharacterSet {
    var out: [ClosedRange<UInt32>] = []
    var start: UInt32? = nil
    var c: UInt32 = 0
    while c <= 0xFFFF {
      let member = ns.characterIsMember(UInt16(c))
      if member, start == nil { start = c }
      if !member, let s = start { out.append(s...(c - 1)); start = nil }
      c += 1
    }
    if let s = start { out.append(s...0xFFFF) }
    return CharacterSet(_ranges: _normalize(out + extra))
  }

  // Letters outside the BMP: the supplementary ideographic planes and the
  // historic scripts of plane 1 (an approximation of the Unicode tables).
  internal static let _supplementaryLetters: [ClosedRange<UInt32>] = [0x10000...0x1BFFF, 0x1D400...0x1D7FF, 0x20000...0x3FFFF]

  internal static let _letters = _fromNS(NSCharacterSet.letters, extra: _supplementaryLetters)
  internal static let _alphanumerics = _fromNS(NSCharacterSet.alphanumerics, extra: _supplementaryLetters)
  internal static let _whitespaces = _fromNS(NSCharacterSet.whitespaces)
  internal static let _whitespacesAndNewlines = _fromNS(NSCharacterSet.whitespacesAndNewlines)
  internal static let _newlines = _fromNS(NSCharacterSet.newlines)
  internal static let _decimalDigits = _fromNS(NSCharacterSet.decimalDigits)
  internal static let _uppercaseLetters = _fromNS(NSCharacterSet.uppercaseLetters)
  internal static let _lowercaseLetters = _fromNS(NSCharacterSet.lowercaseLetters)
  internal static let _punctuationCharacters = _fromNS(NSCharacterSet.punctuationCharacters)
  internal static let _controlCharacters = CharacterSet(_ranges: [0...0x1F, 0x7F...0x9F])
  internal static let _symbols = CharacterSet(charactersIn: "$+<=>^`|~\u{A2}\u{A3}\u{A4}\u{A5}\u{A6}\u{A8}\u{A9}\u{AC}\u{AE}\u{AF}\u{B0}\u{B1}\u{B4}\u{B8}\u{D7}\u{F7}")
    .union(CharacterSet(_ranges: [0x2100...0x2BFF, 0x1F000...0x1FAFF]))

  public static var letters: CharacterSet { return _letters }
  public static var alphanumerics: CharacterSet { return _alphanumerics }
  public static var whitespaces: CharacterSet { return _whitespaces }
  public static var whitespacesAndNewlines: CharacterSet { return _whitespacesAndNewlines }
  public static var newlines: CharacterSet { return _newlines }
  public static var decimalDigits: CharacterSet { return _decimalDigits }
  public static var uppercaseLetters: CharacterSet { return _uppercaseLetters }
  public static var lowercaseLetters: CharacterSet { return _lowercaseLetters }
  public static var capitalizedLetters: CharacterSet { return _uppercaseLetters }
  public static var punctuationCharacters: CharacterSet { return _punctuationCharacters }
  public static var controlCharacters: CharacterSet { return _controlCharacters }
  public static var symbols: CharacterSet { return _symbols }
  public static var illegalCharacters: CharacterSet { return CharacterSet(_ranges: [0xD800...0xDFFF, 0xFFFE...0xFFFF]) }
  public static var nonBaseCharacters: CharacterSet { return CharacterSet(_ranges: [0x0300...0x036F, 0x1AB0...0x1AFF, 0x1DC0...0x1DFF, 0x20D0...0x20FF, 0xFE20...0xFE2F]) }
  public static var decomposables: CharacterSet { return CharacterSet(_ranges: [0xC0...0x17F]) }

  // URL component sets (RFC 3986 unreserved plus each component's allowed
  // delimiters, as Foundation defines them).
  internal static let _unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
  public static var urlUserAllowed: CharacterSet { return _unreserved.union(CharacterSet(charactersIn: "!$&'()*+,;=")) }
  public static var urlPasswordAllowed: CharacterSet { return _unreserved.union(CharacterSet(charactersIn: "!$&'()*+,;=")) }
  public static var urlHostAllowed: CharacterSet { return _unreserved.union(CharacterSet(charactersIn: "!$&'()*+,;=:[]")) }
  public static var urlPathAllowed: CharacterSet { return _unreserved.union(CharacterSet(charactersIn: "!$&'()*+,;=:@/")) }
  public static var urlQueryAllowed: CharacterSet { return _unreserved.union(CharacterSet(charactersIn: "!$&'()*+,;=:@/?")) }
  public static var urlFragmentAllowed: CharacterSet { return _unreserved.union(CharacterSet(charactersIn: "!$&'()*+,;=:@/?")) }
}

// ---- SetAlgebra ----

extension CharacterSet: SetAlgebra {
  public func contains(_ member: Unicode.Scalar) -> Bool { return _containsValue(member.value) }

  public func union(_ other: CharacterSet) -> CharacterSet {
    return CharacterSet(_ranges: CharacterSet._normalize(_ranges + other._ranges))
  }
  public func intersection(_ other: CharacterSet) -> CharacterSet {
    var out: [ClosedRange<UInt32>] = []
    var i = 0, j = 0
    let a = _ranges, b = other._ranges
    while i < a.count && j < b.count {
      let lo = max(a[i].lowerBound, b[j].lowerBound), hi = min(a[i].upperBound, b[j].upperBound)
      if lo <= hi { out.append(lo...hi) }
      if a[i].upperBound < b[j].upperBound { i += 1 } else { j += 1 }
    }
    return CharacterSet(_ranges: out)
  }
  public func symmetricDifference(_ other: CharacterSet) -> CharacterSet {
    return union(other).subtracting(intersection(other))
  }
  public func subtracting(_ other: CharacterSet) -> CharacterSet {
    return intersection(other.inverted)
  }

  @discardableResult
  public mutating func insert(_ character: Unicode.Scalar) -> (inserted: Bool, memberAfterInsert: Unicode.Scalar) {
    if contains(character) { return (false, character) }
    formUnion(CharacterSet(_ranges: [character.value...character.value]))
    return (true, character)
  }
  @discardableResult
  public mutating func update(with character: Unicode.Scalar) -> Unicode.Scalar? {
    let had = contains(character)
    insert(character)
    return had ? character : nil
  }
  @discardableResult
  public mutating func remove(_ character: Unicode.Scalar) -> Unicode.Scalar? {
    guard contains(character) else { return nil }
    subtract(CharacterSet(_ranges: [character.value...character.value]))
    return character
  }
  public mutating func formUnion(_ other: CharacterSet) { self = union(other) }
  public mutating func formIntersection(_ other: CharacterSet) { self = intersection(other) }
  public mutating func formSymmetricDifference(_ other: CharacterSet) { self = symmetricDifference(other) }
  public mutating func subtract(_ other: CharacterSet) { self = subtracting(other) }
  public func isSubset(of other: CharacterSet) -> Bool { return subtracting(other).isEmpty }
  public func isSuperset(of other: CharacterSet) -> Bool { return other.isSubset(of: self) }
  public func isDisjoint(with other: CharacterSet) -> Bool { return intersection(other).isEmpty }
}

extension CharacterSet: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String { return "<CharacterSet: \(_ranges.count) ranges>" }
  public var debugDescription: String { return description }
}

extension CharacterSet: Codable {
  public init(from decoder: any Decoder) throws {
    var c = try decoder.unkeyedContainer()
    var ranges: [ClosedRange<UInt32>] = []
    while !c.isAtEnd {
      let lo = try c.decode(UInt32.self), hi = try c.decode(UInt32.self)
      ranges.append(lo...hi)
    }
    self.init(_ranges: CharacterSet._normalize(ranges))
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.unkeyedContainer()
    for r in _ranges {
      try c.encode(r.lowerBound)
      try c.encode(r.upperBound)
    }
  }
}
