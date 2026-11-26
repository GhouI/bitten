/* Foundation's URL loading: requests and responses, cookies, and
 * URLSession with its data, upload, download and WebSocket tasks.
 *
 * A task runs on a background queue. HTTP, HTTPS, file and FTP transfers
 * go to the host's libcurl (bitten_http_perform, src/frameworks/urlsession);
 * data: URLs are decoded here. Redirects are followed here, one hop at a
 * time, so the delegate can see and change them; cookies are added from
 * and stored to the session's cookie storage. Everything the app sees
 * (completion handlers and delegate calls) runs on the session's delegate
 * queue, in order. WebSocket tasks keep a reader running from the opening
 * handshake until the connection closes, queueing messages for receive. */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>
#include <unistd.h>

#include "bn_http.h"

const int64_t NSURLSessionTransferSizeUnknown = -1LL;
const float NSURLSessionTaskPriorityDefault = 0.5f, NSURLSessionTaskPriorityLow = 0.25f,
            NSURLSessionTaskPriorityHigh = 0.75f;
NSString *const NSURLErrorBackgroundTaskCancelledReasonKey = @"NSURLErrorBackgroundTaskCancelledReasonKey";
NSString *const NSURLSessionDownloadTaskResumeData = @"NSURLSessionDownloadTaskResumeData";
NSString *const NSURLErrorNetworkUnavailableReasonKey = @"NSURLErrorNetworkUnavailableReasonKey";
NSString *const NSURLProtectionSpaceHTTP = @"http", *const NSURLProtectionSpaceHTTPS = @"https";
NSString *const NSURLAuthenticationMethodDefault = @"NSURLAuthenticationMethodDefault";
NSString *const NSURLAuthenticationMethodHTTPBasic = @"NSURLAuthenticationMethodHTTPBasic";
NSString *const NSURLAuthenticationMethodHTTPDigest = @"NSURLAuthenticationMethodHTTPDigest";
NSString *const NSURLAuthenticationMethodServerTrust = @"NSURLAuthenticationMethodServerTrust";
NSString *const NSURLAuthenticationMethodClientCertificate = @"NSURLAuthenticationMethodClientCertificate";
NSHTTPCookiePropertyKey const NSHTTPCookieName = @"Name", NSHTTPCookieValue = @"Value", NSHTTPCookieDomain = @"Domain",
                              NSHTTPCookiePath = @"Path", NSHTTPCookieExpires = @"Expires", NSHTTPCookieSecure = @"Secure",
                              NSHTTPCookieMaximumAge = @"Max-Age", NSHTTPCookieOriginURL = @"OriginURL",
                              NSHTTPCookieVersion = @"Version";

/* ---- headers ---- */

/* The value of a header, its name matched without regard to case. */
static NSString *header_in(NSDictionary *h, NSString *name) {
    NSString *v = h[name];
    if (v) return v;
    for (NSString *k in h)
        if ([k caseInsensitiveCompare:name] == NSOrderedSame) return h[k];
    return nil;
}
static NSString *header_key_in(NSDictionary *h, NSString *name) {
    for (NSString *k in h)
        if ([k caseInsensitiveCompare:name] == NSOrderedSame) return k;
    return nil;
}

/* ---- requests ---- */

@implementation NSURLRequest {
@protected
    NSURL *_URL, *_mainDocumentURL;
    NSURLRequestCachePolicy _cachePolicy;
    NSTimeInterval _timeoutInterval;
    NSURLRequestNetworkServiceType _networkServiceType;
    NSURLRequestAttribution _attribution;
    NSString *_HTTPMethod;
    NSMutableDictionary<NSString *, NSString *> *_headers;
    NSData *_HTTPBody;
    BOOL _allowsCellular, _allowsExpensive, _allowsConstrained, _http3, _dnssec, _cookies, _pipelining;
}
+ (instancetype)requestWithURL:(NSURL *)u { return [[self alloc] initWithURL:u]; }
+ (instancetype)requestWithURL:(NSURL *)u cachePolicy:(NSURLRequestCachePolicy)p timeoutInterval:(NSTimeInterval)t {
    return [[self alloc] initWithURL:u cachePolicy:p timeoutInterval:t];
}
- (instancetype)init { return [self initWithURL:(NSURL *_Nonnull)nil]; }
- (instancetype)initWithURL:(NSURL *)u { return [self initWithURL:u cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:60]; }
- (instancetype)initWithURL:(NSURL *)u cachePolicy:(NSURLRequestCachePolicy)p timeoutInterval:(NSTimeInterval)t {
    if ((self = [super init])) {
        _URL = [u copy];
        _cachePolicy = p;
        _timeoutInterval = t;
        _HTTPMethod = @"GET";
        _headers = [NSMutableDictionary dictionary];
        _allowsCellular = _allowsExpensive = _allowsConstrained = _cookies = YES;
    }
    return self;
}
- (void)_bn_copyInto:(NSURLRequest *)r {
    r->_URL = _URL;
    r->_mainDocumentURL = _mainDocumentURL;
    r->_cachePolicy = _cachePolicy;
    r->_timeoutInterval = _timeoutInterval;
    r->_networkServiceType = _networkServiceType;
    r->_attribution = _attribution;
    r->_HTTPMethod = _HTTPMethod;
    r->_headers = [NSMutableDictionary dictionaryWithDictionary:_headers];
    r->_HTTPBody = _HTTPBody;
    r->_allowsCellular = _allowsCellular;
    r->_allowsExpensive = _allowsExpensive;
    r->_allowsConstrained = _allowsConstrained;
    r->_http3 = _http3;
    r->_dnssec = _dnssec;
    r->_cookies = _cookies;
    r->_pipelining = _pipelining;
}
- (id)copyWithZone:(NSZone *)zone {
    if ([self isMemberOfClass:[NSURLRequest class]]) return self;
    NSURLRequest *r = [[NSURLRequest alloc] initWithURL:_URL];
    [self _bn_copyInto:r];
    return r;
}
- (id)mutableCopyWithZone:(NSZone *)zone {
    NSMutableURLRequest *r = [[NSMutableURLRequest alloc] initWithURL:_URL];
    [self _bn_copyInto:r];
    return r;
}
- (NSURL *)URL { return _URL; }
- (NSURLRequestCachePolicy)cachePolicy { return _cachePolicy; }
- (NSTimeInterval)timeoutInterval { return _timeoutInterval; }
- (NSURL *)mainDocumentURL { return _mainDocumentURL; }
- (NSURLRequestNetworkServiceType)networkServiceType { return _networkServiceType; }
- (BOOL)allowsCellularAccess { return _allowsCellular; }
- (BOOL)allowsExpensiveNetworkAccess { return _allowsExpensive; }
- (BOOL)allowsConstrainedNetworkAccess { return _allowsConstrained; }
- (BOOL)assumesHTTP3Capable { return _http3; }
- (NSURLRequestAttribution)attribution { return _attribution; }
- (BOOL)requiresDNSSECValidation { return _dnssec; }
- (NSString *)HTTPMethod { return _HTTPMethod; }
- (NSDictionary<NSString *, NSString *> *)allHTTPHeaderFields { return _headers.count ? [_headers copy] : nil; }
- (NSString *)valueForHTTPHeaderField:(NSString *)f { return header_in(_headers, f); }
- (NSData *)HTTPBody { return _HTTPBody; }
- (BOOL)HTTPShouldHandleCookies { return _cookies; }
- (BOOL)HTTPShouldUsePipelining { return _pipelining; }
- (BOOL)isEqual:(id)o {
    if (![o isKindOfClass:[NSURLRequest class]]) return NO;
    NSURLRequest *r = o;
    return (r->_URL == _URL || [r->_URL isEqual:_URL]) && [r->_HTTPMethod isEqual:_HTTPMethod] &&
           [r->_headers isEqual:_headers] && (r->_HTTPBody == _HTTPBody || [r->_HTTPBody isEqual:_HTTPBody]) &&
           r->_cachePolicy == _cachePolicy && r->_timeoutInterval == _timeoutInterval;
}
- (NSUInteger)hash { return _URL.hash ^ _HTTPMethod.hash; }
- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p> { URL: %@ }", [self class], (void *)self, _URL.absoluteString];
}
@end

@implementation NSMutableURLRequest
@dynamic URL, cachePolicy, timeoutInterval, mainDocumentURL, networkServiceType, allowsCellularAccess,
    allowsExpensiveNetworkAccess, allowsConstrainedNetworkAccess, assumesHTTP3Capable, attribution,
    requiresDNSSECValidation, HTTPMethod, allHTTPHeaderFields, HTTPBody, HTTPShouldHandleCookies, HTTPShouldUsePipelining;
- (id)copyWithZone:(NSZone *)zone {
    NSURLRequest *r = [[NSURLRequest alloc] initWithURL:_URL];
    [self _bn_copyInto:r];
    return r;
}
- (void)setURL:(NSURL *)u { _URL = [u copy]; }
- (void)setCachePolicy:(NSURLRequestCachePolicy)p { _cachePolicy = p; }
- (void)setTimeoutInterval:(NSTimeInterval)t { _timeoutInterval = t; }
- (void)setMainDocumentURL:(NSURL *)u { _mainDocumentURL = [u copy]; }
- (void)setNetworkServiceType:(NSURLRequestNetworkServiceType)t { _networkServiceType = t; }
- (void)setAllowsCellularAccess:(BOOL)b { _allowsCellular = b; }
- (void)setAllowsExpensiveNetworkAccess:(BOOL)b { _allowsExpensive = b; }
- (void)setAllowsConstrainedNetworkAccess:(BOOL)b { _allowsConstrained = b; }
- (void)setAssumesHTTP3Capable:(BOOL)b { _http3 = b; }
- (void)setAttribution:(NSURLRequestAttribution)a { _attribution = a; }
- (void)setRequiresDNSSECValidation:(BOOL)b { _dnssec = b; }
- (void)setHTTPMethod:(NSString *)m { _HTTPMethod = m.length ? [m copy] : @"GET"; }
- (void)setAllHTTPHeaderFields:(NSDictionary<NSString *, NSString *> *)h {
    _headers = [NSMutableDictionary dictionary];
    for (NSString *k in h) [self setValue:h[k] forHTTPHeaderField:k];
}
- (void)setValue:(NSString *)v forHTTPHeaderField:(NSString *)f {
    NSString *k = header_key_in(_headers, f);
    if (k) [_headers removeObjectForKey:k];
    if (v) _headers[f] = [v copy];
}
- (void)addValue:(NSString *)v forHTTPHeaderField:(NSString *)f {
    NSString *k = header_key_in(_headers, f);
    if (k) _headers[k] = [NSString stringWithFormat:@"%@,%@", _headers[k], v];
    else _headers[f] = [v copy];
}
- (void)setHTTPBody:(NSData *)b { _HTTPBody = [b copy]; }
- (void)setHTTPShouldHandleCookies:(BOOL)b { _cookies = b; }
- (void)setHTTPShouldUsePipelining:(BOOL)b { _pipelining = b; }
@end

/* ---- responses ---- */

static NSString *mime_for_extension(NSString *ext) {
    static NSDictionary *m;
    if (!m)
        m = @{@"html" : @"text/html", @"htm" : @"text/html", @"txt" : @"text/plain", @"css" : @"text/css",
              @"js" : @"text/javascript", @"json" : @"application/json", @"xml" : @"application/xml",
              @"png" : @"image/png", @"jpg" : @"image/jpeg", @"jpeg" : @"image/jpeg", @"gif" : @"image/gif",
              @"svg" : @"image/svg+xml", @"pdf" : @"application/pdf", @"zip" : @"application/zip",
              @"md" : @"text/markdown", @"csv" : @"text/csv", @"mp4" : @"video/mp4", @"mp3" : @"audio/mpeg",
              @"wasm" : @"application/wasm", @"plist" : @"application/x-plist", @"webp" : @"image/webp"};
    return m[ext.lowercaseString] ?: @"application/octet-stream";
}

