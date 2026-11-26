// NWConnection and NWListener over BSD sockets. Each connection owns a
// socket and two private serial queues, one for reads and one for writes,
// on which blocking calls run; results are delivered on the queue given to
// start(queue:), as Network.framework does.
import Foundation
import Dispatch
import Darwin

let _MSG_NOSIGNAL: Int32 = 0x80000

/// A connected or listening socket, closed once.
final class _Socket {
  private(set) var fd: Int32
  private let lock = DispatchSemaphore(value: 1)

  init(_ fd: Int32) {
    self.fd = fd
    var one: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
  }

  func shutdownBoth() {
    lock.wait()
    if fd >= 0 { _ = Darwin.shutdown(fd, SHUT_RDWR) }
    lock.signal()
  }

  func close() {
    lock.wait()
    if fd >= 0 { _ = Darwin.close(fd); fd = -1 }
    lock.signal()
  }

  deinit { close() }
}

/// getaddrinfo over an endpoint; tries each address in turn.
func _connect(_ endpoint: NWEndpoint, datagram: Bool, parameters: NWParameters) -> Result<Int32, NWError> {
  switch endpoint {
  case .unix(let path):
    let fd = socket(AF_UNIX, datagram ? SOCK_DGRAM : SOCK_STREAM, 0)
    if fd < 0 { return .failure(NWError._errno(errno)) }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    if bytes.count >= capacity { _ = close(fd); return .failure(.posix(.ENAMETOOLONG)) }
    withUnsafeMutableBytes(of: &addr.sun_path) { p in
      for (i, b) in bytes.enumerated() { p[i] = b }
    }
    let rc = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    if rc != 0 { let e = errno; _ = close(fd); return .failure(NWError._errno(e)) }
    return .success(fd)
  case .hostPort(let host, let port):
    var hints = addrinfo()
    switch parameters.ipVersion {
    case .v4: hints.ai_family = AF_INET
    case .v6: hints.ai_family = AF_INET6
    case .any: hints.ai_family = AF_UNSPEC
    }
    hints.ai_socktype = datagram ? SOCK_DGRAM : SOCK_STREAM
    var list: UnsafeMutablePointer<addrinfo>? = nil
    let rc = getaddrinfo(host._text, String(port.rawValue), &hints, &list)
    if rc != 0 { return .failure(.dns(-65554)) }    // kDNSServiceErr_NoSuchRecord
    defer { freeaddrinfo(list) }
    var last: NWError = .posix(.ECONNREFUSED)
    var p = list
    while let ai = p {
      let fd = socket(ai.pointee.ai_family, ai.pointee.ai_socktype, ai.pointee.ai_protocol)
      if fd >= 0 {
        if parameters.allowLocalEndpointReuse {
          var one: Int32 = 1
          _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        }
        if let tcp = parameters.tcpOptions, tcp.noDelay, !datagram {
          var one: Int32 = 1
          _ = setsockopt(fd, Int32(IPPROTO_TCP), TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
        }
        if Darwin.connect(fd, ai.pointee.ai_addr, ai.pointee.ai_addrlen) == 0 { return .success(fd) }
        last = NWError._errno(errno)
        _ = close(fd)
      } else {
        last = NWError._errno(errno)
      }
      p = ai.pointee.ai_next
    }
    return .failure(last)
  default:
    return .failure(.posix(.EAFNOSUPPORT))
  }
}

/// The endpoint at the other end (or this end) of a socket.
func _endpoint(_ fd: Int32, peer: Bool) -> NWEndpoint? {
  var storage = sockaddr_storage()
  var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
  let rc = withUnsafeMutablePointer(to: &storage) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      peer ? getpeername(fd, $0, &len) : getsockname(fd, $0, &len)
    }
  }
  if rc != 0 { return nil }
  switch Int32(storage.ss_family) {
  case AF_INET:
    return withUnsafePointer(to: &storage) {
      $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin -> NWEndpoint in
        var a = sin.pointee.sin_addr
        let bytes = withUnsafeBytes(of: &a) { Array($0) }
        return .hostPort(host: .ipv4(IPv4Address(bytes: bytes)),
                         port: NWEndpoint.Port(integerLiteral: UInt16(bigEndian: sin.pointee.sin_port)))
      }
    }
  case AF_INET6:
    return withUnsafePointer(to: &storage) {
      $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin -> NWEndpoint in
        var a = sin.pointee.sin6_addr
        let bytes = withUnsafeBytes(of: &a) { Array($0) }
        return .hostPort(host: .ipv6(IPv6Address(bytes: bytes)),
                         port: NWEndpoint.Port(integerLiteral: UInt16(bigEndian: sin.pointee.sin6_port)))
      }
    }
  default:
    return nil
  }
}

