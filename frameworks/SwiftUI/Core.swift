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

@MainActor @preconcurrency
public protocol View {
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
}

@frozen public struct TupleView<T>: View {
  public var value: T
  @inlinable public init(_ value: T) { self.value = value }
  public typealias Body = Never
  public var body: Never { fatalError("TupleView has no body") }
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
}

/// A type-erased view.
@frozen public struct AnyView: View {
  @usableFromInline internal var storage: AnyViewStorageBase
  public init<V: View>(_ view: V) { storage = AnyViewStorage(view) }
  public init<V: View>(erasing view: V) { self.init(view) }
  public typealias Body = Never
  public var body: Never { fatalError("AnyView has no body") }
}
@usableFromInline internal class AnyViewStorageBase {
  var anyValue: Any { fatalError("abstract") }
}
final class AnyViewStorage<V: View>: AnyViewStorageBase {
  let view: V
  init(_ view: V) { self.view = view }
  override var anyValue: Any { return view }
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
