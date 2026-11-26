// Literals for Foundation's classes, and iterating them in Swift.

extension NSString: ExpressibleByStringLiteral, ExpressibleByUnicodeScalarLiteral,
  ExpressibleByExtendedGraphemeClusterLiteral {
  public required convenience init(stringLiteral value: StaticString) {
    self.init(string: value.description)
  }
  public required convenience init(unicodeScalarLiteral value: StaticString) {
    self.init(string: value.description)
  }
  public required convenience init(extendedGraphemeClusterLiteral value: StaticString) {
    self.init(string: value.description)
  }
}

extension NSNumber: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
  public required convenience init(integerLiteral value: Int) { self.init(value: value) }
  public required convenience init(floatLiteral value: Double) { self.init(value: value) }
  public required convenience init(booleanLiteral value: Bool) { self.init(value: value) }
}

extension NSArray: ExpressibleByArrayLiteral {
  public required convenience init(arrayLiteral elements: Any...) {
    self.init(array: elements)
  }
}
extension NSSet: ExpressibleByArrayLiteral {
  public required convenience init(arrayLiteral elements: Any...) {
    self.init(array: elements)
  }
}
extension NSDictionary: ExpressibleByDictionaryLiteral {
  public required convenience init(dictionaryLiteral elements: (Any, Any)...) {
    var d: [AnyHashable: Any] = [:]
    for (k, v) in elements { d[k as! AnyHashable] = v }
    self.init(dictionary: d)
  }
}

/// Iterates anything with fast enumeration, one object at a time.
public struct NSFastEnumerationIterator: IteratorProtocol {
  let enumerable: NSFastEnumeration
  var state = NSFastEnumerationState(state: 0, itemsPtr: nil, mutationsPtr: nil, extra: (0, 0, 0, 0, 0))
  var buffer = [Unmanaged<AnyObject>?](repeating: nil, count: 16)
  var index = 0
  var count = 0

  public init(_ enumerable: NSFastEnumeration) { self.enumerable = enumerable }

  public mutating func next() -> Any? {
    if index >= count {
      count = buffer.withUnsafeMutableBufferPointer { b in
        b.baseAddress!.withMemoryRebound(to: AnyObject?.self, capacity: 16) { p in
          enumerable.countByEnumerating(with: &state, objects: AutoreleasingUnsafeMutablePointer(p), count: 16)
        }
      }
      index = 0
      if count == 0 { return nil }
    }
    guard let items = state.itemsPtr else { return nil }
    let o = items[index]
    index += 1
    return o
  }
}

extension NSArray: Sequence {
  public func makeIterator() -> NSFastEnumerationIterator { return NSFastEnumerationIterator(self) }
}
extension NSSet: Sequence {
  public func makeIterator() -> NSFastEnumerationIterator { return NSFastEnumerationIterator(self) }
}
extension NSDictionary: Sequence {
  public struct Iterator: IteratorProtocol {
    var keys: NSFastEnumerationIterator
    let dictionary: NSDictionary
    public mutating func next() -> (key: Any, value: Any)? {
      guard let k = keys.next() else { return nil }
      return (k, dictionary.object(forKey: k)!)
    }
  }
  public func makeIterator() -> Iterator { return Iterator(keys: NSFastEnumerationIterator(self), dictionary: self) }
}
