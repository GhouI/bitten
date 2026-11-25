// The buffer pointers: a typed or raw pointer with a count, viewed as a
// random-access collection.
//
// Conversions between pointer types inside the library go through
// `_rawValue`: otherwise the type checker may pick an implicit pointer
// conversion, which this compiler refuses inside the standard library.

@frozen public struct UnsafeBufferPointer<Element> {
  @usableFromInline internal let _position: UnsafePointer<Element>?
  public let count: Int
  @inlinable public init(start: UnsafePointer<Element>?, count: Int) {
    _collectionPrecondition(count >= 0 && (count == 0 || start != nil))
    _position = start
    self.count = count
  }
  @inlinable public init(_empty: ()) {
    _position = nil
    count = 0
  }
  @inlinable public init(_ other: UnsafeMutableBufferPointer<Element>) {
    _position = UnsafePointer<Element>(other._position)
    count = other.count
  }
  @inlinable public var baseAddress: UnsafePointer<Element>? { return _position }
  @inlinable public func deallocate() { _position?.deallocate() }
}

extension UnsafeBufferPointer {
  @frozen public struct Iterator {
    @usableFromInline internal var _position, _end: UnsafePointer<Element>?
    @inlinable public init(_position: UnsafePointer<Element>?, _end: UnsafePointer<Element>?) {
      self._position = _position
      self._end = _end
    }
  }
}
extension UnsafeBufferPointer.Iterator: IteratorProtocol, Sequence {
  @inlinable public mutating func next() -> Element? {
    guard let start = _position else { return nil }
    if start == _end! { return nil }
    _position = start + 1
    return start.pointee
  }
}

extension UnsafeBufferPointer: Sequence {
  @inlinable public func makeIterator() -> Iterator {
    guard let start = _position else { return Iterator(_position: nil, _end: nil) }
    return Iterator(_position: start, _end: start + count)
  }
  @inlinable
  public func _copyContents(initializing destination: UnsafeMutableBufferPointer<Element>) -> (Iterator, Int) {
    guard !isEmpty && !destination.isEmpty else { return (makeIterator(), 0) }
    let s = self.baseAddress!
    let d = destination.baseAddress!
    let n = Swift.min(destination.count, self.count)
    d.initialize(from: s, count: n)
    return (Iterator(_position: s + n, _end: s + count), n)
  }
  @inlinable
  public func withContiguousStorageIfAvailable<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows -> R? {
    return try body(self)
  }
}

extension UnsafeBufferPointer: RandomAccessCollection {
  public typealias Index = Int
  public typealias Indices = Range<Int>
  public typealias SubSequence = Slice<UnsafeBufferPointer<Element>>
  @inlinable public var startIndex: Int { return 0 }
  @inlinable public var endIndex: Int { return count }
  @inlinable public func index(after i: Int) -> Int { return i + 1 }
  @inlinable public func index(before i: Int) -> Int { return i - 1 }
  @inlinable public subscript(i: Int) -> Element {
    _collectionPrecondition(i >= 0 && i < count)
    return _position![i]
  }
  @inlinable public subscript(bounds: Range<Int>) -> Slice<UnsafeBufferPointer<Element>> {
    _collectionPrecondition(bounds.lowerBound >= 0 && bounds.upperBound <= count)
    return Slice(base: self, bounds: bounds)
  }
}

// ---- UnsafeMutableBufferPointer -------------------------------------------------------

@frozen public struct UnsafeMutableBufferPointer<Element> {
  @usableFromInline internal let _position: UnsafeMutablePointer<Element>?
  public let count: Int
  @inlinable public init(start: UnsafeMutablePointer<Element>?, count: Int) {
    _collectionPrecondition(count >= 0 && (count == 0 || start != nil))
    _position = start
    self.count = count
  }
  @inlinable public init(_empty: ()) {
    _position = nil
    count = 0
  }
  @inlinable public init(mutating other: UnsafeBufferPointer<Element>) {
    _position = UnsafeMutablePointer<Element>(mutating: other._position)
    count = other.count
  }
  @inlinable public init(_ other: UnsafeMutableBufferPointer<Element>) { self = other }
  @inlinable public var baseAddress: UnsafeMutablePointer<Element>? { return _position }

