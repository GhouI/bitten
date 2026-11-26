// Unicode scalar properties (Unicode.Scalar.Properties, GeneralCategory,
// NumericType) and the Character properties built on them, from the
// General_Category, binary-property and numeric tables in UnicodeData.swift
// (tools/gen-unicode.py).

extension Unicode {
  public enum GeneralCategory: Sendable {
    case uppercaseLetter, lowercaseLetter, titlecaseLetter, modifierLetter, otherLetter
    case nonspacingMark, spacingMark, enclosingMark
    case decimalNumber, letterNumber, otherNumber
    case connectorPunctuation, dashPunctuation, openPunctuation, closePunctuation
    case initialPunctuation, finalPunctuation, otherPunctuation
    case mathSymbol, currencySymbol, modifierSymbol, otherSymbol
    case spaceSeparator, lineSeparator, paragraphSeparator
    case control, format, surrogate, privateUse, unassigned
  }

  public enum NumericType: Sendable {
    case decimal, digit, numeric
  }
}

extension Unicode.GeneralCategory: Equatable, Hashable {
  internal static let _all: [Unicode.GeneralCategory] = [
    .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
    .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .letterNumber, .otherNumber,
    .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
    .initialPunctuation, .finalPunctuation, .otherPunctuation,
    .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol,
    .spaceSeparator, .lineSeparator, .paragraphSeparator,
    .control, .format, .surrogate, .privateUse, .unassigned]

  internal init(_code: Int) {
    self = _code >= 0 && _code < 30 ? Unicode.GeneralCategory._all[_code] : .unassigned
  }
}

extension Unicode.NumericType: Equatable, Hashable {}

/// Bits of the binary-property table.
internal enum _UnicodeBinaryProperty {
  static let alphabetic: UInt8 = 1, lowercase: UInt8 = 2, uppercase: UInt8 = 4, whiteSpace: UInt8 = 8,
             emoji: UInt8 = 16, emojiPresentation: UInt8 = 32, cased: UInt8 = 64, math: UInt8 = 128
}

extension Unicode.Scalar {
  public struct Properties: Sendable {
    internal var _scalar: Unicode.Scalar
    internal init(_ scalar: Unicode.Scalar) { _scalar = scalar }
  }
  public var properties: Properties { return Properties(self) }
}

extension Unicode.Scalar.Properties {
  internal var _value: UInt32 { return _scalar.value }
  /// General_Category in the order of Unicode.GeneralCategory's cases.
  internal var _cat: Int { return Int(_unicodeTables.generalCategory.lookup(_value)) }
  internal func _has(_ bit: UInt8) -> Bool { return _unicodeTables.binaryProperties.lookup(_value) & bit != 0 }

  public var generalCategory: Unicode.GeneralCategory { return Unicode.GeneralCategory(_code: _cat) }
  public var isAlphabetic: Bool { return _has(_UnicodeBinaryProperty.alphabetic) }
  public var isLowercase: Bool { return _has(_UnicodeBinaryProperty.lowercase) }
  public var isUppercase: Bool { return _has(_UnicodeBinaryProperty.uppercase) }
  public var isWhitespace: Bool { return _has(_UnicodeBinaryProperty.whiteSpace) }
  public var isEmoji: Bool { return _has(_UnicodeBinaryProperty.emoji) }
  public var isEmojiPresentation: Bool { return _has(_UnicodeBinaryProperty.emojiPresentation) }
  public var isCased: Bool { return _has(_UnicodeBinaryProperty.cased) }
  public var isMath: Bool { return _has(_UnicodeBinaryProperty.math) }
  public var isDash: Bool { return _cat == 12 }
  public var isASCIIHexDigit: Bool {
    let v = _value
    return (v >= 48 && v <= 57) || (v >= 65 && v <= 70) || (v >= 97 && v <= 102)
  }
  public var isHexDigit: Bool {
    let v = _value
    return isASCIIHexDigit || (v >= 0xFF10 && v <= 0xFF19) || (v >= 0xFF21 && v <= 0xFF26)
      || (v >= 0xFF41 && v <= 0xFF46)
  }
  public var isNoncharacterCodePoint: Bool {
    let v = _value
    return (v >= 0xFDD0 && v <= 0xFDEF) || (v & 0xFFFE) == 0xFFFE
  }
  public var isEmojiModifier: Bool { return _value >= 0x1F3FB && _value <= 0x1F3FF }
  public var changesWhenLowercased: Bool { return lowercaseMapping != String(_scalar) }
  public var changesWhenUppercased: Bool { return uppercaseMapping != String(_scalar) }
  public var changesWhenCaseMapped: Bool { return changesWhenLowercased || changesWhenUppercased }

