// Descriptions: how numbers, Bool, Optional, the collections, ranges and
// text show in print and interpolation, and the conversions back from text.
// Number formatting is done by the runtime entry points Apple's runtime has
// for it (swift_int64ToString, swift_float64ToString, ...).

// ---- integers -----------------------------------------------------------------

@_silgen_name("swift_int64ToString")
internal func _int64ToStringImpl(
  _ buffer: UnsafeMutablePointer<UInt8>, _ bufferLength: UInt,
  _ value: Int64, _ radix: Int64, _ uppercase: Bool) -> UInt64

@_silgen_name("swift_uint64ToString")
internal func _uint64ToStringImpl(
  _ buffer: UnsafeMutablePointer<UInt8>, _ bufferLength: UInt,
  _ value: UInt64, _ radix: Int64, _ uppercase: Bool) -> UInt64

internal func _int64ToString(_ value: Int64, radix: Int64 = 10, uppercase: Bool = false) -> String {
  return String(unsafeUninitializedCapacity: 65) { b in
    Int(_int64ToStringImpl(b.baseAddress._unsafelyUnwrappedUnchecked, 65, value, radix, uppercase))
  }
}

internal func _uint64ToString(_ value: UInt64, radix: Int64 = 10, uppercase: Bool = false) -> String {
  return String(unsafeUninitializedCapacity: 65) { b in
    Int(_uint64ToStringImpl(b.baseAddress._unsafelyUnwrappedUnchecked, 65, value, radix, uppercase))
  }
}

extension BinaryInteger {
  /// The value in decimal: "42", "-7".
  public var description: String {
    return _description(radix: 10, uppercase: false)
  }

  internal func _description(radix: Int, uppercase: Bool) -> String {
    _precondition(2 <= radix && radix <= 36, "Radix must be between 2 and 36")
    if bitWidth <= 64 {
      if Self.isSigned {
        return _int64ToString(Int64(truncatingIfNeeded: self), radix: Int64(radix), uppercase: uppercase)
      }
      return _uint64ToString(UInt64(truncatingIfNeeded: self), radix: Int64(radix), uppercase: uppercase)
    }
    if self == 0 { return "0" }
    // Wider than 64 bits: digits by repeated division, least significant first.
    var digits: [UInt8] = []
    var x = self.magnitude
    let r = Magnitude(radix)
    while x != 0 {
      let q = x / r
      let d = Int(truncatingIfNeeded: x - q * r)
      digits.append(UInt8(truncatingIfNeeded: d < 10 ? 48 + d : (uppercase ? 55 : 87) + d))
      x = q
    }
    if self < 0 { digits.append(45) }
    var s = String._createEmpty(withInitialCapacity: digits.count)
    var i = digits.count
    while i > 0 {
      i -= 1
      s.append(Character(Unicode.Scalar(digits[i])))
    }
    return s
  }
}

extension String {
  /// An integer's digits in a radix from 2 to 36: String(255, radix: 16) is "ff".
  public init<T: BinaryInteger>(_ value: T, radix: Int = 10, uppercase: Bool = false) {
    self = value._description(radix: radix, uppercase: uppercase)
  }
}

extension FixedWidthInteger {
  /// Parses an optional sign and decimal digits; nil if anything else is
  /// present or the value does not fit.
  public init?(_ description: String) {
    self.init(_parsing: description, radix: 10)
  }

  internal init?(_parsing text: String, radix: Int) {
    var it = text.utf8.makeIterator()
    guard var c = it.next() else { return nil }
    var negative = false
    if c == 45 || c == 43 {          // - +
      negative = c == 45
      guard let n = it.next() else { return nil }
      c = n
    }
    if negative && !Self.isSigned {
      // "-0" is the only negative text an unsigned type accepts.
      var allZero = c == 48
      while let n = it.next() { if n != 48 { allZero = false } }
      if allZero { self = 0; return }
      return nil
    }
    var result: Self = 0
    let r = Self(truncatingIfNeeded: radix)
    while true {
      var d: Int
      switch c {
      case 48...57: d = Int(c) - 48
      case 97...122: d = Int(c) - 87
      case 65...90: d = Int(c) - 55
      default: return nil
      }
      if d >= radix { return nil }
      let (m, o1) = result.multipliedReportingOverflow(by: r)
      let digit = Self(truncatingIfNeeded: d)
      let (s, o2) = negative ? m.subtractingReportingOverflow(digit) : m.addingReportingOverflow(digit)
      if o1 || o2 { return nil }
      result = s
      guard let n = it.next() else { break }
      c = n
    }
    self = result
  }
}

