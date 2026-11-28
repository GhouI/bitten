// print and debugPrint, String(describing:) and String(reflecting:), and
// the generic "how is this value shown" logic they share with string
// interpolation.
//
// A value prints as: its TextOutputStreamable text, else its description,
// else its debugDescription, else a form made from its type. Optionals print
// through their debugDescription ("Optional(1)", "nil"). The last fallback
// lists a struct's stored properties ("Point(x: 1, y: 2)") and shows an
// enum's case with any payload ("dark", "some(3)").

public func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
  var output = _Stdout()
  _print(items, separator: separator, terminator: terminator, to: &output)
}

public func print<Target: TextOutputStream>(
  _ items: Any..., separator: String = " ", terminator: String = "\n", to output: inout Target
) {
  _print(items, separator: separator, terminator: terminator, to: &output)
}

public func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
  var output = _Stdout()
  _debugPrint(items, separator: separator, terminator: terminator, to: &output)
}

public func debugPrint<Target: TextOutputStream>(
  _ items: Any..., separator: String = " ", terminator: String = "\n", to output: inout Target
) {
  _debugPrint(items, separator: separator, terminator: terminator, to: &output)
}

@usableFromInline
internal func _print<Target: TextOutputStream>(
  _ items: [Any], separator: String = " ", terminator: String = "\n", to output: inout Target
) {
  var prefix = ""
  output._lock()
  defer { output._unlock() }
  for item in items {
    output.write(prefix)
    _print_unlocked(item, &output)
    prefix = separator
  }
  output.write(terminator)
}

@usableFromInline
internal func _debugPrint<Target: TextOutputStream>(
  _ items: [Any], separator: String = " ", terminator: String = "\n", to output: inout Target
) {
  var prefix = ""
  output._lock()
  defer { output._unlock() }
  for item in items {
    output.write(prefix)
    _debugPrint_unlocked(item, &output)
    prefix = separator
  }
  output.write(terminator)
}

/// Whether a metatype is Optional's (metadata kind 0x202).
internal func _isOptionalType(_ type: Any.Type) -> Bool {
  let p: Builtin.RawPointer = Builtin.reinterpretCast(type)
  let kind: Int = Builtin.load(p)
  return kind == 0x202
}

@usableFromInline
@_semantics("optimize.sil.specialize.generic.never")
internal func _print_unlocked<T, TargetStream: TextOutputStream>(
  _ value: T, _ target: inout TargetStream
) {
  if _isOptionalType(T.self) || _isOptionalType(type(of: value as Any)) {
    if case let d as CustomDebugStringConvertible = value {
      d.debugDescription.write(to: &target)
      return
    }
  }
  if case let s as TextOutputStreamable = value {
    s.write(to: &target)
    return
  }
  if case let p as CustomStringConvertible = value {
    p.description.write(to: &target)
    return
  }
  if case let d as CustomDebugStringConvertible = value {
    d.debugDescription.write(to: &target)
    return
  }
  _adHocPrint_unlocked(value, &target, isDebugPrint: false)
}

@_semantics("optimize.sil.specialize.generic.never")
public func _debugPrint_unlocked<T, TargetStream: TextOutputStream>(
  _ value: T, _ target: inout TargetStream
) {
  if case let d as CustomDebugStringConvertible = value {
    d.debugDescription.write(to: &target)
    return
  }
  if case let p as CustomStringConvertible = value {
    p.description.write(to: &target)
    return
  }
  if case let s as TextOutputStreamable = value {
    s.write(to: &target)
    return
  }
  _adHocPrint_unlocked(value, &target, isDebugPrint: true)
}

internal func _adHocPrint_unlocked<T, TargetStream: TextOutputStream>(
  _ value: T, _ target: inout TargetStream, isDebugPrint: Bool
) {
  let type = type(of: value as Any)
  let p: Builtin.RawPointer = Builtin.reinterpretCast(type)
  let kind: Int = Builtin.load(p)
  // A metatype prints the type it names (qualified for debugPrint).
  if kind == 0x304 || kind == 0x306, let named = value as? Any.Type {
    target.write(_typeName(named, qualified: isDebugPrint))
    return
  }
  // Classes (kind 0 is a Swift class's isa, > 0x7FF an ObjC class pointer)
  // show their qualified name.
  let isClass = kind == 0 || kind > 0x7FF || kind == 0x305
  if isClass {
    target.write(_typeName(type, qualified: true))
    return
  }
  // Structs and tuples show their stored properties; enums their case.
  let mirror = Mirror(reflecting: value)
  switch mirror.displayStyle {
  case .some(.struct), .some(.tuple):
    if mirror.displayStyle == .struct { target.write(_typeName(type, qualified: isDebugPrint)) }
    target.write("(")
    var first = true
    for child in mirror.children {
      if !first { target.write(", ") }
      first = false
      if let label = child.label, mirror.displayStyle == .struct || !label.isEmpty {
        target.write(label)
        target.write(": ")
      }
      _debugPrint_unlocked(child.value, &target)
    }
    target.write(")")
  case .some(.enum):
    // case, or case(payload) as Swift prints them
    guard let caseName = _enumCaseNameOf(value) else {
      target.write(_typeName(type, qualified: isDebugPrint))
      return
    }
    if isDebugPrint {
      target.write(_typeName(type, qualified: true))
      target.write(".")
    }
    target.write(caseName)
    if let payload = mirror.children.first {
      let tuple = Mirror(reflecting: payload.value).displayStyle == .tuple
      if !tuple { target.write("(") }
      _debugPrint_unlocked(payload.value, &target)
      if !tuple { target.write(")") }
    }
  default:
    target.write(_typeName(type, qualified: isDebugPrint))
  }
}

extension String {
  /// The text `print` shows for a value.
  public init<Subject>(describing instance: Subject) {
    self.init()
    _print_unlocked(instance, &self)
  }

  @inlinable
  public init<Subject: CustomStringConvertible>(describing instance: Subject) {
    self = instance.description
  }

  @inlinable
  public init<Subject: TextOutputStreamable>(describing instance: Subject) {
    self.init()
    instance.write(to: &self)
  }

  @inlinable
  public init<Subject>(describing instance: Subject)
  where Subject: CustomStringConvertible, Subject: TextOutputStreamable {
    self = instance.description
  }

  /// The text `debugPrint` shows for a value.
  public init<Subject>(reflecting subject: Subject) {
    self.init()
    _debugPrint_unlocked(subject, &self)
  }

  /// A value's description.
  @inlinable
  public init<T: LosslessStringConvertible>(_ value: T) {
    self = value.description
  }
}

/// The name of a type: "Int", "Swift.Int", "[Swift.String]", "Main.Point".
public func _typeName(_ type: Any.Type, qualified: Bool = true) -> String {
  let (name, length) = _bitten_getTypeName(Builtin.reinterpretCast(type), qualified)
  return String._uncheckedFromUTF8(
    UnsafeBufferPointer(start: UnsafePointer<UInt8>(name), count: length))
}
