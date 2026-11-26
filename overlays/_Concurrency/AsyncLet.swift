// The entry points the compiler calls for `async let` (it looks them up by
// name in this module, as the toolchain's own _Concurrency declares them).
// The runtime functions behind them are in src/frameworks/concurrency/group.c;
// `swift_asyncLet_begin` is called by the compiler directly.
import Swift

@_silgen_name("swift_asyncLet_start")
public func _asyncLetStart<T>(asyncLet: Builtin.RawPointer, options: Builtin.RawPointer?,
                              operation: @Sendable () async throws -> T)

@_silgen_name("swift_asyncLet_get")
public func _asyncLet_get(_ asyncLet: Builtin.RawPointer, _ resultBuffer: Builtin.RawPointer) async

@_silgen_name("swift_asyncLet_get_throwing")
public func _asyncLet_get_throwing(_ asyncLet: Builtin.RawPointer, _ resultBuffer: Builtin.RawPointer) async throws

@_silgen_name("swift_asyncLet_finish")
public func _asyncLet_finish(_ asyncLet: Builtin.RawPointer, _ resultBuffer: Builtin.RawPointer) async
