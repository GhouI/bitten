// URL resource values: file properties read with stat(2), as
// URL.resourceValues(forKeys:) returns them.

public struct URLResourceValues {
  internal var _values: [URLResourceKey: Any] = [:]
  internal var _keysToSet: Set<URLResourceKey> = []

  public init() {}
  internal init(_values: [URLResourceKey: Any]) { self._values = _values }

  public var allValues: [URLResourceKey: Any] { return _values }

  internal func _get<T>(_ key: URLResourceKey) -> T? { return _values[key] as? T }
  internal mutating func _set(_ key: URLResourceKey, _ value: Any?) {
    _keysToSet.insert(key)
    _values[key] = value
  }

  public var name: String? {
    get { return _get(.nameKey) }
    set { _set(.nameKey, newValue) }
  }
  public var localizedName: String? { return _get(.localizedNameKey) }
  public var path: String? { return _get(.pathKey) }
  public var isRegularFile: Bool? { return _get(.isRegularFileKey) }
  public var isDirectory: Bool? { return _get(.isDirectoryKey) }
  public var isSymbolicLink: Bool? { return _get(.isSymbolicLinkKey) }
  public var isVolume: Bool? { return _get(.isVolumeKey) }
  public var isPackage: Bool? { return _get(.isPackageKey) }
  public var isApplication: Bool? { return _get(.isApplicationKey) }
  public var isHidden: Bool? {
    get { return _get(.isHiddenKey) }
    set { _set(.isHiddenKey, newValue) }
  }
  public var isReadable: Bool? { return _get(.isReadableKey) }
  public var isWritable: Bool? { return _get(.isWritableKey) }
  public var isExecutable: Bool? { return _get(.isExecutableKey) }
  public var creationDate: Date? {
    get { return _get(.creationDateKey) }
    set { _set(.creationDateKey, newValue) }
  }
  public var contentAccessDate: Date? {
    get { return _get(.contentAccessDateKey) }
    set { _set(.contentAccessDateKey, newValue) }
  }
  public var contentModificationDate: Date? {
    get { return _get(.contentModificationDateKey) }
    set { _set(.contentModificationDateKey, newValue) }
  }
  public var attributeModificationDate: Date? { return _get(.attributeModificationDateKey) }
  public var addedToDirectoryDate: Date? { return _get(.addedToDirectoryDateKey) }
  public var fileSize: Int? { return _get(.fileSizeKey) }
  public var fileAllocatedSize: Int? { return _get(.fileAllocatedSizeKey) }
  public var totalFileSize: Int? { return _get(.totalFileSizeKey) }
  public var totalFileAllocatedSize: Int? { return _get(.totalFileAllocatedSizeKey) }
  public var linkCount: Int? { return _get(.linkCountKey) }
  public var parentDirectory: URL? { return _get(.parentDirectoryURLKey) }
  public var typeIdentifier: String? { return _get(.typeIdentifierKey) }
  public var volumeAvailableCapacity: Int? { return _get(.volumeAvailableCapacityKey) }
  public var volumeTotalCapacity: Int? { return _get(.volumeTotalCapacityKey) }
  public var isUbiquitousItem: Bool? { return _get(.isUbiquitousItemKey) }
  public var isExcludedFromBackup: Bool? {
    get { return _get(.isExcludedFromBackupKey) }
    set { _set(.isExcludedFromBackupKey, newValue) }
  }
  public var quarantineProperties: [String: Any]? {
    get { return _get(.quarantinePropertiesKey) }
    set { _set(.quarantinePropertiesKey, newValue) }
  }
}

/// Directory extensions Finder shows as single items.
internal let _packageExtensions: Set<String> = ["app", "bundle", "framework", "plugin", "kext", "rtfd", "pages",
                                                "numbers", "key", "xcodeproj", "xcworkspace", "playground", "photoslibrary"]