@implementation NSURLResponse {
@protected
    NSURL *_URL;
    NSString *_MIMEType, *_textEncodingName;
    long long _expected;
}
- (instancetype)initWithURL:(NSURL *)u MIMEType:(NSString *)m expectedContentLength:(NSInteger)n textEncodingName:(NSString *)t {
    if ((self = [super init])) {
        _URL = [u copy];
        _MIMEType = [m copy];
        _expected = n;
        _textEncodingName = [t copy];
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSURL *)URL { return _URL; }
- (NSString *)MIMEType { return _MIMEType; }
- (long long)expectedContentLength { return _expected; }
- (NSString *)textEncodingName { return _textEncodingName; }
- (NSString *)suggestedFilename {
    NSString *name = _URL.lastPathComponent;
    if (!name.length || [name isEqual:@"/"]) name = _URL.host.length ? _URL.host : @"Unknown";
    return name;
}
- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p> { URL: %@ }", [self class], (void *)self, _URL.absoluteString];
}
@end

@implementation NSHTTPURLResponse {
    NSInteger _status;
    NSDictionary *_headers;
}
- (instancetype)initWithURL:(NSURL *)url statusCode:(NSInteger)status HTTPVersion:(NSString *)version
               headerFields:(NSDictionary<NSString *, NSString *> *)headers {
    NSString *type = header_in(headers, @"Content-Type");
    NSString *mime = nil, *charset = nil;
    if (type) {
        NSArray *parts = [type componentsSeparatedByString:@";"];
        mime = [[parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
        for (NSUInteger i = 1; i < parts.count; i++) {
            NSString *p = [parts[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([p.lowercaseString hasPrefix:@"charset="])
                charset = [[p substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
        }
    }
    NSString *len = header_in(headers, @"Content-Length");
    NSString *enc = header_in(headers, @"Content-Encoding");
    long long n = len && (!enc || [enc isEqual:@"identity"]) ? len.longLongValue : -1;
    if ((self = [super initWithURL:url MIMEType:mime expectedContentLength:(NSInteger)n textEncodingName:charset])) {
        _status = status;
        _headers = [headers copy] ?: @{};
    }
    return self;
}
- (NSInteger)statusCode { return _status; }
- (NSDictionary *)allHeaderFields { return _headers; }
- (NSString *)valueForHTTPHeaderField:(NSString *)f { return header_in(_headers, f); }
- (NSString *)suggestedFilename {
    NSString *cd = header_in(_headers, @"Content-Disposition");
    NSRange r = cd ? [cd rangeOfString:@"filename="] : NSMakeRange(NSNotFound, 0);
    if (r.location != NSNotFound) {
        NSString *name = [cd substringFromIndex:NSMaxRange(r)];
        name = [[name componentsSeparatedByString:@";"][0]
            stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\" "]];
        if (name.length) return name.lastPathComponent;
    }
    return [super suggestedFilename];
}
+ (NSString *)localizedStringForStatusCode:(NSInteger)code {
    static NSDictionary *t;
    if (!t)
        t = @{@100 : @"continue", @101 : @"switching protocols", @200 : @"no error", @201 : @"created", @202 : @"accepted",
              @203 : @"non-authoritative information", @204 : @"no content", @205 : @"reset content",
              @206 : @"partial content", @300 : @"multiple choices", @301 : @"moved permanently", @302 : @"found",
              @303 : @"see other", @304 : @"not modified", @305 : @"needs proxy", @307 : @"temporarily redirected",
              @308 : @"permanent redirect", @400 : @"bad request", @401 : @"unauthorized", @402 : @"payment required",
              @403 : @"forbidden", @404 : @"not found", @405 : @"method not allowed", @406 : @"unacceptable",
              @407 : @"proxy authentication required", @408 : @"request timed out", @409 : @"conflict",
              @410 : @"no longer exists", @411 : @"length required", @412 : @"precondition failed",
              @413 : @"request too large", @414 : @"requested URL too long", @415 : @"unsupported media type",
              @416 : @"requested range not satisfiable", @417 : @"expectation failed", @422 : @"unprocessable request",
              @429 : @"too many requests", @500 : @"internal server error", @501 : @"unimplemented",
              @502 : @"bad gateway", @503 : @"service unavailable", @504 : @"gateway timed out",
              @505 : @"unsupported version"};
    NSString *s = t[@(code)];
    if (s) return s;
    if (code >= 100 && code < 200) return @"informational";
    if (code < 300) return @"success";
    if (code < 400) return @"redirected";
    if (code < 500) return @"client error";
    return @"server error";
}
@end

/* ---- caches ---- */

@implementation NSCachedURLResponse {
    NSURLResponse *_response;
    NSData *_data;
}
- (instancetype)initWithResponse:(NSURLResponse *)r data:(NSData *)d {
    if ((self = [super init])) {
        _response = r;
        _data = [d copy];
    }
    return self;
}
- (NSURLResponse *)response { return _response; }
- (NSData *)data { return _data; }
@end

/* An in-memory cache; nothing is written to disk. Sessions do not read
 * from it on their own. */
@implementation NSURLCache {
    NSMutableDictionary<NSString *, NSCachedURLResponse *> *_entries;
    NSUInteger _usage;
}
@synthesize memoryCapacity = _memoryCapacity, diskCapacity = _diskCapacity;
static NSURLCache *sharedCache;
+ (NSURLCache *)sharedURLCache {
    @synchronized(self) {
        if (!sharedCache) sharedCache = [[NSURLCache alloc] initWithMemoryCapacity:4 << 20 diskCapacity:20 << 20 directoryURL:nil];
        return sharedCache;
    }
}
+ (void)setSharedURLCache:(NSURLCache *)c {
    @synchronized(self) { sharedCache = c; }
}
- (instancetype)initWithMemoryCapacity:(NSUInteger)m diskCapacity:(NSUInteger)d diskPath:(NSString *)p {
    return [self initWithMemoryCapacity:m diskCapacity:d directoryURL:nil];
}
- (instancetype)initWithMemoryCapacity:(NSUInteger)m diskCapacity:(NSUInteger)d directoryURL:(NSURL *)u {
    if ((self = [super init])) {
        _memoryCapacity = m;
        _diskCapacity = d;
        _entries = [NSMutableDictionary dictionary];
    }
    return self;
}
- (NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)r {
    @synchronized(self) { return r.URL ? _entries[r.URL.absoluteString] : nil; }
}
- (void)storeCachedResponse:(NSCachedURLResponse *)c forRequest:(NSURLRequest *)r {
    if (!r.URL || c.data.length > _memoryCapacity / 20) return;
    @synchronized(self) {
        NSCachedURLResponse *old = _entries[r.URL.absoluteString];
        _usage -= old.data.length;
        while (_usage + c.data.length > _memoryCapacity && _entries.count) {
            NSString *k = _entries.allKeys[0];
            _usage -= _entries[k].data.length;
            [_entries removeObjectForKey:k];
        }
        _entries[r.URL.absoluteString] = c;
        _usage += c.data.length;
    }
}
- (void)removeCachedResponseForRequest:(NSURLRequest *)r {
    @synchronized(self) {
        NSCachedURLResponse *old = r.URL ? _entries[r.URL.absoluteString] : nil;
        if (old) {
            _usage -= old.data.length;
            [_entries removeObjectForKey:r.URL.absoluteString];
        }
    }
}
- (void)removeAllCachedResponses {
    @synchronized(self) {
        [_entries removeAllObjects];
        _usage = 0;
    }
}
- (NSUInteger)currentMemoryUsage { return _usage; }
- (NSUInteger)currentDiskUsage { return 0; }
@end

/* ---- cookies ---- */

static NSDate *http_date(NSString *s) {
    const char *u = s.UTF8String;
    if (!u) return nil;
    static const char *formats[] = {"%a, %d %b %Y %H:%M:%S", "%a, %d-%b-%Y %H:%M:%S", "%A, %d-%b-%y %H:%M:%S",
                                    "%a %b %d %H:%M:%S %Y"};
    for (size_t i = 0; i < sizeof formats / sizeof *formats; i++) {
        struct tm tm = {0};
        if (strptime(u, formats[i], &tm)) return [NSDate dateWithTimeIntervalSince1970:(double)timegm(&tm)];
    }
    return nil;
}

@implementation NSHTTPCookie {
    NSDictionary *_props;
    NSDate *_expires;
}
+ (NSHTTPCookie *)cookieWithProperties:(NSDictionary *)p { return [[self alloc] initWithProperties:p]; }
- (instancetype)initWithProperties:(NSDictionary *)p {
    NSString *name = p[NSHTTPCookieName], *value = p[NSHTTPCookieValue], *path = p[NSHTTPCookiePath];
    NSString *domain = p[NSHTTPCookieDomain];
    if (!domain) domain = [p[NSHTTPCookieOriginURL] isKindOfClass:[NSURL class]] ? [p[NSHTTPCookieOriginURL] host]
                                                                                 : [NSURL URLWithString:p[NSHTTPCookieOriginURL] ?: @""].host;
    if (!name || !value || !domain || !path) return nil;
    if ((self = [super init])) {
        _props = [p copy];
        id e = p[NSHTTPCookieExpires];
        if ([e isKindOfClass:[NSDate class]]) _expires = e;
        else if ([e isKindOfClass:[NSString class]]) _expires = http_date(e);
        id age = p[NSHTTPCookieMaximumAge];
        if (age) _expires = [NSDate dateWithTimeIntervalSinceNow:[age doubleValue]];
        NSMutableDictionary *m = [_props mutableCopy];
        m[NSHTTPCookieDomain] = domain;
        _props = m;
    }
    return self;
}
- (NSDictionary *)properties { return _props; }
- (NSString *)name { return _props[NSHTTPCookieName]; }
- (NSString *)value { return _props[NSHTTPCookieValue]; }
- (NSString *)domain { return _props[NSHTTPCookieDomain]; }
- (NSString *)path { return _props[NSHTTPCookiePath]; }
- (NSDate *)expiresDate { return _expires; }
- (BOOL)isSecure { return [_props[NSHTTPCookieSecure] boolValue] || [_props[NSHTTPCookieSecure] isEqual:@"TRUE"]; }
- (BOOL)isSessionOnly { return _expires == nil; }
- (BOOL)isHTTPOnly { return [_props[@"HttpOnly"] boolValue] || [_props[@"HttpOnly"] isEqual:@"TRUE"]; }
- (BOOL)isEqual:(id)o {
    if (![o isKindOfClass:[NSHTTPCookie class]]) return NO;
    NSHTTPCookie *c = o;
    return [c.name isEqual:self.name] && [c.domain caseInsensitiveCompare:self.domain] == NSOrderedSame &&
           [c.path isEqual:self.path];
}
- (NSUInteger)hash { return self.name.hash ^ self.domain.lowercaseString.hash; }
- (NSString *)description {
    return [NSString stringWithFormat:@"<NSHTTPCookie %@=%@; domain=%@; path=%@>", self.name, self.value, self.domain, self.path];
}
+ (NSDictionary *)requestHeaderFieldsWithCookies:(NSArray<NSHTTPCookie *> *)cookies {
    if (!cookies.count) return @{};
    NSMutableArray *parts = [NSMutableArray array];
    for (NSHTTPCookie *c in cookies) [parts addObject:[NSString stringWithFormat:@"%@=%@", c.name, c.value]];
    return @{@"Cookie" : [parts componentsJoinedByString:@"; "]};
}
/* Set-Cookie lines; several may be folded into one header with commas. */
+ (NSArray<NSHTTPCookie *> *)cookiesWithResponseHeaderFields:(NSDictionary *)headers forURL:(NSURL *)url {
    NSString *all = header_in(headers, @"Set-Cookie");
    if (!all.length) return @[];
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *chunk in [all componentsSeparatedByString:@"\n"]) {
        /* split on commas that start a new name=value (not inside an Expires date) */
        NSMutableString *cur = [NSMutableString string];
        for (NSString *piece in [chunk componentsSeparatedByString:@","]) {
            NSString *t = [piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSRange eq = [t rangeOfString:@"="], semi = [t rangeOfString:@";"];
            BOOL starts = cur.length && eq.location != NSNotFound && (semi.location == NSNotFound || eq.location < semi.location) &&
                          ![cur.lowercaseString hasSuffix:@"expires=mon"] && [t rangeOfString:@" "].location > eq.location;
            if (starts) {
                [lines addObject:[cur copy]];
                [cur setString:t];
            } else {
                if (cur.length) [cur appendString:@","];
                [cur appendString:cur.length ? piece : t];
            }
        }
        if (cur.length) [lines addObject:cur];
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *line in lines) {
        NSArray *parts = [line componentsSeparatedByString:@";"];
        NSString *first = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSRange eq = [first rangeOfString:@"="];
        if (eq.location == NSNotFound || eq.location == 0) continue;
        NSMutableDictionary *p = [NSMutableDictionary dictionary];
        p[NSHTTPCookieName] = [first substringToIndex:eq.location];
        p[NSHTTPCookieValue] = [first substringFromIndex:eq.location + 1];
        p[NSHTTPCookieDomain] = url.host ?: @"";
        NSString *dir = url.path.length ? url.path : @"/";
        if (![dir hasSuffix:@"/"]) dir = [dir stringByDeletingLastPathComponent];
        p[NSHTTPCookiePath] = dir.length ? dir : @"/";
        for (NSUInteger i = 1; i < parts.count; i++) {
            NSString *a = [parts[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSRange e = [a rangeOfString:@"="];
            NSString *k = (e.location == NSNotFound ? a : [a substringToIndex:e.location]).lowercaseString;
            NSString *v = e.location == NSNotFound ? @"" : [a substringFromIndex:e.location + 1];
            if ([k isEqual:@"domain"] && v.length) p[NSHTTPCookieDomain] = [v hasPrefix:@"."] ? v : [@"." stringByAppendingString:v];
            else if ([k isEqual:@"path"] && v.length) p[NSHTTPCookiePath] = v;
            else if ([k isEqual:@"expires"]) p[NSHTTPCookieExpires] = v;
            else if ([k isEqual:@"max-age"]) p[NSHTTPCookieMaximumAge] = v;
            else if ([k isEqual:@"secure"]) p[NSHTTPCookieSecure] = @"TRUE";
            else if ([k isEqual:@"httponly"]) p[@"HttpOnly"] = @"TRUE";
        }
        NSHTTPCookie *c = [NSHTTPCookie cookieWithProperties:p];
        if (c) [out addObject:c];
    }
    return out;
}
- (BOOL)_bn_matchesURL:(NSURL *)u {
    NSString *host = u.host.lowercaseString, *d = self.domain.lowercaseString;
    if (!host) return NO;
    BOOL domainOK = [d hasPrefix:@"."] ? ([host hasSuffix:d] || [host isEqual:[d substringFromIndex:1]]) : [host isEqual:d];
    NSString *path = u.path.length ? u.path : @"/";
    BOOL pathOK = [path hasPrefix:self.path];
    BOOL secureOK = !self.isSecure || [u.scheme.lowercaseString isEqual:@"https"] || [u.scheme.lowercaseString isEqual:@"wss"];
    BOOL alive = !_expires || _expires.timeIntervalSinceNow > 0;
    return domainOK && pathOK && secureOK && alive;
}
@end

@implementation NSHTTPCookieStorage {
    NSMutableArray<NSHTTPCookie *> *_cookies;
}
@synthesize cookieAcceptPolicy = _cookieAcceptPolicy;
+ (NSHTTPCookieStorage *)sharedHTTPCookieStorage {
    static NSHTTPCookieStorage *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSHTTPCookieStorage new]; });
    return s;
}
- (instancetype)init {
    if ((self = [super init])) _cookies = [NSMutableArray array];
    return self;
}
- (NSArray<NSHTTPCookie *> *)cookies {
    @synchronized(self) { return [_cookies copy]; }
}
- (void)setCookie:(NSHTTPCookie *)c {
    if (!c || _cookieAcceptPolicy == NSHTTPCookieAcceptPolicyNever) return;
    @synchronized(self) {
        [_cookies removeObject:c];
        if (!c.expiresDate || c.expiresDate.timeIntervalSinceNow > 0) [_cookies addObject:c];
    }
}
- (void)deleteCookie:(NSHTTPCookie *)c {
    @synchronized(self) { [_cookies removeObject:c]; }
}
- (void)removeCookiesSinceDate:(NSDate *)date {
    @synchronized(self) { [_cookies removeAllObjects]; }
}
- (NSArray<NSHTTPCookie *> *)cookiesForURL:(NSURL *)u {
    NSMutableArray *out = [NSMutableArray array];
    @synchronized(self) {
        for (NSHTTPCookie *c in _cookies)
            if ([c _bn_matchesURL:u]) [out addObject:c];
    }
    [out sortUsingComparator:^NSComparisonResult(NSHTTPCookie *a, NSHTTPCookie *b) {
        return a.path.length > b.path.length ? NSOrderedAscending : a.path.length < b.path.length ? NSOrderedDescending : NSOrderedSame;
    }];
    return out;
}
- (void)setCookies:(NSArray<NSHTTPCookie *> *)cookies forURL:(NSURL *)u mainDocumentURL:(NSURL *)m {
    for (NSHTTPCookie *c in cookies) [self setCookie:c];
}
@end

/* ---- credentials and challenges ---- */

@implementation NSURLCredential {
    NSString *_user, *_password;
    NSURLCredentialPersistence _persistence;
}
+ (NSURLCredential *)credentialWithUser:(NSString *)u password:(NSString *)p persistence:(NSURLCredentialPersistence)x {
    return [[self alloc] initWithUser:u password:p persistence:x];
}
- (instancetype)initWithUser:(NSString *)u password:(NSString *)p persistence:(NSURLCredentialPersistence)x {
    if ((self = [super init])) {
        _user = [u copy];
        _password = [p copy];
        _persistence = x;
    }
    return self;
}
+ (NSURLCredential *)credentialForTrust:(id)trust { return [[self alloc] initWithTrust:trust]; }
- (instancetype)initWithTrust:(id)trust { return [super init]; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)user { return _user; }
- (NSString *)password { return _password; }
- (BOOL)hasPassword { return _password != nil; }
- (NSURLCredentialPersistence)persistence { return _persistence; }
@end

@implementation NSURLProtectionSpace {
    NSString *_host, *_protocol, *_realm, *_method;
    NSInteger _port;
}
- (instancetype)initWithHost:(NSString *)h port:(NSInteger)p protocol:(NSString *)proto realm:(NSString *)r
        authenticationMethod:(NSString *)m {
    if ((self = [super init])) {
        _host = [h copy];
        _port = p;
        _protocol = [proto copy];
        _realm = [r copy];
        _method = [m copy] ?: NSURLAuthenticationMethodDefault;
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)host { return _host; }
- (NSInteger)port { return _port; }
- (NSString *)protocol { return _protocol; }
- (NSString *)realm { return _realm; }
- (NSString *)authenticationMethod { return _method; }
- (id)serverTrust { return nil; }
@end

@implementation NSURLAuthenticationChallenge
- (NSURLProtectionSpace *)protectionSpace { return nil; }
- (NSURLCredential *)proposedCredential { return nil; }
- (NSInteger)previousFailureCount { return 0; }
- (NSURLResponse *)failureResponse { return nil; }
- (NSError *)error { return nil; }
@end

/* ---- configuration ---- */

@implementation NSURLSessionConfiguration {
    NSString *_identifier;
}
@synthesize requestCachePolicy = _requestCachePolicy, timeoutIntervalForRequest = _timeoutIntervalForRequest,
            timeoutIntervalForResource = _timeoutIntervalForResource, networkServiceType = _networkServiceType,
            allowsCellularAccess = _allowsCellularAccess, allowsExpensiveNetworkAccess = _allowsExpensiveNetworkAccess,
            allowsConstrainedNetworkAccess = _allowsConstrainedNetworkAccess,
            requiresDNSSECValidation = _requiresDNSSECValidation, waitsForConnectivity = _waitsForConnectivity,
            discretionary = _discretionary, sharedContainerIdentifier = _sharedContainerIdentifier,
            sessionSendsLaunchEvents = _sessionSendsLaunchEvents, connectionProxyDictionary = _connectionProxyDictionary,
            TLSMinimumSupportedProtocolVersion = _TLSMinimumSupportedProtocolVersion,
            TLSMaximumSupportedProtocolVersion = _TLSMaximumSupportedProtocolVersion,
            HTTPShouldUsePipelining = _HTTPShouldUsePipelining, HTTPShouldSetCookies = _HTTPShouldSetCookies,
            HTTPCookieAcceptPolicy = _HTTPCookieAcceptPolicy, HTTPAdditionalHeaders = _HTTPAdditionalHeaders,
            HTTPMaximumConnectionsPerHost = _HTTPMaximumConnectionsPerHost, HTTPCookieStorage = _HTTPCookieStorage,
            URLCredentialStorage = _URLCredentialStorage, URLCache = _URLCache,
            shouldUseExtendedBackgroundIdleMode = _shouldUseExtendedBackgroundIdleMode, protocolClasses = _protocolClasses,
            multipathServiceType = _multipathServiceType;
- (instancetype)init {
    if ((self = [super init])) {
        _timeoutIntervalForRequest = 60;
        _timeoutIntervalForResource = 7 * 24 * 3600;
        _allowsCellularAccess = _allowsExpensiveNetworkAccess = _allowsConstrainedNetworkAccess = YES;
        _HTTPShouldSetCookies = YES;
        _HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain;
        _HTTPMaximumConnectionsPerHost = 6;
        _HTTPCookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        _URLCache = [NSURLCache sharedURLCache];
        _TLSMinimumSupportedProtocolVersion = tls_protocol_version_TLSv10;
        _TLSMaximumSupportedProtocolVersion = tls_protocol_version_TLSv13;
        _protocolClasses = @[];
    }
    return self;
}
+ (NSURLSessionConfiguration *)defaultSessionConfiguration { return [self new]; }
+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration {
    NSURLSessionConfiguration *c = [self new];
    c->_HTTPCookieStorage = [NSHTTPCookieStorage new];
    c->_URLCache = [[NSURLCache alloc] initWithMemoryCapacity:4 << 20 diskCapacity:0 directoryURL:nil];
    return c;
}
+ (NSURLSessionConfiguration *)backgroundSessionConfigurationWithIdentifier:(NSString *)identifier {
    NSURLSessionConfiguration *c = [self new];
    c->_identifier = [identifier copy];
    return c;
}
- (NSString *)identifier { return _identifier; }
- (id)copyWithZone:(NSZone *)zone {
    NSURLSessionConfiguration *c = [NSURLSessionConfiguration new];
    c->_identifier = _identifier;
    c->_requestCachePolicy = _requestCachePolicy;
    c->_timeoutIntervalForRequest = _timeoutIntervalForRequest;
    c->_timeoutIntervalForResource = _timeoutIntervalForResource;
    c->_networkServiceType = _networkServiceType;
    c->_allowsCellularAccess = _allowsCellularAccess;
    c->_allowsExpensiveNetworkAccess = _allowsExpensiveNetworkAccess;
    c->_allowsConstrainedNetworkAccess = _allowsConstrainedNetworkAccess;
    c->_requiresDNSSECValidation = _requiresDNSSECValidation;
    c->_waitsForConnectivity = _waitsForConnectivity;
    c->_discretionary = _discretionary;
    c->_sharedContainerIdentifier = _sharedContainerIdentifier;
    c->_connectionProxyDictionary = _connectionProxyDictionary;
    c->_TLSMinimumSupportedProtocolVersion = _TLSMinimumSupportedProtocolVersion;
    c->_TLSMaximumSupportedProtocolVersion = _TLSMaximumSupportedProtocolVersion;
    c->_HTTPShouldUsePipelining = _HTTPShouldUsePipelining;
    c->_HTTPShouldSetCookies = _HTTPShouldSetCookies;
    c->_HTTPCookieAcceptPolicy = _HTTPCookieAcceptPolicy;
    c->_HTTPAdditionalHeaders = _HTTPAdditionalHeaders;
    c->_HTTPMaximumConnectionsPerHost = _HTTPMaximumConnectionsPerHost;
    c->_HTTPCookieStorage = _HTTPCookieStorage;
    c->_URLCredentialStorage = _URLCredentialStorage;
    c->_URLCache = _URLCache;
    c->_protocolClasses = _protocolClasses;
    c->_multipathServiceType = _multipathServiceType;
    return c;
}
@end

/* ---- metrics ---- */

@interface NSURLSessionTaskTransactionMetrics () {
@public
    NSURLRequest *_request;
    NSURLResponse *_response;
    NSDate *_fetchStart, *_lookupStart, *_lookupEnd, *_connectStart, *_tlsStart, *_tlsEnd, *_connectEnd, *_requestStart,
        *_requestEnd, *_responseStart, *_responseEnd;
    NSString *_protocolName, *_localAddress, *_remoteAddress;
    NSNumber *_localPort, *_remotePort, *_tlsVersion, *_tlsCipher;
    int64_t _headerSent, _bodySent, _headerReceived, _bodyReceived;
}
@end
@implementation NSURLSessionTaskTransactionMetrics
- (NSURLRequest *)request { return _request; }
- (NSURLResponse *)response { return _response; }
- (NSDate *)fetchStartDate { return _fetchStart; }
- (NSDate *)domainLookupStartDate { return _lookupStart; }
- (NSDate *)domainLookupEndDate { return _lookupEnd; }
- (NSDate *)connectStartDate { return _connectStart; }
- (NSDate *)secureConnectionStartDate { return _tlsStart; }
- (NSDate *)secureConnectionEndDate { return _tlsEnd; }
- (NSDate *)connectEndDate { return _connectEnd; }
- (NSDate *)requestStartDate { return _requestStart; }
- (NSDate *)requestEndDate { return _requestEnd; }
- (NSDate *)responseStartDate { return _responseStart; }
- (NSDate *)responseEndDate { return _responseEnd; }
- (NSString *)networkProtocolName { return _protocolName; }
- (BOOL)isProxyConnection { return NO; }
- (BOOL)isReusedConnection { return NO; }
- (NSURLSessionTaskMetricsResourceFetchType)resourceFetchType {
    return _protocolName ? NSURLSessionTaskMetricsResourceFetchTypeNetworkLoad : NSURLSessionTaskMetricsResourceFetchTypeLocalCache;
}
- (int64_t)countOfRequestHeaderBytesSent { return _headerSent; }
- (int64_t)countOfRequestBodyBytesSent { return _bodySent; }
- (int64_t)countOfRequestBodyBytesBeforeEncoding { return _bodySent; }
- (int64_t)countOfResponseHeaderBytesReceived { return _headerReceived; }
- (int64_t)countOfResponseBodyBytesReceived { return _bodyReceived; }
- (int64_t)countOfResponseBodyBytesAfterDecoding { return _bodyReceived; }
- (NSString *)localAddress { return _localAddress; }
- (NSNumber *)localPort { return _localPort; }
- (NSString *)remoteAddress { return _remoteAddress; }
- (NSNumber *)remotePort { return _remotePort; }
- (NSNumber *)negotiatedTLSProtocolVersion { return _tlsVersion; }
- (NSNumber *)negotiatedTLSCipherSuite { return _tlsCipher; }
- (BOOL)isCellular { return NO; }
- (BOOL)isExpensive { return NO; }
- (BOOL)isConstrained { return NO; }
- (BOOL)isMultipath { return NO; }
- (NSURLSessionTaskMetricsDomainResolutionProtocol)domainResolutionProtocol {
    return NSURLSessionTaskMetricsDomainResolutionProtocolUDP;
}
@end

@interface NSURLSessionTaskMetrics () {
@public
    NSMutableArray<NSURLSessionTaskTransactionMetrics *> *_transactions;
    NSUInteger _redirects;
}
@end
@implementation NSURLSessionTaskMetrics
- (NSArray<NSURLSessionTaskTransactionMetrics *> *)transactionMetrics { return [_transactions copy] ?: @[]; }
- (NSUInteger)redirectCount { return _redirects; }
@end

static NSURLSessionTaskTransactionMetrics *metrics_from(NSURLRequest *req, NSURLResponse *resp, NSDate *start,
                                                       const bn_http_result *r) {
    NSURLSessionTaskTransactionMetrics *m = [NSURLSessionTaskTransactionMetrics new];
    m->_request = req;
    m->_response = resp;
    m->_fetchStart = start;
    m->_lookupStart = start;
    m->_lookupEnd = [start dateByAddingTimeInterval:r->t_lookup];
    m->_connectStart = m->_lookupEnd;
    if (r->tls_version) {
        m->_tlsStart = [start dateByAddingTimeInterval:r->t_connect];
        m->_tlsEnd = [start dateByAddingTimeInterval:r->t_tls];
    }
    m->_connectEnd = [start dateByAddingTimeInterval:r->tls_version ? r->t_tls : r->t_connect];
    m->_requestStart = [start dateByAddingTimeInterval:r->t_request];
    m->_requestEnd = m->_requestStart;
    m->_responseStart = [start dateByAddingTimeInterval:r->t_first_byte];
    m->_responseEnd = [start dateByAddingTimeInterval:r->t_total];
    switch (r->http_version) {
    case 10: m->_protocolName = @"http/1.0"; break;
    case 11: m->_protocolName = @"http/1.1"; break;
    case 20: m->_protocolName = @"h2"; break;
    case 30: m->_protocolName = @"h3"; break;
    }
    if (r->local_ip[0]) m->_localAddress = @(r->local_ip);
    if (r->remote_ip[0]) m->_remoteAddress = @(r->remote_ip);
    if (r->local_port) m->_localPort = @(r->local_port);
    if (r->remote_port) m->_remotePort = @(r->remote_port);
    if (r->tls_version) m->_tlsVersion = @(r->tls_version);
    if (r->tls_cipher) m->_tlsCipher = @(r->tls_cipher);
    m->_headerSent = r->request_bytes;
    m->_bodySent = r->upload_bytes;
    m->_headerReceived = r->header_bytes;
    m->_bodyReceived = r->download_bytes;
    return m;
}

/* ---- errors ---- */

static NSError *url_error(NSInteger code, NSURL *url, NSString *detail) {
    NSString *msg;
    switch (code) {
    case NSURLErrorCancelled: msg = @"cancelled"; break;
    case NSURLErrorTimedOut: msg = @"The request timed out."; break;
    case NSURLErrorCannotFindHost: msg = @"A server with the specified hostname could not be found."; break;
    case NSURLErrorCannotConnectToHost: msg = @"Could not connect to the server."; break;
    case NSURLErrorNetworkConnectionLost: msg = @"The network connection was lost."; break;
    case NSURLErrorNotConnectedToInternet: msg = @"The Internet connection appears to be offline."; break;
    case NSURLErrorBadURL: msg = @"bad URL"; break;
    case NSURLErrorUnsupportedURL: msg = @"unsupported URL"; break;
    case NSURLErrorSecureConnectionFailed: msg = @"An SSL error has occurred and a secure connection to the server cannot be made."; break;
    case NSURLErrorServerCertificateUntrusted: msg = @"The certificate for this server is invalid."; break;
    case NSURLErrorHTTPTooManyRedirects: msg = @"too many HTTP redirects"; break;
    case NSURLErrorBadServerResponse: msg = @"The server returned a bad response."; break;
    case NSURLErrorFileDoesNotExist: msg = @"The requested URL was not found on this server."; break;
    case NSURLErrorCannotDecodeContentData: msg = @"cannot decode content data"; break;
    default: msg = @"An unknown error occurred."; break;
    }
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:msg forKey:NSLocalizedDescriptionKey];
    if (url) {
        info[NSURLErrorFailingURLErrorKey] = url;
        info[NSURLErrorFailingURLStringErrorKey] = url.absoluteString ?: @"";
    }
    if (detail.length) info[@"_bn_detail"] = detail;
    return [NSError errorWithDomain:NSURLErrorDomain code:code userInfo:info];
}

/* ---- data: URLs ---- */

/* A Location against the URL it came from. */
static NSURL *resolve_url(NSString *loc, NSURL *base) {
    if (!loc.length) return nil;
    NSRange colon = [loc rangeOfString:@":"], slash = [loc rangeOfString:@"/"];
    if (colon.location != NSNotFound && (slash.location == NSNotFound || colon.location < slash.location))
        return [NSURL URLWithString:loc];
    NSString *origin = [NSString stringWithFormat:@"%@://%@%@", base.scheme, base.host ?: @"",
                                                  base.port ? [NSString stringWithFormat:@":%@", base.port] : @""];
    if ([loc hasPrefix:@"//"]) return [NSURL URLWithString:[NSString stringWithFormat:@"%@:%@", base.scheme, loc]];
    if ([loc hasPrefix:@"/"]) return [NSURL URLWithString:[origin stringByAppendingString:loc]];
    NSString *path = base.path.length ? base.path : @"/";
    NSString *dir = [path hasSuffix:@"/"] ? path : [path stringByDeletingLastPathComponent];
    if (![dir hasSuffix:@"/"]) dir = [dir stringByAppendingString:@"/"];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *p in [[dir stringByAppendingString:loc] componentsSeparatedByString:@"/"]) {
        if ([p isEqual:@".."]) {
            if (parts.count > 1) [parts removeLastObject];
        } else if (![p isEqual:@"."]) {
            [parts addObject:p];
        }
    }
    return [NSURL URLWithString:[origin stringByAppendingString:[parts componentsJoinedByString:@"/"]]];
}

static int hexval(int c) {
    return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
}
static NSData *percent_decode(NSString *s) {
    const char *u = s.UTF8String;
    size_t n = strlen(u);
    NSMutableData *d = [NSMutableData dataWithCapacity:n];
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)u[i];
        if (c == '%' && i + 2 < n + 1 && hexval(u[i + 1]) >= 0 && hexval(u[i + 2]) >= 0) {
            c = (unsigned char)(hexval(u[i + 1]) << 4 | hexval(u[i + 2]));
            i += 2;
        }
        [d appendBytes:&c length:1];
    }
    return d;
}
/* data:[<type>][;charset=x][;base64],<data> */
static BOOL data_url(NSURL *url, NSData **body, NSURLResponse **resp) {
    NSString *s = url.absoluteString;
    NSRange comma = [s rangeOfString:@","];
    if (![s.lowercaseString hasPrefix:@"data:"] || comma.location == NSNotFound) return NO;
    NSString *meta = [s substringWithRange:NSMakeRange(5, comma.location - 5)];
    NSString *payload = [s substringFromIndex:comma.location + 1];
    NSArray *parts = [meta componentsSeparatedByString:@";"];
    NSString *mime = [parts[0] length] ? [parts[0] lowercaseString] : @"text/plain";
    NSString *charset = [parts[0] length] ? nil : @"US-ASCII";
    BOOL b64 = NO;
    for (NSUInteger i = 1; i < parts.count; i++) {
        if ([[parts[i] lowercaseString] isEqual:@"base64"]) b64 = YES;
        else if ([[parts[i] lowercaseString] hasPrefix:@"charset="]) charset = [parts[i] substringFromIndex:8];
    }
    NSData *raw = percent_decode(payload);
    if (b64) {
        NSString *t = [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding];
        raw = t ? [[NSData alloc] initWithBase64EncodedString:t options:NSDataBase64DecodingIgnoreUnknownCharacters] : nil;
        if (!raw) return NO;
    }
    *body = raw;
    *resp = [[NSURLResponse alloc] initWithURL:url MIMEType:mime expectedContentLength:(NSInteger)raw.length
                              textEncodingName:charset];
    return YES;
}

/* ---- tasks ---- */

@class NSURLSession;
@interface NSURLSession ()
- (void)_bn_onDelegateQueue:(void (^)(void))block;
- (void)_bn_taskFinished:(NSURLSessionTask *)task;
- (id)_bn_delegate;
@end

typedef void (^BNDataCompletion)(NSData *, NSURLResponse *, NSError *);
typedef void (^BNDownloadCompletion)(NSURL *, NSURLResponse *, NSError *);

@interface NSURLSessionTask () {
@public
    __weak NSURLSession *_session;
    NSURLSession *_sessionWhileRunning;
    NSUInteger _identifier;
    NSURLRequest *_originalRequest, *_currentRequest;
    NSURLResponse *_response;
    id<NSURLSessionTaskDelegate> _delegate;
    NSProgress *_progress;
    NSString *_taskDescription;
    NSDate *_earliestBeginDate;
    int64_t _clientSend, _clientReceive, _sent, _received, _expectedSend, _expectedReceive;
    NSURLSessionTaskState _state;
    NSError *_error;
    float _priority;
    BOOL _incremental, _started;
    volatile int _cancelled;
    NSURL *_uploadFile;
    NSData *_uploadData;
    BNDataCompletion _dataCompletion;
    BNDownloadCompletion _downloadCompletion;
    NSMutableData *_collected;
    NSURLSessionTaskMetrics *_metrics;
}
- (void)_bn_run;
@end

static NSUInteger nextTaskID = 1;

@implementation NSURLSessionTask
- (instancetype)initWithBNSession:(NSURLSession *)s request:(NSURLRequest *)r {
    if ((self = [super init])) {
        _session = s;
        @synchronized([NSURLSessionTask class]) { _identifier = nextTaskID++; }
        _originalRequest = [r copy];
        _currentRequest = _originalRequest;
        _state = NSURLSessionTaskStateSuspended;
        _priority = NSURLSessionTaskPriorityDefault;
        _progress = [NSProgress progressWithTotalUnitCount:-1];
        _expectedReceive = NSURLSessionTransferSizeUnknown;
        _expectedSend = NSURLSessionTransferSizeUnknown;
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSUInteger)taskIdentifier { return _identifier; }
- (NSURLRequest *)originalRequest { return _originalRequest; }
- (NSURLRequest *)currentRequest { return _currentRequest; }
- (NSURLResponse *)response {
    @synchronized(self) { return _response; }
}
- (id<NSURLSessionTaskDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSURLSessionTaskDelegate>)d { _delegate = d; }
- (NSProgress *)progress { return _progress; }
- (NSDate *)earliestBeginDate { return _earliestBeginDate; }
- (void)setEarliestBeginDate:(NSDate *)d { _earliestBeginDate = [d copy]; }
- (int64_t)countOfBytesClientExpectsToSend { return _clientSend; }
- (void)setCountOfBytesClientExpectsToSend:(int64_t)n { _clientSend = n; }
- (int64_t)countOfBytesClientExpectsToReceive { return _clientReceive; }
- (void)setCountOfBytesClientExpectsToReceive:(int64_t)n { _clientReceive = n; }
- (int64_t)countOfBytesSent { return _sent; }
- (int64_t)countOfBytesReceived { return _received; }
- (int64_t)countOfBytesExpectedToSend { return _expectedSend; }
- (int64_t)countOfBytesExpectedToReceive { return _expectedReceive; }
- (NSString *)taskDescription { return _taskDescription; }
- (void)setTaskDescription:(NSString *)d { _taskDescription = [d copy]; }
- (NSURLSessionTaskState)state {
    @synchronized(self) { return _state; }
}
- (NSError *)error { return _error; }
- (float)priority { return _priority; }
- (void)setPriority:(float)p { _priority = p; }
- (BOOL)prefersIncrementalDelivery { return _incremental; }
- (void)setPrefersIncrementalDelivery:(BOOL)b { _incremental = b; }

- (void)resume {
    @synchronized(self) {
        if (_state != NSURLSessionTaskStateSuspended) return;
        _state = NSURLSessionTaskStateRunning;
        if (_started) return;
        _started = YES;
        _sessionWhileRunning = _session;
    }
    NSDate *begin = _earliestBeginDate;
    double delay = begin ? begin.timeIntervalSinceNow : 0;
    dispatch_block_t go = ^{ [self _bn_run]; };
    if (delay > 0)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), go);
    else
        dispatch_async(dispatch_get_global_queue(0, 0), go);
}
/* Suspending pauses nothing already under way; it only delays a start. */
- (void)suspend {
    @synchronized(self) {
        if (_state == NSURLSessionTaskStateRunning && !_started) _state = NSURLSessionTaskStateSuspended;
    }
}
- (void)cancel {
    BOOL notStarted;
    @synchronized(self) {
        if (_state == NSURLSessionTaskStateCompleted || _state == NSURLSessionTaskStateCanceling) return;
        _cancelled = 1;
        notStarted = !_started;
        _state = NSURLSessionTaskStateCanceling;
        if (notStarted) {
            _started = YES;
            _sessionWhileRunning = _session;
        }
    }
    [_progress cancel];
    if (notStarted)
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            [self _bn_finishWithData:nil location:nil error:url_error(NSURLErrorCancelled, self->_currentRequest.URL, nil)];
        });
}
- (void)_bn_run {}

