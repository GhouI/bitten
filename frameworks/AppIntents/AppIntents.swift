// AppIntents: the declarations programs make for Shortcuts, Siri and
// Spotlight: intents, entities and their queries, parameters, summaries,
// shortcuts. There is no Shortcuts app or system intent service here, so
// nothing asks a program to run its intents: the types exist with Apple's
// shapes (programs' metadata and conformances bind to them), parameters
// and properties hold values, and summaries, dialogs and representations
// keep what they were built from.
import Foundation
import UniformTypeIdentifiers

// ---- the protocols -----------------------------------------------------------

public protocol _SupportsAppDependencies {}

public protocol PersistentlyIdentifiable {
  static var persistentIdentifier: String { get }
}
extension PersistentlyIdentifiable {
  public static var persistentIdentifier: String { return String(describing: Self.self) }
}

/// How the system would resolve a parameter's value (not used here).
public protocol ResolverSpecification {}
public struct EmptyResolverSpecification<Value>: ResolverSpecification, Sendable {
  public init() {}
}

/// A type that can be an intent's parameter or result.
public protocol _IntentValue {
  associatedtype ValueType: _IntentValue = Self
  associatedtype UnwrappedType: _IntentValue = Self
  associatedtype Specification: ResolverSpecification
  static var defaultResolverSpecification: Specification { get }
}

/// A collection of intent values (the result of a query).
public protocol ResultsCollection {}

public protocol EntityIdentifierConvertible {
  var entityIdentifierString: String { get }
  static func entityIdentifier(for entityIdentifierString: String) -> Self?
}

public protocol TypeDisplayRepresentable {
  static var typeDisplayRepresentation: TypeDisplayRepresentation { get }
}
public protocol InstanceDisplayRepresentable: CustomLocalizedStringResourceConvertible {
  var displayRepresentation: DisplayRepresentation { get }
}
extension InstanceDisplayRepresentable {
  public var localizedStringResource: LocalizedStringResource { return displayRepresentation.title }
}
public protocol DisplayRepresentable: InstanceDisplayRepresentable, TypeDisplayRepresentable {}

public protocol AppValue: TypeDisplayRepresentable, PersistentlyIdentifiable, _IntentValue {}

public protocol DynamicOptionsProvider: _SupportsAppDependencies {
  associatedtype Result: ResultsCollection
  associatedtype DefaultValue: _IntentValue
  func results() async throws -> Result
  func defaultResult() async -> DefaultValue?
}
extension DynamicOptionsProvider {
  public func defaultResult() async -> DefaultValue? { return nil }
}

public protocol AppEntity: Identifiable, DisplayRepresentable, AppValue where ID: EntityIdentifierConvertible {
  associatedtype DefaultQuery: EntityQuery
  static var defaultQuery: DefaultQuery { get }
}
extension AppEntity {
  public static var defaultResolverSpecification: EmptyResolverSpecification<Self> { return .init() }
}

public protocol EntityQuery: PersistentlyIdentifiable, DynamicOptionsProvider {
  associatedtype Entity: AppEntity
  init()
  func entities(for identifiers: [Entity.ID]) async throws -> [Entity]
  func suggestedEntities() async throws -> Result
}
extension EntityQuery {
  public func results() async throws -> Result { return try await suggestedEntities() }
}

public protocol EnumerableEntityQuery: EntityQuery {
  func allEntities() async throws -> Result
  static var findIntentDescription: IntentDescription? { get }
}
extension EnumerableEntityQuery {
  public static var findIntentDescription: IntentDescription? { return nil }
}

public protocol EntityStringQuery: EntityQuery {
  func entities(matching string: String) async throws -> Result
}

public enum IntentAuthenticationPolicy: Sendable, Hashable {
  case alwaysAllowed
  case requiresAuthentication
  case requiresLocalDeviceAuthentication
}

public protocol IntentResult {}
public protocol ReturnsValue<Value>: IntentResult {
  associatedtype Value
}