// ---- floating point -----------------------------------------------------------

@_silgen_name("swift_float32ToString")
internal func _float32ToStringImpl(
  _ buffer: UnsafeMutablePointer<UInt8>, _ bufferLength: UInt, _ value: Float, _ debug: Bool) -> UInt64

@_silgen_name("swift_float64ToString")
internal func _float64ToStringImpl(
  _ buffer: UnsafeMutablePointer<UInt8>, _ bufferLength: UInt, _ value: Double, _ debug: Bool) -> UInt64

@_silgen_name("swift_float80ToString")
internal func _float80ToStringImpl(
  _ buffer: UnsafeMutablePointer<UInt8>, _ bufferLength: UInt, _ value: Float80, _ debug: Bool) -> UInt64

@_silgen_name("_swift_stdlib_strtof_clocale")
internal func _swift_stdlib_strtof_clocale(
  _ nptr: UnsafePointer<CChar>, _ outResult: UnsafeMutablePointer<Float>) -> UnsafePointer<CChar>?

@_silgen_name("_swift_stdlib_strtod_clocale")
internal func _swift_stdlib_strtod_clocale(
  _ nptr: UnsafePointer<CChar>, _ outResult: UnsafeMutablePointer<Double>) -> UnsafePointer<CChar>?

@_silgen_name("_swift_stdlib_strtold_clocale")
internal func _swift_stdlib_strtold_clocale(
  _ nptr: UnsafePointer<CChar>, _ outResult: UnsafeMutablePointer<Float80>) -> UnsafePointer<CChar>?

/// Parses the whole of `text` with a C-locale strtod-like function.
internal func _parseFloat<F>(
  _ text: String, _ zero: F,
  _ parse: (UnsafePointer<CChar>, UnsafeMutablePointer<F>) -> UnsafePointer<CChar>?
) -> F? {
  var value = zero
  let ok: Bool = text.withCString { p in
    guard let end = parse(p, &value) else { return false }
    return end.pointee == 0 && end != p
  }
  return ok ? value : nil
}

extension Float: CustomStringConvertible, CustomDebugStringConvertible, TextOutputStreamable,
                 LosslessStringConvertible {
  /// The shortest text that reads back as this value: "0.1", "1e+10", "nan".
  public var description: String {
    return String(unsafeUninitializedCapacity: 32) { b in
      Int(_float32ToStringImpl(b.baseAddress._unsafelyUnwrappedUnchecked, 32, self, false))
    }
  }

  /// As description, with the sign and payload of NaNs ("-nan", "snan").
  public var debugDescription: String {
    return String(unsafeUninitializedCapacity: 32) { b in
      Int(_float32ToStringImpl(b.baseAddress._unsafelyUnwrappedUnchecked, 32, self, true))
    }
  }

  public func write<Target: TextOutputStream>(to target: inout Target) {
    target.write(description)
  }

  /// Parses decimal or hexadecimal text, "inf", "nan"; nil unless all of it is a number.
  public init?(_ text: String) {
    guard let v = _parseFloat(text, Float(0), _swift_stdlib_strtof_clocale) else { return nil }
    self = v
  }

  public init?(_ text: Substring) {
    self.init(String(text))
  }
}

