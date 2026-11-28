// Foundation's additions to String and StringProtocol: encodings, format
// strings, character-set operations, comparison with options, searching and
// replacing. Comparison and search work on Characters in Swift; the
// "localized" variants use the same rules as the plain ones.

extension String {
  public typealias CompareOptions = NSString.CompareOptions

  public struct Encoding: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static var ascii: Encoding { return Encoding(rawValue: 1) }
    public static var nextstep: Encoding { return Encoding(rawValue: 2) }
    public static var japaneseEUC: Encoding { return Encoding(rawValue: 3) }
    public static var utf8: Encoding { return Encoding(rawValue: 4) }
    public static var isoLatin1: Encoding { return Encoding(rawValue: 5) }
    public static var symbol: Encoding { return Encoding(rawValue: 6) }
    public static var nonLossyASCII: Encoding { return Encoding(rawValue: 7) }
    public static var shiftJIS: Encoding { return Encoding(rawValue: 8) }
    public static var isoLatin2: Encoding { return Encoding(rawValue: 9) }
    public static var unicode: Encoding { return Encoding(rawValue: 10) }
    public static var windowsCP1251: Encoding { return Encoding(rawValue: 11) }
    public static var windowsCP1252: Encoding { return Encoding(rawValue: 12) }
    public static var windowsCP1253: Encoding { return Encoding(rawValue: 13) }
    public static var windowsCP1254: Encoding { return Encoding(rawValue: 14) }
    public static var windowsCP1250: Encoding { return Encoding(rawValue: 15) }
    public static var iso2022JP: Encoding { return Encoding(rawValue: 21) }
    public static var macOSRoman: Encoding { return Encoding(rawValue: 30) }
    public static var utf16: Encoding { return Encoding(rawValue: 10) }
    public static var utf16BigEndian: Encoding { return Encoding(rawValue: 0x90000100) }
    public static var utf16LittleEndian: Encoding { return Encoding(rawValue: 0x94000100) }
    public static var utf32: Encoding { return Encoding(rawValue: 0x8c000100) }
    public static var utf32BigEndian: Encoding { return Encoding(rawValue: 0x98000100) }
    public static var utf32LittleEndian: Encoding { return Encoding(rawValue: 0x9c000100) }

    public var description: String {
      switch rawValue {
      case 1: return "Western (ASCII)"
      case 4: return "Unicode (UTF-8)"
      case 5: return "Western (ISO Latin 1)"
      case 10: return "Unicode (UTF-16)"
      case 30: return "Western (Mac OS Roman)"
      default: return "String.Encoding(rawValue: \(rawValue))"
      }
    }
  }

  public init(format: __shared String, _ arguments: CVarArg...) {
    self = String(format: format, arguments: arguments)
  }
  public init(format: __shared String, arguments: __shared [CVarArg]) {
    self = withVaList(arguments) { NSString(format: format, arguments: $0) as String }
  }

  public init(utf16CodeUnits: UnsafePointer<unichar>, count: Int) {
    self = String(decoding: UnsafeBufferPointer(start: utf16CodeUnits, count: count), as: UTF16.self)
  }
}

// MARK: - comparison

internal func _isDigit(_ c: Character) -> Bool {
  guard let a = c.asciiValue else { return false }
  return a >= 48 && a <= 57
}

/// The string without its accents: decomposed, combining marks dropped,
/// recomposed ("café" is "cafe").
internal func _stripDiacritics(_ s: String) -> String {
  var out = ""
  for u in _bitten_normalize(s, form: 1).unicodeScalars where u.properties.generalCategory != .nonspacingMark {
    out.unicodeScalars.append(u)
  }
  return _bitten_normalize(out, form: 0)
}

