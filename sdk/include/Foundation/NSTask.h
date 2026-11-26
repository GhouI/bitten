/* bitten SDK: processes, pipes and file handles (NSTask, NSPipe,
 * NSFileHandle). Included from Foundation.h. */
#ifndef BITTEN_FOUNDATION_NSTASK_H
#define BITTEN_FOUNDATION_NSTASK_H

#pragma clang assume_nonnull begin

@class NSPipe;

extern NSNotificationName const NSFileHandleReadCompletionNotification;
extern NSNotificationName const NSFileHandleReadToEndOfFileCompletionNotification;
extern NSNotificationName const NSFileHandleConnectionAcceptedNotification;
extern NSNotificationName const NSFileHandleDataAvailableNotification;
extern NSString *const NSFileHandleNotificationDataItem;
extern NSString *const NSFileHandleNotificationFileHandleItem;
extern NSString *const NSFileHandleOperationException;

NS_SWIFT_NAME(FileHandle)
@interface NSFileHandle : NSObject
@property (readonly, copy) NSData *availableData;
- (instancetype)initWithFileDescriptor:(int)fd closeOnDealloc:(BOOL)closeopt;
- (instancetype)initWithFileDescriptor:(int)fd;
@property (readonly) int fileDescriptor;

@property (class, readonly, strong) NSFileHandle *fileHandleWithStandardInput NS_SWIFT_NAME(standardInput);
@property (class, readonly, strong) NSFileHandle *fileHandleWithStandardOutput NS_SWIFT_NAME(standardOutput);
@property (class, readonly, strong) NSFileHandle *fileHandleWithStandardError NS_SWIFT_NAME(standardError);
@property (class, readonly, strong) NSFileHandle *fileHandleWithNullDevice NS_SWIFT_NAME(nullDevice);
+ (nullable instancetype)fileHandleForReadingAtPath:(NSString *)path NS_SWIFT_NAME(init(forReadingAtPath:));
+ (nullable instancetype)fileHandleForWritingAtPath:(NSString *)path NS_SWIFT_NAME(init(forWritingAtPath:));
+ (nullable instancetype)fileHandleForUpdatingAtPath:(NSString *)path NS_SWIFT_NAME(init(forUpdatingAtPath:));
+ (nullable instancetype)fileHandleForReadingFromURL:(NSURL *)url error:(NSError *_Nullable *_Nullable)error
    NS_SWIFT_NAME(init(forReadingFrom:));
+ (nullable instancetype)fileHandleForWritingToURL:(NSURL *)url error:(NSError *_Nullable *_Nullable)error
    NS_SWIFT_NAME(init(forWritingTo:));
+ (nullable instancetype)fileHandleForUpdatingURL:(NSURL *)url error:(NSError *_Nullable *_Nullable)error
    NS_SWIFT_NAME(init(forUpdating:));

- (nullable NSData *)readDataToEndOfFileAndReturnError:(NSError *_Nullable *_Nullable)error NS_REFINED_FOR_SWIFT;
- (nullable NSData *)readDataUpToLength:(NSUInteger)length error:(NSError *_Nullable *_Nullable)error NS_REFINED_FOR_SWIFT;
- (BOOL)writeData:(NSData *)data error:(NSError *_Nullable *_Nullable)error NS_REFINED_FOR_SWIFT;
- (BOOL)getOffset:(unsigned long long *)offsetInFile error:(NSError *_Nullable *_Nullable)error NS_REFINED_FOR_SWIFT;
- (BOOL)seekToEndReturningOffset:(unsigned long long *_Nullable)offsetInFile error:(NSError *_Nullable *_Nullable)error NS_REFINED_FOR_SWIFT;
- (BOOL)seekToOffset:(unsigned long long)offset error:(NSError *_Nullable *_Nullable)error;
- (BOOL)truncateAtOffset:(unsigned long long)offset error:(NSError *_Nullable *_Nullable)error;
- (BOOL)synchronizeAndReturnError:(NSError *_Nullable *_Nullable)error;
- (BOOL)closeAndReturnError:(NSError *_Nullable *_Nullable)error;

- (NSData *)readDataToEndOfFile;
- (NSData *)readDataOfLength:(NSUInteger)length;
- (void)writeData:(NSData *)data;
@property (readonly) unsigned long long offsetInFile;
- (unsigned long long)seekToEndOfFile;
- (void)seekToFileOffset:(unsigned long long)offset;
- (void)truncateFileAtOffset:(unsigned long long)offset;
- (void)synchronizeFile;
- (void)closeFile;

@property (nullable, copy) void (^readabilityHandler)(NSFileHandle *);
@property (nullable, copy) void (^writeabilityHandler)(NSFileHandle *);
- (void)readInBackgroundAndNotifyForModes:(nullable NSArray<NSRunLoopMode> *)modes;
- (void)readInBackgroundAndNotify;
- (void)readToEndOfFileInBackgroundAndNotifyForModes:(nullable NSArray<NSRunLoopMode> *)modes;
- (void)readToEndOfFileInBackgroundAndNotify;
- (void)waitForDataInBackgroundAndNotifyForModes:(nullable NSArray<NSRunLoopMode> *)modes;
- (void)waitForDataInBackgroundAndNotify;
@end

NS_SWIFT_NAME(Pipe)
@interface NSPipe : NSObject
@property (readonly, retain) NSFileHandle *fileHandleForReading;
@property (readonly, retain) NSFileHandle *fileHandleForWriting;
+ (NSPipe *)pipe;
@end

typedef NS_ENUM(NSInteger, NSTaskTerminationReason) {
    NSTaskTerminationReasonExit = 1,
    NSTaskTerminationReasonUncaughtSignal = 2,
} NS_SWIFT_NAME(Process.TerminationReason);

extern NSNotificationName const NSTaskDidTerminateNotification;

NS_SWIFT_NAME(Process)
@interface NSTask : NSObject
- (instancetype)init;
@property (nullable, copy) NSURL *executableURL;
@property (nullable, copy) NSArray<NSString *> *arguments;
@property (nullable, copy) NSDictionary<NSString *, NSString *> *environment;
@property (nullable, copy) NSURL *currentDirectoryURL;
@property (nullable, retain) id standardInput;
@property (nullable, retain) id standardOutput;
@property (nullable, retain) id standardError;
- (BOOL)launchAndReturnError:(out NSError **_Nullable)error NS_SWIFT_NAME(run());
- (void)interrupt;
- (void)terminate;
- (BOOL)suspend;
- (BOOL)resume;
@property (readonly) int processIdentifier;
@property (readonly, getter=isRunning) BOOL running;
@property (readonly) int terminationStatus;
@property (readonly) NSTaskTerminationReason terminationReason;
@property (nullable, copy) void (^terminationHandler)(NSTask *);
@property NSQualityOfService qualityOfService;
+ (nullable NSTask *)launchedTaskWithExecutableURL:(NSURL *)url arguments:(NSArray<NSString *> *)arguments
                                             error:(out NSError **_Nullable)error
                                terminationHandler:(void (^_Nullable)(NSTask *))terminationHandler
    NS_SWIFT_NAME(run(_:arguments:terminationHandler:));
- (void)waitUntilExit;

@property (nullable, copy) NSString *launchPath;
@property (copy) NSString *currentDirectoryPath;
- (void)launch;
+ (NSTask *)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray<NSString *> *)arguments;
@end

#pragma clang assume_nonnull end
#endif
