// URLSession against a local server (tests/foundation/urlserver.py): data
// tasks, headers, redirects (followed, refused, too many), cookies, POST
// and PUT bodies, compressed bodies, downloads, delegates, cancelling,
// errors, timeouts, data: and file: URLs, metrics, and WebSockets.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

static NSString *base;
static NSURL *U(NSString *path) { return [NSURL URLWithString:[base stringByAppendingString:path]]; }

typedef struct {
    NSData *data;
    NSHTTPURLResponse *response;
    NSError *error;
} Result;

static Result fetch(NSURLSession *s, NSURLRequest *r) {
    __block Result out = {nil, nil, nil};
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[s dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        out.data = d;
        out.response = (NSHTTPURLResponse *)resp;
        out.error = e;
        dispatch_semaphore_signal(done);
    }] resume];
    CHECK(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)) == 0);
    return out;
}
static NSString *text(NSData *d) { return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]; }

@interface Watcher : NSObject <NSURLSessionDataDelegate, NSURLSessionDownloadDelegate, NSURLSessionWebSocketDelegate>
@property NSMutableData *received;
@property NSURLResponse *response;
@property NSError *completedError;
@property BOOL completed, refuseRedirect, sawMetrics;
@property NSString *downloaded, *openedProtocol;
@property NSInteger closeCode;
@property int redirects;
@property dispatch_semaphore_t done;
@end
@implementation Watcher
- (instancetype)init {
    if ((self = [super init])) {
        _received = [NSMutableData data];
        _done = dispatch_semaphore_create(0);
    }
    return self;
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveResponse:(NSURLResponse *)r
    completionHandler:(void (^)(NSURLSessionResponseDisposition))h {
    self.response = r;
    h(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d { [self.received appendData:d]; }
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t willPerformHTTPRedirection:(NSHTTPURLResponse *)r
        newRequest:(NSURLRequest *)req completionHandler:(void (^)(NSURLRequest *))h {
    self.redirects++;
    h(self.refuseRedirect ? nil : req);
}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)m {
    self.sawMetrics = m.transactionMetrics.count > 0 && m.transactionMetrics.lastObject.remotePort != nil;
}
- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)t didFinishDownloadingToURL:(NSURL *)location {
    self.downloaded = [NSString stringWithContentsOfFile:location.path encoding:NSUTF8StringEncoding error:NULL];
}
- (void)URLSession:(NSURLSession *)s webSocketTask:(NSURLSessionWebSocketTask *)t didOpenWithProtocol:(NSString *)p {
    self.openedProtocol = p ?: @"";
}
- (void)URLSession:(NSURLSession *)s webSocketTask:(NSURLSessionWebSocketTask *)t
    didCloseWithCode:(NSURLSessionWebSocketCloseCode)code reason:(NSData *)reason {
    self.closeCode = code;
}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)e {
    self.completedError = e;
    self.completed = YES;
    dispatch_semaphore_signal(self.done);
}
- (void)wait { CHECK(dispatch_semaphore_wait(self.done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)) == 0); }
@end

static NSURLSessionWebSocketMessage *receive(NSURLSessionWebSocketTask *t, NSError **err) {
    __block NSURLSessionWebSocketMessage *m = nil;
    __block NSError *e = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [t receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *msg, NSError *error) {
        m = msg;
        e = error;
        dispatch_semaphore_signal(done);
    }];
    CHECK(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)) == 0);
    if (err) *err = e;
    return m;
}

