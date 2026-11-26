// SwiftUI's core protocols and the result builders.
//
// Declarations follow Apple's documented API, because their mangled names
// are what programs bind to. Types that programs inline against keep
// Apple's stored layout (marked @frozen below); everything else is ours.

@_exported import Foundation
@_exported import AppKit
@_exported import Combine
@_exported import Observation

// ---- View ---------------------------------------------------------------------

/// Apple's requirements: the three static graph entry points (whose
/// default implementations programs reference by symbol), then the body.
@MainActor @preconcurrency
public protocol View {
  nonisolated static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs
  nonisolated static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs
  nonisolated static func _viewListCount(inputs: _ViewListCountInputs) -> Int?
  associatedtype Body: View
  @ViewBuilder @MainActor @preconcurrency var body: Self.Body { get }
}

extension Never: View {
  public typealias Body = Never
  public var body: Never { fatalError("Never has no body") }
}

/// Views whose body is never evaluated: the engine handles them directly.
@MainActor
protocol _PrimitiveView: View where Body == Never {}

@frozen public struct EmptyView: View {
  @inlinable public init() {}
  public typealias Body = Never
  public var body: Never { fatalError("EmptyView has no body") }
  public static func _makeView(view: _GraphValue<EmptyView>, inputs: _ViewInputs) -> _ViewOutputs {
    return _ViewOutputs(_EmptyNode(environment: inputs.environment))
  }
  public static func _makeViewList(view: _GraphValue<EmptyView>, inputs: _ViewListInputs) -> _ViewListOutputs {
    return _ViewListOutputs([])
  }
  public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? { return 0 }
}

@frozen public struct TupleView<T>: View {
  public var value: T
  @inlinable public init(_ value: T) { self.value = value }
  public typealias Body = Never
  public var body: Never { fatalError("TupleView has no body") }

  /// Each element contributes its own list (so stacks see them all).
  public static func _makeViewList(view: _GraphValue<TupleView<T>>, inputs: _ViewListInputs) -> _ViewListOutputs {
    var nodes: [_ViewNode] = []
    var index = 0
    _forEachTupleElement(view.value.value) { element in
      if let v = element as? any View { nodes += _makeNodesOpened(v, inputs: inputs.base.child(index)) }
      index += 1
    }
    return _ViewListOutputs(nodes)
  }
  public static func _makeView(view: _GraphValue<TupleView<T>>, inputs: _ViewInputs) -> _ViewOutputs {
    let nodes = _makeViewList(view: view, inputs: _ViewListInputs(inputs)).nodes
    return _ViewOutputs(_StackNode(axis: .vertical, alignment: .center, spacing: nil,
                                   environment: inputs.environment, children: nodes))
  }
  public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? { return nil }
}

internal func _makeNodesOpened(_ v: any View, inputs: _ViewInputs) -> [_ViewNode] {
  func open<V: View>(_ v: V) -> [_ViewNode] { return _makeNodes(v, inputs: inputs) }
  return open(v)
}
internal func _makeNodeOpened(_ v: any View, inputs: _ViewInputs) -> _ViewNode {
  func open<V: View>(_ v: V) -> _ViewNode { return _makeNode(v, inputs: inputs) }
  return open(v)
}

@frozen public struct _ConditionalContent<TrueContent, FalseContent> {
  @usableFromInline @frozen internal enum Storage {
    case trueContent(TrueContent)
    case falseContent(FalseContent)
  }
  @usableFromInline internal let storage: Storage
  @usableFromInline internal init(storage: Storage) { self.storage = storage }
}
extension _ConditionalContent: View where TrueContent: View, FalseContent: View {
  public typealias Body = Never
  public var body: Never { fatalError("_ConditionalContent has no body") }
  public static func _makeView(view: _GraphValue<_ConditionalContent>, inputs: _ViewInputs) -> _ViewOutputs {
    switch view.value.storage {
    case .trueContent(let t): return TrueContent._makeView(view: _GraphValue({ t }), inputs: inputs.named("T"))
    case .falseContent(let f): return FalseContent._makeView(view: _GraphValue({ f }), inputs: inputs.named("F"))
    }
  }
  public static func _makeViewList(view: _GraphValue<_ConditionalContent>, inputs: _ViewListInputs) -> _ViewListOutputs {
    switch view.value.storage {
    case .trueContent(let t): return _ViewListOutputs(_makeNodes(t, inputs: inputs.base.named("T")))
    case .falseContent(let f): return _ViewListOutputs(_makeNodes(f, inputs: inputs.base.named("F")))
    }
  }
}

