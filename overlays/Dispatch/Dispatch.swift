// The Swift overlay of Dispatch (libswiftDispatch): DispatchQueue and the
// other dispatch objects as Swift sees them (sdk/include/dispatch/swift.h),
// with the value types around them (DispatchTime, DispatchQoS...). The work
// is done by bitten's libdispatch (src/frameworks/dispatch), called here by
// symbol; the Objective-C classes those objects belong to are the ones
// Swift code binds to (src/frameworks/dispatch/swift_classes.c).

@_exported import Dispatch
import Darwin

// ---- the C interface (src/frameworks/dispatch) ------------------------------

typealias _DispatchBlock = @convention(block) () -> Void
typealias _Object = UnsafeMutableRawPointer

@_silgen_name("dispatch_get_global_queue") func _dispatch_get_global_queue(_ identifier: Int, _ flags: UInt) -> _Object
@_silgen_name("dispatch_get_main_queue") func _dispatch_get_main_queue() -> _Object
@_silgen_name("dispatch_queue_attr_make_initially_inactive") func _dispatch_queue_attr_make_initially_inactive(_ attr: _Object?) -> _Object?
@_silgen_name("dispatch_queue_attr_make_with_qos_class") func _dispatch_queue_attr_make_with_qos_class(_ attr: _Object?, _ qos: UInt32, _ relpri: Int32) -> _Object?
@_silgen_name("dispatch_queue_attr_make_with_autorelease_frequency") func _dispatch_queue_attr_make_with_autorelease_frequency(_ attr: _Object?, _ frequency: UInt) -> _Object?
@_silgen_name("dispatch_queue_get_label") func _dispatch_queue_get_label(_ queue: _Object?) -> UnsafePointer<CChar>?
@_silgen_name("dispatch_async") func _dispatch_async(_ queue: _Object, _ block: @escaping _DispatchBlock)
@_silgen_name("dispatch_sync") func _dispatch_sync(_ queue: _Object, _ block: _DispatchBlock)
@_silgen_name("dispatch_barrier_async") func _dispatch_barrier_async(_ queue: _Object, _ block: @escaping _DispatchBlock)
@_silgen_name("dispatch_barrier_sync") func _dispatch_barrier_sync(_ queue: _Object, _ block: _DispatchBlock)
@_silgen_name("dispatch_after") func _dispatch_after(_ when: UInt64, _ queue: _Object, _ block: @escaping _DispatchBlock)
@_silgen_name("dispatch_apply") func _dispatch_apply(_ iterations: Int, _ queue: _Object?, _ block: @convention(block) (Int) -> Void)
@_silgen_name("dispatch_queue_set_specific") func _dispatch_queue_set_specific(_ queue: _Object, _ key: UnsafeRawPointer, _ context: UnsafeMutableRawPointer?, _ destructor: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?)
@_silgen_name("dispatch_get_specific") func _dispatch_get_specific(_ key: UnsafeRawPointer) -> UnsafeMutableRawPointer?
@_silgen_name("dispatch_assert_queue") func _dispatch_assert_queue(_ queue: _Object)
@_silgen_name("dispatch_assert_queue_not") func _dispatch_assert_queue_not(_ queue: _Object)
@_silgen_name("dispatch_activate") func _dispatch_activate(_ object: _Object)
@_silgen_name("dispatch_resume") func _dispatch_resume(_ object: _Object)
@_silgen_name("dispatch_suspend") func _dispatch_suspend(_ object: _Object)
@_silgen_name("dispatch_group_async") func _dispatch_group_async(_ group: _Object, _ queue: _Object, _ block: @escaping _DispatchBlock)
@_silgen_name("dispatch_group_notify") func _dispatch_group_notify(_ group: _Object, _ queue: _Object, _ block: @escaping _DispatchBlock)
@_silgen_name("dispatch_group_wait") func _dispatch_group_wait(_ group: _Object, _ timeout: UInt64) -> Int
@_silgen_name("dispatch_semaphore_signal") func _dispatch_semaphore_signal(_ sema: _Object) -> Int
@_silgen_name("dispatch_semaphore_wait") func _dispatch_semaphore_wait(_ sema: _Object, _ timeout: UInt64) -> Int
@_silgen_name("dispatch_source_create") func _dispatch_source_create(_ type: UnsafeRawPointer, _ handle: UInt, _ mask: UInt, _ queue: _Object?) -> _Object?
@_silgen_name("dispatch_source_set_event_handler") func _dispatch_source_set_event_handler(_ source: _Object, _ handler: _DispatchBlock?)
@_silgen_name("dispatch_source_set_cancel_handler") func _dispatch_source_set_cancel_handler(_ source: _Object, _ handler: _DispatchBlock?)
@_silgen_name("dispatch_source_set_registration_handler") func _dispatch_source_set_registration_handler(_ source: _Object, _ handler: _DispatchBlock?)
@_silgen_name("dispatch_source_cancel") func _dispatch_source_cancel(_ source: _Object)
@_silgen_name("dispatch_source_testcancel") func _dispatch_source_testcancel(_ source: _Object) -> Int
@_silgen_name("dispatch_source_get_data") func _dispatch_source_get_data(_ source: _Object) -> UInt
@_silgen_name("dispatch_source_get_mask") func _dispatch_source_get_mask(_ source: _Object) -> UInt
@_silgen_name("dispatch_source_get_handle") func _dispatch_source_get_handle(_ source: _Object) -> UInt
@_silgen_name("dispatch_source_merge_data") func _dispatch_source_merge_data(_ source: _Object, _ value: UInt)
@_silgen_name("dispatch_source_set_timer") func _dispatch_source_set_timer(_ source: _Object, _ start: UInt64, _ interval: UInt64, _ leeway: UInt64)
@_silgen_name("dispatch_time") func _dispatch_time(_ when: UInt64, _ delta: Int64) -> UInt64
@_silgen_name("dispatch_walltime") func _dispatch_walltime(_ when: UnsafePointer<timespec>?, _ delta: Int64) -> UInt64

