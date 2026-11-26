// WebKit without an engine: HTML to text, navigation delegates, content
// rule lists, user scripts, the legacy WebView, and drawing.
#import <WebKit/WebKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

static BOOL spin(BOOL (^done)(void)) {
    for (int i = 0; i < 300 && !done(); i++)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return done();
}

@interface Nav : NSObject <WKNavigationDelegate>
@property int finished, failed;
@end
@implementation Nav
- (void)webView:(WKWebView *)w didFinishNavigation:(WKNavigation *)n { self.finished++; }
- (void)webView:(WKWebView *)w didFailProvisionalNavigation:(WKNavigation *)n withError:(NSError *)e { self.failed++; }
@end

@interface Legacy : NSObject
@property int loaded;
@end
@implementation Legacy
- (void)webView:(WebView *)v didFinishLoadForFrame:(WebFrame *)f { self.loaded++; }
@end

int main(void) {
    @autoreleasepool {
        WKWebViewConfiguration *config = [WKWebViewConfiguration new];
        WKUserScript *script = [[WKUserScript alloc] initWithSource:@"document.body.style.color='red'"
                                                      injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                   forMainFrameOnly:YES];
        [config.userContentController addUserScript:script];
        CHECK(config.userContentController.userScripts.count == 1);
        __block WKContentRuleList *rules = nil;
        __block NSError *ruleError = nil;
        [[WKContentRuleListStore defaultStore] compileContentRuleListForIdentifier:@"block"
            encodedContentRuleList:@"[{\"trigger\":{\"url-filter\":\".*\"},\"action\":{\"type\":\"block\"}}]"
            completionHandler:^(WKContentRuleList *l, NSError *e) { rules = l; }];
        [[WKContentRuleListStore defaultStore] compileContentRuleListForIdentifier:@"bad" encodedContentRuleList:@"{"
            completionHandler:^(WKContentRuleList *l, NSError *e) { ruleError = e; }];
        CHECK(spin(^{ return (BOOL)(rules != nil && ruleError != nil); }));
        CHECK([rules.identifier isEqualToString:@"block"]);
        [config.userContentController addContentRuleList:rules];

        WKWebView *web = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200) configuration:config];
        Nav *nav = [Nav new];
        web.navigationDelegate = nav;
        [web setValue:@NO forKey:@"drawsBackground"];
        [web loadHTMLString:@"<html><head><title>Release &amp; notes</title><style>p{}</style></head>"
                             "<body><h1>Version 2</h1><p>Fixed   a <b>crash</b> &lt;sometimes&gt;.</p>"
                             "<ul><li>One</li><li>Two&#33;</li></ul><script>alert(1)</script></body></html>"
                    baseURL:nil];
        CHECK([web._bn_text isEqualToString:@"Version 2\nFixed a crash <sometimes>.\n• One\n• Two!"]);
        CHECK([web.title isEqualToString:@"Release & notes"]);
        CHECK(spin(^{ return (BOOL)(nav.finished == 1); }));
        __block NSError *jsError = nil;
        [web evaluateJavaScript:@"1+1" completionHandler:^(id r, NSError *e) { jsError = e; }];
        CHECK(spin(^{ return (BOOL)(jsError != nil); }));
        NSString *path = [NSString stringWithFormat:@"/tmp/bitten-webkit-%d.html", getpid()];
        [@"<p>From a file</p>" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [web loadFileURL:[NSURL fileURLWithPath:path] allowingReadAccessToURL:[NSURL fileURLWithPath:@"/tmp"]];
        CHECK([web._bn_text isEqualToString:@"From a file"]);
        CHECK(spin(^{ return (BOOL)(nav.finished == 2); }));
        [web loadFileURL:[NSURL fileURLWithPath:@"/nonexistent.html"] allowingReadAccessToURL:[NSURL fileURLWithPath:@"/"]];
        CHECK(spin(^{ return (BOOL)(nav.failed == 1); }));

        /* Drawing: text reaches the bitmap. */
        [web loadHTMLString:@"<p>Ink ink ink ink</p>" baseURL:nil];
        uint8_t *px = calloc(300 * 200, 4);
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGContextRef cg = CGBitmapContextCreate(px, 300, 200, 8, 300 * 4, rgb, kCGImageAlphaPremultipliedLast);
        CGContextTranslateCTM(cg, 0, 200);
        CGContextScaleCTM(cg, 1, -1);
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:cg flipped:YES]];
        [web drawRect:web.bounds];
        int ink = 0;
        for (int i = 0; i < 300 * 200; i++) if (px[i * 4 + 3] > 100) ink++;
        CHECK(ink > 30);

        /* the legacy WebView */
        WebView *old = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100) frameName:nil groupName:nil];
        Legacy *legacy = [Legacy new];
        old.frameLoadDelegate = legacy;
        WebPreferences *prefs = [[WebPreferences alloc] initWithIdentifier:@"x"];
        prefs.javaScriptEnabled = NO;
        prefs.plugInsEnabled = NO;
        old.preferences = prefs;
        CHECK(!old.preferences.isJavaScriptEnabled);
        [old.mainFrame loadHTMLString:@"<div>Hello<br>there</div>" baseURL:nil];
        CHECK([old._bn_text isEqualToString:@"Hello\nthere"]);
        CHECK(spin(^{ return (BOOL)(legacy.loaded == 1); }));
        [old stopLoading:nil];
    }
    printf("webkit ok\n");
    return 0;
}
