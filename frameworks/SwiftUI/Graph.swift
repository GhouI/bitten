// The view graph. Apple's View protocol builds views through static
// requirements (`_makeView(view:inputs:)` and friends) whose types —
// _GraphValue, _ViewInputs, _ViewOutputs, ... — are SwiftUI's own. Programs
// only pass them through to SwiftUI's default implementations, so here they
// carry our engine: each view becomes a retained render node (layout and
// drawing into a CGContext), and state lives in storage keyed by the view's
// structural position, which survives the tree being rebuilt.

import CoreGraphics
import Dispatch
import Observation

// MARK: - graph types

public struct _Graph {
  internal init() {}
}

/// A value in the graph: how to read the current view value.
public struct _GraphValue<Value>: Equatable {
  internal let _read: () -> Value
  internal let _id: Int

  internal init(_ read: @escaping () -> Value, id: Int = 0) {
    _read = read
    _id = id
  }
  internal var value: Value { return _read() }

  public subscript<Member>(keyPath: KeyPath<Value, Member>) -> _GraphValue<Member> {
    let read = _read
    return _GraphValue<Member>({ read()[keyPath: keyPath] }, id: _id)
  }
  public static func == (a: _GraphValue<Value>, b: _GraphValue<Value>) -> Bool { return a._id == b._id }
}

/// Where state for a view lives, shared by every rebuild of one host.
internal final class _RenderContext {
  var storage: [String: AnyObject] = [:]
  var invalidate: () -> Void = {}
  /// The view AppKit subviews (representables) are added to.
  weak var hostView: NSView?
  /// AppKit subviews placed in the last layout.
  var livePlatformViews: Set<ObjectIdentifier> = []

  /// Appear/disappear: views seen in the build in progress, and the
  /// disappear actions of those seen in the last one.
  private var seen: Set<String> = []
  private var live: [String: (() -> Void)?] = [:]
  private var pendingAppear: [() -> Void] = []
  /// Counts builds. Observation registered by an earlier build watches a
  /// tree that is gone: a write that fires it while a newer tree is built
  /// (a view's initialiser storing what it was given) is not a change the
  /// new tree missed.
  var generation = 0
  /// What the current tree is watching (Observation); a new build or the
  /// host going away stops it.
  var trackings: [AnyObject] = []
  func cancelObservation() {
    for t in trackings { _bitten_cancelObservationTracking(t) }
    trackings = []
  }
  func beginBuild() {
    seen = []
    generation += 1
    cancelObservation()
  }
  func lifecycle(_ key: String, appear: (() -> Void)?, disappear: (() -> Void)?) {
    seen.insert(key)
    if live[key] == nil, let a = appear { pendingAppear.append(a) }
    live[key] = .some(disappear)
  }
  /// Runs the appear actions of new views and the disappear actions of
  /// views that are gone, after the build.
  func endBuild() {
    for (k, d) in live where !seen.contains(k) {
      live[k] = nil
      if let d = d { DispatchQueue.main.async { d() } }
    }
    let appear = pendingAppear
    pendingAppear = []
    for a in appear { DispatchQueue.main.async { a() } }
  }
  /// Whether the view `key` names was in the last build.
  func isLive(_ key: String) -> Bool { return live[key] != nil }
  /// Representables still here when the host goes are told (dismantle).
  deinit {
    for case let b as _PlatformViewBox in storage.values { b.dismantleNow() }
  }
  func store<T: AnyObject>(_ key: String, _ make: () -> T) -> T {
    if let s = storage[key] as? T { return s }
    let s = make()
    storage[key] = s
    return s
  }
}

public struct _GraphInputs {
  internal var environment: EnvironmentValues
  internal var context: _RenderContext
  internal var path: String
  internal init(environment: EnvironmentValues, context: _RenderContext, path: String) {
    self.environment = environment
    self.context = context
    self.path = path
  }
}

public struct _ViewInputs {
  internal var base: _GraphInputs
  internal init(_ base: _GraphInputs) { self.base = base }
  internal var environment: EnvironmentValues {
    get { return base.environment }
    set { base.environment = newValue }
  }
  /// Inputs for a child at `index`: its own place in the structure.
  internal func child(_ index: Int) -> _ViewInputs {
    var c = self
    c.base.path += "/\(index)"
    return c
  }
  internal func named(_ name: String) -> _ViewInputs {
    var c = self
    c.base.path += "/" + name
    return c
  }
}

public struct _ViewOutputs {
  internal var node: _ViewNode
  internal init(_ node: _ViewNode) { self.node = node }
}

