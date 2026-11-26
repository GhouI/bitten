// Data: a byte buffer value. Programs inline much of Data, so the type and
// its pieces have Apple's declared shapes: Data is @frozen and holds a
// @frozen _Representation enum whose cases are small inline bytes (14 on
// 64-bit), a slice of a shared __DataStorage with 32-bit bounds, or one
// with a boxed Int range. Inlined code reaches __DataStorage only through
// its accessors, so the storage class itself is ours.
//
// Invariants shared with inlined code:
// - .inline: indices 0..<length.
// - .slice / .large: indices are the slice's range; index i lives at
//   storage._bytes + (i - storage._offset).

// MARK: - protocols

public protocol ContiguousBytes {
  func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R
}

public protocol DataProtocol: RandomAccessCollection where Element == UInt8, SubSequence: DataProtocol {
  associatedtype Regions: BidirectionalCollection
    where Regions.Element: DataProtocol & ContiguousBytes, Regions.Element.SubSequence: ContiguousBytes
  var regions: Regions { get }
  func firstRange<D: DataProtocol, R: RangeExpression>(of: D, in: R) -> Range<Index>? where R.Bound == Index
  func lastRange<D: DataProtocol, R: RangeExpression>(of: D, in: R) -> Range<Index>? where R.Bound == Index
  @discardableResult func copyBytes(to: UnsafeMutableRawBufferPointer) -> Int
  @discardableResult func copyBytes<DestinationType>(to: UnsafeMutableBufferPointer<DestinationType>) -> Int
  @discardableResult func copyBytes(to: UnsafeMutableRawBufferPointer, count: Int) -> Int
  @discardableResult func copyBytes<DestinationType>(to: UnsafeMutableBufferPointer<DestinationType>, count: Int) -> Int
  @discardableResult func copyBytes<R: RangeExpression>(to: UnsafeMutableRawBufferPointer, from: R) -> Int where R.Bound == Index
  @discardableResult func copyBytes<DestinationType, R: RangeExpression>(to: UnsafeMutableBufferPointer<DestinationType>, from: R) -> Int
    where R.Bound == Index
}

public protocol MutableDataProtocol: DataProtocol, MutableCollection, RangeReplaceableCollection {
  mutating func resetBytes<R: RangeExpression>(in range: R) where R.Bound == Index
}

extension DataProtocol {
  public func firstRange<D: DataProtocol>(of data: D) -> Range<Index>? {
    return firstRange(of: data, in: startIndex..<endIndex)
  }
  public func lastRange<D: DataProtocol>(of data: D) -> Range<Index>? {
    return lastRange(of: data, in: startIndex..<endIndex)
  }

  @discardableResult
  public func copyBytes(to ptr: UnsafeMutableRawBufferPointer) -> Int { return copyBytes(to: ptr, from: startIndex..<endIndex) }
  @discardableResult
  public func copyBytes<D>(to ptr: UnsafeMutableBufferPointer<D>) -> Int { return copyBytes(to: ptr, from: startIndex..<endIndex) }
  @discardableResult
  public func copyBytes(to ptr: UnsafeMutableRawBufferPointer, count: Int) -> Int {
    return copyBytes(to: ptr, from: startIndex..<index(startIndex, offsetBy: count))
  }
  @discardableResult
  public func copyBytes<D>(to ptr: UnsafeMutableBufferPointer<D>, count: Int) -> Int {
    return copyBytes(to: ptr, from: startIndex..<index(startIndex, offsetBy: count))
  }
  @discardableResult
  public func copyBytes<R: RangeExpression>(to ptr: UnsafeMutableRawBufferPointer, from range: R) -> Int where R.Bound == Index {
    precondition(ptr.baseAddress != nil || ptr.count == 0)
    let r = range.relative(to: self)
    var written = 0
    var i = r.lowerBound
    while i != r.upperBound && written < ptr.count {
      ptr[written] = self[i]
      written += 1
      i = index(after: i)
    }
    return written
  }
  @discardableResult
  public func copyBytes<D, R: RangeExpression>(to ptr: UnsafeMutableBufferPointer<D>, from range: R) -> Int where R.Bound == Index {
    return copyBytes(to: UnsafeMutableRawBufferPointer(start: ptr.baseAddress, count: ptr.count * MemoryLayout<D>.stride), from: range)
  }

  internal func _matches<D: DataProtocol>(_ data: D, at i: Index) -> Bool {
    var a = i
    var b = data.startIndex
    while b != data.endIndex {
      if a == endIndex || self[a] != data[b] { return false }
      a = index(after: a)
      b = data.index(after: b)
    }
    return true
  }

  public func firstRange<D: DataProtocol, R: RangeExpression>(of data: D, in range: R) -> Range<Index>? where R.Bound == Index {
    let r = range.relative(to: self)
    let n = data.count
    if n == 0 || distance(from: r.lowerBound, to: r.upperBound) < n { return nil }
    var i = r.lowerBound
    let last = index(r.upperBound, offsetBy: -n)
    while true {
      if _matches(data, at: i) { return i..<index(i, offsetBy: n) }
      if i == last { return nil }
      i = index(after: i)
    }
  }
  public func lastRange<D: DataProtocol, R: RangeExpression>(of data: D, in range: R) -> Range<Index>? where R.Bound == Index {
    let r = range.relative(to: self)
    let n = data.count
    if n == 0 || distance(from: r.lowerBound, to: r.upperBound) < n { return nil }
    var i = index(r.upperBound, offsetBy: -n)
    while true {
      if _matches(data, at: i) { return i..<index(i, offsetBy: n) }
      if i == r.lowerBound { return nil }
      i = index(before: i)
    }
  }
}

extension DataProtocol where Self: ContiguousBytes {
  public func copyBytes<D, R: RangeExpression>(to ptr: UnsafeMutableBufferPointer<D>, from range: R) where R.Bound == Index {
    _ = copyBytes(to: UnsafeMutableRawBufferPointer(start: ptr.baseAddress, count: ptr.count * MemoryLayout<D>.stride), from: range)
  }
}