/// Compares two strings with NSString's options: case and diacritic
/// insensitivity and numeric runs.
internal func _foundationCompare(_ lhs: String, _ rhs: String, _ options: String.CompareOptions) -> ComparisonResult {
  let caseless = options.contains(.caseInsensitive), accentless = options.contains(.diacriticInsensitive)
  func prepare(_ s: String) -> [Character] {
    var t = accentless ? _stripDiacritics(s) : s
    if caseless { t = t.lowercased() }
    return Array(t)
  }
  let a = prepare(lhs)
  let b = prepare(rhs)
  let numeric = options.contains(.numeric)
  var i = 0, j = 0
  while i < a.count && j < b.count {
    if numeric && _isDigit(a[i]) && _isDigit(b[j]) {
      var ei = i, ej = j
      while ei < a.count && _isDigit(a[ei]) { ei += 1 }
      while ej < b.count && _isDigit(b[ej]) { ej += 1 }
      // Compare digit runs as numbers: strip leading zeros, then by length.
      var si = i, sj = j
      while si < ei - 1 && a[si] == "0" { si += 1 }
      while sj < ej - 1 && b[sj] == "0" { sj += 1 }
      if ei - si != ej - sj { return ei - si < ej - sj ? .orderedAscending : .orderedDescending }
      var k = 0
      while si + k < ei {
        if a[si + k] != b[sj + k] { return a[si + k] < b[sj + k] ? .orderedAscending : .orderedDescending }
        k += 1
      }
      i = ei
      j = ej
      continue
    }
    if a[i] != b[j] {
      let x = String(a[i]).unicodeScalars.first!.value, y = String(b[j]).unicodeScalars.first!.value
      if x != y { return x < y ? .orderedAscending : .orderedDescending }
      return String(a[i]) < String(b[j]) ? .orderedAscending : .orderedDescending
    }
    i += 1
    j += 1
  }
  if a.count - i == b.count - j { return .orderedSame }
  return a.count - i < b.count - j ? .orderedAscending : .orderedDescending
}

// MARK: - searching

extension StringProtocol {
  /// Finds `target` in `searchRange` (Character offsets), honoring the
  /// case-insensitive, backwards and anchored options.
  internal func _foundationFind(_ target: [Character], in hay: [Character], _ options: String.CompareOptions,
                                from lo: Int, to hi: Int) -> Swift.Range<Int>? {
    if target.isEmpty { return nil }
    let fold = options.contains(.caseInsensitive)
    func eq(_ x: Character, _ y: Character) -> Bool { return fold ? x.lowercased() == y.lowercased() : x == y }
    func matches(at p: Int) -> Bool {
      if p < lo || p + target.count > hi { return false }
      for k in 0..<target.count where !eq(hay[p + k], target[k]) { return false }
      return true
    }
    if hi - lo < target.count { return nil }
    if options.contains(.backwards) {
      if options.contains(.anchored) { return matches(at: hi - target.count) ? (hi - target.count)..<hi : nil }
      var p = hi - target.count
      while p >= lo {
        if matches(at: p) { return p..<(p + target.count) }
        p -= 1
      }
      return nil
    }
    if options.contains(.anchored) { return matches(at: lo) ? lo..<(lo + target.count) : nil }
    var p = lo
    while p + target.count <= hi {
      if matches(at: p) { return p..<(p + target.count) }
      p += 1
    }
    return nil
  }

  internal func _characterOffsets(of range: Swift.Range<Index>?) -> (Int, Int) {
    guard let r = range else { return (0, count) }
    return (distance(from: startIndex, to: r.lowerBound), distance(from: startIndex, to: r.upperBound))
  }
  internal func _indexRange(_ r: Swift.Range<Int>) -> Swift.Range<Index> {
    let lo = index(startIndex, offsetBy: r.lowerBound)
    return lo..<index(lo, offsetBy: r.count)
  }

