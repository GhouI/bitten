// The Swift overlay of CoreAudio: a buffer list as a collection of its
// buffers (Apple's UnsafeMutableAudioBufferListPointer).
@_exported import CoreAudio

public struct UnsafeMutableAudioBufferListPointer {
  public var unsafeMutablePointer: UnsafeMutablePointer<AudioBufferList>

  public init(_ p: UnsafeMutablePointer<AudioBufferList>) { unsafeMutablePointer = p }
  public init?(_ p: UnsafeMutablePointer<AudioBufferList>?) {
    guard let p = p else { return nil }
    unsafeMutablePointer = p
  }

  /// A list with room for this many buffers (free it with free()).
  public static func allocate(maximumBuffers: Int) -> UnsafeMutableAudioBufferListPointer {
    let bytes = MemoryLayout<AudioBufferList>.size + Swift.max(maximumBuffers - 1, 0) * MemoryLayout<AudioBuffer>.stride
    let raw = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: MemoryLayout<AudioBufferList>.alignment)
    let p = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
    p.pointee.mNumberBuffers = UInt32(maximumBuffers)
    return UnsafeMutableAudioBufferListPointer(p)
  }

  public var unsafePointer: UnsafePointer<AudioBufferList> { return UnsafePointer(unsafeMutablePointer) }

  public var count: Int {
    get { return Int(unsafeMutablePointer.pointee.mNumberBuffers) }
    nonmutating set { unsafeMutablePointer.pointee.mNumberBuffers = UInt32(newValue) }
  }

  internal var _buffers: UnsafeMutablePointer<AudioBuffer> {
    // mBuffers is the list's last field: the list's size less one buffer.
    let offset = MemoryLayout<AudioBufferList>.size - MemoryLayout<AudioBuffer>.stride
    let raw = UnsafeMutableRawPointer(unsafeMutablePointer) + offset
    return raw.assumingMemoryBound(to: AudioBuffer.self)
  }
}

extension UnsafeMutableAudioBufferListPointer: MutableCollection, RandomAccessCollection {
  public typealias Index = Int
  public var startIndex: Int { return 0 }
  public var endIndex: Int { return count }
  public subscript(index: Int) -> AudioBuffer {
    _read { yield _buffers[index] }
    nonmutating _modify { yield &_buffers[index] }
  }
}
