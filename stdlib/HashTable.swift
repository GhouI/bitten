// The open-addressing hash table shared by Dictionary and Set.
//
// A table has 2^scale buckets; bucket i holds an element iff bit i of the
// occupancy bitmap is set. Lookups start at `hash & bucketMask` and probe
// linearly (wrapping) until they find the element or a hole; the table is
// never full, so there is always a hole. Deletion shifts later members of
// the probe run back instead of leaving tombstones.
//
// All of this is inlined into programs (they walk the bitmap and the key
// array themselves), so the bitmap layout is ABI: 64-bit words, bucket i in
// word i / 64, bit i % 64, and in tables smaller than one word the bits
// above the last bucket are kept SET, so hole searches never leave the
// table.

// ---- a bitset over raw words -----------------------------------------------------------

@usableFromInline @frozen
internal struct _UnsafeBitset {
  @usableFromInline internal let words: UnsafeMutablePointer<Word>
  @usableFromInline internal let wordCount: Int

  @inlinable @inline(__always)
  internal init(words: UnsafeMutablePointer<Word>, wordCount: Int) {
    self.words = words
    self.wordCount = wordCount
  }
}

extension _UnsafeBitset {
  @inlinable @inline(__always)
  internal static func word(for element: Int) -> Int {
    return Int(bitPattern: UInt(bitPattern: element) &>> 6)
  }
  @inlinable @inline(__always)
  internal static func bit(for element: Int) -> Int {
    return element & 63
  }
  @inlinable @inline(__always)
  internal static func split(_ element: Int) -> (word: Int, bit: Int) {
    return (word(for: element), bit(for: element))
  }
  @inlinable @inline(__always)
  internal static func join(word: Int, bit: Int) -> Int {
    return word &<< 6 | bit
  }
  @inlinable @inline(__always)
  internal static func wordCount(forCapacity capacity: Int) -> Int {
    return word(for: capacity &+ 63)
  }

  @inlinable internal var capacity: Int {
    @inline(__always) get { return wordCount &* 64 }
  }
  @inlinable @inline(__always)
  internal func isValid(_ element: Int) -> Bool {
    return element >= 0 && element < capacity
  }
  @inlinable @inline(__always)
  internal func uncheckedContains(_ element: Int) -> Bool {
    return words[_UnsafeBitset.word(for: element)].uncheckedContains(_UnsafeBitset.bit(for: element))
  }
  @inlinable @inline(__always) @discardableResult
  internal func uncheckedInsert(_ element: Int) -> Bool {
    return words[_UnsafeBitset.word(for: element)].uncheckedInsert(_UnsafeBitset.bit(for: element))
  }
  @inlinable @inline(__always) @discardableResult
  internal func uncheckedRemove(_ element: Int) -> Bool {
    return words[_UnsafeBitset.word(for: element)].uncheckedRemove(_UnsafeBitset.bit(for: element))
  }
  @inlinable internal var count: Int {
    var total = 0
    var i = 0
    while i < wordCount {
      total &+= words[i].count
      i &+= 1
    }
    return total
  }
  @inlinable @inline(__always)
  internal func clear() {
    words.update(repeating: .empty, count: wordCount)
  }
}

extension _UnsafeBitset: Sequence {
  @usableFromInline internal typealias Element = Int

  @usableFromInline @frozen
  internal struct Iterator: IteratorProtocol {
    @usableFromInline internal let bitset: _UnsafeBitset
    @usableFromInline internal var index: Int
    @usableFromInline internal var word: Word

    @inlinable @inline(__always)
    internal init(_ bitset: _UnsafeBitset) {
      self.bitset = bitset
      self.index = 0
      self.word = bitset.wordCount > 0 ? bitset.words[0] : .empty
    }

    @inlinable
    internal mutating func next() -> Int? {
      while true {
        if let bit = word.next() {
          return _UnsafeBitset.join(word: index, bit: bit)
        }
        index &+= 1
        if index >= bitset.wordCount { return nil }
        word = bitset.words[index]
      }
    }
  }

