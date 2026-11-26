// Localized strings: String.LocalizationValue (a localization key built
// from a literal with its interpolated arguments), LocalizedStringResource
// (a key with its table, locale and bundle, resolved later) and
// String(localized:). A key is the literal with each interpolation replaced
// by its format specifier ("%@" for strings, "%lld" for Int...), as Apple
// builds them, so the key matches the program's .strings tables. Resolving
// looks the key up in the bundle's table, then puts the arguments into the
// localized format; a missing key resolves to its own format.

/// A value that can sit in a localized format with a printf specifier.
public protocol _FormatSpecifiable: Equatable {
  associatedtype _Arg: CVarArg
  var _arg: _Arg { get }
  var _specifier: String { get }
}

extension Int: _FormatSpecifiable {
  public var _arg: Int { return self }
  public var _specifier: String { return "%lld" }
}
extension Int8: _FormatSpecifiable {
  public var _arg: Int32 { return Int32(self) }
  public var _specifier: String { return "%d" }
}
extension Int16: _FormatSpecifiable {
  public var _arg: Int32 { return Int32(self) }
  public var _specifier: String { return "%d" }
}
extension Int32: _FormatSpecifiable {
  public var _arg: Int32 { return self }
  public var _specifier: String { return "%d" }
}
extension Int64: _FormatSpecifiable {
  public var _arg: Int64 { return self }
  public var _specifier: String { return "%lld" }
}
extension UInt: _FormatSpecifiable {
  public var _arg: UInt { return self }
  public var _specifier: String { return "%llu" }
}
extension UInt8: _FormatSpecifiable {
  public var _arg: UInt32 { return UInt32(self) }
  public var _specifier: String { return "%u" }
}
extension UInt16: _FormatSpecifiable {
  public var _arg: UInt32 { return UInt32(self) }
  public var _specifier: String { return "%u" }
}
extension UInt32: _FormatSpecifiable {
  public var _arg: UInt32 { return self }
  public var _specifier: String { return "%u" }
}
extension UInt64: _FormatSpecifiable {
  public var _arg: UInt64 { return self }
  public var _specifier: String { return "%llu" }
}
extension Float: _FormatSpecifiable {
  public var _arg: Double { return Double(self) }
  public var _specifier: String { return "%f" }
}
extension Double: _FormatSpecifiable {
  public var _arg: Double { return self }
  public var _specifier: String { return "%lf" }
}

extension String {
  public struct LocalizationValue: Equatable, Hashable, ExpressibleByStringInterpolation, Sendable,
                                   CustomStringConvertible {
    /// The key: the literal with format specifiers where values went.
    internal var _key: String
    internal var _arguments: [_LocalizationArgument]

    public init(_ value: String) {
      _key = value.replacingPercents()
      _arguments = []
    }
    public init(stringLiteral value: String) {
      _key = value.replacingPercents()
      _arguments = []
    }
    public init(stringInterpolation: StringInterpolation) {
      _key = stringInterpolation._key
      _arguments = stringInterpolation._arguments
    }

    public var description: String { return _format(_key) }

    /// The arguments put into a (localized) format.
    internal func _format(_ format: String) -> String {
      return _LocalizationArgument.format(format, _arguments)
    }

    public static func == (a: LocalizationValue, b: LocalizationValue) -> Bool {
      return a._key == b._key && a._arguments == b._arguments
    }
    public func hash(into h: inout Hasher) {
      h.combine(_key)
      h.combine(_arguments)
    }

    public enum Placeholder: Hashable, Sendable {
      case int, uint, float, double, object
      internal var _specifier: String {
        switch self {
        case .int: return "%lld"
        case .uint: return "%llu"
        case .float: return "%f"
        case .double: return "%lf"
        case .object: return "%@"
        }
      }
    }

    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
      internal var _key = ""
      internal var _arguments: [_LocalizationArgument] = []

      public init(literalCapacity: Int, interpolationCount: Int) {
        _key.reserveCapacity(literalCapacity + interpolationCount * 2)
      }
      public mutating func appendLiteral(_ literal: String) {
        _key += literal.replacingPercents()
      }
      public mutating func appendInterpolation(_ string: String) {
        _key += "%@"
        _arguments.append(.string(string))
      }
      public mutating func appendInterpolation<T: _FormatSpecifiable>(_ value: T) {
        _key += value._specifier
        _arguments.append(.value(String(describing: value), value._arg))
      }
      public mutating func appendInterpolation<T: _FormatSpecifiable>(_ value: T, specifier: String) {
        _key += specifier
        _arguments.append(.value(String(describing: value), value._arg))
      }
      public mutating func appendInterpolation(placeholder: Placeholder, specifier: String) {
        _key += specifier
        _arguments.append(.placeholder)
      }
      public mutating func appendInterpolation<T: NSObject>(_ object: T) {
        _key += "%@"
        _arguments.append(.string(object.description))
      }
    }
  }

  /// The resource resolved in its bundle, table and locale.
  public init(localized resource: LocalizedStringResource) {
    self = resource._resolved()
  }

  public init(localized keyAndValue: String.LocalizationValue, table: String? = nil, bundle: Bundle? = nil,
              locale: Locale = .current, comment: StaticString? = nil) {
    self = _localize(keyAndValue._key, default: keyAndValue._key, keyAndValue, table: table,
                     bundle: bundle ?? Bundle.main)
  }

  public init(localized key: StaticString, defaultValue: String.LocalizationValue, table: String? = nil,
              bundle: Bundle? = nil, locale: Locale = .current, comment: StaticString? = nil) {
    self = _localize(key.description, default: defaultValue._key, defaultValue, table: table,
                     bundle: bundle ?? Bundle.main)
  }

  /// "%" in a literal is written "%%" in the key.
  fileprivate func replacingPercents() -> String {
    guard contains("%") else { return self }
    var out = ""
    for c in self { out += c == "%" ? "%%" : String(c) }
    return out
  }
}