extension Double: CustomStringConvertible, CustomDebugStringConvertible, TextOutputStreamable,
                  LosslessStringConvertible {
  /// The shortest text that reads back as this value: "0.1", "1e+16", "nan".
  public var description: String {
    return String(unsafeUninitializedCapacity: 32) { b in
      Int(_float64ToStringImpl(b.baseAddress._unsafelyUnwrappedUnchecked, 32, self, false))
    }
  }

  /// As description, with the sign and payload of NaNs ("-nan", "snan").
  public var debugDescription: String {
    return String(unsafeUninitializedCapacity: 48) { b in
      Int(_float64ToStringImpl(b.baseAddress._unsafelyUnwrappedUnchecked, 48, self, true))
    }
  }

  public func write<Target: TextOutputStream>(to target: inout Target) {
    target.write(description)
  }

  /// Parses decimal or hexadecimal text, "inf", "nan"; nil unless all of it is a number.
  public init?(_ text: String) {
    guard let v = _parseFloat(text, Double(0), _swift_stdlib_strtod_clocale) else { return nil }
    self = v
  }

  public init?(_ text: Substring) {
    self.init(String(text))
  }
}

extension Float80: CustomStringConvertible, CustomDebugStringConvertible, TextOutputStreamable,
                   LosslessStringConvertible {
  public var description: String {
    return String(unsafeUninitializedCapacity: 48) { b in
      Int(_float80ToStringImpl(b.baseAddress._unsafelyUnwrappedUnchecked, 48, self, false))
    }
  }

  public var debugDescription: String {
    return String(unsafeUninitializedCapacity: 64) { b in
      Int(_float80ToStringImpl(b.baseAddress._unsafelyUnwrappedUnchecked, 64, self, true))
    }
  }

  public func write<Target: TextOutputStream>(to target: inout Target) {
    target.write(description)
  }

  public init?(_ text: String) {
    guard let v = _parseFloat(text, Float80(0), _swift_stdlib_strtold_clocale) else { return nil }
    self = v
  }

  public init?(_ text: Substring) {
    self.init(String(text))
  }
}

// ---- Bool -----------------------------------------------------------------------

extension Bool: CustomStringConvertible, LosslessStringConvertible {
  @inlinable
  public var description: String {
    return self ? "true" : "false"
  }

  /// "true" or "false", nothing else.
  @inlinable
  public init?(_ description: String) {
    if description == "true" {
      self = true
    } else if description == "false" {
      self = false
    } else {
      return nil
    }
  }
}

// ---- Optional -------------------------------------------------------------------

extension Optional: CustomDebugStringConvertible {
  /// "Optional(" + the wrapped value's debug text + ")", or "nil".
  public var debugDescription: String {
    switch self {
    case .some(let value):
      var result = "Optional("
      _debugPrint_unlocked(value, &result)
      result += ")"
      return result
    case .none:
      return "nil"
    }
  }
}

// ---- collections ----------------------------------------------------------------

/// "[a, b, c]" with each element's debug text; `typeName` prefixes it (for
/// ContiguousArray and ArraySlice debugDescription).
internal func _makeCollectionDescription<C: Collection>(
  for items: C, withTypeName typeName: String? = nil
) -> String {
  var result = ""
  if let type = typeName {
    result += type
    result += "("
  }
  result += "["
  var first = true
  for item in items {
    if first {
      first = false
    } else {
      result += ", "
    }
    _debugPrint_unlocked(item, &result)
  }
  result += "]"
  if typeName != nil { result += ")" }
  return result
}

extension Array: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    return _makeCollectionDescription(for: self)
  }

  public var debugDescription: String {
    return _makeCollectionDescription(for: self)
  }
}

extension ContiguousArray: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    return _makeCollectionDescription(for: self)
  }

  public var debugDescription: String {
    return _makeCollectionDescription(for: self, withTypeName: "ContiguousArray")
  }
}

extension ArraySlice: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    return _makeCollectionDescription(for: self)
  }

  public var debugDescription: String {
    return _makeCollectionDescription(for: self, withTypeName: "ArraySlice")
  }
}

extension Set: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    return _makeCollectionDescription(for: self)
  }

  public var debugDescription: String {
    return _makeCollectionDescription(for: self, withTypeName: "Set")
  }
}

extension Dictionary: CustomStringConvertible, CustomDebugStringConvertible {
  internal func _makeDescription() -> String {
    if isEmpty { return "[:]" }
    var result = "["
    var first = true
    for (k, v) in self {
      if first {
        first = false
      } else {
        result += ", "
      }
      _debugPrint_unlocked(k, &result)
      result += ": "
      _debugPrint_unlocked(v, &result)
    }
    result += "]"
    return result
  }