/* The delegate to ask: the task's own, else the session's. */
- (id)_bn_delegateFor:(SEL)sel {
    if ([_delegate respondsToSelector:sel]) return _delegate;
    id d = [_sessionWhileRunning _bn_delegate];
    return [d respondsToSelector:sel] ? d : nil;
}

/* Called on a worker thread with the outcome; delivers everything on the
 * delegate queue, then marks the task completed. */
- (void)_bn_finishWithData:(NSData *)data location:(NSURL *)location error:(NSError *)error {
    NSURLSession *s = _sessionWhileRunning;
    NSURLResponse *resp = self.response;
    @synchronized(self) {
        _error = error;
        if (_state != NSURLSessionTaskStateCompleted) _state = NSURLSessionTaskStateCompleted;
    }
    if (!error) {
        _progress.totalUnitCount = MAX(_received, 1);
        _progress.completedUnitCount = MAX(_received, 1);
    }
    [s _bn_onDelegateQueue:^{
        if (self->_dataCompletion) {
            self->_dataCompletion(error ? nil : (data ?: [NSData data]), resp, error);
            self->_dataCompletion = nil;
        } else if (self->_downloadCompletion) {
            self->_downloadCompletion(error ? nil : location, resp, error);
            self->_downloadCompletion = nil;
            if (location) [[NSFileManager defaultManager] removeItemAtPath:location.path error:NULL];
        } else {
            if (location && !error) {
                id d = [self _bn_delegateFor:@selector(URLSession:downloadTask:didFinishDownloadingToURL:)];
                [d URLSession:s downloadTask:(NSURLSessionDownloadTask *)self didFinishDownloadingToURL:location];
                [[NSFileManager defaultManager] removeItemAtPath:location.path error:NULL];
            }
            if (self->_metrics) {
                id d = [self _bn_delegateFor:@selector(URLSession:task:didFinishCollectingMetrics:)];
                [d URLSession:s task:self didFinishCollectingMetrics:self->_metrics];
            }
            id d = [self _bn_delegateFor:@selector(URLSession:task:didCompleteWithError:)];
            [d URLSession:s task:self didCompleteWithError:error];
        }
        [s _bn_taskFinished:self];
        self->_sessionWhileRunning = nil;
    }];
}
@end