  @inlinable @inline(__always)
  internal func makeIterator() -> Iterator {
    return Iterator(self)
  }
}

extension _UnsafeBitset {
  /// Runs `body` with a zeroed bitset of at least `capacity` bits, on the
  /// stack when small.
  @inlinable
  internal static func withTemporaryBitset<R>(capacity: Int,
                                              body: (_UnsafeBitset) throws -> R) rethrows -> R {
    let count = wordCount(forCapacity: capacity)
    let words = UnsafeMutablePointer<Word>.allocate(capacity: count > 0 ? count : 1)
    words.initialize(repeating: .empty, count: count > 0 ? count : 1)
    defer { words.deallocate() }
    return try body(_UnsafeBitset(words: words, wordCount: count))
  }
}

extension _UnsafeBitset {
  /// One 64-bit word of a bitset, as a set of the integers 0..<64.
  @usableFromInline @frozen
  internal struct Word {
    @usableFromInline internal var value: UInt

    @inlinable @inline(__always)
    internal init(_ value: UInt) {
      self.value = value
    }
  }
}

extension _UnsafeBitset.Word {
  @inlinable internal static var capacity: Int {
    @inline(__always) get { return 64 }
  }
  @inlinable internal static var empty: _UnsafeBitset.Word {
    @inline(__always) get { return _UnsafeBitset.Word(0) }
  }
  @inlinable internal static var allBits: _UnsafeBitset.Word {
    @inline(__always) get { return _UnsafeBitset.Word(~0) }
  }

  @inlinable @inline(__always)
  internal func uncheckedContains(_ bit: Int) -> Bool {
    return value & (1 &<< UInt(bitPattern: bit)) != 0
  }
  @inlinable @inline(__always) @discardableResult
  internal mutating func uncheckedInsert(_ bit: Int) -> Bool {
    let mask: UInt = 1 &<< UInt(bitPattern: bit)
    let inserted = value & mask == 0
    value |= mask
    return inserted
  }
  @inlinable @inline(__always) @discardableResult
  internal mutating func uncheckedRemove(_ bit: Int) -> Bool {
    let mask: UInt = 1 &<< UInt(bitPattern: bit)
    let removed = value & mask != 0
    value &= ~mask
    return removed
  }

  @inlinable internal var isEmpty: Bool {
    @inline(__always) get { return value == 0 }
  }
  @inlinable internal var count: Int {
    @inline(__always) get { return value.nonzeroBitCount }
  }
  /// The smallest member, if any.
  @inlinable internal var minimum: Int? {
    @inline(__always) get {
      if value == 0 { return nil }
      return value.trailingZeroBitCount
    }
  }
  /// The largest member, if any.
  @inlinable internal var maximum: Int? {
    @inline(__always) get {
      if value == 0 { return nil }
      return 63 &- value.leadingZeroBitCount
    }
  }
  @inlinable internal var complement: _UnsafeBitset.Word {
    @inline(__always) get { return _UnsafeBitset.Word(~value) }
  }

  /// The members at or above `bit`.
  @inlinable @inline(__always)
  internal func subtracting(elementsBelow bit: Int) -> _UnsafeBitset.Word {
    let below: UInt = (1 &<< UInt(bitPattern: bit)) &- 1
    return _UnsafeBitset.Word(value & ~below)
  }
  /// The members below `bit` (`bit` may be 64).
  @inlinable @inline(__always)
  internal func intersecting(elementsBelow bit: Int) -> _UnsafeBitset.Word {
    if bit >= 64 { return self }
    let below: UInt = (1 &<< UInt(bitPattern: bit)) &- 1
    return _UnsafeBitset.Word(value & below)
  }
  /// The members strictly above `bit`.
  @inlinable @inline(__always)
  internal func intersecting(elementsAbove bit: Int) -> _UnsafeBitset.Word {
    if bit >= 63 { return .empty }
    let atOrBelow: UInt = (2 &<< UInt(bitPattern: bit)) &- 1
    return _UnsafeBitset.Word(value & ~atOrBelow)
  }

