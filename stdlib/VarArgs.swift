// C variadic arguments: values encoded as words, the way the x86-64 Darwin
// va_list passes them (integers and pointers in one word each, floating
// point as Double).

public protocol CVarArg {
  var _cVarArgEncoding: [Int] { get }
}
public protocol _CVarArgPassedAsDouble: CVarArg {}
public protocol _CVarArgAligned: CVarArg {
  var _cVarArgAlignment: Int { get }
}

extension Int: CVarArg { public var _cVarArgEncoding: [Int] { return [self] } }
extension Int8: CVarArg { public var _cVarArgEncoding: [Int] { return [Int(self)] } }
extension Int16: CVarArg { public var _cVarArgEncoding: [Int] { return [Int(self)] } }
extension Int32: CVarArg { public var _cVarArgEncoding: [Int] { return [Int(self)] } }
extension Int64: CVarArg { public var _cVarArgEncoding: [Int] { return [Int(self)] } }
extension UInt: CVarArg { public var _cVarArgEncoding: [Int] { return [Int(bitPattern: self)] } }
extension UInt8: CVarArg { public var _cVarArgEncoding: [Int] { return [Int(self)] } }
extension UInt16: CVarArg { public var _cVarArgEncoding: [Int] { return [Int(self)] } }
extension UInt32: CVarArg { public var _cVarArgEncoding: [Int] { return [Int(self)] } }
extension UInt64: CVarArg { public var _cVarArgEncoding: [Int] { return [Int(bitPattern: UInt(self))] } }
extension Double: _CVarArgPassedAsDouble {
  public var _cVarArgEncoding: [Int] { return [Int(bitPattern: UInt(bitPattern.self))] }
}
extension Float: _CVarArgPassedAsDouble {
  public var _cVarArgEncoding: [Int] { return Double(self)._cVarArgEncoding }
}
extension OpaquePointer: CVarArg { public var _cVarArgEncoding: [Int] { return [Int(Builtin.ptrtoint_Word(_rawValue))] } }
extension UnsafePointer: CVarArg { public var _cVarArgEncoding: [Int] { return [Int(bitPattern: self)] } }
extension UnsafeMutablePointer: CVarArg { public var _cVarArgEncoding: [Int] { return [Int(bitPattern: self)] } }
extension UnsafeRawPointer: CVarArg { public var _cVarArgEncoding: [Int] { return [Int(bitPattern: self)] } }
extension UnsafeMutableRawPointer: CVarArg { public var _cVarArgEncoding: [Int] { return [Int(bitPattern: self)] } }

/// A `va_list`, as C functions taking one receive it.
@frozen public struct CVaListPointer {
  @usableFromInline internal var _value: UnsafeMutableRawPointer
  @inlinable public init(_fromUnsafeMutablePointer from: UnsafeMutableRawPointer) { _value = from }
}

/// Builds an x86-64 System V va_list: a header pointing at a register save
/// area (6 integer registers, then 8 vector registers of 16 bytes) and an
/// overflow area for arguments that did not fit.
final internal class __VaListBuilder {
  internal var _gp: [Int] = []
  internal var _fp: [Int] = []
  internal var _overflow: [Int] = []
  internal var _memory: UnsafeMutableRawPointer? = nil

  internal init() {}

  internal func append(_ arg: CVarArg) {
    let words = arg._cVarArgEncoding
    if arg is _CVarArgPassedAsDouble, words.count == 1, _fp.count < 8 {
      _fp.append(words[0])
    } else if words.count == 1, _gp.count < 6 {
      _gp.append(words[0])
    } else {
      if arg is _CVarArgAligned, words.count > 1, _overflow.count % 2 == 1 { _overflow.append(0) }
      _overflow.append(contentsOf: words)
    }
  }

  internal func va_list() -> CVaListPointer {
    // header (24 bytes, padded to 32) + 22 words of register save area + overflow
    let saveWords = 6 + 8 * 2
    let total = 32 + (saveWords + _overflow.count) * 8
    let mem = UnsafeMutableRawPointer.allocate(byteCount: total, alignment: 16)
    _memory = mem
    let save = mem + 32
    let overflow = save + saveWords * 8
    for i in 0..<saveWords { save.storeBytes(of: 0, toByteOffset: i * 8, as: Int.self) }
    for (i, w) in _gp.enumerated() { save.storeBytes(of: w, toByteOffset: i * 8, as: Int.self) }
    for (i, w) in _fp.enumerated() { save.storeBytes(of: w, toByteOffset: 48 + i * 16, as: Int.self) }
    for (i, w) in _overflow.enumerated() { overflow.storeBytes(of: w, toByteOffset: i * 8, as: Int.self) }
    // The callee reads from these offsets on; the arguments start the areas.
    mem.storeBytes(of: UInt32(0), toByteOffset: 0, as: UInt32.self)  // gp_offset
    mem.storeBytes(of: UInt32(48), toByteOffset: 4, as: UInt32.self) // fp_offset
    mem.storeBytes(of: overflow, toByteOffset: 8, as: UnsafeMutableRawPointer.self)
    mem.storeBytes(of: save, toByteOffset: 16, as: UnsafeMutableRawPointer.self)
    return CVaListPointer(_fromUnsafeMutablePointer: mem)
  }

  deinit { _memory?.deallocate() }
}

/// Calls `body` with a va_list holding `args`, valid only during the call.
public func withVaList<R>(_ args: [CVarArg], _ body: (CVaListPointer) -> R) -> R {
  let builder = __VaListBuilder()
  for a in args { builder.append(a) }
  let result = body(builder.va_list())
  _fixLifetime(builder)
  return result
}

/// A va_list holding `args` that is never freed (prefer withVaList).
public func getVaList(_ args: [CVarArg]) -> CVaListPointer {
  let builder = __VaListBuilder()
  for a in args { builder.append(a) }
  _ = Unmanaged.passRetained(builder)
  return builder.va_list()
}