public protocol ParameterSummary {
  associatedtype Intent: AppIntent
}

public protocol AppIntent: PersistentlyIdentifiable, _SupportsAppDependencies {
  associatedtype SummaryContent: ParameterSummary
  associatedtype PerformResult: IntentResult
  static var title: LocalizedStringResource { get }
  static var description: IntentDescription? { get }
  static var openAppWhenRun: Bool { get }
  static var isDiscoverable: Bool { get }
  static var authenticationPolicy: IntentAuthenticationPolicy { get }
  static var parameterSummary: SummaryContent { get }
  init()
  func perform() async throws -> PerformResult
}
extension AppIntent {
  public static var persistentIdentifier: String { return String(describing: Self.self) }
  public static var description: IntentDescription? { return nil }
  public static var openAppWhenRun: Bool { return false }
  public static var isDiscoverable: Bool { return true }
  public static var authenticationPolicy: IntentAuthenticationPolicy { return .alwaysAllowed }
}

/// A parameter's value, seen through its wrapper (summaries compare it).
public protocol AnyIntentValue {
  associatedtype Value
}

// ---- values ----------------------------------------------------------------------

extension String: _IntentValue {
  public static var defaultResolverSpecification: EmptyResolverSpecification<String> { return .init() }
}
extension Bool: _IntentValue {
  public static var defaultResolverSpecification: EmptyResolverSpecification<Bool> { return .init() }
}
extension Int: _IntentValue {
  public static var defaultResolverSpecification: EmptyResolverSpecification<Int> { return .init() }
}
extension Double: _IntentValue {
  public static var defaultResolverSpecification: EmptyResolverSpecification<Double> { return .init() }
}
extension Date: _IntentValue {
  public static var defaultResolverSpecification: EmptyResolverSpecification<Date> { return .init() }
}
extension URL: _IntentValue {
  public static var defaultResolverSpecification: EmptyResolverSpecification<URL> { return .init() }
}
extension Optional: _IntentValue where Wrapped: _IntentValue {
  public typealias ValueType = Wrapped.ValueType
  public typealias UnwrappedType = Wrapped
  public static var defaultResolverSpecification: EmptyResolverSpecification<Wrapped?> { return .init() }
}
extension Array: _IntentValue where Element: _IntentValue {
  public typealias ValueType = [Element.ValueType]
  public typealias UnwrappedType = [Element]
  public static var defaultResolverSpecification: EmptyResolverSpecification<[Element]> { return .init() }
}
extension Array: ResultsCollection where Element: _IntentValue {}

extension String: EntityIdentifierConvertible {
  public var entityIdentifierString: String { return self }
  public static func entityIdentifier(for s: String) -> String? { return s }
}
extension Int: EntityIdentifierConvertible {
  public var entityIdentifierString: String { return String(self) }
  public static func entityIdentifier(for s: String) -> Int? { return Int(s) }
}
extension UUID: EntityIdentifierConvertible {
  public var entityIdentifierString: String { return uuidString }
  public static func entityIdentifier(for s: String) -> UUID? { return UUID(uuidString: s) }
}

public struct IntentFile: _IntentValue, Sendable {
  public var fileURL: URL?
  public var data: Data
  public var filename: String
  public var type: UTType?

  public init(fileURL: URL, filename: String? = nil, type: UTType? = nil) {
    self.fileURL = fileURL
    self.data = (try? Data(contentsOf: fileURL)) ?? Data()
    self.filename = filename ?? fileURL.lastPathComponent
    self.type = type ?? UTType(filenameExtension: fileURL.pathExtension)
  }
  public init(data: Data, filename: String, type: UTType? = nil) {
    self.fileURL = nil
    self.data = data
    self.filename = filename
    self.type = type
  }
  public static var defaultResolverSpecification: EmptyResolverSpecification<IntentFile> { return .init() }
}