/* ---- HTTP transfers ---- */

@interface BNTransfer : NSObject {
@public
    __unsafe_unretained NSURLSessionTask *task;
    NSURLSession *session;
    NSHTTPURLResponse *httpResponse;
    NSURLResponse *response;
    BOOL redirecting, deliveredResponse, toFile, collect, cancelled;
    FILE *file;
    int64_t written, lastReported;
    dispatch_semaphore_t wait;
}
@end
@implementation BNTransfer
@end

static NSDictionary *parse_headers(const char *h, size_t n) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSString *all = [[NSString alloc] initWithBytes:h length:n encoding:NSUTF8StringEncoding]
                        ?: [[NSString alloc] initWithBytes:h length:n encoding:NSISOLatin1StringEncoding];
    for (NSString *line in [all componentsSeparatedByString:@"\r\n"]) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound || colon.location == 0) continue;
        NSString *k = [line substringToIndex:colon.location];
        NSString *v = [[line substringFromIndex:colon.location + 1]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *existing = header_key_in(out, k);
        if (existing) {
            NSString *sep = [k caseInsensitiveCompare:@"Set-Cookie"] == NSOrderedSame ? @"\n" : @", ";
            out[existing] = [NSString stringWithFormat:@"%@%@%@", out[existing], sep, v];
        } else {
            out[k] = v;
        }
    }
    return out;
}

