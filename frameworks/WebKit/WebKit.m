/* WebKit without a browser engine (see the header). */
#import <WebKit/WebKit.h>
#include <CoreText/CoreText.h>
#include <dispatch/dispatch.h>
#include <stdlib.h>

NSString *const WKErrorDomain = @"WKErrorDomain";

/* ---- HTML to text ---- */

/* The first occurrence of `needle` at or after `from`. */
static NSRange find(NSString *s, NSString *needle, NSUInteger from, NSUInteger limit, NSStringCompareOptions opts) {
    if (from >= s.length) return NSMakeRange(NSNotFound, 0);
    NSUInteger len = MIN(limit, s.length - from);
    NSRange r = [[s substringWithRange:NSMakeRange(from, len)] rangeOfString:needle options:opts];
    if (r.location != NSNotFound) r.location += from;
    return r;
}

static NSString *entity(NSString *name) {
    static NSDictionary *named;
    if (!named) named = @{@"amp": @"&", @"lt": @"<", @"gt": @">", @"quot": @"\"", @"apos": @"'", @"nbsp": @" ",
                          @"mdash": @"—", @"ndash": @"–", @"hellip": @"…", @"copy": @"©",
                          @"bull": @"•", @"rsquo": @"’", @"lsquo": @"‘", @"rdquo": @"”",
                          @"ldquo": @"“"};
    if ([name hasPrefix:@"#"]) {
        BOOL hex = name.length > 1 && ([name characterAtIndex:1] == 'x' || [name characterAtIndex:1] == 'X');
        NSString *digits = [name substringFromIndex:hex ? 2 : 1];
        if (!digits.length) return nil;
        unsigned long v = 0;
        for (NSUInteger k = 0; k < digits.length; k++) {
            unichar d = [digits characterAtIndex:k];
            int x = d >= '0' && d <= '9' ? d - '0' : hex && d >= 'a' && d <= 'f' ? d - 'a' + 10 :
                    hex && d >= 'A' && d <= 'F' ? d - 'A' + 10 : -1;
            if (x < 0 || v > 0x10ffff) return nil;
            v = v * (hex ? 16 : 10) + (unsigned long)x;
        }
        unichar c = (unichar)v;
        return v < 0x10000 ? [NSString stringWithCharacters:&c length:1] : @"?";
    }
    return named[name.lowercaseString];
}

/* The text of an HTML document: scripts, styles and heads dropped, block
 * elements on lines of their own, list items bulleted, spaces collapsed. */
