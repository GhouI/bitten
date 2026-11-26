// Network.framework, written for bitten: the value types (endpoints,
// addresses, interfaces, errors, paths) and the protocol and parameter
// classes. Connections and listeners (Connection.swift) run over BSD
// sockets. There is no TLS: a connection that asks for it fails with
// NWError.tls.
import Foundation
import Dispatch
import Darwin
import Security

// ---- interfaces -----------------------------------------------------------------

public struct NWInterface: Hashable, CustomDebugStringConvertible {
  public enum InterfaceType: Hashable {
    case other
    case wifi
    case cellular
    case wiredEthernet
    case loopback
  }

  public let name: String
  public let type: InterfaceType
  public let index: Int

  init(name: String, type: InterfaceType, index: Int) {
    self.name = name
    self.type = type
    self.index = index
  }

  public var debugDescription: String { return name }
}

// ---- addresses --------------------------------------------------------------------

public protocol IPAddress {
  init?(_ rawValue: Data, _ interface: NWInterface?)
  var rawValue: Data { get }
  var interface: NWInterface? { get }
  var isLoopback: Bool { get }
  var isLinkLocal: Bool { get }
  var isMulticast: Bool { get }
}

func _inetPton(_ family: Int32, _ string: String, _ size: Int) -> [UInt8]? {
  var out = [UInt8](repeating: 0, count: size)
  let rc = string.withCString { s in out.withUnsafeMutableBytes { inet_pton(family, s, $0.baseAddress!) } }
  return rc == 1 ? out : nil
}

func _inetNtop(_ family: Int32, _ bytes: [UInt8]) -> String {
  var buf = [CChar](repeating: 0, count: 64)
  _ = bytes.withUnsafeBytes { b in buf.withUnsafeMutableBufferPointer { inet_ntop(family, b.baseAddress!, $0.baseAddress!, 64) } }
  return String(cString: buf)
}

public struct IPv4Address: IPAddress, Hashable, CustomDebugStringConvertible {
  let bytes: [UInt8]
  public let interface: NWInterface?

  public static let any = IPv4Address(bytes: [0, 0, 0, 0])
  public static let broadcast = IPv4Address(bytes: [255, 255, 255, 255])
  public static let loopback = IPv4Address(bytes: [127, 0, 0, 1])
  public static let allHostsGroup = IPv4Address(bytes: [224, 0, 0, 1])

  init(bytes: [UInt8], interface: NWInterface? = nil) {
    self.bytes = bytes
    self.interface = interface
  }

  public init?(_ rawValue: Data, _ interface: NWInterface? = nil) {
    if rawValue.count != 4 { return nil }
    self.init(bytes: Array(rawValue), interface: interface)
  }

  public init?(_ string: String) {
    guard let b = _inetPton(AF_INET, string, 4) else { return nil }
    self.init(bytes: b)
  }

  public var rawValue: Data { return Data(bytes) }
  public var isLoopback: Bool { return bytes[0] == 127 }
  public var isLinkLocal: Bool { return bytes[0] == 169 && bytes[1] == 254 }
  public var isMulticast: Bool { return bytes[0] >= 224 && bytes[0] <= 239 }
  public var debugDescription: String { return _inetNtop(AF_INET, bytes) }

  public static func == (a: IPv4Address, b: IPv4Address) -> Bool { return a.bytes == b.bytes }
  public func hash(into h: inout Hasher) { h.combine(bytes) }
}

public struct IPv6Address: IPAddress, Hashable, CustomDebugStringConvertible {
  let bytes: [UInt8]
  public let interface: NWInterface?

  public static let any = IPv6Address(bytes: [UInt8](repeating: 0, count: 16))
  public static let loopback = IPv6Address(bytes: [UInt8](repeating: 0, count: 15) + [1])

  init(bytes: [UInt8], interface: NWInterface? = nil) {
    self.bytes = bytes
    self.interface = interface
  }

