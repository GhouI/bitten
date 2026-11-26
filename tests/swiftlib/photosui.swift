// PhotosUI: configuration, filters, results, and a picker that finishes
// with nothing once it appears (there is no photo library here).
import AppKit
import Foundation
import PhotosUI

final class Catcher: PHPickerViewControllerDelegate {
  var calls = 0
  var last: [PHPickerResult]? = nil
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    calls += 1
    last = results
  }
}

@_silgen_name("swl_photosui") public func photosui() -> Int {
  var bad = 0
  var config = PHPickerConfiguration()
  if config.selectionLimit != 1 || config.filter != nil { bad |= 1 }
  config.filter = .images
  config.selectionLimit = 0
  config.preferredAssetRepresentationMode = .compatible
  if config.filter != .images || config.filter == .videos { bad |= 2 }
  let picker = PHPickerViewController(configuration: config)
  let catcher = Catcher()
  picker.delegate = catcher
  if picker.delegate !== catcher { bad |= 4 }
  picker.viewDidAppear()
  picker.viewDidAppear()                       // reports once
  for _ in 0..<50 where catcher.calls == 0 {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
  }
  RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
  if catcher.calls != 1 || catcher.last?.isEmpty != true { bad |= 8 }
  let result = PHPickerResult(itemProvider: NSItemProvider(), assetIdentifier: "x")
  if result.assetIdentifier != "x" { bad |= 0x10 }
  return bad
}