/// The address of a libdispatch data symbol (a source type, the
/// concurrent-queue attribute), which has no C declaration Swift can see.
func _dispatchSymbol(_ name: String) -> UnsafeMutableRawPointer {
  guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else {
    fatalError("Dispatch: \(name) is missing")
  }
  return p
}

func _object(_ o: AnyObject) -> _Object { return Unmanaged.passUnretained(o).toOpaque() }

let _DISPATCH_TIME_FOREVER: UInt64 = ~0

/// A dispatch time: nanoseconds of uptime, or negated wall-clock time.
public typealias dispatch_time_t = UInt64

// ---- quality of service -----------------------------------------------------

public struct DispatchQoS: Equatable {
  public let qosClass: QoSClass
  public let relativePriority: Int

  public static let background = DispatchQoS(qosClass: .background, relativePriority: 0)
  public static let utility = DispatchQoS(qosClass: .utility, relativePriority: 0)
  public static let `default` = DispatchQoS(qosClass: .default, relativePriority: 0)
  public static let userInitiated = DispatchQoS(qosClass: .userInitiated, relativePriority: 0)
  public static let userInteractive = DispatchQoS(qosClass: .userInteractive, relativePriority: 0)
  public static let unspecified = DispatchQoS(qosClass: .unspecified, relativePriority: 0)

  public enum QoSClass {
    case background, utility, `default`, userInitiated, userInteractive, unspecified

    public init?(rawValue: qos_class_t) {
      switch rawValue {
      case QOS_CLASS_BACKGROUND: self = .background
      case QOS_CLASS_UTILITY: self = .utility
      case QOS_CLASS_DEFAULT: self = .default
      case QOS_CLASS_USER_INITIATED: self = .userInitiated
      case QOS_CLASS_USER_INTERACTIVE: self = .userInteractive
      case QOS_CLASS_UNSPECIFIED: self = .unspecified
      default: return nil
      }
    }