  public init?(_ rawValue: Data, _ interface: NWInterface? = nil) {
    if rawValue.count != 16 { return nil }
    self.init(bytes: Array(rawValue), interface: interface)
  }

  public init?(_ string: String) {
    var s = string
    if s.hasPrefix("[") && s.hasSuffix("]") { s = String(s.dropFirst().dropLast()) }
    if let pct = s.firstIndex(of: "%") { s = String(s[..<pct]) }
    guard let b = _inetPton(AF_INET6, s, 16) else { return nil }
    self.init(bytes: b)
  }

  public var rawValue: Data { return Data(bytes) }
  public var isAny: Bool { return bytes.allSatisfy { $0 == 0 } }
  public var isLoopback: Bool { return bytes == IPv6Address.loopback.bytes }
  public var isLinkLocal: Bool { return bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 }
  public var isMulticast: Bool { return bytes[0] == 0xff }
  public var isIPv4Mapped: Bool {
    return bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xff && bytes[11] == 0xff
  }
  public var asIPv4: IPv4Address? {
    return isIPv4Mapped ? IPv4Address(bytes: Array(bytes[12..<16]), interface: interface) : nil
  }
  public var debugDescription: String { return _inetNtop(AF_INET6, bytes) }

  public static func == (a: IPv6Address, b: IPv6Address) -> Bool { return a.bytes == b.bytes }
  public func hash(into h: inout Hasher) { h.combine(bytes) }
}

// ---- endpoints ------------------------------------------------------------------------

public enum NWEndpoint: Hashable, CustomDebugStringConvertible {
  case hostPort(host: NWEndpoint.Host, port: NWEndpoint.Port)
  case service(name: String, type: String, domain: String, interface: NWInterface?)
  case unix(path: String)
  case url(URL)

  public enum Host: Hashable, CustomDebugStringConvertible, ExpressibleByStringLiteral {
    case name(String, NWInterface?)
    case ipv4(IPv4Address)
    case ipv6(IPv6Address)

    public init(_ string: String) {
      if let a = IPv4Address(string) { self = .ipv4(a) }
      else if let a = IPv6Address(string) { self = .ipv6(a) }
      else { self = .name(string, nil) }
    }

    public init(stringLiteral: String) { self.init(stringLiteral) }

    public var interface: NWInterface? {
      switch self {
      case .name(_, let i): return i
      case .ipv4(let a): return a.interface
      case .ipv6(let a): return a.interface
      }
    }

    public var debugDescription: String {
      switch self {
      case .name(let n, _): return n
      case .ipv4(let a): return a.debugDescription
      case .ipv6(let a): return a.debugDescription
      }
    }

    /// The text getaddrinfo takes.
    var _text: String {
      switch self {
      case .name(let n, _): return n
      case .ipv4(let a): return a.debugDescription
      case .ipv6(let a): return a.debugDescription
      }
    }
  }

  public struct Port: Hashable, CustomDebugStringConvertible, ExpressibleByIntegerLiteral, RawRepresentable {
    public let rawValue: UInt16

    public static let any = Port(integerLiteral: 0)
    public static let ssh = Port(integerLiteral: 22)
    public static let smtp = Port(integerLiteral: 25)
    public static let http = Port(integerLiteral: 80)
    public static let pop = Port(integerLiteral: 110)
    public static let imap = Port(integerLiteral: 143)
    public static let https = Port(integerLiteral: 443)
    public static let imaps = Port(integerLiteral: 993)
    public static let socks = Port(integerLiteral: 1080)

    public init?(rawValue: UInt16) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt16) { rawValue = value }

    public init?(_ string: String) {
      guard let v = UInt16(string) else { return nil }
      rawValue = v
    }