public final class NWConnection: CustomDebugStringConvertible {
  public enum State: Equatable {
    case setup
    case waiting(NWError)
    case preparing
    case ready
    case failed(NWError)
    case cancelled

    public static func == (a: State, b: State) -> Bool {
      switch (a, b) {
      case (.setup, .setup), (.preparing, .preparing), (.ready, .ready), (.cancelled, .cancelled): return true
      case (.waiting(let x), .waiting(let y)), (.failed(let x), .failed(let y)): return x == y
      default: return false
      }
    }
  }

  public enum SendCompletion {
    case contentProcessed((NWError?) -> Void)
    case idempotent
  }

  public final class ContentContext {
    public let identifier: String
    public let expirationMilliseconds: UInt64
    public let relativePriority: Double
    public let isFinal: Bool
    public let antecedent: ContentContext?
    public let protocolMetadata: [NWProtocolMetadata]

    public init(identifier: String, expiration: UInt64 = 0, priority: Double = 0.5, isFinal: Bool = false,
                antecedent: ContentContext? = nil, metadata: [NWProtocolMetadata]? = []) {
      self.identifier = identifier
      expirationMilliseconds = expiration
      relativePriority = priority
      self.isFinal = isFinal
      self.antecedent = antecedent
      protocolMetadata = metadata ?? []
    }

    public static let defaultMessage = ContentContext(identifier: "default")
    public static let finalMessage = ContentContext(identifier: "final", isFinal: true)
    public static let defaultStream = ContentContext(identifier: "stream")

    public func protocolMetadata(definition: NWProtocolDefinition) -> NWProtocolMetadata? {
      return protocolMetadata.first { $0.definition == definition }
    }
  }

  public struct EstablishmentReport {

    public struct Resolution {
      public enum Source: Equatable {
        case query
        case cache
        case expiredCache
      }
      public let source: Source
      public let duration: TimeInterval
      public let endpointCount: Int
      public let successfulEndpoint: NWEndpoint
      public let preferredEndpoint: NWEndpoint
    }

    public struct Handshake {
      public let definition: NWProtocolDefinition
      public let handshakeDuration: TimeInterval
      public let handshakeRTT: TimeInterval
    }

    public let duration: TimeInterval
    public let attemptStartedAfterInterval: TimeInterval
    public let previousAttemptCount: Int
    public let usedProxy: Bool
    public let proxyEndpoint: NWEndpoint?
    public let resolutions: [Resolution]
    public let handshakes: [Handshake]
  }

  public struct DataTransferReport {
    public let duration: TimeInterval
    public let pathReports: [Int]
  }

  public final class PendingDataTransferReport {
    let started: DispatchTime
    init(started: DispatchTime) { self.started = started }
    public func collect(queue: DispatchQueue, completion: @escaping (DataTransferReport) -> Void) {
      let d = TimeInterval(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e9
      queue.async { completion(DataTransferReport(duration: d, pathReports: [])) }
    }
  }

  public let endpoint: NWEndpoint
  public let parameters: NWParameters
  public private(set) var queue: DispatchQueue?
  public private(set) var state: State = .setup

  public var stateUpdateHandler: ((State) -> Void)?
  public var viabilityUpdateHandler: ((Bool) -> Void)?
  public var betterPathUpdateHandler: ((Bool) -> Void)?
  public var pathUpdateHandler: ((NWPath) -> Void)?

  var socket: _Socket?
  let reads = DispatchQueue(label: "Network.NWConnection.reads")
  let writes = DispatchQueue(label: "Network.NWConnection.writes")
  var connectStarted = DispatchTime.now()
  var connectDuration: TimeInterval = 0

  public init(to endpoint: NWEndpoint, using parameters: NWParameters) {
    self.endpoint = endpoint
    self.parameters = parameters
  }

  public convenience init(host: NWEndpoint.Host, port: NWEndpoint.Port, using parameters: NWParameters) {
    self.init(to: .hostPort(host: host, port: port), using: parameters)
  }

  /// An accepted connection (NWListener).
  init(accepted fd: Int32, endpoint: NWEndpoint, parameters: NWParameters) {
    self.endpoint = endpoint
    self.parameters = parameters
    socket = _Socket(fd)
  }

  public var debugDescription: String { return "NWConnection to \(endpoint.debugDescription)" }

  public var currentPath: NWPath? {
    guard let fd = socket?.fd, fd >= 0, case .ready = state else { return nil }
    let base = NWPath._current()
    return NWPath(status: .satisfied, interfaces: base.availableInterfaces,
                  local: _endpoint(fd, peer: false), remote: _endpoint(fd, peer: true))
  }

