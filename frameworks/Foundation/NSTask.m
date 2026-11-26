/* Processes, pipes and file handles. NSTask starts its program with
 * posix_spawn (which runs Mach-O programs under mrun and Linux ones
 * directly), wiring standard input, output and error to file handles or
 * pipes, and waits for it on a background queue; NSFileHandle wraps a
 * descriptor, with blocking reads and writes, the throwing variants, and
 * background reads (readability handlers on a dispatch source, and the
 * notification forms). */
#import <Foundation/Foundation.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

NSNotificationName const NSFileHandleReadCompletionNotification = @"NSFileHandleReadCompletionNotification";
NSNotificationName const NSFileHandleReadToEndOfFileCompletionNotification = @"NSFileHandleReadToEndOfFileCompletionNotification";
NSNotificationName const NSFileHandleConnectionAcceptedNotification = @"NSFileHandleConnectionAcceptedNotification";
NSNotificationName const NSFileHandleDataAvailableNotification = @"NSFileHandleDataAvailableNotification";
NSString *const NSFileHandleNotificationDataItem = @"NSFileHandleNotificationDataItem";
NSString *const NSFileHandleNotificationFileHandleItem = @"NSFileHandleNotificationFileHandleItem";
NSString *const NSFileHandleOperationException = @"NSFileHandleOperationException";
NSNotificationName const NSTaskDidTerminateNotification = @"NSTaskDidTerminateNotification";

static NSError *posix_error(int e, NSString *path) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSLocalizedDescriptionKey] = @(strerror(e));
    if (path) info[NSFilePathErrorKey] = path;
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:e userInfo:info];
}
static NSError *cocoa_error(NSInteger code, int e, NSString *path) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSUnderlyingErrorKey] = posix_error(e, path);
    if (path) info[NSFilePathErrorKey] = path;
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:info];
}

/* ---- file handles ---- */

@implementation NSFileHandle {
    int _fd;
    BOOL _closeOnDealloc, _closed;
    void (^_readability)(NSFileHandle *);
    void (^_writeability)(NSFileHandle *);
    dispatch_source_t _readSource, _writeSource;
    BOOL _backgroundBusy;
}
- (instancetype)initWithFileDescriptor:(int)fd closeOnDealloc:(BOOL)c {
    if ((self = [super init])) {
        _fd = fd;
        _closeOnDealloc = c;
    }
    return self;
}
- (instancetype)initWithFileDescriptor:(int)fd { return [self initWithFileDescriptor:fd closeOnDealloc:NO]; }
- (instancetype)init { return [self initWithFileDescriptor:-1 closeOnDealloc:NO]; }
- (void)dealloc {
    if (_readSource) {
        dispatch_source_cancel(_readSource);
        dispatch_release(_readSource);
    }
    if (_writeSource) {
        dispatch_source_cancel(_writeSource);
        dispatch_release(_writeSource);
    }
    if (_closeOnDealloc && !_closed && _fd >= 0) close(_fd);
}
- (int)fileDescriptor { return _fd; }

