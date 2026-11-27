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