static int on_response(void *ctx, long status, const char *headers, size_t len) {
    BNTransfer *x = (__bridge BNTransfer *)ctx;
    NSURLSessionTask *task = x->task;
    NSURL *url = task->_currentRequest.URL;
    NSString *scheme = url.scheme.lowercaseString;
    NSURLResponse *resp;
    if ([scheme isEqual:@"http"] || [scheme isEqual:@"https"]) {
        NSDictionary *h = parse_headers(headers, len);
        x->httpResponse = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:h];
        resp = x->httpResponse;
        BOOL redirect = (status == 301 || status == 302 || status == 303 || status == 307 || status == 308) &&
                        header_in(h, @"Location");
        if (redirect) {
            x->redirecting = YES;
            return 0;
        }
    } else if ([scheme isEqual:@"data"]) {
        @synchronized(task) { resp = task->_response; }
    } else {
        NSString *path = url.path;
        BOOL dir = NO;
        long long size = -1;
        if (url.isFileURL && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir] && !dir) {
            NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
            size = [a[NSFileSize] longLongValue];
        }
        resp = [[NSURLResponse alloc] initWithURL:url MIMEType:mime_for_extension(url.pathExtension)
                            expectedContentLength:(NSInteger)size textEncodingName:nil];
    }
    x->redirecting = NO;
    x->response = resp;
    @synchronized(task) { task->_response = resp; }
    task->_expectedReceive = resp.expectedContentLength;
    task->_progress.totalUnitCount = resp.expectedContentLength;
    x->deliveredResponse = YES;
    /* A data task's delegate decides whether to go on. */
    if (!x->collect && !x->toFile && [task isKindOfClass:[NSURLSessionDataTask class]]) {
        id d = [task _bn_delegateFor:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)];
        if (d) {
            __block NSURLSessionResponseDisposition disposition = NSURLSessionResponseAllow;
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            NSURLSession *s = x->session;
            [s _bn_onDelegateQueue:^{
                [d URLSession:s dataTask:(NSURLSessionDataTask *)task didReceiveResponse:resp
                    completionHandler:^(NSURLSessionResponseDisposition r) {
                        disposition = r;
                        dispatch_semaphore_signal(sem);
                    }];
            }];
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
            if (disposition == NSURLSessionResponseCancel) {
                x->cancelled = YES;
                return 1;
            }
        }
    }
    return task->_cancelled ? 1 : 0;
}

