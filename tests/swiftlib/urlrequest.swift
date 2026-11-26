// URLRequest's value semantics and bridging, WebSocket messages, and the
// TLS version of transaction metrics, through the Swift overlay.
import Foundation
import Security

@_silgen_name("swl_ur_request") public func request() -> Int {
  var bad = 0
  var a = URLRequest(url: URL(string: "https://example.com/a")!)
  if a.httpMethod != "GET" || a.timeoutInterval != 60 || a.cachePolicy != .useProtocolCachePolicy { bad |= 1 }
  var b = a
  b.httpMethod = "POST"
  b.setValue("text/plain", forHTTPHeaderField: "Content-Type")
  b.httpBody = Data("x".utf8)
  if a.httpMethod != "GET" || a.allHTTPHeaderFields != nil || a.httpBody != nil { bad |= 2 }
  if b.value(forHTTPHeaderField: "content-type") != "text/plain" || b.httpBody?.count != 1 { bad |= 4 }
  if a == b || a != URLRequest(url: URL(string: "https://example.com/a")!) { bad |= 8 }
  b.addValue("text/html", forHTTPHeaderField: "Content-Type")
  if b.value(forHTTPHeaderField: "Content-Type") != "text/plain,text/html" { bad |= 0x10 }
  // Through Objective-C and back.
  let ns = b._bridgeToObjectiveC()
  if ns.httpMethod != "POST" || ns.url?.absoluteString != "https://example.com/a" { bad |= 0x20 }
  let back = URLRequest._unconditionallyBridgeFromObjectiveC(ns)
  if back != b || back.url?.path != "/a" { bad |= 0x40 }
  a.url = URL(string: "https://example.com/b")
  if a.description != "https://example.com/b" { bad |= 0x80 }
  return bad
}

@_silgen_name("swl_ur_websocket") public func websocket() -> Int {
  var bad = 0
  let messages: [URLSessionWebSocketTask.Message] = [.string("hi"), .data(Data([1, 2]))]
  switch messages[0] { case .string(let s): if s != "hi" { bad |= 1 }; default: bad |= 2 }
  switch messages[1] { case .data(let d): if d != Data([1, 2]) { bad |= 4 }; default: bad |= 8 }
  if tls_protocol_version_t(rawValue: 0x0304).rawValue != 0x0304 { bad |= 0x10 }
  let config = URLSessionConfiguration.ephemeral
  if config.timeoutIntervalForRequest != 60 || config.tlsMinimumSupportedProtocolVersion.rawValue != 0x0301 { bad |= 0x20 }
  if URLSession.shared !== URLSession.shared { bad |= 0x40 }
  return bad
}
