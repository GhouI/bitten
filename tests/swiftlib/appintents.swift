// AppIntents: an intent with parameters and a summary, an entity with its
// query, results, shortcuts, and the defaults the protocols supply.
import Dispatch
import Foundation
import AppIntents

struct Note: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Note"
  static var defaultQuery = NoteQuery()
  var id: String
  @EntityProperty(title: "Title") var title: String
  @EntityProperty(title: "Pinned") var pinned: Bool
  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title)", subtitle: pinned ? "pinned" : nil, image: .init(systemName: "note.text"))
  }
  init(id: String, title: String, pinned: Bool) {
    self.id = id
    self.title = title
    self.pinned = pinned
  }
}

struct NoteQuery: EnumerableEntityQuery, EntityStringQuery {
  typealias Result = [Note]
  typealias DefaultValue = Note
  static let all = [Note(id: "a", title: "Groceries", pinned: true), Note(id: "b", title: "Ideas", pinned: false)]
  func entities(for identifiers: [String]) async throws -> [Note] { Self.all.filter { identifiers.contains($0.id) } }
  func suggestedEntities() async throws -> [Note] { Self.all.filter { $0.pinned } }
  func allEntities() async throws -> [Note] { Self.all }
  func entities(matching string: String) async throws -> [Note] { Self.all.filter { $0.title.contains(string) } }
}

struct OpenNote: AppIntent {
  static var title: LocalizedStringResource = "Open Note"
  static var description: IntentDescription? = IntentDescription("Opens a note", categoryName: "Notes")
  @Parameter(title: "Note") var note: Note
  @Parameter(title: "Text", default: "hello") var text: String
  @Parameter(title: "Loud", default: false) var loud: Bool
  @Parameter(title: "Comment") var comment: String?
  static var parameterSummary: some ParameterSummary {
    Summary("Open \(\.$note) with \(\.$text)") {
      \.$loud
    }
  }
  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    return .result(value: loud ? text.uppercased() : text)
  }
}

struct Shortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: OpenNote(), phrases: ["Open a note in \(.applicationName)"], shortTitle: "Open Note",
                systemImageName: "note")
  }
}

final class Box<T>: @unchecked Sendable {
  var value: T?
  init() {}
}

func wait<T>(_ body: @escaping @Sendable () async throws -> T) -> T? {
  let box = Box<T>()
  let done = DispatchSemaphore(value: 0)
  Task {
    box.value = try? await body()
    done.signal()
  }
  done.wait()
  return box.value
}

@_silgen_name("swl_ai_entities") public func entities() -> Int {
  var bad = 0
  let q = NoteQuery()
  if wait({ try await q.entities(for: ["b"]) })?.map(\.title) != ["Ideas"] { bad |= 1 }
  if wait({ try await q.results() })?.map(\.id) != ["a"] { bad |= 2 }   // the default: suggested
  if wait({ try await q.entities(matching: "Gro") })?.count != 1 { bad |= 4 }
  if wait({ try await q.allEntities() })?.count != 2 { bad |= 8 }
  if NoteQuery.findIntentDescription != nil { bad |= 0x10 }
  let n = NoteQuery.all[0]
  if String(localized: n.localizedStringResource) != "Groceries" { bad |= 0x20 }
  if n.displayRepresentation.image?.systemName != "note.text" { bad |= 0x40 }
  if Note.persistentIdentifier != "Note" || String(localized: Note.typeDisplayRepresentation.name) != "Note" { bad |= 0x80 }
  if "a".entityIdentifierString != "a" || String.entityIdentifier(for: "z") != "z" { bad |= 0x100 }
  return bad
}

@_silgen_name("swl_ai_intents") public func intents() -> Int {
  var bad = 0
  var intent = OpenNote()
  if intent.text != "hello" || intent.loud || intent.comment != nil { bad |= 1 }
  intent.note = NoteQuery.all[1]
  intent.loud = true
  if intent.note.id != "b" || String(localized: intent.$text.title) != "Text" { bad |= 2 }
  let run = intent
  let r = wait({ try await run.perform() })
  if (r as? IntentResultContainer<String, Never, Never, Never>)?.value != "HELLO" { bad |= 4 }
  if OpenNote.openAppWhenRun || !OpenNote.isDiscoverable || OpenNote.authenticationPolicy != .alwaysAllowed { bad |= 8 }
  if String(localized: OpenNote.description!.descriptionText) != "Opens a note" { bad |= 0x10 }
  let summary = OpenNote.parameterSummary as? IntentParameterSummary<OpenNote>
  if summary == nil || summary!.parameters.count != 1 || !summary!.summary.text.hasPrefix("Open ") { bad |= 0x20 }
  let s = Shortcuts.appShortcuts
  if s.count != 1 || s[0].phrases != ["Open a note in ${applicationName}"] || Shortcuts.shortcutTileColor != .blue { bad |= 0x40 }
  return bad
}