static int on_data(void *ctx, const void *bytes, size_t n) {
    BNTransfer *x = (__bridge BNTransfer *)ctx;
    NSURLSessionTask *task = x->task;
    if (task->_cancelled) return 1;
    if (x->redirecting) return 0; /* a redirect's body is dropped */
    task->_received += (int64_t)n;
    task->_progress.completedUnitCount = task->_received;
    if (x->toFile) {
        if (fwrite(bytes, 1, n, x->file) != n) return 1;
        x->written += (int64_t)n;
        id d = [task _bn_delegateFor:@selector(URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)];
        if (d) {
            int64_t total = x->written, expected = task->_expectedReceive, chunk = x->written - x->lastReported;
            x->lastReported = x->written;
            NSURLSession *s = x->session;
            [s _bn_onDelegateQueue:^{
                [d URLSession:s downloadTask:(NSURLSessionDownloadTask *)task didWriteData:chunk totalBytesWritten:total
                    totalBytesExpectedToWrite:expected];
            }];
        }
    } else if (x->collect) {
        [task->_collected appendBytes:bytes length:n];
    } else {
        id d = [task _bn_delegateFor:@selector(URLSession:dataTask:didReceiveData:)];
        if (d) {
            NSData *chunk = [NSData dataWithBytes:bytes length:n];
            NSURLSession *s = x->session;
            [s _bn_onDelegateQueue:^{ [d URLSession:s dataTask:(NSURLSessionDataTask *)task didReceiveData:chunk]; }];
        }
    }
    return 0;
}

static int on_progress(void *ctx, int64_t dt, int64_t dn, int64_t ut, int64_t un) {
    BNTransfer *x = (__bridge BNTransfer *)ctx;
    NSURLSessionTask *task = x->task;
    if (task->_cancelled) return 1;
    if (ut > 0 && un != task->_sent) {
        int64_t delta = un - task->_sent;
        task->_sent = un;
        task->_expectedSend = ut;
        id d = [task _bn_delegateFor:@selector(URLSession:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)];
        if (d) {
            NSURLSession *s = x->session;
            [s _bn_onDelegateQueue:^{
                [d URLSession:s task:task didSendBodyData:delta totalBytesSent:un totalBytesExpectedToSend:ut];
            }];
        }
    }
    return 0;
}

static NSString *default_user_agent(void) {
    static NSString *ua;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *info = [NSBundle mainBundle].infoDictionary;
        NSString *name = info[@"CFBundleName"] ?: info[@"CFBundleExecutable"] ?: [NSProcessInfo processInfo].processName;
        NSString *version = info[@"CFBundleVersion"] ?: @"1";
        ua = [NSString stringWithFormat:@"%@/%@ CFNetwork/1490.0.4 Darwin/23.2.0",
                                        [name stringByReplacingOccurrencesOfString:@" " withString:@"%20"], version];
    });
    return ua;
}

@interface NSURLSession () {
@public
    NSURLSessionConfiguration *_configuration;
}
@end

@implementation NSURLSessionDataTask
/* The transfer, hop by hop. */
- (void)_bn_run {
    NSURLSession *s = _sessionWhileRunning;
    NSURLSessionConfiguration *cfg = s->_configuration;
    BOOL download = [self isKindOfClass:[NSURLSessionDownloadTask class]];
    _metrics = [NSURLSessionTaskMetrics new];
    _metrics->_transactions = [NSMutableArray array];
    NSDate *taskStart = [NSDate date];
    NSString *tmpPath = nil;
    NSError *error = nil;
    for (int hop = 0;; hop++) {
        if (_cancelled) {
            error = url_error(NSURLErrorCancelled, _currentRequest.URL, nil);
            break;
        }
        if (hop > 16) {
            error = url_error(NSURLErrorHTTPTooManyRedirects, _currentRequest.URL, nil);
            break;
        }
        NSURLRequest *req = _currentRequest;
        NSURL *url = req.URL;
        if (!url || !url.scheme.length) {
            error = url_error(url ? NSURLErrorUnsupportedURL : NSURLErrorBadURL, url, nil);
            break;
        }
        /* data: URLs, here */
        NSData *inline_body;
        NSURLResponse *inline_resp;
        if ([url.scheme.lowercaseString isEqual:@"data"]) {
            if (!data_url(url, &inline_body, &inline_resp)) {
                error = url_error(NSURLErrorBadURL, url, nil);
                break;
            }
            @synchronized(self) { _response = inline_resp; }
            BNTransfer *x = [BNTransfer new];
            x->task = self;
            x->session = s;
            x->collect = _dataCompletion != nil;
            x->toFile = download;
            if (download) {
                tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                      [NSString stringWithFormat:@"CFNetworkDownload_%@.tmp", [NSUUID UUID].UUIDString]];
                x->file = fopen(tmpPath.fileSystemRepresentation, "wb");
            }
            if (x->collect) _collected = [NSMutableData data];
            const char *noHeaders = "";
            x->redirecting = NO;
            /* deliver as a transfer would */
            on_response((__bridge void *)x, 0, noHeaders, 0);
            if (!x->cancelled && !_cancelled) on_data((__bridge void *)x, inline_body.bytes, inline_body.length);
            if (x->file) fclose(x->file);
            if (x->cancelled || _cancelled) error = url_error(NSURLErrorCancelled, url, nil);
            break;
        }

        /* headers: the request's, the session's, cookies, a user agent */
        NSMutableDictionary *h = [NSMutableDictionary dictionaryWithDictionary:req.allHTTPHeaderFields ?: @{}];
        for (NSString *k in cfg.HTTPAdditionalHeaders)
            if (!header_key_in(h, k)) h[k] = [cfg.HTTPAdditionalHeaders[k] description];
        if (!header_key_in(h, @"User-Agent")) h[@"User-Agent"] = default_user_agent();
        if (!header_key_in(h, @"Accept")) h[@"Accept"] = @"*/*";
        if (!header_key_in(h, @"Accept-Language")) h[@"Accept-Language"] = @"en-US,en;q=0.9";
        NSData *body = _uploadData ?: req.HTTPBody;
        if (body && !header_key_in(h, @"Content-Type") && [req.HTTPMethod isEqual:@"POST"])
            h[@"Content-Type"] = @"application/x-www-form-urlencoded";
        if (cfg.HTTPShouldSetCookies && req.HTTPShouldHandleCookies && cfg.HTTPCookieStorage && !header_key_in(h, @"Cookie")) {
            NSDictionary *c = [NSHTTPCookie requestHeaderFieldsWithCookies:[cfg.HTTPCookieStorage cookiesForURL:url]];
            [h addEntriesFromDictionary:c];
        }
        NSMutableArray *lines = [NSMutableArray array];
        for (NSString *k in h) [lines addObject:[NSString stringWithFormat:@"%@: %@", k, h[k]]];
        const char **hv = malloc(sizeof(char *) * (lines.count + 1));
        for (NSUInteger i = 0; i < lines.count; i++) hv[i] = [lines[i] UTF8String];

        bn_http_request r = {0};
        r.method = req.HTTPMethod.UTF8String;
        r.url = url.absoluteString.UTF8String;
        r.headers = hv;
        r.nheaders = (int)lines.count;
        r.body = body.bytes;
        r.body_len = body.length;
        r.body_file = _uploadFile.path.fileSystemRepresentation;
        r.timeout = req.timeoutInterval > 0 ? MIN(req.timeoutInterval, cfg.timeoutIntervalForRequest) : cfg.timeoutIntervalForRequest;
        r.resource_timeout = cfg.timeoutIntervalForResource;
        r.decode = 1;
        r.tls_min = cfg.TLSMinimumSupportedProtocolVersion;
        r.tls_max = cfg.TLSMaximumSupportedProtocolVersion;
        if (body.length || _uploadFile) {
            _expectedSend = _uploadFile ? [[[NSFileManager defaultManager] attributesOfItemAtPath:_uploadFile.path error:NULL][NSFileSize] longLongValue]
                                        : (int64_t)body.length;
        }

        BNTransfer *x = [BNTransfer new];
        x->task = self;
        x->session = s;
        x->collect = _dataCompletion != nil;
        x->toFile = download;
        if (x->collect && !_collected) _collected = [NSMutableData data];
        if (download) {
            if (!tmpPath)
                tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                      [NSString stringWithFormat:@"CFNetworkDownload_%@.tmp", [NSUUID UUID].UUIDString]];
            x->file = fopen(tmpPath.fileSystemRepresentation, "wb");
            if (!x->file) {
                free(hv);
                error = url_error(NSURLErrorCannotCreateFile, url, nil);
                break;
            }
        }
        bn_http_callbacks cb = {(__bridge void *)x, on_response, on_data, on_progress};
        bn_http_result res;
        NSDate *hopStart = [NSDate date];
        int rc = bitten_http_perform(&r, &cb, &res);
        free(hv);
        if (x->file) fclose(x->file);
        [_metrics->_transactions addObject:metrics_from(req, x->httpResponse ?: x->response, hopStart, &res)];
        if (rc < 0) {
            error = url_error(NSURLErrorNotConnectedToInternet, url, @(res.message));
            break;
        }
        /* cookies from every response, redirects included */
        if (x->httpResponse && cfg.HTTPShouldSetCookies && req.HTTPShouldHandleCookies && cfg.HTTPCookieStorage) {
            for (NSHTTPCookie *c in [NSHTTPCookie cookiesWithResponseHeaderFields:x->httpResponse.allHeaderFields forURL:url])
                [cfg.HTTPCookieStorage setCookie:c];
        }
        if (x->cancelled || _cancelled || res.cancelled) {
            error = url_error(NSURLErrorCancelled, url, nil);
            break;
        }
        if (res.error) {
            error = url_error(res.error, url, @(res.message));
            break;
        }
        if (!x->redirecting) break;

        /* a redirect: the next request, which the delegate may change */
        NSHTTPURLResponse *redirectResponse = x->httpResponse;
        NSString *location = header_in(redirectResponse.allHeaderFields, @"Location");
        NSURL *next = resolve_url(location, url);
        if (!next && res.redirect_url[0]) next = [NSURL URLWithString:@(res.redirect_url)];
        if (!next) {
            error = url_error(NSURLErrorRedirectToNonExistentLocation, url, nil);
            break;
        }
        NSMutableURLRequest *nr = [req mutableCopy];
        nr.URL = next;
        NSInteger st = redirectResponse.statusCode;
        if (st == 303 || ((st == 301 || st == 302) && [req.HTTPMethod isEqual:@"POST"])) {
            nr.HTTPMethod = [req.HTTPMethod isEqual:@"HEAD"] ? @"HEAD" : @"GET";
            nr.HTTPBody = nil;
            [nr setValue:nil forHTTPHeaderField:@"Content-Type"];
            [nr setValue:nil forHTTPHeaderField:@"Content-Length"];
            _uploadData = nil;
            _uploadFile = nil;
        }
        if (![next.host isEqual:url.host]) [nr setValue:nil forHTTPHeaderField:@"Authorization"];
        [nr setValue:nil forHTTPHeaderField:@"Cookie"];
        NSURLRequest *chosen = nr;
        id d = _dataCompletion || _downloadCompletion ? nil
                                                      : [self _bn_delegateFor:@selector(URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:)];
        if (d) {
            __block NSURLRequest *answer = nil;
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            [s _bn_onDelegateQueue:^{
                [d URLSession:s task:self willPerformHTTPRedirection:redirectResponse newRequest:nr
                    completionHandler:^(NSURLRequest *q) {
                        answer = q;
                        dispatch_semaphore_signal(sem);
                    }];
            }];
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
            chosen = answer;
        }
        if (!chosen) {
            /* the redirect response is the answer */
            @synchronized(self) { _response = redirectResponse; }
            break;
        }
        _metrics->_redirects++;
        _currentRequest = [chosen copy];
        _received = 0;
        if (_collected) [_collected setLength:0];
    }
    if (error && tmpPath) {
        [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:NULL];
        tmpPath = nil;
    }
    (void)taskStart;
    [self _bn_finishWithData:_collected location:tmpPath ? [NSURL fileURLWithPath:tmpPath] : nil error:error];
}
@end