    public var debugDescription: String { return String(rawValue) }
  }

  public var interface: NWInterface? {
    switch self {
    case .hostPort(let host, _): return host.interface
    case .service(_, _, _, let i): return i
    default: return nil
    }
  }

  public var debugDescription: String {
    switch self {
    case .hostPort(let host, let port):
      if case .ipv6 = host { return "[\(host.debugDescription)]:\(port.rawValue)" }
      return "\(host.debugDescription):\(port.rawValue)"
    case .service(let name, let type, let domain, _): return "\(name).\(type)\(domain)"
    case .unix(let path): return path
    case .url(let url): return url.absoluteString
    }
  }
}

// ---- errors ------------------------------------------------------------------------

public enum NWError: Error, CustomDebugStringConvertible, Equatable {
  case posix(POSIXErrorCode)
  case dns(Int32)
  case tls(Int32)

  public var debugDescription: String {
    switch self {
    case .posix(let code):
      return "POSIXErrorCode(rawValue: \(code.rawValue)): " + String(cString: strerror(code.rawValue))
    case .dns(let code): return "DNSServiceErrorType(\(code))"
    case .tls(let status): return "OSStatus(\(status)): TLS is not available"
    }
  }

  public static func == (a: NWError, b: NWError) -> Bool {
    switch (a, b) {
    case (.posix(let x), .posix(let y)): return x == y
    case (.dns(let x), .dns(let y)): return x == y
    case (.tls(let x), .tls(let y)): return x == y
    default: return false
    }
  }

  static func _errno(_ e: Int32) -> NWError {
    return .posix(POSIXErrorCode(rawValue: e) ?? .EIO)
  }
}

// ---- paths --------------------------------------------------------------------------

public struct NWPath: Equatable, CustomDebugStringConvertible {
  public enum Status: Equatable, Hashable {
    case satisfied
    case unsatisfied
    case requiresConnection
  }

  public let status: Status
  public let availableInterfaces: [NWInterface]
  public let isExpensive: Bool
  public let isConstrained: Bool
  public let supportsIPv4: Bool
  public let supportsIPv6: Bool
  public let supportsDNS: Bool
  public let localEndpoint: NWEndpoint?
  public let remoteEndpoint: NWEndpoint?

  init(status: Status, interfaces: [NWInterface], local: NWEndpoint? = nil, remote: NWEndpoint? = nil) {
    self.status = status
    availableInterfaces = interfaces
    isExpensive = false
    isConstrained = false
    supportsIPv4 = true
    supportsIPv6 = true
    supportsDNS = true
    localEndpoint = local
    remoteEndpoint = remote
  }

  public func usesInterfaceType(_ type: NWInterface.InterfaceType) -> Bool {
    return availableInterfaces.contains { $0.type == type }
  }

  public var gateways: [NWEndpoint] { return [] }

  public var debugDescription: String {
    switch status {
    case .satisfied: return "satisfied"
    case .unsatisfied: return "unsatisfied"
    case .requiresConnection: return "requiresConnection"
    }
  }

  public static func == (a: NWPath, b: NWPath) -> Bool {
    return a.status == b.status && a.availableInterfaces == b.availableInterfaces &&
      a.localEndpoint == b.localEndpoint && a.remoteEndpoint == b.remoteEndpoint
  }

  /// The machine's interfaces, by name: a container has a loopback and,
  /// usually, an Ethernet interface.
  static func _current() -> NWPath {
    var interfaces: [NWInterface] = []
    // Interface indexes are small integers; ask for the name of each.
    var name = [CChar](repeating: 0, count: 64)
    for index in 1...64 {
      guard name.withUnsafeMutableBufferPointer({ if_indextoname(UInt32(index), $0.baseAddress!) }) != nil else { continue }
      let n = String(cString: name)
      let type: NWInterface.InterfaceType = n.hasPrefix("lo") ? .loopback : (n.hasPrefix("wl") ? .wifi : .wiredEthernet)
      interfaces.append(NWInterface(name: n, type: type, index: index))
    }
    if interfaces.isEmpty { interfaces = [NWInterface(name: "lo0", type: .loopback, index: 1)] }
    let online = interfaces.contains { $0.type != .loopback }
    return NWPath(status: online ? .satisfied : .unsatisfied, interfaces: interfaces.filter { $0.type != .loopback } + interfaces.filter { $0.type == .loopback })
  }
}

