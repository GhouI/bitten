// UniformTypeIdentifiers' Swift API (libswiftUniformTypeIdentifiers): UTType
// over a table of the system's declared types. The table holds each type's
// identifier, the types it conforms to, its filename extensions and MIME
// types; a filename extension or MIME type the table does not know gives a
// dynamic type ("dyn." + the tag) conforming to the type asked for, as
// Apple's does.
import Foundation

public struct UTType: Hashable, Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
  public let identifier: String

  internal init(_id identifier: String) { self.identifier = identifier }

  /// A declared type with this identifier, or nil.
  public init?(_ identifier: String) {
    let e = _UTTable.entry(identifier)
    guard e != nil || identifier.lowercased().hasPrefix("dyn.") else { return nil }
    self.identifier = e?.id ?? identifier
  }

  public init?(filenameExtension: String) {
    self.init(filenameExtension: filenameExtension, conformingTo: .data)
  }
  public init?(filenameExtension: String, conformingTo supertype: UTType) {
    let ext = filenameExtension.lowercased()
    guard !ext.isEmpty else { return nil }
    if let e = _UTTable.byExtension[ext]?.first(where: { UTType(_id: $0.id).conforms(to: supertype) }) {
      self.identifier = e.id
    } else {
      self.identifier = _UTTable.dynamicID("ext", ext, supertype)
    }
  }
  public init?(mimeType: String) {
    self.init(mimeType: mimeType, conformingTo: .data)
  }
  public init?(mimeType: String, conformingTo supertype: UTType) {
    let mime = mimeType.lowercased()
    guard !mime.isEmpty else { return nil }
    if let e = _UTTable.byMIME[mime]?.first(where: { UTType(_id: $0.id).conforms(to: supertype) }) {
      self.identifier = e.id
    } else {
      self.identifier = _UTTable.dynamicID("mime", mime, supertype)
    }
  }
  /// A type the program declares in its Info.plist; here, the identifier
  /// as given (declarations are not read).
  public init(exportedAs identifier: String, conformingTo parentType: UTType? = nil) {
    self.identifier = identifier
    _UTTable.declare(identifier, parentType ?? .data)
  }
  public init(importedAs identifier: String, conformingTo parentType: UTType? = nil) {
    self.identifier = identifier
    _UTTable.declare(identifier, parentType ?? .data)
  }

  // ---- what a type is ----

  public var preferredFilenameExtension: String? { return _UTTable.entry(identifier)?.exts.first ?? _UTTable.dynamicTag(identifier, "ext") }
  public var preferredMIMEType: String? { return _UTTable.entry(identifier)?.mimes.first ?? _UTTable.dynamicTag(identifier, "mime") }
  public var localizedDescription: String? { return _UTTable.entry(identifier)?.name }
  public var isDeclared: Bool { return _UTTable.entry(identifier) != nil }
  public var isDynamic: Bool { return identifier.hasPrefix("dyn.") }
  public var isPublic: Bool { return identifier.hasPrefix("public.") }
  public var version: Int? { return nil }
  public var referenceURL: URL? { return nil }

  /// Every type this one conforms to, directly or not (not itself).
  public var supertypes: Set<UTType> {
    var out = Set<UTType>()
    var todo = _UTTable.parents(identifier)
    while let id = todo.popLast() {
      if out.insert(UTType(_id: id)).inserted { todo += _UTTable.parents(id) }
    }
    return out
  }
  public func conforms(to type: UTType) -> Bool {
    return self == type || supertypes.contains(type)
  }
  public func isSupertype(of type: UTType) -> Bool { return type != self && type.conforms(to: self) }
  public func isSubtype(of type: UTType) -> Bool { return type != self && conforms(to: type) }

  public var description: String { return identifier }
  public var debugDescription: String { return identifier }

  public static func == (a: UTType, b: UTType) -> Bool {
    return a.identifier.lowercased() == b.identifier.lowercased()
  }
  public func hash(into h: inout Hasher) { h.combine(identifier.lowercased()) }

  public init(from decoder: Decoder) throws {
    identifier = try decoder.singleValueContainer().decode(String.self)
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    try c.encode(identifier)
  }

  /// The declared types with this tag ("public.filename-extension" or
  /// "public.mime-type") conforming to a type.
  public static func types(tag: String, tagClass: UTTagClass, conformingTo supertype: UTType?) -> [UTType] {
    let t = tag.lowercased()
    let list = tagClass == .filenameExtension ? _UTTable.byExtension[t] : _UTTable.byMIME[t]
    return (list ?? []).map { UTType(_id: $0.id) }.filter { supertype == nil || $0.conforms(to: supertype!) }
  }
  public var tags: [UTTagClass: [String]] {
    guard let e = _UTTable.entry(identifier) else { return [:] }
    var out: [UTTagClass: [String]] = [:]
    if !e.exts.isEmpty { out[.filenameExtension] = e.exts }
    if !e.mimes.isEmpty { out[.mimeType] = e.mimes }
    return out
  }
}