@implementation NSURLSessionUploadTask
@end

@implementation NSURLSessionDownloadTask
- (void)_bn_run {
    ((void (*)(id, SEL))[NSURLSessionDataTask instanceMethodForSelector:@selector(_bn_run)])(self, @selector(_bn_run));
}
- (void)cancelByProducingResumeData:(void (^)(NSData *))completionHandler {
    [self cancel];
    if (completionHandler) {
        NSURLSession *s = _sessionWhileRunning ?: _session;
        [s _bn_onDelegateQueue:^{ completionHandler(nil); }];
    }
}
@end

/* ---- WebSockets ---- */

@implementation NSURLSessionWebSocketMessage {
    NSURLSessionWebSocketMessageType _type;
    NSData *_data;
    NSString *_string;
}
- (instancetype)initWithData:(NSData *)d {
    if ((self = [super init])) {
        _type = NSURLSessionWebSocketMessageTypeData;
        _data = [d copy];
    }
    return self;
}
- (instancetype)initWithString:(NSString *)s {
    if ((self = [super init])) {
        _type = NSURLSessionWebSocketMessageTypeString;
        _string = [s copy];
    }
    return self;
}
- (NSURLSessionWebSocketMessageType)type { return _type; }
- (NSData *)data { return _data; }
- (NSString *)string { return _string; }
@end

typedef void (^BNWSReceive)(NSURLSessionWebSocketMessage *, NSError *);

@implementation NSURLSessionWebSocketTask {
    bn_ws *_ws;
    NSArray<NSString *> *_protocols;
    dispatch_queue_t _writer;
    NSMutableArray<NSURLSessionWebSocketMessage *> *_inbox;
    NSMutableArray<BNWSReceive> *_waiting;
    NSMutableArray *_pongs;
    NSError *_failure;
    NSInteger _maxSize;
    NSURLSessionWebSocketCloseCode _closeCode;
    NSData *_closeReason;
    BOOL _open, _closed;
    dispatch_semaphore_t _opened;
}
- (instancetype)initWithBNSession:(NSURLSession *)s request:(NSURLRequest *)r protocols:(NSArray *)protocols {
    if ((self = [super initWithBNSession:s request:r])) {
        _protocols = [protocols copy];
        _writer = dispatch_queue_create("bitten.websocket.writer", DISPATCH_QUEUE_SERIAL);
        _inbox = [NSMutableArray array];
        _waiting = [NSMutableArray array];
        _pongs = [NSMutableArray array];
        _maxSize = 1 << 20;
        _opened = dispatch_semaphore_create(0);
    }
    return self;
}
- (NSInteger)maximumMessageSize { return _maxSize; }
- (void)setMaximumMessageSize:(NSInteger)n { _maxSize = n; }
- (NSURLSessionWebSocketCloseCode)closeCode { return _closeCode; }
- (NSData *)closeReason { return _closeReason; }

/* Connects, then reads until the connection ends. */
- (void)_bn_run {
    NSURLSession *s = _sessionWhileRunning;
    NSURLSessionConfiguration *cfg = s->_configuration;
    NSURLRequest *req = _currentRequest;
    NSMutableArray *lines = [NSMutableArray array];
    NSDictionary *h = req.allHTTPHeaderFields;
    for (NSString *k in h) [lines addObject:[NSString stringWithFormat:@"%@: %@", k, h[k]]];
    if (!header_key_in(h, @"User-Agent")) [lines addObject:[@"User-Agent: " stringByAppendingString:default_user_agent()]];
    if (cfg.HTTPShouldSetCookies && cfg.HTTPCookieStorage && req.URL) {
        NSDictionary *c = [NSHTTPCookie requestHeaderFieldsWithCookies:[cfg.HTTPCookieStorage cookiesForURL:req.URL]];
        for (NSString *k in c) [lines addObject:[NSString stringWithFormat:@"%@: %@", k, c[k]]];
    }
    const char **hv = malloc(sizeof(char *) * (lines.count + 1));
    for (NSUInteger i = 0; i < lines.count; i++) hv[i] = [lines[i] UTF8String];
    bn_http_request r = {0};
    r.url = req.URL.absoluteString.UTF8String;
    r.headers = hv;
    r.nheaders = (int)lines.count;
    r.timeout = req.timeoutInterval > 0 ? req.timeoutInterval : cfg.timeoutIntervalForRequest;
    r.tls_min = cfg.TLSMinimumSupportedProtocolVersion;
    r.tls_max = cfg.TLSMaximumSupportedProtocolVersion;
    bn_http_result res;
    char *protocol = NULL;
    NSString *joined = [_protocols componentsJoinedByString:@", "];
    NSDate *start = [NSDate date];
    bn_ws *ws = _cancelled ? NULL : bitten_ws_open(&r, joined.length ? joined.UTF8String : NULL, &res, &protocol);
    free(hv);
    if (!ws) {
        NSError *e = url_error(_cancelled ? NSURLErrorCancelled : (res.error ?: NSURLErrorCannotConnectToHost), req.URL,
                               @(res.message));
        if (res.status) {
            NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:req.URL statusCode:res.status
                                                                 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
            @synchronized(self) { _response = resp; }
        }
        [self _bn_fail:e];
        dispatch_semaphore_signal(_opened);
        [self _bn_finishWithData:nil location:nil error:e];
        return;
    }
    _ws = ws;
    NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:req.URL statusCode:101 HTTPVersion:@"HTTP/1.1"
                                                        headerFields:@{@"Upgrade" : @"websocket", @"Connection" : @"Upgrade"}];
    @synchronized(self) { _response = resp; }
    _metrics = [NSURLSessionTaskMetrics new];
    _metrics->_transactions = [NSMutableArray arrayWithObject:metrics_from(req, resp, start, &res)];
    NSString *proto = protocol ? @(protocol) : nil;
    free(protocol);
    @synchronized(self) { _open = YES; }
    dispatch_semaphore_signal(_opened);
    id d = [self _bn_delegateFor:@selector(URLSession:webSocketTask:didOpenWithProtocol:)];
    if (d) [s _bn_onDelegateQueue:^{ [d URLSession:s webSocketTask:self didOpenWithProtocol:proto]; }];

    /* the reader */
    NSError *end = nil;
    BOOL serverClosed = NO;
    while (!_cancelled) {
        void *data = NULL;
        size_t len = 0;
        int code = 0;
        int op = bitten_ws_receive(ws, 0.25, &data, &len, &code);
        if (op == 0) continue;
        if (op < 0) {
            end = url_error(NSURLErrorNetworkConnectionLost, req.URL, nil);
            break;
        }
        _received += (int64_t)len;
        if (op == BN_WS_TEXT || op == BN_WS_BINARY) {
            if ((NSInteger)len > _maxSize) {
                free(data);
                unsigned char reason[2] = {1009 >> 8, 1009 & 255};
                bitten_ws_send(ws, BN_WS_CLOSE, reason, 2);
                end = [NSError errorWithDomain:NSPOSIXErrorDomain code:40 userInfo:@{NSLocalizedDescriptionKey : @"Message too long"}];
                break;
            }
            NSURLSessionWebSocketMessage *m =
                op == BN_WS_TEXT
                    ? [[NSURLSessionWebSocketMessage alloc] initWithString:[[NSString alloc] initWithBytes:data length:len
                                                                                                  encoding:NSUTF8StringEncoding] ?: @""]
                    : [[NSURLSessionWebSocketMessage alloc] initWithData:[NSData dataWithBytes:data length:len]];
            free(data);
            [self _bn_deliver:m];
        } else if (op == BN_WS_PONG) {
            free(data);
            void (^pong)(NSError *) = nil;
            @synchronized(self) {
                if (_pongs.count) {
                    pong = _pongs[0];
                    [_pongs removeObjectAtIndex:0];
                }
            }
            if (pong) [s _bn_onDelegateQueue:^{ pong(nil); }];
        } else if (op == BN_WS_CLOSE) {
            _closeCode = (NSURLSessionWebSocketCloseCode)code;
            _closeReason = len ? [NSData dataWithBytes:data length:len] : nil;
            free(data);
            serverClosed = YES;
            break;
        }
    }
    @synchronized(self) { _closed = YES; }
    if (serverClosed) {
        id cd = [self _bn_delegateFor:@selector(URLSession:webSocketTask:didCloseWithCode:reason:)];
        NSURLSessionWebSocketCloseCode cc = _closeCode;
        NSData *why = _closeReason;
        if (cd) [s _bn_onDelegateQueue:^{ [cd URLSession:s webSocketTask:self didCloseWithCode:cc reason:why]; }];
    }
    NSError *pending = end ?: [NSError errorWithDomain:NSPOSIXErrorDomain code:57
                                              userInfo:@{NSLocalizedDescriptionKey : @"Socket is not connected"}];
    [self _bn_fail:pending];
    dispatch_sync(_writer, ^{
        bitten_ws_free(self->_ws);
        self->_ws = NULL;
    });
    NSError *completion = end;
    if (_cancelled && _closeCode == NSURLSessionWebSocketCloseCodeInvalid)
        completion = url_error(NSURLErrorCancelled, req.URL, nil);
    [self _bn_finishWithData:nil location:nil error:completion];
}

- (void)_bn_deliver:(NSURLSessionWebSocketMessage *)m {
    BNWSReceive handler = nil;
    @synchronized(self) {
        if (_waiting.count) {
            handler = _waiting[0];
            [_waiting removeObjectAtIndex:0];
        } else {
            [_inbox addObject:m];
        }
    }
    if (handler) [_sessionWhileRunning _bn_onDelegateQueue:^{ handler(m, nil); }];
}
/* Everything still waiting gets the error. */
- (void)_bn_fail:(NSError *)e {
    NSArray *waiting, *pongs;
    @synchronized(self) {
        _failure = e;
        waiting = [_waiting copy];
        pongs = [_pongs copy];
        [_waiting removeAllObjects];
        [_pongs removeAllObjects];
    }
    NSURLSession *s = _sessionWhileRunning ?: _session;
    for (BNWSReceive h in waiting) [s _bn_onDelegateQueue:^{ h(nil, e); }];
    for (void (^p)(NSError *) in pongs) [s _bn_onDelegateQueue:^{ p(e); }];
}

- (void)receiveMessageWithCompletionHandler:(void (^)(NSURLSessionWebSocketMessage *, NSError *))handler {
    NSURLSessionWebSocketMessage *m = nil;
    NSError *e = nil;
    @synchronized(self) {
        if (_inbox.count) {
            m = _inbox[0];
            [_inbox removeObjectAtIndex:0];
        } else if (_failure || _closed) {
            e = _failure;
        } else {
            [_waiting addObject:[handler copy]];
            return;
        }
    }
    NSURLSession *s = _sessionWhileRunning ?: _session;
    [s _bn_onDelegateQueue:^{ handler(m, e); }];
}