NSString *bn_html_text(NSString *html) {
    if (!html) return @"";
    static NSSet *blocks;
    if (!blocks) blocks = [NSSet setWithArray:@[@"p", @"div", @"br", @"li", @"ul", @"ol", @"h1", @"h2", @"h3", @"h4",
                                                @"h5", @"h6", @"tr", @"table", @"section", @"article", @"header",
                                                @"footer", @"blockquote", @"pre", @"hr", @"dt", @"dd"]];
    NSMutableString *out = [NSMutableString string];
    NSUInteger n = html.length, i = 0;
    NSString *skipUntil = nil;
    BOOL space = NO;
    while (i < n) {
        unichar c = [html characterAtIndex:i];
        if (c == '<') {
            NSRange end = find(html, @">", i, n - i, 0);
            if (end.location == NSNotFound) break;
            NSString *tag = [[html substringWithRange:NSMakeRange(i + 1, end.location - i - 1)] lowercaseString];
            i = end.location + 1;
            BOOL closing = [tag hasPrefix:@"/"];
            NSString *name = closing ? [tag substringFromIndex:1] : tag;
            NSRange ws = [name rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (ws.location != NSNotFound) name = [name substringToIndex:ws.location];
            if ([name hasSuffix:@"/"]) name = [name substringToIndex:name.length - 1];
            if (skipUntil) {
                if (closing && [name isEqualToString:skipUntil]) skipUntil = nil;
                continue;
            }
            if (!closing && ([name isEqualToString:@"script"] || [name isEqualToString:@"style"] ||
                             [name isEqualToString:@"head"] || [name isEqualToString:@"title"])) {
                skipUntil = name;
                continue;
            }
            if ([blocks containsObject:name]) {
                while ([out hasSuffix:@" "]) [out deleteCharactersInRange:NSMakeRange(out.length - 1, 1)];
                if (out.length && ![out hasSuffix:@"\n"]) [out appendString:@"\n"];
                if (!closing && [name isEqualToString:@"li"]) [out appendString:@"• "];
                space = NO;
            }
            continue;
        }
        i++;
        if (skipUntil) continue;
        NSString *piece;
        if (c == '&') {
            NSRange semi = find(html, @";", i, 10, 0);
            NSString *decoded = semi.location != NSNotFound ? entity([html substringWithRange:NSMakeRange(i, semi.location - i)]) : nil;
            if (decoded) { piece = decoded; i = semi.location + 1; }
            else piece = @"&";
        } else if (c == ' ' || c == '\n' || c == '\t' || c == '\r') {
            space = out.length && ![out hasSuffix:@"\n"];
            continue;
        } else {
            piece = [NSString stringWithCharacters:&c length:1];
        }
        if (space) [out appendString:@" "];
        space = NO;
        [out appendString:piece];
    }
    while ([out hasSuffix:@"\n"] || [out hasSuffix:@" "]) [out deleteCharactersInRange:NSMakeRange(out.length - 1, 1)];
    return out;
}

static NSString *html_title(NSString *html) {
    NSRange a = [html rangeOfString:@"<title>" options:NSCaseInsensitiveSearch];
    if (a.location == NSNotFound) return nil;
    NSRange b = find(html, @"</title>", NSMaxRange(a), html.length - NSMaxRange(a), NSCaseInsensitiveSearch);
    if (b.location == NSNotFound) return nil;
    return bn_html_text([html substringWithRange:NSMakeRange(NSMaxRange(a), b.location - NSMaxRange(a))]);
}

/* Text in a view's bounds from the top, wrapped at words, with CoreText. */
static void draw_text(NSString *text, NSRect bounds, BOOL flipped, BOOL background) {
    CGContextRef ctx = [NSGraphicsContext currentContext].CGContext;
    if (!ctx) return;
    if (background) {
        CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
        CGContextFillRect(ctx, bounds);
    }
    if (!text.length) return;
    CTFontRef font = CTFontCreateWithName((__bridge CFStringRef)@"Helvetica", 13, NULL);
    CGColorRef black = CGColorCreateGenericGray(0.1, 1);
    NSDictionary *attrs = @{(__bridge id)kCTFontAttributeName: (__bridge id)font,
                            (__bridge id)kCTForegroundColorAttributeName: (__bridge id)black};
    CGFloat ascent = CTFontGetAscent(font), lineHeight = ascent + CTFontGetDescent(font) + 4, margin = 12;
    CGFloat width = bounds.size.width - 2 * margin, y = margin;
    CGContextSaveGState(ctx);
    if (flipped) CGContextSetTextMatrix(ctx, CGAffineTransformMakeScale(1, -1));
    else CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
    for (NSString *para in [text componentsSeparatedByString:@"\n"]) {
        NSArray *words = [para componentsSeparatedByString:@" "];
        NSMutableString *line = [NSMutableString string];
        NSUInteger w = 0;
        while (w <= words.count) {
            NSString *candidate = w < words.count ? (line.length ? [line stringByAppendingFormat:@" %@", words[w]] : words[w]) : nil;
            CTLineRef probe = NULL;
            double cw = 0;
            if (candidate) {
                CFAttributedStringRef as = CFAttributedStringCreate(NULL, (__bridge CFStringRef)candidate, (__bridge CFDictionaryRef)attrs);
                probe = CTLineCreateWithAttributedString(as);
                cw = CTLineGetTypographicBounds(probe, NULL, NULL, NULL);
                CFRelease(as);
                CFRelease(probe);
            }
            if (candidate && (cw <= width || !line.length)) {
                [line setString:candidate];
                w++;
                continue;
            }
            CFAttributedStringRef as = CFAttributedStringCreate(NULL, (__bridge CFStringRef)line, (__bridge CFDictionaryRef)attrs);
            CTLineRef l = CTLineCreateWithAttributedString(as);
            CGFloat baseline = flipped ? bounds.origin.y + y + ascent : NSMaxY(bounds) - y - ascent;
            CGContextSetTextPosition(ctx, bounds.origin.x + margin, baseline);
            CTLineDraw(l, ctx);
            CFRelease(l);
            CFRelease(as);
            y += lineHeight;
            [line setString:@""];
            if (!candidate) break;
            if (y > bounds.size.height) break;
        }
        if (y > bounds.size.height) break;
    }
    CGContextRestoreGState(ctx);
    CGColorRelease(black);
    CFRelease(font);
}

static NSError *unsupported(NSURL *url) {
    return [NSError errorWithDomain:NSURLErrorDomain code:-1002 /* NSURLErrorUnsupportedURL */
                           userInfo:@{NSLocalizedDescriptionKey: @"bitten's WebKit loads HTML strings and file URLs only",
                                      NSURLErrorFailingURLErrorKey: url ?: [NSNull null]}];
}

/* ---- WKWebView and its parts ---- */

@implementation WKUserScript
- (instancetype)initWithSource:(NSString *)source injectionTime:(WKUserScriptInjectionTime)time forMainFrameOnly:(BOOL)main {
    if ((self = [super init])) { _source = [source copy]; _injectionTime = time; _forMainFrameOnly = main; }
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@implementation WKContentRuleList
- (instancetype)initWithBNIdentifier:(NSString *)identifier {
    if ((self = [super init])) _identifier = [identifier copy] ?: @"";
    return self;
}
@end

@implementation WKContentRuleListStore {
    NSMutableDictionary<NSString *, WKContentRuleList *> *_lists;
}
+ (instancetype)defaultStore {
    static WKContentRuleListStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [WKContentRuleListStore new]; });
    return store;
}
+ (instancetype)storeWithURL:(NSURL *)url { return [WKContentRuleListStore new]; }
- (instancetype)init {
    if ((self = [super init])) _lists = [NSMutableDictionary dictionary];
    return self;
}
/* Rules are JSON: compiled means parsed and kept (they filter nothing). */
- (void)compileContentRuleListForIdentifier:(NSString *)identifier encodedContentRuleList:(NSString *)encoded
                          completionHandler:(void (^)(WKContentRuleList *, NSError *))handler {
    NSData *data = [encoded dataUsingEncoding:NSUTF8StringEncoding];
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    WKContentRuleList *list = nil;
    NSError *error = nil;
    if ([json isKindOfClass:[NSArray class]]) {
        list = [[WKContentRuleList alloc] initWithBNIdentifier:identifier];
        @synchronized(self) { _lists[identifier ?: @""] = list; }
    } else {
        error = [NSError errorWithDomain:WKErrorDomain code:6 /* WKErrorContentRuleListStoreCompileFailed */
                                userInfo:@{NSLocalizedDescriptionKey: @"Rule list compilation failed: not a JSON array"}];
    }
    if (handler) dispatch_async(dispatch_get_main_queue(), ^{ handler(list, error); });
}
- (void)lookUpContentRuleListForIdentifier:(NSString *)identifier
                         completionHandler:(void (^)(WKContentRuleList *, NSError *))handler {
    WKContentRuleList *list;
    @synchronized(self) { list = _lists[identifier ?: @""]; }
    NSError *error = list ? nil : [NSError errorWithDomain:WKErrorDomain code:7 userInfo:nil];
    if (handler) dispatch_async(dispatch_get_main_queue(), ^{ handler(list, error); });
}
- (void)removeContentRuleListForIdentifier:(NSString *)identifier completionHandler:(void (^)(NSError *))handler {
    @synchronized(self) { [_lists removeObjectForKey:identifier ?: @""]; }
    if (handler) dispatch_async(dispatch_get_main_queue(), ^{ handler(nil); });
}
@end