  public func range<T: StringProtocol>(of aString: T, options mask: String.CompareOptions = [],
                                       range searchRange: Swift.Range<Index>? = nil, locale: Locale? = nil) -> Swift.Range<Index>? {
    if mask.contains(.regularExpression) {
      let whole = String(self)
      guard let re = _regex(String(aString), mask) else { return nil }
      let ns = NSRange(searchRange.map { $0.lowerBound..<$0.upperBound } ?? startIndex..<endIndex, in: self)
      var opts: NSRegularExpression.MatchingOptions = []
      if mask.contains(.anchored) { opts.insert(.anchored) }
      guard let m = re.firstMatch(in: whole, options: opts, range: ns), let r = Swift.Range(m.range, in: whole) else {
        return nil
      }
      return index(startIndex, offsetBy: whole.distance(from: whole.startIndex, to: r.lowerBound))
        ..< index(startIndex, offsetBy: whole.distance(from: whole.startIndex, to: r.upperBound))
    }
    let hay = Array(self)
    let (lo, hi) = _characterOffsets(of: searchRange)
    guard let r = _foundationFind(Array(aString), in: hay, mask, from: lo, to: hi) else { return nil }
    return _indexRange(r)
  }

  /// The pattern of a .regularExpression search (case-insensitive when
  /// asked); nil when it doesn't compile.
  internal func _regex(_ pattern: String, _ mask: String.CompareOptions) -> NSRegularExpression? {
    return try? NSRegularExpression(pattern: pattern, options: mask.contains(.caseInsensitive) ? [.caseInsensitive] : [])
  }

  @_disfavoredOverload
  public func contains<T: StringProtocol>(_ other: T) -> Bool {
    return range(of: other, options: [], range: nil, locale: nil) != nil
  }
  public func localizedCaseInsensitiveContains<T: StringProtocol>(_ other: T) -> Bool {
    return range(of: other, options: .caseInsensitive, range: nil, locale: nil) != nil
  }
  public func localizedStandardContains<T: StringProtocol>(_ string: T) -> Bool {
    return range(of: string, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: nil) != nil
  }
  public func localizedStandardRange<T: StringProtocol>(of target: T) -> Swift.Range<Index>? {
    return range(of: target, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: nil)
  }