/// One interpolated value: its text (strings, objects) or its printf
/// argument (numbers), kept with its description for equality.
internal enum _LocalizationArgument: Hashable, @unchecked Sendable {
  case string(String)
  case value(String, CVarArg)
  case placeholder

  static func == (a: _LocalizationArgument, b: _LocalizationArgument) -> Bool {
    switch (a, b) {
    case let (.string(x), .string(y)): return x == y
    case let (.value(x, _), .value(y, _)): return x == y
    case (.placeholder, .placeholder): return true
    default: return false
    }
  }
  func hash(into h: inout Hasher) {
    switch self {
    case let .string(s): h.combine(0); h.combine(s)
    case let .value(s, _): h.combine(1); h.combine(s)
    case .placeholder: h.combine(2)
    }
  }

  /// A printf-style format with these arguments: each specifier (or
  /// positional "%n$" one) takes the next argument; "%@" takes text,
  /// numeric specifiers their value.
  static func format(_ format: String, _ args: [_LocalizationArgument]) -> String {
    var out = ""
    var next = 0
    var chars = Array(format)
    var i = 0
    while i < chars.count {
      let c = chars[i]
      guard c == "%", i + 1 < chars.count else { out.append(c); i += 1; continue }
      if chars[i + 1] == "%" { out.append("%"); i += 2; continue }
      // Collect the specifier: flags, width, precision, length, conversion.
      var j = i + 1
      var position: Int? = nil
      var digits = ""
      while j < chars.count, chars[j].isNumber { digits.append(chars[j]); j += 1 }
      if j < chars.count, chars[j] == "$", let p = Int(digits) { position = p - 1; j += 1 } else { j = i + 1 }
      var spec = "%"
      while j < chars.count {
        let s = chars[j]
        spec.append(s)
        j += 1
        if s.isLetter && !"hlqLzjt".contains(s) || s == "@" { break }
      }
      let index = position ?? next
      if position == nil { next += 1 }
      if index < args.count {
        switch args[index] {
        case let .string(text): out += text
        case let .value(text, arg): out += spec.hasSuffix("@") ? text : String(format: spec, arg)
        case .placeholder: out += spec
        }
      } else {
        out += spec
      }
      i = j
    }
    chars.removeAll()
    return out
  }
}

/// The localized format for a key (the default when the table has none)
/// with the value's arguments put in.
internal func _localize(_ key: String, default defaultFormat: String, _ value: String.LocalizationValue,
                        table: String?, bundle: Bundle) -> String {
  let format = bundle.localizedString(forKey: key, value: defaultFormat, table: table)
  return value._format(format)
}

public struct LocalizedStringResource: Equatable, Hashable, ExpressibleByStringInterpolation, Sendable,
                                       CustomStringConvertible, CustomDebugStringConvertible {
  public typealias StringInterpolation = String.LocalizationValue.StringInterpolation

  public enum BundleDescription: @unchecked Sendable, Hashable {
    case main
    case forClass(AnyClass)
    case atURL(URL)

    public static func == (a: BundleDescription, b: BundleDescription) -> Bool {
      switch (a, b) {
      case (.main, .main): return true
      case let (.forClass(x), .forClass(y)): return x == y
      case let (.atURL(x), .atURL(y)): return x == y
      default: return false
      }
    }
    public func hash(into h: inout Hasher) {
      switch self {
      case .main: h.combine(0)
      case let .forClass(c): h.combine(1); h.combine(ObjectIdentifier(c))
      case let .atURL(u): h.combine(2); h.combine(u)
      }
    }

    internal var _bundle: Bundle {
      switch self {
      case .main: return Bundle.main
      case let .forClass(c): return Bundle(for: c)
      case let .atURL(u): return Bundle(url: u) ?? Bundle.main
      }
    }
  }

  public var key: String
  public var defaultValue: String.LocalizationValue
  public var table: String?
  public var locale: Locale
  public var bundle: BundleDescription

  public init(_ keyAndValue: String.LocalizationValue, table: String? = nil, locale: Locale = .current,
              bundle: BundleDescription = .main, comment: StaticString? = nil) {
    self.key = keyAndValue._key
    self.defaultValue = keyAndValue
    self.table = table
    self.locale = locale
    self.bundle = bundle
  }
  public init(_ key: StaticString, defaultValue: String.LocalizationValue, table: String? = nil,
              locale: Locale = .current, bundle: BundleDescription = .main, comment: StaticString? = nil) {
    self.key = key.description
    self.defaultValue = defaultValue
    self.table = table
    self.locale = locale
    self.bundle = bundle
  }
  public init(stringLiteral value: String) {
    self.init(String.LocalizationValue(stringLiteral: value))
  }
  public init(stringInterpolation: String.LocalizationValue.StringInterpolation) {
    self.init(String.LocalizationValue(stringInterpolation: stringInterpolation))
  }

  internal func _resolved() -> String {
    return _localize(key, default: defaultValue._key, defaultValue, table: table, bundle: bundle._bundle)
  }

  public var description: String { return _resolved() }
  public var debugDescription: String { return "LocalizedStringResource(\(key.debugDescription))" }

  public static func == (a: LocalizedStringResource, b: LocalizedStringResource) -> Bool {
    return a.key == b.key && a.defaultValue == b.defaultValue && a.table == b.table && a.bundle == b.bundle &&
      a.locale.identifier == b.locale.identifier
  }
  public func hash(into h: inout Hasher) {
    h.combine(key)
    h.combine(table)
  }
}

public protocol CustomLocalizedStringResourceConvertible {
  var localizedStringResource: LocalizedStringResource { get }
}
