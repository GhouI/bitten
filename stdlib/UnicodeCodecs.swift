// The Unicode encodings as types (Unicode.UTF8/UTF16/UTF32 and their
// top-level aliases), String(decoding:as:), and parsing integers from text.

public protocol _UnicodeEncoding {
  associatedtype CodeUnit: UnsignedInteger & FixedWidthInteger
}
extension Unicode {
  public typealias Encoding = _UnicodeEncoding
  @frozen public enum UTF8: _UnicodeEncoding { public typealias CodeUnit = UInt8 }
  @frozen public enum UTF16: _UnicodeEncoding { public typealias CodeUnit = UInt16 }
  @frozen public enum UTF32: _UnicodeEncoding { public typealias CodeUnit = UInt32 }
  @frozen public enum ASCII: _UnicodeEncoding { public typealias CodeUnit = UInt8 }
}
public typealias UTF8 = Unicode.UTF8
public typealias UTF16 = Unicode.UTF16
public typealias UTF32 = Unicode.UTF32

extension String {
  /// Decodes code units, replacing invalid sequences with U+FFFD.
  public init<C: Collection, Encoding: Unicode.Encoding>(decoding codeUnits: C, as sourceEncoding: Encoding.Type)
  where C.Element == Encoding.CodeUnit {
    if Encoding.CodeUnit.bitWidth == 8 {
      // Bytes laid out in memory already (arrays, slices, Data): read in
      // place, without copying them one at a time first.
      if let direct = codeUnits.withContiguousStorageIfAvailable({ units -> String in
        let start = UnsafeRawPointer(units.baseAddress)?.assumingMemoryBound(to: UInt8.self)
        return String._fromUTF8Repairing(UnsafeBufferPointer(start: start, count: units.count)).result
      }) {
        self = direct
        return
      }
      let bytes = codeUnits.lazyMapToUInt8()
      self = bytes.withUnsafeBufferPointer { String._fromUTF8Repairing($0).result }
      return
    }
    // UTF-16 or UTF-32: decode scalars, transcode to UTF-8.
    var utf8: [UInt8] = []
    var it = codeUnits.makeIterator()
    var pending: UInt32? = nil
    func emit(_ v: UInt32) {
      let s = Unicode.Scalar(v) ?? Unicode.Scalar(UInt32(0xFFFD))!
      let x = s.value
      if x < 0x80 { utf8.append(UInt8(x)) }
      else if x < 0x800 { utf8.append(UInt8(0xC0 | (x >> 6))); utf8.append(UInt8(0x80 | (x & 0x3F))) }
      else if x < 0x10000 {
        utf8.append(UInt8(0xE0 | (x >> 12))); utf8.append(UInt8(0x80 | ((x >> 6) & 0x3F))); utf8.append(UInt8(0x80 | (x & 0x3F)))
      } else {
        utf8.append(UInt8(0xF0 | (x >> 18))); utf8.append(UInt8(0x80 | ((x >> 12) & 0x3F)))
        utf8.append(UInt8(0x80 | ((x >> 6) & 0x3F))); utf8.append(UInt8(0x80 | (x & 0x3F)))
      }
    }
    while let unit = it.next() {
      let u = UInt32(truncatingIfNeeded: unit)
      if Encoding.CodeUnit.bitWidth == 16 {
        if let hi = pending {
          pending = nil
          if u >= 0xDC00 && u < 0xE000 { emit(0x10000 + ((hi - 0xD800) << 10) + (u - 0xDC00)); continue }
          emit(0xFFFD)
        }
        if u >= 0xD800 && u < 0xDC00 { pending = u; continue }
        emit(u >= 0xDC00 && u < 0xE000 ? 0xFFFD : u)
      } else {
        emit(u)
      }
    }
    if pending != nil { emit(0xFFFD) }
    self = utf8.withUnsafeBufferPointer { String._fromUTF8Repairing($0).result }
  }
}

extension Collection where Element: FixedWidthInteger {
  internal func lazyMapToUInt8() -> [UInt8] {
    var out: [UInt8] = []
    out.reserveCapacity(count)
    for e in self { out.append(UInt8(truncatingIfNeeded: e)) }
    return out
  }
}

extension FixedWidthInteger {
  /// Parses an optional sign and digits in `radix` (2...36); nil on any
  /// other character, on an empty string, or on overflow.
  public init?<S: StringProtocol>(_ text: S, radix: Int = 10) {
    _precondition(2 <= radix && radix <= 36, "Radix not in range 2...36")
    var bytes = text.utf8[...]
    guard let first = bytes.first else { return nil }
    var negative = false
    if first == UInt8(ascii: "-") || first == UInt8(ascii: "+") {
      negative = first == UInt8(ascii: "-")
      bytes = bytes.dropFirst()
      if bytes.isEmpty { return nil }
    }
    var value: Self = 0
    let r = Self(radix)
    for b in bytes {
      let d: Int
      switch b {
      case UInt8(ascii: "0")...UInt8(ascii: "9"): d = Int(b) - 48
      case UInt8(ascii: "a")...UInt8(ascii: "z"): d = Int(b) - 87
      case UInt8(ascii: "A")...UInt8(ascii: "Z"): d = Int(b) - 55
      default: return nil
      }
      if d >= radix { return nil }
      let (m, o1) = value.multipliedReportingOverflow(by: r)
      if o1 { return nil }
      let (s, o2) = negative ? m.subtractingReportingOverflow(Self(d)) : m.addingReportingOverflow(Self(d))
      if o2 { return nil }
      value = s
    }
    self = value
  }
}