    public var rawValue: qos_class_t {
      switch self {
      case .background: return QOS_CLASS_BACKGROUND
      case .utility: return QOS_CLASS_UTILITY
      case .default: return QOS_CLASS_DEFAULT
      case .userInitiated: return QOS_CLASS_USER_INITIATED
      case .userInteractive: return QOS_CLASS_USER_INTERACTIVE
      case .unspecified: return QOS_CLASS_UNSPECIFIED
      }
    }

    /// The dispatch_get_global_queue identifier.
    var _globalIdentifier: Int {
      switch self {
      case .background: return 0x09
      case .utility: return 0x11
      case .default, .unspecified: return 0x15
      case .userInitiated: return 0x19
      case .userInteractive: return 0x21
      }
    }
  }

  public init(qosClass: QoSClass, relativePriority: Int) {
    self.qosClass = qosClass
    self.relativePriority = relativePriority
  }
}

public struct DispatchWorkItemFlags: OptionSet {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }

  public static let barrier = DispatchWorkItemFlags(rawValue: 0x1)
  public static let detached = DispatchWorkItemFlags(rawValue: 0x2)
  public static let assignCurrentContext = DispatchWorkItemFlags(rawValue: 0x4)
  public static let noQoS = DispatchWorkItemFlags(rawValue: 0x8)
  public static let inheritQoS = DispatchWorkItemFlags(rawValue: 0x10)
  public static let enforceQoS = DispatchWorkItemFlags(rawValue: 0x20)
}

// ---- time --------------------------------------------------------------------

public struct DispatchTime: Comparable {
  public let rawValue: dispatch_time_t

  public static func now() -> DispatchTime { return DispatchTime(rawValue: _dispatch_time(0, 0)) }
  public static let distantFuture = DispatchTime(rawValue: _DISPATCH_TIME_FOREVER)

  init(rawValue: dispatch_time_t) { self.rawValue = rawValue }

  /// Mach absolute time is in nanoseconds here (mach_timebase_info is 1/1).
  public init(uptimeNanoseconds: UInt64) {
    rawValue = uptimeNanoseconds == 0 ? 1 : min(uptimeNanoseconds, UInt64(Int64.max))
  }

  public var uptimeNanoseconds: UInt64 { return rawValue }

  public static func < (a: DispatchTime, b: DispatchTime) -> Bool { return a.rawValue < b.rawValue }
  public static func == (a: DispatchTime, b: DispatchTime) -> Bool { return a.rawValue == b.rawValue }
}

public struct DispatchWallTime: Comparable {
  public let rawValue: dispatch_time_t

  public static func now() -> DispatchWallTime { return DispatchWallTime(rawValue: _dispatch_walltime(nil, 0)) }
  public static let distantFuture = DispatchWallTime(rawValue: _DISPATCH_TIME_FOREVER)

  init(rawValue: dispatch_time_t) { self.rawValue = rawValue }

  public init(timespec: timespec) {
    var t = timespec
    rawValue = _dispatch_walltime(&t, 0)
  }

  /// Wall-clock times are stored negated (as in libdispatch), so a later
  /// time has a smaller raw value; forever is the largest.
  public static func < (a: DispatchWallTime, b: DispatchWallTime) -> Bool {
    if b.rawValue == _DISPATCH_TIME_FOREVER { return a.rawValue != _DISPATCH_TIME_FOREVER }
    if a.rawValue == _DISPATCH_TIME_FOREVER { return false }
    return -Int64(bitPattern: a.rawValue) < -Int64(bitPattern: b.rawValue)
  }

  public static func == (a: DispatchWallTime, b: DispatchWallTime) -> Bool { return a.rawValue == b.rawValue }
}

