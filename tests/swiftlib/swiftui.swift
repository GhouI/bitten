// SwiftUI: views laid out and drawn by NSHostingView into a bitmap (stacks,
// spacers, padding, frames, shapes, backgrounds), and state that survives
// rebuilds and drives them.
import AppKit
import Observation
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

/// Counts how often the tree is built: a timeline's content runs each time.
final class Builds {
  var n = 0
  func bump() { n += 1 }
}
struct Ticking: View {
  let builds: Builds
  let paused: Bool
  var body: some View {
    TimelineView(.animation(minimumInterval: 0.01, paused: paused)) { _ -> Color in
      builds.n += 1
      return Color(.sRGB, red: 1, green: 0, blue: 0)
    }
  }
}
struct MaybeTicking: View {
  let builds: Builds
  let show: Bool
  var body: some View {
    let _ = builds.bump()
    if show { Ticking(builds: Builds(), paused: false) } else { Color(.sRGB, red: 0, green: 0, blue: 1) }
  }
}

/// A running timeline rebuilds its content; a paused one, or one that has
/// left the tree, does not.
@_silgen_name("swl_swiftui_timelines") public func timelines() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    @MainActor func spinThenDraw<V: View>(_ host: NSHostingView<V>) {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
      _ = render(host.rootView, 10, 10, host: host)
    }
    // Any host's timer rebuilds every host: the running timeline goes last,
    // after rebuilds earlier tests asked for.
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    let paused = Builds()
    let b = NSHostingView(rootView: Ticking(builds: paused, paused: true))
    _ = render(b.rootView, 10, 10, host: b)
    spinThenDraw(b)
    if paused.n != 1 { bad |= 2 }
    let gone = Builds()
    let c = NSHostingView(rootView: MaybeTicking(builds: gone, show: true))
    _ = render(c.rootView, 10, 10, host: c)
    c.rootView = MaybeTicking(builds: gone, show: false)
    spinThenDraw(c)
    spinThenDraw(c)
    let after = gone.n
    spinThenDraw(c)
    if gone.n != after { bad |= 4 }
    let running = Builds()
    let a = NSHostingView(rootView: Ticking(builds: running, paused: false))
    _ = render(a.rootView, 10, 10, host: a)
    spinThenDraw(a)
    if running.n < 2 { bad |= 1 }
    if getenv("SWIFTUI_DUMP") != nil { print("timelines: running \(running.n) paused \(paused.n) gone \(after) -> \(gone.n)") }
    return bad
  }
}

final class LazyModel {
  var a = 1, b = 2, c = 3
}
struct Big { var a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7 }

@_silgen_name("swl_swiftui_lazy") public func lazyState() -> Int {
  var bad = 0
  // Copies through generic code (an Any box, an array) exercise the
  // storage enum's value witnesses.
  let s = LazyState(wrappedValue: LazyModel())
  let boxed: Any = s
  var copies = [s, s, s]
  copies.append(boxed as! LazyState<LazyModel>)
  if copies[3].wrappedValue.c != 3 { bad |= 1 }
  let big = LazyState(wrappedValue: Big())
  let anyBig: [Any] = [big, big]
  if (anyBig[1] as! LazyState<Big>).wrappedValue.g != 7 { bad |= 2 }
  return bad
}

/// An AppKit view that fills itself red.
final class RedFill: NSView {
  override func draw(_ dirtyRect: NSRect) {
    NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
    NSBezierPath.fill(bounds)
  }
}
struct RedRep: NSViewRepresentable {
  func makeNSView(context: Context) -> RedFill { return RedFill() }
  func updateNSView(_ nsView: RedFill, context: Context) {}
}