  @inlinable public static func allocate(capacity count: Int) -> UnsafeMutableBufferPointer<Element> {
    let base = UnsafeMutablePointer<Element>.allocate(capacity: count)
    return UnsafeMutableBufferPointer(start: base, count: count)
  }
  @inlinable public func deallocate() { _position?.deallocate() }
  @inlinable public func initialize(repeating repeatedValue: Element) {
    guard let dst = _position else { return }
    dst.initialize(repeating: repeatedValue, count: count)
  }
  @inlinable public func initialize<S: Sequence>(from source: S) -> (S.Iterator, Index) where S.Element == Element {
    var it = source.makeIterator()
    var i = 0
    while i < count, let e = it.next() {
      (_position! + i).initialize(to: e)
      i += 1
    }
    return (it, i)
  }
  @inlinable @discardableResult
  public func deinitialize() -> UnsafeMutableRawBufferPointer {
    guard let p = _position else { return UnsafeMutableRawBufferPointer(start: nil, count: 0) }
    p.deinitialize(count: count)
    return UnsafeMutableRawBufferPointer(start: UnsafeMutableRawPointer(p._rawValue), count: count * MemoryLayout<Element>.stride)
  }
  @inlinable public func swapAt(_ i: Int, _ j: Int) {
    guard i != j else { return }
    _collectionPrecondition(i >= 0 && j >= 0 && i < count && j < count)
    let pi = _position! + i
    let pj = _position! + j
    let tmp = pi.move()
    pi.moveInitialize(from: pj, count: 1)
    pj.initialize(to: tmp)
  }
}

extension UnsafeMutableBufferPointer: Sequence {
  public typealias Iterator = UnsafeBufferPointer<Element>.Iterator
  @inlinable public func makeIterator() -> Iterator {
    guard let start = _position else { return Iterator(_position: nil, _end: nil) }
    let p = UnsafePointer<Element>(start._rawValue)
    return Iterator(_position: p, _end: p + count)
  }
  @inlinable
  public func _copyContents(initializing destination: UnsafeMutableBufferPointer<Element>) -> (Iterator, Int) {
    return UnsafeBufferPointer(self)._copyContents(initializing: destination)
  }
  @inlinable
  public func withContiguousStorageIfAvailable<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows -> R? {
    return try body(UnsafeBufferPointer(self))
  }
}

extension UnsafeMutableBufferPointer: RandomAccessCollection, MutableCollection {
  public typealias Index = Int
  public typealias Indices = Range<Int>
  public typealias SubSequence = Slice<UnsafeMutableBufferPointer<Element>>
  @inlinable public var startIndex: Int { return 0 }
  @inlinable public var endIndex: Int { return count }
  @inlinable public func index(after i: Int) -> Int { return i + 1 }
  @inlinable public func index(before i: Int) -> Int { return i - 1 }
  @inlinable public subscript(i: Int) -> Element {
    get {
      _collectionPrecondition(i >= 0 && i < count)
      return _position![i]
    }
    nonmutating _modify {
      _collectionPrecondition(i >= 0 && i < count)
      yield &_position![i]
    }
  }
  @inlinable public subscript(bounds: Range<Int>) -> Slice<UnsafeMutableBufferPointer<Element>> {
    get {
      _collectionPrecondition(bounds.lowerBound >= 0 && bounds.upperBound <= count)
      return Slice(base: self, bounds: bounds)
    }
    nonmutating set {
      var i = bounds.lowerBound
      var j = newValue.startIndex
      while i != bounds.upperBound {
        _position![i] = newValue[j]
        i += 1
        j = newValue.index(after: j)
      }
    }
  }
  @inlinable
  public mutating func withContiguousMutableStorageIfAvailable<R>(
    _ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R) rethrows -> R? {
    var copy = self
    return try body(&copy)
  }
}

// ---- raw buffers -------------------------------------------------------------------