public enum DispatchTimeInterval: Equatable {
  case seconds(Int)
  case milliseconds(Int)
  case microseconds(Int)
  case nanoseconds(Int)
  case never

  var _nanoseconds: Int64 {
    switch self {
    case .seconds(let s): return Int64(s).multipliedReportingOverflow(by: 1_000_000_000).overflow ? Int64.max : Int64(s) * 1_000_000_000
    case .milliseconds(let ms): return Int64(ms).multipliedReportingOverflow(by: 1_000_000).overflow ? Int64.max : Int64(ms) * 1_000_000
    case .microseconds(let us): return Int64(us).multipliedReportingOverflow(by: 1_000).overflow ? Int64.max : Int64(us) * 1_000
    case .nanoseconds(let ns): return Int64(ns)
    case .never: return Int64.max
    }
  }

  public static func == (lhs: DispatchTimeInterval, rhs: DispatchTimeInterval) -> Bool {
    switch (lhs, rhs) {
    case (.never, .never): return true
    case (.never, _), (_, .never): return false
    default: return lhs._nanoseconds == rhs._nanoseconds
    }
  }
}

func _seconds(_ s: Double) -> Int64 {
  let ns = s * 1_000_000_000
  if ns >= Double(Int64.max) { return Int64.max }
  if ns <= Double(Int64.min) { return Int64.min }
  return Int64(ns)
}

public func + (time: DispatchTime, interval: DispatchTimeInterval) -> DispatchTime {
  if case .never = interval { return .distantFuture }
  return DispatchTime(rawValue: _dispatch_time(time.rawValue, interval._nanoseconds))
}

public func - (time: DispatchTime, interval: DispatchTimeInterval) -> DispatchTime {
  if case .never = interval { return DispatchTime(rawValue: 0) }
  return DispatchTime(rawValue: _dispatch_time(time.rawValue, -interval._nanoseconds))
}

public func + (time: DispatchTime, seconds: Double) -> DispatchTime {
  return DispatchTime(rawValue: _dispatch_time(time.rawValue, _seconds(seconds)))
}

public func - (time: DispatchTime, seconds: Double) -> DispatchTime {
  return DispatchTime(rawValue: _dispatch_time(time.rawValue, -_seconds(seconds)))
}

public func + (time: DispatchWallTime, interval: DispatchTimeInterval) -> DispatchWallTime {
  if case .never = interval { return .distantFuture }
  return DispatchWallTime(rawValue: _dispatch_time(time.rawValue, interval._nanoseconds))
}

public func - (time: DispatchWallTime, interval: DispatchTimeInterval) -> DispatchWallTime {
  return DispatchWallTime(rawValue: _dispatch_time(time.rawValue, -interval._nanoseconds))
}

public func + (time: DispatchWallTime, seconds: Double) -> DispatchWallTime {
  return DispatchWallTime(rawValue: _dispatch_time(time.rawValue, _seconds(seconds)))
}

public func - (time: DispatchWallTime, seconds: Double) -> DispatchWallTime {
  return DispatchWallTime(rawValue: _dispatch_time(time.rawValue, -_seconds(seconds)))
}

public enum DispatchTimeoutResult {
  case success
  case timedOut
}

// ---- queues --------------------------------------------------------------------

public final class DispatchSpecificKey<T> {
  public init() {}
}

final class _DispatchSpecificValue<T> {
  let value: T
  init(_ value: T) { self.value = value }
}

extension DispatchQueue {
  public struct Attributes: OptionSet {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static let concurrent = Attributes(rawValue: 1 << 1)
    public static let initiallyInactive = Attributes(rawValue: 1 << 2)
  }

  public enum AutoreleaseFrequency {
    case inherit
    case workItem
    case never
  }

  public class func global(qos: DispatchQoS.QoSClass = .default) -> DispatchQueue {
    let q = _dispatch_get_global_queue(qos._globalIdentifier, 0)
    return Unmanaged<DispatchQueue>.fromOpaque(q).takeUnretainedValue()
  }

