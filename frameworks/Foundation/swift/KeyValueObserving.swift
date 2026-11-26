// Key-value observing from Swift: `object.observe(\.property) { ... }`
// over Foundation's KVO, with the change decoded into Swift values.

public protocol _KeyValueCodingAndObserving {}
extension NSObject: _KeyValueCodingAndObserving {}

public struct NSKeyValueObservedChange<Value> {
  public typealias Kind = NSKeyValueChange
  public let kind: Kind
  public let newValue: Value?
  public let oldValue: Value?
  public let indexes: IndexSet?
  public let isPrior: Bool
}

/// An observation in progress; it ends when invalidated or released.
public class NSKeyValueObservation: NSObject {
  weak var object: NSObject?
  let keyPath: String
  let callback: (NSObject, [NSKeyValueChangeKey: Any]) -> Void
  var observing = false

  init(object: NSObject, keyPath: String, callback: @escaping (NSObject, [NSKeyValueChangeKey: Any]) -> Void) {
    self.object = object
    self.keyPath = keyPath
    self.callback = callback
    super.init()
  }
  func start(_ options: NSKeyValueObservingOptions) {
    observing = true
    object?.addObserver(self, forKeyPath: keyPath, options: options, context: nil)
  }
  public override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                    change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    guard let o = object as? NSObject else { return }
    callback(o, change ?? [:])
  }
  @objc public func invalidate() {
    if observing, let o = object { o.removeObserver(self, forKeyPath: keyPath, context: nil) }
    observing = false
  }
  deinit { invalidate() }
}

extension _KeyValueCodingAndObserving {
  public func observe<Value>(_ keyPath: KeyPath<Self, Value>, options: NSKeyValueObservingOptions = [],
                             changeHandler: @escaping (Self, NSKeyValueObservedChange<Value>) -> Void)
    -> NSKeyValueObservation {
    let object = self as! NSObject
    guard let path = keyPath._kvcKeyPathString else {
      fatalError("observe(_:) needs a key path of @objc properties, not \(keyPath)")
    }
    let observation = NSKeyValueObservation(object: object, keyPath: path) { o, change in
      let raw = UInt((change[.kindKey] as? NSNumber)?.unsignedIntegerValue ?? 1)
      let decoded = NSKeyValueObservedChange<Value>(
        kind: NSKeyValueChange(rawValue: raw) ?? .setting,
        newValue: change[.newKey].flatMap { $0 is NSNull ? nil : $0 as? Value },
        oldValue: change[.oldKey].flatMap { $0 is NSNull ? nil : $0 as? Value },
        indexes: nil,
        isPrior: (change[.notificationIsPriorKey] as? NSNumber)?.boolValue ?? false)
      changeHandler(o as! Self, decoded)
    }
    observation.start(options)
    return observation
  }
}
