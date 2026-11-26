// Network.framework over real sockets: a listener and a connection on the
// loopback interface, failures, addresses and endpoints, the path monitor.
import Foundation
import Dispatch
import Network

func waitFor(_ s: DispatchSemaphore) -> Bool { return s.wait(timeout: .now() + .seconds(10)) == .success }

@_silgen_name("swl_network_values") public func values() -> Int {
  var bad = 0
  guard let a = IPv4Address("127.0.0.1"), a.isLoopback, a.rawValue == Data([127, 0, 0, 1]) else { return 1 }
  if a.debugDescription != "127.0.0.1" || IPv4Address("300.1.1.1") != nil { bad |= 2 }
  guard let b = IPv6Address("::ffff:10.0.0.1") else { return 4 }
  if !b.isIPv4Mapped || b.asIPv4 != IPv4Address("10.0.0.1") || IPv6Address("::1")?.isLoopback != true { bad |= 8 }
  if case .ipv4 = NWEndpoint.Host("10.1.2.3") {} else { bad |= 16 }
  if case .name("example.org", nil) = NWEndpoint.Host("example.org") {} else { bad |= 32 }
  let e = NWEndpoint.hostPort(host: "::1", port: 8080)
  if e.debugDescription != "[::1]:8080" || NWEndpoint.Port(rawValue: 22) != .ssh || NWEndpoint.Port.any.rawValue != 0 { bad |= 64 }
  if NWError.posix(.ECONNREFUSED) == NWError.dns(1) || NWError.posix(.EPIPE) != .posix(.EPIPE) { bad |= 128 }
  let p = NWParameters.tcp
  p.allowLocalEndpointReuse = true
  if p.defaultProtocolStack.internetProtocol == nil || NWProtocolTCP.definition != NWProtocolTCP.definition { bad |= 256 }
  return bad
}

@_silgen_name("swl_network_echo") public func echo() -> Int {
  var bad = 0
  let q = DispatchQueue(label: "test.network")
  let params = NWParameters.tcp
  params.acceptLocalOnly = true
  guard let listener = try? NWListener(using: params, on: .any) else { return 1 }
  let ready = DispatchSemaphore(value: 0)
  listener.stateUpdateHandler = { if $0 == .ready { ready.signal() } }
  // The server echoes what it receives, upper-cased, then closes.
  listener.newConnectionHandler = { conn in
    conn.start(queue: q)
    conn.receive(minimumIncompleteLength: 5, maximumLength: 64) { data, _, _, _ in
      let reply = Data((data.map { Array($0) } ?? []).map { $0 >= 97 && $0 <= 122 ? $0 - 32 : $0 })
      conn.send(content: reply, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in })
    }
  }
  listener.start(queue: q)
  if !waitFor(ready) { return 2 }
  guard let port = listener.port, port.rawValue != 0 else { return 4 }

  let client = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
  let connected = DispatchSemaphore(value: 0)
  var sawPreparing = false
  client.stateUpdateHandler = { state in
    if state == .preparing { sawPreparing = true }
    if state == .ready { connected.signal() }
  }
  client.start(queue: q)
  if !waitFor(connected) || !sawPreparing { bad |= 8 }
  if client.currentPath?.remoteEndpoint != .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: port) { bad |= 16 }

  let sent = DispatchSemaphore(value: 0)
  client.send(content: "hello".data(using: .utf8), completion: .contentProcessed { e in
    if e != nil { bad |= 32 }
    sent.signal()
  })
  if !waitFor(sent) { bad |= 64 }
  let got = DispatchSemaphore(value: 0)
  var reply = Data(), finished = false
  func readAll() {
    client.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, complete, error in
      if let d = data { reply.append(d) }
      if complete || error != nil { finished = complete; got.signal() } else { readAll() }
    }
  }
  readAll()
  if !waitFor(got) || String(data: reply, encoding: .utf8) != "HELLO" || !finished { bad |= 128 }

  let report = DispatchSemaphore(value: 0)
  client.requestEstablishmentReport(queue: q) { r in
    if r?.resolutions.first?.successfulEndpoint == nil { bad |= 256 }
    report.signal()
  }
  if !waitFor(report) { bad |= 512 }

  let cancelled = DispatchSemaphore(value: 0)
  client.stateUpdateHandler = { if $0 == .cancelled { cancelled.signal() } }
  client.cancel()
  if !waitFor(cancelled) || client.state != .cancelled { bad |= 1024 }
  listener.cancel()
  return bad
}

@_silgen_name("swl_network_failures") public func failures() -> Int {
  var bad = 0
  let q = DispatchQueue(label: "test.network.fail")
  // Nothing listens on a port we just released.
  guard let l = try? NWListener(using: .tcp, on: .any), let port = l.port else { return 1 }
  l.cancel()
  func outcome(_ c: NWConnection) -> NWConnection.State? {
    let s = DispatchSemaphore(value: 0)
    var last: NWConnection.State? = nil
    c.stateUpdateHandler = { st in
      if case .failed = st { last = st; s.signal() }
      if case .ready = st { last = st; s.signal() }
    }
    c.start(queue: q)
    return waitFor(s) ? last : nil
  }
  if outcome(NWConnection(host: "127.0.0.1", port: port, using: .tcp)) != .failed(.posix(.ECONNREFUSED)) { bad |= 2 }
  if case .failed(.dns)? = outcome(NWConnection(host: "no-such-host.invalid", port: 80, using: .tcp)) {} else { bad |= 4 }
  if case .failed(.tls)? = outcome(NWConnection(host: "127.0.0.1", port: 443, using: .tls)) {} else { bad |= 8 }
  // The path monitor reports the machine's interfaces.
  let monitor = NWPathMonitor()
  let updated = DispatchSemaphore(value: 0)
  var path: NWPath? = nil
  monitor.pathUpdateHandler = { path = $0; updated.signal() }
  monitor.start(queue: q)
  if !waitFor(updated) || path?.usesInterfaceType(.loopback) != true { bad |= 16 }
  monitor.cancel()
  return bad
}