  public class var main: DispatchQueue {
    return Unmanaged<DispatchQueue>.fromOpaque(_dispatch_get_main_queue()).takeUnretainedValue()
  }

  public convenience init(label: String, qos: DispatchQoS = .unspecified, attributes: Attributes = [],
                          autoreleaseFrequency: AutoreleaseFrequency = .inherit, target: DispatchQueue? = nil) {
    var attr: _Object? = nil
    if attributes.contains(.concurrent) { attr = _dispatchSymbol("_dispatch_queue_attr_concurrent") }
    if attributes.contains(.initiallyInactive) { attr = _dispatch_queue_attr_make_initially_inactive(attr) }
    switch autoreleaseFrequency {
    case .inherit: break
    case .workItem: attr = _dispatch_queue_attr_make_with_autorelease_frequency(attr, 1)
    case .never: attr = _dispatch_queue_attr_make_with_autorelease_frequency(attr, 2)
    }
    if qos != .unspecified {
      attr = _dispatch_queue_attr_make_with_qos_class(attr, qos.qosClass.rawValue.rawValue, Int32(qos.relativePriority))
    }
    let attrObject = attr.map { Unmanaged<__OS_dispatch_queue_attr>.fromOpaque($0).takeUnretainedValue() }
    self.init(__label: label, attr: attrObject, queue: target)
  }

  public var label: String {
    guard let p = _dispatch_queue_get_label(_object(self)) else { return "" }
    return String(cString: p)
  }

  public func async(group: DispatchGroup? = nil, qos: DispatchQoS = .unspecified,
                    flags: DispatchWorkItemFlags = [], execute work: @escaping @convention(block) () -> Void) {
    if let group = group {
      _dispatch_group_async(_object(group), _object(self), work)
    } else if flags.contains(.barrier) {
      _dispatch_barrier_async(_object(self), work)
    } else {
      _dispatch_async(_object(self), work)
    }
  }

  public func asyncAfter(deadline: DispatchTime, qos: DispatchQoS = .unspecified,
                         flags: DispatchWorkItemFlags = [], execute work: @escaping @convention(block) () -> Void) {
    _dispatch_after(deadline.rawValue, _object(self), work)
  }

  public func asyncAfter(wallDeadline: DispatchWallTime, qos: DispatchQoS = .unspecified,
                         flags: DispatchWorkItemFlags = [], execute work: @escaping @convention(block) () -> Void) {
    _dispatch_after(wallDeadline.rawValue, _object(self), work)
  }

  /// dispatch_sync's block parameter is not escaping, so a non-escaping
  /// closure goes straight through.
  func _syncBlock(barrier: Bool, _ work: () -> Void) {
    if barrier { _dispatch_barrier_sync(_object(self), work) } else { _dispatch_sync(_object(self), work) }
  }

  private func _syncHelper<T>(barrier: Bool, execute work: () throws -> T,
                              rescue: (Error) throws -> T) rethrows -> T {
    var result: T?
    var error: Error?
    _syncBlock(barrier: barrier) {
      do { result = try work() } catch let e { error = e }
    }
    if let e = error { return try rescue(e) }
    return result!
  }

  public func sync(execute block: () -> Void) {
    _syncBlock(barrier: false, block)
  }

  public func sync<T>(execute work: () throws -> T) rethrows -> T {
    return try _syncHelper(barrier: false, execute: work, rescue: { throw $0 })
  }

  public func sync<T>(flags: DispatchWorkItemFlags, execute work: () throws -> T) rethrows -> T {
    return try _syncHelper(barrier: flags.contains(.barrier), execute: work, rescue: { throw $0 })
  }

  public class func concurrentPerform(iterations: Int, execute work: (Int) -> Void) {
    _dispatch_apply(iterations, nil, { work($0) })
  }

