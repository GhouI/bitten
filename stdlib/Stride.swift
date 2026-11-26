// stride(from:to:by:) and stride(from:through:by:), with Apple's frozen
// layouts (programs inline their iteration).

@frozen
public struct StrideToIterator<Element: Strideable>: IteratorProtocol {
  @usableFromInline internal let _start: Element
  @usableFromInline internal let _end: Element
  @usableFromInline internal let _stride: Element.Stride
  @usableFromInline internal var _current: (index: Int?, value: Element)

  @inlinable internal init(_start: Element, end: Element, stride: Element.Stride) {
    self._start = _start
    _end = end
    _stride = stride
    _current = (0, _start)
  }

  @inlinable public mutating func next() -> Element? {
    let result = _current.value
    if _stride > 0 ? result >= _end : result <= _end { return nil }
    _current = Element._step(after: _current, from: _start, by: _stride)
    return result
  }
}

@frozen
public struct StrideTo<Element: Strideable>: Sequence {
  @usableFromInline internal let _start: Element
  @usableFromInline internal let _end: Element
  @usableFromInline internal let _stride: Element.Stride

  @inlinable internal init(_start: Element, end: Element, stride: Element.Stride) {
    _precondition(stride != 0, "Stride size must not be zero")
    self._start = _start
    _end = end
    _stride = stride
  }
  @inlinable public __consuming func makeIterator() -> StrideToIterator<Element> {
    return StrideToIterator(_start: _start, end: _end, stride: _stride)
  }
  @inlinable public var underestimatedCount: Int {
    var it = makeIterator()
    var n = 0
    while it.next() != nil { n += 1 }
    return n
  }
}

@inlinable
public func stride<T>(from start: T, to end: T, by stride: T.Stride) -> StrideTo<T> {
  return StrideTo(_start: start, end: end, stride: stride)
}

@frozen
public struct StrideThroughIterator<Element: Strideable>: IteratorProtocol {
  @usableFromInline internal let _start: Element
  @usableFromInline internal let _end: Element
  @usableFromInline internal let _stride: Element.Stride
  @usableFromInline internal var _current: (index: Int?, value: Element)
  @usableFromInline internal var _didReturnEnd: Bool = false

  @inlinable internal init(_start: Element, end: Element, stride: Element.Stride) {
    self._start = _start
    _end = end
    _stride = stride
    _current = (0, _start)
  }

  @inlinable public mutating func next() -> Element? {
    let result = _current.value
    if _stride > 0 ? result >= _end : result <= _end {
      if result == _end && !_didReturnEnd {
        _didReturnEnd = true
        return result
      }
      return nil
    }
    _current = Element._step(after: _current, from: _start, by: _stride)
    return result
  }
}

@frozen
public struct StrideThrough<Element: Strideable>: Sequence {
  @usableFromInline internal let _start: Element
  @usableFromInline internal let _end: Element
  @usableFromInline internal let _stride: Element.Stride

  @inlinable internal init(_start: Element, end: Element, stride: Element.Stride) {
    _precondition(stride != 0, "Stride size must not be zero")
    self._start = _start
    _end = end
    _stride = stride
  }
  @inlinable public __consuming func makeIterator() -> StrideThroughIterator<Element> {
    return StrideThroughIterator(_start: _start, end: _end, stride: _stride)
  }
}

@inlinable
public func stride<T>(from start: T, through end: T, by stride: T.Stride) -> StrideThrough<T> {
  return StrideThrough(_start: start, end: end, stride: stride)
}