int main(void) {
    /* the server */
    NSTask *server = [NSTask new];
    server.executableURL = [NSURL fileURLWithPath:@"/usr/bin/python3"];
    server.arguments = @[@"tests/foundation/urlserver.py"];
    NSPipe *portPipe = [NSPipe pipe], *stdinPipe = [NSPipe pipe];
    server.standardOutput = portPipe;
    server.standardInput = stdinPipe;
    NSError *e = nil;
    if (![server launchAndReturnError:&e]) {
        printf("urlsession skipped (no python3)\n");
        return 0;
    }
    NSMutableString *line = [NSMutableString string];
    while (![line hasSuffix:@"\n"]) {
        NSData *d = [portPipe.fileHandleForReading readDataOfLength:1];
        if (!d.length) break;
        [line appendString:text(d)];
    }
    int port = line.intValue;
    CHECK(port > 0);
    base = [NSString stringWithFormat:@"http://127.0.0.1:%d", port];
    NSURLSession *s = [NSURLSession sharedSession];

    /* a plain GET */
    Result r = fetch(s, [NSURLRequest requestWithURL:U(@"/hello")]);
    CHECK(!r.error && [text(r.data) isEqual:@"hello world"]);
    CHECK(r.response.statusCode == 200 && [r.response.MIMEType isEqual:@"text/plain"] &&
          [r.response.textEncodingName isEqual:@"utf-8"] && r.response.expectedContentLength == 11);
    CHECK([[r.response valueForHTTPHeaderField:@"x-test"] isEqual:@"yes"]);
    CHECK([r.response.suggestedFilename isEqual:@"hello"]);
    CHECK([[NSHTTPURLResponse localizedStringForStatusCode:404] isEqual:@"not found"]);

    /* status codes are not errors */
    r = fetch(s, [NSURLRequest requestWithURL:U(@"/missing")]);
    CHECK(!r.error && r.response.statusCode == 404 && [text(r.data) isEqual:@"nope"]);

    /* redirects: followed (absolute and relative), and too many */
    r = fetch(s, [NSURLRequest requestWithURL:U(@"/redirect")]);
    CHECK(!r.error && [text(r.data) isEqual:@"hello world"] && [r.response.URL.path isEqual:@"/hello"]);
    r = fetch(s, [NSURLRequest requestWithURL:U(@"/relative/redirect")]);
    CHECK(!r.error && [text(r.data) isEqual:@"hello world"]);
    r = fetch(s, [NSURLRequest requestWithURL:U(@"/loop")]);
    CHECK(r.error.code == NSURLErrorHTTPTooManyRedirects && [r.error.domain isEqual:NSURLErrorDomain]);

    /* POST bodies, the content type defaulting, other methods */
    NSMutableURLRequest *post = [NSMutableURLRequest requestWithURL:U(@"/echo")];
    post.HTTPMethod = @"POST";
    post.HTTPBody = [@"a=1&b=2" dataUsingEncoding:NSUTF8StringEncoding];
    r = fetch(s, post);
    CHECK([text(r.data) isEqual:@"a=1&b=2"] &&
          [[r.response valueForHTTPHeaderField:@"Content-Type"] isEqual:@"application/x-www-form-urlencoded"]);
    [post setValue:@"application/json" forHTTPHeaderField:@"content-type"];
    CHECK([[post valueForHTTPHeaderField:@"Content-Type"] isEqual:@"application/json"]);
    r = fetch(s, post);
    CHECK([[r.response valueForHTTPHeaderField:@"Content-Type"] isEqual:@"application/json"]);
    NSMutableURLRequest *put = [NSMutableURLRequest requestWithURL:U(@"/anything")];
    put.HTTPMethod = @"PUT";
    __block NSData *putData = nil;
    dispatch_semaphore_t putDone = dispatch_semaphore_create(0);
    [[s uploadTaskWithRequest:put fromData:[@"xyz" dataUsingEncoding:NSUTF8StringEncoding]
            completionHandler:^(NSData *d, NSURLResponse *resp, NSError *err) {
                putData = d;
                dispatch_semaphore_signal(putDone);
            }] resume];
    dispatch_semaphore_wait(putDone, DISPATCH_TIME_FOREVER);
    CHECK([text(putData) isEqual:@"put:xyz"]);
    NSMutableURLRequest *head = [NSMutableURLRequest requestWithURL:U(@"/hello")];
    head.HTTPMethod = @"HEAD";
    r = fetch(s, head);
    CHECK(r.response.statusCode == 200 && r.data.length == 0);
    /* 303 after POST becomes a GET (and /method is a 404 here) */
    NSMutableURLRequest *see = [NSMutableURLRequest requestWithURL:U(@"/seeother")];
    see.HTTPMethod = @"POST";
    see.HTTPBody = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
    r = fetch(s, see);
    CHECK(r.response.statusCode == 404 && [r.response.URL.path isEqual:@"/method"]);

    /* compressed bodies are decoded; a user agent is sent */
    r = fetch(s, [NSURLRequest requestWithURL:U(@"/gzip")]);
    CHECK(r.data.length == 1000 && ((const char *)r.data.bytes)[999] == 'z');
    r = fetch(s, [NSURLRequest requestWithURL:U(@"/agent")]);
    CHECK([text(r.data) containsString:@"CFNetwork/"]);

    /* cookies, through an ephemeral session's own storage */
    NSURLSession *eph = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    fetch(eph, [NSURLRequest requestWithURL:U(@"/setcookie")]);
    CHECK([eph.configuration.HTTPCookieStorage cookiesForURL:U(@"/")].count == 2);
    r = fetch(eph, [NSURLRequest requestWithURL:U(@"/cookies")]);
    CHECK([text(r.data) containsString:@"flavor=oat"] && [text(r.data) containsString:@"other=1"]);
    r = fetch(s, [NSURLRequest requestWithURL:U(@"/cookies")]);
    CHECK(![text(r.data) containsString:@"flavor"]);

    /* errors: nothing listening, a bad scheme */
    r = fetch(s, [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:1/"]]);
    CHECK(r.error.code == NSURLErrorCannotConnectToHost && !r.data);
    CHECK([r.error.userInfo[NSURLErrorFailingURLStringErrorKey] isEqual:@"http://127.0.0.1:1/"]);

    /* a timeout */
    NSMutableURLRequest *slow = [NSMutableURLRequest requestWithURL:U(@"/slow")];
    slow.timeoutInterval = 1;
    r = fetch(s, slow);
    CHECK(r.error.code == NSURLErrorTimedOut);

    /* data: and file: URLs */
    r = fetch(s, [NSURLRequest requestWithURL:[NSURL URLWithString:@"data:text/plain;base64,aGk="]]);
    CHECK([text(r.data) isEqual:@"hi"] && [((NSURLResponse *)r.response).MIMEType isEqual:@"text/plain"]);
    r = fetch(s, [NSURLRequest requestWithURL:[NSURL URLWithString:@"data:,a%20b"]]);
    CHECK([text(r.data) isEqual:@"a b"]);
    NSString *file = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"bitten-url-%d.json", getpid()]];
    [@"{}" writeToFile:file atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    r = fetch(s, [NSURLRequest requestWithURL:[NSURL fileURLWithPath:file]]);
    CHECK([text(r.data) isEqual:@"{}"] && [((NSURLResponse *)r.response).MIMEType isEqual:@"application/json"] &&
          ![r.response isKindOfClass:[NSHTTPURLResponse class]]);
    [[NSFileManager defaultManager] removeItemAtPath:file error:NULL];

    /* delegates: response, data in pieces, metrics, refusing a redirect */
    Watcher *w = [Watcher new];
    NSURLSession *ds = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                     delegate:w delegateQueue:nil];
    NSURLSessionDataTask *dt = [ds dataTaskWithURL:U(@"/big")];
    CHECK(dt.state == NSURLSessionTaskStateSuspended && dt.taskIdentifier > 0);
    [dt resume];
    [w wait];
    CHECK(!w.completedError && w.received.length == 256 * 4096 && dt.state == NSURLSessionTaskStateCompleted);
    CHECK(((const unsigned char *)w.received.bytes)[257] == 1 && w.sawMetrics && dt.countOfBytesReceived == 256 * 4096);
    w.refuseRedirect = YES;
    w.received = [NSMutableData data];
    [[ds dataTaskWithURL:U(@"/redirect")] resume];
    [w wait];
    CHECK(w.redirects == 1 && [text(w.received) isEqual:@""]);

    /* downloads */
    [[ds downloadTaskWithURL:U(@"/hello")] resume];
    [w wait];
    CHECK([w.downloaded isEqual:@"hello world"]);
    __block NSString *dl = nil;
    dispatch_semaphore_t dlDone = dispatch_semaphore_create(0);
    [[s downloadTaskWithURL:U(@"/hello") completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
        dl = [NSString stringWithContentsOfFile:loc.path encoding:NSUTF8StringEncoding error:NULL];
        dispatch_semaphore_signal(dlDone);
    }] resume];
    dispatch_semaphore_wait(dlDone, DISPATCH_TIME_FOREVER);
    CHECK([dl isEqual:@"hello world"]);

    /* cancelling, before and during */
    NSURLSessionDataTask *never = [ds dataTaskWithURL:U(@"/hello")];
    [never cancel];
    [w wait];
    CHECK(w.completedError.code == NSURLErrorCancelled);
    NSURLSessionDataTask *during = [ds dataTaskWithURL:U(@"/slow")];
    [during resume];
    usleep(200000);
    [during cancel];
    [w wait];
    CHECK(w.completedError.code == NSURLErrorCancelled);

    /* WebSockets: open, the server's greeting, echo (fragmented text and
     * binary), ping, and a close from the server */
    NSString *wsBase = [base stringByReplacingOccurrencesOfString:@"http:" withString:@"ws:"];
    NSURLSessionWebSocketTask *ws = [ds webSocketTaskWithURL:[NSURL URLWithString:[wsBase stringByAppendingString:@"/ws"]]
                                                   protocols:@[@"chat", @"other"]];
    [ws resume];
    NSError *we = nil;
    NSURLSessionWebSocketMessage *m = receive(ws, &we);
    CHECK(m && m.type == NSURLSessionWebSocketMessageTypeString && [m.string isEqual:@"welcome"]);
    CHECK([w.openedProtocol isEqual:@"chat"] && ((NSHTTPURLResponse *)ws.response).statusCode == 101);
    __block NSError *sendErr = (id)@"unset";
    dispatch_semaphore_t sent = dispatch_semaphore_create(0);
    [ws sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:@"echo me"] completionHandler:^(NSError *err) {
        sendErr = err;
        dispatch_semaphore_signal(sent);
    }];
    dispatch_semaphore_wait(sent, DISPATCH_TIME_FOREVER);
    CHECK(sendErr == nil);
    m = receive(ws, &we);
    CHECK([m.string isEqual:@"echo me"]);
    [ws sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithData:[NSData dataWithBytes:"\x01\x02" length:2]]
        completionHandler:^(NSError *err) {}];
    m = receive(ws, &we);
    CHECK(m.type == NSURLSessionWebSocketMessageTypeData && m.data.length == 2 && ((const char *)m.data.bytes)[1] == 2);
    __block int pongs = 0;
    dispatch_semaphore_t ponged = dispatch_semaphore_create(0);
    [ws sendPingWithPongReceiveHandler:^(NSError *err) {
        if (!err) pongs++;
        dispatch_semaphore_signal(ponged);
    }];
    CHECK(dispatch_semaphore_wait(ponged, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0 && pongs == 1);
    [ws sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:@"close please"] completionHandler:^(NSError *err) {}];
    [w wait];
    CHECK(w.closeCode == 4000 && [text(ws.closeReason) isEqual:@"bye"]);
    m = receive(ws, &we);
    CHECK(!m && we);

    /* WebSocket to nothing */
    NSURLSessionWebSocketTask *nows = [ds webSocketTaskWithURL:[NSURL URLWithString:@"ws://127.0.0.1:1/"]];
    [nows resume];
    [w wait];
    CHECK(w.completedError.code == NSURLErrorCannotConnectToHost);

    /* invalidation */
    [ds finishTasksAndInvalidate];
    [stdinPipe.fileHandleForWriting closeFile];
    [server waitUntilExit];
    printf("urlsession ok\n");
    return 0;
}