@_silgen_name("swl_swiftui_order") public func order() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    // A representable as a background sits below the content, as an
    // overlay above it, whichever order layout reaches them in.
    let below = Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 10, height: 10)
      .background(RedRep().frame(width: 20, height: 20))
    let pb = render(below, 30, 30)
    if pb(15, 15) != blue || pb(7, 7) != red { bad |= 1 }
    let above = Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 20, height: 20)
      .overlay(RedRep().frame(width: 10, height: 10))
    let pa = render(above, 30, 30)
    if pa(15, 15) != red || pa(7, 7) != blue { bad |= 2 }

    // Wrapped text centred through the environment (the key path the
    // program builds from the property descriptor).
    let words = Text("Wide wide wide wide\nx").font(.system(size: 12)).foregroundStyle(Color.black)
      .environment(\.multilineTextAlignment, .center)
    let left = Text("Wide wide wide wide\nx").font(.system(size: 12)).foregroundStyle(Color.black)
    @MainActor func lastLineInk(_ v: some View) -> Int {
      let p = render(v.frame(width: 120, height: 60), 120, 60)
      var rows: [Int] = []
      for y in 0..<60 where (0..<120).contains(where: { p($0, y) & 0xff < 0x80 }) { rows.append(y) }
      guard let last = rows.last else { return -1 }
      return (0..<120).first { p($0, last) & 0xff < 0x80 } ?? -1
    }
    let centred = lastLineInk(words), leading = lastLineInk(left)
    if centred < 0 || leading < 0 || centred <= leading + 10 { bad |= 4 }
    return bad
  }
}

struct RedBackdrop: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.frame(width: 20, height: 20).background(Color(.sRGB, red: 1, green: 0, blue: 0))
  }
}
final class Taps { var n = 0 }
struct Forwarding: PrimitiveButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    Button(configuration).padding(2)
  }
}

@_silgen_name("swl_swiftui_styles") public func styles() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    let taps = Taps()
    let styled = Button(action: { taps.n += 1 }) { Color.clear.frame(width: 4, height: 4) }.buttonStyle(RedBackdrop())
    let host = NSHostingView(rootView: styled)
    let p = render(styled, 30, 30, host: host)
    if p(15, 15) != red || p(2, 2) != white { bad |= 1 }
    let at = NSMakePoint(15, 15)
    host.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: at, modifierFlags: [], timestamp: 0,
                                            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
    host.mouseUp(with: NSEvent.mouseEvent(with: .leftMouseUp, location: at, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!)
    if taps.n != 1 { bad |= 2 }
    let forwarded = Button(action: { taps.n += 10 }) { Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 10, height: 10) }
      .buttonStyle(Forwarding())
    let host2 = NSHostingView(rootView: forwarded)
    let q = render(forwarded, 40, 40, host: host2)
    if q(20, 20) != blue { bad |= 4 }
    let mid = NSMakePoint(20, 20)
    host2.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: mid, modifierFlags: [], timestamp: 0,
                                             windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
    host2.mouseUp(with: NSEvent.mouseEvent(with: .leftMouseUp, location: mid, modifierFlags: [], timestamp: 0,
                                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!)
    if taps.n != 11 { bad |= 8 }
    return bad
  }
}

/// A click whose press and release straddle a rebuild of the tree (state
/// changing while the button is held) still taps the button.
@_silgen_name("swl_swiftui_pressrebuild") public func pressRebuild() -> Int {
  return MainActor.assumeIsolated {
    let taps = Taps()
    let view = Button(action: { taps.n += 1 }) { Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 10, height: 10) }
      .buttonStyle(.plain)
    let host = NSHostingView(rootView: view)
    _ = render(view, 30, 30, host: host)
    let at = NSMakePoint(15, 15)
    host.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: at, modifierFlags: [], timestamp: 0,
                                            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
    host.rootView = view
    _ = render(view, 30, 30, host: host)
    host.mouseUp(with: NSEvent.mouseEvent(with: .leftMouseUp, location: at, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!)
    return taps.n == 1 ? 0 : 1
  }
}

@_silgen_name("swl_swiftui_hits") public func hits() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    let taps = Taps()
    // A button in front of a background representable takes the click; a
    // container's tap gesture does not swallow its button's.
    let v = Button(action: { taps.n += 1 }) { Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 10, height: 10) }
      .buttonStyle(.plain)
      .frame(width: 30, height: 30)
      .background(RedRep())
      .onTapGesture { taps.n += 100 }
    let host = NSHostingView(rootView: v)
    _ = render(v, 30, 30, host: host)
    if host.hitTest(NSMakePoint(15, 15)) !== host { bad |= 1 }
    if !(host.hitTest(NSMakePoint(2, 2)) is RedFill) && host.hitTest(NSMakePoint(2, 2)) !== host { bad |= 2 }
    let at = NSMakePoint(15, 15)
    host.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: at, modifierFlags: [], timestamp: 0,
                                            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
    host.mouseUp(with: NSEvent.mouseEvent(with: .leftMouseUp, location: at, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!)
    if taps.n != 1 { bad |= 4 }
    return bad
  }
}

