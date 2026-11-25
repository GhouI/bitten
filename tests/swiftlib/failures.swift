// StaticString, Unicode.Scalar and the failure entry points: what a
// force-unwrap of nil, an overflow check and an unimplemented initializer
// print before trapping. The C driver runs each failure in a child process.

@_silgen_name("swl_debug") public func debug() -> Bool { _isDebugAssertConfiguration() }

@inline(never) func identity<T>(_ x: T) -> T { x }

@_silgen_name("swl_static_count") public func staticCount() -> Int {
  let s: StaticString = "héllo"     // 6 UTF-8 code units, not ASCII
  let t: StaticString = "plain"
  let u = identity(StaticString())
  var r = s.utf8CodeUnitCount * 100 + t.utf8CodeUnitCount * 10 + u.utf8CodeUnitCount
  if !s.isASCII && t.isASCII && s.hasPointerRepresentation { r += 1000 }
  return r
}

@_silgen_name("swl_static_scalar") public func staticScalar() -> UInt32 {
  let s: StaticString = "é"   // a single-scalar literal: may use the scalar representation
  if s.hasPointerRepresentation { return s.isASCII || s.utf8CodeUnitCount != 2 ? 1 : 2 }
  return s.unicodeScalar.value
}

@_silgen_name("swl_scalar") public func scalar(_ v: UInt32) -> UInt32 {
  guard let s = Unicode.Scalar(v) else { return 0xFFFF_FFFF }
  let a: Unicode.Scalar = "A"
  return s.value &+ (s > a ? 0x1000_0000 : 0) &+ (s.isASCII ? 0x2000_0000 : 0)
}

@_silgen_name("swl_unwrap") public func unwrap(_ v: Int) -> Int {
  let o: Int? = v == 0 ? nil : v
  return identity(o)!
}

@_silgen_name("swl_overflow") public func overflow(_ a: Int) -> Int {
  return _overflowChecked((a, a > 100))
}

@_silgen_name("swl_unimplemented") public func unimplemented() -> Int {
  _unimplementedInitializer(className: "failures.Widget")
}
