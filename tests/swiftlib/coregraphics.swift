// CoreGraphics' Swift API: geometry equality and dictionaries, paths built
// with CGMutablePath's methods, and drawing through CGContext's.
import CoreGraphics

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
  return CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: w, height: h))
}

@_silgen_name("swl_cg_geometry") public func geometry() -> Int {
  var bad = 0
  let r = CGRect(origin: CGPoint(x: 1, y: 2), size: CGSize(width: 3, height: 4))
  if r != CGRect(origin: CGPoint(x: 1, y: 2), size: CGSize(width: 3, height: 4)) { bad |= 1 }
  if r == CGRect(origin: CGPoint(x: 1, y: 2), size: CGSize(width: 3, height: 5)) { bad |= 2 }
  if CGSize(width: 1, height: 2) != CGSize(width: 1, height: 2) { bad |= 4 }
  if CGRect(dictionaryRepresentation: r.dictionaryRepresentation) != r { bad |= 8 }
  if CGPoint(dictionaryRepresentation: CGPoint(x: 5, y: 6).dictionaryRepresentation) != CGPoint(x: 5, y: 6) { bad |= 0x10 }
  if CGSize(dictionaryRepresentation: CGPoint(x: 5, y: 6).dictionaryRepresentation) != nil { bad |= 0x20 }
  if CGAffineTransformIdentity != CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) { bad |= 0x40 }
  if CGPathFillRule.evenOdd.rawValue != 1 || CGPathFillRule(rawValue: 0) != .winding { bad |= 0x80 }
  return bad
}

@_silgen_name("swl_cg_paths") public func paths() -> Int {
  var bad = 0
  let p = CGPathCreateMutable()
  p.move(to: CGPoint(x: 0, y: 0))
  p.addLine(to: CGPoint(x: 10, y: 0))
  p.addCurve(to: CGPoint(x: 10, y: 10), control1: CGPoint(x: 12, y: 3), control2: CGPoint(x: 12, y: 7))
  p.closeSubpath()
  if CGPathGetBoundingBox(p).size.width < 10 { bad |= 1 }
  let q = CGPathCreateMutable()
  q.addRect(rect(0, 0, 4, 4), transform: CGAffineTransformMakeTranslation(20, 20))
  if CGPathGetBoundingBox(q) != rect(20, 20, 4, 4) { bad |= 2 }
  q.addEllipse(in: rect(30, 30, 2, 2))
  q.addRoundedRect(in: rect(40, 0, 5, 5), cornerWidth: 1, cornerHeight: 1)
  q.addArc(center: CGPoint(x: 50, y: 50), radius: 2, startAngle: 0, endAngle: 3.14159, clockwise: false)
  q.addPath(p)
  let box = CGPathGetBoundingBox(q)
  if box.origin.x != 0 || box.origin.y != 0 || box.size.width < 51.9 || box.size.height < 51.9 { bad |= 4 }
  let u = p.union(q)
  if CGPathGetBoundingBox(u) != box { bad |= 8 }
  if !CGPathContainsPoint(u, nil, CGPoint(x: 21, y: 21), false) { bad |= 0x10 }
  return bad
}

@_silgen_name("swl_cg_context") public func context() -> Int {
  var bad = 0
  let space = CGColorSpaceCreateDeviceRGB()
  guard let ctx = CGBitmapContextCreate(nil, 16, 16, 8, 64, space, CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
  // Even-odd: the inner square of two nested ones stays empty.
  CGContextSetRGBFillColor(ctx, 1, 0, 0, 1)
  CGContextAddRect(ctx, rect(0, 0, 16, 16))
  CGContextAddRect(ctx, rect(4, 4, 8, 8))
  ctx.fillPath(using: .evenOdd)
  let px = CGBitmapContextGetData(ctx)!.assumingMemoryBound(to: UInt8.self)
  func alpha(_ x: Int, _ y: Int) -> UInt8 { return px[((15 - y) * 16 + x) * 4 + 3] }
  if alpha(1, 1) != 255 || alpha(8, 8) != 0 { bad |= 2 }
  ctx.textPosition = CGPoint(x: 3, y: 4)
  if ctx.textPosition != CGPoint(x: 3, y: 4) { bad |= 4 }
  ctx.setLineDash(phase: 0, lengths: [2, 2])
  // Clipping to an even-odd ring, then filling everything.
  CGContextClearRect(ctx, rect(0, 0, 16, 16))
  CGContextAddRect(ctx, rect(0, 0, 16, 16))
  CGContextAddRect(ctx, rect(4, 4, 8, 8))
  ctx.clip(using: .evenOdd)
  CGContextFillRect(ctx, rect(0, 0, 16, 16))
  if alpha(1, 1) != 255 || alpha(8, 8) != 0 { bad |= 8 }
  return bad
}