  public class func getSpecific<T>(key: DispatchSpecificKey<T>) -> T? {
    guard let p = _dispatch_get_specific(UnsafeRawPointer(_object(key))) else { return nil }
    return Unmanaged<_DispatchSpecificValue<T>>.fromOpaque(p).takeUnretainedValue().value
  }

  public func setSpecific<T>(key: DispatchSpecificKey<T>, value: T?) {
    let ctx = value.map { Unmanaged.passRetained(_DispatchSpecificValue($0)).toOpaque() }
    _dispatch_queue_set_specific(_object(self), UnsafeRawPointer(_object(key)), ctx, { p in
      if let p = p { Unmanaged<AnyObject>.fromOpaque(p).release() }
    })
  }

  public func activate() { _dispatch_activate(_object(self)) }
  public func suspend() { _dispatch_suspend(_object(self)) }
  public func resume() { _dispatch_resume(_object(self)) }
}

// ---- groups and semaphores --------------------------------------------------

extension DispatchGroup {
  public func notify(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                     queue: DispatchQueue, execute work: @escaping @convention(block) () -> Void) {
    _dispatch_group_notify(_object(self), _object(queue), work)
  }

  public func wait() {
    _ = _dispatch_group_wait(_object(self), _DISPATCH_TIME_FOREVER)
  }

  public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
    return _dispatch_group_wait(_object(self), timeout.rawValue) == 0 ? .success : .timedOut
  }

  public func wait(wallTimeout timeout: DispatchWallTime) -> DispatchTimeoutResult {
    return _dispatch_group_wait(_object(self), timeout.rawValue) == 0 ? .success : .timedOut
  }
}

extension DispatchSemaphore {
  @discardableResult
  public func signal() -> Int {
    return _dispatch_semaphore_signal(_object(self))
  }

  public func wait() {
    _ = _dispatch_semaphore_wait(_object(self), _DISPATCH_TIME_FOREVER)
  }

  public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
    return _dispatch_semaphore_wait(_object(self), timeout.rawValue) == 0 ? .success : .timedOut
  }

  public func wait(wallTimeout: DispatchWallTime) -> DispatchTimeoutResult {
    return _dispatch_semaphore_wait(_object(self), wallTimeout.rawValue) == 0 ? .success : .timedOut
  }
}

// ---- sources -------------------------------------------------------------------

public typealias DispatchSourceHandler = @convention(block) () -> Void

