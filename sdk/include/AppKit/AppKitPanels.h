/* bitten SDK: AppKit panels (NSPanel) and the open and save panels. */
#ifndef BITTEN_APPKIT_PANELS_H
#define BITTEN_APPKIT_PANELS_H
#import <AppKit/AppKitCore.h>

#ifndef IBAction
#define IBAction void
#endif
#ifndef IBOutlet
#define IBOutlet
#endif

#pragma clang assume_nonnull begin

@interface NSPanel : NSWindow
@property (getter=isFloatingPanel) BOOL floatingPanel;
@property BOOL becomesKeyOnlyIfNeeded;
@property BOOL worksWhenModal;
@end

@class NSSavePanel;

@protocol NSOpenSavePanelDelegate <NSObject>
@optional
- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url;
- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)outError;
- (void)panel:(id)sender didChangeToDirectoryURL:(nullable NSURL *)url;
- (nullable NSString *)panel:(id)sender userEnteredFilename:(NSString *)filename confirmed:(BOOL)okFlag;
- (void)panel:(id)sender willExpand:(BOOL)expanding;
- (void)panelSelectionDidChange:(nullable id)sender;
@end

/* A panel browsing the file system for a place to save: a directory list,
 * a name field, and Cancel and Save. allowedContentTypes takes UTType
 * objects (or type identifier strings). */
@interface NSSavePanel : NSPanel
+ (NSSavePanel *)savePanel;
@property (nullable, readonly, copy) NSURL *URL;
@property (nullable, copy) NSURL *directoryURL;
@property (copy) NSArray *allowedContentTypes;
@property (nullable, copy) NSArray<NSString *> *allowedFileTypes;
@property BOOL allowsOtherFileTypes;
@property (nullable, strong) NSView *accessoryView;
@property (nullable, weak) id<NSOpenSavePanelDelegate> delegate;
@property (getter=isExpanded, readonly) BOOL expanded;
@property BOOL canCreateDirectories;
@property BOOL canSelectHiddenExtension;
@property (getter=isExtensionHidden) BOOL extensionHidden;
@property BOOL treatsFilePackagesAsDirectories;
@property (null_resettable, copy) NSString *prompt;
@property (null_resettable, copy) NSString *nameFieldLabel;
@property (copy) NSString *nameFieldStringValue;
@property (null_resettable, copy) NSString *message;
@property BOOL showsHiddenFiles;
@property BOOL showsTagField;
@property (nullable, copy) NSArray<NSString *> *tagNames;
@property BOOL showsContentTypes;
@property (nullable, copy) NSString *identifier;
- (void)validateVisibleColumns;
- (IBAction)ok:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse result))handler;
- (void)beginWithCompletionHandler:(void (^)(NSModalResponse result))handler;
- (NSModalResponse)runModal;
@end

/* A panel for choosing existing files or directories. */
@interface NSOpenPanel : NSSavePanel
+ (NSOpenPanel *)openPanel;
@property (readonly, copy) NSArray<NSURL *> *URLs;
@property BOOL resolvesAliases;
@property BOOL canChooseDirectories;
@property BOOL allowsMultipleSelection;
@property BOOL canChooseFiles;
@property BOOL canResolveUbiquitousConflicts;
@property BOOL canDownloadUbiquitousContents;
@property (getter=isAccessoryViewDisclosed) BOOL accessoryViewDisclosed;
@end

#pragma clang assume_nonnull end
#endif