public final class NWPathMonitor {
  public var pathUpdateHandler: ((NWPath) -> Void)?
  public private(set) var queue: DispatchQueue?
  let requiredType: NWInterface.InterfaceType?

  public init() { requiredType = nil }
  public init(requiredInterfaceType: NWInterface.InterfaceType) { requiredType = requiredInterfaceType }
  public init(prohibitedInterfaceTypes: [NWInterface.InterfaceType]) { requiredType = nil }

  public var currentPath: NWPath {
    let path = NWPath._current()
    if let t = requiredType, !path.usesInterfaceType(t) {
      return NWPath(status: .unsatisfied, interfaces: [])
    }
    return path
  }

  public func start(queue: DispatchQueue) {
    self.queue = queue
    let path = currentPath
    queue.async { self.pathUpdateHandler?(path) }
  }

  public func cancel() { pathUpdateHandler = nil }
}

// ---- protocols and parameters ---------------------------------------------------------

public final class NWProtocolDefinition: Equatable, CustomDebugStringConvertible {
  public let name: String
  init(name: String) { self.name = name }
  public var debugDescription: String { return name }
  public static func == (a: NWProtocolDefinition, b: NWProtocolDefinition) -> Bool { return a.name == b.name }
}

public class NWProtocolOptions {
  public var definition: NWProtocolDefinition { return NWProtocolDefinition(name: "options") }
  init() {}
}

public class NWProtocolMetadata {
  public var definition: NWProtocolDefinition { return NWProtocolDefinition(name: "metadata") }
  init() {}
}

public class NWProtocol {
  init() {}
}

public class NWProtocolIP: NWProtocol {
  public static let definition = NWProtocolDefinition(name: "ip")

  public class Options: NWProtocolOptions {
    public enum Version {
      case any
      case v4
      case v6
    }

    public var version: Version = .any
    public var hopLimit: UInt8 = 64
    public var useMinimumMTU: Bool = false
    public var disableFragmentation: Bool = false
    public var shouldCalculateReceiveTime: Bool = false
    public override var definition: NWProtocolDefinition { return NWProtocolIP.definition }
  }
}

public class NWProtocolTCP: NWProtocol {
  public static let definition = NWProtocolDefinition(name: "tcp")

  public class Options: NWProtocolOptions {
    public var noDelay: Bool = false
    public var noPush: Bool = false
    public var noOptions: Bool = false
    public var enableKeepalive: Bool = false
    public var keepaliveCount: Int = 0
    public var keepaliveIdle: Int = 0
    public var keepaliveInterval: Int = 0
    public var maximumSegmentSize: Int = 0
    public var connectionTimeout: Int = 0
    public var persistTimeout: Int = 0
    public var retransmitConnectionDropTime: Int = 0
    public var connectionDropTime: Int = 0
    public var retransmitFinDrop: Bool = false
    public var disableAckStretching: Bool = false
    public var enableFastOpen: Bool = false
    public var disableECN: Bool = false

    public override init() { super.init() }
    public override var definition: NWProtocolDefinition { return NWProtocolTCP.definition }
  }
}

public class NWProtocolUDP: NWProtocol {
  public static let definition = NWProtocolDefinition(name: "udp")

  public class Options: NWProtocolOptions {
    public var preferNoChecksum: Bool = false
    public override init() { super.init() }
    public override var definition: NWProtocolDefinition { return NWProtocolUDP.definition }
  }
}

public class NWProtocolTLS: NWProtocol {
  public static let definition = NWProtocolDefinition(name: "tls")

  public class Options: NWProtocolOptions {
    public override init() { super.init() }
    public override var definition: NWProtocolDefinition { return NWProtocolTLS.definition }