public struct UTTagClass: RawRepresentable, Hashable, Sendable {
  public var rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public static var filenameExtension: UTTagClass { return UTTagClass(rawValue: "public.filename-extension") }
  public static var mimeType: UTTagClass { return UTTagClass(rawValue: "public.mime-type") }
}

// ---- the table ----

internal final class _UTEntry: @unchecked Sendable {
  let id: String, parents: [String], exts: [String], mimes: [String], name: String
  init(_ id: String, _ parents: [String], _ exts: [String], _ mimes: [String], _ name: String) {
    self.id = id; self.parents = parents; self.exts = exts; self.mimes = mimes; self.name = name
  }
}

internal enum _UTTable {
  static let entries: [_UTEntry] = [
    _UTEntry("public.item", [], [], [], "item"),
    _UTEntry("public.content", [], [], [], "content"),
    _UTEntry("public.composite-content", ["public.content"], [], [], "composite content"),
    _UTEntry("public.data", ["public.item"], [], ["application/octet-stream"], "data"),
    _UTEntry("public.directory", ["public.item"], [], [], "directory"),
    _UTEntry("public.folder", ["public.directory"], [], [], "folder"),
    _UTEntry("public.volume", ["public.folder"], [], [], "volume"),
    _UTEntry("com.apple.package", ["public.directory"], [], [], "package"),
    _UTEntry("com.apple.bundle", ["public.directory"], ["bundle"], [], "bundle"),
    _UTEntry("com.apple.plugin", ["com.apple.bundle", "com.apple.package"], ["plugin"], [], "plug-in"),
    _UTEntry("public.symlink", ["public.item"], [], [], "symbolic link"),
    _UTEntry("com.apple.alias-file", ["public.data"], [], [], "alias"),
    _UTEntry("public.url", ["public.data"], [], [], "URL"),
    _UTEntry("public.file-url", ["public.url"], [], [], "file URL"),
    _UTEntry("com.microsoft.internet-shortcut", ["public.url", "public.data"], ["url"], [], "Internet shortcut"),
    _UTEntry("com.apple.web-internet-location", ["public.data"], ["webloc"], [], "Web internet location"),
    // executables and applications
    _UTEntry("public.executable", ["public.item"], [], [], "executable"),
    _UTEntry("public.unix-executable", ["public.data", "public.executable"], [], [], "Unix executable"),
    _UTEntry("com.microsoft.windows-executable", ["public.data", "public.executable"], ["exe"], ["application/x-msdownload"], "Windows executable"),
    _UTEntry("com.apple.application", ["public.executable"], [], [], "application"),
    _UTEntry("com.apple.application-bundle", ["com.apple.application", "com.apple.bundle", "com.apple.package"], ["app"], [], "application"),
    _UTEntry("com.apple.application-and-system-extension", ["com.apple.bundle"], ["appex"], [], "application extension"),
    _UTEntry("com.apple.framework", ["com.apple.bundle"], ["framework"], [], "framework"),
    // text and code
    _UTEntry("public.text", ["public.data", "public.content"], [], ["text/*"], "text"),
    _UTEntry("public.plain-text", ["public.text"], ["txt", "text"], ["text/plain"], "plain text"),
    _UTEntry("public.utf8-plain-text", ["public.plain-text"], [], [], "Unicode text"),
    _UTEntry("public.utf16-plain-text", ["public.plain-text"], [], [], "UTF-16 text"),
    _UTEntry("public.rtf", ["public.text"], ["rtf"], ["text/rtf"], "rich text"),
    _UTEntry("public.html", ["public.text"], ["html", "htm"], ["text/html"], "HTML"),
    _UTEntry("public.xml", ["public.text"], ["xml"], ["application/xml", "text/xml"], "XML"),
    _UTEntry("public.json", ["public.text"], ["json"], ["application/json"], "JSON"),
    _UTEntry("public.yaml", ["public.text"], ["yaml", "yml"], ["application/x-yaml"], "YAML"),
    _UTEntry("public.comma-separated-values-text", ["public.text"], ["csv"], ["text/csv"], "comma-separated values"),
    _UTEntry("public.tab-separated-values-text", ["public.text"], ["tsv"], ["text/tab-separated-values"], "tab-separated values"),
    _UTEntry("public.log", ["public.plain-text"], ["log"], [], "log"),
    _UTEntry("net.daringfireball.markdown", ["public.plain-text"], ["md", "markdown"], ["text/markdown"], "Markdown"),
    _UTEntry("public.source-code", ["public.plain-text"], [], [], "source code"),
    _UTEntry("public.script", ["public.source-code"], [], [], "script"),
    _UTEntry("public.shell-script", ["public.script"], ["sh", "command"], ["application/x-sh"], "shell script"),
    _UTEntry("public.zsh-script", ["public.shell-script"], ["zsh"], [], "Zsh script"),
    _UTEntry("public.bash-script", ["public.shell-script"], ["bash"], [], "Bash script"),
    _UTEntry("public.python-script", ["public.shell-script"], ["py"], ["text/x-python-script"], "Python script"),
    _UTEntry("public.ruby-script", ["public.shell-script"], ["rb"], ["text/ruby-script"], "Ruby script"),
    _UTEntry("public.perl-script", ["public.shell-script"], ["pl", "pm"], ["text/x-perl-script"], "Perl script"),
    _UTEntry("com.netscape.javascript-source", ["public.script"], ["js", "mjs"], ["text/javascript"], "JavaScript"),
    _UTEntry("com.apple.applescript.text", ["public.script"], ["applescript"], [], "AppleScript"),
    _UTEntry("com.apple.applescript.script", ["public.data", "public.script"], ["scpt"], [], "compiled AppleScript"),
    _UTEntry("com.apple.applescript.script-bundle", ["com.apple.bundle", "com.apple.package", "public.script"], ["scptd"], [], "AppleScript bundle"),
    _UTEntry("public.swift-source", ["public.source-code"], ["swift"], [], "Swift source"),
    _UTEntry("public.c-source", ["public.source-code"], ["c"], [], "C source"),
    _UTEntry("public.c-header", ["public.source-code"], ["h"], [], "C header"),
    _UTEntry("public.c-plus-plus-source", ["public.source-code"], ["cpp", "cc", "cxx"], [], "C++ source"),
    _UTEntry("public.objective-c-source", ["public.source-code"], ["m"], [], "Objective-C source"),
    _UTEntry("com.apple.property-list", ["public.data"], ["plist"], [], "property list"),
    _UTEntry("com.apple.xml-property-list", ["public.xml", "com.apple.property-list"], [], [], "XML property list"),
    // images
    _UTEntry("public.image", ["public.data", "public.content"], [], ["image/*"], "image"),
    _UTEntry("public.png", ["public.image"], ["png"], ["image/png"], "PNG image"),
    _UTEntry("public.jpeg", ["public.image"], ["jpeg", "jpg"], ["image/jpeg"], "JPEG image"),
    _UTEntry("public.tiff", ["public.image"], ["tiff", "tif"], ["image/tiff"], "TIFF image"),
    _UTEntry("com.compuserve.gif", ["public.image"], ["gif"], ["image/gif"], "GIF image"),
    _UTEntry("public.heic", ["public.image"], ["heic"], ["image/heic"], "HEIC image"),
    _UTEntry("org.webmproject.webp", ["public.image"], ["webp"], ["image/webp"], "WebP image"),
    _UTEntry("com.microsoft.bmp", ["public.image"], ["bmp"], ["image/bmp"], "BMP image"),
    _UTEntry("com.microsoft.ico", ["public.image"], ["ico"], ["image/vnd.microsoft.icon"], "Windows icon"),
    _UTEntry("com.apple.icns", ["public.image"], ["icns"], [], "Apple icon"),
    _UTEntry("public.svg-image", ["public.image", "public.xml"], ["svg"], ["image/svg+xml"], "SVG image"),
    _UTEntry("com.adobe.pdf", ["public.data", "public.composite-content"], ["pdf"], ["application/pdf"], "PDF document"),
    // audio and video
    _UTEntry("public.audiovisual-content", ["public.data", "public.content"], [], [], "audiovisual content"),
    _UTEntry("public.audio", ["public.audiovisual-content"], [], ["audio/*"], "audio"),
    _UTEntry("public.mp3", ["public.audio"], ["mp3"], ["audio/mpeg"], "MP3 audio"),
    _UTEntry("com.microsoft.waveform-audio", ["public.audio"], ["wav"], ["audio/wav"], "WAVE audio"),
    _UTEntry("public.movie", ["public.audiovisual-content"], [], ["video/*"], "movie"),
    _UTEntry("public.mpeg-4", ["public.movie"], ["mp4"], ["video/mp4"], "MPEG-4 movie"),
    _UTEntry("com.apple.quicktime-movie", ["public.movie"], ["mov"], ["video/quicktime"], "QuickTime movie"),
    // archives, disk images, fonts
    _UTEntry("public.archive", ["public.data"], [], [], "archive"),
    _UTEntry("public.zip-archive", ["public.archive"], ["zip"], ["application/zip"], "ZIP archive"),
    _UTEntry("org.gnu.gnu-zip-archive", ["public.archive"], ["gz", "gzip"], ["application/gzip"], "gzip archive"),
    _UTEntry("public.tar-archive", ["public.archive"], ["tar"], ["application/x-tar"], "tar archive"),
    _UTEntry("public.bzip2-archive", ["public.archive"], ["bz2"], ["application/x-bzip2"], "bzip2 archive"),
    _UTEntry("public.disk-image", ["public.archive"], [], [], "disk image"),
    _UTEntry("com.apple.disk-image-udif", ["public.disk-image"], ["dmg"], [], "disk image"),
    _UTEntry("public.font", ["public.data", "public.content"], [], [], "font"),
    _UTEntry("public.truetype-ttf-font", ["public.font"], ["ttf"], ["font/ttf"], "TrueType font"),
    _UTEntry("public.opentype-font", ["public.font"], ["otf"], ["font/otf"], "OpenType font"),
    _UTEntry("public.database", ["public.data"], [], [], "database"),
    _UTEntry("public.calendar-event", ["public.data"], ["ics"], ["text/calendar"], "calendar event"),
    _UTEntry("public.vcard", ["public.text"], ["vcf"], ["text/vcard"], "vCard"),
  ]

