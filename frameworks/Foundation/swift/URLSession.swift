// URL loading for Swift: URLRequest (a value type over NSMutableURLRequest,
// bridged to NSURLRequest), WebSocket messages, the TLS details of
// transaction metrics, and URLSession's async methods.

import Security
import _Concurrency

// MARK: - URLRequest

public struct URLRequest: Hashable, Equatable, @unchecked Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  public typealias CachePolicy = NSURLRequest.CachePolicy
  public typealias NetworkServiceType = NSURLRequest.NetworkServiceType
  public typealias Attribution = NSURLRequest.Attribution

  internal var _handle: NSMutableURLRequest

  public init(url: URL, cachePolicy: CachePolicy = .useProtocolCachePolicy, timeoutInterval: TimeInterval = 60.0) {
    _handle = NSMutableURLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
  }

  internal init(_bridged request: NSURLRequest) {
    _handle = request.mutableCopy() as! NSMutableURLRequest
  }

  private mutating func _unique() {
    if !isKnownUniquelyReferenced(&_handle) {
      _handle = _handle.mutableCopy() as! NSMutableURLRequest
    }
  }

  public var url: URL? {
    get { return _handle.url }
    set { _unique(); _handle.url = newValue }
  }
  public var cachePolicy: CachePolicy {
    get { return _handle.cachePolicy }
    set { _unique(); _handle.cachePolicy = newValue }
  }
  public var timeoutInterval: TimeInterval {
    get { return _handle.timeoutInterval }
    set { _unique(); _handle.timeoutInterval = newValue }
  }
  public var mainDocumentURL: URL? {
    get { return _handle.mainDocumentURL }
    set { _unique(); _handle.mainDocumentURL = newValue }
  }
  public var networkServiceType: NetworkServiceType {
    get { return _handle.networkServiceType }
    set { _unique(); _handle.networkServiceType = newValue }
  }
  public var allowsCellularAccess: Bool {
    get { return _handle.allowsCellularAccess }
    set { _unique(); _handle.allowsCellularAccess = newValue }
  }
  public var allowsExpensiveNetworkAccess: Bool {
    get { return _handle.allowsExpensiveNetworkAccess }
    set { _unique(); _handle.allowsExpensiveNetworkAccess = newValue }
  }
  public var allowsConstrainedNetworkAccess: Bool {
    get { return _handle.allowsConstrainedNetworkAccess }
    set { _unique(); _handle.allowsConstrainedNetworkAccess = newValue }
  }
  public var assumesHTTP3Capable: Bool {
    get { return _handle.assumesHTTP3Capable }
    set { _unique(); _handle.assumesHTTP3Capable = newValue }
  }
  public var attribution: Attribution {
    get { return _handle.attribution }
    set { _unique(); _handle.attribution = newValue }
  }
  public var requiresDNSSECValidation: Bool {
    get { return _handle.requiresDNSSECValidation }
    set { _unique(); _handle.requiresDNSSECValidation = newValue }
  }
  public var httpMethod: String? {
    get { return _handle.httpMethod }
    set { _unique(); _handle.httpMethod = newValue ?? "GET" }
  }
  public var allHTTPHeaderFields: [String: String]? {
    get { return _handle.allHTTPHeaderFields }
    set { _unique(); _handle.allHTTPHeaderFields = newValue }
  }
  public func value(forHTTPHeaderField field: String) -> String? {
    return _handle.value(forHTTPHeaderField: field)
  }
  public mutating func setValue(_ value: String?, forHTTPHeaderField field: String) {
    _unique()
    _handle.setValue(value, forHTTPHeaderField: field)
  }
  public mutating func addValue(_ value: String, forHTTPHeaderField field: String) {
    _unique()
    _handle.addValue(value, forHTTPHeaderField: field)
  }
  public var httpBody: Data? {
    get { return _handle.httpBody }
    set { _unique(); _handle.httpBody = newValue }
  }
  public var httpShouldHandleCookies: Bool {
    get { return _handle.httpShouldHandleCookies }
    set { _unique(); _handle.httpShouldHandleCookies = newValue }
  }
  public var httpShouldUsePipelining: Bool {
    get { return _handle.httpShouldUsePipelining }
    set { _unique(); _handle.httpShouldUsePipelining = newValue }
  }

  public static func == (lhs: URLRequest, rhs: URLRequest) -> Bool {
    return lhs._handle.isEqual(rhs._handle)
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(_handle.hash)
  }
  public var description: String { return url?.description ?? "url: nil" }
  public var debugDescription: String { return description }
}

