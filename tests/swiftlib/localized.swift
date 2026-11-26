// String.LocalizationValue, LocalizedStringResource and String(localized:):
// keys built from interpolations, defaults, and lookups in a .strings table
// that reorders its arguments.
import Foundation

@_silgen_name("swl_loc_defaults") public func defaults() -> Int {
  var bad = 0
  let name = "Bob", count = 3
  if String(localized: "Hello \(name), you have \(count) items") != "Hello Bob, you have 3 items" { bad |= 1 }
  let pi = 3.14159
  if String(localized: "pi is \(pi, specifier: "%.2f")") != "pi is 3.14" { bad |= 2 }
  if String(localized: "100% sure") != "100% sure" { bad |= 4 }
  let r: LocalizedStringResource = "Hello \(name)"
  if r.key != "Hello %@" || String(localized: r) != "Hello Bob" { bad |= 8 }
  let r2 = LocalizedStringResource("Hello \(name)", table: nil)
  if r != r2 || r == LocalizedStringResource("Hello \("Ann")") { bad |= 0x10 }
  let v: String.LocalizationValue = "Count: \(Int32(7)) and \(UInt32(8))"
  if String(localized: v) != "Count: 7 and 8" { bad |= 0x20 }
  if LocalizedStringResource(stringLiteral: "Plain").key != "Plain" { bad |= 0x40 }
  if String(localized: "Plain", table: "NoSuchTable") != "Plain" { bad |= 0x80 }
  if String(format: "%.2f|%d", CGFloat(2.5), 7) != "2.50|7" { bad |= 0x100 }   // CGFloat: CVarArg
  return bad
}

@_silgen_name("swl_loc_table") public func table() -> Int {
  var bad = 0
  let dir = "/tmp/bitten-loc-\(getpid())"
  let resources = dir + "/Contents/Resources"
  try? FileManager.default.createDirectory(atPath: resources, withIntermediateDirectories: true, attributes: nil)
  let strings = "\"Hello %@, you have %lld items\" = \"%2$lld items for %1$@\";\n\"Plain\" = \"Translated\";\n"
  guard FileManager.default.createFile(atPath: resources + "/Localizable.strings", contents: Data(strings.utf8),
                                       attributes: [:]),
        let bundle = Bundle(path: dir) else { return 1 }
  let name = "Bob", count = 3
  if String(localized: "Hello \(name), you have \(count) items", bundle: bundle) != "3 items for Bob" { bad |= 2 }
  if String(localized: "Plain", bundle: bundle) != "Translated" { bad |= 4 }
  let r = LocalizedStringResource("Plain", bundle: .atURL(URL(fileURLWithPath: dir)))
  if String(localized: r) != "Translated" { bad |= 8 }
  return bad
}