+ (NSFileHandle *)fileHandleWithStandardInput {
    static NSFileHandle *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = [[NSFileHandle alloc] initWithFileDescriptor:0]; });
    return h;
}
+ (NSFileHandle *)fileHandleWithStandardOutput {
    static NSFileHandle *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = [[NSFileHandle alloc] initWithFileDescriptor:1]; });
    return h;
}
+ (NSFileHandle *)fileHandleWithStandardError {
    static NSFileHandle *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = [[NSFileHandle alloc] initWithFileDescriptor:2]; });
    return h;
}
+ (NSFileHandle *)fileHandleWithNullDevice {
    int fd = open("/dev/null", O_RDWR | O_CLOEXEC);
    return [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
}
+ (instancetype)_bn_open:(NSString *)path flags:(int)flags error:(NSError **)error {
    int fd = path ? open(path.fileSystemRepresentation, flags | O_CLOEXEC) : -1;
    if (fd < 0) {
        if (error) *error = cocoa_error(errno == ENOENT ? NSFileNoSuchFileError : NSFileReadUnknownError, errno, path);
        return nil;
    }
    return [[self alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
}
+ (instancetype)fileHandleForReadingAtPath:(NSString *)p { return [self _bn_open:p flags:O_RDONLY error:NULL]; }
+ (instancetype)fileHandleForWritingAtPath:(NSString *)p { return [self _bn_open:p flags:O_WRONLY error:NULL]; }
+ (instancetype)fileHandleForUpdatingAtPath:(NSString *)p { return [self _bn_open:p flags:O_RDWR error:NULL]; }
+ (instancetype)fileHandleForReadingFromURL:(NSURL *)u error:(NSError **)e { return [self _bn_open:u.path flags:O_RDONLY error:e]; }
+ (instancetype)fileHandleForWritingToURL:(NSURL *)u error:(NSError **)e { return [self _bn_open:u.path flags:O_WRONLY error:e]; }
+ (instancetype)fileHandleForUpdatingURL:(NSURL *)u error:(NSError **)e { return [self _bn_open:u.path flags:O_RDWR error:e]; }

/* Reads up to length bytes (all, for NSUIntegerMax), retrying interrupted
 * reads; stops early only at end of file. */
- (NSData *)_bn_read:(NSUInteger)length untilEnd:(BOOL)toEnd error:(int *)err {
    NSMutableData *d = [NSMutableData data];
    char buf[65536];
    while (d.length < length) {
        size_t want = MIN(sizeof buf, length - d.length);
        ssize_t n = read(_fd, buf, want);
        if (n < 0) {
            if (errno == EINTR) continue;
            if (err) *err = errno;
            return nil;
        }
        if (n == 0) break;
        [d appendBytes:buf length:(NSUInteger)n];
        if (!toEnd && length == NSUIntegerMax) break;
    }
    return d;
}
- (NSData *)readDataToEndOfFileAndReturnError:(NSError **)error {
    int e = 0;
    NSData *d = [self _bn_read:NSUIntegerMax untilEnd:YES error:&e];
    if (!d && error) *error = cocoa_error(NSFileReadUnknownError, e, nil);
    return d;
}
- (NSData *)readDataUpToLength:(NSUInteger)length error:(NSError **)error {
    int e = 0;
    NSData *d = [self _bn_read:length untilEnd:YES error:&e];
    if (!d && error) *error = cocoa_error(NSFileReadUnknownError, e, nil);
    return d;
}
- (BOOL)writeData:(NSData *)data error:(NSError **)error {
    const char *p = data.bytes;
    size_t left = data.length;
    while (left) {
        ssize_t n = write(_fd, p, left);
        if (n < 0) {
            if (errno == EINTR) continue;
            if (error) *error = cocoa_error(NSFileWriteUnknownError, errno, nil);
            return NO;
        }
        p += n;
        left -= (size_t)n;
    }
    return YES;
}
- (BOOL)getOffset:(unsigned long long *)offset error:(NSError **)error {
    off_t o = lseek(_fd, 0, SEEK_CUR);
    if (o < 0) {
        if (error) *error = cocoa_error(NSFileReadUnknownError, errno, nil);
        return NO;
    }
    *offset = (unsigned long long)o;
    return YES;
}
- (BOOL)seekToEndReturningOffset:(unsigned long long *)offset error:(NSError **)error {
    off_t o = lseek(_fd, 0, SEEK_END);
    if (o < 0) {
        if (error) *error = cocoa_error(NSFileReadUnknownError, errno, nil);
        return NO;
    }
    if (offset) *offset = (unsigned long long)o;
    return YES;
}
- (BOOL)seekToOffset:(unsigned long long)offset error:(NSError **)error {
    if (lseek(_fd, (off_t)offset, SEEK_SET) < 0) {
        if (error) *error = cocoa_error(NSFileReadUnknownError, errno, nil);
        return NO;
    }
    return YES;
}
- (BOOL)truncateAtOffset:(unsigned long long)offset error:(NSError **)error {
    if (ftruncate(_fd, (off_t)offset) < 0 || lseek(_fd, (off_t)offset, SEEK_SET) < 0) {
        if (error) *error = cocoa_error(NSFileWriteUnknownError, errno, nil);
        return NO;
    }
    return YES;
}
- (BOOL)synchronizeAndReturnError:(NSError **)error {
    if (fsync(_fd) < 0 && errno != EINVAL && errno != EROFS) {
        if (error) *error = cocoa_error(NSFileWriteUnknownError, errno, nil);
        return NO;
    }
    return YES;
}
- (BOOL)closeAndReturnError:(NSError **)error {
    if (_closed) return YES;
    self.readabilityHandler = nil;
    self.writeabilityHandler = nil;
    _closed = YES;
    if (_fd >= 0 && close(_fd) < 0 && errno != EINTR) {
        if (error) *error = cocoa_error(NSFileWriteUnknownError, errno, nil);
        return NO;
    }
    return YES;
}

- (NSData *)availableData { return [self _bn_read:NSUIntegerMax untilEnd:NO error:NULL] ?: [NSData data]; }
- (NSData *)readDataToEndOfFile { return [self readDataToEndOfFileAndReturnError:NULL] ?: [NSData data]; }
- (NSData *)readDataOfLength:(NSUInteger)length { return [self readDataUpToLength:length error:NULL] ?: [NSData data]; }
- (void)writeData:(NSData *)data { [self writeData:data error:NULL]; }
- (unsigned long long)offsetInFile {
    unsigned long long o = 0;
    [self getOffset:&o error:NULL];
    return o;
}
- (unsigned long long)seekToEndOfFile {
    unsigned long long o = 0;
    [self seekToEndReturningOffset:&o error:NULL];
    return o;
}
- (void)seekToFileOffset:(unsigned long long)o { [self seekToOffset:o error:NULL]; }
- (void)truncateFileAtOffset:(unsigned long long)o { [self truncateAtOffset:o error:NULL]; }
- (void)synchronizeFile { [self synchronizeAndReturnError:NULL]; }
- (void)closeFile { [self closeAndReturnError:NULL]; }

/* ---- reading in the background ---- */

- (void (^)(NSFileHandle *))readabilityHandler { return _readability; }
- (void)setReadabilityHandler:(void (^)(NSFileHandle *))h {
    @synchronized(self) {
        if (_readSource) {
            dispatch_source_cancel(_readSource);
            dispatch_release(_readSource);
            _readSource = NULL;
        }
        _readability = [h copy];
        if (!h || _fd < 0) return;
        dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)_fd, 0,
                                                     dispatch_queue_create("bitten.filehandle.read", DISPATCH_QUEUE_SERIAL));
        __weak NSFileHandle *weakSelf = self;
        dispatch_source_set_event_handler(s, ^{
            NSFileHandle *me = weakSelf;
            void (^handler)(NSFileHandle *) = nil;
            if (me) handler = me->_readability;
            if (handler) handler(me);
        });
        _readSource = s;
        dispatch_resume(s);
    }
}
- (void (^)(NSFileHandle *))writeabilityHandler { return _writeability; }
- (void)setWriteabilityHandler:(void (^)(NSFileHandle *))h {
    @synchronized(self) {
        if (_writeSource) {
            dispatch_source_cancel(_writeSource);
            dispatch_release(_writeSource);
            _writeSource = NULL;
        }
        _writeability = [h copy];
        if (!h || _fd < 0) return;
        dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, (uintptr_t)_fd, 0,
                                                     dispatch_queue_create("bitten.filehandle.write", DISPATCH_QUEUE_SERIAL));
        __weak NSFileHandle *weakSelf = self;
        dispatch_source_set_event_handler(s, ^{
            NSFileHandle *me = weakSelf;
            void (^handler)(NSFileHandle *) = nil;
            if (me) handler = me->_writeability;
            if (handler) handler(me);
        });
        _writeSource = s;
        dispatch_resume(s);
    }
}