/// Scroll content is placed at its ideal size: a stack of two sections that
/// both have a full-width header gives each section its ideal width (the
/// header used to swallow the extra and push the rest out of view).
@_silgen_name("swl_swiftui_scrollstack") public func scrollStack() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    func section(_ c: Color, _ w: CGFloat) -> some View {
      VStack(alignment: .leading, spacing: 0) {
        Color.clear.frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
        c.frame(width: w, height: 10)
      }
    }
    let view = ScrollView(.horizontal) {
      HStack(spacing: 0) {
        section(Color(.sRGB, red: 1, green: 0, blue: 0), 10)
        section(Color(.sRGB, red: 0, green: 0, blue: 1), 30)
      }
    }.frame(width: 30, height: 11)
    let px = render(view, 30, 11)
    if px(1, 5) != red || px(8, 5) != red { bad |= 1 }
    if px(12, 5) != blue || px(28, 5) != blue { bad |= 2 }
    return bad
  }
}

/// `.aspectRatio(_:contentMode: .fit)` offered only a width (as a stack
/// offers its children) takes that width and the height the ratio gives.
@_silgen_name("swl_swiftui_aspect") public func aspect() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    let view = VStack(spacing: 0) {
      Color(.sRGB, red: 1, green: 0, blue: 0).aspectRatio(1, contentMode: .fit)
    }.frame(width: 20)
    let px = render(view, 20, 30)
    // 20x20, centred vertically: rows 5..<25.
    if px(1, 6) != red || px(18, 23) != red { bad |= 1 }
    if px(1, 2) != white || px(1, 27) != white { bad |= 2 }
    return bad
  }
}

/// `safeAreaInset(edge:)` puts its content on that edge, the view in the
/// rest (built as Apple's ModifiedContent<_, _InsetViewModifier>).
@_silgen_name("swl_swiftui_inset") public func inset() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    let top = Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 20, height: 10)
      .safeAreaInset(edge: .top, spacing: 0) { Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 20, height: 10) }
    var px = render(top, 20, 20)
    if px(10, 3) != blue || px(10, 15) != red { bad |= 1 }
    let lead = Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 10, height: 20)
      .safeAreaInset(edge: .leading, spacing: 0) { Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 10, height: 20) }
    px = render(lead, 20, 20)
    if px(3, 10) != blue || px(15, 10) != red { bad |= 2 }
    return bad
  }
}

/// `labelsHidden()` leaves controls' labels out: a hidden toggle label draws
/// no text.
@_silgen_name("swl_swiftui_labels") public func labels() -> Int {
  return MainActor.assumeIsolated {
    @MainActor func ink(_ v: some View) -> Int {
      let px = render(v.frame(width: 200, height: 30, alignment: .leading), 200, 30)
      var n = 0
      for y in 0..<30 { for x in 40..<200 where px(x, y) != white { n += 1 } }
      return n
    }
    var bad = 0
    let shown = ink(Toggle("WWWWWWWWWW", isOn: .constant(false)))
    let hidden = ink(Toggle("WWWWWWWWWW", isOn: .constant(false)).labelsHidden())
    if shown == 0 { bad |= 1 }
    if hidden != 0 { bad |= 2 }
    return bad
  }
}

/// `onHover` and `onContinuousHover` hear the pointer enter, move in and
/// leave their region.
@_silgen_name("swl_swiftui_hover") public func hover() -> Int {
  return MainActor.assumeIsolated {
    final class Log { var events: [String] = [] }
    let log = Log()
    let view = HStack(spacing: 0) {
      Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 20, height: 20).onHover { log.events.append("hover \($0)") }
      Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 20, height: 20).onContinuousHover { phase in
        switch phase {
        case .active(let p): log.events.append("at \(Int(p.x)),\(Int(p.y))")
        case .ended: log.events.append("ended")
        }
      }
    }
    let host = NSHostingView(rootView: view)
    _ = render(view, 40, 20, host: host)
    func move(_ x: CGFloat, _ y: CGFloat) {
      host.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: NSMakePoint(x, y), modifierFlags: [],
                                               timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                               clickCount: 0, pressure: 0)!)
    }
    move(5, 5)
    move(8, 5)
    move(25, 5)
    host.mouseExited(with: NSEvent.mouseEvent(with: .mouseExited, location: NSMakePoint(50, 5), modifierFlags: [],
                                              timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                              clickCount: 0, pressure: 0)!)
    let want = ["hover true", "hover false", "at 5,15", "ended"]  // window points run up; the host is flipped
    if log.events != want {
      print("hover events: \(log.events)")
      return 1
    }
    return 0
  }
}

