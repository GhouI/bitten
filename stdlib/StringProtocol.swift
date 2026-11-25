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