@frozen public struct UnsafeRawBufferPointer {
  @usableFromInline internal let _position, _end: UnsafeRawPointer?
  @inlinable public init(start: UnsafeRawPointer?, count: Int) {
    _collectionPrecondition(count >= 0 && (count == 0 || start != nil))
    _position = start
    _end = start.map { $0 + count }
  }
  @inlinable public init(_ other: UnsafeMutableRawBufferPointer) {
    _position = UnsafeRawPointer(other._position)
    _end = UnsafeRawPointer(other._end)
  }
  @inlinable public init<T>(_ buffer: UnsafeBufferPointer<T>) {
    self.init(start: buffer.baseAddress.map { UnsafeRawPointer($0._rawValue) },
              count: buffer.count * MemoryLayout<T>.stride)
  }
  @inlinable public var baseAddress: UnsafeRawPointer? { return _position }
  @inlinable public var count: Int {
    guard let s = _position, let e = _end else { return 0 }
    return Int(bitPattern: e) - Int(bitPattern: s)
  }
  @inlinable public func load<T>(fromByteOffset offset: Int = 0, as type: T.Type) -> T {
    return _position!.load(fromByteOffset: offset, as: type)
  }
}
extension UnsafeRawBufferPointer: RandomAccessCollection {
  public typealias Index = Int
  public typealias Indices = Range<Int>
  public typealias Element = UInt8
  public typealias SubSequence = Slice<UnsafeRawBufferPointer>
  @inlinable public var startIndex: Int { return 0 }
  @inlinable public var endIndex: Int { return count }
  @inlinable public subscript(i: Int) -> UInt8 {
    _collectionPrecondition(i >= 0 && i < count)
    return _position!.load(fromByteOffset: i, as: UInt8.self)
  }
  @inlinable public subscript(bounds: Range<Int>) -> Slice<UnsafeRawBufferPointer> {
    return Slice(base: self, bounds: bounds)
  }
}

@frozen public struct UnsafeMutableRawBufferPointer {
  @usableFromInline internal let _position, _end: UnsafeMutableRawPointer?
  @inlinable public init(start: UnsafeMutableRawPointer?, count: Int) {
    _collectionPrecondition(count >= 0 && (count == 0 || start != nil))
    _position = start
    _end = start.map { $0 + count }
  }
  @inlinable public init<T>(_ buffer: UnsafeMutableBufferPointer<T>) {
    self.init(start: buffer.baseAddress.map { UnsafeMutableRawPointer($0._rawValue) },
              count: buffer.count * MemoryLayout<T>.stride)
  }
  @inlinable public var baseAddress: UnsafeMutableRawPointer? { return _position }
  @inlinable public var count: Int {
    guard let s = _position, let e = _end else { return 0 }
    return Int(bitPattern: e) - Int(bitPattern: s)
  }
  @inlinable public static func allocate(byteCount: Int, alignment: Int) -> UnsafeMutableRawBufferPointer {
    let base = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: alignment)
    return UnsafeMutableRawBufferPointer(start: base, count: byteCount)
  }
  @inlinable public func deallocate() { _position?.deallocate() }
}
extension UnsafeMutableRawBufferPointer: RandomAccessCollection, MutableCollection {
  public typealias Index = Int
  public typealias Indices = Range<Int>
  public typealias Element = UInt8
  public typealias SubSequence = Slice<UnsafeMutableRawBufferPointer>
  @inlinable public var startIndex: Int { return 0 }
  @inlinable public var endIndex: Int { return count }
  @inlinable public subscript(i: Int) -> UInt8 {
    get {
      _collectionPrecondition(i >= 0 && i < count)
      return _position!.load(fromByteOffset: i, as: UInt8.self)
    }
    nonmutating set {
      _collectionPrecondition(i >= 0 && i < count)
      _position!.storeBytes(of: newValue, toByteOffset: i, as: UInt8.self)
    }
  }
  @inlinable public subscript(bounds: Range<Int>) -> Slice<UnsafeMutableRawBufferPointer> {
    get { return Slice(base: self, bounds: bounds) }
    nonmutating set {
      var i = bounds.lowerBound
      var j = newValue.startIndex
      while i != bounds.upperBound {
        self[i] = newValue[j]
        i += 1
        j = newValue.index(after: j)
      }
    }
  }
}

@inlinable
public func withUnsafeBytes<T, Result>(of value: inout T,
                                       _ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
  return try withUnsafePointer(to: &value) {
    try body(UnsafeRawBufferPointer(start: UnsafeRawPointer($0._rawValue), count: MemoryLayout<T>.size))
  }
}
@inlinable
public func withUnsafeMutableBytes<T, Result>(of value: inout T,
                                              _ body: (UnsafeMutableRawBufferPointer) throws -> Result) rethrows -> Result {
  return try withUnsafeMutablePointer(to: &value) {
    try body(UnsafeMutableRawBufferPointer(start: UnsafeMutableRawPointer($0._rawValue), count: MemoryLayout<T>.size))
  }
}