/* The notification forms read on a background queue and post on the
 * thread that asked (here: the main queue, or the caller's queue). */
- (void)_bn_background:(NSNotificationName)name read:(BOOL)read toEnd:(BOOL)toEnd {
    @synchronized(self) {
        if (_backgroundBusy) return;
        _backgroundBusy = YES;
    }
    dispatch_queue_t back = [NSThread isMainThread] ? dispatch_get_main_queue() : dispatch_get_global_queue(0, 0);
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSDictionary *info;
        if (read) {
            int e = 0;
            NSData *d = [self _bn_read:NSUIntegerMax untilEnd:toEnd error:&e] ?: [NSData data];
            info = e ? @{NSFileHandleNotificationDataItem : d, @"NSFileHandleError" : @(e)}
                     : @{NSFileHandleNotificationDataItem : d};
        } else {
            struct pollfd pf = {self->_fd, POLLIN, 0};
            while (poll(&pf, 1, -1) < 0 && errno == EINTR) {
            }
            info = nil;
        }
        dispatch_async(back, ^{
            @synchronized(self) { self->_backgroundBusy = NO; }
            [[NSNotificationCenter defaultCenter] postNotificationName:name object:self userInfo:info];
        });
    });
}
- (void)readInBackgroundAndNotifyForModes:(NSArray *)modes { [self _bn_background:NSFileHandleReadCompletionNotification read:YES toEnd:NO]; }
- (void)readInBackgroundAndNotify { [self readInBackgroundAndNotifyForModes:nil]; }
- (void)readToEndOfFileInBackgroundAndNotifyForModes:(NSArray *)modes {
    [self _bn_background:NSFileHandleReadToEndOfFileCompletionNotification read:YES toEnd:YES];
}
- (void)readToEndOfFileInBackgroundAndNotify { [self readToEndOfFileInBackgroundAndNotifyForModes:nil]; }
- (void)waitForDataInBackgroundAndNotifyForModes:(NSArray *)modes {
    [self _bn_background:NSFileHandleDataAvailableNotification read:NO toEnd:NO];
}
- (void)waitForDataInBackgroundAndNotify { [self waitForDataInBackgroundAndNotifyForModes:nil]; }
@end

