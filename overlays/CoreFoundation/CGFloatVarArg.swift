// CGFloat in C variadic calls (String(format:), os_log...): passed as a
// Double, as on 64-bit Darwin. Mangled under CoreGraphics with the type.

@available(macOS 10.15, *)
@_originallyDefinedIn(module: "CoreGraphics", macOS 14.0)
extension CGFloat: _CVarArgPassedAsDouble {
  public var _cVarArgEncoding: [Int] { return native._cVarArgEncoding }
}