  func setState(_ s: State) {
    guard let q = queue else { state = s; return }
    q.async {
      if case .cancelled = self.state { return }
      if case .failed = self.state, s != .cancelled { return }
      self.state = s
      self.stateUpdateHandler?(s)
      if case .ready = s, let path = self.currentPath {
        self.viabilityUpdateHandler?(true)
        self.pathUpdateHandler?(path)
      }
    }
  }

  public func start(queue: DispatchQueue) {
    guard self.queue == nil else { return }
    self.queue = queue
    if socket != nil { setState(.ready); return }       // accepted
    if parameters.wantsTLS {
      setState(.preparing)
      setState(.failed(.tls(-9810)))                    // errSSLInternal: no TLS here
      return
    }
    setState(.preparing)
    connectStarted = DispatchTime.now()
    reads.async {
      switch _connect(self.endpoint, datagram: self.parameters.datagram, parameters: self.parameters) {
      case .success(let fd):
        self.socket = _Socket(fd)
        self.connectDuration = TimeInterval(DispatchTime.now().uptimeNanoseconds - self.connectStarted.uptimeNanoseconds) / 1e9
        self.setState(.ready)
      case .failure(let e):
        self.setState(.failed(e))
      }
    }
  }

  public func restart() {
    if case .waiting = state { queue.map { q in self.queue = nil; self.start(queue: q) } }
  }

  public func cancel() {
    socket?.shutdownBoth()
    let s = socket
    reads.async { s?.close() }
    guard let q = queue else { state = .cancelled; return }
    q.async {
      if case .cancelled = self.state { return }
      self.state = .cancelled
      self.stateUpdateHandler?(.cancelled)
    }
  }

  public func forceCancel() { cancel() }

  public func cancelCurrentEndpoint() { cancel() }

  public func batch(_ block: () -> Void) { block() }

  public func send(content: Data?, contentContext: ContentContext = .defaultMessage, isComplete: Bool = true,
                   completion: SendCompletion) {
    let bytes = content.map { Array($0) } ?? []
    writes.async {
      var error: NWError? = nil
      if let fd = self.socket?.fd, fd >= 0 {
        var off = 0
        while off < bytes.count {
          let n = bytes.withUnsafeBytes { Darwin.send(fd, $0.baseAddress! + off, bytes.count - off, _MSG_NOSIGNAL) }
          if n < 0 {
            if errno == EINTR { continue }
            error = NWError._errno(errno)
            break
          }
          off += n
        }
        if error == nil && isComplete && contentContext.isFinal && !self.parameters.datagram {
          _ = Darwin.shutdown(fd, SHUT_WR)
        }
      } else {
        error = .posix(.ENOTCONN)
      }
      if case .contentProcessed(let done) = completion {
        (self.queue ?? DispatchQueue.global()).async { done(error) }
      }
    }
  }

  public func receive(minimumIncompleteLength: Int, maximumLength: Int,
                      completion: @escaping (Data?, ContentContext?, Bool, NWError?) -> Void) {
    reads.async {
      var got = [UInt8]()
      var complete = false
      var error: NWError? = nil
      let want = Swift.max(maximumLength, 1)
      if let fd = self.socket?.fd, fd >= 0 {
        var buf = [UInt8](repeating: 0, count: want)
        repeat {
          let n = buf.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress!, want - got.count, 0) }
          if n < 0 {
            if errno == EINTR { continue }
            if case .cancelled = self.state { break }
            error = NWError._errno(errno)
            break
          }
          if n == 0 { complete = true; break }
          got.append(contentsOf: buf[0..<n])
          if self.parameters.datagram { complete = true; break }
        } while got.count < Swift.max(minimumIncompleteLength, 1) && got.count < want
      } else {
        error = .posix(.ENOTCONN)
      }
      let data: Data? = got.isEmpty ? nil : Data(got)
      let context: ContentContext? = complete ? .finalMessage : .defaultMessage
      (self.queue ?? DispatchQueue.global()).async { completion(data, context, complete, error) }
    }
  }

  public func receiveMessage(completion: @escaping (Data?, ContentContext?, Bool, NWError?) -> Void) {
    receive(minimumIncompleteLength: 1, maximumLength: 65536, completion: completion)
  }

  public func metadata(definition: NWProtocolDefinition) -> NWProtocolMetadata? {
    return nil
  }

  public func requestEstablishmentReport(queue: DispatchQueue, completion: @escaping (EstablishmentReport?) -> Void) {
    let report: EstablishmentReport?
    if case .ready = state {
      report = EstablishmentReport(
        duration: connectDuration, attemptStartedAfterInterval: 0, previousAttemptCount: 0,
        usedProxy: false, proxyEndpoint: nil,
        resolutions: [EstablishmentReport.Resolution(source: .query, duration: 0, endpointCount: 1,
                                                     successfulEndpoint: endpoint, preferredEndpoint: endpoint)],
        handshakes: [EstablishmentReport.Handshake(definition: parameters.datagram ? NWProtocolUDP.definition : NWProtocolTCP.definition,
                                                   handshakeDuration: connectDuration, handshakeRTT: connectDuration)])
    } else {
      report = nil
    }
    queue.async { completion(report) }
  }

  public func startDataTransferReport() -> PendingDataTransferReport {
    return PendingDataTransferReport(started: DispatchTime.now())
  }
}