extension URL {
  public func resourceValues(forKeys keys: Set<URLResourceKey>) throws -> URLResourceValues {
    guard isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
    let p = path
    var st = stat()
    let found = p.withCString { lstat($0, &st) } == 0
    guard found else {
      throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: p])
    }
    var target = st
    let isLink = (st.st_mode & S_IFMT) == S_IFLNK
    if isLink { _ = p.withCString { stat($0, &target) } }
    let isDir = (target.st_mode & S_IFMT) == S_IFDIR
    func date(_ t: timespec) -> Date {
      return Date(timeIntervalSince1970: Double(t.tv_sec) + Double(t.tv_nsec) / 1e9)
    }
    var v: [URLResourceKey: Any] = [:]
    for key in keys {
      switch key {
      case .nameKey, .localizedNameKey: v[key] = lastPathComponent
      case .pathKey: v[key] = p
      case .isRegularFileKey: v[key] = (target.st_mode & S_IFMT) == S_IFREG
      case .isDirectoryKey: v[key] = isDir
      case .isSymbolicLinkKey: v[key] = isLink
      case .isVolumeKey: v[key] = p == "/"
      case .isPackageKey: v[key] = isDir && _packageExtensions.contains(pathExtension.lowercased())
      case .isApplicationKey: v[key] = isDir && pathExtension.lowercased() == "app"
      case .isHiddenKey: v[key] = lastPathComponent.hasPrefix(".")
      case .isReadableKey: v[key] = p.withCString { access($0, R_OK) } == 0
      case .isWritableKey: v[key] = p.withCString { access($0, W_OK) } == 0
      case .isExecutableKey: v[key] = p.withCString { access($0, X_OK) } == 0
      case .creationDateKey: v[key] = date(target.st_birthtimespec)
      case .contentAccessDateKey: v[key] = date(target.st_atimespec)
      case .contentModificationDateKey: v[key] = date(target.st_mtimespec)
      case .attributeModificationDateKey: v[key] = date(target.st_ctimespec)
      case .fileSizeKey, .totalFileSizeKey: if !isDir { v[key] = Int(target.st_size) }
      case .fileAllocatedSizeKey, .totalFileAllocatedSizeKey: if !isDir { v[key] = Int(target.st_blocks) * 512 }
      case .linkCountKey: v[key] = Int(target.st_nlink)
      case .parentDirectoryURLKey: v[key] = deletingLastPathComponent()
      case .isExcludedFromBackupKey, .isUbiquitousItemKey: v[key] = false
      case .volumeAvailableCapacityKey, .volumeTotalCapacityKey:
        var fs = statfs()
        if p.withCString({ statfs($0, &fs) }) == 0 {
          let block = Int(fs.f_bsize)
          v[key] = key == .volumeAvailableCapacityKey ? Int(fs.f_bavail) * block : Int(fs.f_blocks) * block
        }
      default: break
      }
    }
    return URLResourceValues(_values: v)
  }

  public mutating func setResourceValues(_ values: URLResourceValues) throws {
    guard isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
    let p = path
    for key in values._keysToSet {
      switch key {
      case .contentModificationDateKey, .contentAccessDateKey:
        // Dates are set with utimes(2); the others keep their value.
        if let d = values._values[key] as? Date {
          var times = [timeval(), timeval()]
          var st = stat()
          _ = p.withCString { stat($0, &st) }
          times[0] = timeval(tv_sec: st.st_atimespec.tv_sec, tv_usec: Int32(st.st_atimespec.tv_nsec / 1000))
          times[1] = timeval(tv_sec: st.st_mtimespec.tv_sec, tv_usec: Int32(st.st_mtimespec.tv_nsec / 1000))
          let t = timeval(tv_sec: Int(d.timeIntervalSince1970), tv_usec: 0)
          if key == .contentModificationDateKey { times[1] = t } else { times[0] = t }
          _ = p.withCString { utimes($0, &times) }
        }
      default:
        break // backup exclusion, quarantine, hidden: nothing to record here
      }
    }
  }

  public mutating func removeAllCachedResourceValues() {}
  public mutating func removeCachedResourceValue(forKey key: URLResourceKey) {}
  public func checkResourceIsReachable() throws -> Bool {
    guard isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
    var st = stat()
    if path.withCString({ stat($0, &st) }) != 0 { throw CocoaError(.fileReadNoSuchFile) }
    return true
  }
}