  public var numericType: Unicode.NumericType? {
    switch _unicodeTables.numeric.lookup(_value) & 3 {
    case 1: return .decimal
    case 2: return .digit
    case 3: return .numeric
    default: return nil
    }
  }
  /// The integer numeric value, when it is one of 0...62.
  internal var _integerValue: Int? {
    let v = Int(_unicodeTables.numeric.lookup(_value) >> 2)
    return v == 0 ? nil : v - 1
  }
  public var numericValue: Double? {
    guard numericType != nil else { return nil }
    return _integerValue.map(Double.init)
  }

  public var lowercaseMapping: String { return String(_scalar).lowercased() }
  public var uppercaseMapping: String { return String(_scalar).uppercased() }
  public var titlecaseMapping: String {
    var out = ""
    _appendCaseMapped(_value, upper: true, to: &out)
    return out
  }
}

// MARK: - Character

extension Character {
  internal var _firstScalar: Unicode.Scalar { return unicodeScalars.first! }

  public var isASCIIHexDigit: Bool { return _isSingleScalar && _firstScalar.properties.isASCIIHexDigit }
  public var isLetter: Bool { return _firstScalar.properties.isAlphabetic }
  public var isNumber: Bool { return _firstScalar.properties.numericType != nil }
  public var isWholeNumber: Bool { return wholeNumberValue != nil }
  public var isWhitespace: Bool { return _firstScalar.properties.isWhitespace }
  public var isNewline: Bool {
    switch _firstScalar.value {
    case 0x0A...0x0D, 0x85, 0x2028, 0x2029: return true
    default: return false
    }
  }
  public var isPunctuation: Bool {
    let c = _firstScalar.properties._cat
    return c >= 11 && c <= 17
  }
  public var isSymbol: Bool {
    let c = _firstScalar.properties._cat
    return c >= 18 && c <= 21
  }
  public var isMathSymbol: Bool { return _firstScalar.properties.isMath }
  public var isCurrencySymbol: Bool { return _firstScalar.properties._cat == 19 }
  public var isCased: Bool { return unicodeScalars.contains { $0.properties.isCased } }
  public var _isUppercased: Bool { return String(self) == String(self).uppercased() }
  public var _isLowercased: Bool { return String(self) == String(self).lowercased() }
  public var isUppercase: Bool {
    if _isSingleScalar && _firstScalar.properties.isUppercase { return true }
    return _isUppercased && isCased
  }
  public var isLowercase: Bool {
    if _isSingleScalar && _firstScalar.properties.isLowercase { return true }
    return _isLowercased && isCased
  }
  public var isHexDigit: Bool { return hexDigitValue != nil }
  public var hexDigitValue: Int? {
    guard _isSingleScalar else { return nil }
    let v = _firstScalar.value
    switch v {
    case 48...57: return Int(v - 48)
    case 65...70: return Int(v - 55)
    case 97...102: return Int(v - 87)
    case 0xFF10...0xFF19: return Int(v - 0xFF10)
    case 0xFF21...0xFF26: return Int(v - 0xFF21 + 10)
    case 0xFF41...0xFF46: return Int(v - 0xFF41 + 10)
    default: return nil
    }
  }
  public var wholeNumberValue: Int? {
    guard _isSingleScalar, _firstScalar.properties.numericType != nil else { return nil }
    return _firstScalar.properties._integerValue
  }
}