@implementation WKUserContentController {
    NSMutableArray<WKUserScript *> *_scripts;
    NSMutableArray<WKContentRuleList *> *_rules;
    NSMutableDictionary<NSString *, id> *_handlers;
}
- (instancetype)init {
    if ((self = [super init])) {
        _scripts = [NSMutableArray array];
        _rules = [NSMutableArray array];
        _handlers = [NSMutableDictionary dictionary];
    }
    return self;
}
- (NSArray<WKUserScript *> *)userScripts { return [_scripts copy]; }
- (void)addUserScript:(WKUserScript *)s { if (s) [_scripts addObject:s]; }
- (void)removeAllUserScripts { [_scripts removeAllObjects]; }
- (void)addContentRuleList:(WKContentRuleList *)l { if (l) [_rules addObject:l]; }
- (void)removeContentRuleList:(WKContentRuleList *)l { [_rules removeObject:l]; }
- (void)removeAllContentRuleLists { [_rules removeAllObjects]; }
- (void)addScriptMessageHandler:(id<WKScriptMessageHandler>)h name:(NSString *)name { if (h && name) _handlers[name] = h; }
- (void)removeScriptMessageHandlerForName:(NSString *)name { if (name) [_handlers removeObjectForKey:name]; }
@end

@implementation WKPreferences
- (instancetype)init {
    if ((self = [super init])) _javaScriptEnabled = YES;
    return self;
}
@end

