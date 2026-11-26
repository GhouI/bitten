// The Swift overlay of os (libswiftos): Logger, OSSignposter and the log
// type constants. Programs inline the log calls themselves (they build the
// argument buffer and call _os_log_impl); what they bind to here are the
// handle types and constants.

@_exported import os

extension os_log_type_t {
  public static let `default` = OS_LOG_TYPE_DEFAULT
  public static let info = OS_LOG_TYPE_INFO
  public static let debug = OS_LOG_TYPE_DEBUG
  public static let error = OS_LOG_TYPE_ERROR
  public static let fault = OS_LOG_TYPE_FAULT
}

extension os_signpost_type_t {
  public static let event = OS_SIGNPOST_EVENT
  public static let begin = OS_SIGNPOST_INTERVAL_BEGIN
  public static let end = OS_SIGNPOST_INTERVAL_END
}

extension OSLog {
  public static let `default`: OSLog = _bitten_os_log_default()
  public static let disabled: OSLog = _bitten_os_log_disabled()
  public var signpostsEnabled: Bool { return os_signpost_enabled(self) }
  public convenience init(subsystem: String, category: String) {
    // OSLog handles come from os_log_create; this initializer exists for
    // source compatibility and is not reached by compiled programs.
    fatalError("OSLog(subsystem:category:) is not supported; use Logger")
  }
}

public struct Logger: @unchecked Sendable {
  public let logObject: OSLog
  public init(subsystem: String, category: String) {
    logObject = subsystem.withCString { s in category.withCString { c in os_log_create(s, c) } }
  }
  public init(_ logObj: OSLog) { logObject = logObj }
  public init() { logObject = OSLog.default }
}

// ---- signposts ------------------------------------------------------------------

public struct OSSignpostID: Comparable, Hashable, Sendable {
  public let rawValue: UInt64
  public init(_ value: UInt64) { rawValue = value }
  public init(log: OSLog) { rawValue = os_signpost_id_generate(log) }
  public static let exclusive = OSSignpostID(0xEEEE_B0B5_B2B2_EEEE)
  public static let invalid = OSSignpostID(~0)
  public static let null = OSSignpostID(0)
  public static func < (a: OSSignpostID, b: OSSignpostID) -> Bool { return a.rawValue < b.rawValue }
}

public enum OSSignpostError: Error, Sendable {
  case doubleEnd
  /// The interval was open: no error (the check returns a value, not an
  /// optional).
  case none
}

public final class OSSignpostIntervalState: Codable, @unchecked Sendable {
  public let signpostID: OSSignpostID
  var isOpen: Bool
  public init(id: OSSignpostID, isOpen: Bool) {
    signpostID = id
    self.isOpen = isOpen
  }
  enum CodingKeys: String, CodingKey { case id, open }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    signpostID = OSSignpostID(try c.decode(UInt64.self, forKey: .id))
    isOpen = try c.decode(Bool.self, forKey: .open)
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(signpostID.rawValue, forKey: .id)
    try c.encode(isOpen, forKey: .open)
  }
}

/// Ends an interval: reports a second end of the same interval.
public func checkForErrorAndConsumeState(state: OSSignpostIntervalState) -> OSSignpostError {
  if !state.isOpen { return .doubleEnd }
  state.isOpen = false
  return .none
}

public struct OSSignposter: @unchecked Sendable {
  public let logHandle: OSLog
  public init(subsystem: String, category: String) {
    logHandle = subsystem.withCString { s in category.withCString { c in os_log_create(s, c) } }
  }
  public init(logger: Logger) { logHandle = logger.logObject }
  public init(logHandle: OSLog) { self.logHandle = logHandle }
  public init() { logHandle = OSLog.disabled }
  public var isEnabled: Bool { return os_signpost_enabled(logHandle) }
  public func makeSignpostID() -> OSSignpostID { return OSSignpostID(log: logHandle) }
}

/// The classic varargs interface. Arguments are not formatted here (the
/// format would need the Objective-C %@ machinery); the format alone is
/// logged.
public func os_log(_ type: os_log_type_t, dso: UnsafeRawPointer = #dsohandle, log: OSLog = OSLog.default,
                   _ message: StaticString, _ args: CVarArg...) {
  guard os_log_type_enabled(log, type) else { return }
  let fmt = UnsafeRawPointer(message.utf8Start).assumingMemoryBound(to: CChar.self)
  var header: (UInt8, UInt8) = (0, 0)
  withUnsafeMutableBytes(of: &header) { h in
    _os_log_impl(UnsafeMutableRawPointer(mutating: dso), log, type, fmt,
                 h.baseAddress!.assumingMemoryBound(to: UInt8.self), 2)
  }
}