  // Types programs declare at run time, after the table.
  nonisolated(unsafe) static var declared: [String: _UTEntry] = [:]
  static let lock = NSRecursiveLock()

  static let byID: [String: _UTEntry] = {
    var d: [String: _UTEntry] = [:]
    for e in entries { d[e.id.lowercased()] = e }
    return d
  }()
  static let byExtension: [String: [_UTEntry]] = {
    var d: [String: [_UTEntry]] = [:]
    for e in entries { for x in e.exts { d[x, default: []].append(e) } }
    return d
  }()
  static let byMIME: [String: [_UTEntry]] = {
    var d: [String: [_UTEntry]] = [:]
    for e in entries { for m in e.mimes where !m.hasSuffix("/*") { d[m, default: []].append(e) } }
    return d
  }()

  static func entry(_ id: String) -> _UTEntry? {
    let key = id.lowercased()
    if let e = byID[key] { return e }
    lock.lock()
    defer { lock.unlock() }
    return declared[key]
  }
  static func declare(_ id: String, _ parent: UTType) {
    let key = id.lowercased()
    if byID[key] != nil { return }
    lock.lock()
    if declared[key] == nil { declared[key] = _UTEntry(id, [parent.identifier], [], [], id) }
    lock.unlock()
  }

  /// Dynamic identifiers carry their tag and supertype in the name:
  /// "dyn." + class + "." + supertype + "." + tag (Apple encodes them; the
  /// shape only matters to this table).
  static func dynamicID(_ tagClass: String, _ tag: String, _ supertype: UTType) -> String {
    return "dyn.\(tagClass).\(supertype.identifier).\(tag)"
  }
  static func dynamicTag(_ id: String, _ tagClass: String) -> String? {
    guard id.hasPrefix("dyn.\(tagClass).") else { return nil }
    return id.split(separator: ".").last.map(String.init)
  }
  static func parents(_ id: String) -> [String] {
    if let e = entry(id) { return e.parents }
    if id.hasPrefix("dyn.") {
      // dyn.<class>.<supertype id>.<tag>: the supertype is everything between.
      var parts = id.split(separator: ".").map(String.init)
      guard parts.count >= 4 else { return ["public.data"] }
      parts.removeFirst(2)
      parts.removeLast()
      return [parts.joined(separator: ".")]
    }
    return []
  }
}