extension MutableDataProtocol {
  public mutating func resetBytes<R: RangeExpression>(in range: R) where R.Bound == Index {
    let r = range.relative(to: self)
    var i = r.lowerBound
    while i != r.upperBound {
      self[i] = 0
      i = index(after: i)
    }
  }
}

// Conformances of the standard library's buffers.
extension UnsafeRawBufferPointer: DataProtocol {
  public var regions: CollectionOfOne<UnsafeRawBufferPointer> { return CollectionOfOne(self) }
}
extension UnsafeRawBufferPointer: ContiguousBytes {
  public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { return try body(self) }
}
extension UnsafeMutableRawBufferPointer: ContiguousBytes {
  public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    return try body(UnsafeRawBufferPointer(self))
  }
}
extension Array: ContiguousBytes where Element == UInt8 {}
extension ArraySlice: ContiguousBytes where Element == UInt8 {}
extension ContiguousArray: ContiguousBytes where Element == UInt8 {}
extension Array: DataProtocol where Element == UInt8 {
  public var regions: CollectionOfOne<Array<UInt8>> { return CollectionOfOne(self) }
}
extension ArraySlice: DataProtocol where Element == UInt8 {
  public var regions: CollectionOfOne<ArraySlice<UInt8>> { return CollectionOfOne(self) }
}
extension ContiguousArray: DataProtocol where Element == UInt8 {
  public var regions: CollectionOfOne<ContiguousArray<UInt8>> { return CollectionOfOne(self) }
}
extension Array: MutableDataProtocol where Element == UInt8 {}
extension ContiguousArray: MutableDataProtocol where Element == UInt8 {}
extension Slice: ContiguousBytes where Base: ContiguousBytes {
  public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    let offset = base.distance(from: base.startIndex, to: startIndex)
    let n = base.distance(from: startIndex, to: endIndex)
    return try base.withUnsafeBytes { try body(UnsafeRawBufferPointer(rebasing: $0[offset..<(offset + n)])) }
  }
}
extension Slice: DataProtocol where Base: DataProtocol {
  public typealias Regions = [Base.Regions.Element.SubSequence]
  public var regions: [Base.Regions.Element.SubSequence] {
    // The parts of each region of the base that fall inside this slice.
    var out: [Base.Regions.Element.SubSequence] = []
    var offset = 0
    let lo = base.distance(from: base.startIndex, to: startIndex)
    let hi = base.distance(from: base.startIndex, to: endIndex)
    for region in base.regions {
      let n = region.count
      let a = Swift.max(lo, offset), b = Swift.min(hi, offset + n)
      if a < b {
        let s = region.index(region.startIndex, offsetBy: a - offset)
        let e = region.index(region.startIndex, offsetBy: b - offset)
        out.append(region[s..<e])
      }
      offset += n
    }
    return out
  }
}

// MARK: - storage

@usableFromInline
internal final class __DataStorage: @unchecked Sendable {
  @usableFromInline var _bytes: UnsafeMutableRawPointer?
  @usableFromInline var _length: Int
  @usableFromInline var _capacity: Int
  @usableFromInline var _offset: Int
  @usableFromInline var _deallocator: ((UnsafeMutableRawPointer, Int) -> Void)?
  @usableFromInline var _needToZero: Bool

  @usableFromInline
  init(capacity: Int) {
    _capacity = Swift.max(capacity, 0)
    _bytes = _capacity > 0 ? malloc(_capacity) : nil
    _length = 0
    _offset = 0
    _deallocator = nil
    _needToZero = true
  }

  @usableFromInline
  init(length: Int) {
    _capacity = Swift.max(length, 0)
    _bytes = _capacity > 0 ? calloc(1, _capacity) : nil
    _length = Swift.max(length, 0)
    _offset = 0
    _deallocator = nil
    _needToZero = false
  }

  @usableFromInline
  init(bytes: UnsafeRawPointer?, length: Int) {
    _capacity = Swift.max(length, 0)
    _bytes = _capacity > 0 ? malloc(_capacity) : nil
    if let src = bytes, let dst = _bytes, length > 0 { memcpy(dst, src, length) }
    _length = Swift.max(length, 0)
    _offset = 0
    _deallocator = nil
    _needToZero = true
  }

  @usableFromInline
  init(bytes: UnsafeMutableRawPointer?, length: Int, copy: Bool,
       deallocator: ((UnsafeMutableRawPointer, Int) -> Void)?, offset: Int) {
    _offset = offset
    _length = length
    _needToZero = true
    if copy {
      _capacity = length
      _bytes = length > 0 ? malloc(length) : nil
      if let src = bytes, let dst = _bytes, length > 0 { memcpy(dst, src, length) }
      _deallocator = nil
      if let d = deallocator, let src = bytes { d(src, length) }
    } else {
      _capacity = length
      _bytes = bytes
      _deallocator = deallocator
    }
  }

  deinit {
    if let b = _bytes {
      if let d = _deallocator { d(b, _length) } else { free(b) }
    }
  }

  /// The bytes of `range` (in the storage's index space).
  internal func _withBytes<R>(in range: Range<Int>, _ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
    guard let b = _bytes, range.count > 0 else { return try body(UnsafeRawBufferPointer(start: nil, count: 0)) }
    return try body(UnsafeRawBufferPointer(start: b + (range.lowerBound - _offset), count: range.count))
  }

  /// A new storage holding a copy of `range`, indexed from range.lowerBound,
  /// with room for at least `capacity` bytes.
  internal func _copy(_ range: Range<Int>, capacity: Int) -> __DataStorage {
    let s = __DataStorage(capacity: Swift.max(capacity, range.count))
    if range.count > 0, let src = _bytes, let dst = s._bytes { memcpy(dst, src + (range.lowerBound - _offset), range.count) }
    s._length = range.count
    s._offset = range.lowerBound
    return s
  }