extension DispatchSource {
  public struct TimerFlags: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let strict = TimerFlags(rawValue: 1)
  }

  public struct FileSystemEvent: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let delete = FileSystemEvent(rawValue: 0x1)
    public static let write = FileSystemEvent(rawValue: 0x2)
    public static let extend = FileSystemEvent(rawValue: 0x4)
    public static let attrib = FileSystemEvent(rawValue: 0x8)
    public static let link = FileSystemEvent(rawValue: 0x10)
    public static let rename = FileSystemEvent(rawValue: 0x20)
    public static let revoke = FileSystemEvent(rawValue: 0x40)
    public static let funlock = FileSystemEvent(rawValue: 0x100)
    public static let all: FileSystemEvent = [.delete, .write, .extend, .attrib, .link, .rename, .revoke]
  }

  static func _make(_ type: String, handle: UInt, mask: UInt, queue: DispatchQueue?) -> AnyObject {
    guard let s = _dispatch_source_create(_dispatchSymbol(type), handle, mask, queue.map(_object)) else {
      fatalError("Dispatch: dispatch_source_create failed")
    }
    return Unmanaged<DispatchSource>.fromOpaque(s).takeRetainedValue()
  }

  public class func makeTimerSource(flags: TimerFlags = [], queue: DispatchQueue? = nil) -> DispatchSourceTimer {
    return unsafeBitCast(_make("_dispatch_source_type_timer", handle: 0, mask: flags.rawValue, queue: queue),
                         to: DispatchSourceTimer.self)
  }

  public class func makeReadSource(fileDescriptor: Int32, queue: DispatchQueue? = nil) -> DispatchSourceRead {
    return unsafeBitCast(_make("_dispatch_source_type_read", handle: UInt(fileDescriptor), mask: 0, queue: queue),
                         to: DispatchSourceRead.self)
  }

  public class func makeWriteSource(fileDescriptor: Int32, queue: DispatchQueue? = nil) -> DispatchSourceWrite {
    return unsafeBitCast(_make("_dispatch_source_type_write", handle: UInt(fileDescriptor), mask: 0, queue: queue),
                         to: DispatchSourceWrite.self)
  }

  public class func makeFileSystemObjectSource(fileDescriptor: Int32, eventMask: FileSystemEvent,
                                               queue: DispatchQueue? = nil) -> DispatchSourceFileSystemObject {
    return unsafeBitCast(_make("_dispatch_source_type_vnode", handle: UInt(fileDescriptor),
                               mask: eventMask.rawValue, queue: queue),
                         to: DispatchSourceFileSystemObject.self)
  }

  public class func makeSignalSource(signal: Int32, queue: DispatchQueue? = nil) -> DispatchSourceSignal {
    return unsafeBitCast(_make("_dispatch_source_type_signal", handle: UInt(signal), mask: 0, queue: queue),
                         to: DispatchSourceSignal.self)
  }

  public class func makeUserDataAddSource(queue: DispatchQueue? = nil) -> DispatchSourceUserDataAdd {
    return unsafeBitCast(_make("_dispatch_source_type_data_add", handle: 0, mask: 0, queue: queue),
                         to: DispatchSourceUserDataAdd.self)
  }

  public class func makeUserDataOrSource(queue: DispatchQueue? = nil) -> DispatchSourceUserDataOr {
    return unsafeBitCast(_make("_dispatch_source_type_data_or", handle: 0, mask: 0, queue: queue),
                         to: DispatchSourceUserDataOr.self)
  }
}

extension DispatchSourceProtocol {
  var _source: _Object { return _object(self) }

  public func setEventHandler(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                              handler: DispatchSourceHandler?) {
    _dispatch_source_set_event_handler(_source, handler)
  }

  public func setCancelHandler(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                               handler: DispatchSourceHandler?) {
    _dispatch_source_set_cancel_handler(_source, handler)
  }

  public func setRegistrationHandler(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [],
                                     handler: DispatchSourceHandler?) {
    _dispatch_source_set_registration_handler(_source, handler)
  }

  public func activate() { _dispatch_activate(_source) }
  public func cancel() { _dispatch_source_cancel(_source) }
  public func resume() { _dispatch_resume(_source) }
  public func suspend() { _dispatch_suspend(_source) }

  public var data: UInt { return _dispatch_source_get_data(_source) }
  public var mask: UInt { return _dispatch_source_get_mask(_source) }
  public var handle: UInt { return _dispatch_source_get_handle(_source) }
  public var isCancelled: Bool { return _dispatch_source_testcancel(_source) != 0 }
}

extension DispatchSourceTimer {
  public func schedule(deadline: DispatchTime, repeating interval: DispatchTimeInterval = .never,
                       leeway: DispatchTimeInterval = .nanoseconds(0)) {
    let every: UInt64 = interval == .never ? _DISPATCH_TIME_FOREVER : UInt64(max(interval._nanoseconds, 0))
    _dispatch_source_set_timer(_source, deadline.rawValue, every, UInt64(max(leeway._nanoseconds, 0)))
  }

  public func schedule(deadline: DispatchTime, repeating interval: Double,
                       leeway: DispatchTimeInterval = .nanoseconds(0)) {
    let every: UInt64 = interval.isInfinite ? _DISPATCH_TIME_FOREVER : UInt64(max(_seconds(interval), 0))
    _dispatch_source_set_timer(_source, deadline.rawValue, every, UInt64(max(leeway._nanoseconds, 0)))
  }