public struct _ViewListInputs {
  internal var base: _ViewInputs
  internal init(_ base: _ViewInputs) { self.base = base }
}

public struct _ViewListOutputs {
  internal var nodes: [_ViewNode]
  internal init(_ nodes: [_ViewNode]) { self.nodes = nodes }
}

public struct _ViewListCountInputs {
  internal init() {}
}

// MARK: - render nodes

/// A laid-out piece of the view tree. Coordinates are top-left based, in
/// the hosting view's (flipped) space.
internal class _ViewNode {
  var frame: CGRect = ._zero
  var children: [_ViewNode] = []
  var environment: EnvironmentValues
  /// The view type that made this node (set only with BITTEN_SWIFTUI_TREE).
  var _debugName: String?

  /// Prints the placed subtree (BITTEN_SWIFTUI_TREE=1).
  func _dumpTree(_ depth: Int = 0) {
    let f = frame
    var name = _debugName.map { String($0.prefix(160)) } ?? ""
    if let t = self as? _TextNode { name += " \"" + String(t.string.prefix(40)) + "\"" }
    if let fr = self as? _FrameNode {
      func d(_ v: CGFloat?) -> String { return v.map { "\($0)" } ?? "-" }
      name += " [w \(d(fr.minW))/\(d(fr.idealW))/\(d(fr.maxW)) h \(d(fr.minH))/\(d(fr.idealH))/\(d(fr.maxH))]"
    }
    _dbg(String(repeating: "  ", count: depth) + "\(type(of: self)) \(name) (\(f.origin.x),\(f.origin.y) \(f.size.width)x\(f.size.height))")
    for c in children { c._dumpTree(depth + 1) }
  }

  init(environment: EnvironmentValues, children: [_ViewNode] = []) {
    self.environment = environment
    self.children = children
  }

  /// Sizes measured in the current layout pass (see _measureGeneration).
  private var _measuredGen = -1
  private var _measured: [(ProposedViewSize, CGSize)] = []
  /// sizeThatFits, remembered for the rest of the layout pass: stacks ask
  /// their children several times (ideal, least, most, final), which nested
  /// stacks would otherwise multiply level by level.
  final func measure(_ p: ProposedViewSize) -> CGSize {
    if _measuredGen != _measureGeneration {
      _measured.removeAll(keepingCapacity: true)
      _measuredGen = _measureGeneration
    }
    if _bn_noMeasureCache { return sizeThatFits(p) }
    for (q, size) in _measured where q == p { return size }
    let size = sizeThatFits(p)
    if _measured.count < 8 { _measured.append((p, size)) }
    return size
  }

  /// The size this node wants for a proposal (nil dimensions: ideal size).
  func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    // By default a node is as big as its single child, or takes what it is given.
    if children.count == 1 { return children[0].sizeThatFits(proposal) }
    return CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
  }
  func place(in rect: CGRect) {
    frame = rect
    for c in children { c.place(in: rect) }
  }
  func draw(_ context: CGContext) {
    for c in children { c.draw(context) }
  }
  /// The AppKit views (representables) in this subtree, back to front.
  func collectPlatformViews(_ into: inout [NSView]) {
    for c in children { c.collectPlatformViews(&into) }
  }
  /// The deepest node under `point` that handles taps.
  func hit(_ point: CGPoint) -> _ViewNode? {
    guard frame._contains(point) else { return nil }
    for c in children.reversed() {
      if let h = c.hit(point) { return h }
    }
    return handlesTaps ? self : nil
  }
  var handlesTaps: Bool { return false }
  /// The hover regions (onHover, onContinuousHover) at `point`, each with
  /// its path in the tree, which stays the same when the tree is rebuilt.
  func collectHover(_ point: CGPoint, path: String, into: inout [(String, _HoverNode)]) {
    for (i, c) in children.enumerated() { c.collectHover(point, path: path + "/\(i)", into: &into) }
  }
  /// Whether something this subtree draws (or a content shape) is at
  /// `point`: gestures take clicks only there, as in SwiftUI.
  func hitsContent(_ point: CGPoint) -> Bool {
    guard frame._contains(point) else { return false }
    return children.contains { $0.hitsContent(point) }
  }
  func tap() {}
  /// Where a press that may become a tap began.
  func press(at point: CGPoint) {}
  /// A drag from `start` now at `point`; true when this node took it.
  func drag(from start: CGPoint, to point: CGPoint, ended: Bool) -> Bool { return false }
  /// The scroll wheel over `point`; true when something scrolled.
  func scroll(at point: CGPoint, dx: CGFloat, dy: CGFloat) -> Bool {
    for c in children.reversed() where c.frame._contains(point) {
      if c.scroll(at: point, dx: dx, dy: dy) { return true }
    }
    return false
  }
  /// A key typed while this host has focus; true when handled.
  func key(_ characters: String, keyCode: UInt16) -> Bool {
    for c in children where c.key(characters, keyCode: keyCode) { return true }
    return false
  }
  /// Layout priority and flexibility, for stacks.
  var layoutPriority: Double { return children.count == 1 ? children[0].layoutPriority : 0 }
  var isSpacer: Bool { return false }
  /// Values for custom layouts (`layoutValue(key:value:)`).
  var layoutValues: [ObjectIdentifier: Any] { return children.count == 1 ? children[0].layoutValues : [:] }
  /// Collects the preference values for `key` written in this subtree.
  func preference(_ key: ObjectIdentifier, into values: inout [Any]) {
    for c in children { c.preference(key, into: &values) }
  }
}

