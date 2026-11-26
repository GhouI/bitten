// FileHandle's throwing methods for Swift, over the Objective-C ones.

extension FileHandle {
  public func readToEnd() throws -> Data? {
    let d = try __readDataToEndOfFileAndReturnError()
    return d.isEmpty ? nil : d
  }
  public func read(upToCount count: Int) throws -> Data? {
    let d = try __readDataUp(toLength: count)
    return d.isEmpty ? nil : d
  }
  public func write<T: DataProtocol>(contentsOf data: T) throws {
    try __write(Data(data), error: ())
  }
  public func offset() throws -> UInt64 {
    var o: UInt64 = 0
    try __getOffset(&o)
    return o
  }
  @discardableResult
  public func seekToEnd() throws -> UInt64 {
    var o: UInt64 = 0
    try __seek(toEndReturningOffset: &o)
    return o
  }
}