  /// Removes and returns the smallest member.
  @inlinable @inline(__always)
  internal mutating func next() -> Int? {
    if value == 0 { return nil }
    let bit = value.trailingZeroBitCount
    value &= value &- 1
    return bit
  }
}

// ---- the hash table ----------------------------------------------------------------------

@usableFromInline @frozen
internal struct _HashTable {
  @usableFromInline internal typealias Word = _UnsafeBitset.Word

  @usableFromInline internal var words: UnsafeMutablePointer<Word>
  @usableFromInline internal let bucketMask: Int

  @inlinable @inline(__always)
  internal init(words: UnsafeMutablePointer<Word>, bucketCount: Int) {
    self.words = words
    self.bucketMask = bucketCount &- 1
  }

  @inlinable internal var bucketCount: Int {
    @inline(__always) get { return bucketMask &+ 1 }
  }
  @inlinable internal var wordCount: Int {
    @inline(__always) get { return _UnsafeBitset.wordCount(forCapacity: bucketCount) }
  }
  @inlinable internal var bitset: _UnsafeBitset {
    get { return _UnsafeBitset(words: words, wordCount: wordCount) }
  }
}

extension _HashTable {
  /// The highest fraction of buckets that may be occupied.
  @inlinable internal static var maxLoadFactor: Double {
    @inline(__always) get { return 3.0 / 4.0 }
  }

  /// Number of buckets a table must have to hold `capacity` elements.
  internal static func capacity(forScale scale: Int8) -> Int {
    let bucketCount = 1 &<< Int(scale)
    return bucketCount &* 3 / 4
  }

  /// The smallest scale whose table holds `capacity` elements below the
  /// maximum load factor (at least one word's worth of buckets once the
  /// table is real, as with Apple's).
  internal static func scale(forCapacity capacity: Int) -> Int8 {
    let capacity = capacity > 1 ? capacity : 1
    var scale = 0
    while (1 &<< scale) &* 3 / 4 < capacity {
      scale &+= 1
    }
    return Int8(truncatingIfNeeded: scale)
  }

  /// The per-storage hash seed. A new table gets a fresh seed, so that
  /// iteration orders differ between tables and copying elements from one
  /// table into another never meets its own probe sequence (which would make
  /// insertion quadratic). With deterministic hashing the seed only depends
  /// on the scale.
  internal static func hashSeed(for object: AnyObject, scale: Int8) -> Int {
    if Hasher._isDeterministic { return Int(scale) }
    return Int(Builtin.ptrtoint_Word(Builtin.bridgeToRawPointer(object)))
  }

  /// The age of new storage: anything that differs between storages, so
  /// an index of one table is not mistaken for an index of another.
  internal static func initialAge(for object: AnyObject) -> Int32 {
    let address = UInt(Builtin.ptrtoint_Word(Builtin.bridgeToRawPointer(object)))
    return Int32(truncatingIfNeeded: (address &>> 4) ^ (address &>> 32))
  }
}

extension _HashTable {
  @usableFromInline @frozen
  internal struct Bucket {
    @usableFromInline internal var offset: Int

    @inlinable @inline(__always)
    internal init(offset: Int) {
      self.offset = offset
    }
    @inlinable @inline(__always)
    internal init(word: Int, bit: Int) {
      self.offset = _UnsafeBitset.join(word: word, bit: bit)
    }

    @inlinable internal var word: Int {
      @inline(__always) get { return _UnsafeBitset.word(for: offset) }
    }
    @inlinable internal var bit: Int {
      @inline(__always) get { return _UnsafeBitset.bit(for: offset) }
    }
  }
}

extension _HashTable.Bucket: Equatable {
  @inlinable @inline(__always)
  internal static func == (lhs: _HashTable.Bucket, rhs: _HashTable.Bucket) -> Bool {
    return lhs.offset == rhs.offset
  }
}
extension _HashTable.Bucket: Comparable {
  @inlinable @inline(__always)
  internal static func < (lhs: _HashTable.Bucket, rhs: _HashTable.Bucket) -> Bool {
    return lhs.offset < rhs.offset
  }
}