/// Nodes of views made from other nodes without adding anything.
internal final class _GroupNode: _ViewNode {}

/// Shows nothing and takes no space.
internal final class _EmptyNode: _ViewNode {
  override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { return ._zero }
}

// MARK: - dynamic properties

/// What @State and friends do when their view joins the graph: find their
/// storage (by the view's position and the property's).
internal protocol _GraphInstallable {
  mutating func _install(key: String, inputs: _ViewInputs)
}

@_silgen_name("_bitten_mirror_count")
internal func _sw_fieldCount(_ value: UnsafeRawPointer, _ type: Any.Type) -> Int
@_silgen_name("_bitten_mirror_child")
internal func _sw_field(_ value: UnsafeRawPointer, _ type: Any.Type, _ index: Int,
                        _ name: UnsafeMutablePointer<UnsafePointer<CChar>?>,
                        _ childType: UnsafeMutablePointer<Any.Type?>) -> UnsafeRawPointer?

/// Bumped at the start of every layout pass: measurements from an earlier
/// pass are stale.
nonisolated(unsafe) var _measureGeneration = 0
nonisolated(unsafe) let _bn_noMeasureCache = getenv("BITTEN_NO_MEASURE_CACHE") != nil
nonisolated(unsafe) let _debugGraph = getenv("BITTEN_SWIFTUI_DEBUG") != nil
nonisolated(unsafe) let _debugTree = getenv("BITTEN_SWIFTUI_TREE") != nil
/// BITTEN_REP_DEBUG=Name prints representables whose type contains Name
/// (their values and the colour scheme) each time they are updated.
nonisolated(unsafe) let _debugRepOf: String? = getenv("BITTEN_REP_DEBUG").map { String(cString: $0) }
/// BITTEN_SWIFTUI_BODY=Name prints the body type of views whose type starts with Name.
nonisolated(unsafe) let _debugBodyOf: String? = getenv("BITTEN_SWIFTUI_BODY").map { String(cString: $0) }
/// Debug output, unbuffered (it often comes just before a crash).
internal func _dbg(_ s: String) { fputs(s + "\n", stderr) }

/// Installs every installable stored property of `value` (a struct).
internal func _installDynamicProperties<V>(_ value: inout V, inputs: _ViewInputs) {
  withUnsafeMutablePointer(to: &value) { p in
    let raw = UnsafeRawPointer(p)
    let n = _sw_fieldCount(raw, V.self)
    if _debugGraph { _dbg("bitten: install \(V.self): \(n) fields") }
    var i = 0
    while i < n {
      var name: UnsafePointer<CChar>? = nil
      var type: Any.Type? = nil
      if let addr = _sw_field(raw, V.self, i, &name, &type), let t = type {
        let key = inputs.base.path + "#" + (name.map { String(cString: $0) } ?? "\(i)")
        if _debugGraph {
          func size<T>(_: T.Type) -> Int { MemoryLayout<T>.size }
          _dbg("  field \(name.map { String(cString: $0) } ?? "?"): \(t) @\(addr - raw) size \(_openExistential(t, do: size)) installable=\(t is _GraphInstallable.Type)")
        }
        if let installable = t as? _GraphInstallable.Type {
          // A field outside the value would be written over someone else's memory.
          func fits<T>(_: T.Type) -> Bool { addr >= raw && addr - raw + MemoryLayout<T>.size <= MemoryLayout<V>.size }
          guard _openExistential(t, do: fits) else {
            _dbg("bitten: install \(V.self): field \(name.map { String(cString: $0) } ?? "\(i)") at offset \(addr - raw) is outside the value (size \(MemoryLayout<V>.size)); skipped")
            i += 1
            continue
          }
          func install<T: _GraphInstallable>(_: T.Type) {
            UnsafeMutableRawPointer(mutating: addr).assumingMemoryBound(to: T.self).pointee._install(key: key, inputs: inputs)
          }
          install(installable)
        }
      }
      i += 1
    }
  }
}

