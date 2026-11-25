// @_cdecl entry points: the compiler builds their C signatures through the
// C type aliases (CInt, CLong, CDouble...) of the standard library.

@_cdecl("swd_scale") public func scale(_ x: CInt, _ by: CDouble) -> CDouble {
  return Double(x) * by
}
@_cdecl("swd_sum") public func sum(_ p: UnsafePointer<CLong>, _ n: CLong) -> CLong {
  var s = 0
  for i in 0..<n { s += p[i] }
  return s
}
@_cdecl("swd_flag") public func flag(_ b: CBool) -> CUnsignedChar { b ? 0xAB : 0 }
