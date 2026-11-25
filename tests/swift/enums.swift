// module: Swift
// Enum metadata laid out by the runtime (swift_initEnumMetadata*), its tags
// and extra inhabitants. Every generic function below has a concrete twin
// whose layout the compiler computes itself; the C driver checks that both
// produce the same bytes. Compiled as the module Swift because the compiler
// looks up Optional by name when it builds enums (see the Makefile).
@frozen public enum Optional<Wrapped> { case none; case some(Wrapped) }
public typealias I8 = Builtin.Int8
public typealias I64 = Builtin.Int64

public enum MP<T, U> { case a(T), b(U), c, d }
public enum E3<T> { case p(T), x, y, z }
public enum One<T> { case only(T) }
public enum Big<T> { case p(T), q(T), c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, c17, c18, c19, c20, c21, c22, c23, c24, c25, c26, c27, c28, c29, c30, c31, c32, c33, c34, c35, c36, c37, c38, c39, c40, c41, c42, c43, c44, c45, c46, c47, c48, c49, c50, c51, c52, c53, c54, c55, c56, c57, c58, c59, c60, c61, c62, c63, c64, c65, c66, c67, c68, c69, c70, c71, c72, c73, c74, c75, c76, c77, c78, c79, c80, c81, c82, c83, c84, c85, c86, c87, c88, c89, c90, c91, c92, c93, c94, c95, c96, c97, c98, c99, c100, c101, c102, c103, c104, c105, c106, c107, c108, c109, c110, c111, c112, c113, c114, c115, c116, c117, c118, c119, c120, c121, c122, c123, c124, c125, c126, c127, c128, c129, c130, c131, c132, c133, c134, c135, c136, c137, c138, c139, c140, c141, c142, c143, c144, c145, c146, c147, c148, c149, c150, c151, c152, c153, c154, c155, c156, c157, c158, c159, c160, c161, c162, c163, c164, c165, c166, c167, c168, c169, c170, c171, c172, c173, c174, c175, c176, c177, c178, c179, c180, c181, c182, c183, c184, c185, c186, c187, c188, c189, c190, c191, c192, c193, c194, c195, c196, c197, c198, c199, c200, c201, c202, c203, c204, c205, c206, c207, c208, c209, c210, c211, c212, c213, c214, c215, c216, c217, c218, c219, c220, c221, c222, c223, c224, c225, c226, c227, c228, c229, c230, c231, c232, c233, c234, c235, c236, c237, c238, c239, c240, c241, c242, c243, c244, c245, c246, c247, c248, c249, c250, c251, c252, c253, c254, c255, c256, c257, c258, c259, c260, c261, c262, c263, c264, c265, c266, c267, c268, c269, c270, c271, c272, c273, c274, c275, c276, c277, c278, c279, c280, c281, c282, c283, c284, c285, c286, c287, c288, c289, c290, c291, c292, c293, c294, c295, c296, c297, c298, c299 }

// Generic: the runtime lays these out and the compiled code asks it for tags.
@inline(never) public func mpB<T, U>(_ t: T.Type, _ u: U) -> MP<T, U> { return .b(u) }
@inline(never) public func mpD<T, U>(_ t: T.Type, _ u: U.Type) -> MP<T, U> { return .d }
@inline(never) public func e3z<T>(_ t: T.Type) -> E3<T> { return .z }
@inline(never) public func e3p<T>(_ t: T) -> E3<T> { return .p(t) }
@inline(never) public func bigLast<T>(_ t: T.Type) -> Big<T> { return .c299 }
@inline(never) public func none<T>(_ t: T.Type) -> Optional<T> { return .none }
@inline(never) public func some<T>(_ t: T) -> Optional<T> { return .some(t) }
@inline(never) public func mpCase<T, U>(_ e: MP<T, U>, _ k0: I64, _ k1: I64, _ k2: I64, _ k3: I64) -> I64 {
  switch e { case .a: return k0; case .b: return k1; case .c: return k2; case .d: return k3 }
}
@inline(never) public func optCase<T>(_ e: Optional<T>, _ k0: I64, _ k1: I64) -> I64 {
  switch e { case .none: return k0; case .some: return k1 }
}

