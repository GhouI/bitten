// Text output: the stream protocols and the description protocols.

public protocol TextOutputStream {
  mutating func _lock()
  mutating func _unlock()
  mutating func write(_ string: String)
  mutating func _writeASCII(_ buffer: UnsafeBufferPointer<UInt8>)
}

extension TextOutputStream {
  public mutating func _lock() {}
  public mutating func _unlock() {}
  public mutating func _writeASCII(_ buffer: UnsafeBufferPointer<UInt8>) {
    write(String._uncheckedFromUTF8(buffer, isASCII: true))
  }
}

public protocol TextOutputStreamable {
  func write<Target: TextOutputStream>(to target: inout Target)
}

public protocol CustomStringConvertible {
  var description: String { get }
}

public protocol LosslessStringConvertible: CustomStringConvertible {
  init?(_ description: String)
}

public protocol CustomDebugStringConvertible {
  var debugDescription: String { get }
}

extension String: TextOutputStream {
  public mutating func write(_ other: String) { append(other) }

  public mutating func _writeASCII(_ buffer: UnsafeBufferPointer<UInt8>) {
    _guts.append(utf8: buffer, isASCII: true)
  }
}

extension String: TextOutputStreamable {
  @inlinable
  public func write<Target: TextOutputStream>(to target: inout Target) {
    target.write(self)
  }
}

extension String: CustomStringConvertible, LosslessStringConvertible {
  @inlinable
  public var description: String { return self }

  @inlinable
  public init(_ description: String) { self = description }
}

/// Standard output, written with write(2).
internal struct _Stdout: TextOutputStream {
  internal init() {}
  internal mutating func write(_ string: String) {
    if string.isEmpty { return }
    string._guts.withFastUTF8 { b in
      var p = b.baseAddress._unsafelyUnwrappedUnchecked
      var n = b.count
      while n > 0 {
        let k = _bitten_write(1, p._rawValue, n)
        if k <= 0 { return }
        p += k
        n -= k
      }
    }
  }
}
