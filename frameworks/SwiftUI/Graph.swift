// The view graph. Apple's View protocol builds views through static
// requirements (`_makeView(view:inputs:)` and friends) whose types —
// _GraphValue, _ViewInputs, _ViewOutputs, ... — are SwiftUI's own. Programs
// only pass them through to SwiftUI's default implementations, so here they
// carry our engine: each view becomes a retained render node (layout and
// drawing into a CGContext), and state lives in storage keyed by the view's
// structural position, which survives the tree being rebuilt.

import CoreGraphics

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

  init(environment: EnvironmentValues, children: [_ViewNode] = []) {
    self.environment = environment
    self.children = children
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
  /// The deepest node under `point` that handles taps.
  func hit(_ point: CGPoint) -> _ViewNode? {
    guard frame._contains(point) else { return nil }
    for c in children.reversed() {
      if let h = c.hit(point) { return h }
    }
    return handlesTaps ? self : nil
  }
  var handlesTaps: Bool { return false }
  func tap() {}
  /// Layout priority and flexibility, for stacks.
  var layoutPriority: Double { return children.count == 1 ? children[0].layoutPriority : 0 }
  var isSpacer: Bool { return false }
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

/// Installs every installable stored property of `value` (a struct).
internal func _installDynamicProperties<V>(_ value: inout V, inputs: _ViewInputs) {
  withUnsafeMutablePointer(to: &value) { p in
    let raw = UnsafeRawPointer(p)
    let n = _sw_fieldCount(raw, V.self)
    var i = 0
    while i < n {
      var name: UnsafePointer<CChar>? = nil
      var type: Any.Type? = nil
      if let addr = _sw_field(raw, V.self, i, &name, &type), let t = type {
        let key = inputs.base.path + "#" + (name.map { String(cString: $0) } ?? "\(i)")
        if let installable = t as? _GraphInstallable.Type {
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
  return V._makeView(view: _GraphValue({ view }), inputs: inputs).node
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
    return Body._makeView(view: _GraphValue({ body }), inputs: inputs.child(0))
  }

  public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
    return _ViewListOutputs([_makeView(view: view, inputs: inputs.base).node])
  }

  public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? { return 1 }
}

extension View where Self: Animatable {
  public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
    var value = view.value
    _installDynamicProperties(&value, inputs: inputs)
    let body = _withObservation(inputs) { value.body }
    return Body._makeView(view: _GraphValue({ body }), inputs: inputs.child(0))
  }
  public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
    return _ViewListOutputs([_makeView(view: view, inputs: inputs.base).node])
  }
}

/// Evaluates a body while watching the @Observable properties it reads:
/// when one changes, the host rebuilds.
internal func _withObservation<T>(_ inputs: _ViewInputs, _ body: () -> T) -> T {
  let context = inputs.base.context
  return withObservationTracking(body, onChange: { context.invalidate() })
}