  public func compare<T: StringProtocol>(_ aString: T, options mask: String.CompareOptions = [],
                                         range: Swift.Range<Index>? = nil, locale: Locale? = nil) -> ComparisonResult {
    let me = range.map { String(self[$0]) } ?? String(self)
    return _foundationCompare(me, String(aString), mask)
  }
  public func caseInsensitiveCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
    return _foundationCompare(String(self), String(aString), .caseInsensitive)
  }
  public func localizedCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
    return _foundationCompare(String(self), String(aString), [])
  }
  public func localizedCaseInsensitiveCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
    return _foundationCompare(String(self), String(aString), .caseInsensitive)
  }
  /// As the Finder sorts: digits as numbers, case and accents ignored, and
  /// then, between strings that differ only so, lower case first and
  /// unaccented first (the collation's later levels).
  public func localizedStandardCompare<T: StringProtocol>(_ string: T) -> ComparisonResult {
    let a = String(self), b = String(string)
    let primary = _foundationCompare(a, b, [.caseInsensitive, .diacriticInsensitive, .numeric])
    if primary != .orderedSame { return primary }
    let accents = _foundationCompare(a, b, [.caseInsensitive, .numeric])
    if accents != .orderedSame { return accents }
    // lower case before upper case, character by character
    for (x, y) in zip(a, b) where x != y {
      if x.lowercased() == y.lowercased() { return x.isLowercase ? .orderedAscending : .orderedDescending }
    }
    return _foundationCompare(a, b, [.numeric])
  }

  public func folding(options: String.CompareOptions = [], locale: Locale?) -> String {
    var s = String(self)
    if options.contains(.diacriticInsensitive) { s = _stripDiacritics(s) }
    if options.contains(.caseInsensitive) { s = s.lowercased() }
    if options.contains(.widthInsensitive) { s = _bitten_normalize(s, form: 2) }
    return s
  }

  public func replacingOccurrences<Target: StringProtocol, Replacement: StringProtocol>(
    of target: Target, with replacement: Replacement, options: String.CompareOptions = [],
    range searchRange: Swift.Range<Index>? = nil
  ) -> String {
    if options.contains(.regularExpression) {
      // the replacement is a template ($1 is the first group)
      let whole = String(self)
      guard let re = _regex(String(target), options) else { return whole }
      let ns = NSRange(searchRange.map { $0.lowerBound..<$0.upperBound } ?? startIndex..<endIndex, in: self)
      var opts: NSRegularExpression.MatchingOptions = []
      if options.contains(.anchored) { opts.insert(.anchored) }
      return re.stringByReplacingMatches(in: whole, options: opts, range: ns, withTemplate: String(replacement))
    }
    let hay = Array(self)
    let needle = Array(target)
    var (lo, hi) = _characterOffsets(of: searchRange)
    if needle.isEmpty { return String(self) }
    var out = String(hay[0..<lo])
    let opts = options.subtracting(.backwards)
    while let r = _foundationFind(needle, in: hay, opts, from: lo, to: hi) {
      out += String(hay[lo..<r.lowerBound])
      out += String(replacement)
      lo = r.upperBound
      if options.contains(.anchored) { break }
    }
    out += String(hay[lo..<hay.count])
    return out
  }

  public func components<T: StringProtocol>(separatedBy separator: T) -> [String] {
    let hay = Array(self)
    let needle = Array(separator)
    var out: [String] = []
    var start = 0
    while let r = _foundationFind(needle, in: hay, [], from: start, to: hay.count) {
      out.append(String(hay[start..<r.lowerBound]))
      start = r.upperBound
    }
    out.append(String(hay[start..<hay.count]))
    return out
  }

  public func components(separatedBy separator: CharacterSet) -> [String] {
    var out: [String] = []
    var current = String.UnicodeScalarView()
    for s in unicodeScalars {
      if separator.contains(s) {
        out.append(String(current))
        current = String.UnicodeScalarView()
      } else {
        current.append(s)
      }
    }
    out.append(String(current))
    return out
  }

  public func trimmingCharacters(in set: CharacterSet) -> String {
    let scalars = Array(unicodeScalars)
    var lo = 0, hi = scalars.count
    while lo < hi && set.contains(scalars[lo]) { lo += 1 }
    while hi > lo && set.contains(scalars[hi - 1]) { hi -= 1 }
    var view = String.UnicodeScalarView()
    view.append(contentsOf: scalars[lo..<hi])
    return String(view)
  }

  public func rangeOfCharacter(from aSet: CharacterSet, options mask: String.CompareOptions = [],
                               range aRange: Swift.Range<Index>? = nil) -> Swift.Range<Index>? {
    let view = unicodeScalars
    let lo = aRange?.lowerBound ?? view.startIndex
    let hi = aRange?.upperBound ?? view.endIndex
    if mask.contains(.backwards) {
      var i = hi
      while i > lo {
        let p = view.index(before: i)
        if aSet.contains(view[p]) { return p..<i }
        if mask.contains(.anchored) { return nil }
        i = p
      }
      return nil
    }
    var i = lo
    while i < hi {
      let n = view.index(after: i)
      if aSet.contains(view[i]) { return i..<n }
      if mask.contains(.anchored) { return nil }
      i = n
    }
    return nil
  }

  public func addingPercentEncoding(withAllowedCharacters allowedCharacters: CharacterSet) -> String? {
    let hex: [UInt8] = Array("0123456789ABCDEF".utf8)
    var out: [UInt8] = []
    for s in unicodeScalars {
      if allowedCharacters.contains(s) {
        out.append(contentsOf: String(s).utf8)
      } else {
        for b in String(s).utf8 {
          out.append(37)
          out.append(hex[Int(b >> 4)])
          out.append(hex[Int(b & 15)])
        }
      }
    }
    return String(decoding: out, as: UTF8.self)
  }

  public var removingPercentEncoding: String? {
    let bytes = Array(utf8)
    var out: [UInt8] = []
    var i = 0
    func hexValue(_ b: UInt8) -> UInt8? {
      switch b {
      case 48...57: return b - 48
      case 65...70: return b - 55
      case 97...102: return b - 87
      default: return nil
      }
    }
    while i < bytes.count {
      if bytes[i] == 37 {
        guard i + 2 < bytes.count, let h = hexValue(bytes[i + 1]), let l = hexValue(bytes[i + 2]) else { return nil }
        out.append(h << 4 | l)
        i += 3
      } else {
        out.append(bytes[i])
        i += 1
      }
    }
    let s = String(decoding: out, as: UTF8.self)
    return Array(s.utf8) == out ? s : nil // nil when the bytes are not valid UTF-8
  }

  // Unicode normalization forms (NFC, NFD, NFKC, NFKD).
  public var precomposedStringWithCanonicalMapping: String { return _bitten_normalize(String(self), form: 0) }
  public var decomposedStringWithCanonicalMapping: String { return _bitten_normalize(String(self), form: 1) }
  public var precomposedStringWithCompatibilityMapping: String { return _bitten_normalize(String(self), form: 2) }
  public var decomposedStringWithCompatibilityMapping: String { return _bitten_normalize(String(self), form: 3) }

  /// Cut or padded with repeats of `padString` (from `padIndex` of it) to
  /// `newLength` characters.
  public func padding<T: StringProtocol>(toLength newLength: Int, withPad padString: T, startingAt padIndex: Int) -> String {
    let chars = Array(self)
    if newLength <= chars.count { return String(chars[0..<Swift.max(newLength, 0)]) }
    let pad = Array(padString)
    precondition(!pad.isEmpty && padIndex >= 0 && padIndex < pad.count, "invalid pad")
    var out = String(self)
    var k = padIndex
    for _ in chars.count..<newLength {
      out.append(pad[k])
      k = (k + 1) % pad.count
    }
    return out
  }

  /// Each line (without its terminator), until `stop` is set.
  public func enumerateLines(invoking body: @escaping (_ line: String, _ stop: inout Bool) -> Void) {
    var stop = false
    var line = ""
    var pendingCR = false
    for c in self {
      if c == "\r\n" || c == "\n" || c == "\r" || c == "\u{2028}" || c == "\u{2029}" || c == "\u{85}" {
        body(line, &stop)
        if stop { return }
        line = ""
        pendingCR = false
      } else {
        line.append(c)
      }
    }
    _ = pendingCR
    if !line.isEmpty { body(line, &stop) }
  }

  public var capitalized: String {
    var out = ""
    var atWordStart = true
    let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    for c in self {
      if let first = c.unicodeScalars.first, separators.contains(first) {
        out.append(c)
        atWordStart = true
      } else {
        // a word's first letter in title case ("ǆ" -> "ǅ", not "Ǆ")
        if atWordStart, let first = c.unicodeScalars.first {
          out += first.properties.titlecaseMapping
          for s in c.unicodeScalars.dropFirst() { out += s.properties.lowercaseMapping }
        } else {
          out += c.lowercased()
        }
        atWordStart = false
      }
    }
    return out
  }
  public var localizedCapitalized: String { return capitalized }
  public var localizedLowercase: String { return lowercased() }
  public var localizedUppercase: String { return uppercased() }
}

// MARK: - objects as C variadic arguments (%@)

extension NSObject: CVarArg {
  public var _cVarArgEncoding: [Int] {
    // Kept alive by the autorelease pool, as the callee only borrows it.
    return [Int(bitPattern: Unmanaged.passRetained(self).autorelease().toOpaque())]
  }
}
extension String: CVarArg {
  public var _cVarArgEncoding: [Int] { return (self as NSString)._cVarArgEncoding }
}
extension Substring: CVarArg {
  public var _cVarArgEncoding: [Int] { return String(self)._cVarArgEncoding }
}
