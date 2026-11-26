// Swift Charts: a line chart from Identifiable data drawn through SwiftUI
// into a bitmap; series colours from foregroundStyle(by:); axis modifiers.
import AppKit
import SwiftUI
import Charts

struct Sample: Identifiable {
  let id: Int
  let value: Double
  let series: String
}

@MainActor
func render<V: View>(_ view: V, _ w: Int, _ h: Int) -> (Int, Int) -> UInt32 {
  let space = CGColorSpaceCreateDeviceRGB()
  let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
  let ctx = CGBitmapContextCreate(nil, w, h, 8, 0, space, info)!
  CGContextSetRGBFillColor(ctx, 1, 1, 1, 1)
  CGContextFillRect(ctx, CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: CGFloat(w), height: CGFloat(h))))
  CGContextTranslateCTM(ctx, 0, CGFloat(h))
  CGContextScaleCTM(ctx, 1, -1)
  let v = NSHostingView(rootView: view)
  v.frame = NSMakeRect(0, 0, CGFloat(w), CGFloat(h))
  NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
  v.draw(v.bounds)
  NSGraphicsContext.current = nil
  let data = CGBitmapContextGetData(ctx)!.assumingMemoryBound(to: UInt8.self)
  let stride = CGBitmapContextGetBytesPerRow(ctx)
  return { x, y in
    withExtendedLifetime(ctx) {}
    let p = data + y * stride + x * 4
    return UInt32(p[2]) << 16 | UInt32(p[1]) << 8 | UInt32(p[0])
  }
}

/// Whether a pixel near (x, y) is mostly the given channel.
func near(_ px: (Int, Int) -> UInt32, _ x: Int, _ y: Int, blue: Bool) -> Bool {
  for dy in -2...2 {
    for dx in -2...2 {
      let c = px(x + dx, y + dy)
      let r = Int(c >> 16 & 0xff), g = Int(c >> 8 & 0xff), b = Int(c & 0xff)
      if blue ? (b > 150 && r < 120) : (g > 120 && r < 120 && b < 120) { return true }
    }
  }
  return false
}

@_silgen_name("swl_charts_line") public func line() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    // y = x from 0 to 4: a diagonal from the bottom left to the top right.
    let data = (0..<5).map { Sample(id: $0, value: Double($0), series: "a") }
    let chart = Chart(data) { s in
      LineMark(x: .value("Index", Double(s.id)), y: .value("Value", s.value), series: .value("Series", s.series))
    }
    let px = render(chart.chartXAxis(.hidden), 100, 100)
    if !near(px, 50, 50, blue: true) { bad |= 1 }           // the middle of the line
    if !near(px, 2, 97, blue: true) { bad |= 2 }            // its start
    if px(10, 10) != 0xffffff || px(90, 90) != 0xffffff { bad |= 4 }   // off the line
    // Two series by style: the second takes the second colour (green).
    let two = (0..<4).map { Sample(id: $0, value: 3, series: "b") }
    let styled = Chart(two) { s in
      LineMark(x: .value("Index", Double(s.id)), y: .value("Value", s.value), series: .value("Series", s.series))
        .foregroundStyle(by: .value("Series", s.series))
    }
    let px2 = render(styled, 100, 100)
    if !near(px2, 50, 2, blue: true) { bad |= 8 }           // y = 3 tops the 0...3 scale; the first style is blue
    let labelled = render(chart.chartYAxisLabel("Value"), 140, 100)
    var ink = false
    for x in 0..<40 { for y in 0..<100 where labelled(x, y) != 0xffffff { ink = true } }
    if !ink { bad |= 0x10 }
    return bad
  }
}