  /// Ensures room for `capacity` bytes; only for storage this code owns.
  internal func _grow(to capacity: Int) {
    if capacity <= _capacity { return }
    var newCap = Swift.max(_capacity * 2, 16)
    while newCap < capacity { newCap *= 2 }
    if _deallocator != nil {
      let nb = malloc(newCap)!
      if let old = _bytes, _length > 0 { memcpy(nb, old, _length) }
      if let old = _bytes, let d = _deallocator { d(old, _length) }
      _deallocator = nil
      _bytes = nb
    } else {
      _bytes = realloc(_bytes, newCap)
    }
    _capacity = newCap
  }
}

// MARK: - Data

@frozen
public struct Data: Equatable, Hashable, RandomAccessCollection, MutableCollection, RangeReplaceableCollection,
  MutableDataProtocol, ContiguousBytes, Sendable {
  public typealias Index = Int
  public typealias Indices = Range<Int>
  public typealias Element = UInt8
  public typealias SubSequence = Data
  public typealias Regions = CollectionOfOne<Data>

  @usableFromInline
  @frozen
  internal struct InlineData: Sendable {
    @usableFromInline
    internal typealias Buffer = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    @usableFromInline var bytes: Buffer
    @usableFromInline var length: UInt8

    internal static var capacity: Int { return MemoryLayout<Buffer>.size }

    internal init(_ buffer: UnsafeRawBufferPointer) {
      bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
      length = UInt8(buffer.count)
      if buffer.count > 0 {
        Swift.withUnsafeMutableBytes(of: &bytes) { dst in
          dst.baseAddress!.copyMemory(from: buffer.baseAddress!, byteCount: buffer.count)
        }
      }
    }
    internal init(count: Int) {
      bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
      length = UInt8(count)
    }
    internal func withBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
      var copy = bytes
      let n = Int(length)
      return try Swift.withUnsafeBytes(of: &copy) { try body(UnsafeRawBufferPointer(rebasing: $0[0..<n])) }
    }
  }

  @usableFromInline
  @frozen
  internal struct InlineSlice: Sendable {
    @usableFromInline internal typealias HalfInt = Int32
    @usableFromInline var slice: Range<HalfInt>
    @usableFromInline var storage: __DataStorage

    internal init(storage: __DataStorage, range: Range<Int>) {
      self.storage = storage
      slice = HalfInt(range.lowerBound)..<HalfInt(range.upperBound)
    }
    internal var range: Range<Int> { return Int(slice.lowerBound)..<Int(slice.upperBound) }
  }

  @usableFromInline
  internal final class RangeReference: @unchecked Sendable {
    @usableFromInline var range: Range<Int>
    @usableFromInline init(_ range: Range<Int>) { self.range = range }
  }

  @usableFromInline
  @frozen
  internal struct LargeSlice: Sendable {
    @usableFromInline var slice: RangeReference
    @usableFromInline var storage: __DataStorage

    internal init(storage: __DataStorage, range: Range<Int>) {
      self.storage = storage
      slice = RangeReference(range)
    }
    internal var range: Range<Int> { return slice.range }

    @usableFromInline
    internal mutating func ensureUniqueReference() {
      if !isKnownUniquelyReferenced(&storage) { storage = storage._copy(range, capacity: range.count) }
      if !isKnownUniquelyReferenced(&slice) { slice = RangeReference(range) }
    }
  }

  @usableFromInline
  @frozen
  internal enum _Representation: Sendable {
    case empty
    case inline(InlineData)
    case slice(InlineSlice)
    case large(LargeSlice)

    /// The representation for `range` of `storage` (storage indices).
    internal static func _sliced(_ storage: __DataStorage, _ range: Range<Int>) -> _Representation {
      if range.upperBound <= Int(Int32.max) { return .slice(InlineSlice(storage: storage, range: range)) }
      return .large(LargeSlice(storage: storage, range: range))
    }

    @usableFromInline
    internal init(_ buffer: UnsafeRawBufferPointer) {
      if buffer.count == 0 {
        self = .empty
      } else if buffer.count <= InlineData.capacity {
        self = .inline(InlineData(buffer))
      } else {
        self = _Representation._sliced(__DataStorage(bytes: buffer.baseAddress, length: buffer.count), 0..<buffer.count)
      }
    }

    @usableFromInline
    internal init(count: Int) {
      precondition(count >= 0, "count must not be negative")
      if count == 0 {
        self = .empty
      } else if count <= InlineData.capacity {
        self = .inline(InlineData(count: count))
      } else {
        self = _Representation._sliced(__DataStorage(length: count), 0..<count)
      }
    }

    internal var startIndex: Int {
      switch self {
      case .empty, .inline: return 0
      case .slice(let s): return Int(s.slice.lowerBound)
      case .large(let s): return s.range.lowerBound
      }
    }
    internal var endIndex: Int {
      switch self {
      case .empty: return 0
      case .inline(let d): return Int(d.length)
      case .slice(let s): return Int(s.slice.upperBound)
      case .large(let s): return s.range.upperBound
      }
    }
    internal var count: Int { return endIndex - startIndex }

    internal func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
      switch self {
      case .empty: return try body(UnsafeRawBufferPointer(start: nil, count: 0))
      case .inline(let d): return try d.withBytes(body)
      case .slice(let s): return try s.storage._withBytes(in: s.range, body)
      case .large(let s): return try s.storage._withBytes(in: s.range, body)
      }
    }

    @usableFromInline
    internal subscript(index: Int) -> UInt8 {
      precondition(index >= startIndex && index < endIndex, "Data index out of range")
      return withUnsafeBytes { $0[index - startIndex] }
    }

    @usableFromInline
    internal subscript(bounds: Range<Int>) -> Data {
      precondition(bounds.lowerBound >= startIndex && bounds.upperBound <= endIndex, "Range out of bounds")
      if bounds.isEmpty { return Data() }
      switch self {
      case .slice(let s): return Data(_representation: _Representation._sliced(s.storage, bounds))
      case .large(let s): return Data(_representation: _Representation._sliced(s.storage, bounds))
      default:
        let lo = bounds.lowerBound - startIndex
        return withUnsafeBytes { buf -> Data in
          let part = UnsafeRawBufferPointer(rebasing: buf[lo..<(lo + bounds.count)])
          if bounds.lowerBound == 0 { return Data(_representation: _Representation(part)) }
          let storage = __DataStorage(bytes: part.baseAddress, length: part.count)
          storage._offset = bounds.lowerBound
          return Data(_representation: _Representation._sliced(storage, bounds))
        }
      }
    }

    /// Replaces `subrange` with `cnt` bytes from `bytes` (zeros if nil),
    /// keeping startIndex.
    @usableFromInline
    internal mutating func replaceSubrange(_ subrange: Range<Int>, with bytes: UnsafeRawPointer?, count cnt: Int) {
      let start = startIndex, end = endIndex
      precondition(subrange.lowerBound >= start && subrange.upperBound <= end, "Range out of bounds")
      let newCount = (end - start) - subrange.count + cnt
      // Small results that start at 0 stay inline.
      if start == 0 && newCount <= InlineData.capacity {
        var tmp = [UInt8](repeating: 0, count: newCount)
        withUnsafeBytes { old in
          let a = subrange.lowerBound - start
          for i in 0..<a { tmp[i] = old[i] }
          if let b = bytes { for i in 0..<cnt { tmp[a + i] = b.load(fromByteOffset: i, as: UInt8.self) } }
          let tail = (end - start) - (subrange.upperBound - start)
          for i in 0..<tail { tmp[a + cnt + i] = old[subrange.upperBound - start + i] }
        }
        self = newCount == 0 ? .empty : tmp.withUnsafeBytes { .inline(InlineData($0)) }
        return
      }
      // Otherwise work in a storage this Data owns outright, covering
      // exactly start..<end.
      var storage: __DataStorage
      switch self {
      case .slice(let s) where s.storage._offset == start && s.storage._length == end - start
        && s.storage._deallocator == nil:
        storage = s.storage
        self = .empty // drop our reference so the storage can be unique
        if !isKnownUniquelyReferenced(&storage) { storage = storage._copy(start..<end, capacity: newCount) }
      case .large(let s) where s.storage._offset == start && s.storage._length == end - start
        && s.storage._deallocator == nil:
        storage = s.storage
        self = .empty
        if !isKnownUniquelyReferenced(&storage) { storage = storage._copy(start..<end, capacity: newCount) }
      default:
        let copy = __DataStorage(capacity: Swift.max(newCount, 16))
        withUnsafeBytes { old in
          if old.count > 0 { memcpy(copy._bytes!, old.baseAddress!, old.count) }
        }
        copy._length = end - start
        copy._offset = start
        storage = copy
      }
      storage._grow(to: newCount)
      let base = storage._bytes!
      let a = subrange.lowerBound - start
      let tailStart = subrange.upperBound - start
      let tail = (end - start) - tailStart
      if tail > 0 { memmove(base + a + cnt, base + tailStart, tail) }
      if cnt > 0 {
        if let b = bytes { memmove(base + a, b, cnt) } else { memset(base + a, 0, cnt) }
      }
      storage._length = newCount
      self = _Representation._sliced(storage, start..<(start + newCount))
    }

    @usableFromInline
    internal mutating func append(contentsOf buffer: UnsafeRawBufferPointer) {
      if buffer.count == 0 { return }
      let e = endIndex
      replaceSubrange(e..<e, with: buffer.baseAddress, count: buffer.count)
    }

    @usableFromInline
    internal mutating func reserveCapacity(_ minimumCapacity: Int) {
      if minimumCapacity <= InlineData.capacity { return }
      let start = startIndex, end = endIndex
      // Move into an owned storage with the room, then trim nothing.
      let e = end
      replaceSubrange(e..<e, with: nil, count: 0)
      switch self {
      case .slice(let s): s.storage._grow(to: minimumCapacity)
      case .large(let s): s.storage._grow(to: minimumCapacity)
      default:
        let storage = __DataStorage(capacity: minimumCapacity)
        withUnsafeBytes { old in if old.count > 0 { memcpy(storage._bytes!, old.baseAddress!, old.count) } }
        storage._length = end - start
        storage._offset = start
        self = _Representation._sliced(storage, start..<end)
      }
    }

    @usableFromInline
    internal mutating func resetBytes(in range: Range<Int>) {
      if range.isEmpty { return }
      let end = endIndex
      if range.upperBound > end {
        // Extends the data with zeros.
        replaceSubrange(range.lowerBound..<end, with: nil, count: range.count)
      } else {
        replaceSubrange(range, with: nil, count: range.count)
      }
    }

    internal mutating func setByte(_ value: UInt8, at index: Int) {
      precondition(index >= startIndex && index < endIndex, "Data index out of range")
      var v = value
      replaceSubrange(index..<(index + 1), with: &v, count: 1)
    }
  }

  @usableFromInline internal var _representation: _Representation

  @usableFromInline
  internal init(_representation: _Representation) { self._representation = _representation }

  // MARK: initializers

  public init() { _representation = .empty }
  public init(bytes: UnsafeRawPointer, count: Int) {
    _representation = _Representation(UnsafeRawBufferPointer(start: bytes, count: count))
  }
  public init<SourceType>(buffer: UnsafeBufferPointer<SourceType>) {
    _representation = _Representation(UnsafeRawBufferPointer(buffer))
  }
  public init<SourceType>(buffer: UnsafeMutableBufferPointer<SourceType>) {
    _representation = _Representation(UnsafeRawBufferPointer(UnsafeBufferPointer(buffer)))
  }
  public init(repeating repeatedValue: UInt8, count: Int) {
    _representation = _Representation(count: count)
    if repeatedValue != 0 {
      for i in 0..<count { self[i] = repeatedValue }
    }
  }
  public init(capacity: Int) {
    _representation = .empty
    reserveCapacity(capacity)
  }
  public init(count: Int) { _representation = _Representation(count: count) }
  public init(bytesNoCopy bytes: UnsafeMutableRawPointer, count: Int, deallocator: Deallocator) {
    if count == 0 {
      deallocator._deallocator(bytes, 0)
      _representation = .empty
      return
    }
    let storage = __DataStorage(bytes: bytes, length: count, copy: false, deallocator: deallocator._deallocator, offset: 0)
    _representation = _Representation._sliced(storage, 0..<count)
  }
  public init<S: Sequence>(_ elements: S) where S.Element == UInt8 {
    let bytes = Array(elements)
    _representation = bytes.withUnsafeBytes { _Representation($0) }
  }

  public enum Deallocator: Sendable {
    case virtualMemory
    case unmap
    case free
    case none
    case custom(@Sendable (UnsafeMutableRawPointer, Int) -> Void)

    @usableFromInline
    internal var _deallocator: (UnsafeMutableRawPointer, Int) -> Void {
      switch self {
      case .virtualMemory, .free: return { p, _ in Darwin.free(p) }
      case .unmap: return { p, n in _ = munmap(p, n) }
      case .none: return { _, _ in }
      case .custom(let b): return b
      }
    }
  }

  // MARK: collection

  public var startIndex: Int { return _representation.startIndex }
  public var endIndex: Int { return _representation.endIndex }
  public var count: Int {
    get { return _representation.count }
    set {
      precondition(newValue >= 0, "count must not be negative")
      let c = _representation.count
      if newValue > c {
        _representation.resetBytes(in: endIndex..<(endIndex + newValue - c))
      } else if newValue < c {
        _representation.replaceSubrange((startIndex + newValue)..<endIndex, with: nil, count: 0)
      }
    }
  }
  public var isEmpty: Bool { return count == 0 }
  public var indices: Range<Int> { return startIndex..<endIndex }
  public func index(after i: Int) -> Int { return i + 1 }
  public func index(before i: Int) -> Int { return i - 1 }
  public func index(_ i: Int, offsetBy n: Int) -> Int { return i + n }
  public func distance(from start: Int, to end: Int) -> Int { return end - start }

  public subscript(index: Int) -> UInt8 {
    get { return _representation[index] }
    set { _representation.setByte(newValue, at: index) }
  }
  public subscript(bounds: Range<Int>) -> Data {
    get { return _representation[bounds] }
    set { replaceSubrange(bounds, with: newValue) }
  }

  public var regions: CollectionOfOne<Data> { return CollectionOfOne(self) }

  public func withUnsafeBytes<ResultType>(_ body: (UnsafeRawBufferPointer) throws -> ResultType) rethrows -> ResultType {
    return try _representation.withUnsafeBytes(body)
  }
  public mutating func withUnsafeMutableBytes<ResultType>(
    _ body: (UnsafeMutableRawBufferPointer) throws -> ResultType
  ) rethrows -> ResultType {
    // Work on owned out-of-line storage, then let small data go back inline.
    let start = startIndex, n = count
    if n == 0 { return try body(UnsafeMutableRawBufferPointer(start: nil, count: 0)) }
    _representation.reserveCapacity(Swift.max(n, _Representation.InlineDataCapacityPlusOne))
    switch _representation {
    case .slice(let s):
      return try body(UnsafeMutableRawBufferPointer(start: s.storage._bytes! + (start - s.storage._offset), count: n))
    case .large(let s):
      return try body(UnsafeMutableRawBufferPointer(start: s.storage._bytes! + (start - s.storage._offset), count: n))
    default:
      fatalError("Data: unexpected representation")
    }
  }

  public func copyBytes(to pointer: UnsafeMutablePointer<UInt8>, count: Int) {
    precondition(count <= self.count, "count out of range")
    withUnsafeBytes { if count > 0 { memcpy(pointer, $0.baseAddress!, count) } }
  }
  public func copyBytes(to pointer: UnsafeMutablePointer<UInt8>, from range: Range<Int>) {
    precondition(range.lowerBound >= startIndex && range.upperBound <= endIndex, "range out of bounds")
    withUnsafeBytes { buf in
      if range.count > 0 { memcpy(pointer, buf.baseAddress! + (range.lowerBound - startIndex), range.count) }
    }
  }

  // MARK: mutation

  public mutating func reserveCapacity(_ minimumCapacity: Int) { _representation.reserveCapacity(minimumCapacity) }

  public mutating func append(_ bytes: UnsafePointer<UInt8>, count: Int) {
    _representation.append(contentsOf: UnsafeRawBufferPointer(start: bytes, count: count))
  }
  public mutating func append(_ other: Data) {
    other.withUnsafeBytes { _representation.append(contentsOf: $0) }
  }
  public mutating func append<SourceType>(_ buffer: UnsafeBufferPointer<SourceType>) {
    _representation.append(contentsOf: UnsafeRawBufferPointer(buffer))
  }
  public mutating func append(contentsOf bytes: [UInt8]) {
    bytes.withUnsafeBytes { _representation.append(contentsOf: $0) }
  }
  public mutating func append<S: Sequence>(contentsOf elements: S) where S.Element == UInt8 {
    let bytes = Array(elements)
    bytes.withUnsafeBytes { _representation.append(contentsOf: $0) }
  }
  public mutating func append(_ byte: UInt8) {
    var b = byte
    _representation.append(contentsOf: UnsafeRawBufferPointer(start: &b, count: 1))
  }

  public mutating func resetBytes(in range: Range<Int>) { _representation.resetBytes(in: range) }

  public mutating func replaceSubrange(_ subrange: Range<Int>, with data: Data) {
    data.withUnsafeBytes { _representation.replaceSubrange(subrange, with: $0.baseAddress, count: $0.count) }
  }
  public mutating func replaceSubrange<SourceType>(_ subrange: Range<Int>, with buffer: UnsafeBufferPointer<SourceType>) {
    let raw = UnsafeRawBufferPointer(buffer)
    _representation.replaceSubrange(subrange, with: raw.baseAddress, count: raw.count)
  }
  public mutating func replaceSubrange<C: Collection>(_ subrange: Range<Int>, with newElements: C) where C.Element == UInt8 {
    let bytes = Array(newElements)
    bytes.withUnsafeBytes { _representation.replaceSubrange(subrange, with: $0.baseAddress, count: $0.count) }
  }
  public mutating func replaceSubrange(_ subrange: Range<Int>, with bytes: UnsafeRawPointer, count cnt: Int) {
    _representation.replaceSubrange(subrange, with: bytes, count: cnt)
  }

  public func subdata(in range: Range<Int>) -> Data {
    precondition(range.lowerBound >= startIndex && range.upperBound <= endIndex, "range out of bounds")
    return withUnsafeBytes { buf in
      Data(bytes: buf.baseAddress! + (range.lowerBound - startIndex), count: range.count)
    }
  }

  public func range(of dataToFind: Data, options: Data.SearchOptions = [], in range: Range<Int>? = nil) -> Range<Int>? {
    let r = range ?? (startIndex..<endIndex)
    if options.contains(.anchored) {
      if options.contains(.backwards) {
        let lo = r.upperBound - dataToFind.count
        return lo >= r.lowerBound && _matches(dataToFind, at: lo) ? lo..<r.upperBound : nil
      }
      return _matches(dataToFind, at: r.lowerBound) && r.count >= dataToFind.count
        ? r.lowerBound..<(r.lowerBound + dataToFind.count) : nil
    }
    return options.contains(.backwards) ? lastRange(of: dataToFind, in: r) : firstRange(of: dataToFind, in: r)
  }

  public typealias SearchOptions = NSData.SearchOptions
  public typealias ReadingOptions = NSData.ReadingOptions
  public typealias WritingOptions = NSData.WritingOptions
  public typealias Base64EncodingOptions = NSData.Base64EncodingOptions
  public typealias Base64DecodingOptions = NSData.Base64DecodingOptions

  // MARK: iteration

  @frozen
  public struct Iterator: IteratorProtocol, Sendable {
    @usableFromInline
    internal typealias Buffer = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    @usableFromInline internal let _data: Data
    @usableFromInline internal var _buffer: Buffer
    @usableFromInline internal var _idx: Data.Index
    @usableFromInline internal let _endIdx: Data.Index

    /// The buffer holds the 32-byte block containing _idx (block k covers
    /// indices 32k..<32k+32), so next() refills it at each block start.
    @usableFromInline
    internal init(_ data: Data, at loc: Data.Index) {
      _data = data
      _buffer = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
      _idx = loc
      _endIdx = data.endIndex
      let size = MemoryLayout<Buffer>.size
      let inBlock = loc % size
      if inBlock != 0 && loc < _endIdx {
        let blockStart = loc - inBlock
        let blockEnd = Swift.min(blockStart + size, _endIdx)
        let from = Swift.max(blockStart, data.startIndex)
        Swift.withUnsafeMutableBytes(of: &_buffer) { buf in
          data.withUnsafeBytes { src in
            for i in from..<blockEnd { buf[i - blockStart] = src[i - data.startIndex] }
          }
        }
      }
    }

    public mutating func next() -> UInt8? {
      let idx = _idx
      guard idx < _endIdx else { return nil }
      let size = MemoryLayout<Buffer>.size
      let inBlock = idx % size
      if inBlock == 0 {
        let end = Swift.min(idx + size, _endIdx)
        let data = _data
        Swift.withUnsafeMutableBytes(of: &_buffer) { buf in
          data.withUnsafeBytes { src in
            for i in idx..<end { buf[i - idx] = src[i - data.startIndex] }
          }
        }
      }
      _idx = idx + 1
      return Swift.withUnsafeBytes(of: &_buffer) { $0[inBlock] }
    }
  }

  public func makeIterator() -> Data.Iterator { return Iterator(self, at: startIndex) }

  public func _copyContents(initializing buffer: UnsafeMutableBufferPointer<UInt8>) -> (Iterator, UnsafeMutableBufferPointer<UInt8>.Index) {
    let n = Swift.min(count, buffer.count)
    if n > 0 { withUnsafeBytes { memcpy(buffer.baseAddress!, $0.baseAddress!, n) } }
    return (Iterator(self, at: startIndex + n), n)
  }

  // MARK: equality and hashing

  public static func == (d1: Data, d2: Data) -> Bool {
    if d1.count != d2.count { return false }
    if d1.count == 0 { return true }
    return d1.withUnsafeBytes { a in d2.withUnsafeBytes { b in memcmp(a.baseAddress!, b.baseAddress!, a.count) == 0 } }
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(count)
    withUnsafeBytes { buf in
      for b in buf.prefix(80) { hasher.combine(b) }
    }
  }

  // MARK: base64

  internal static let _base64Alphabet: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)

  public func base64EncodedData(options: Base64EncodingOptions = []) -> Data {
    let alphabet = Data._base64Alphabet
    var out: [UInt8] = []
    out.reserveCapacity((count + 2) / 3 * 4)
    let lineLength = options.contains(.lineLength64Characters) ? 64 : options.contains(.lineLength76Characters) ? 76 : 0
    var separator: [UInt8] = []
    if options.contains(.endLineWithCarriageReturn) { separator.append(13) }
    if options.contains(.endLineWithLineFeed) { separator.append(10) }
    if lineLength > 0 && separator.isEmpty { separator = [13, 10] }
    var lineCount = 0
    func emit(_ c: UInt8) {
      if lineLength > 0 && lineCount == lineLength {
        out.append(contentsOf: separator)
        lineCount = 0
      }
      out.append(c)
      lineCount += 1
    }
    withUnsafeBytes { buf in
      var i = 0
      while i + 3 <= buf.count {
        let v = UInt32(buf[i]) << 16 | UInt32(buf[i + 1]) << 8 | UInt32(buf[i + 2])
        emit(alphabet[Int(v >> 18 & 63)]); emit(alphabet[Int(v >> 12 & 63)])
        emit(alphabet[Int(v >> 6 & 63)]); emit(alphabet[Int(v & 63)])
        i += 3
      }
      let rest = buf.count - i
      if rest == 1 {
        let v = UInt32(buf[i]) << 16
        emit(alphabet[Int(v >> 18 & 63)]); emit(alphabet[Int(v >> 12 & 63)]); emit(61); emit(61)
      } else if rest == 2 {
        let v = UInt32(buf[i]) << 16 | UInt32(buf[i + 1]) << 8
        emit(alphabet[Int(v >> 18 & 63)]); emit(alphabet[Int(v >> 12 & 63)]); emit(alphabet[Int(v >> 6 & 63)]); emit(61)
      }
    }
    return Data(out)
  }

  public func base64EncodedString(options: Base64EncodingOptions = []) -> String {
    let d = base64EncodedData(options: options)
    return d.withUnsafeBytes { String(decoding: $0, as: UTF8.self) }
  }

  public init?(base64Encoded base64Data: __shared Data, options: Base64DecodingOptions = []) {
    var values: [UInt8] = []
    var padding = 0
    let ignoreUnknown = options.contains(.ignoreUnknownCharacters)
    for c in base64Data {
      let v: UInt8
      switch c {
      case 65...90: v = c - 65
      case 97...122: v = c - 71
      case 48...57: v = c + 4
      case 43: v = 62
      case 47: v = 63
      case 61:
        padding += 1
        continue
      default:
        if ignoreUnknown { continue }
        return nil
      }
      if padding > 0 { return nil } // data after padding
      values.append(v)
    }
    if (values.count + padding) % 4 != 0 || padding > 2 { return nil }
    if values.count % 4 == 1 { return nil }
    var out: [UInt8] = []
    out.reserveCapacity(values.count * 3 / 4)
    var i = 0
    while i + 4 <= values.count {
      let v = UInt32(values[i]) << 18 | UInt32(values[i + 1]) << 12 | UInt32(values[i + 2]) << 6 | UInt32(values[i + 3])
      out.append(UInt8(v >> 16 & 255)); out.append(UInt8(v >> 8 & 255)); out.append(UInt8(v & 255))
      i += 4
    }
    let rest = values.count - i
    if rest == 2 {
      let v = UInt32(values[i]) << 18 | UInt32(values[i + 1]) << 12
      out.append(UInt8(v >> 16 & 255))
    } else if rest == 3 {
      let v = UInt32(values[i]) << 18 | UInt32(values[i + 1]) << 12 | UInt32(values[i + 2]) << 6
      out.append(UInt8(v >> 16 & 255)); out.append(UInt8(v >> 8 & 255))
    }
    self.init(out)
  }

  public init?(base64Encoded base64String: __shared String, options: Base64DecodingOptions = []) {
    self.init(base64Encoded: Data(base64String.utf8), options: options)
  }

  // MARK: files

  public init(contentsOf url: __shared URL, options: ReadingOptions = []) throws {
    guard url.isFileURL else { throw _dataPOSIXError(ENOTSUP, url: url, reading: true) }
    let fd = url.path.withCString { open($0, O_RDONLY) }
    if fd < 0 { throw _dataPOSIXError(_posixErrno, url: url, reading: true) }
    defer { close(fd) }
    var bytes: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 65536)
    while true {
      let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress!, 65536) }
      if n < 0 {
        if _posixErrno == EINTR { continue }
        throw _dataPOSIXError(_posixErrno, url: url, reading: true)
      }
      if n == 0 { break }
      bytes.append(contentsOf: chunk[0..<n])
    }
    self.init(bytes)
  }

  public func write(to url: URL, options: WritingOptions = []) throws {
    guard url.isFileURL else { throw _dataPOSIXError(ENOTSUP, url: url, reading: false) }
    let path = url.path
    let atomic = options.contains(.atomic)
    let target = atomic ? path + ".tmp-\(getpid())-\(arc4random())" : path
    var flags = O_WRONLY | O_CREAT | O_TRUNC
    if options.contains(.withoutOverwriting) { flags |= O_EXCL }
    let fd = target.withCString { open($0, flags, 0o666) }
    if fd < 0 { throw _dataPOSIXError(_posixErrno, url: url, reading: false) }
    var failure: Int32 = 0
    withUnsafeBytes { buf in
      var done = 0
      while done < buf.count {
        let n = Darwin.write(fd, buf.baseAddress! + done, buf.count - done)
        if n < 0 {
          if _posixErrno == EINTR { continue }
          failure = _posixErrno
          return
        }
        done += n
      }
    }
    close(fd)
    if failure != 0 { throw _dataPOSIXError(failure, url: url, reading: false) }
    if atomic && target.withCString({ t in path.withCString { rename(t, $0) } }) != 0 {
      let e = _posixErrno
      _ = target.withCString { unlink($0) }
      throw _dataPOSIXError(e, url: url, reading: false)
    }
  }
}

