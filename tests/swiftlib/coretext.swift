// CoreText from Swift: font files read into descriptors, and the casts a
// program makes on what comes back (CFArray to [CTFontDescriptor]).
import CoreText
import Foundation

@_silgen_name("swl_ct_files") public func files() -> Int {
  var bad = 0
  let paths = ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/TTF/DejaVuSans.ttf"]
  guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return 0 }
  let url = URL(fileURLWithPath: path)
  guard let raw = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) else { return 1 }
  if CFArrayGetCount(raw) != 1 { bad |= 2 }
  guard let descriptors = raw as? [CTFontDescriptor] else { return bad | 4 }
  if descriptors.count != 1 { bad |= 8 }
  if let d = descriptors.first {
    let family = CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String
    if family != "DejaVu Sans" { bad |= 0x10 }
    let font = CTFontCreateWithFontDescriptor(d, 12, nil)
    if CTFontGetSize(font) != 12 { bad |= 0x20 }
  }
  let any: [Any] = raw as! [Any]
  if any.count != 1 || CFGetTypeID(any[0] as CFTypeRef) != CTFontDescriptorGetTypeID() { bad |= 0x40 }
  return bad
}