    /// No TLS implementation exists here; there are no options to give.
    public var securityProtocolOptions: sec_protocol_options_t {
      fatalError("Network: TLS is not available")
    }
  }

  public class Metadata: NWProtocolMetadata {
    public var securityProtocolMetadata: sec_protocol_metadata_t {
      fatalError("Network: TLS is not available")
    }
    public override var definition: NWProtocolDefinition { return NWProtocolTLS.definition }
  }
}

public final class NWParameters: CustomDebugStringConvertible {
  public enum MultipathServiceType {
    case disabled
    case handover
    case interactive
    case aggregate
  }

  public enum ExpiredDNSBehavior {
    case systemDefault
    case allow
    case prohibit
  }

  public class ProtocolStack {
    public var applicationProtocols: [NWProtocolOptions]
    public var transportProtocol: NWProtocolOptions?
    public var internetProtocol: NWProtocolOptions?

    init(application: [NWProtocolOptions], transport: NWProtocolOptions?) {
      applicationProtocols = application
      transportProtocol = transport
      internetProtocol = NWProtocolIP.Options()
    }
  }

  public var requiredLocalEndpoint: NWEndpoint?
  public var requiredInterface: NWInterface?
  public var requiredInterfaceType: NWInterface.InterfaceType = .other
  public var prohibitedInterfaceTypes: [NWInterface.InterfaceType]?
  public var prohibitedInterfaces: [NWInterface]?
  public var prohibitExpensivePaths: Bool = false
  public var prohibitConstrainedPaths: Bool = false
  public var multipathServiceType: MultipathServiceType = .disabled
  public var includePeerToPeer: Bool = false
  public var allowLocalEndpointReuse: Bool = false
  public var acceptLocalOnly: Bool = false
  public var allowFastOpen: Bool = false
  public var preferNoProxies: Bool = false
  public var expiredDNSBehavior: ExpiredDNSBehavior = .systemDefault
  public let defaultProtocolStack: ProtocolStack

  let datagram: Bool
  let wantsTLS: Bool

  public init() {
    defaultProtocolStack = ProtocolStack(application: [], transport: NWProtocolTCP.Options())
    datagram = false
    wantsTLS = false
  }

  public init(tls: NWProtocolTLS.Options?, tcp: NWProtocolTCP.Options = NWProtocolTCP.Options()) {
    defaultProtocolStack = ProtocolStack(application: tls.map { [$0] } ?? [], transport: tcp)
    datagram = false
    wantsTLS = tls != nil
  }

  public init(dtls: NWProtocolTLS.Options?, udp: NWProtocolUDP.Options = NWProtocolUDP.Options()) {
    defaultProtocolStack = ProtocolStack(application: dtls.map { [$0] } ?? [], transport: udp)
    datagram = true
    wantsTLS = dtls != nil
  }

  public static var tcp: NWParameters { return NWParameters(tls: nil) }
  public static var udp: NWParameters { return NWParameters(dtls: nil) }
  public static var tls: NWParameters { return NWParameters(tls: NWProtocolTLS.Options()) }
  public static var dtls: NWParameters { return NWParameters(dtls: NWProtocolTLS.Options()) }

  public func copy() -> NWParameters {
    let p = datagram ? NWParameters(dtls: wantsTLS ? NWProtocolTLS.Options() : nil)
                     : NWParameters(tls: wantsTLS ? NWProtocolTLS.Options() : nil)
    p.requiredLocalEndpoint = requiredLocalEndpoint
    p.requiredInterface = requiredInterface
    p.allowLocalEndpointReuse = allowLocalEndpointReuse
    p.includePeerToPeer = includePeerToPeer
    return p
  }

  public var debugDescription: String { return datagram ? "udp" : (wantsTLS ? "tls" : "tcp") }

  var tcpOptions: NWProtocolTCP.Options? { return defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options }

  var ipVersion: NWProtocolIP.Options.Version {
    return (defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version ?? .any
  }
}