extension _HashTable {
  /// A bucket together with the age of the table it came from, so indices
  /// from before a mutation are caught.
  @usableFromInline @frozen
  internal struct Index {
    @usableFromInline internal let bucket: Bucket
    @usableFromInline internal let age: Int32

    @inlinable @inline(__always)
    internal init(bucket: Bucket, age: Int32) {
      self.bucket = bucket
      self.age = age
    }
  }
}

extension _HashTable.Index: Equatable {
  @inlinable @inline(__always)
  internal static func == (lhs: _HashTable.Index, rhs: _HashTable.Index) -> Bool {
    _precondition(lhs.age == rhs.age, "Can't compare indices belonging to different collections")
    return lhs.bucket == rhs.bucket
  }
}
extension _HashTable.Index: Comparable {
  @inlinable @inline(__always)
  internal static func < (lhs: _HashTable.Index, rhs: _HashTable.Index) -> Bool {
    _precondition(lhs.age == rhs.age, "Can't compare indices belonging to different collections")
    return lhs.bucket < rhs.bucket
  }
}

extension _HashTable: Sequence {
  @usableFromInline internal typealias Element = Bucket

  /// Visits the occupied buckets in order.
  @usableFromInline @frozen
  internal struct Iterator: IteratorProtocol {
    @usableFromInline internal typealias Element = Bucket
    @usableFromInline internal let hashTable: _HashTable
    @usableFromInline internal var wordIndex: Int
    @usableFromInline internal var word: Word

    @inlinable @inline(__always)
    internal init(_ hashTable: _HashTable) {
      self.hashTable = hashTable
      self.wordIndex = 0
      // Bits past the last bucket of a small table are set: mask them off.
      self.word = hashTable.words[0].intersecting(elementsBelow: hashTable.bucketCount)
    }

    @inlinable @inline(__always)
    internal mutating func next() -> Bucket? {
      while true {
        if let bit = word.next() {
          return Bucket(word: wordIndex, bit: bit)
        }
        if wordIndex &+ 1 >= hashTable.wordCount { return nil }
        wordIndex &+= 1
        word = hashTable.words[wordIndex]
      }
    }
  }

  @inlinable @inline(__always)
  internal func makeIterator() -> Iterator {
    return Iterator(self)
  }
}

extension _HashTable {
  @inlinable @inline(__always)
  internal func isValid(_ bucket: Bucket) -> Bool {
    return bucket.offset >= 0 && bucket.offset < bucketCount
  }
  @inlinable @inline(__always)
  internal func _isOccupied(_ bucket: Bucket) -> Bool {
    return words[bucket.word].uncheckedContains(bucket.bit)
  }
  @inlinable @inline(__always)
  internal func isOccupied(_ bucket: Bucket) -> Bool {
    return isValid(bucket) && _isOccupied(bucket)
  }
  @inlinable @inline(__always)
  internal func checkOccupied(_ bucket: Bucket) {
    _precondition(isOccupied(bucket), "Attempting to access Collection elements using an invalid Index")
  }

  @inlinable @inline(__always)
  internal func _firstOccupiedBucket(fromWord word: Int) -> Bucket {
    var w = word
    let limit = wordCount
    while w < limit {
      // In a small table the bits past the last bucket are set, so the
      // search stops at bucketCount: the end bucket.
      if let bit = words[w].minimum {
        return Bucket(word: w, bit: bit)
      }
      w &+= 1
    }
    return endBucket
  }

  @inlinable
  internal func occupiedBucket(after bucket: Bucket) -> Bucket {
    let w = bucket.word
    if let bit = words[w].intersecting(elementsAbove: bucket.bit).minimum {
      return Bucket(word: w, bit: bit)
    }
    return _firstOccupiedBucket(fromWord: w &+ 1)
  }

  @inlinable internal var startBucket: Bucket {
    return _firstOccupiedBucket(fromWord: 0)
  }
  @inlinable internal var endBucket: Bucket {
    @inline(__always) get { return Bucket(offset: bucketCount) }
  }