  public func schedule(wallDeadline: DispatchWallTime, repeating interval: DispatchTimeInterval = .never,
                       leeway: DispatchTimeInterval = .nanoseconds(0)) {
    let every: UInt64 = interval == .never ? _DISPATCH_TIME_FOREVER : UInt64(max(interval._nanoseconds, 0))
    _dispatch_source_set_timer(_source, wallDeadline.rawValue, every, UInt64(max(leeway._nanoseconds, 0)))
  }
}

extension DispatchSourceFileSystemObject {
  public var data: DispatchSource.FileSystemEvent {
    return DispatchSource.FileSystemEvent(rawValue: _dispatch_source_get_data(_source))
  }
}

extension DispatchSourceUserDataAdd {
  public func add(data: UInt) { _dispatch_source_merge_data(_source, data) }
}

extension DispatchSourceUserDataOr {
  public func or(data: UInt) { _dispatch_source_merge_data(_source, data) }
}

// ---- preconditions -----------------------------------------------------------

public enum DispatchPredicate {
  case onQueue(DispatchQueue)
  case onQueueAsBarrier(DispatchQueue)
  case notOnQueue(DispatchQueue)
}

/// dispatch_assert_queue and its sibling stop the program when the
/// condition does not hold, so a test that returns holds.
public func _dispatchPreconditionTest(_ condition: DispatchPredicate) -> Bool {
  switch condition {
  case .onQueue(let q), .onQueueAsBarrier(let q): _dispatch_assert_queue(_object(q))
  case .notOnQueue(let q): _dispatch_assert_queue_not(_object(q))
  }
  return true
}

@_transparent
public func dispatchPrecondition(condition: @autoclosure () -> DispatchPredicate) {
  precondition(_dispatchPreconditionTest(condition()), "dispatchPrecondition failure")
}

// ---- data ------------------------------------------------------------------------

/// A byte buffer. Here it holds its bytes directly rather than wrapping a
/// dispatch_data_t.
public struct DispatchData: RandomAccessCollection {
  public typealias Index = Int
  public typealias Indices = Range<Int>
  var _bytes: [UInt8]

  public static let empty = DispatchData(_bytes: [])

  init(_bytes: [UInt8]) { self._bytes = _bytes }

  public init(bytes buffer: UnsafeRawBufferPointer) { _bytes = Array(buffer) }
  public init(bytes buffer: UnsafeBufferPointer<UInt8>) { _bytes = Array(buffer) }

  public var count: Int { return _bytes.count }
  public var startIndex: Int { return 0 }
  public var endIndex: Int { return _bytes.count }
  public subscript(index: Int) -> UInt8 { return _bytes[index] }

  public mutating func append(_ bytes: UnsafeRawBufferPointer) { _bytes.append(contentsOf: bytes) }
  public mutating func append(_ other: DispatchData) { _bytes.append(contentsOf: other._bytes) }

  public func copyBytes(to pointer: UnsafeMutablePointer<UInt8>, count: Int) {
    let n = Swift.min(count, _bytes.count)
    if n == 0 { return }
    _bytes.withUnsafeBytes { UnsafeMutableRawPointer(pointer).copyMemory(from: $0.baseAddress!, byteCount: n) }
  }

  public func copyBytes(to pointer: UnsafeMutableRawBufferPointer, count: Int) {
    let n = Swift.min(Swift.min(count, pointer.count), _bytes.count)
    if n == 0 { return }
    _bytes.withUnsafeBytes { pointer.baseAddress!.copyMemory(from: $0.baseAddress!, byteCount: n) }
  }

  public func withUnsafeBytes<Result, ContentType>(body: (UnsafePointer<ContentType>) throws -> Result) rethrows -> Result {
    return try _bytes.withUnsafeBytes { try body($0.baseAddress!.assumingMemoryBound(to: ContentType.self)) }
  }
}
