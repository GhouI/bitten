// Scanner's Swift methods (macOS 10.15): optionals instead of out
// parameters, and String.Index positions.

extension Scanner {
  public enum NumberRepresentation: Sendable {
    case decimal
    case hexadecimal
  }

  /// The position as a String.Index of `string`.
  public var currentIndex: String.Index {
    get {
      let s = string
      let u = s.utf16
      let i = u.index(u.startIndex, offsetBy: Swift.min(scanLocation, u.count))
      return i.samePosition(in: s) ?? s.endIndex
    }
    set { scanLocation = newValue.utf16Offset(in: string) }
  }

  public func scanInt(representation: NumberRepresentation = .decimal) -> Int? {
    if representation == .hexadecimal {
      var v: UInt64 = 0
      return scanHexInt64(&v) ? Int(truncatingIfNeeded: v) : nil
    }
    var v = 0
    return scanInteger(&v) ? v : nil
  }
  public func scanInt64(representation: NumberRepresentation = .decimal) -> Int64? {
    if representation == .hexadecimal {
      var v: UInt64 = 0
      return scanHexInt64(&v) ? Int64(truncatingIfNeeded: v) : nil
    }
    var v: Int64 = 0
    return scanInt64(&v) ? v : nil
  }
  public func scanUInt64(representation: NumberRepresentation = .decimal) -> UInt64? {
    var v: UInt64 = 0
    if representation == .hexadecimal { return scanHexInt64(&v) ? v : nil }
    return scanUnsignedLongLong(&v) ? v : nil
  }
  public func scanInt32(representation: NumberRepresentation = .decimal) -> Int32? {
    return scanInt64(representation: representation).map { Int32(truncatingIfNeeded: $0) }
  }
  public func scanDouble(representation: NumberRepresentation = .decimal) -> Double? {
    var v = 0.0
    return scanDouble(&v) ? v : nil
  }
  public func scanFloat(representation: NumberRepresentation = .decimal) -> Float? {
    var v: Float = 0
    return scanFloat(&v) ? v : nil
  }
  public func scanDecimal() -> Decimal? {
    var v = Decimal()
    return scanDecimal(&v) ? v : nil
  }
  public func scanString(_ searchString: String) -> String? {
    var out: NSString?
    return scanString(searchString, into: &out) ? out.map { $0 as String } : nil
  }
  public func scanUpToString(_ substring: String) -> String? {
    var out: NSString?
    return scanUpTo(substring, into: &out) ? out.map { $0 as String } : nil
  }
  /// The UTF-16 offset after the characters to be skipped.
  internal func _skippedOffset() -> Int {
    let u = Array(string.utf16)
    var i = scanLocation
    if let skip = charactersToBeSkipped {
      while i < u.count && skip.characterIsMember(u[i]) { i += 1 }
    }
    return i
  }
  /// Scalars from the current position (after skipping) while `keep` says
  /// so; nil when there are none.
  internal func _scanScalars(while keep: (Unicode.Scalar) -> Bool) -> String? {
    let s = string
    let start = _skippedOffset()
    let u = s.utf16
    guard let from = u.index(u.startIndex, offsetBy: start, limitedBy: u.endIndex)?.samePosition(in: s.unicodeScalars)
    else { return nil }
    var end = from
    let scalars = s.unicodeScalars
    while end < scalars.endIndex && keep(scalars[end]) { end = scalars.index(after: end) }
    if end == from { return nil }
    scanLocation = u.distance(from: u.startIndex, to: end)
    var out = ""
    out.unicodeScalars.append(contentsOf: scalars[from..<end])
    return out
  }
  public func scanCharacters(from set: CharacterSet) -> String? {
    return _scanScalars { set.contains($0) }
  }
  public func scanUpToCharacters(from set: CharacterSet) -> String? {
    return _scanScalars { !set.contains($0) }
  }
  /// The next character (after skipping), whatever it is.
  public func scanCharacter() -> Character? {
    scanLocation = _skippedOffset()
    let idx = currentIndex
    guard idx < string.endIndex else { return nil }
    let c = string[idx]
    currentIndex = string.index(after: idx)
    return c
  }
}
