// launchctl without launchd: bootstrap a job from a plist (which is then
// deleted, as launchd keeps its own copy), print, list, kickstart, bootout.
#import <Foundation/Foundation.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

static NSString *home;
static int run(NSArray *args, NSString **out) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    t.arguments = args;
    t.environment = @{@"HOME" : home, @"PATH" : @"/usr/bin:/bin"};
    NSPipe *p = [NSPipe pipe];
    t.standardOutput = p;
    t.standardError = p;
    CHECK([t launchAndReturnError:NULL]);
    NSData *d = [p.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    if (out) *out = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    return t.terminationStatus;
}

int main(void) {
    home = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"bitten-launchd-%d", getpid()]];
    [[NSFileManager defaultManager] createDirectoryAtPath:home withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *plist = [home stringByAppendingPathComponent:@"job.plist"];
    NSString *xml = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>"
                     "<key>Label</key><string>com.example.sleeper</string>"
                     "<key>ProgramArguments</key><array><string>/bin/sleep</string><string>60</string></array>"
                     "<key>RunAtLoad</key><true/>"
                     "<key>EnvironmentVariables</key><dict><key>A</key><string>b &amp; c</string></dict>"
                     "</dict></plist>\n";
    CHECK([xml writeToFile:plist atomically:NO encoding:NSUTF8StringEncoding error:NULL]);
    NSString *out = nil;
    CHECK(run(@[@"print", @"gui/0/com.example.sleeper"], &out) == 113);
    CHECK(run(@[@"bootout", @"gui/0/com.example.sleeper"], &out) == 3);
    CHECK(run(@[@"bootstrap", @"gui/0", plist], &out) == 0);
    [[NSFileManager defaultManager] removeItemAtPath:plist error:NULL];
    CHECK(run(@[@"print", @"gui/0/com.example.sleeper"], &out) == 0);
    CHECK([out containsString:@"state = running"] && [out containsString:@"/bin/sleep"]);
    NSRange r = [out rangeOfString:@"pid = "];
    CHECK(r.location != NSNotFound);
    pid_t pid = [[out substringFromIndex:NSMaxRange(r)] intValue];
    CHECK(pid > 0 && kill(pid, 0) == 0);
    CHECK(run(@[@"bootstrap", @"gui/0", plist], &out) == 5);
    CHECK(run(@[@"list"], &out) == 0 && [out containsString:@"com.example.sleeper"]);
    /* kickstart -k restarts it; -p prints the pid */
    CHECK(run(@[@"kickstart", @"-kp", @"gui/0/com.example.sleeper"], &out) == 0);
    pid_t pid2 = out.intValue;
    CHECK(pid2 > 0 && pid2 != pid && kill(pid2, 0) == 0);
    CHECK(run(@[@"bootout", @"gui/0/com.example.sleeper"], &out) == 0);
    usleep(100000);
    CHECK(kill(pid2, 0) != 0);
    CHECK(run(@[@"print", @"gui/0/com.example.sleeper"], &out) == 113);
    CHECK(run(@[@"version"], &out) == 0 && [out containsString:@"Darwin Bootstrapper"]);
    [[NSFileManager defaultManager] removeItemAtPath:home error:NULL];
    printf("launchctl ok\n");
    return 0;
}
