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
