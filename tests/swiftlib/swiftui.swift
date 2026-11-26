// SwiftUI: views laid out and drawn by NSHostingView into a bitmap (stacks,
// spacers, padding, frames, shapes, backgrounds), and state that survives
// rebuilds and drives them.
import AppKit
import SwiftUI

/// Renders `view` at `w`x`h` and returns a function giving 0xRRGGBB at
/// (x, y), top-left origin.
@MainActor
func render<V: View>(_ view: V, _ w: Int, _ h: Int, host: NSHostingView<V>? = nil) -> (Int, Int) -> UInt32 {
  let space = CGColorSpaceCreateDeviceRGB()
  let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
  let ctx = CGBitmapContextCreate(nil, w, h, 8, 0, space, info)!
  CGContextSetRGBFillColor(ctx, 1, 1, 1, 1)
  CGContextFillRect(ctx, CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: CGFloat(w), height: CGFloat(h))))
  // The hosting view is flipped: draw top-down.
  CGContextTranslateCTM(ctx, 0, CGFloat(h))
  CGContextScaleCTM(ctx, 1, -1)
  let v = host ?? NSHostingView(rootView: view)
  v.frame = NSMakeRect(0, 0, CGFloat(w), CGFloat(h))
  NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
  v.draw(v.bounds)
  NSGraphicsContext.current = nil
  let data = CGBitmapContextGetData(ctx)!.assumingMemoryBound(to: UInt8.self)
  let stride = CGBitmapContextGetBytesPerRow(ctx)
  return { x, y in
    withExtendedLifetime(ctx) {}  // the bitmap lives as long as this reader
    let p = data + y * stride + x * 4
    return UInt32(p[2]) << 16 | UInt32(p[1]) << 8 | UInt32(p[0])
  }
}

let red: UInt32 = 0xff0000, blue: UInt32 = 0x0000ff, green: UInt32 = 0x00ff00, white: UInt32 = 0xffffff

@_silgen_name("swl_swiftui_layout") public func layout() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    // A fixed-size red box above a full-width row: blue, a spacer, green.
    let view = VStack(alignment: .leading, spacing: 0) {
      Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 20, height: 10)
      HStack(spacing: 0) {
        Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 10)
        Spacer()
        Color(.sRGB, red: 0, green: 1, blue: 0).frame(width: 5)
      }.frame(height: 10)
    }.padding(5)
    let px = render(view, 100, 40)
    // The stack is 90x20 after padding, centred: its top-left is (5, 10).
    if getenv("SWIFTUI_DUMP") != nil {
      for y in stride(from: 0, to: 40, by: 3) { print((0..<100).map { x -> String in let c = px(x, y); return c == white ? "." : c == red ? "r" : c == blue ? "b" : c == green ? "g" : "?" }.joined()) }
    }
    if px(7, 12) != red || px(24, 12) != red { bad |= 1 }
    if px(26, 12) != white { bad |= 2 }
    if px(7, 25) != blue || px(14, 25) != blue { bad |= 4 }
    if px(50, 25) != white { bad |= 8 }
    if px(92, 25) != green || px(94, 25) != green || px(96, 25) != white { bad |= 16 }
    if px(2, 2) != white { bad |= 32 }

    // ZStack alignment, a circle, a background and an overlay.
    let z = ZStack(alignment: .topLeading) {
      Rectangle().fill(Color(.sRGB, red: 0, green: 0, blue: 1))
      Circle().fill(Color(.sRGB, red: 1, green: 0, blue: 0)).frame(width: 20, height: 20)
    }
    let pz = render(z, 40, 40)
    if pz(10, 10) != red || pz(1, 1) != blue || pz(30, 30) != blue { bad |= 64 }
    let bg = Color.clear.frame(width: 10, height: 10).background(Color(.sRGB, red: 0, green: 1, blue: 0))
    let pb = render(bg, 30, 30)
    if pb(15, 15) != green || pb(5, 5) != white { bad |= 128 }

    // Text draws glyphs (dark pixels) in its own frame and nowhere else.
    let t = HStack(spacing: 0) {
      Text("Hello").font(.system(size: 20)).foregroundStyle(Color.black)
      Spacer()
    }.frame(width: 120, height: 30)
    let pt = render(t, 120, 30)
    if getenv("SWIFTUI_DUMP") != nil {
      for y in 0..<30 { print((0..<70).map { pt($0, y) & 0xff < 0x80 ? "#" : "." }.joined()) }
    }
    var ink = 0, stray = 0
    for y in 0..<30 {
      for x in 0..<120 where pt(x, y) & 0xff < 0x80 {
        if x < 70 { ink += 1 } else { stray += 1 }
      }
    }
    if ink < 40 || stray != 0 { bad |= 256 }
    return bad
  }
}

final class Counter: ObservableObject {
  @Published var n = 0
}

struct Tapper: View {
  @State var on = false
  var body: some View {
    Button(action: { on.toggle() }) {
      (on ? Color(.sRGB, red: 1, green: 0, blue: 0) : Color(.sRGB, red: 0, green: 0, blue: 1)).frame(width: 30, height: 30)
    }.buttonStyle(.plain)
  }
}

@_silgen_name("swl_swiftui_state") public func state() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    let host = NSHostingView(rootView: Tapper())
    var px = render(Tapper(), 30, 30, host: host)
    if px(15, 15) != blue { bad |= 1 }
    // A click on the button: down and up inside it.
    let at = NSMakePoint(15, 15)
    let down = NSEvent.mouseEvent(with: .leftMouseDown, location: at, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                  context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    let up = NSEvent.mouseEvent(with: .leftMouseUp, location: at, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
    host.mouseDown(with: down)
    host.mouseUp(with: up)
    // State changes rebuild on the next main-queue turn; rebuild now.
    host.rootView = Tapper()
    px = render(Tapper(), 30, 30, host: host)
    if px(15, 15) != red { bad |= 2 }
    return bad
  }
}