/// A switch draws a white knob at the end it is set to; a checkbox that is
/// on draws a white check in its box.
@_silgen_name("swl_swiftui_togglemarks") public func togglemarks() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    @MainActor func mark(_ on: Bool, _ style: some ToggleStyle) -> (Int, Int) -> UInt32 {
      return render(Toggle("", isOn: .constant(on)).labelsHidden().toggleStyle(style).frame(width: 40, height: 20), 40, 20)
    }
    // The 32x16 switch sits centred: x 4...36, y 2...18; its knob is 14 across.
    var px = mark(true, .switch)
    if px(28, 10) != white || px(10, 10) == white { bad |= 1 }
    px = mark(false, .switch)
    if px(12, 10) != white || px(28, 10) == white { bad |= 2 }
    // The 14x14 checkbox: x 13...27, y 3...17; the check crosses near its middle.
    px = mark(true, .checkbox)
    var whiteInBox = 0
    for y in 5..<15 { for x in 15..<25 where px(x, y) == white { whiteInBox += 1 } }
    if whiteInBox == 0 { bad |= 4 }
    return bad
  }
}

/// Buttons whose labels take all the room offered (`.frame(maxWidth:
/// .infinity, maxHeight: .infinity)`) share a fixed frame's height between
/// rows, as their widths are shared within a row.
@_silgen_name("swl_swiftui_flexrows") public func flexRows() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    @MainActor func cell(_ on: Bool) -> some View {
      Button(action: {}) {
        Capsule().fill(on ? Color(.sRGB, red: 1, green: 0, blue: 0) : Color(.sRGB, red: 0, green: 0, blue: 1))
          .frame(width: 28, height: 14)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }.buttonStyle(.plain)
    }
    let grid = VStack(spacing: 0) {
      HStack(spacing: 0) { cell(false); cell(false); cell(false) }
      HStack(spacing: 0) { cell(false); cell(false); cell(true) }
    }.padding(5).frame(width: 112, height: 64)
    let px = render(grid, 112, 64)
    // Two rows of 27 between 5-point insets: the lower row's capsules are
    // centred at y 45.5, the upper's at 18.5.
    if px(84, 45) != red { bad |= 1 }
    if px(84, 18) != blue { bad |= 2 }
    if px(84, 32) != white { bad |= 4 }
    return bad
  }
}

/// A frame with only a minimum width takes a smaller proposal than its
/// content (SwiftUI's flexible frame), so a stack short of room shrinks it.
@_silgen_name("swl_swiftui_minframe") public func minFrame() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    let row = HStack(spacing: 0) {
      Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 60).frame(minWidth: 0)
      Color(.sRGB, red: 0, green: 0, blue: 1).frame(maxWidth: .infinity)
    }.frame(width: 40, height: 10)
    let px = render(row, 40, 10)
    // Each gets half: red to 20, blue after it.
    if px(10, 5) != red { bad |= 1 }
    if px(30, 5) != blue { bad |= 2 }
    return bad
  }
}

final class StoreCount {
  var n = 0
  func bump() { n += 1 }
}
/// An observable model, as the @Observable macro writes one.
final class Shown: Observable {
  let registrar = ObservationRegistrar()
  var _value = 0
  var value: Int {
    get { registrar.access(self, keyPath: \.value); return _value }
    set { registrar.withMutation(of: self, keyPath: \.value) { _value = newValue } }
  }
}
/// Stores what it is given when created (as a view's initialiser storing
/// into a model does), and shows the model.
struct Storing: View {
  let model: Shown
  let builds: StoreCount
  init(model: Shown, builds: StoreCount) {
    self.model = model
    self.builds = builds
    model.value = 0
  }
  var body: some View {
    let _ = builds.bump()
    Text("\(model.value)")
  }
}
struct StoringParent: View {
  let model: Shown
  let builds: StoreCount
  var body: some View { Storing(model: model, builds: builds) }
}

