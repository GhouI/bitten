// UndoManager's generic registration for Swift.

extension UndoManager {
  public func registerUndo<TargetType: AnyObject>(withTarget target: TargetType,
                                                  handler: @escaping (TargetType) -> Void) {
    __registerUndo(withTarget: target) { t in handler(t as! TargetType) }
  }
}
