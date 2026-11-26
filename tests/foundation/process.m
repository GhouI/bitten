// Processes, pipes and file handles; XPC connections (one to a service
// that cannot be reached, one to an anonymous listener in this process).
#import <Foundation/Foundation.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

static BOOL wait_for(BOOL (^cond)(void)) {
    for (int i = 0; i < 500 && !cond(); i++) usleep(10000);
    return cond();
}

@protocol Adder <NSObject>
- (void)add:(int)a to:(int)b reply:(void (^)(int sum))reply;
- (void)shout:(NSString *)s;
@end

@interface AdderService : NSObject <Adder>
@property int shouts;
@end
@implementation AdderService
- (void)add:(int)a to:(int)b reply:(void (^)(int))reply { reply(a + b); }
- (void)shout:(NSString *)s { self.shouts++; }
@end

@interface Accepter : NSObject <NSXPCListenerDelegate>
@property AdderService *service;
@property BOOL refuse;
@end
@implementation Accepter
- (BOOL)listener:(NSXPCListener *)l shouldAcceptNewConnection:(NSXPCConnection *)c {
    if (self.refuse) return NO;
    c.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(Adder)];
    c.exportedObject = self.service;
    [c resume];
    return YES;
}
@end

int main(void) {
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"bitten-proc-%d", getpid()]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:NULL];

    /* Output through a pipe, the exit status, the termination handler. */
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    t.arguments = @[@"-c", @"echo hello; echo \"$GREETING\" >&2; pwd; exit 3"];
    t.environment = @{@"GREETING" : @"from env", @"PATH" : @"/usr/bin:/bin"};
    t.currentDirectoryURL = [NSURL fileURLWithPath:tmp isDirectory:YES];
    NSPipe *out = [NSPipe pipe], *err = [NSPipe pipe];
    t.standardOutput = out;
    t.standardError = err;
    __block int handled = 0;
    t.terminationHandler = ^(NSTask *task) { handled = task.terminationStatus + 100; };
    NSError *e = nil;
    CHECK([t launchAndReturnError:&e] && !e && t.processIdentifier > 0);
    NSData *o = [out.fileHandleForReading readDataToEndOfFile];
    NSData *er = [err.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    CHECK(!t.isRunning && t.terminationStatus == 3 && t.terminationReason == NSTaskTerminationReasonExit);
    NSString *text = [[NSString alloc] initWithData:o encoding:NSUTF8StringEncoding];
    CHECK([text hasPrefix:@"hello\n"] && [text containsString:@"bitten-proc-"]);
    CHECK([[[NSString alloc] initWithData:er encoding:NSUTF8StringEncoding] isEqual:@"from env\n"]);
    CHECK(wait_for(^{ return (BOOL)(handled == 103); }));

    /* Input through a pipe. */
    NSTask *cat = [NSTask new];
    cat.launchPath = @"/bin/cat";
    NSPipe *in = [NSPipe pipe], *catOut = [NSPipe pipe];
    cat.standardInput = in;
    cat.standardOutput = catOut;
    [cat launch];
    [in.fileHandleForWriting writeData:[@"round trip" dataUsingEncoding:NSUTF8StringEncoding]];
    [in.fileHandleForWriting closeFile];
    NSData *back = [catOut.fileHandleForReading readDataToEndOfFile];
    [cat waitUntilExit];
    CHECK([[[NSString alloc] initWithData:back encoding:NSUTF8StringEncoding] isEqual:@"round trip"] && cat.terminationStatus == 0);

    /* A signal ends it. */
    NSTask *sleeper = [NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/bin/sleep"] arguments:@[@"30"]
                                                      error:&e terminationHandler:nil];
    CHECK(sleeper && sleeper.isRunning);
    [sleeper terminate];
    [sleeper waitUntilExit];
    CHECK(sleeper.terminationReason == NSTaskTerminationReasonUncaughtSignal && sleeper.terminationStatus == SIGTERM);

    /* A missing program fails to launch. */
    NSTask *bad = [NSTask new];
    bad.executableURL = [NSURL fileURLWithPath:@"/no/such/program"];
    e = nil;
    CHECK(![bad launchAndReturnError:&e] && e.code == NSFileNoSuchFileError);

    /* File handles over a file. */
    NSString *path = [tmp stringByAppendingPathComponent:@"f.txt"];
    [[NSFileManager defaultManager] createFileAtPath:path contents:[NSData data] attributes:@{}];
    NSFileHandle *w = [NSFileHandle fileHandleForUpdatingAtPath:path];
    CHECK(w && w.fileDescriptor >= 0);
    CHECK([w writeData:[@"0123456789" dataUsingEncoding:NSUTF8StringEncoding] error:&e]);
    CHECK(w.offsetInFile == 10);
    [w seekToFileOffset:2];
    CHECK([[[NSString alloc] initWithData:[w readDataOfLength:3] encoding:NSUTF8StringEncoding] isEqual:@"234"]);
    unsigned long long end = 0;
    CHECK([w seekToEndReturningOffset:&end error:&e] && end == 10);
    CHECK([w truncateAtOffset:4 error:&e] && w.offsetInFile == 4);
    [w seekToFileOffset:0];
    CHECK([[[NSString alloc] initWithData:[w readDataToEndOfFile] encoding:NSUTF8StringEncoding] isEqual:@"0123"]);
    CHECK([w closeAndReturnError:&e]);
    CHECK([NSFileHandle fileHandleForReadingAtPath:@"/no/such/file"] == nil);
    e = nil;
    CHECK(![NSFileHandle fileHandleForReadingFromURL:[NSURL fileURLWithPath:@"/no/such/file"] error:&e] &&
          e.code == NSFileNoSuchFileError);

    /* A readability handler sees what is written to a pipe. */
    NSPipe *p = [NSPipe pipe];
    __block NSMutableString *seen = [NSMutableString string];
    p.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
        NSData *d = h.availableData;
        @synchronized(seen) { [seen appendString:[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]]; }
    };
    [p.fileHandleForWriting writeData:[@"ping" dataUsingEncoding:NSUTF8StringEncoding]];
    CHECK(wait_for(^{ @synchronized(seen) { return [seen isEqual:@"ping"]; } }));
    p.fileHandleForReading.readabilityHandler = nil;

    /* XPC: a named service is not there. */
    NSXPCConnection *svc = [[NSXPCConnection alloc] initWithServiceName:@"org.example.helper"];
    svc.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(Adder)];
    __block int invalidated = 0, errors = 0, replies = 0;
    __block NSInteger code = 0;
    svc.invalidationHandler = ^{ invalidated++; };
    [svc resume];
    id<Adder> remote = [svc remoteObjectProxyWithErrorHandler:^(NSError *err2) {
        errors++;
        code = err2.code;
    }];
    CHECK([remote conformsToProtocol:@protocol(Adder)] && [remote respondsToSelector:@selector(add:to:reply:)]);
    CHECK(class_conformsToProtocol(object_getClass(remote), @protocol(Adder)));
    [remote add:1 to:2 reply:^(int sum) { replies++; }];
    CHECK(wait_for(^{ return (BOOL)(errors == 1 && invalidated == 1); }));
    CHECK(code == NSXPCConnectionInvalid && replies == 0);
    [svc invalidate];
    usleep(20000);
    CHECK(invalidated == 1);

    /* XPC: an anonymous listener in this process. */
    NSXPCListener *listener = [NSXPCListener anonymousListener];
    Accepter *accepter = [Accepter new];
    accepter.service = [AdderService new];
    listener.delegate = accepter;
    [listener resume];
    NSXPCConnection *c = [[NSXPCConnection alloc] initWithListenerEndpoint:listener.endpoint];
    c.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(Adder)];
    [c resume];
    __block int sum = 0;
    id<Adder> adder = [c remoteObjectProxyWithErrorHandler:^(NSError *err3) { errors++; }];
    [adder add:20 to:22 reply:^(int s) { sum = s; }];
    [[c remoteObjectProxy] shout:@"hi"];
    CHECK(wait_for(^{ return (BOOL)(sum == 42); }) && accepter.service.shouts == 1 && errors == 1);
    __block int closed = 0;
    c.invalidationHandler = ^{ closed++; };
    [c invalidate];
    CHECK(wait_for(^{ return (BOOL)(closed == 1); }));

    /* A listener that refuses. */
    accepter.refuse = YES;
    NSXPCConnection *refused = [[NSXPCConnection alloc] initWithListenerEndpoint:listener.endpoint];
    __block int refusedInvalid = 0;
    refused.invalidationHandler = ^{ refusedInvalid++; };
    [refused resume];
    CHECK(wait_for(^{ return (BOOL)(refusedInvalid == 1); }));

    [[NSFileManager defaultManager] removeItemAtPath:tmp error:NULL];
    printf("process ok\n");
    return 0;
}