extension Bool {
  /// What a Bool parameter shows for true and false.
  public struct IntentDisplayName: Sendable {
    public var trueName: LocalizedStringResource
    public var falseName: LocalizedStringResource
    public init(true trueName: LocalizedStringResource, false falseName: LocalizedStringResource) {
      self.trueName = trueName
      self.falseName = falseName
    }
  }
}

extension String {
  /// How a String parameter is typed in.
  public struct IntentInputOptions: Sendable {
    public enum KeyboardType: Sendable, Hashable {
      case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad, namePhonePad,
        emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad
    }
    public enum CapitalizationType: Sendable, Hashable {
      case none, words, sentences, allCharacters
    }
    public var keyboardType: KeyboardType
    public var capitalizationType: CapitalizationType
    public var multiline: Bool
    public var autocorrect: Bool
    public var smartQuotes: Bool
    public var smartDashes: Bool
    public init(keyboardType: _const KeyboardType = .default, capitalizationType: _const CapitalizationType = .sentences,
                multiline: _const Bool = true, autocorrect: _const Bool = true, smartQuotes: _const Bool = true,
                smartDashes: _const Bool = true) {
      self.keyboardType = keyboardType
      self.capitalizationType = capitalizationType
      self.multiline = multiline
      self.autocorrect = autocorrect
      self.smartQuotes = smartQuotes
      self.smartDashes = smartDashes
    }
  }
}

// ---- representations, descriptions, dialogs -------------------------------------

public struct DisplayRepresentation: Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
  public struct Image: Sendable {
    public var systemName: String?
    public var url: URL?
    public var data: Data?
    public var isTemplate: Bool?
    public init(systemName: String, isTemplate: Bool? = nil) {
      self.systemName = systemName
      self.isTemplate = isTemplate
    }
    public init(named name: String, isTemplate: Bool? = nil) {
      self.systemName = name
      self.isTemplate = isTemplate
    }
    public init(url: URL, isTemplate: Bool? = nil) {
      self.url = url
      self.isTemplate = isTemplate
    }
    public init(data: Data, isTemplate: Bool? = nil) {
      self.data = data
      self.isTemplate = isTemplate
    }
  }
  public var title: LocalizedStringResource
  public var subtitle: LocalizedStringResource?
  public var image: Image?
  public var synonyms: [LocalizedStringResource]

  public init(title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil, image: Image? = nil) {
    self.title = title
    self.subtitle = subtitle
    self.image = image
    self.synonyms = []
  }
  public init(title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil, image: Image? = nil,
              synonyms: [LocalizedStringResource]) {
    self.init(title: title, subtitle: subtitle, image: image)
    self.synonyms = synonyms
  }
  public init(stringLiteral value: String) { self.init(title: LocalizedStringResource(stringLiteral: value)) }
  public init(stringInterpolation: String.LocalizationValue.StringInterpolation) {
    self.init(title: LocalizedStringResource(stringInterpolation: stringInterpolation))
  }
}

public struct TypeDisplayRepresentation: Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
  public var name: LocalizedStringResource
  public var numericFormat: LocalizedStringResource?
  public init(name: LocalizedStringResource, numericFormat: LocalizedStringResource? = nil) {
    self.name = name
    self.numericFormat = numericFormat
  }
  public init(stringLiteral value: String) { self.init(name: LocalizedStringResource(stringLiteral: value)) }
  public init(stringInterpolation: String.LocalizationValue.StringInterpolation) {
    self.init(name: LocalizedStringResource(stringInterpolation: stringInterpolation))
  }
}

public struct IntentDescription: Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
  public var descriptionText: LocalizedStringResource
  public var categoryName: LocalizedStringResource?
  public var searchKeywords: [LocalizedStringResource]
  public init(_ descriptionText: LocalizedStringResource, categoryName: LocalizedStringResource? = nil,
              searchKeywords: [LocalizedStringResource] = []) {
    self.descriptionText = descriptionText
    self.categoryName = categoryName
    self.searchKeywords = searchKeywords
  }
  public init(stringLiteral value: String) { self.init(LocalizedStringResource(stringLiteral: value)) }
  public init(stringInterpolation: String.LocalizationValue.StringInterpolation) {
    self.init(LocalizedStringResource(stringInterpolation: stringInterpolation))
  }
}

