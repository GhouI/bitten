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
  /// Title case: upper case but for the letters whose title form differs
  /// (digraphs, ligatures, Greek letters with a subscript iota).
  public var titlecaseMapping: String {
    if let t = _titlecaseSpecial(_value) { return t }
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

/// Unicode's title case where it isn't the upper case (UnicodeData's
/// titlecase column and SpecialCasing.txt's title column).
internal func _titlecaseSpecial(_ v: UInt32) -> String? {
  func str(_ scalars: UInt32...) -> String {
    var s = ""
    for c in scalars { s.unicodeScalars.append(Unicode.Scalar(c)!) }
    return s
  }
  switch v {
  case 0x01C4...0x01C6: return str(0x01C5)
  case 0x01C7...0x01C9: return str(0x01C8)
  case 0x01CA...0x01CC: return str(0x01CB)
  case 0x01F1...0x01F3: return str(0x01F2)
  case 0x00DF: return "Ss"
  case 0xFB00: return "Ff"
  case 0xFB01: return "Fi"
  case 0xFB02: return "Fl"
  case 0xFB03: return "Ffi"
  case 0xFB04: return "Ffl"
  case 0xFB05, 0xFB06: return "St"
  case 0x0149: return str(0x02BC, 0x004E)
  case 0x0587: return str(0x0535, 0x0582)
  case 0xFB13: return str(0x0544, 0x0576)
  case 0xFB14: return str(0x0544, 0x0565)
  case 0xFB15: return str(0x0544, 0x056B)
  case 0xFB16: return str(0x054E, 0x0576)
  case 0xFB17: return str(0x0544, 0x056D)
  case 0x1F80...0x1F87, 0x1F90...0x1F97, 0x1FA0...0x1FA7: return str(v + 8)
  case 0x1F88...0x1F8F, 0x1F98...0x1F9F, 0x1FA8...0x1FAF, 0x1FBC, 0x1FCC, 0x1FFC: return str(v)
  case 0x1FB3: return str(0x1FBC)
  case 0x1FC3: return str(0x1FCC)
  case 0x1FF3: return str(0x1FFC)
  case 0x1FB2: return str(0x1FBA, 0x0345)
  case 0x1FB4: return str(0x0386, 0x0345)
  case 0x1FC2: return str(0x1FCA, 0x0345)
  case 0x1FC4: return str(0x0389, 0x0345)
  case 0x1FF2: return str(0x1FFA, 0x0345)
  case 0x1FF4: return str(0x038F, 0x0345)
  case 0x1FB7: return str(0x0391, 0x0342, 0x0345)
  case 0x1FC7: return str(0x0397, 0x0342, 0x0345)
  case 0x1FF7: return str(0x03A9, 0x0342, 0x0345)
  default: return nil
  }
}