/* Sends wait for the handshake, then go out in order. */
- (void)_bn_write:(int)opcode data:(NSData *)data completion:(void (^)(NSError *))completion {
    NSURLSession *s = _sessionWhileRunning ?: _session;
    dispatch_async(_writer, ^{
        BOOL open;
        @synchronized(self) { open = self->_open; }
        if (!open && !self->_failure) {
            dispatch_semaphore_wait(self->_opened, DISPATCH_TIME_FOREVER);
            dispatch_semaphore_signal(self->_opened);
        }
        NSError *e = nil;
        @synchronized(self) {
            if (self->_failure) e = self->_failure;
            else if (self->_closed || !self->_ws) e = [NSError errorWithDomain:NSPOSIXErrorDomain code:57 userInfo:nil];
        }
        if (!e) {
            int rc = bitten_ws_send(self->_ws, opcode, data.bytes, data.length);
            if (rc) e = url_error(rc, self->_currentRequest.URL, nil);
            else self->_sent += (int64_t)data.length;
        }
        if (completion) [s _bn_onDelegateQueue:^{ completion(e); }];
    });
}
- (void)sendMessage:(NSURLSessionWebSocketMessage *)message completionHandler:(void (^)(NSError *))completionHandler {
    if (message.type == NSURLSessionWebSocketMessageTypeString)
        [self _bn_write:BN_WS_TEXT data:[message.string dataUsingEncoding:NSUTF8StringEncoding] completion:completionHandler];
    else
        [self _bn_write:BN_WS_BINARY data:message.data ?: [NSData data] completion:completionHandler];
}
- (void)sendPingWithPongReceiveHandler:(void (^)(NSError *))pongReceiveHandler {
    @synchronized(self) {
        if (pongReceiveHandler) [_pongs addObject:[pongReceiveHandler copy]];
    }
    [self _bn_write:BN_WS_PING data:[NSData data] completion:^(NSError *e) {
        if (e && pongReceiveHandler) {
            BOOL mine;
            @synchronized(self) {
                mine = [self->_pongs containsObject:pongReceiveHandler];
                [self->_pongs removeObject:pongReceiveHandler];
            }
            if (mine) pongReceiveHandler(e);
        }
    }];
}
- (void)cancelWithCloseCode:(NSURLSessionWebSocketCloseCode)code reason:(NSData *)reason {
    _closeCode = code;
    _closeReason = [reason copy];
    NSMutableData *payload = [NSMutableData data];
    if (code != NSURLSessionWebSocketCloseCodeInvalid) {
        unsigned char c[2] = {(unsigned char)(code >> 8), (unsigned char)(code & 255)};
        [payload appendBytes:c length:2];
        if (reason) [payload appendData:reason];
    }
    [self _bn_write:BN_WS_CLOSE data:payload completion:^(NSError *e) { [self cancel]; }];
}
- (void)cancel {
    @synchronized(self) {
        if (_state == NSURLSessionTaskStateCompleted) return;
    }
    BOOL started;
    @synchronized(self) { started = _started; }
    if (started) {
        _cancelled = 1;
        @synchronized(self) { _state = NSURLSessionTaskStateCanceling; }
        return;
    }
    [super cancel];
}
@end

/* ---- the session ---- */

@implementation NSURLSession {
    id<NSURLSessionDelegate> _delegate;
    NSOperationQueue *_queue;
    NSMutableArray<NSURLSessionTask *> *_tasks;
    NSString *_sessionDescription;
    BOOL _invalidating, _invalid;
}
+ (NSURLSession *)sharedSession {
    static NSURLSession *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]]; });
    return s;
}
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)c {
    return [self sessionWithConfiguration:c delegate:nil delegateQueue:nil];
}
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)c delegate:(id<NSURLSessionDelegate>)d
                             delegateQueue:(NSOperationQueue *)q {
    NSURLSession *s = [self new];
    s->_configuration = [c copy] ?: [NSURLSessionConfiguration defaultSessionConfiguration];
    s->_delegate = d;
    if (!q) {
        q = [NSOperationQueue new];
        q.maxConcurrentOperationCount = 1;
        q.name = @"NSURLSession delegate queue";
    }
    s->_queue = q;
    s->_tasks = [NSMutableArray array];
    return s;
}
- (NSOperationQueue *)delegateQueue { return _queue; }
- (id<NSURLSessionDelegate>)delegate { return _delegate; }
- (id)_bn_delegate { return _delegate; }
- (NSURLSessionConfiguration *)configuration { return [_configuration copy]; }
- (NSString *)sessionDescription { return _sessionDescription; }
- (void)setSessionDescription:(NSString *)d { _sessionDescription = [d copy]; }
- (void)_bn_onDelegateQueue:(void (^)(void))block { [_queue addOperationWithBlock:block]; }

- (id)_bn_add:(NSURLSessionTask *)t {
    @synchronized(self) {
        if (_invalidating) {
            t->_state = NSURLSessionTaskStateCompleted;
            return t;
        }
        [_tasks addObject:t];
    }
    id<NSURLSessionTaskDelegate> d = (id)_delegate;
    if ([d respondsToSelector:@selector(URLSession:didCreateTask:)]) [d URLSession:self didCreateTask:t];
    return t;
}
- (void)_bn_taskFinished:(NSURLSessionTask *)t {
    BOOL done;
    @synchronized(self) {
        [_tasks removeObjectIdenticalTo:t];
        done = _invalidating && !_tasks.count && !_invalid;
        if (done) _invalid = YES;
    }
    if (done) [self _bn_invalidated];
}
- (void)_bn_invalidated {
    id d = _delegate;
    [self _bn_onDelegateQueue:^{
        if ([d respondsToSelector:@selector(URLSession:didBecomeInvalidWithError:)]) [d URLSession:self didBecomeInvalidWithError:nil];
        self->_delegate = nil;
    }];
}
- (void)finishTasksAndInvalidate {
    if (self == [NSURLSession sharedSession]) return;
    BOOL now;
    @synchronized(self) {
        _invalidating = YES;
        now = !_tasks.count && !_invalid;
        if (now) _invalid = YES;
    }
    if (now) [self _bn_invalidated];
}
- (void)invalidateAndCancel {
    if (self == [NSURLSession sharedSession]) return;
    NSArray *tasks;
    @synchronized(self) {
        _invalidating = YES;
        tasks = [_tasks copy];
    }
    for (NSURLSessionTask *t in tasks) [t cancel];
    [self finishTasksAndInvalidate];
}
- (void)resetWithCompletionHandler:(void (^)(void))h {
    [_configuration.HTTPCookieStorage removeCookiesSinceDate:[NSDate distantPast]];
    [_configuration.URLCache removeAllCachedResponses];
    [self _bn_onDelegateQueue:h];
}
- (void)flushWithCompletionHandler:(void (^)(void))h { [self _bn_onDelegateQueue:h]; }
- (void)getTasksWithCompletionHandler:(void (^)(NSArray<NSURLSessionDataTask *> *, NSArray<NSURLSessionUploadTask *> *,
                                                NSArray<NSURLSessionDownloadTask *> *))h {
    NSArray *all;
    @synchronized(self) { all = [_tasks copy]; }
    NSMutableArray *data = [NSMutableArray array], *up = [NSMutableArray array], *down = [NSMutableArray array];
    for (id t in all) {
        if ([t isKindOfClass:[NSURLSessionUploadTask class]]) [up addObject:t];
        else if ([t isKindOfClass:[NSURLSessionDataTask class]]) [data addObject:t];
        else if ([t isKindOfClass:[NSURLSessionDownloadTask class]]) [down addObject:t];
    }
    [self _bn_onDelegateQueue:^{ h(data, up, down); }];
}
- (void)getAllTasksWithCompletionHandler:(void (^)(NSArray<__kindof NSURLSessionTask *> *))h {
    NSArray *all;
    @synchronized(self) { all = [_tasks copy]; }
    [self _bn_onDelegateQueue:^{ h(all); }];
}

- (NSURLRequest *)_bn_request:(NSURLRequest *)r {
    if (r.cachePolicy == NSURLRequestUseProtocolCachePolicy && _configuration.requestCachePolicy != NSURLRequestUseProtocolCachePolicy) {
        NSMutableURLRequest *m = [r mutableCopy];
        m.cachePolicy = _configuration.requestCachePolicy;
        return m;
    }
    return r;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)r {
    return [self _bn_add:[[NSURLSessionDataTask alloc] initWithBNSession:self request:[self _bn_request:r]]];
}
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)u { return [self dataTaskWithRequest:[NSURLRequest requestWithURL:u]]; }
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)r fromFile:(NSURL *)f {
    NSURLSessionUploadTask *t = [[NSURLSessionUploadTask alloc] initWithBNSession:self request:[self _bn_request:r]];
    t->_uploadFile = f;
    return [self _bn_add:t];
}
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)r fromData:(NSData *)d {
    NSURLSessionUploadTask *t = [[NSURLSessionUploadTask alloc] initWithBNSession:self request:[self _bn_request:r]];
    t->_uploadData = d ? [d copy] : [NSData data];
    return [self _bn_add:t];
}
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)r {
    return [self _bn_add:[[NSURLSessionDownloadTask alloc] initWithBNSession:self request:[self _bn_request:r]]];
}
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)u { return [self downloadTaskWithRequest:[NSURLRequest requestWithURL:u]]; }
- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)d {
    NSURL *u = [NSURL URLWithString:@"about:blank"];
    return [self downloadTaskWithURL:u];
}
- (NSURLSessionWebSocketTask *)webSocketTaskWithURL:(NSURL *)u { return [self webSocketTaskWithURL:u protocols:@[]]; }
- (NSURLSessionWebSocketTask *)webSocketTaskWithURL:(NSURL *)u protocols:(NSArray<NSString *> *)p {
    return [self _bn_add:[[NSURLSessionWebSocketTask alloc] initWithBNSession:self request:[NSURLRequest requestWithURL:u]
                                                                    protocols:p]];
}
- (NSURLSessionWebSocketTask *)webSocketTaskWithRequest:(NSURLRequest *)r {
    NSString *p = [r valueForHTTPHeaderField:@"Sec-WebSocket-Protocol"];
    NSMutableURLRequest *m = [r mutableCopy];
    [m setValue:nil forHTTPHeaderField:@"Sec-WebSocket-Protocol"];
    NSMutableArray *protocols = [NSMutableArray array];
    for (NSString *x in [p componentsSeparatedByString:@","] ?: @[]) {
        NSString *t = [x stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (t.length) [protocols addObject:t];
    }
    return [self _bn_add:[[NSURLSessionWebSocketTask alloc] initWithBNSession:self request:m protocols:protocols]];
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)r completionHandler:(BNDataCompletion)h {
    NSURLSessionDataTask *t = [self dataTaskWithRequest:r];
    t->_dataCompletion = [h copy];
    return t;
}
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)u completionHandler:(BNDataCompletion)h {
    return [self dataTaskWithRequest:[NSURLRequest requestWithURL:u] completionHandler:h];
}
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)r fromFile:(NSURL *)f completionHandler:(BNDataCompletion)h {
    NSURLSessionUploadTask *t = [self uploadTaskWithRequest:r fromFile:f];
    t->_dataCompletion = [h copy];
    return t;
}
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)r fromData:(NSData *)d completionHandler:(BNDataCompletion)h {
    NSURLSessionUploadTask *t = [self uploadTaskWithRequest:r fromData:d ?: [NSData data]];
    t->_dataCompletion = [h copy];
    return t;
}
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)r completionHandler:(BNDownloadCompletion)h {
    NSURLSessionDownloadTask *t = [self downloadTaskWithRequest:r];
    t->_downloadCompletion = [h copy];
    return t;
}
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)u completionHandler:(BNDownloadCompletion)h {
    return [self downloadTaskWithRequest:[NSURLRequest requestWithURL:u] completionHandler:h];
}
@end
