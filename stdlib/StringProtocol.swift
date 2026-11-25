// StringProtocol: what String and Substring share. Apple's protocol is
// resilient, so its requirements can be added to over time; these are the
// ones the rest of the library uses so far.

public protocol StringProtocol
  : BidirectionalCollection,
    TextOutputStream, TextOutputStreamable,
    LosslessStringConvertible, ExpressibleByStringInterpolation,
    Hashable, Comparable
  where Element == Character, Index == String.Index,
        StringInterpolation == DefaultStringInterpolation
{
  associatedtype UTF8View: Collection
  where UTF8View.Element == UInt8, UTF8View.Index == String.Index
  associatedtype UTF16View: BidirectionalCollection
  where UTF16View.Element == UInt16, UTF16View.Index == String.Index
  associatedtype UnicodeScalarView: BidirectionalCollection
  where UnicodeScalarView.Element == Unicode.Scalar, UnicodeScalarView.Index == String.Index

  var utf8: UTF8View { get }
  var utf16: UTF16View { get }
  var unicodeScalars: UnicodeScalarView { get }

  func hasPrefix(_ prefix: String) -> Bool
  func hasSuffix(_ suffix: String) -> Bool
  func lowercased() -> String
  func uppercased() -> String

  init(cString nullTerminatedUTF8: UnsafePointer<CChar>)
  func withCString<Result>(_ body: (UnsafePointer<CChar>) throws -> Result) rethrows -> Result
}

extension String: StringProtocol {}
extension Substring: StringProtocol {}

extension String {
  /// The text of any String or Substring.
  public init<S: StringProtocol>(_ other: S) {
    self.init()
    other.write(to: &self)
  }
}

extension BidirectionalCollection where Element == String {
  /// The strings, one after the other, with `separator` between them.
  public func joined(separator: String = "") -> String {
    var result = ""
    var first = true
    for e in self {
      if first {
        first = false
      } else {
        result += separator
      }
      result += e
    }
    return result
  }
}

// Substring search. (On Apple's platforms these come with the string
// processing library and Foundation; programs expect them on strings.)
extension StringProtocol {
  public func contains<T: StringProtocol>(_ other: T) -> Bool {
    return _firstRange(of: other) != nil
  }
  public func range<T: StringProtocol>(of other: T) -> Range<Index>? {
    return _firstRange(of: other)
  }
  internal func _firstRange<T: StringProtocol>(of other: T) -> Range<Index>? {
    let needle = Array(other.utf8)
    if needle.isEmpty { return startIndex..<startIndex }
    let hay = Array(self.utf8)
    guard hay.count >= needle.count else { return nil }
    var i = 0
    while i <= hay.count - needle.count {
      var j = 0
      while j < needle.count && hay[i + j] == needle[j] { j += 1 }
      if j == needle.count {
        let lo = utf8.index(utf8.startIndex, offsetBy: i)
        let hi = utf8.index(lo, offsetBy: needle.count)
        return lo..<hi
      }
      i += 1
    }
    return nil
  }
}

// ---- switch over strings ----------------------------------------------------------
// `switch s { case "a": ... }` and String-backed enums' `init(rawValue:)`
// lower to these (found by the compiler through their semantics attributes).

@frozen public struct _OpaqueStringSwitchCache {
  internal var a: Builtin.Word
  internal var b: Builtin.Word
}

@_semantics("findStringSwitchCase")
public func _findStringSwitchCase(cases: [StaticString], string: String) -> Int {
  let s = Array(string.utf8)
  var i = 0
  while i < cases.count {
    let c = cases[i]
    if c.utf8CodeUnitCount == s.count {
      var same = true
      var j = 0
      while same && j < s.count {
        same = c.utf8Start[j] == s[j]
        j += 1
      }
      if same { return i }
    }
    i += 1
  }
  return -1
}

@_semantics("findStringSwitchCaseWithCache")
public func _findStringSwitchCaseWithCache(cases: [StaticString], string: String,
                                           cache: inout _OpaqueStringSwitchCache) -> Int {
  return _findStringSwitchCase(cases: cases, string: string)
}