@resultBuilder
public struct ViewBuilder {
  @_alwaysEmitIntoClient public static func buildExpression<Content: View>(_ content: Content) -> Content { content }
  @_alwaysEmitIntoClient public static func buildBlock() -> EmptyView { EmptyView() }
  @_alwaysEmitIntoClient public static func buildBlock<Content: View>(_ content: Content) -> Content { content }
  @_alwaysEmitIntoClient
  public static func buildBlock<each Content: View>(_ content: repeat each Content) -> TupleView<(repeat each Content)> {
    return TupleView((repeat each content))
  }
  @_alwaysEmitIntoClient public static func buildIf<Content: View>(_ content: Content?) -> Content? { content }
  @_alwaysEmitIntoClient
  public static func buildEither<TrueContent: View, FalseContent: View>(first: TrueContent)
    -> _ConditionalContent<TrueContent, FalseContent> {
    return _ConditionalContent(storage: .trueContent(first))
  }
  @_alwaysEmitIntoClient
  public static func buildEither<TrueContent: View, FalseContent: View>(second: FalseContent)
    -> _ConditionalContent<TrueContent, FalseContent> {
    return _ConditionalContent(storage: .falseContent(second))
  }
  @_alwaysEmitIntoClient public static func buildLimitedAvailability<Content: View>(_ content: Content) -> AnyView {
    AnyView(content)
  }
}

extension Optional: View where Wrapped: View {
  public typealias Body = Never
  public var body: Never { fatalError("Optional has no body") }
  public static func _makeView(view: _GraphValue<Optional>, inputs: _ViewInputs) -> _ViewOutputs {
    guard let w = view.value else { return _ViewOutputs(_EmptyNode(environment: inputs.environment)) }
    return Wrapped._makeView(view: _GraphValue({ w }), inputs: inputs)
  }
  public static func _makeViewList(view: _GraphValue<Optional>, inputs: _ViewListInputs) -> _ViewListOutputs {
    guard let w = view.value else { return _ViewListOutputs([]) }
    return Wrapped._makeViewList(view: _GraphValue({ w }), inputs: inputs)
  }
}

/// A type-erased view.
@frozen public struct AnyView: View {
  @usableFromInline internal var storage: AnyViewStorageBase
  public init<V: View>(_ view: V) { storage = AnyViewStorage(view) }
  public init<V: View>(erasing view: V) { self.init(view) }
  public typealias Body = Never
  public var body: Never { fatalError("AnyView has no body") }
  public static func _makeView(view: _GraphValue<AnyView>, inputs: _ViewInputs) -> _ViewOutputs {
    return _ViewOutputs(view.value.storage.makeNode(inputs))
  }
  public static func _makeViewList(view: _GraphValue<AnyView>, inputs: _ViewListInputs) -> _ViewListOutputs {
    return _ViewListOutputs(view.value.storage.makeNodes(inputs.base))
  }
}
@usableFromInline internal class AnyViewStorageBase {
  var anyValue: Any { fatalError("abstract") }
  func makeNode(_ inputs: _ViewInputs) -> _ViewNode { fatalError("abstract") }
  func makeNodes(_ inputs: _ViewInputs) -> [_ViewNode] { fatalError("abstract") }
}
final class AnyViewStorage<V: View>: AnyViewStorageBase {
  let view: V
  init(_ view: V) { self.view = view }
  override var anyValue: Any { return view }
  /// The view's type is part of its identity: a different type is a new view.
  override func makeNode(_ inputs: _ViewInputs) -> _ViewNode {
    return _makeNode(view, inputs: inputs.named(String(describing: V.self)))
  }
  override func makeNodes(_ inputs: _ViewInputs) -> [_ViewNode] {
    return _makeNodes(view, inputs: inputs.named(String(describing: V.self)))
  }
}

// ---- Scene and App ------------------------------------------------------------------

@MainActor @preconcurrency
public protocol Scene {
  associatedtype Body: Scene
  @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }
}

extension Never: Scene {}

@resultBuilder
public struct SceneBuilder {
  @_alwaysEmitIntoClient public static func buildExpression<Content: Scene>(_ content: Content) -> Content { content }
  @_alwaysEmitIntoClient public static func buildBlock<Content: Scene>(_ content: Content) -> Content { content }
  @_alwaysEmitIntoClient
  public static func buildBlock<each Content: Scene>(_ content: repeat each Content) -> some Scene {
    return _TupleScene((repeat each content))
  }
}

@frozen public struct _TupleScene<T>: Scene {
  public var value: T
  @inlinable public init(_ value: T) { self.value = value }
  public typealias Body = Never
  public var body: Never { fatalError("_TupleScene has no body") }
}

@MainActor @preconcurrency
public protocol App {
  associatedtype Body: Scene
  @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }
  @MainActor @preconcurrency init()
}

extension App {
  /// The program's entry point (`@main`): creates the app value, builds its
  /// scenes, opens their windows and runs the application.
  @MainActor @preconcurrency
  public static func main() {
    let host = _AppHost.shared
    let app = Self()
    host.start(app)
  }
}

// ---- DynamicProperty ---------------------------------------------------------------------

public protocol DynamicProperty {
  mutating func update()
}
extension DynamicProperty {
  public mutating func update() {}
}
