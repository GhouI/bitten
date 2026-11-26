// Casts between collections of different element types ([String: Any] as
// [AnyHashable: Any], [Any] as! [Int], ...). The compiler calls these by
// name, with these generic signatures, for `as`, `as?` and `as!`.

@inlinable
public func _arrayForceCast<SourceElement, TargetElement>(_ source: Array<SourceElement>) -> Array<TargetElement> {
  var result = ContiguousArray<TargetElement>()
  result.reserveCapacity(source.count)
  for e in source { result.append(e as! TargetElement) }
  return Array(result)
}

@inlinable
public func _arrayConditionalCast<SourceElement, TargetElement>(_ source: [SourceElement]) -> [TargetElement]? {
  var result = ContiguousArray<TargetElement>()
  result.reserveCapacity(source.count)
  for e in source {
    guard let t = e as? TargetElement else { return nil }
    result.append(t)
  }
  return Array(result)
}

@inlinable
public func _dictionaryUpCast<DerivedKey, DerivedValue, BaseKey, BaseValue>(
  _ source: Dictionary<DerivedKey, DerivedValue>
) -> Dictionary<BaseKey, BaseValue> {
  var result = Dictionary<BaseKey, BaseValue>(minimumCapacity: source.count)
  for (k, v) in source { result[k as! BaseKey] = (v as! BaseValue) }
  return result
}

@inlinable
public func _dictionaryDownCast<BaseKey, BaseValue, DerivedKey, DerivedValue>(
  _ source: Dictionary<BaseKey, BaseValue>
) -> Dictionary<DerivedKey, DerivedValue> {
  var result = Dictionary<DerivedKey, DerivedValue>(minimumCapacity: source.count)
  for (k, v) in source { result[k as! DerivedKey] = (v as! DerivedValue) }
  return result
}

@inlinable
public func _dictionaryDownCastConditional<BaseKey, BaseValue, DerivedKey, DerivedValue>(
  _ source: Dictionary<BaseKey, BaseValue>
) -> Dictionary<DerivedKey, DerivedValue>? {
  var result = Dictionary<DerivedKey, DerivedValue>(minimumCapacity: source.count)
  for (k, v) in source {
    guard let key = k as? DerivedKey, let value = v as? DerivedValue else { return nil }
    result[key] = value
  }
  return result
}

@inlinable
public func _setUpCast<DerivedValue, BaseValue>(_ source: Set<DerivedValue>) -> Set<BaseValue> {
  var result = Set<BaseValue>(minimumCapacity: source.count)
  for e in source { result.insert(e as! BaseValue) }
  return result
}

@inlinable
public func _setDownCast<BaseValue, DerivedValue>(_ source: Set<BaseValue>) -> Set<DerivedValue> {
  var result = Set<DerivedValue>(minimumCapacity: source.count)
  for e in source { result.insert(e as! DerivedValue) }
  return result
}

@inlinable
public func _setDownCastConditional<BaseValue, DerivedValue>(_ source: Set<BaseValue>) -> Set<DerivedValue>? {
  var result = Set<DerivedValue>(minimumCapacity: source.count)
  for e in source {
    guard let d = e as? DerivedValue else { return nil }
    result.insert(d)
  }
  return result
}
