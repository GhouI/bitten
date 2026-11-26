// UniformTypeIdentifiers: declared types, conformance, tags, dynamic types,
// Codable, and URLResourceValues.contentType.
import Foundation
import UniformTypeIdentifiers

@_silgen_name("swl_ut_types") public func types() -> Int {
  var bad = 0
  if UTType.png.identifier != "public.png" || UTType("public.PNG") != .png { bad |= 1 }
  if !UTType.png.conforms(to: .image) || !UTType.png.conforms(to: .data) || !UTType.png.conforms(to: .item) { bad |= 2 }
  if UTType.png.conforms(to: .text) || !UTType.image.isSupertype(of: .jpeg) || !UTType.jpeg.isSubtype(of: .image) { bad |= 4 }
  if UTType.applicationBundle.conforms(to: .application) == false || !UTType.applicationBundle.conforms(to: .directory) { bad |= 8 }
  if UTType(filenameExtension: "JPG") != .jpeg || UTType(mimeType: "application/json") != .json { bad |= 0x10 }
  if UTType.jpeg.preferredFilenameExtension != "jpeg" || UTType.json.preferredMIMEType != "application/json" { bad |= 0x20 }
  if UTType("com.example.nothing") != nil { bad |= 0x40 }
  if !UTType.pythonScript.conforms(to: .script) || !UTType.osaScript.conforms(to: .script) { bad |= 0x80 }
  if UTType.unixExecutable.conforms(to: .executable) == false || !UTType.exe.conforms(to: .executable) { bad |= 0x100 }
  // An unknown extension: a dynamic type under the type asked for.
  guard let dyn = UTType(filenameExtension: "frobz", conformingTo: .text) else { return bad | 0x200 }
  if !dyn.isDynamic || dyn.isDeclared || !dyn.conforms(to: .text) || dyn.conforms(to: .image) { bad |= 0x400 }
  if dyn.preferredFilenameExtension != "frobz" { bad |= 0x800 }
  if UTType(filenameExtension: "png", conformingTo: .text)?.isDynamic != true { bad |= 0x1000 }
  if UTType.png.tags[.filenameExtension] != ["png"] { bad |= 0x2000 }
  let mine = UTType(exportedAs: "com.example.thing", conformingTo: .json)
  if !mine.conforms(to: .text) || UTType("com.example.thing") == nil { bad |= 0x4000 }
  return bad
}

@_silgen_name("swl_ut_foundation") public func foundation() -> Int {
  var bad = 0
  let data = try? JSONEncoder().encode([UTType.pdf])
  if let d = data, String(decoding: d, as: UTF8.self) != "[\"com.adobe.pdf\"]" { bad |= 1 }
  if let d = data, (try? JSONDecoder().decode([UTType].self, from: d)) != [.pdf] { bad |= 2 }
  let dir = URL(fileURLWithPath: "/tmp")
  if let t = (try? dir.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .pathKey]))?.contentType {
    if t != .folder { bad |= 4 }
  } else { bad |= 8 }
  let file = URL(fileURLWithPath: "/etc/hostname.json")
  var v = URLResourceValues()
  v.name = file.lastPathComponent
  if v.contentType != .json { bad |= 0x10 }
  if dir.appendingPathComponent("notes", conformingTo: .plainText).lastPathComponent != "notes.txt" { bad |= 0x20 }
  return bad
}