  /// "[key: value, ...]" with each key's and value's debug text; "[:]" if empty.
  public var description: String {
    return _makeDescription()
  }

  public var debugDescription: String {
    return _makeDescription()
  }
}

// ---- ranges ---------------------------------------------------------------------

extension Range: CustomStringConvertible, CustomDebugStringConvertible {
  /// "lower..<upper"
  public var description: String {
    return "\(lowerBound)..<\(upperBound)"
  }

  public var debugDescription: String {
    return "Range(\(String(reflecting: lowerBound))..<\(String(reflecting: upperBound)))"
  }
}

extension ClosedRange: CustomStringConvertible, CustomDebugStringConvertible {
  /// "lower...upper"
  public var description: String {
    return "\(lowerBound)...\(upperBound)"
  }

  public var debugDescription: String {
    return "ClosedRange(\(String(reflecting: lowerBound))...\(String(reflecting: upperBound)))"
  }
}

// ---- text -----------------------------------------------------------------------

extension Unicode.Scalar {
  /// The scalar as Swift source would write it inside a string literal:
  /// \0 \t \n \r \" \' \\ escaped, other control characters (and, when
  /// `asASCII`, everything outside printable ASCII) as \u{X}.
  public func escaped(asASCII forceASCII: Bool) -> String {
    switch value {
    case 0: return "\\0"
    case 9: return "\\t"
    case 10: return "\\n"
    case 13: return "\\r"
    case 0x22: return "\\\""
    case 0x27: return "\\'"
    case 0x5C: return "\\\\"
    case 0x20..<0x7F: return String(Character(self))
    default:
      if !forceASCII && value > 0x9F { return String(Character(self)) }
      return "\\u{" + _uint64ToString(UInt64(value), radix: 16, uppercase: true) + "}"
    }
  }
}

extension Unicode.Scalar: CustomStringConvertible, CustomDebugStringConvertible, TextOutputStreamable {
  public var description: String {
    return String(Character(self))
  }

  /// "\"a\"" with the scalar escaped.
  public var debugDescription: String {
    return "\"" + escaped(asASCII: true) + "\""
  }

  public func write<Target: TextOutputStream>(to target: inout Target) {
    target.write(String(Character(self)))
  }
}

internal func _quotedDebugText<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
  var result = "\""
  for s in scalars {
    result += s.escaped(asASCII: false)
  }
  result += "\""
  return result
}

extension String: CustomDebugStringConvertible {
  /// The string quoted, as Swift source would write it: "\"a\\n\"".
  public var debugDescription: String {
    return _quotedDebugText(unicodeScalars)
  }
}

extension Substring: CustomDebugStringConvertible {
  public var debugDescription: String {
    return _quotedDebugText(unicodeScalars)
  }
}

extension Character: CustomDebugStringConvertible {
  public var debugDescription: String {
    return _quotedDebugText(unicodeScalars)
  }
}

extension StaticString: CustomStringConvertible, CustomDebugStringConvertible {
  /// The string's text.
  public var description: String {
    if !hasPointerRepresentation { return String(Character(unicodeScalar)) }
    return String._uncheckedFromUTF8(UnsafeBufferPointer(start: utf8Start, count: utf8CodeUnitCount))
  }

  public var debugDescription: String {
    return description.debugDescription
  }
}

extension AnyHashable: CustomStringConvertible, CustomDebugStringConvertible {
  /// The wrapped value's description.
  public var description: String {
    return String(describing: base)
  }

  public var debugDescription: String {
    return "AnyHashable(" + String(reflecting: base) + ")"
  }
}

// ---- joining --------------------------------------------------------------------

extension Sequence where Element: StringProtocol {
  /// The elements, one after the other, with `separator` between them.
  public func joined(separator: String = "") -> String {
    var result = ""
    var first = true
    for e in self {
      if first {
        first = false
      } else {
        result += separator
      }
      result += String(e)
    }
    return result
  }
}