public struct IntentDialog: Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
  public var full: LocalizedStringResource
  public var supporting: LocalizedStringResource
  public init(_ resource: LocalizedStringResource) {
    full = resource
    supporting = resource
  }
  public init(full: LocalizedStringResource, supporting: LocalizedStringResource) {
    self.full = full
    self.supporting = supporting
  }
  public init(stringLiteral value: String) { self.init(LocalizedStringResource(stringLiteral: value)) }
  public init(stringInterpolation: String.LocalizationValue.StringInterpolation) {
    self.init(LocalizedStringResource(stringInterpolation: stringInterpolation))
  }
}

// ---- parameters and properties ---------------------------------------------------

public enum InputConnectionBehavior: Sendable, Hashable {
  case `default`
  case connectToPreviousIntentResult
}

/// A default (of the unwrapped type) as the parameter's type: itself, or
/// wrapped in the parameter's Optional.
internal func _intentCast<A, B>(_ value: A, to: B.Type) -> B? {
  if let same = value as? B { return same }
  return nil
}

/// The nil a parameter of optional type starts with.
internal func _intentNone<Value>(_: Value.Type) -> Value? {
  let none: Any? = nil
  return none as? Value
}

@propertyWrapper
public final class IntentParameter<Value: _IntentValue>: @unchecked Sendable {
  public let title: LocalizedStringResource
  public let description: LocalizedStringResource?
  public let requestValueDialog: IntentDialog?
  public let inputConnectionBehavior: InputConnectionBehavior
  internal var _value: Value?
  internal let _default: Value?

  internal init<D>(_title title: LocalizedStringResource, description: LocalizedStringResource?, default defaultValue: D?,
                   requestValueDialog: IntentDialog?, inputConnectionBehavior: InputConnectionBehavior) {
    self.title = title
    self.description = description
    self.requestValueDialog = requestValueDialog
    self.inputConnectionBehavior = inputConnectionBehavior
    self._default = defaultValue.flatMap { _intentCast($0, to: Value.self) }
  }

  /// The value given, else the default, else nil for an optional parameter.
  public var wrappedValue: Value {
    get {
      if let v = _value { return v }
      if let d = _default { return d }
      if let none = _intentNone(Value.self) { return none }
      fatalError("AppIntents: parameter \"\(String(localized: title))\" has no value")
    }
    set { _value = newValue }
  }
  public var projectedValue: IntentParameter<Value> { return self }
}

extension IntentParameter: AnyIntentValue {}

extension IntentParameter where Value.ValueType == Bool {
  public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil,
                          default defaultValue: _const Value.UnwrappedType? = nil,
                          displayName: Bool.IntentDisplayName? = nil, requestValueDialog: IntentDialog? = nil,
                          inputConnectionBehavior: _const InputConnectionBehavior = .default) {
    self.init(_title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog,
              inputConnectionBehavior: inputConnectionBehavior)
  }
}
extension IntentParameter where Value.ValueType == String {
  public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil,
                          default defaultValue: _const Value.UnwrappedType? = nil,
                          inputOptions: String.IntentInputOptions? = nil, requestValueDialog: IntentDialog? = nil,
                          inputConnectionBehavior: _const InputConnectionBehavior = .default) {
    self.init(_title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog,
              inputConnectionBehavior: inputConnectionBehavior)
  }
}
extension IntentParameter where Value.ValueType == IntentFile {
  public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil,
                          default defaultValue: Value.UnwrappedType? = nil, supportedContentTypes: [UTType] = [],
                          requestValueDialog: IntentDialog? = nil,
                          inputConnectionBehavior: _const InputConnectionBehavior = .default) {
    self.init(_title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog,
              inputConnectionBehavior: inputConnectionBehavior)
  }
}
extension IntentParameter where Value.ValueType: AppEntity {
  public convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil,
                          default defaultValue: Value.UnwrappedType? = nil, requestValueDialog: IntentDialog? = nil,
                          requestDisambiguationDialog: IntentDialog? = nil,
                          inputConnectionBehavior: _const InputConnectionBehavior = .default) {
    self.init(_title: title, description: description, default: defaultValue, requestValueDialog: requestValueDialog,
              inputConnectionBehavior: inputConnectionBehavior)
  }
}