/* ---- pipes ---- */

@implementation NSPipe {
    NSFileHandle *_read, *_write;
}
+ (NSPipe *)pipe { return [self new]; }
- (instancetype)init {
    if ((self = [super init])) {
        int fds[2];
        if (pipe(fds) != 0) return nil;
        fcntl(fds[0], F_SETFD, FD_CLOEXEC);
        fcntl(fds[1], F_SETFD, FD_CLOEXEC);
        _read = [[NSFileHandle alloc] initWithFileDescriptor:fds[0] closeOnDealloc:YES];
        _write = [[NSFileHandle alloc] initWithFileDescriptor:fds[1] closeOnDealloc:YES];
    }
    return self;
}
- (NSFileHandle *)fileHandleForReading { return _read; }
- (NSFileHandle *)fileHandleForWriting { return _write; }
@end

/* ---- tasks ---- */

@implementation NSTask {
    NSURL *_executableURL, *_currentDirectoryURL;
    NSArray<NSString *> *_arguments;
    NSDictionary<NSString *, NSString *> *_environment;
    id _stdin, _stdout, _stderr;
    pid_t _pid;
    BOOL _launched, _running;
    int _status;
    NSTaskTerminationReason _reason;
    void (^_terminationHandler)(NSTask *);
    NSQualityOfService _qos;
    dispatch_semaphore_t _exited;
}
- (instancetype)init {
    if ((self = [super init])) {
        _exited = dispatch_semaphore_create(0);
        _qos = NSQualityOfServiceDefault;
    }
    return self;
}
- (NSURL *)executableURL { return _executableURL; }
- (void)setExecutableURL:(NSURL *)u { _executableURL = [u copy]; }
- (NSString *)launchPath { return _executableURL.path; }
- (void)setLaunchPath:(NSString *)p { _executableURL = p ? [NSURL fileURLWithPath:p] : nil; }
- (NSArray *)arguments { return _arguments; }
- (void)setArguments:(NSArray *)a { _arguments = [a copy]; }
- (NSDictionary *)environment { return _environment; }
- (void)setEnvironment:(NSDictionary *)e { _environment = [e copy]; }
- (NSURL *)currentDirectoryURL { return _currentDirectoryURL; }
- (void)setCurrentDirectoryURL:(NSURL *)u { _currentDirectoryURL = [u copy]; }
- (NSString *)currentDirectoryPath {
    return _currentDirectoryURL.path ?: [[NSFileManager defaultManager] currentDirectoryPath];
}
- (void)setCurrentDirectoryPath:(NSString *)p { _currentDirectoryURL = p ? [NSURL fileURLWithPath:p isDirectory:YES] : nil; }
- (id)standardInput { return _stdin; }
- (void)setStandardInput:(id)h { _stdin = h; }
- (id)standardOutput { return _stdout; }
- (void)setStandardOutput:(id)h { _stdout = h; }
- (id)standardError { return _stderr; }
- (void)setStandardError:(id)h { _stderr = h; }
- (void (^)(NSTask *))terminationHandler { return _terminationHandler; }
- (void)setTerminationHandler:(void (^)(NSTask *))h { _terminationHandler = [h copy]; }
- (NSQualityOfService)qualityOfService { return _qos; }
- (void)setQualityOfService:(NSQualityOfService)q { _qos = q; }
- (int)processIdentifier { return _pid; }
- (BOOL)isRunning {
    @synchronized(self) { return _running; }
}
- (int)terminationStatus {
    if (!_launched || self.isRunning)
        [NSException raise:NSInvalidArgumentException format:@"task not launched or still running"];
    return _status;
}
- (NSTaskTerminationReason)terminationReason { return _reason; }