/// errno, read directly: Darwin's `errno` moved to _errno in macOS 14 and
/// is hidden from links for older targets.
internal var _posixErrno: Int32 { return __error().pointee }

internal func _dataPOSIXError(_ code: Int32, url: URL, reading: Bool) -> NSError {
  let cocoa: Int
  switch code {
  case ENOENT: cocoa = reading ? 260 : 4
  case EACCES, EPERM: cocoa = reading ? 257 : 513
  case EEXIST: cocoa = 516
  default: cocoa = reading ? 256 : 512
  }
  return NSError._bn_error(withDomain: NSCocoaErrorDomain, code: cocoa, filePath: url.path, underlyingPOSIX: code)
}

extension Data._Representation {
  /// A capacity that forces out-of-line storage.
  internal static var InlineDataCapacityPlusOne: Int { return Data.InlineData.capacity + 1 }
}

extension Data: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String { return "\(count) bytes" }
  public var debugDescription: String { return description }
}

extension Data: Codable {
  public init(from decoder: any Decoder) throws {
    var c = try decoder.unkeyedContainer()
    var bytes: [UInt8] = []
    if let n = c.count { bytes.reserveCapacity(n) }
    while !c.isAtEnd { bytes.append(try c.decode(UInt8.self)) }
    self.init(bytes)
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.unkeyedContainer()
    try withUnsafeBytes { buf in
      for b in buf { try c.encode(b) }
    }
  }
}

