// String: the two-word representation (checked word by word against the
// layout compiled programs inline), literals, copies and mutation,
// comparison, hashing, C strings. Each function returns a bit per failed
// check.

@inline(never) func words(_ s: String) -> (UInt64, UInt64) {
  var c = s
  return withUnsafeBytes(of: &c) { ($0.load(fromByteOffset: 0, as: UInt64.self),
                                    $0.load(fromByteOffset: 8, as: UInt64.self)) }
}
@inline(never) func opaque(_ s: String) -> String { s }

@_silgen_name("swl_strings_layout") public func layout(_ literalAddress: UnsafeMutablePointer<UInt64>) -> Int {
  var bad = 0
  if MemoryLayout<String>.size != 16 || MemoryLayout<String>.stride != 16 { bad |= 1 }
  // Empty: (0, 0xE0...).
  let e = words("")
  if e.0 != 0 || e.1 != (0xE000_0000_0000_0000 as UInt64) { bad |= 2 }
  // Small ASCII: bytes in order, discriminator 0xE0 | count.
  let s = words(opaque("hello"))
  if s.0 != (0x6F_6C6C_6568 as UInt64) || s.1 != (0xE500_0000_0000_0000 as UInt64) { bad |= 4 }
  let s15 = words(opaque("abcdefghijklmno"))
  if s15.0 != (0x6867_6665_6463_6261 as UInt64) || s15.1 != (0xEF6F_6E6D_6C6B_6A69 as UInt64) { bad |= 8 }
  // Small non-ASCII: 0xA0 | count ("é" is C3 A9).
  let u = words(opaque("é"))
  if u.0 != 0xA9C3 || u.1 != (0xA200_0000_0000_0000 as UInt64) { bad |= 16 }
  // Large literal: ASCII|NFC|tail-allocated|count, immortal biased address.
  let lit = "this literal is longer than fifteen bytes"
  let l = words(opaque(lit))
  if l.0 != (0xD000_0000_0000_0000 as UInt64) | 41 { bad |= 32 }
  if l.1 & (0xF000_0000_0000_0000 as UInt64) != (0x8000_0000_0000_0000 as UInt64) { bad |= 64 }
  literalAddress.pointee = (l.1 & (0x0FFF_FFFF_FFFF_FFFF as UInt64)) &+ 32
  // Non-ASCII large literal: only tail-allocated.
  let nl = words(opaque("ünïcödé text, longer than 15"))
  if nl.0 != (0x1000_0000_0000_0000 as UInt64) | 32 { bad |= 128 }
  // Native: natively stored + tail allocated, object is a plain pointer.
  var n = opaque("0123456789")
  n += "abcdefghij"
  let nw = words(n)
  if nw.0 != (0xF000_0000_0000_0000 as UInt64) | 20 || nw.1 & (0xF000_0000_0000_0000 as UInt64) != 0 || nw.1 == 0 { bad |= 256 }
  if UnsafePointer<UInt8>(bitPattern: UInt(nw.1 &+ 32))!.pointee != 0x30 { bad |= 512 }
  return bad
}

@_silgen_name("swl_strings_basics") public func basics() -> Int {
  var bad = 0
  let empty = ""
  if !empty.isEmpty || !String().isEmpty || opaque("x").isEmpty { bad |= 1 }
  // Equality across representations: small, literal, native.
  let a = opaque("hello, world, this is long")
  var b = opaque("hello, world")
  b += ", this is long"
  if a != b || !(a == b) { bad |= 2 }
  var c = opaque("hel")
  c.append("lo")
  if c != "hello" || c == "hellO" { bad |= 4 }
  // Ordering: byte (scalar) order, prefixes first.
  if !(opaque("abc") < "abd") || !(opaque("ab") < "abc") || opaque("b") < "abc" { bad |= 8 }
  if !(opaque("Z") < "a") || !(opaque("z") < "é") { bad |= 16 }
  // Hashing: equal strings hash alike whatever their form.
  if a.hashValue != b.hashValue || c.hashValue != opaque("hello").hashValue { bad |= 32 }
  if a.hashValue == opaque("hello, world, this is lonG").hashValue { bad |= 64 }
  // Copy on write: appending to a copy leaves the original alone.
  var d = b
  d += "!"
  if b != a || d == b || d != "hello, world, this is long!" { bad |= 128 }
  // Growing from small to native and back through + .
  var e = ""
  var i = 0
  while i < 100 { e += "ab"; i += 1 }
  if words(e).0 & 0xFFFF != 200 || !e.hasPrefix("abab") || !e.hasSuffix("abab") || e.hasPrefix("b") { bad |= 256 }
  if String(repeating: "ab", count: 100) != e { bad |= 512 }
  if opaque("x") + opaque("y") + "z" != "xyz" { bad |= 1024 }
  // Case.
  if opaque("Hello World").uppercased() != "HELLO WORLD" || opaque("Hello World").lowercased() != "hello world" { bad |= 2048 }
  if opaque("straße àÿ").uppercased() != "STRASSE ÀŸ" || opaque("ÀÉ").lowercased() != "àé" { bad |= 4096 }
  return bad
}

@_silgen_name("swl_strings_cstrings") public func cstrings(_ p: UnsafePointer<CChar>, _ bad8: UnsafePointer<UInt8>) -> Int {
  var bad = 0
  let s = String(cString: p)
  if s != "from C, a long enough string" { bad |= 1 }
  // Invalid UTF-8 is repaired with U+FFFD.
  let r = String(cString: bad8)
  if r != "a\u{FFFD}b\u{FFFD}" { bad |= 2 }
  if String(validatingCString: UnsafePointer<CChar>(OpaquePointer(bad8))) != nil { bad |= 4 }
  // String to C: literal, native, small.
  var n = 0
  opaque("abc").withCString { n += strlen($0) }
  opaque("a long literal string, 31 bytes").withCString { n += strlen($0) }
  (opaque("native ") + "string, 27 bytes long").withCString { n += strlen($0) }
  if n != 3 + 31 + 28 { bad |= 8 }
  // The implicit argument conversion.
  if strlen(opaque("conversion")) != 10 { bad |= 16 }
  return bad
}

@_silgen_name("strlen") func strlen(_ s: UnsafePointer<CChar>) -> Int
