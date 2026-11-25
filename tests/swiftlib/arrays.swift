// Array, ContiguousArray and ArraySlice: representation, literals,
// copy-on-write, mutation, with trivial, class and generic struct elements.
// Class elements report their deinit to the C driver, so leaks and double
// releases show as wrong counts.

@_silgen_name("swa_note_deinit") func noteDeinit(_ v: Int)
@_silgen_name("swa_empty_storage") func emptyStorage() -> UnsafeRawPointer
@_silgen_name("swa_fill") func cFill(_ p: UnsafeMutablePointer<Int>, _ n: Int)
@_silgen_name("swa_sum") func cSum(_ p: UnsafePointer<Int>, _ n: Int) -> Int

final class Token {
  let v: Int
  init(_ v: Int) { self.v = v }
  deinit { noteDeinit(v) }
}

struct Wrapper<T: Equatable>: Equatable {
  var value: T
  var tag: Int8
}

@inline(never) func opaque<T>(_ x: T) -> T { return x }

/// The storage object an array references.
func storage<T>(_ a: [T]) -> UnsafeRawPointer { return unsafeBitCast(a, to: UnsafeRawPointer.self) }

/// Layout: one word, storage {isa, refcount, count, capacity << 1 | flag,
/// elements at 32}, the shared empty storage, ArraySlice's four words.
@_silgen_name("swa_layout") public func layout() -> Int {
  var r = 0
  if MemoryLayout<[Int]>.size == 8 && MemoryLayout<ContiguousArray<Int>>.size == 8
     && MemoryLayout<ArraySlice<Int>>.size == 32 && MemoryLayout<[Int]?>.size == 8 { r |= 1 }
  let empty: [Int] = []
  let e2 = [Token]()
  if storage(empty) == emptyStorage() && storage(e2) == emptyStorage()
     && unsafeBitCast(ContiguousArray<Int8>(), to: UnsafeRawPointer.self) == emptyStorage() { r |= 2 }
  let a = opaque([10, 20, 30])
  let s = storage(a)
  if s.load(fromByteOffset: 16, as: Int.self) == 3
     && s.load(fromByteOffset: 24, as: UInt.self) >> 1 >= 3
     && s.load(fromByteOffset: 24, as: UInt.self) & 1 == 0
     && s.load(fromByteOffset: 32, as: Int.self) == 10
     && s.load(fromByteOffset: 48, as: Int.self) == 30 { r |= 4 }
  // Class elements are "bridged verbatim"; 16-byte aligned elements start
  // at 32 as well.
  let t = opaque([Token(100)])
  if storage(t).load(fromByteOffset: 24, as: UInt.self) & 1 == 1 { r |= 8 }
  // A slice: owner, base address, start, end << 1 | native.
  let slice = a[1..<3]
  let words = unsafeBitCast(slice, to: (UnsafeRawPointer, UnsafeRawPointer, Int, UInt).self)
  if words.0 == s && words.1 == s + 32 && words.2 == 1 && words.3 == (3 << 1 | 1) { r |= 16 }
  return r
}

/// Literals, subscripts, iteration, equality.
@_silgen_name("swa_basics") public func basics() -> Int {
  var r = 0
  let a = [1, 2, 3, 4, 5]
  var sum = 0
  for x in a { sum += x }
  if sum == 15 && a.count == 5 && a[0] == 1 && a[4] == 5 && !a.isEmpty { r |= 1 }
  if a == [1, 2, 3, 4, 5] && a != [1, 2, 3] && [Int]() == [] { r |= 2 }
  let c: ContiguousArray = [7, 8, 9]
  let sl: ArraySlice = [1, 2]
  if c.count == 3 && c[2] == 9 && sl.count == 2 && sl.startIndex == 0 { r |= 4 }
  let w = [Wrapper(value: 1.5, tag: 1), Wrapper(value: 2.5, tag: 2)]
  if w[1].value == 2.5 && w[0].tag == 1 && w == [Wrapper(value: 1.5, tag: 1), Wrapper(value: 2.5, tag: 2)] { r |= 8 }
  let nested = [[1], [2, 3], []]
  if nested[1][1] == 3 && nested[2].isEmpty && nested.count == 3 { r |= 16 }
  if a.first == 1 && a.last == 5 && a.firstIndex(of: 3) == 2 && a.contains(4) { r |= 32 }
  return r
}

/// append, insert, remove, replaceSubrange, reserveCapacity, removeAll.
@_silgen_name("swa_mutation") public func mutation() -> Int {
  var r = 0
  var a: [Int] = []
  for i in 0..<100 { a.append(i) }
  var ok = a.count == 100 && a.capacity >= 100
  for i in 0..<100 where a[i] != i { ok = false }
  if ok { r |= 1 }
  a.insert(-1, at: 0)
  a.insert(1000, at: a.count)
  a.insert(50, at: 3)
  if a.count == 103 && a[0] == -1 && a[1] == 0 && a[3] == 50 && a[4] == 2 && a[102] == 1000 { r |= 2 }
  let removed = a.remove(at: 3)
  let last = a.removeLast()
  let first = a.removeFirst()
  if removed == 50 && last == 1000 && first == -1 && a.count == 100 && a[0] == 0 && a[99] == 99 { r |= 4 }
  a.replaceSubrange(10..<90, with: [7, 7])
  if a.count == 22 && a[9] == 9 && a[10] == 7 && a[11] == 7 && a[12] == 90 { r |= 8 }
  a.replaceSubrange(0..<0, with: 0..<5)   // grow at the front from a range
  if a.count == 27 && a[4] == 4 && a[5] == 0 { r |= 16 }
  a.append(contentsOf: [1, 2, 3])
  a += [4]
  if a.count == 31 && a[30] == 4 && a[27] == 1 { r |= 32 }
  a.reserveCapacity(500)
  let cap = a.capacity
  a.removeAll(keepingCapacity: true)
  if cap >= 500 && a.isEmpty && a.capacity == cap { r |= 64 }
  a.removeAll()
  if a.capacity == 0 && storage(a) == emptyStorage() { r |= 128 }
  var b = [3, 1, 2]
  b.sort()
  b.swapAt(0, 2)
  if b == [3, 2, 1] && b.popLast() == 1 && b == [3, 2] { r |= 256 }
  b[1] += 40
  b[0] = 5
  if b == [5, 42] { r |= 512 }
  let c = [1, 2] + [3]
  if c == [1, 2, 3] && Array(repeating: 9, count: 3) == [9, 9, 9] && Array(1...4) == [1, 2, 3, 4] { r |= 1024 }
  return r
}