/// A write made while the tree is rebuilt, to a property the previous tree
/// read, does not make the new tree rebuild again (and again).
@_silgen_name("swl_swiftui_rebuildwrites") public func rebuildWrites() -> Int {
  return MainActor.assumeIsolated {
    let model = Shown(), builds = StoreCount()
    let view = StoringParent(model: model, builds: builds)
    let host = NSHostingView(rootView: view)
    @MainActor func spinThenDraw() {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
      _ = render(view, 20, 20, host: host)
    }
    spinThenDraw()
    host.rootView = view
    spinThenDraw()
    let settled = builds.n
    spinThenDraw()
    spinThenDraw()
    if builds.n != settled { return 1 }
    // A write from outside the build still rebuilds.
    model.value = 1
    spinThenDraw()
    return builds.n > settled ? 0 : 2
  }
}

/// Shows a counter kept in @State and hands out a binding to it.
struct Counting: View {
  @State var n = 0
  let builds: StoreCount
  let expose: (Binding<Int>) -> Void
  var body: some View {
    let _ = builds.bump()
    let _ = expose($n)
    Text("\(n)")
  }
}

/// A state change rebuilds only the host whose graph keeps the state, and
/// storing the value already there rebuilds nothing.
@_silgen_name("swl_swiftui_statescope") public func stateScope() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    let aBuilds = StoreCount(), bBuilds = StoreCount()
    var binding: Binding<Int>?
    let a = Counting(builds: aBuilds, expose: { binding = $0 })
    let b = Counting(builds: bBuilds, expose: { _ in })
    let hostA = NSHostingView(rootView: a), hostB = NSHostingView(rootView: b)
    @MainActor func settle() {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
      _ = render(a, 20, 20, host: hostA)
      _ = render(b, 20, 20, host: hostB)
    }
    settle()
    let a0 = aBuilds.n, b0 = bBuilds.n
    binding?.wrappedValue = 1
    settle()
    if aBuilds.n == a0 { bad |= 1 }   // its own host rebuilt
    if bBuilds.n != b0 { bad |= 2 }   // the other did not
    let a1 = aBuilds.n
    binding?.wrappedValue = 1
    settle()
    if aBuilds.n != a1 { bad |= 4 }   // the same value: no rebuild
    return bad
  }
}

/// A sheet is a window of its own over the presenting window, as large as
/// its content, and goes when it is no longer presented.
@_silgen_name("swl_swiftui_sheetwindow") public func sheetWindow() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    @MainActor func page(_ shown: Bool) -> some View {
      Color.white.frame(width: 300, height: 200)
        .sheet(isPresented: .constant(shown)) { Color.red.frame(width: 120, height: 80) }
    }
    let host = NSHostingView(rootView: AnyView(page(true)))
    let w = NSWindow(contentRect: NSMakeRect(0, 0, 300, 200), styleMask: [.titled], backing: .buffered, defer: false)
    w.contentView = host
    _ = render(AnyView(page(true)), 300, 200, host: host)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    guard let sheet = w.attachedSheet else { return 1 }
    if sheet.frame.size.width != 120 || sheet.frame.size.height != 80 { bad |= 2 }
    host.rootView = AnyView(page(false))
    _ = render(AnyView(page(false)), 300, 200, host: host)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    if w.attachedSheet != nil { bad |= 4 }
    w.close()
    return bad
  }
}

/// GridRow stores its alignment and its content as two fields, in that
/// order (programs read the content's offset from the field offsets).
@_silgen_name("swl_swiftui_gridrowfields") public func gridRowFields() -> Int {
  return MainActor.assumeIsolated {
    let row = GridRow(alignment: .top) { Text("a") }
    let labels = Mirror(reflecting: row).children.map { $0.label ?? "" }
    return labels == ["alignment", "content"] ? 0 : 1
  }
}

/// A grid cell spanning columns and unsized horizontally doesn't widen the
/// first column: the next row's cells sit side by side.
@_silgen_name("swl_swiftui_gridspan") public func gridSpan() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    let grid = Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
      GridRow {
        Color(.sRGB, red: 1, green: 0, blue: 0).frame(maxWidth: .infinity).frame(height: 10)
          .gridCellColumns(2).gridCellUnsizedAxes(.horizontal)
      }
      GridRow {
        Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 20, height: 10)
        Color(.sRGB, red: 0, green: 1, blue: 0).frame(width: 20, height: 10)
      }
    }
    let px = render(grid.frame(width: 40, height: 20, alignment: .topLeading), 40, 20)
    if px(30, 15) != 0x00FF00 { bad |= 1 }   // the second column right after the first
    if px(5, 15) != blue { bad |= 2 }
    if px(35, 5) != red { bad |= 4 }         // the header spans both columns
    return bad
  }
}

