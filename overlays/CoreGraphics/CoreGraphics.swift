// The Swift overlay of CoreGraphics. The importer maps the C typedef
// `CGFloat` to the Swift type `CGFloat` found in this module; it is defined
// in the CoreFoundation overlay (where current macOS keeps it, under its
// original mangled module CoreGraphics) and re-exported here.
@_exported import CoreGraphics
@_exported import CoreFoundation
