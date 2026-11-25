// The C type names. The compiler maps imported C types to Swift through
// these aliases (BuiltinMappedTypes.def), both when importing headers and
// when it needs a C signature for @_cdecl functions or calls into C.

public typealias CChar = Int8
public typealias CSignedChar = Int8
public typealias CUnsignedChar = UInt8
public typealias CShort = Int16
public typealias CUnsignedShort = UInt16
public typealias CInt = Int32
public typealias CUnsignedInt = UInt32
public typealias CLong = Int
public typealias CUnsignedLong = UInt
public typealias CLongLong = Int64
public typealias CUnsignedLongLong = UInt64
public typealias CWideChar = Unicode.Scalar
public typealias CChar8 = UInt8
public typealias CChar16 = UInt16
public typealias CChar32 = Unicode.Scalar
public typealias CBool = Bool
public typealias CFloat = Float
public typealias CDouble = Double
public typealias CLongDouble = Float80