/// A representable under allowsHitTesting(false) gets no clicks: hit
/// testing where nothing else is finds the hosting view, not the AppKit view.
@_silgen_name("swl_swiftui_nohitrep") public func noHitRep() -> Int {
  return MainActor.assumeIsolated {
    let view = Color.clear.frame(width: 40, height: 40).overlay(RedRep().allowsHitTesting(false))
    let host = NSHostingView(rootView: view)
    _ = render(view, 40, 40, host: host)
    let hit = host.hitTest(NSMakePoint(20, 20))
    if hit is RedFill { return 1 }
    return hit === host ? 0 : 2
  }
}

/// Text too wide for its frame is cut with an ellipsis and drawn inside
/// the frame.
@_silgen_name("swl_swiftui_truncate") public func truncate() -> Int {
  return MainActor.assumeIsolated {
    let view = HStack(spacing: 0) {
      Text("WWWWWWWWWWWWWWWWWWWWWWWW").font(.system(size: 12)).foregroundStyle(Color.black)
        .lineLimit(1).truncationMode(.middle).frame(width: 60)
      Spacer(minLength: 0)
    }.frame(width: 120, height: 20)
    let px = render(view, 120, 20)
    var outside = 0
    for x in 64..<120 { for y in 0..<20 where px(x, y) != white { outside += 1 } }
    var inside = 0
    for x in 0..<60 { for y in 0..<20 where px(x, y) != white { inside += 1 } }
    return (outside == 0 ? 0 : 1) | (inside > 0 ? 0 : 2)
  }
}

/// A destinationOut blend erases what is under it, within its compositing
/// group only (the white underneath shows through, the red around stays).
@_silgen_name("swl_swiftui_blendout") public func blendOut() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    let view = ZStack {
      Color(.sRGB, red: 1, green: 0, blue: 0)
      Color.black.frame(width: 10, height: 10).blendMode(.destinationOut)
    }.compositingGroup().frame(width: 30, height: 30)
    let px = render(view, 30, 30)
    if px(15, 15) != white { bad |= 1 }
    if px(2, 2) != red { bad |= 2 }
    return bad
  }
}

/// A canvas draws in a layer of its own: a destinationOut fill erases only
/// the canvas's own drawing, so the view under it shows through the hole.
@_silgen_name("swl_swiftui_canvashole") public func canvasHole() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    let view = ZStack {
      Color(.sRGB, red: 0, green: 0, blue: 1)
      Canvas { g, size in
        g.fill(Path(CGRect(origin: CGPoint(x: 0, y: 0), size: size)), with: .color(Color(.sRGB, red: 1, green: 0, blue: 0)))
        g.blendMode = .destinationOut
        g.fill(Path(CGRect(origin: CGPoint(x: 10, y: 10), size: CGSize(width: 10, height: 10))), with: .color(.black))
      }
    }.frame(width: 30, height: 30)
    let px = render(view, 30, 30)
    if px(15, 15) != blue { bad |= 1 }   // the view under the hole
    if px(2, 2) != red { bad |= 2 }
    return bad
  }
}

/// In a stack short of room, a spacer keeps only its minimum length while
/// a flexible view takes the rest (not half).
@_silgen_name("swl_swiftui_spacershort") public func spacerShort() -> Int {
  return MainActor.assumeIsolated {
    let row = HStack(spacing: 0) {
      Color(.sRGB, red: 0, green: 0, blue: 1).frame(minWidth: 0, idealWidth: 500, maxWidth: 500)
      Spacer(minLength: 8)
      Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 20)
    }.frame(width: 200, height: 10)
    let px = render(row, 200, 10)
    // Blue to 172, the spacer's 8, then red.
    var bad = 0
    if px(150, 5) != blue { bad |= 1 }
    if px(176, 5) != white { bad |= 2 }
    if px(190, 5) != red { bad |= 4 }
    return bad
  }
}