// ---- the system's types ----

extension UTType {
  public static var item: UTType { return UTType(_id: "public.item") }
  public static var content: UTType { return UTType(_id: "public.content") }
  public static var compositeContent: UTType { return UTType(_id: "public.composite-content") }
  public static var data: UTType { return UTType(_id: "public.data") }
  public static var directory: UTType { return UTType(_id: "public.directory") }
  public static var folder: UTType { return UTType(_id: "public.folder") }
  public static var volume: UTType { return UTType(_id: "public.volume") }
  public static var package: UTType { return UTType(_id: "com.apple.package") }
  public static var bundle: UTType { return UTType(_id: "com.apple.bundle") }
  public static var pluginBundle: UTType { return UTType(_id: "com.apple.plugin") }
  public static var symbolicLink: UTType { return UTType(_id: "public.symlink") }
  public static var aliasFile: UTType { return UTType(_id: "com.apple.alias-file") }
  public static var url: UTType { return UTType(_id: "public.url") }
  public static var fileURL: UTType { return UTType(_id: "public.file-url") }
  public static var internetShortcut: UTType { return UTType(_id: "com.microsoft.internet-shortcut") }
  public static var executable: UTType { return UTType(_id: "public.executable") }
  public static var unixExecutable: UTType { return UTType(_id: "public.unix-executable") }
  public static var exe: UTType { return UTType(_id: "com.microsoft.windows-executable") }
  public static var application: UTType { return UTType(_id: "com.apple.application") }
  public static var applicationBundle: UTType { return UTType(_id: "com.apple.application-bundle") }
  public static var applicationExtension: UTType { return UTType(_id: "com.apple.application-and-system-extension") }
  public static var framework: UTType { return UTType(_id: "com.apple.framework") }
  public static var text: UTType { return UTType(_id: "public.text") }
  public static var plainText: UTType { return UTType(_id: "public.plain-text") }
  public static var utf8PlainText: UTType { return UTType(_id: "public.utf8-plain-text") }
  public static var utf16PlainText: UTType { return UTType(_id: "public.utf16-plain-text") }
  public static var rtf: UTType { return UTType(_id: "public.rtf") }
  public static var html: UTType { return UTType(_id: "public.html") }
  public static var xml: UTType { return UTType(_id: "public.xml") }
  public static var json: UTType { return UTType(_id: "public.json") }
  public static var yaml: UTType { return UTType(_id: "public.yaml") }
  public static var commaSeparatedText: UTType { return UTType(_id: "public.comma-separated-values-text") }
  public static var tabSeparatedText: UTType { return UTType(_id: "public.tab-separated-values-text") }
  public static var log: UTType { return UTType(_id: "public.log") }
  public static var sourceCode: UTType { return UTType(_id: "public.source-code") }
  public static var script: UTType { return UTType(_id: "public.script") }
  public static var shellScript: UTType { return UTType(_id: "public.shell-script") }
  public static var pythonScript: UTType { return UTType(_id: "public.python-script") }
  public static var rubyScript: UTType { return UTType(_id: "public.ruby-script") }
  public static var perlScript: UTType { return UTType(_id: "public.perl-script") }
  public static var javaScript: UTType { return UTType(_id: "com.netscape.javascript-source") }
  public static var appleScript: UTType { return UTType(_id: "com.apple.applescript.text") }
  public static var osaScript: UTType { return UTType(_id: "com.apple.applescript.script") }
  public static var osaScriptBundle: UTType { return UTType(_id: "com.apple.applescript.script-bundle") }
  public static var swiftSource: UTType { return UTType(_id: "public.swift-source") }
  public static var cSource: UTType { return UTType(_id: "public.c-source") }
  public static var cHeader: UTType { return UTType(_id: "public.c-header") }
  public static var cPlusPlusSource: UTType { return UTType(_id: "public.c-plus-plus-source") }
  public static var objectiveCSource: UTType { return UTType(_id: "public.objective-c-source") }
  public static var propertyList: UTType { return UTType(_id: "com.apple.property-list") }
  public static var xmlPropertyList: UTType { return UTType(_id: "com.apple.xml-property-list") }
  public static var image: UTType { return UTType(_id: "public.image") }
  public static var png: UTType { return UTType(_id: "public.png") }
  public static var jpeg: UTType { return UTType(_id: "public.jpeg") }
  public static var tiff: UTType { return UTType(_id: "public.tiff") }
  public static var gif: UTType { return UTType(_id: "com.compuserve.gif") }
  public static var heic: UTType { return UTType(_id: "public.heic") }
  public static var webP: UTType { return UTType(_id: "org.webmproject.webp") }
  public static var bmp: UTType { return UTType(_id: "com.microsoft.bmp") }
  public static var ico: UTType { return UTType(_id: "com.microsoft.ico") }
  public static var icns: UTType { return UTType(_id: "com.apple.icns") }
  public static var svg: UTType { return UTType(_id: "public.svg-image") }
  public static var pdf: UTType { return UTType(_id: "com.adobe.pdf") }
  public static var audiovisualContent: UTType { return UTType(_id: "public.audiovisual-content") }
  public static var audio: UTType { return UTType(_id: "public.audio") }
  public static var mp3: UTType { return UTType(_id: "public.mp3") }
  public static var wav: UTType { return UTType(_id: "com.microsoft.waveform-audio") }
  public static var movie: UTType { return UTType(_id: "public.movie") }
  public static var mpeg4Movie: UTType { return UTType(_id: "public.mpeg-4") }
  public static var quickTimeMovie: UTType { return UTType(_id: "com.apple.quicktime-movie") }
  public static var archive: UTType { return UTType(_id: "public.archive") }
  public static var zip: UTType { return UTType(_id: "public.zip-archive") }
  public static var gzip: UTType { return UTType(_id: "org.gnu.gnu-zip-archive") }
  public static var diskImage: UTType { return UTType(_id: "public.disk-image") }
  public static var font: UTType { return UTType(_id: "public.font") }
  public static var database: UTType { return UTType(_id: "public.database") }
  public static var calendarEvent: UTType { return UTType(_id: "public.calendar-event") }
  public static var vCard: UTType { return UTType(_id: "public.vcard") }
}