@implementation WKWebViewConfiguration
- (instancetype)init {
    if ((self = [super init])) {
        _userContentController = [WKUserContentController new];
        _preferences = [WKPreferences new];
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone {
    WKWebViewConfiguration *c = [WKWebViewConfiguration new];
    c.userContentController = _userContentController;
    c.preferences = _preferences;
    c.applicationNameForUserAgent = _applicationNameForUserAgent;
    return c;
}
@end

@implementation WKNavigation
@end
@implementation WKNavigationAction
- (NSURLRequest *)request { return nil; }
- (WKNavigationType)navigationType { return WKNavigationTypeOther; }
@end

@interface WKWebView ()
- (WKNavigation *)_bn_loadURL:(NSURL *)url;
@end

@implementation WKWebView {
    WKWebViewConfiguration *_config;
    NSString *_text, *_title;
    NSURL *_url;
    BOOL _drawsBackground;
}
@synthesize navigationDelegate = _navigationDelegate, UIDelegate = _UIDelegate, customUserAgent = _customUserAgent,
            allowsBackForwardNavigationGestures = _allowsBackForwardNavigationGestures,
            allowsMagnification = _allowsMagnification;
- (instancetype)initWithFrame:(NSRect)frame configuration:(WKWebViewConfiguration *)configuration {
    if ((self = [super initWithFrame:frame])) {
        _config = [configuration copy] ?: [WKWebViewConfiguration new];
        _text = @"";
        _drawsBackground = YES;
    }
    return self;
}
- (instancetype)initWithFrame:(NSRect)frame { return [self initWithFrame:frame configuration:[WKWebViewConfiguration new]]; }
- (WKWebViewConfiguration *)configuration { return [_config copy]; }
- (NSString *)title { return _title; }
- (NSURL *)URL { return _url; }
- (BOOL)isLoading { return NO; }
- (double)estimatedProgress { return 1; }
- (NSString *)_bn_text { return _text; }
- (void)setDrawsBackground:(BOOL)d { _drawsBackground = d; }
- (void)_setDrawsBackground:(BOOL)d { _drawsBackground = d; }
- (BOOL)drawsBackground { return _drawsBackground; }
- (BOOL)isFlipped { return YES; }

- (WKNavigation *)_bn_show:(NSString *)html url:(NSURL *)url {
    _text = bn_html_text(html);
    _title = html_title(html);
    _url = url;
    [self setNeedsDisplay:YES];
    WKNavigation *nav = [WKNavigation new];
    dispatch_async(dispatch_get_main_queue(), ^{
        id<WKNavigationDelegate> d = self.navigationDelegate;
        if ([d respondsToSelector:@selector(webView:didStartProvisionalNavigation:)]) [d webView:self didStartProvisionalNavigation:nav];
        if ([d respondsToSelector:@selector(webView:didCommitNavigation:)]) [d webView:self didCommitNavigation:nav];
        if ([d respondsToSelector:@selector(webView:didFinishNavigation:)]) [d webView:self didFinishNavigation:nav];
    });
    return nav;
}
- (WKNavigation *)_bn_fail:(NSURL *)url {
    WKNavigation *nav = [WKNavigation new];
    NSError *e = unsupported(url);
    dispatch_async(dispatch_get_main_queue(), ^{
        id<WKNavigationDelegate> d = self.navigationDelegate;
        if ([d respondsToSelector:@selector(webView:didFailProvisionalNavigation:withError:)])
            [d webView:self didFailProvisionalNavigation:nav withError:e];
    });
    return nav;
}
- (WKNavigation *)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL { return [self _bn_show:string url:baseURL]; }
- (WKNavigation *)loadData:(NSData *)data MIMEType:(NSString *)mime characterEncodingName:(NSString *)enc baseURL:(NSURL *)baseURL {
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if (![mime containsString:@"html"]) s = [[s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"]
                                              stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    return [self _bn_show:s url:baseURL];
}
- (WKNavigation *)loadRequest:(NSURLRequest *)request {
    NSURL *url = [(id)request URL];
    return [self _bn_loadURL:url];
}
- (WKNavigation *)_bn_loadURL:(NSURL *)url {
    if (url.isFileURL) {
        NSString *s = [NSString stringWithContentsOfFile:url.path encoding:NSUTF8StringEncoding error:NULL];
        if (s) return [self _bn_show:s url:url];
    }
    return [self _bn_fail:url];
}
- (WKNavigation *)loadFileURL:(NSURL *)url allowingReadAccessToURL:(NSURL *)readAccessURL {
    return [self _bn_loadURL:url];
}
- (void)stopLoading {}
- (WKNavigation *)reload { return _url ? [self _bn_loadURL:_url] : nil; }
- (void)evaluateJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))handler {
    if (!handler) return;
    NSError *e = [NSError errorWithDomain:WKErrorDomain code:WKErrorJavaScriptExceptionOccurred
                                 userInfo:@{NSLocalizedDescriptionKey: @"No JavaScript engine in bitten's WebKit"}];
    dispatch_async(dispatch_get_main_queue(), ^{ handler(nil, e); });
}
- (void)drawRect:(NSRect)dirty { draw_text(_text, self.bounds, YES, _drawsBackground); }
@end

/* ---- the legacy WebView ---- */

@implementation WebPreferences
+ (WebPreferences *)standardPreferences {
    static WebPreferences *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [[WebPreferences alloc] initWithIdentifier:@"WebPreferences"]; });
    return p;
}
- (instancetype)initWithIdentifier:(NSString *)identifier {
    if ((self = [super init])) {
        _identifier = [identifier copy] ?: @"";
        _javaScriptEnabled = YES;
    }
    return self;
}
- (instancetype)init { return [self initWithIdentifier:nil]; }
@end