/// A button's keyboard shortcut performs it: Escape a .cancelAction
/// button, a command key a ⌘ shortcut; a disabled one doesn't.
@_silgen_name("swl_swiftui_shortcuts") public func shortcuts() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    var cancelled = 0, saved = 0, off = 0
    let view = VStack {
      Button("Cancel") { cancelled += 1 }.keyboardShortcut(.cancelAction)
      Button("Save") { saved += 1 }.keyboardShortcut("s")
      Button("Off") { off += 1 }.keyboardShortcut("o").disabled(true)
    }
    let host = NSHostingView(rootView: view)
    _ = render(view, 100, 80, host: host)
    func key(_ c: String, _ code: UInt16, _ mods: NSEvent.ModifierFlags) -> NSEvent {
      return NSEvent.keyEvent(with: .keyDown, location: NSPoint(x: 0, y: 0), modifierFlags: mods, timestamp: 0, windowNumber: 0,
                              context: nil, characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: code)!
    }
    if !host.performKeyEquivalent(with: key("\u{1B}", 53, [])) || cancelled != 1 { bad |= 1 }
    if !host.performKeyEquivalent(with: key("s", 1, .command)) || saved != 1 { bad |= 2 }
    if host.performKeyEquivalent(with: key("s", 1, [])) || saved != 1 { bad |= 4 }   /* without ⌘: not it */
    if host.performKeyEquivalent(with: key("o", 31, .command)) || off != 0 { bad |= 8 }
    return bad
  }
}

/// A click on a switch or a checkbox flips it.
@_silgen_name("swl_swiftui_toggleclick") public func toggleClick() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    for (i, style) in [AnyToggleStyleBox(.switch), AnyToggleStyleBox(.checkbox)].enumerated() {
      var on = false
      let binding = Binding(get: { on }, set: { on = $0 })
      let view = style.apply(Toggle("", isOn: binding).labelsHidden()).frame(width: 40, height: 20)
      let host = NSHostingView(rootView: view)
      _ = render(view, 40, 20, host: host)
      let at = NSMakePoint(20, 10)
      for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        if type == .leftMouseDown { host.mouseDown(with: e) } else { host.mouseUp(with: e) }
      }
      if !on { bad |= 1 << i }
    }
    return bad
  }
}
/// A toggle style chosen at run time.
struct AnyToggleStyleBox {
  let isSwitch: Bool
  init(_ s: SwitchToggleStyle) { isSwitch = true }
  init(_ s: CheckboxToggleStyle) { isSwitch = false }
  @MainActor func apply<V: View>(_ v: V) -> AnyView {
    return isSwitch ? AnyView(v.toggleStyle(.switch)) : AnyView(v.toggleStyle(.checkbox))
  }
}