// ---- Foundation ----

extension URLResourceValues {
  /// The file's type: the type identifier Foundation fetched, else what the
  /// directory flags and the filename extension say.
  public var contentType: UTType? {
    if let id = allValues[.typeIdentifierKey] as? String, let t = UTType(id) { return t }
    if (allValues[.isDirectoryKey] as? Bool) == true {
      if (allValues[.isPackageKey] as? Bool) == true {
        if let path = allValues[.pathKey] as? String, path.hasSuffix(".app") { return .applicationBundle }
        return .package
      }
      return .folder
    }
    if (allValues[.isSymbolicLinkKey] as? Bool) == true { return .symbolicLink }
    if let name = (allValues[.nameKey] as? String) ?? (allValues[.pathKey] as? String),
       let dot = name.lastIndex(of: "."), dot != name.startIndex {
      return UTType(filenameExtension: String(name[name.index(after: dot)...]))
    }
    if (allValues[.isRegularFileKey] as? Bool) == true { return .data }
    return nil
  }
}

extension URL {
  /// A file URL for a name with the type's preferred extension.
  public func appendingPathComponent(_ partialName: String, conformingTo contentType: UTType) -> URL {
    guard let ext = contentType.preferredFilenameExtension else { return appendingPathComponent(partialName) }
    return appendingPathComponent(partialName).appendingPathExtension(ext)
  }
}

// ---- item providers ----

extension NSItemProvider {
  /// A file of the given type: a copy (removed when the handler returns,
  /// as on macOS), or the file itself when opening in place is allowed.
  public func loadFileRepresentation(for contentType: UTType, openInPlace: Bool = false,
                                     completionHandler: @escaping @Sendable (URL?, Bool, Error?) -> Void) -> NSProgress {
    let progress: NSProgress?
    if openInPlace {
      progress = loadInPlaceFileRepresentation(forTypeIdentifier: contentType.identifier) { url, inPlace, error in
        completionHandler(url, inPlace, error)
      }
    } else {
      progress = loadFileRepresentation(forTypeIdentifier: contentType.identifier) { url, error in
        completionHandler(url, false, error)
      }
    }
    return progress ?? NSProgress(totalUnitCount: 1)
  }

  /// The registered type identifiers as types.
  public var registeredContentTypes: [UTType] {
    return registeredTypeIdentifiers.compactMap { UTType($0) }
  }
}