/// Copy-on-write: copies share storage until one is mutated.
@_silgen_name("swa_cow") public func cow() -> Int {
  var r = 0
  var a = opaque([1, 2, 3])
  var b = a
  if storage(a) == storage(b) { r |= 1 }
  b[0] = 100
  if storage(a) != storage(b) && a[0] == 1 && b[0] == 100 { r |= 2 }
  let before = storage(b)
  b[1] = 200                                   // unique now: in place
  b.append(4)                                  // may reallocate (capacity)
  b.reserveCapacity(100)
  let grown = storage(b)
  b.append(5)
  if storage(b) == grown && b == [100, 200, 3, 4, 5] && a == [1, 2, 3] && before != storage(a) { r |= 4 }
  var c = ContiguousArray(a)
  let d = c
  c.append(9)
  if d == [1, 2, 3] && c == [1, 2, 3, 9] { r |= 8 }
  // Slices share the array's storage; mutating either copies.
  var s = a[1...]
  if s.startIndex == 1 && s[1] == 2 && s.count == 2 { r |= 16 }
  s[2] = 30
  s.append(40)
  if s == [2, 30, 40] && s.startIndex == 1 && s[3] == 40 && a == [1, 2, 3] { r |= 32 }
  a[0..<2] = [7]                                // replace through a range
  if a == [7, 3] && Array(s) == [2, 30, 40] { r |= 64 }
  // In-place mutation through a buffer pointer.
  a.withUnsafeMutableBufferPointer { buf in buf[0] = 70; buf[1] += 1 }
  let total = a.withUnsafeBufferPointer { $0[0] + $0[1] }
  if total == 74 { r |= 128 }
  return r
}

/// Class elements: every reference released exactly once.
@_silgen_name("swa_objects") public func objects(_ step: Int) -> Int {
  var r = 0
  if step == 1 {
    var a = [Token(1), Token(2)]
    a.append(Token(3))
    var b = a                                   // shared
    b.remove(at: 0)                             // b copies; 1 still in a
    b.append(Token(4))
    if a.count == 3 && b.count == 3 && b[0] === a[1] && b[2].v == 4 { r |= 1 }
    a.removeAll()                               // 1 dies (b never held it)
    return r                                    // the rest die on return
  }
  if step == 2 {
    var a: [Token] = []
    for i in 0..<20 { a.append(Token(5 + (i % 2))) }   // 10 of 5, 10 of 6
    a.replaceSubrange(0..<20, with: [Token(7)])
    if a.count == 1 && a[0].v == 7 { r |= 1 }
    var s = ArraySlice(a)
    s.append(Token(8))
    s.insert(Token(9), at: 0)
    if s.count == 3 && s.first!.v == 9 && s.last!.v == 8 { r |= 2 }
    return r
  }
  return r
}

/// Arrays passed to C as pointers.
@_silgen_name("swa_pointers") public func pointers() -> Int {
  var r = 0
  var a = [Int](repeating: 0, count: 5)
  let copy = a
  cFill(&a, a.count)
  if a == [0, 10, 20, 30, 40] && copy == [0, 0, 0, 0, 0] { r |= 1 }
  if cSum(a, a.count) == 100 { r |= 2 }
  return r
}

/// Generic code over the array types (witness tables at -Onone).
func sumAll<C: Collection>(_ c: C) -> Int where C.Element == Int {
  var s = 0
  for x in c { s += x }
  return s
}
func grow<C: RangeReplaceableCollection>(_ c: inout C, _ x: C.Element) {
  c.append(x)
  c.insert(x, at: c.startIndex)
}
@_silgen_name("swa_generic") public func generic() -> Int {
  var r = 0
  var a = [1, 2, 3]
  var c: ContiguousArray = [4, 5]
  var s = a[1...]
  grow(&a, 10)
  grow(&c, 10)
  grow(&s, 10)
  if sumAll(a) == 26 && sumAll(c) == 29 && sumAll(s) == 25 && s.startIndex == 1 { r |= 1 }
  var h1 = Hasher(), h2 = Hasher()
  h1.combine([1, 2, 3])
  h2.combine(ContiguousArray([1, 2, 3]))
  if h1.finalize() == h2.finalize() && [1, 2].hashValue != [2, 1].hashValue { r |= 2 }
  let m: [[Wrapper<Int>]] = [[Wrapper(value: 1, tag: 0)], []]
  if m == [[Wrapper(value: 1, tag: 0)], []] && m != [[], []] { r |= 4 }
  return r
}