@_cdecl("g_mp_b") public func g_mp_b(_ o: Builtin.RawPointer, _ u: I8) { Builtin.initialize(mpB(I64.self, u), o) }
@_cdecl("g_mp_d") public func g_mp_d(_ o: Builtin.RawPointer) { Builtin.initialize(mpD(I64.self, I8.self), o) }
@_cdecl("g_mp_d8") public func g_mp_d8(_ o: Builtin.RawPointer) { Builtin.initialize(mpD(I8.self, I8.self), o) }
@_cdecl("g_e3z8") public func g_e3z8(_ o: Builtin.RawPointer) { Builtin.initialize(e3z(I8.self), o) }
@_cdecl("g_e3z1") public func g_e3z1(_ o: Builtin.RawPointer) { Builtin.initialize(e3z(Builtin.Int1.self), o) }
@_cdecl("g_e3zp") public func g_e3zp(_ o: Builtin.RawPointer) { Builtin.initialize(e3z(Builtin.RawPointer.self), o) }
@_cdecl("g_e3p8") public func g_e3p8(_ o: Builtin.RawPointer, _ v: I8) { Builtin.initialize(e3p(v), o) }
@_cdecl("g_big") public func g_big(_ o: Builtin.RawPointer) { Builtin.initialize(bigLast(I8.self), o) }
@_cdecl("g_opt_mp_none") public func g_opt_mp_none(_ o: Builtin.RawPointer) {
  Builtin.initialize(none(MP<I64, I8>.self), o)
}
@_cdecl("g_opt_opt1_none") public func g_opt_opt1_none(_ o: Builtin.RawPointer) {
  Builtin.initialize(none(Optional<Builtin.Int1>.self), o)
}
@_cdecl("g_opt_opt1_some_none") public func g_opt_opt1_some_none(_ o: Builtin.RawPointer) {
  Builtin.initialize(some(none(Builtin.Int1.self)), o)
}
@_cdecl("g_mp_case") public func g_mp_case(_ p: Builtin.RawPointer, _ k0: I64, _ k1: I64, _ k2: I64,
                                           _ k3: I64) -> I64 {
  let e: MP<I64, I8> = Builtin.load(p)
  return mpCase(e, k0, k1, k2, k3)
}
@_cdecl("g_opt_case") public func g_opt_case(_ p: Builtin.RawPointer, _ k0: I64, _ k1: I64) -> I64 {
  let e: Optional<MP<I64, I8>> = Builtin.load(p)
  return optCase(e, k0, k1)
}

// Concrete twins: layouts computed by the compiler.
@_cdecl("c_mp_b") public func c_mp_b(_ o: Builtin.RawPointer, _ u: I8) { Builtin.initialize(MP<I64, I8>.b(u), o) }
@_cdecl("c_mp_d") public func c_mp_d(_ o: Builtin.RawPointer) { Builtin.initialize(MP<I64, I8>.d, o) }
@_cdecl("c_mp_d8") public func c_mp_d8(_ o: Builtin.RawPointer) { Builtin.initialize(MP<I8, I8>.d, o) }
@_cdecl("c_e3z8") public func c_e3z8(_ o: Builtin.RawPointer) { Builtin.initialize(E3<I8>.z, o) }
@_cdecl("c_e3z1") public func c_e3z1(_ o: Builtin.RawPointer) { Builtin.initialize(E3<Builtin.Int1>.z, o) }
@_cdecl("c_e3zp") public func c_e3zp(_ o: Builtin.RawPointer) { Builtin.initialize(E3<Builtin.RawPointer>.z, o) }
@_cdecl("c_big") public func c_big(_ o: Builtin.RawPointer) { Builtin.initialize(Big<I8>.c299, o) }
@_cdecl("c_opt_mp_none") public func c_opt_mp_none(_ o: Builtin.RawPointer) {
  Builtin.initialize(Optional<MP<I64, I8>>.none, o)
}
@_cdecl("c_opt_opt1_none") public func c_opt_opt1_none(_ o: Builtin.RawPointer) {
  Builtin.initialize(Optional<Optional<Builtin.Int1>>.none, o)
}
@_cdecl("c_opt_opt1_some_none") public func c_opt_opt1_some_none(_ o: Builtin.RawPointer) {
  Builtin.initialize(Optional<Optional<Builtin.Int1>>.some(.none), o)
}