@propertyWrapper
public final class EntityProperty<Value: _IntentValue>: @unchecked Sendable {
  public let title: LocalizedStringResource
  internal var _value: Value?

  internal init(_title title: LocalizedStringResource) { self.title = title }

  public var wrappedValue: Value {
    get {
      if let v = _value { return v }
      if let none = _intentNone(Value.self) { return none }
      fatalError("AppIntents: property \"\(String(localized: title))\" has no value")
    }
    set { _value = newValue }
  }
  public var projectedValue: EntityProperty<Value> { return self }
}

extension EntityProperty where Value.ValueType == Bool {
  public convenience init(title: LocalizedStringResource) { self.init(_title: title) }
}
extension EntityProperty where Value.ValueType == String {
  public convenience init(title: LocalizedStringResource) { self.init(_title: title) }
}

// ---- results --------------------------------------------------------------------------

/// What perform() returns: a value, a dialog, a view, an intent to open.
public struct IntentResultContainer<Value, ToBeOpened, Content, Dialog>: IntentResult, @unchecked Sendable {
  public let value: Value?
  internal init(value: Value?) { self.value = value }
}
extension IntentResultContainer: ReturnsValue {}

extension IntentResult {
  public static func result() -> Self where Self == IntentResultContainer<Never, Never, Never, Never> {
    return IntentResultContainer(value: nil)
  }
  public static func result<V: _IntentValue>(value: V) -> Self where Self == IntentResultContainer<V, Never, Never, Never> {
    return IntentResultContainer(value: value)
  }
}

// ---- parameter summaries ------------------------------------------------------------

public enum EquatableComparisonOperator: Sendable, Hashable {
  case equalTo
  case notEqualTo
}

@resultBuilder
public enum ParameterSummaryBuilder<Intent: AppIntent> {
  public static func buildExpression<S: ParameterSummary>(_ summary: S) -> S where S.Intent == Intent { return summary }
  public static func buildBlock<S: ParameterSummary>(_ summary: S) -> S where S.Intent == Intent { return summary }
}

public struct ParameterSummaryString<Intent: AppIntent>: ExpressibleByStringInterpolation, Sendable {
  public struct StringInterpolation: StringInterpolationProtocol, Sendable {
    internal var _text = ""
    public init(literalCapacity: Int, interpolationCount: Int) {}
    public mutating func appendLiteral(_ literal: String) { _text += literal }
    public mutating func appendInterpolation<Value: _IntentValue & Sendable, P: KeyPath<Intent, IntentParameter<Value>>>(
      _ parameter: P
    ) {
      _text += "${\(parameter)}"
    }
  }
  public let text: String
  public init(stringLiteral value: String) { text = value }
  public init(stringInterpolation: StringInterpolation) { text = stringInterpolation._text }
}

public struct IntentParameterSummary<Intent: AppIntent>: ParameterSummary, @unchecked Sendable {
  @resultBuilder
  public enum ParameterKeyPathsBuilder {
    public static func buildExpression<Value: _IntentValue & Sendable>(
      _ keyPath: KeyPath<Intent, IntentParameter<Value>>
    ) -> PartialKeyPath<Intent> {
      return keyPath
    }
    public static func buildBlock(_ keyPaths: PartialKeyPath<Intent>...) -> [PartialKeyPath<Intent>] { return keyPaths }
  }
  public let summary: ParameterSummaryString<Intent>
  public let table: String?
  public let parameters: [PartialKeyPath<Intent>]