/* The descriptor a standard stream comes from: a pipe's end, a handle's
 * descriptor, or -1 to inherit. */
static int stream_fd(id s, BOOL forReading) {
    if ([s isKindOfClass:[NSPipe class]])
        return forReading ? [s fileHandleForReading].fileDescriptor : [s fileHandleForWriting].fileDescriptor;
    if ([s isKindOfClass:[NSFileHandle class]]) return [s fileDescriptor];
    return -1;
}

- (BOOL)launchAndReturnError:(NSError **)error {
    if (_launched) {
        if (error) *error = cocoa_error(NSFileWriteUnknownError, EALREADY, nil);
        return NO;
    }
    NSString *path = _executableURL.path;
    struct stat st;
    if (!path.length || stat(path.fileSystemRepresentation, &st) != 0) {
        if (error) *error = cocoa_error(NSFileNoSuchFileError, ENOENT, path);
        return NO;
    }
    if (!(st.st_mode & 0111) || S_ISDIR(st.st_mode)) {
        if (error) *error = cocoa_error(NSFileReadNoPermissionError, EACCES, path);
        return NO;
    }

    NSUInteger argc = _arguments.count;
    char **argv = calloc(argc + 2, sizeof(char *));
    argv[0] = strdup(path.fileSystemRepresentation);
    for (NSUInteger i = 0; i < argc; i++) argv[i + 1] = strdup(_arguments[i].UTF8String ?: "");
    char **envp = environ;
    char **own = NULL;
    if (_environment) {
        own = calloc(_environment.count + 1, sizeof(char *));
        NSUInteger i = 0;
        for (NSString *k in _environment)
            own[i++] = strdup([NSString stringWithFormat:@"%@=%@", k, _environment[k]].UTF8String);
        envp = own;
    }

    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    int in = stream_fd(_stdin, YES), out = stream_fd(_stdout, NO), err = stream_fd(_stderr, NO);
    if (in >= 0) posix_spawn_file_actions_adddup2(&fa, in, 0);
    if (out >= 0) posix_spawn_file_actions_adddup2(&fa, out, 1);
    if (err >= 0) posix_spawn_file_actions_adddup2(&fa, err, 2);
    if (_currentDirectoryURL.path.length)
        posix_spawn_file_actions_addchdir_np(&fa, _currentDirectoryURL.path.fileSystemRepresentation);
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    sigset_t none, all;
    sigemptyset(&none);
    sigfillset(&all);
    posix_spawnattr_setsigmask(&attr, &none);
    posix_spawnattr_setsigdefault(&attr, &all);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);

    pid_t pid = 0;
    int rc = posix_spawn(&pid, argv[0], &fa, &attr, argv, envp);
    posix_spawn_file_actions_destroy(&fa);
    posix_spawnattr_destroy(&attr);
    for (NSUInteger i = 0; argv[i]; i++) free(argv[i]);
    free(argv);
    if (own) {
        for (NSUInteger i = 0; own[i]; i++) free(own[i]);
        free(own);
    }
    if (rc != 0) {
        if (error) *error = cocoa_error(rc == ENOENT ? NSFileNoSuchFileError : NSFileReadUnknownError, rc, path);
        return NO;
    }
    _pid = pid;
    _launched = YES;
    @synchronized(self) { _running = YES; }
    /* The child has the pipe ends it needs; the parent's copies go. */
    if ([_stdin isKindOfClass:[NSPipe class]]) [[_stdin fileHandleForReading] closeFile];
    if ([_stdout isKindOfClass:[NSPipe class]]) [[_stdout fileHandleForWriting] closeFile];
    if ([_stderr isKindOfClass:[NSPipe class]] && _stderr != _stdout) [[_stderr fileHandleForWriting] closeFile];

    NSTask *me = self; /* alive until it exits */
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        int status = 0;
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
        }
        if (WIFSIGNALED(status)) {
            me->_status = WTERMSIG(status);
            me->_reason = NSTaskTerminationReasonUncaughtSignal;
        } else {
            me->_status = WEXITSTATUS(status);
            me->_reason = NSTaskTerminationReasonExit;
        }
        @synchronized(me) { me->_running = NO; }
        void (^h)(NSTask *) = me->_terminationHandler;
        if (h) h(me);
        me->_terminationHandler = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:NSTaskDidTerminateNotification object:me];
        });
        dispatch_semaphore_signal(me->_exited);
    });
    return YES;
}
- (void)launch {
    NSError *e = nil;
    if (![self launchAndReturnError:&e])
        [NSException raise:NSInvalidArgumentException format:@"launch path not accessible: %@", self.launchPath];
}
+ (NSTask *)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray<NSString *> *)arguments {
    NSTask *t = [NSTask new];
    t.launchPath = path;
    t.arguments = arguments;
    [t launch];
    return t;
}
+ (NSTask *)launchedTaskWithExecutableURL:(NSURL *)url arguments:(NSArray<NSString *> *)arguments error:(NSError **)error
                       terminationHandler:(void (^)(NSTask *))handler {
    NSTask *t = [NSTask new];
    t.executableURL = url;
    t.arguments = arguments;
    t.terminationHandler = handler;
    return [t launchAndReturnError:error] ? t : nil;
}
- (void)_bn_signal:(int)sig {
    if (_launched && self.isRunning) kill(_pid, sig);
}
- (void)interrupt { [self _bn_signal:SIGINT]; }
- (void)terminate { [self _bn_signal:SIGTERM]; }
- (BOOL)suspend {
    [self _bn_signal:SIGSTOP];
    return _launched;
}
- (BOOL)resume {
    [self _bn_signal:SIGCONT];
    return _launched;
}
- (void)waitUntilExit {
    if (!_launched) return;
    BOOL main = [NSThread isMainThread];
    while (self.isRunning) {
        if (dispatch_semaphore_wait(_exited, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC)) == 0) {
            dispatch_semaphore_signal(_exited);
            break;
        }
        /* keep the main queue going, as the run loop would */
        if (main) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}
@end