  @inlinable @inline(__always)
  internal func idealBucket(forHashValue hashValue: Int) -> Bucket {
    return Bucket(offset: hashValue & bucketMask)
  }
  @inlinable @inline(__always)
  internal func bucket(wrappedAfter bucket: Bucket) -> Bucket {
    return Bucket(offset: (bucket.offset &+ 1) & bucketMask)
  }

  /// The closest hole before `bucket`, wrapping around.
  @inlinable
  internal func previousHole(before bucket: Bucket) -> Bucket {
    var w = bucket.word
    if let bit = words[w].complement.intersecting(elementsBelow: bucket.bit).maximum {
      return Bucket(word: w, bit: bit)
    }
    var wrapped = false
    while true {
      if w == 0 {
        _precondition(!wrapped, "Hash table has no holes")
        wrapped = true
        w = wordCount
      }
      w &-= 1
      if let bit = words[w].complement.maximum {
        return Bucket(word: w, bit: bit)
      }
    }
  }

  /// The first hole at or after `bucket`, wrapping around.
  @inlinable
  internal func nextHole(atOrAfter bucket: Bucket) -> Bucket {
    var w = bucket.word
    if let bit = words[w].complement.subtracting(elementsBelow: bucket.bit).minimum {
      return Bucket(word: w, bit: bit)
    }
    var wrapped = false
    while true {
      w &+= 1
      if w == wordCount {
        _precondition(!wrapped, "Hash table has no holes")
        wrapped = true
        w = 0
      }
      if let bit = words[w].complement.minimum {
        return Bucket(word: w, bit: bit)
      }
    }
  }
}

/// What deletion needs from the table's owner: the hash of a member, and a
/// way to move one.
@usableFromInline
internal protocol _HashTableDelegate {
  func hashValue(at bucket: _HashTable.Bucket) -> Int
  func moveEntry(from source: _HashTable.Bucket, to target: _HashTable.Bucket)
}

extension _HashTable {
  @inlinable @inline(__always)
  internal func copyContents(of other: _HashTable) {
    words.update(from: UnsafePointer(other.words), count: wordCount)
  }

  /// Marks the first hole of `hashValue`'s probe run occupied and returns it.
  @inlinable @inline(__always)
  internal func insertNew(hashValue: Int) -> Bucket {
    let hole = nextHole(atOrAfter: idealBucket(forHashValue: hashValue))
    insert(hole)
    return hole
  }

  @inlinable @inline(__always)
  internal func insert(_ bucket: Bucket) {
    words[bucket.word].uncheckedInsert(bucket.bit)
  }

  /// Empties the table, keeping the out-of-range bits of a small table set.
  @inlinable @inline(__always)
  internal func clear() {
    if bucketCount < Word.capacity {
      words[0] = Word.allBits.subtracting(elementsBelow: bucketCount)
    } else {
      words.update(repeating: .empty, count: wordCount)
    }
  }

  /// Removes the (already deinitialized) member at `bucket`. Later members
  /// of the same probe run whose ideal bucket is not between the hole and
  /// themselves move back into the hole, so lookups never need tombstones.
  @inlinable @inline(__always)
  internal func delete<D: _HashTableDelegate>(at bucket: Bucket, with delegate: D) {
    var hole = bucket
    var candidate = self.bucket(wrappedAfter: hole)
    if !_isOccupied(candidate) {
      words[hole.word].uncheckedRemove(hole.bit)
      return
    }
    // The run containing `bucket` starts after the hole before it.
    let start = self.bucket(wrappedAfter: previousHole(before: bucket))
    while _isOccupied(candidate) {
      let ideal = idealBucket(forHashValue: delegate.hashValue(at: candidate))
      // Can the candidate move to the hole? Only if its ideal bucket is in
      // the cyclic range start...hole.
      let fits: Bool
      if start <= hole {
        fits = ideal >= start && ideal <= hole
      } else {
        fits = ideal >= start || ideal <= hole
      }
      if fits {
        delegate.moveEntry(from: candidate, to: hole)
        hole = candidate
      }
      candidate = self.bucket(wrappedAfter: candidate)
    }
    words[hole.word].uncheckedRemove(hole.bit)
  }
}