extension Data: _ObjectiveCBridgeable {
  public func _bridgeToObjectiveC() -> NSData {
    return withUnsafeBytes { buf -> NSData in
      guard let base = buf.baseAddress, buf.count > 0 else { return NSData() }
      return NSData(bytes: base, length: buf.count)
    }
  }
  public static func _forceBridgeFromObjectiveC(_ input: NSData, result: inout Data?) {
    result = _unconditionallyBridgeFromObjectiveC(input)
  }
  public static func _conditionallyBridgeFromObjectiveC(_ input: NSData, result: inout Data?) -> Bool {
    result = _unconditionallyBridgeFromObjectiveC(input)
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSData?) -> Data {
    guard let s = source, s.length > 0 else { return Data() }
    return Data(bytes: s.bytes, count: s.length)
  }
}

extension NSError: Error {}

// MARK: - String and Data

extension StringProtocol {
  public func data(using encoding: String.Encoding, allowLossyConversion: Bool = false) -> Data? {
    switch encoding {
    case .utf8: return Data(String(self).utf8)
    case .ascii, .nonLossyASCII:
      var out: [UInt8] = []
      for s in unicodeScalars {
        if s.value < 128 { out.append(UInt8(s.value)) } else if allowLossyConversion { out.append(63) } else { return nil }
      }
      return Data(out)
    case .isoLatin1:
      var out: [UInt8] = []
      for s in unicodeScalars {
        if s.value < 256 { out.append(UInt8(s.value)) } else if allowLossyConversion { out.append(63) } else { return nil }
      }
      return Data(out)
    case .utf16, .utf16LittleEndian, .utf16BigEndian:
      var out: [UInt8] = encoding == .utf16 ? [0xFF, 0xFE] : []
      for u in String(self).utf16 {
        if encoding == .utf16BigEndian { out.append(UInt8(u >> 8)); out.append(UInt8(u & 255)) }
        else { out.append(UInt8(u & 255)); out.append(UInt8(u >> 8)) }
      }
      return Data(out)
    default:
      return Data(String(self).utf8)
    }
  }