extension URLRequest: _ObjectiveCBridgeable {
  public typealias _ObjectiveCType = NSURLRequest
  public func _bridgeToObjectiveC() -> NSURLRequest { return _handle.copy() as! NSURLRequest }
  public static func _forceBridgeFromObjectiveC(_ source: NSURLRequest, result: inout URLRequest?) {
    result = URLRequest(_bridged: source)
  }
  @discardableResult
  public static func _conditionallyBridgeFromObjectiveC(_ source: NSURLRequest, result: inout URLRequest?) -> Bool {
    result = URLRequest(_bridged: source)
    return true
  }
  public static func _unconditionallyBridgeFromObjectiveC(_ source: NSURLRequest?) -> URLRequest {
    guard let source = source else { return URLRequest(_bridged: NSURLRequest()) }
    return URLRequest(_bridged: source)
  }
}

// MARK: - WebSockets

extension URLSessionWebSocketTask {
  public enum Message: @unchecked Sendable {
    case data(Data)
    case string(String)
  }

  public func send(_ message: Message, completionHandler: @escaping (Error?) -> Void) {
    let m: __NSURLSessionWebSocketMessage
    switch message {
    case .data(let d): m = __NSURLSessionWebSocketMessage(data: d)
    case .string(let s): m = __NSURLSessionWebSocketMessage(string: s)
    }
    __send(m, completionHandler: completionHandler)
  }

  public func receive(completionHandler: @escaping (Result<Message, Error>) -> Void) {
    __receiveMessage { message, error in
      if let message = message {
        if message.type == .string { completionHandler(.success(.string(message.string ?? ""))) }
        else { completionHandler(.success(.data(message.data ?? Data()))) }
      } else {
        completionHandler(.failure(error ?? URLError(.unknown)))
      }
    }
  }

  public func send(_ message: Message) async throws {
    try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
      send(message) { error in
        if let error = error { c.resume(throwing: error) } else { c.resume() }
      }
    }
  }

  public func receive() async throws -> Message {
    return try await withCheckedThrowingContinuation { (c: CheckedContinuation<Message, Error>) in
      receive { c.resume(with: $0) }
    }
  }

  public func sendPing() async throws {
    try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
      sendPing { error in
        if let error = error { c.resume(throwing: error) } else { c.resume() }
      }
    }
  }
}

// MARK: - Metrics

extension URLSessionTaskTransactionMetrics {
  public var negotiatedTLSProtocolVersion: tls_protocol_version_t? {
    return __negotiatedTLSProtocolVersion.map { tls_protocol_version_t(rawValue: UInt16(truncatingIfNeeded: $0.intValue)) }
  }
  public var negotiatedTLSCipherSuite: tls_ciphersuite_t? {
    return __negotiatedTLSCipherSuite.map { tls_ciphersuite_t(rawValue: UInt16(truncatingIfNeeded: $0.intValue)) }
  }
  public var localPort: Int? { return __localPort.map { $0.integerValue } }
  public var remotePort: Int? { return __remotePort.map { $0.integerValue } }
}

// MARK: - Async

private final class _TaskBox: @unchecked Sendable {
  var task: URLSessionTask?
  init() {}
}

extension URLSession {
  private func _run<T>(_ make: (@escaping (T?, URLResponse?, Error?) -> Void) -> URLSessionTask,
                       delegate: (any URLSessionTaskDelegate)?) async throws -> (T, URLResponse) {
    let box = _TaskBox()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (c: CheckedContinuation<(T, URLResponse), Error>) in
        let task = make { value, response, error in
          if let error = error { c.resume(throwing: error) }
          else if let value = value, let response = response { c.resume(returning: (value, response)) }
          else { c.resume(throwing: URLError(.badServerResponse)) }
        }
        task.delegate = delegate
        box.task = task
        task.resume()
      }
    } onCancel: {
      box.task?.cancel()
    }
  }

  public func data(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
    return try await _run({ done in self.dataTask(with: request) { d, r, e in done(d, r, e) } }, delegate: delegate)
  }
  public func data(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
    return try await _run({ done in self.dataTask(with: url) { d, r, e in done(d, r, e) } }, delegate: delegate)
  }
  public func upload(for request: URLRequest, from bodyData: Data,
                     delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
    return try await _run({ done in self.uploadTask(with: request, from: bodyData) { d, r, e in done(d, r, e) } },
                          delegate: delegate)
  }
  public func upload(for request: URLRequest, fromFile fileURL: URL,
                     delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
    return try await _run({ done in self.uploadTask(with: request, fromFile: fileURL) { d, r, e in done(d, r, e) } },
                          delegate: delegate)
  }

  /// The file is moved somewhere that outlives the call, as Apple's does.
  private func _keep(_ location: URL?) -> URL? {
    guard let location = location else { return nil }
    let kept = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CFNetworkDownload_" + UUID().uuidString + ".tmp")
    do { try FileManager.default.moveItem(at: location, to: kept) } catch { return nil }
    return kept
  }
  public func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
    return try await _run({ done in
      self.downloadTask(with: request) { l, r, e in done(self._keep(l), r, e) }
    }, delegate: delegate)
  }
  public func download(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
    return try await _run({ done in
      self.downloadTask(with: url) { l, r, e in done(self._keep(l), r, e) }
    }, delegate: delegate)
  }
}