/// A hosting view that goes away takes its representables' coordinators
/// (and so whatever they hold) with it, and SwiftUI tells the
/// representable first (dismantleNSView).
nonisolated(unsafe) var _leakFreed = 0, _leakDismantled = 0
final class _LeakCoordinator: NSObject, NSTextFieldDelegate {
  var parent: _LeakField
  init(_ p: _LeakField) { parent = p }
  deinit { _leakFreed += 1 }
}
struct _LeakField: NSViewRepresentable {
  @Binding var text: String
  func makeCoordinator() -> _LeakCoordinator { _LeakCoordinator(self) }
  func makeNSView(context: Context) -> NSTextField {
    let f = NSTextField(frame: NSMakeRect(0, 0, 80, 20))
    f.stringValue = text
    f.delegate = context.coordinator
    return f
  }
  func updateNSView(_ v: NSTextField, context: Context) { context.coordinator.parent = self }
  static func dismantleNSView(_ v: NSTextField, coordinator: _LeakCoordinator) { _leakDismantled += 1 }
}
struct _LeakPage: View {
  @State var name = "a"
  @State var other = "b"
  var body: some View {
    VStack {
      _LeakField(text: $name)
      _LeakField(text: $other).onAppear {}
      Text(name)
    }
  }
}
@_silgen_name("swl_swiftui_leakfree") public func leakFree() -> Int {
  return MainActor.assumeIsolated {
    _leakFreed = 0
    _leakDismantled = 0
    do {
      let host = NSHostingView(rootView: _LeakPage())
      _ = render(_LeakPage(), 100, 60, host: host)
      _ = render(_LeakPage(), 100, 60, host: host)
    }
    for _ in 0..<3 { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
    var bad = (_leakFreed == 2 ? 0 : 1) | (_leakDismantled == 2 ? 0 : 2)
    // Leaving the tree while the host stays: dismantled once, and a new
    // one is made when it comes back.
    _leakFreed = 0
    _leakDismantled = 0
    let host = NSHostingView(rootView: _LeakToggle(show: true))
    @MainActor func frame(_ show: Bool) {
      host.rootView = _LeakToggle(show: show)
      _ = render(host.rootView, 100, 60, host: host)
      for _ in 0..<3 { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
    }
    frame(true)
    frame(false)
    if _leakDismantled != 1 || _leakFreed != 1 { bad |= 4 }
    frame(true)
    frame(true)
    if _leakDismantled != 1 { bad |= 8 }
    // A host whose tree holds a menu picker is freed too (the picker's
    // button must not keep its own host).
    weak var gone: NSHostingView<_LeakPicker>?
    do {
      let h = NSHostingView(rootView: _LeakPicker())
      _ = render(_LeakPicker(), 100, 60, host: h)
      gone = h
    }
    for _ in 0..<3 { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
    if gone != nil { bad |= 16 }
    return bad
  }
}
struct _LeakPicker: View {
  @State var pick = 1
  var body: some View {
    Picker("P", selection: $pick) { Text("One").tag(1); Text("Two").tag(2) }
  }
}
struct _LeakToggle: View {
  var show: Bool
  @State var text = "t"
  var body: some View {
    VStack {
      if show { _LeakField(text: $text) }
      Text("x")
    }
  }
}

/// A background with several views layers them as a ZStack, centered in
/// the content's frame (not one under the other).
@_silgen_name("swl_swiftui_bglayers") public func bgLayers() -> Int {
  return MainActor.assumeIsolated {
    let view = Color.clear.frame(width: 100, height: 50).background {
      Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 40, height: 40)
      Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 10, height: 10)
    }
    let px = render(view, 100, 50)
    var bad = 0
    if px(50, 25) != blue { bad |= 1 }   // the small one on top, centered
    if px(35, 10) != red { bad |= 2 }
    if px(50, 2) != white { bad |= 4 }   // the large one centered too
    return bad
  }
}

/// A custom view gives the container around it its body's views: two
/// colours in a view's body are two children of the VStack (no inner
/// stack and spacing), and a picker's options can come from a view.
struct _TwoRows: View {
  var body: some View {
    Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 20, height: 10)
    Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 20, height: 10)
  }
}
struct _PickOptions: View {
  var body: some View {
    ForEach([1, 2], id: \.self) { i in
      (i == 1 ? Color(.sRGB, red: 1, green: 0, blue: 0) : Color(.sRGB, red: 0, green: 0, blue: 1))
        .frame(width: 10, height: 10).tag(i)
    }
  }
}
@_silgen_name("swl_swiftui_viewlists") public func viewLists() -> Int {
  return MainActor.assumeIsolated {
    var bad = 0
    let stack = VStack(spacing: 0) { _TwoRows() }.frame(width: 20, height: 20)
    let px = render(stack, 20, 20)
    if px(10, 5) != red { bad |= 1 }
    if px(10, 15) != blue { bad |= 2 }
    // The picker shows the chosen option only (blue), not every option.
    let picker = Picker(selection: .constant(2), content: { _PickOptions() }, label: { EmptyView() })
      .frame(width: 80, height: 30)
    let pp = render(picker, 80, 30)
    var reds = 0, blues = 0
    for x in 0..<80 { for y in 0..<30 { if pp(x, y) == red { reds += 1 }; if pp(x, y) == blue { blues += 1 } } }
    if reds != 0 { bad |= 4 }
    if blues == 0 { bad |= 8 }
    // Options under an environment modifier are still separate options.
    let modified = Picker(selection: .constant(2), content: { _PickOptions().disabled(false) }, label: { EmptyView() })
      .frame(width: 80, height: 30)
    let mp = render(modified, 80, 30)
    var mreds = 0
    for x in 0..<80 { for y in 0..<30 where mp(x, y) == red { mreds += 1 } }
    if mreds != 0 { bad |= 16 }
    // Options in sections are options too: the chosen one shows alone.
    let sectioned = Picker(selection: .constant(2), content: {
      Section { Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 10, height: 10).tag(1) } header: { EmptyView() }
      Section { Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 10, height: 10).tag(2) } header: { EmptyView() }
    }, label: { EmptyView() }).frame(width: 80, height: 30)
    let sp = render(sectioned, 80, 30)
    var sreds = 0, sblues = 0
    for x in 0..<80 { for y in 0..<30 { if sp(x, y) == red { sreds += 1 }; if sp(x, y) == blue { sblues += 1 } } }
    if sreds != 0 || sblues == 0 { bad |= 32 }
    return bad
  }
}