public final class NWListener: CustomDebugStringConvertible {
  public enum State: Equatable {
    case setup
    case waiting(NWError)
    case ready
    case failed(NWError)
    case cancelled

    public static func == (a: State, b: State) -> Bool {
      switch (a, b) {
      case (.setup, .setup), (.ready, .ready), (.cancelled, .cancelled): return true
      case (.waiting(let x), .waiting(let y)), (.failed(let x), .failed(let y)): return x == y
      default: return false
      }
    }
  }

  public struct Service: Equatable {
    public let name: String?
    public let type: String
    public let domain: String?
    public let txtRecord: Data?

    public init(name: String? = nil, type: String, domain: String? = nil, txtRecord: Data? = nil) {
      self.name = name
      self.type = type
      self.domain = domain
      self.txtRecord = txtRecord
    }
  }

  public let parameters: NWParameters
  public private(set) var queue: DispatchQueue?
  public private(set) var state: State = .setup
  public var service: Service?
  public var stateUpdateHandler: ((State) -> Void)?
  public var newConnectionHandler: ((NWConnection) -> Void)?
  public var newConnectionLimit: Int = Int.max
  var socket: _Socket
  let accepts = DispatchQueue(label: "Network.NWListener.accept")

  public init(using parameters: NWParameters, on port: NWEndpoint.Port = .any) throws {
    if parameters.wantsTLS { throw NWError.tls(-9810) }
    self.parameters = parameters
    let v6 = parameters.ipVersion == .v6
    let fd = Darwin.socket(v6 ? AF_INET6 : AF_INET, parameters.datagram ? SOCK_DGRAM : SOCK_STREAM, 0)
    if fd < 0 { throw NWError._errno(errno) }
    var one: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
    var rc: Int32
    if v6 {
      var addr = sockaddr_in6()
      addr.sin6_family = sa_family_t(AF_INET6)
      addr.sin6_port = port.rawValue.bigEndian
      rc = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
      }
    } else {
      var addr = sockaddr_in()
      addr.sin_family = sa_family_t(AF_INET)
      addr.sin_port = port.rawValue.bigEndian
      if parameters.acceptLocalOnly { addr.sin_addr.s_addr = UInt32(0x7f000001).bigEndian }
      rc = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
      }
    }
    if rc != 0 { let e = errno; _ = Darwin.close(fd); throw NWError._errno(e) }
    if !parameters.datagram && listen(fd, 128) != 0 { let e = errno; _ = Darwin.close(fd); throw NWError._errno(e) }
    socket = _Socket(fd)
  }

  public var port: NWEndpoint.Port? {
    guard case .hostPort(_, let p)? = _endpoint(socket.fd, peer: false) else { return nil }
    return p
  }

  public var debugDescription: String { return "NWListener on \(port?.rawValue ?? 0)" }

  func setState(_ s: State) {
    queue?.async {
      if case .cancelled = self.state { return }
      self.state = s
      self.stateUpdateHandler?(s)
    }
  }

  public func start(queue: DispatchQueue) {
    guard self.queue == nil else { return }
    self.queue = queue
    setState(.ready)
    accepts.async { self.acceptLoop() }
  }

  func acceptLoop() {
    while true {
      let fd = socket.fd
      if fd < 0 { return }
      let c = accept(fd, nil, nil)
      if c < 0 {
        if errno == EINTR { continue }
        if case .cancelled = state { return }
        if socket.fd < 0 { return }
        setState(.failed(NWError._errno(errno)))
        return
      }
      let remote = _endpoint(c, peer: true) ?? .unix(path: "")
      let conn = NWConnection(accepted: c, endpoint: remote, parameters: parameters)
      queue?.async {
        if let handler = self.newConnectionHandler { handler(conn) } else { conn.cancel() }
      }
    }
  }

  public func cancel() {
    socket.shutdownBoth()
    socket.close()
    queue?.async {
      if case .cancelled = self.state { return }
      self.state = .cancelled
      self.stateUpdateHandler?(.cancelled)
    }
  }
}
