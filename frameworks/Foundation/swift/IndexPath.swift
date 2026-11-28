// IndexPath: a list of indexes into nested collections (a section and an
// item, a path down a tree). Value semantics over an array; prints as the
// array does ("[1, 2]"). There is no NSIndexPath here to bridge to.

public struct IndexPath: Hashable, Sendable, RandomAccessCollection, MutableCollection, Comparable, Codable,
  ExpressibleByArrayLiteral, CustomStringConvertible, CustomDebugStringConvertible
{
  public typealias Element = Int
  public typealias Index = Array<Int>.Index
  public typealias Indices = Range<Int>
  public typealias ArrayLiteralElement = Int

  private var storage: [Int]

  public init() { storage = [] }
  public init<ElementSequence: Sequence>(indexes: ElementSequence) where ElementSequence.Element == Int {
    storage = Array(indexes)
  }
  public init(indexes: [Int]) { storage = indexes }
  public init(index: Int) { storage = [index] }
  public init(arrayLiteral indexes: Int...) { storage = indexes }

  public var startIndex: Int { return storage.startIndex }
  public var endIndex: Int { return storage.endIndex }
  public var count: Int { return storage.count }
  public var indices: Range<Int> { return storage.indices }
  public func index(after i: Int) -> Int { return i + 1 }
  public func index(before i: Int) -> Int { return i - 1 }
  public subscript(index: Int) -> Int {
    get { return storage[index] }
    set { storage[index] = newValue }
  }
  public subscript(range: Range<Int>) -> IndexPath {
    get { return IndexPath(indexes: storage[range]) }
    set { storage.replaceSubrange(range, with: newValue.storage) }
  }

  public mutating func append(_ other: IndexPath) { storage.append(contentsOf: other.storage) }
  public mutating func append(_ other: Int) { storage.append(other) }
  public mutating func append(_ other: [Int]) { storage.append(contentsOf: other) }
  public func appending(_ other: Int) -> IndexPath { var p = self; p.append(other); return p }
  public func appending(_ other: IndexPath) -> IndexPath { var p = self; p.append(other); return p }
  public func appending(_ other: [Int]) -> IndexPath { var p = self; p.append(other); return p }
  public func dropLast() -> IndexPath { return IndexPath(indexes: storage.dropLast()) }

  /// The first and second indexes, as table and collection views use them.
  public var section: Int {
    get { precondition(count == 2, "Invalid index path for use with UITableView or NSCollectionView"); return storage[0] }
    set { precondition(count == 2, "Invalid index path for use with UITableView or NSCollectionView"); storage[0] = newValue }
  }
  public var item: Int {
    get { precondition(count == 2, "Invalid index path for use with UITableView or NSCollectionView"); return storage[1] }
    set { precondition(count == 2, "Invalid index path for use with UITableView or NSCollectionView"); storage[1] = newValue }
  }
  public init(item: Int, section: Int) { storage = [section, item] }

  /// Element by element; a path that is a prefix of another comes first.
  public func compare(_ other: IndexPath) -> ComparisonResult {
    for (a, b) in zip(storage, other.storage) where a != b { return a < b ? .orderedAscending : .orderedDescending }
    return storage.count == other.storage.count ? .orderedSame
      : storage.count < other.storage.count ? .orderedAscending : .orderedDescending
  }
  public static func < (a: IndexPath, b: IndexPath) -> Bool { return a.compare(b) == .orderedAscending }
  public static func + (a: IndexPath, b: IndexPath) -> IndexPath { return a.appending(b) }
  public static func += (a: inout IndexPath, b: IndexPath) { a.append(b) }

  public var description: String { return storage.description }
  public var debugDescription: String { return storage.description }

  public init(from decoder: Decoder) throws {
    var c = try decoder.unkeyedContainer()
    var out: [Int] = []
    if let n = c.count { out.reserveCapacity(n) }
    while !c.isAtEnd { out.append(try c.decode(Int.self)) }
    storage = out
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.unkeyedContainer()
    try c.encode(contentsOf: storage)
  }
}