// MARK: - building

/// Builds the node for a view value, through its type's _makeView.
internal func _makeNode<V: View>(_ view: V, inputs: _ViewInputs) -> _ViewNode {
  let node = V._makeView(view: _GraphValue({ view }), inputs: inputs).node
  if _debugTree { _debugLabel(node, V.self) }
  return node
}

/// Prepends a view type's name to a node's debug label.
internal func _debugLabel(_ node: _ViewNode, _ type: Any.Type) {
  let full = "\(type)"
  let short = full.split(separator: "<").first.map(String.init) ?? full
  if node._debugName?.hasPrefix(short + "/") == true || node._debugName == short { return }
  node._debugName = node._debugName.map { short + "/" + $0 } ?? short
}

/// Builds the list of nodes a view contributes to a stack.
internal func _makeNodes<V: View>(_ view: V, inputs: _ViewInputs) -> [_ViewNode] {
  return V._makeViewList(view: _GraphValue({ view }), inputs: _ViewListInputs(inputs)).nodes
}

extension View {
  /// The default: install the view's dynamic properties, then build its body.
  public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
    var value = view.value
    _installDynamicProperties(&value, inputs: inputs)
    if Body.self == Never.self {
      return _ViewOutputs(_EmptyNode(environment: inputs.environment))
    }
    let body = _withObservation(inputs) { value.body }
    if let want = _debugBodyOf, "\(Self.self)".hasPrefix(want) { _dbg("bitten: body of \(Self.self) is \(Body.self)") }
    let out = Body._makeView(view: _GraphValue({ body }), inputs: inputs.child(0))
    if _debugTree { _debugLabel(out.node, Self.self) }
    return out
  }

  /// A view's elements in a container are its body's: a view whose body
  /// is a ForEach or several views gives the stack, picker or list around
  /// it one element per view, as in SwiftUI.
  public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
    if Body.self == Never.self { return _ViewListOutputs([_makeView(view: view, inputs: inputs.base).node]) }
    return _bodyViewList(view, inputs)
  }

  public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
    return Body.self == Never.self ? 1 : Body._viewListCount(inputs: inputs)
  }
}

/// The view list of a view's body (dynamic properties installed, reads
/// watched), at the same place in the graph its _makeView builds it.
internal func _bodyViewList<V: View>(_ view: _GraphValue<V>, _ inputs: _ViewListInputs) -> _ViewListOutputs {
  var value = view.value
  _installDynamicProperties(&value, inputs: inputs.base)
  let body = _withObservation(inputs.base) { value.body }
  let out = V.Body._makeViewList(view: _GraphValue({ body }), inputs: _ViewListInputs(inputs.base.child(0)))
  if _debugTree { for n in out.nodes { _debugLabel(n, V.self) } }
  return out
}

extension View where Self: Animatable {
  public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
    var value = view.value
    _installDynamicProperties(&value, inputs: inputs)
    let body = _withObservation(inputs) { value.body }
    if let want = _debugBodyOf, "\(Self.self)".hasPrefix(want) { _dbg("bitten: body of \(Self.self) is \(Body.self)") }
    let out = Body._makeView(view: _GraphValue({ body }), inputs: inputs.child(0))
    if _debugTree { _debugLabel(out.node, Self.self) }
    return out
  }
  public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
    return _bodyViewList(view, inputs)
  }
}

/// Evaluates a body while watching the @Observable properties it reads:
/// when one changes, the host rebuilds.
internal func _withObservation<T>(_ inputs: _ViewInputs, _ body: () -> T) -> T {
  let context = inputs.base.context
  let generation = context.generation
  let (result, token) = _bitten_withObservationTracking(body, onChange: { [weak context] in
    guard let context = context, generation == context.generation else { return }
    if _debugGraph || _debugTree { _dbg("bitten: observed change: rebuilding") }
    context.invalidate()
  })
  if let t = token { context.trackings.append(t) }
  return result
}