  public func write(to url: URL, atomically useAuxiliaryFile: Bool, encoding enc: String.Encoding) throws {
    guard let d = data(using: enc) else { throw NSError._bn_error(withDomain: NSCocoaErrorDomain, code: 517, filePath: nil, underlyingPOSIX: 0) }
    try d.write(to: url, options: useAuxiliaryFile ? .atomic : [])
  }
  public func write(toFile path: String, atomically useAuxiliaryFile: Bool, encoding enc: String.Encoding) throws {
    try write(to: URL(fileURLWithPath: path), atomically: useAuxiliaryFile, encoding: enc)
  }
}

extension String {
  public init?(data: __shared Data, encoding: Encoding) {
    let bytes = Array(data)
    guard let s = String(bytes: bytes, encoding: encoding) else { return nil }
    self = s
  }

  public init?<S: Sequence>(bytes: __shared S, encoding: Encoding) where S.Element == UInt8 {
    let b = Array(bytes)
    switch encoding {
    case .utf8:
      let s = String(decoding: b, as: UTF8.self)
      if Array(s.utf8) != b { return nil }
      self = s
    case .ascii:
      if b.contains(where: { $0 >= 128 }) { return nil }
      self = String(decoding: b, as: UTF8.self)
    case .isoLatin1:
      var view = String.UnicodeScalarView()
      for x in b { view.append(Unicode.Scalar(x)) }
      self = String(view)
    case .utf16, .utf16LittleEndian, .utf16BigEndian:
      var units: [UInt16] = []
      var i = 0
      var big = encoding == .utf16BigEndian
      if encoding == .utf16 && b.count >= 2 {
        if b[0] == 0xFE && b[1] == 0xFF { big = true; i = 2 } else if b[0] == 0xFF && b[1] == 0xFE { i = 2 }
      }
      if (b.count - i) % 2 != 0 { return nil }
      while i + 1 < b.count {
        units.append(big ? UInt16(b[i]) << 8 | UInt16(b[i + 1]) : UInt16(b[i + 1]) << 8 | UInt16(b[i]))
        i += 2
      }
      self = String(decoding: units, as: UTF16.self)
    default:
      self = String(decoding: b, as: UTF8.self)
    }
  }

