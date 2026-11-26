// Geometry helpers for the engine. Underscored so they never clash with
// the CoreGraphics overlay's own members.

import CoreGraphics

extension CGRect {
  internal static var _zero: CGRect { return CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 0, height: 0)) }
  internal init(_x x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
    self.init(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
  }
  internal var _minX: CGFloat { return origin.x }
  internal var _minY: CGFloat { return origin.y }
  internal var _maxX: CGFloat { return origin.x + size.width }
  internal var _maxY: CGFloat { return origin.y + size.height }
  internal var _width: CGFloat { return size.width }
  internal var _height: CGFloat { return size.height }
  internal func _contains(_ p: CGPoint) -> Bool {
    return p.x >= _minX && p.x < _maxX && p.y >= _minY && p.y < _maxY
  }
}
extension CGSize {
  internal static var _zero: CGSize { return CGSize(width: 0, height: 0) }
}
