// PhotosUI's Swift API: the picker's configuration, filters and results,
// and its delegate. There is no photo library: a picker that appears
// finishes with no results.
@_exported import PhotosUI
import Foundation

public struct PHPickerFilter: Equatable, Hashable, Sendable {
  internal let kinds: [String]
  public static var images: PHPickerFilter { return PHPickerFilter(kinds: ["images"]) }
  public static var videos: PHPickerFilter { return PHPickerFilter(kinds: ["videos"]) }
  public static var livePhotos: PHPickerFilter { return PHPickerFilter(kinds: ["livePhotos"]) }
  public static func any(of filters: [PHPickerFilter]) -> PHPickerFilter {
    return PHPickerFilter(kinds: filters.flatMap { $0.kinds })
  }
}

public struct PHPickerConfiguration: Equatable, Hashable, Sendable {
  public enum AssetRepresentationMode: Int, Hashable, Sendable { case automatic, current, compatible }
  public enum Selection: Int, Hashable, Sendable { case `default`, ordered, continuous }
  public var filter: PHPickerFilter?
  public var selectionLimit: Int
  public var preferredAssetRepresentationMode: AssetRepresentationMode
  public var selection: Selection
  public init() {
    filter = nil
    selectionLimit = 1
    preferredAssetRepresentationMode = .automatic
    selection = .default
  }
}

public struct PHPickerResult: Equatable, Hashable {
  public let itemProvider: NSItemProvider
  public let assetIdentifier: String?
  public init(itemProvider: NSItemProvider, assetIdentifier: String? = nil) {
    self.itemProvider = itemProvider
    self.assetIdentifier = assetIdentifier
  }
}

public protocol PHPickerViewControllerDelegate: AnyObject {
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult])
}

extension PHPickerViewController {
  public convenience init(configuration: PHPickerConfiguration) {
    self.init(nibName: nil, bundle: nil)
    _bn_onAppear = { [weak self] in
      guard let self = self else { return }
      self.delegate?.picker(self, didFinishPicking: [])
    }
  }

  public var delegate: PHPickerViewControllerDelegate? {
    get { return _bn_delegate as? PHPickerViewControllerDelegate }
    set { _bn_delegate = newValue }
  }
}
