// CoreAudio's buffer-list pointer, Accessibility announcements, and the
// Secure Enclave that is not there.
import Foundation
import CoreAudio
import Accessibility
import CryptoKit
import Security
import Symbols

@_silgen_name("swl_small_coreaudio") public func coreaudio() -> Int {
  var bad = 0
  let list = UnsafeMutableAudioBufferListPointer.allocate(maximumBuffers: 3)
  if list.count != 3 { bad |= 1 }
  let data = UnsafeMutablePointer<Float>.allocate(capacity: 4)
  for i in 0..<3 { list[i] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(4 * i), mData: UnsafeMutableRawPointer(data)) }
  if list[2].mDataByteSize != 8 || list[0].mNumberChannels != 1 { bad |= 2 }
  if list.map({ $0.mDataByteSize }) != [0, 4, 8] { bad |= 4 }
  if list.unsafePointer.pointee.mNumberBuffers != 3 { bad |= 8 }
  list.count = 2
  if list.count != 2 || UnsafeMutableAudioBufferListPointer(nil as UnsafeMutablePointer<AudioBufferList>?) != nil { bad |= 0x10 }
  return bad
}

@_silgen_name("swl_small_other") public func other() -> Int {
  var bad = 0
  AccessibilityNotification.Announcement("Saved").post()
  if AccessibilityNotification.Announcement("Saved").text != "Saved" { bad |= 1 }
  if SecureEnclave.isAvailable { bad |= 2 }
  if (try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: Data([1, 2, 3]))) != nil { bad |= 4 }
  let effect = VariableColorSymbolEffect().iterative.reversing
  if effect.configuration.name != "variableColor" || effect.configuration.options != ["iterative", "reversing"] { bad |= 8 }
  if ReplaceSymbolEffect().configuration.name != "replace" || SymbolEffectOptions.default.repeats { bad |= 0x10 }
  if SymbolEffectOptions.default.speed(2).speed != 2 { bad |= 0x20 }
  return bad
}
