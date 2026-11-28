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

@_silgen_name("swl_cg_members") public func members() -> Int {
  var bad = 0
  let r = CGRect(origin: CGPoint(x: 10, y: 20), size: CGSize(width: 30, height: 40))
  if r.minX != 10 || r.midX != 25 || r.maxX != 40 || r.minY != 20 || r.midY != 40 || r.maxY != 60 { bad |= 1 }
  if r.width != 30 || r.height != 40 || r.isEmpty || r.isNull || r.isInfinite { bad |= 2 }
  if r.insetBy(dx: 5, dy: 5) != CGRect(origin: CGPoint(x: 15, y: 25), size: CGSize(width: 20, height: 30)) { bad |= 4 }
  if r.offsetBy(dx: 1, dy: 2).origin != CGPoint(x: 11, y: 22) { bad |= 8 }
  if !r.contains(CGPoint(x: 11, y: 21)) || r.contains(CGPoint(x: 0, y: 0)) { bad |= 0x10 }
  let s = CGRect(origin: CGPoint(x: 30, y: 50), size: CGSize(width: 30, height: 30))
  if !r.intersects(s) || r.intersection(s).width != 10 || r.union(s).maxX != 60 { bad |= 0x20 }
  if !r.equalTo(r) || CGRect(origin: CGPoint(x: 1, y: 1), size: CGSize(width: -2, height: 2)).standardized.minX != -1 { bad |= 0x40 }
  if r.applying(CGAffineTransformMakeTranslation(1, 1)).minX != 11 || CGPoint(x: 1, y: 2).applying(CGAffineTransformIdentity) != CGPoint(x: 1, y: 2) { bad |= 0x80 }
  let reversed = CGRect(origin: CGPoint(x: 9, y: 8), size: CGSize(width: -6, height: -4))
  if reversed.minX != 3 || reversed.midX != 6 || reversed.maxX != 9 ||
     reversed.minY != 4 || reversed.midY != 6 || reversed.maxY != 8 { bad |= 0x100 }
  return bad
}

/// Geometry prints as Apple's overlay prints it (programs put these in
/// strings and keys).
@_silgen_name("swl_cg_describe") public func describeGeometry() -> Int {
  var bad = 0
  if String(describing: CGPoint(x: 1, y: 2.5)) != "(1.0, 2.5)" { bad |= 1 }
  if String(describing: CGSize(width: 3, height: 4)) != "(3.0, 4.0)" { bad |= 2 }
  if String(describing: CGRect(x: 0, y: 1, width: 2, height: 3)) != "(0.0, 1.0, 2.0, 3.0)" { bad |= 4 }
  if String(describing: CGVector(dx: -1, dy: 0)) != "(-1.0, 0.0)" { bad |= 8 }
  if "\([CGPoint.zero])" != "[(0.0, 0.0)]" { bad |= 0x10 }
  if String(describing: Optional(CGSize.zero)) != "Optional((0.0, 0.0))" { bad |= 0x20 }
  if String(reflecting: CGRect.zero) != "(0.0, 0.0, 0.0, 0.0)" { bad |= 0x40 }
  if String(describing: CGFloat(1.5)) != "1.5" { bad |= 0x80 }
  // the overlay's conveniences
  let r = CGRect(x: 10, y: 20, width: -4, height: 6)
  if r.minX != 6 || r.maxX != 10 || r.width != 4 || r.midY != 23 || r.standardized != CGRect(x: 6, y: 20, width: 4, height: 6) { bad |= 0x100 }
  if CGRect(x: 0.5, y: 0.5, width: 1, height: 1).integral != CGRect(x: 0, y: 0, width: 2, height: 2) { bad |= 0x200 }
  let a = CGRect(x: 0, y: 0, width: 10, height: 10), b = CGRect(x: 5, y: 5, width: 10, height: 10)
  if a.intersection(b) != CGRect(x: 5, y: 5, width: 5, height: 5) || a.union(b) != CGRect(x: 0, y: 0, width: 15, height: 15) { bad |= 0x400 }
  if !a.intersection(CGRect(x: 20, y: 20, width: 1, height: 1)).isNull || a.intersects(CGRect(x: 10, y: 0, width: 1, height: 1)) { bad |= 0x800 }
  if !a.contains(CGPoint(x: 0, y: 9.5)) || a.contains(CGPoint(x: 10, y: 0)) || !a.contains(CGRect(x: 1, y: 1, width: 2, height: 2)) { bad |= 0x1000 }
  if a.insetBy(dx: 2, dy: 3) != CGRect(x: 2, y: 3, width: 6, height: 4) || !a.insetBy(dx: 6, dy: 0).isNull { bad |= 0x2000 }
  if a.offsetBy(dx: 1, dy: -1).origin != CGPoint(x: 1, y: -1) || !CGRect.zero.isEmpty || CGRect.null.union(a) != a { bad |= 0x4000 }
  if a.applying(CGAffineTransform(a: 2, b: 0, c: 0, d: 3, tx: 1, ty: 0)) != CGRect(x: 1, y: 0, width: 20, height: 30) { bad |= 0x8000 }
  return bad
}