@interface WebFrame ()
@property (readwrite, weak) WebView *webView;
@end

@interface WebView ()
- (void)_bn_show:(NSString *)html;
- (void)_bn_fail:(NSURL *)url;
@end

@implementation WebFrame
- (void)loadHTMLString:(NSString *)string baseURL:(NSURL *)URL { [self.webView _bn_show:string]; }
- (void)loadRequest:(NSURLRequest *)request {
    NSURL *url = [(id)request URL];
    NSString *s = url.isFileURL ? [NSString stringWithContentsOfFile:url.path encoding:NSUTF8StringEncoding error:NULL] : nil;
    if (s) [self.webView _bn_show:s];
    else [self.webView _bn_fail:url];
}
- (void)stopLoading {}
- (void)reload {}
@end

@implementation WebView {
    WebFrame *_frame;
    WebPreferences *_prefs;
    NSString *_text;
}
@synthesize frameLoadDelegate = _frameLoadDelegate, policyDelegate = _policyDelegate, UIDelegate = _UIDelegate,
            resourceLoadDelegate = _resourceLoadDelegate, drawsBackground = _drawsBackground;
- (instancetype)initWithFrame:(NSRect)frame frameName:(NSString *)frameName groupName:(NSString *)groupName {
    if ((self = [super initWithFrame:frame])) {
        _frame = [WebFrame new];
        _frame.webView = self;
        _text = @"";
        _drawsBackground = YES;
    }
    return self;
}
- (instancetype)initWithFrame:(NSRect)frame { return [self initWithFrame:frame frameName:nil groupName:nil]; }
- (WebFrame *)mainFrame { return _frame; }
- (WebPreferences *)preferences { return _prefs ?: [WebPreferences standardPreferences]; }
- (void)setPreferences:(WebPreferences *)p { _prefs = p; }
- (NSString *)_bn_text { return _text; }
- (void)_setDrawsBackground:(BOOL)d { _drawsBackground = d; }
- (BOOL)isFlipped { return YES; }
- (void)stopLoading:(id)sender {}
- (void)_bn_show:(NSString *)html {
    _text = bn_html_text(html);
    [self setNeedsDisplay:YES];
    WebFrame *frame = _frame;
    dispatch_async(dispatch_get_main_queue(), ^{
        id d = self.frameLoadDelegate;
        if ([d respondsToSelector:@selector(webView:didFinishLoadForFrame:)])
            ((void (*)(id, SEL, id, id))[d methodForSelector:@selector(webView:didFinishLoadForFrame:)])(
                d, @selector(webView:didFinishLoadForFrame:), self, frame);
    });
}
- (void)_bn_fail:(NSURL *)url {
    WebFrame *frame = _frame;
    NSError *e = unsupported(url);
    dispatch_async(dispatch_get_main_queue(), ^{
        id d = self.frameLoadDelegate;
        SEL sel = @selector(webView:didFailProvisionalLoadWithError:forFrame:);
        if ([d respondsToSelector:sel])
            ((void (*)(id, SEL, id, id, id))[d methodForSelector:sel])(d, sel, self, e, frame);
    });
}
- (void)drawRect:(NSRect)dirty { draw_text(_text, self.bounds, YES, _drawsBackground); }
@end