  public init(_ summary: ParameterSummaryString<Intent>, table: String? = nil,
              @ParameterKeyPathsBuilder _ parameters: () -> [PartialKeyPath<Intent>]) {
    self.summary = summary
    self.table = table
    self.parameters = parameters()
  }
  public init(_ summary: ParameterSummaryString<Intent>, table: String? = nil) {
    self.summary = summary
    self.table = table
    self.parameters = []
  }
}

/// One summary or another, by a parameter's value.
public struct ParameterSummaryWhenCondition<Intent: AppIntent, When: ParameterSummary, Otherwise: ParameterSummary>:
  ParameterSummary, @unchecked Sendable
{
  public let keyPath: AnyKeyPath
  public let comparison: EquatableComparisonOperator
  public let value: Any
  public let when: When
  public let otherwise: Otherwise

  public init<Value: Equatable, P: AnyIntentValue>(
    _ keyPath: KeyPath<Intent, P>, _ comparison: EquatableComparisonOperator, _ value: Value,
    @ParameterSummaryBuilder<Intent> _ when: () -> When,
    @ParameterSummaryBuilder<Intent> otherwise: () -> Otherwise
  ) where Value == P.Value {
    self.keyPath = keyPath
    self.comparison = comparison
    self.value = value
    self.when = when()
    self.otherwise = otherwise()
  }
}

// ---- shortcuts --------------------------------------------------------------------------

public enum AppShortcutPhraseToken: Sendable, Hashable {
  case applicationName
}

public struct AppShortcutPhrase<Intent: AppIntent>: ExpressibleByStringInterpolation, Sendable {
  public struct StringInterpolation: StringInterpolationProtocol, Sendable {
    internal var _text = ""
    public init(literalCapacity: Int, interpolationCount: Int) {}
    public mutating func appendLiteral(_ literal: String) { _text += literal }
    public mutating func appendInterpolation(_ token: AppShortcutPhraseToken) { _text += "${applicationName}" }
  }
  public let text: String
  public init(stringLiteral value: String) { text = value }
  public init(stringInterpolation: StringInterpolation) { text = stringInterpolation._text }
}

public struct AppShortcut: @unchecked Sendable {
  public let intent: any AppIntent
  public let phrases: [String]
  public let shortTitle: LocalizedStringResource
  public let systemImageName: String

  public init<Intent: AppIntent>(intent: Intent, phrases: [AppShortcutPhrase<Intent>], shortTitle: LocalizedStringResource,
                                 systemImageName: _const String) {
    self.intent = intent
    self.phrases = phrases.map { $0.text }
    self.shortTitle = shortTitle
    self.systemImageName = systemImageName
  }
}

@resultBuilder
public enum AppShortcutsBuilder {
  public static func buildExpression(_ shortcut: AppShortcut) -> [AppShortcut] { return [shortcut] }
  public static func buildBlock(_ shortcuts: [AppShortcut]...) -> [AppShortcut] { return shortcuts.flatMap { $0 } }
}

public enum ShortcutTileColor: Sendable, Hashable {
  case red, tangerine, orange, yellow, lime, grayGreen, teal, lightBlue, blue, navy, purple, grape, pink, grayBrown,
    gray, grayBlue
}

public protocol AppShortcutsProvider {
  @AppShortcutsBuilder static var appShortcuts: [AppShortcut] { get }
  static var shortcutTileColor: ShortcutTileColor { get }
}
extension AppShortcutsProvider {
  public static var shortcutTileColor: ShortcutTileColor { return .blue }
  /// Nothing to tell: no system collects shortcuts here.
  public static func updateAppShortcutParameters() {}
}

// ---- the names intents write ------------------------------------------------------

extension AppIntent {
  public typealias Parameter<Value: _IntentValue> = IntentParameter<Value>
  public typealias Summary = IntentParameterSummary<Self>
  public typealias When<W: ParameterSummary, O: ParameterSummary> = ParameterSummaryWhenCondition<Self, W, O>
}
extension AppEntity {
  public typealias Property<Value: _IntentValue> = EntityProperty<Value>
}