  public init(contentsOf url: __shared URL, encoding enc: Encoding) throws {
    let d = try Data(contentsOf: url)
    guard let s = String(data: d, encoding: enc) else {
      throw NSError._bn_error(withDomain: NSCocoaErrorDomain, code: 261, filePath: url.path, underlyingPOSIX: 0)
    }
    self = s
  }
  public init(contentsOfFile path: __shared String, encoding enc: Encoding) throws {
    try self.init(contentsOf: URL(fileURLWithPath: path), encoding: enc)
  }
  public init(contentsOf url: __shared URL) throws {
    try self.init(contentsOf: url, encoding: .utf8)
  }
}

// MARK: - Error <-> NSError (the compiler calls these for `as NSError`)

public func _convertErrorToNSError(_ error: Error) -> NSError {
  if let embedded = error._getEmbeddedNSError() as? NSError { return embedded }
  if type(of: error) is NSError.Type, let ns = error as? NSError { return ns }
  let domain: String
  let code: Int
  var info: [String: Any] = [:]
  if let custom = error as? CustomNSError {
    domain = type(of: custom).errorDomain
    code = custom.errorCode
    info = custom.errorUserInfo
  } else {
    domain = error._domain
    code = error._code
  }
  if let localized = error as? LocalizedError {
    if let d = localized.errorDescription { info[NSLocalizedDescriptionKey] = d }
    if let r = localized.failureReason { info[NSLocalizedFailureReasonErrorKey] = r }
  }
  return NSError(domain: domain, code: code, userInfo: info.isEmpty ? nil : info)
}

public func _convertNSErrorToError(_ error: NSError?) -> Error {
  if let e = error { return e }
  return NSError._bn_error(withDomain: "Foundation._GenericObjCError", code: 0, filePath: nil, underlyingPOSIX: 0)
}
