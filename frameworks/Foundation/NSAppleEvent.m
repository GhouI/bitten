/* Apple event descriptors, the Apple event manager, and Cocoa scripting.
 *
 * Descriptors hold their value as AppKit's would: a type code and bytes
 * (UTF-16 for text, native integers and doubles, seconds since 1904 for
 * dates, a URL string for file URLs), or items for lists, records and
 * events (parameters and attributes by keyword).
 *
 * There is no Apple event transport between processes here: an event
 * sent to this process goes straight to its handler, and nothing else
 * arrives. Handlers are set with setEventHandler:andSelector:...; an event
 * with no handler goes to the scripting commands of the application's
 * scripting definition (the sdef its Info.plist names), which are read on
 * first use: the command's class is made, given its direct parameter,
 * receivers and arguments, and executed, and its result is the reply. */
#import <Foundation/Foundation.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

NSNotificationName const NSAppleEventManagerWillProcessFirstEventNotification =
    @"NSAppleEventManagerWillProcessFirstEventNotification";

static NSString *fourcc(FourCharCode c) {
    char s[5] = {(char)(c >> 24), (char)(c >> 16), (char)(c >> 8), (char)c, 0};
    return [NSString stringWithFormat:@"'%s'", s];
}
static FourCharCode code_from(NSString *s) {
    const char *u = s.UTF8String;
    if (!u || strlen(u) < 4) return 0;
    return (FourCharCode)(unsigned char)u[0] << 24 | (FourCharCode)(unsigned char)u[1] << 16 |
           (FourCharCode)(unsigned char)u[2] << 8 | (unsigned char)u[3];
}

/* ---- descriptors ---- */

@interface NSAppleEventDescriptor ()
- (void)_bn_setType:(DescType)t;
@end

static const double kSeconds1904To2001 = 3061152000.0;

@implementation NSAppleEventDescriptor {
    DescType _type;
    NSData *_data;
    NSMutableArray<NSAppleEventDescriptor *> *_items;   /* lists */
    NSMutableArray<NSNumber *> *_keys;                   /* records and events: keywords of _items */
    NSMutableDictionary<NSNumber *, NSAppleEventDescriptor *> *_attributes;
    AEDesc _aedesc;
}

- (instancetype)initWithDescriptorType:(DescType)t bytes:(const void *)bytes length:(NSUInteger)n {
    if ((self = [super init])) {
        _type = t;
        _data = bytes && n ? [NSData dataWithBytes:bytes length:n] : [NSData data];
    }
    return self;
}
- (instancetype)initWithDescriptorType:(DescType)t data:(NSData *)data {
    return [self initWithDescriptorType:t bytes:data.bytes length:data.length];
}
- (instancetype)initWithAEDescNoCopy:(const AEDesc *)d {
    return [self initWithDescriptorType:d ? d->descriptorType : typeNull bytes:NULL length:0];
}
- (instancetype)initListDescriptor {
    if ((self = [self initWithDescriptorType:typeAEList bytes:NULL length:0])) _items = [NSMutableArray array];
    return self;
}
- (instancetype)initRecordDescriptor {
    if ((self = [self initWithDescriptorType:typeAERecord bytes:NULL length:0])) {
        _items = [NSMutableArray array];
        _keys = [NSMutableArray array];
    }
    return self;
}
- (instancetype)initWithEventClass:(AEEventClass)eventClass eventID:(AEEventID)eventID
                  targetDescriptor:(NSAppleEventDescriptor *)target
                          returnID:(AEReturnID)returnID
                     transactionID:(AETransactionID)transactionID {
    if ((self = [self initRecordDescriptor])) {
        _type = typeAppleEvent;
        _attributes = [NSMutableDictionary dictionary];
        static int16_t nextReturnID = 1;
        if (returnID == kAutoGenerateReturnID) returnID = nextReturnID++;
        [self setAttributeDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:eventClass] forKeyword:keyEventClassAttr];
        [self setAttributeDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:eventID] forKeyword:keyEventIDAttr];
        int16_t r = returnID;
        [self setAttributeDescriptor:[NSAppleEventDescriptor descriptorWithDescriptorType:typeSInt16 bytes:&r length:2]
                          forKeyword:keyReturnIDAttr];
        [self setAttributeDescriptor:[NSAppleEventDescriptor descriptorWithInt32:transactionID]
                          forKeyword:keyTransactionIDAttr];
        if (target) [self setAttributeDescriptor:target forKeyword:keyAddressAttr];
    }
    return self;
}

+ (NSAppleEventDescriptor *)nullDescriptor { return [[self alloc] initWithDescriptorType:typeNull bytes:NULL length:0]; }
+ (NSAppleEventDescriptor *)descriptorWithDescriptorType:(DescType)t bytes:(const void *)b length:(NSUInteger)n {
    return [[self alloc] initWithDescriptorType:t bytes:b length:n];
}
+ (NSAppleEventDescriptor *)descriptorWithDescriptorType:(DescType)t data:(NSData *)d {
    return [[self alloc] initWithDescriptorType:t data:d];
}
+ (NSAppleEventDescriptor *)descriptorWithBoolean:(Boolean)b {
    uint8_t v = b ? 1 : 0;
    return [self descriptorWithDescriptorType:typeBoolean bytes:&v length:1];
}
+ (NSAppleEventDescriptor *)descriptorWithEnumCode:(OSType)e { return [self descriptorWithDescriptorType:typeEnumerated bytes:&e length:4]; }
+ (NSAppleEventDescriptor *)descriptorWithInt32:(SInt32)i { return [self descriptorWithDescriptorType:typeSInt32 bytes:&i length:4]; }
+ (NSAppleEventDescriptor *)descriptorWithDouble:(double)d {
    return [self descriptorWithDescriptorType:typeIEEE64BitFloatingPoint bytes:&d length:8];
}
+ (NSAppleEventDescriptor *)descriptorWithTypeCode:(OSType)t { return [self descriptorWithDescriptorType:typeType bytes:&t length:4]; }
+ (NSAppleEventDescriptor *)descriptorWithString:(NSString *)s {
    NSUInteger n = s.length;
    unichar *buf = malloc(n * sizeof(unichar) + 1);
    [s getCharacters:buf range:NSMakeRange(0, n)];
    NSAppleEventDescriptor *d = [self descriptorWithDescriptorType:typeUnicodeText bytes:buf length:n * sizeof(unichar)];
    free(buf);
    return d;
}
+ (NSAppleEventDescriptor *)descriptorWithDate:(NSDate *)date {
    int64_t secs = (int64_t)(date.timeIntervalSinceReferenceDate + kSeconds1904To2001);
    return [self descriptorWithDescriptorType:typeLongDateTime bytes:&secs length:8];
}
+ (NSAppleEventDescriptor *)descriptorWithFileURL:(NSURL *)url {
    NSData *d = [url.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
    return [self descriptorWithDescriptorType:typeFileURL data:d];
}
+ (NSAppleEventDescriptor *)appleEventWithEventClass:(AEEventClass)c eventID:(AEEventID)i
                                    targetDescriptor:(NSAppleEventDescriptor *)t
                                            returnID:(AEReturnID)r
                                       transactionID:(AETransactionID)x {
    return [[self alloc] initWithEventClass:c eventID:i targetDescriptor:t returnID:r transactionID:x];
}
+ (NSAppleEventDescriptor *)listDescriptor { return [[self alloc] initListDescriptor]; }
+ (NSAppleEventDescriptor *)recordDescriptor { return [[self alloc] initRecordDescriptor]; }
+ (NSAppleEventDescriptor *)currentProcessDescriptor {
    pid_t p = getpid();
    return [self descriptorWithDescriptorType:typeKernelProcessID bytes:&p length:sizeof p];
}
+ (NSAppleEventDescriptor *)descriptorWithProcessIdentifier:(pid_t)p {
    return [self descriptorWithDescriptorType:typeKernelProcessID bytes:&p length:sizeof p];
}
+ (NSAppleEventDescriptor *)descriptorWithBundleIdentifier:(NSString *)b {
    return [self descriptorWithDescriptorType:typeApplicationBundleID data:[b dataUsingEncoding:NSUTF8StringEncoding]];
}
+ (NSAppleEventDescriptor *)descriptorWithApplicationURL:(NSURL *)u {
    return [self descriptorWithDescriptorType:typeApplicationURL data:[u.absoluteString dataUsingEncoding:NSUTF8StringEncoding]];
}

- (id)copyWithZone:(NSZone *)zone {
    NSAppleEventDescriptor *c = [[NSAppleEventDescriptor alloc] initWithDescriptorType:_type data:_data];
    if (_items) c->_items = [NSMutableArray arrayWithArray:_items];
    if (_keys) c->_keys = [NSMutableArray arrayWithArray:_keys];
    if (_attributes) c->_attributes = [NSMutableDictionary dictionaryWithDictionary:_attributes];
    return c;
}

- (const AEDesc *)aeDesc {
    _aedesc.descriptorType = _type;
    _aedesc.dataHandle = NULL;
    return &_aedesc;
}
- (DescType)descriptorType { return _type; }
- (void)_bn_setType:(DescType)t { _type = t; }
- (NSData *)data { return _data ?: [NSData data]; }
- (BOOL)isRecordDescriptor { return _type == typeAERecord || (_keys != nil && _type != typeAppleEvent); }

/* ---- values ---- */

- (Boolean)booleanValue {
    NSAppleEventDescriptor *d = [self coerceToDescriptorType:typeBoolean];
    return d && d->_data.length && ((const uint8_t *)d->_data.bytes)[0];
}
- (OSType)enumCodeValue {
    OSType v = 0;
    if (_data.length >= 4) memcpy(&v, _data.bytes, 4);
    return v;
}
- (OSType)typeCodeValue { return self.enumCodeValue; }
- (SInt32)int32Value {
    NSAppleEventDescriptor *d = [self coerceToDescriptorType:typeSInt32];
    SInt32 v = 0;
    if (d && d->_data.length >= 4) memcpy(&v, d->_data.bytes, 4);
    return v;
}
- (double)doubleValue {
    NSAppleEventDescriptor *d = [self coerceToDescriptorType:typeIEEE64BitFloatingPoint];
    double v = 0;
    if (d && d->_data.length >= 8) memcpy(&v, d->_data.bytes, 8);
    return v;
}
- (NSString *)stringValue {
    NSAppleEventDescriptor *d = [self coerceToDescriptorType:typeUnicodeText];
    if (!d) return nil;
    return [NSString stringWithCharacters:d->_data.bytes length:d->_data.length / sizeof(unichar)];
}
- (NSDate *)dateValue {
    if (_type != typeLongDateTime || _data.length < 8) return nil;
    int64_t secs;
    memcpy(&secs, _data.bytes, 8);
    return [NSDate dateWithTimeIntervalSinceReferenceDate:(double)secs - kSeconds1904To2001];
}
- (NSURL *)fileURLValue {
    if (_type == typeFileURL || _type == typeApplicationURL) {
        NSString *s = [[NSString alloc] initWithData:_data encoding:NSUTF8StringEncoding];
        return s ? [NSURL URLWithString:s] : nil;
    }
    NSString *s = self.stringValue;
    if (!s.length) return nil;
    if ([s hasPrefix:@"file:"]) return [NSURL URLWithString:s];
    return [s hasPrefix:@"/"] ? [NSURL fileURLWithPath:s] : nil;
}

/* Coercions between the plain types. */
- (NSAppleEventDescriptor *)coerceToDescriptorType:(DescType)t {
    if (t == _type || t == typeWildCard) return self;
    const void *b = _data.bytes;
    NSUInteger n = _data.length;
    NSString *text = nil;
    double num = 0;
    BOOL numeric = YES;
    switch (_type) {
    case typeUnicodeText: text = [NSString stringWithCharacters:b length:n / sizeof(unichar)]; break;
    case typeUTF8Text: case typeChar: text = [[NSString alloc] initWithData:_data encoding:NSUTF8StringEncoding]; break;
    case typeUTF16ExternalRepresentation: text = [[NSString alloc] initWithData:_data encoding:NSUTF16StringEncoding]; break;
    case typeSInt32: { int32_t v = 0; if (n >= 4) memcpy(&v, b, 4); num = v; break; }
    case typeSInt16: { int16_t v = 0; if (n >= 2) memcpy(&v, b, 2); num = v; break; }
    case typeUInt32: { uint32_t v = 0; if (n >= 4) memcpy(&v, b, 4); num = v; break; }
    case typeSInt64: { int64_t v = 0; if (n >= 8) memcpy(&v, b, 8); num = (double)v; break; }
    case typeIEEE64BitFloatingPoint: { double v = 0; if (n >= 8) memcpy(&v, b, 8); num = v; break; }
    case typeIEEE32BitFloatingPoint: { float v = 0; if (n >= 4) memcpy(&v, b, 4); num = v; break; }
    case typeBoolean: num = n && ((const uint8_t *)b)[0]; break;
    case typeTrue: num = 1; break;
    case typeFalse: num = 0; break;
    case typeFileURL: text = [[NSString alloc] initWithData:_data encoding:NSUTF8StringEncoding]; break;
    case typeEnumerated: case typeType: case typeKeyword:
        if (t == typeType || t == typeEnumerated || t == typeKeyword)
            return [NSAppleEventDescriptor descriptorWithDescriptorType:t data:_data];
        numeric = NO;
        break;
    default: numeric = NO;
    }
    if (text) {
        switch (t) {
        case typeUnicodeText: return [NSAppleEventDescriptor descriptorWithString:text];
        case typeUTF8Text: case typeChar:
            return [NSAppleEventDescriptor descriptorWithDescriptorType:t data:[text dataUsingEncoding:NSUTF8StringEncoding]];
        case typeSInt32: return [NSAppleEventDescriptor descriptorWithInt32:(SInt32)text.intValue];
        case typeIEEE64BitFloatingPoint: return [NSAppleEventDescriptor descriptorWithDouble:text.doubleValue];
        case typeBoolean:
            return [NSAppleEventDescriptor descriptorWithBoolean:[text.lowercaseString isEqual:@"true"] || text.intValue != 0];
        case typeFileURL: {
            NSURL *u = [text hasPrefix:@"/"] ? [NSURL fileURLWithPath:text] : [NSURL URLWithString:text];
            return u ? [NSAppleEventDescriptor descriptorWithFileURL:u] : nil;
        }
        }
        return nil;
    }
    if (!numeric) return nil;
    switch (t) {
    case typeSInt32: return [NSAppleEventDescriptor descriptorWithInt32:(SInt32)num];
    case typeIEEE64BitFloatingPoint: return [NSAppleEventDescriptor descriptorWithDouble:num];
    case typeBoolean: return [NSAppleEventDescriptor descriptorWithBoolean:num != 0];
    case typeUnicodeText:
        return [NSAppleEventDescriptor descriptorWithString:(_type == typeBoolean || _type == typeTrue || _type == typeFalse)
                                                                ? (num != 0 ? @"true" : @"false")
                                                                : [NSString stringWithFormat:@"%g", num]];
    }
    return nil;
}

/* ---- events ---- */

- (AEEventClass)eventClass { return [self attributeDescriptorForKeyword:keyEventClassAttr].typeCodeValue; }
- (AEEventID)eventID { return [self attributeDescriptorForKeyword:keyEventIDAttr].typeCodeValue; }
- (AEReturnID)returnID {
    NSData *d = [self attributeDescriptorForKeyword:keyReturnIDAttr].data;
    int16_t v = 0;
    if (d.length >= 2) memcpy(&v, d.bytes, 2);
    return v;
}
- (AETransactionID)transactionID { return [self attributeDescriptorForKeyword:keyTransactionIDAttr].int32Value; }

- (void)setParamDescriptor:(NSAppleEventDescriptor *)d forKeyword:(AEKeyword)k { [self setDescriptor:d forKeyword:k]; }
- (NSAppleEventDescriptor *)paramDescriptorForKeyword:(AEKeyword)k { return [self descriptorForKeyword:k]; }
- (void)removeParamDescriptorWithKeyword:(AEKeyword)k { [self removeDescriptorWithKeyword:k]; }
- (void)setAttributeDescriptor:(NSAppleEventDescriptor *)d forKeyword:(AEKeyword)k {
    if (!_attributes) _attributes = [NSMutableDictionary dictionary];
    if (d) _attributes[@(k)] = d;
    else [_attributes removeObjectForKey:@(k)];
}
- (NSAppleEventDescriptor *)attributeDescriptorForKeyword:(AEKeyword)k { return _attributes[@(k)]; }

/* ---- lists and records ---- */

- (NSInteger)numberOfItems { return (NSInteger)_items.count; }
/* Indexes are one-based, as in the Apple Event Manager; 0 appends. */
- (void)insertDescriptor:(NSAppleEventDescriptor *)d atIndex:(NSInteger)i {
    if (!d) return;
    if (!_items) _items = [NSMutableArray array];
    NSUInteger at = i <= 0 || (NSUInteger)i > _items.count ? _items.count : (NSUInteger)i - 1;
    [_items insertObject:d atIndex:at];
    if (_keys) [_keys insertObject:@0 atIndex:at];
}
- (NSAppleEventDescriptor *)descriptorAtIndex:(NSInteger)i {
    if (i < 1 || (NSUInteger)i > _items.count) return nil;
    return _items[(NSUInteger)i - 1];
}
- (void)removeDescriptorAtIndex:(NSInteger)i {
    if (i < 1 || (NSUInteger)i > _items.count) return;
    [_items removeObjectAtIndex:(NSUInteger)i - 1];
    if (_keys) [_keys removeObjectAtIndex:(NSUInteger)i - 1];
}
- (void)setDescriptor:(NSAppleEventDescriptor *)d forKeyword:(AEKeyword)k {
    if (!_items) _items = [NSMutableArray array];
    if (!_keys) {
        _keys = [NSMutableArray array];
        for (NSUInteger i = 0; i < _items.count; i++) [_keys addObject:@0];
    }
    NSUInteger at = [_keys indexOfObject:@(k)];
    if (!d) {
        if (at != NSNotFound) {
            [_items removeObjectAtIndex:at];
            [_keys removeObjectAtIndex:at];
        }
        return;
    }
    if (at != NSNotFound) _items[at] = d;
    else {
        [_items addObject:d];
        [_keys addObject:@(k)];
    }
}
- (NSAppleEventDescriptor *)descriptorForKeyword:(AEKeyword)k {
    NSUInteger at = _keys ? [_keys indexOfObject:@(k)] : NSNotFound;
    return at == NSNotFound ? nil : _items[at];
}
- (void)removeDescriptorWithKeyword:(AEKeyword)k { [self setDescriptor:(id _Nonnull)nil forKeyword:k]; }
- (AEKeyword)keywordForDescriptorAtIndex:(NSInteger)i {
    if (!_keys || i < 1 || (NSUInteger)i > _keys.count) return 0;
    return (AEKeyword)_keys[(NSUInteger)i - 1].unsignedIntValue;
}

- (NSAppleEventDescriptor *)sendEventWithOptions:(NSAppleEventSendOptions)options timeout:(NSTimeInterval)timeout
                                           error:(NSError **)error {
    NSAppleEventDescriptor *target = [self attributeDescriptorForKeyword:keyAddressAttr];
    BOOL toSelf = !target;
    if (target.descriptorType == typeKernelProcessID && target.data.length >= sizeof(pid_t)) {
        pid_t p;
        memcpy(&p, target.data.bytes, sizeof p);
        toSelf = p == getpid();
    } else if (target.descriptorType == typeApplicationBundleID) {
        NSString *b = [[NSString alloc] initWithData:target.data encoding:NSUTF8StringEncoding];
        toSelf = [b isEqual:[NSBundle mainBundle].bundleIdentifier];
    } else if (target.descriptorType == typeProcessSerialNumber) {
        toSelf = YES; /* kCurrentProcess */
    }
    if (!toSelf) {
        if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:procNotFound userInfo:nil];
        return nil;
    }
    NSAppleEventDescriptor *reply = [[NSAppleEventManager sharedAppleEventManager] _bn_dispatchEvent:self];
    NSAppleEventDescriptor *err = [reply paramDescriptorForKeyword:keyErrorNumber];
    if (err && err.int32Value != 0) {
        if (error) {
            NSString *msg = [reply paramDescriptorForKeyword:keyErrorString].stringValue;
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err.int32Value
                                     userInfo:msg ? @{NSLocalizedDescriptionKey : msg} : nil];
        }
        return nil;
    }
    return reply;
}

- (NSString *)description {
    if (_type == typeAppleEvent) {
        return [NSString stringWithFormat:@"<NSAppleEventDescriptor: %@\\%@ %@>", fourcc(self.eventClass),
                                          fourcc(self.eventID), [self _bn_itemsDescription]];
    }
    if (_items) return [NSString stringWithFormat:@"<NSAppleEventDescriptor: %@>", [self _bn_itemsDescription]];
    NSString *s = self.stringValue;
    if (s && (_type == typeUnicodeText || _type == typeUTF8Text || _type == typeChar))
        return [NSString stringWithFormat:@"<NSAppleEventDescriptor: \"%@\">", s];
    return [NSString stringWithFormat:@"<NSAppleEventDescriptor: %@ (%lu bytes)>", fourcc(_type),
                                      (unsigned long)_data.length];
}
- (NSString *)_bn_itemsDescription {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSUInteger i = 0; i < _items.count; i++) {
        NSString *v = _items[i].description;
        if (_keys && _keys[i].unsignedIntValue) [parts addObject:[NSString stringWithFormat:@"%@:%@", fourcc(_keys[i].unsignedIntValue), v]];
        else [parts addObject:v];
    }
    return [NSString stringWithFormat:@"{ %@ }", [parts componentsJoinedByString:@", "]];
}
@end

/* ---- objects and descriptors ---- */

static id object_from(NSAppleEventDescriptor *d);
static NSAppleEventDescriptor *descriptor_from(id o);

static id object_from(NSAppleEventDescriptor *d) {
    if (!d) return nil;
    switch (d.descriptorType) {
    case typeNull: return nil;
    case typeUnicodeText: case typeUTF8Text: case typeChar: case typeUTF16ExternalRepresentation: return d.stringValue;
    case typeBoolean: case typeTrue: case typeFalse: return @(d.booleanValue != 0);
    case typeSInt16: case typeSInt32: case typeUInt32: return @(d.int32Value);
    case typeSInt64: case typeIEEE64BitFloatingPoint: case typeIEEE32BitFloatingPoint: return @(d.doubleValue);
    case typeLongDateTime: return d.dateValue;
    case typeFileURL: return d.fileURLValue;
    case typeType: case typeEnumerated: case typeKeyword: return @(d.typeCodeValue);
    case typeObjectSpecifier: return [NSScriptObjectSpecifier objectSpecifierWithDescriptor:d];
    case typeAEList: {
        NSMutableArray *a = [NSMutableArray array];
        for (NSInteger i = 1; i <= d.numberOfItems; i++) {
            id o = object_from([d descriptorAtIndex:i]);
            [a addObject:o ?: [NSNull null]];
        }
        return a;
    }
    case typeAERecord: {
        NSMutableDictionary *r = [NSMutableDictionary dictionary];
        for (NSInteger i = 1; i <= d.numberOfItems; i++) {
            id o = object_from([d descriptorAtIndex:i]);
            r[fourcc([d keywordForDescriptorAtIndex:i])] = o ?: [NSNull null];
        }
        return r;
    }
    default: return d;
    }
}

static NSAppleEventDescriptor *descriptor_from(id o) {
    if (!o || o == [NSNull null]) return [NSAppleEventDescriptor nullDescriptor];
    if ([o isKindOfClass:[NSAppleEventDescriptor class]]) return o;
    if ([o isKindOfClass:[NSString class]]) return [NSAppleEventDescriptor descriptorWithString:o];
    if ([o isKindOfClass:[NSNumber class]]) {
        NSNumber *n = o;
        const char *t = n.objCType;
        if (!strcmp(t, "c") || !strcmp(t, "B")) return [NSAppleEventDescriptor descriptorWithBoolean:n.boolValue];
        if (!strcmp(t, "d") || !strcmp(t, "f")) return [NSAppleEventDescriptor descriptorWithDouble:n.doubleValue];
        long long v = n.longLongValue;
        if (v >= INT32_MIN && v <= INT32_MAX) return [NSAppleEventDescriptor descriptorWithInt32:(SInt32)v];
        return [NSAppleEventDescriptor descriptorWithDouble:n.doubleValue];
    }
    if ([o isKindOfClass:[NSDate class]]) return [NSAppleEventDescriptor descriptorWithDate:o];
    if ([o isKindOfClass:[NSURL class]]) return [NSAppleEventDescriptor descriptorWithFileURL:o];
    if ([o isKindOfClass:[NSArray class]]) {
        NSAppleEventDescriptor *l = [NSAppleEventDescriptor listDescriptor];
        for (id e in o) [l insertDescriptor:descriptor_from(e) atIndex:0];
        return l;
    }
    if ([o isKindOfClass:[NSScriptObjectSpecifier class]]) return ((NSScriptObjectSpecifier *)o).descriptor;
    NSScriptObjectSpecifier *spec = [o objectSpecifier];
    if (spec.descriptor) return spec.descriptor;
    return [NSAppleEventDescriptor descriptorWithString:[o description]];
}

/* ---- the scripting definition ---- */

/* A small reader for the sdef: tags with attributes, in order. */
@interface BNSdefTag : NSObject
@property NSString *name;
@property NSDictionary<NSString *, NSString *> *attrs;
@property NSMutableArray<BNSdefTag *> *children;
@property (weak) BNSdefTag *parent;
@end
@implementation BNSdefTag
@end

static NSString *xml_unescape(NSString *s) {
    if ([s rangeOfString:@"&"].location == NSNotFound) return s;
    s = [s stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    s = [s stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    s = [s stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    s = [s stringByReplacingOccurrencesOfString:@"&apos;" withString:@"'"];
    return [s stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
}

static BNSdefTag *sdef_parse(NSData *data) {
    const char *p = data.bytes, *end = p + data.length;
    BNSdefTag *root = [BNSdefTag new];
    root.children = [NSMutableArray array];
    BNSdefTag *cur = root;
    while (p < end) {
        const char *lt = memchr(p, '<', (size_t)(end - p));
        if (!lt) break;
        p = lt + 1;
        if (p < end && (*p == '?' || *p == '!')) {
            const char *close = (p + 2 < end && !strncmp(p, "!--", 3)) ? strstr(p, "-->") : memchr(p, '>', (size_t)(end - p));
            if (!close) break;
            p = close + 1;
            continue;
        }
        if (p < end && *p == '/') {
            const char *gt = memchr(p, '>', (size_t)(end - p));
            if (!gt) break;
            if (cur.parent) cur = cur.parent;
            p = gt + 1;
            continue;
        }
        const char *n = p;
        while (p < end && *p != ' ' && *p != '\t' && *p != '\n' && *p != '\r' && *p != '>' && *p != '/') p++;
        BNSdefTag *t = [BNSdefTag new];
        t.name = [[NSString alloc] initWithBytes:n length:(NSUInteger)(p - n) encoding:NSUTF8StringEncoding];
        t.children = [NSMutableArray array];
        NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
        BOOL selfClosing = NO;
        while (p < end && *p != '>') {
            if (*p == '/') { selfClosing = YES; p++; continue; }
            if (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') { p++; continue; }
            const char *k = p;
            while (p < end && *p != '=' && *p != ' ' && *p != '>' && *p != '/') p++;
            NSString *key = [[NSString alloc] initWithBytes:k length:(NSUInteger)(p - k) encoding:NSUTF8StringEncoding];
            if (p < end && *p == '=') {
                p++;
                char q = *p;
                if (q != '"' && q != '\'') continue;
                const char *v = ++p;
                while (p < end && *p != q) p++;
                attrs[key] = xml_unescape([[NSString alloc] initWithBytes:v length:(NSUInteger)(p - v)
                                                                 encoding:NSUTF8StringEncoding]);
                p++;
            }
        }
        p++;
        t.attrs = attrs;
        t.parent = cur;
        [cur.children addObject:t];
        if (!selfClosing) cur = t;
    }
    return root;
}

static void sdef_walk(BNSdefTag *t, void (^f)(BNSdefTag *)) {
    f(t);
    for (BNSdefTag *c in t.children) sdef_walk(c, f);
}
static BNSdefTag *child(BNSdefTag *t, NSString *name) {
    for (BNSdefTag *c in t.children) if ([c.name isEqual:name]) return c;
    return nil;
}

static NSMutableDictionary<NSString *, NSScriptCommandDescription *> *commandsByCode;   /* "classid" */
static NSMutableDictionary<NSString *, NSScriptClassDescription *> *classesByName;       /* by Cocoa class name */
static NSMutableDictionary<NSNumber *, NSScriptClassDescription *> *classesByCode;

@interface NSScriptCommandDescription ()
- (instancetype)initWithBNTag:(BNSdefTag *)t suite:(NSString *)suite;
@end
@interface NSScriptClassDescription ()
- (instancetype)initWithBNTag:(BNSdefTag *)t suite:(NSString *)suite;
- (void)_bn_mergeFrom:(NSScriptClassDescription *)o;
@end
@interface NSScriptCommand ()
- (void)_bn_setAppleEvent:(NSAppleEventDescriptor *)e;
@end

static void sdef_load(void) {
    static BOOL loaded;
    if (loaded) return;
    loaded = YES;
    commandsByCode = [NSMutableDictionary dictionary];
    classesByName = [NSMutableDictionary dictionary];
    classesByCode = [NSMutableDictionary dictionary];
    NSBundle *b = [NSBundle mainBundle];
    NSString *name = [b objectForInfoDictionaryKey:@"OSAScriptingDefinition"];
    if (!name.length) return;
    NSString *path = [b.resourcePath stringByAppendingPathComponent:name];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;
    BNSdefTag *root = sdef_parse(data);
    sdef_walk(root, ^(BNSdefTag *t) {
        if (![t.name isEqual:@"command"] && ![t.name isEqual:@"class"] && ![t.name isEqual:@"class-extension"]) return;
        NSString *suite = t.parent.attrs[@"name"] ?: @"";
        if ([t.name isEqual:@"command"]) {
            NSScriptCommandDescription *c = [[NSScriptCommandDescription alloc] initWithBNTag:t suite:suite];
            NSString *code = t.attrs[@"code"];
            if (c && code.length == 8) commandsByCode[code] = c;
        } else {
            NSScriptClassDescription *c = [[NSScriptClassDescription alloc] initWithBNTag:t suite:suite];
            if (c.implementationClassName) {
                NSScriptClassDescription *old = classesByName[c.implementationClassName];
                if (old && [t.name isEqual:@"class-extension"]) [old _bn_mergeFrom:c];
                else classesByName[c.implementationClassName] = c;
            }
            if (c.appleEventCode && !classesByCode[@(c.appleEventCode)]) classesByCode[@(c.appleEventCode)] = c;
        }
    });
}

/* ---- the manager ---- */

@interface BNAEHandler : NSObject
@property (weak) id target;
@property SEL selector;
@end
@implementation BNAEHandler
@end

@interface BNAESuspension : NSObject
@property NSAppleEventDescriptor *event, *reply;
@property BOOL resumed;
@end
@implementation BNAESuspension
@end

@implementation NSAppleEventManager {
    NSMutableDictionary<NSString *, BNAEHandler *> *_handlers;
    NSAppleEventDescriptor *_current, *_currentReply;
    BNAESuspension *_suspended;
    BOOL _sawFirst;
}
+ (NSAppleEventManager *)sharedAppleEventManager {
    static NSAppleEventManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [NSAppleEventManager new]; });
    return m;
}
- (instancetype)init {
    if ((self = [super init])) _handlers = [NSMutableDictionary dictionary];
    return self;
}
static NSString *handler_key(AEEventClass c, AEEventID i) { return [NSString stringWithFormat:@"%08x%08x", c, i]; }
- (void)setEventHandler:(id)handler andSelector:(SEL)sel forEventClass:(AEEventClass)c andEventID:(AEEventID)i {
    BNAEHandler *h = [BNAEHandler new];
    h.target = handler;
    h.selector = sel;
    @synchronized(self) { _handlers[handler_key(c, i)] = h; }
}
- (void)removeEventHandlerForEventClass:(AEEventClass)c andEventID:(AEEventID)i {
    @synchronized(self) { [_handlers removeObjectForKey:handler_key(c, i)]; }
}
- (OSErr)dispatchRawAppleEvent:(const AppleEvent *)event withRawReply:(AppleEvent *)reply handlerRefCon:(void *)refCon {
    return errAEEventNotHandled;
}
- (NSAppleEventDescriptor *)currentAppleEvent { return _current; }
- (NSAppleEventDescriptor *)currentReplyAppleEvent { return _currentReply; }
- (NSAppleEventManagerSuspensionID)suspendCurrentAppleEvent {
    if (!_current) return NULL;
    BNAESuspension *s = [BNAESuspension new];
    s.event = _current;
    s.reply = _currentReply;
    _suspended = s;
    return (__bridge_retained NSAppleEventManagerSuspensionID)s;
}
- (NSAppleEventDescriptor *)appleEventForSuspensionID:(NSAppleEventManagerSuspensionID)sid {
    return ((__bridge BNAESuspension *)sid).event;
}
- (NSAppleEventDescriptor *)replyAppleEventForSuspensionID:(NSAppleEventManagerSuspensionID)sid {
    return ((__bridge BNAESuspension *)sid).reply;
}
- (void)setCurrentAppleEventAndReplyEventWithSuspensionID:(NSAppleEventManagerSuspensionID)sid {
    BNAESuspension *s = (__bridge BNAESuspension *)sid;
    _current = s.event;
    _currentReply = s.reply;
}
- (void)resumeWithSuspensionID:(NSAppleEventManagerSuspensionID)sid {
    BNAESuspension *s = (__bridge_transfer BNAESuspension *)sid;
    s.resumed = YES;
}

- (NSAppleEventDescriptor *)_bn_dispatchEvent:(NSAppleEventDescriptor *)event {
    if (!_sawFirst) {
        _sawFirst = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:NSAppleEventManagerWillProcessFirstEventNotification
                                                            object:self];
    }
    NSAppleEventDescriptor *reply = [NSAppleEventDescriptor appleEventWithEventClass:kCoreEventClass eventID:kAEAnswer
                                                                    targetDescriptor:nil returnID:event.returnID
                                                                       transactionID:event.transactionID];
    NSAppleEventDescriptor *savedEvent = _current, *savedReply = _currentReply;
    _current = event;
    _currentReply = reply;
    BNAEHandler *h;
    @synchronized(self) {
        h = _handlers[handler_key(event.eventClass, event.eventID)] ?: _handlers[handler_key(event.eventClass, typeWildCard)]
                                                                      ?: _handlers[handler_key(typeWildCard, typeWildCard)];
    }
    id target = h.target;
    if (target && h.selector) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(target, h.selector, event, reply);
    } else if (![self _bn_runScriptCommand:event reply:reply]) {
        [reply setParamDescriptor:[NSAppleEventDescriptor descriptorWithInt32:errAEEventNotHandled] forKeyword:keyErrorNumber];
    }
    _current = savedEvent;
    _currentReply = savedReply;
    return reply;
}

/* An event of the scripting definition: its command, executed. */
- (BOOL)_bn_runScriptCommand:(NSAppleEventDescriptor *)event reply:(NSAppleEventDescriptor *)reply {
    sdef_load();
    NSString *code = [[fourcc(event.eventClass) stringByAppendingString:fourcc(event.eventID)]
        stringByReplacingOccurrencesOfString:@"'" withString:@""];
    NSScriptCommandDescription *desc = commandsByCode[code];
    if (!desc) return NO;
    NSScriptCommand *cmd = [desc createCommandInstance];
    [cmd _bn_setAppleEvent:event];
    NSAppleEventDescriptor *direct = [event paramDescriptorForKeyword:keyDirectObject];
    id directObject = object_from(direct);
    if ([directObject isKindOfClass:[NSScriptObjectSpecifier class]]) cmd.receiversSpecifier = directObject;
    else cmd.directParameter = directObject;
    NSMutableDictionary *args = [NSMutableDictionary dictionary];
    for (NSString *name in desc.argumentNames) {
        NSAppleEventDescriptor *d = [event paramDescriptorForKeyword:[desc appleEventCodeForArgumentWithName:name]];
        id o = object_from(d);
        if (o) args[name] = o;
    }
    cmd.arguments = args;
    id result = [cmd executeCommand];
    if (cmd.scriptErrorNumber) {
        [reply setParamDescriptor:[NSAppleEventDescriptor descriptorWithInt32:(SInt32)cmd.scriptErrorNumber]
                       forKeyword:keyErrorNumber];
        if (cmd.scriptErrorString)
            [reply setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:cmd.scriptErrorString]
                           forKeyword:keyErrorString];
    } else if (result) {
        [reply setParamDescriptor:descriptor_from(result) forKeyword:keyAEResult];
    }
    return YES;
}
@end

/* ---- class descriptions ---- */

static NSMutableDictionary<NSString *, NSClassDescription *> *registered;

@implementation NSClassDescription
+ (void)registerClassDescription:(NSClassDescription *)d forClass:(Class)c {
    @synchronized(self) {
        if (!registered) registered = [NSMutableDictionary dictionary];
        if (d && c) registered[NSStringFromClass(c)] = d;
    }
}
+ (void)invalidateClassDescriptionCache {
    @synchronized(self) { [registered removeAllObjects]; }
}
+ (NSClassDescription *)classDescriptionForClass:(Class)c {
    @synchronized(self) {
        for (Class k = c; k; k = class_getSuperclass(k)) {
            NSClassDescription *d = registered[NSStringFromClass(k)];
            if (d) return d;
        }
    }
    return nil;
}
- (NSArray<NSString *> *)attributeKeys { return @[]; }
- (NSArray<NSString *> *)toOneRelationshipKeys { return @[]; }
- (NSArray<NSString *> *)toManyRelationshipKeys { return @[]; }
- (NSString *)inverseForRelationshipKey:(NSString *)k { return nil; }
@end

@implementation NSScriptClassDescription {
    NSString *_suiteName, *_className, *_implementationClassName, *_superName;
    FourCharCode _code;
    NSMutableDictionary<NSString *, NSDictionary *> *_keys;          /* cocoa key -> {code, type, access, element} */
    NSMutableDictionary<NSString *, NSString *> *_commands;         /* command name -> method */
}
+ (NSScriptClassDescription *)classDescriptionForClass:(Class)c {
    sdef_load();
    for (Class k = c; k; k = class_getSuperclass(k)) {
        NSScriptClassDescription *d = classesByName[NSStringFromClass(k)];
        if (d) return d;
    }
    id r = [NSClassDescription classDescriptionForClass:c];
    return [r isKindOfClass:self] ? r : nil;
}
- (instancetype)initWithSuiteName:(NSString *)suite className:(NSString *)name dictionary:(NSDictionary *)decl {
    if ((self = [super init])) {
        _suiteName = [suite copy];
        _className = [name copy];
        _implementationClassName = decl[@"Name"] ?: name;
        _superName = decl[@"Superclass"];
        _code = code_from(decl[@"AppleEventCode"] ?: @"");
        _keys = [NSMutableDictionary dictionary];
        _commands = [NSMutableDictionary dictionary];
        NSDictionary *attrs = decl[@"Attributes"];
        for (NSString *k in attrs) {
            NSDictionary *a = attrs[k];
            _keys[k] = @{@"code" : @(code_from(a[@"AppleEventCode"] ?: @"")), @"type" : a[@"Type"] ?: @""};
        }
        NSDictionary *many = decl[@"ToManyRelationships"];
        for (NSString *k in many) {
            NSDictionary *a = many[k];
            _keys[k] = @{@"code" : @(code_from(a[@"AppleEventCode"] ?: @"")), @"type" : a[@"Type"] ?: @"", @"element" : @YES};
        }
        NSDictionary *cmds = decl[@"SupportedCommands"];
        for (NSString *k in cmds) _commands[k] = cmds[k];
    }
    return self;
}
- (instancetype)initWithBNTag:(BNSdefTag *)t suite:(NSString *)suite {
    if ((self = [super init])) {
        _suiteName = [suite copy];
        _className = t.attrs[@"name"] ?: t.attrs[@"extends"];
        _implementationClassName = child(t, @"cocoa").attrs[@"class"];
        if (!_implementationClassName && [_className isEqual:@"application"]) _implementationClassName = @"NSApplication";
        _superName = t.attrs[@"inherits"];
        _code = code_from(t.attrs[@"code"] ?: @"");
        _keys = [NSMutableDictionary dictionary];
        _commands = [NSMutableDictionary dictionary];
        for (BNSdefTag *c in t.children) {
            NSString *key = child(c, @"cocoa").attrs[@"key"];
            if ([c.name isEqual:@"property"]) {
                if (!key) key = c.attrs[@"name"];
                if (key) _keys[key] = @{@"code" : @(code_from(c.attrs[@"code"] ?: @"")), @"type" : c.attrs[@"type"] ?: @"",
                                        @"access" : c.attrs[@"access"] ?: @"rw"};
            } else if ([c.name isEqual:@"element"]) {
                NSString *type = c.attrs[@"type"] ?: @"";
                if (!key) key = [type stringByAppendingString:@"s"];
                _keys[key] = @{@"code" : @0, @"type" : type, @"element" : @YES};
            } else if ([c.name isEqual:@"responds-to"]) {
                NSString *cmd = c.attrs[@"command"] ?: c.attrs[@"name"];
                NSString *method = child(c, @"cocoa").attrs[@"method"];
                if (cmd) _commands[cmd] = method ?: @"";
            }
        }
    }
    return self;
}
- (void)_bn_mergeFrom:(NSScriptClassDescription *)o {
    [_keys addEntriesFromDictionary:o->_keys];
    [_commands addEntriesFromDictionary:o->_commands];
}
- (NSString *)suiteName { return _suiteName; }
- (NSString *)className { return _className; }
- (NSString *)implementationClassName { return _implementationClassName; }
- (NSScriptClassDescription *)superclassDescription {
    if (!_superName) return nil;
    sdef_load();
    for (NSScriptClassDescription *d in classesByName.allValues)
        if ([d.className isEqual:_superName]) return d;
    return nil;
}
- (FourCharCode)appleEventCode { return _code; }
- (BOOL)matchesAppleEventCode:(FourCharCode)c {
    for (NSScriptClassDescription *d = self; d; d = d.superclassDescription)
        if (d.appleEventCode == c) return YES;
    return NO;
}
- (BOOL)supportsCommand:(NSScriptCommandDescription *)c {
    for (NSScriptClassDescription *d = self; d; d = d.superclassDescription)
        if (d->_commands[c.commandName]) return YES;
    return NO;
}
- (SEL)selectorForCommand:(NSScriptCommandDescription *)c {
    for (NSScriptClassDescription *d = self; d; d = d.superclassDescription) {
        NSString *m = d->_commands[c.commandName];
        if (m.length) return NSSelectorFromString([m hasSuffix:@":"] ? m : [m stringByAppendingString:@":"]);
    }
    return NULL;
}
- (NSDictionary *)_bn_keyInfo:(NSString *)k {
    for (NSScriptClassDescription *d = self; d; d = d.superclassDescription)
        if (d->_keys[k]) return d->_keys[k];
    return nil;
}
- (NSString *)typeForKey:(NSString *)k { return [self _bn_keyInfo:k][@"type"]; }
- (NSScriptClassDescription *)classDescriptionForKey:(NSString *)k {
    NSString *type = [self typeForKey:k];
    if (!type) return nil;
    sdef_load();
    for (NSScriptClassDescription *d in classesByName.allValues)
        if ([d.className isEqual:type]) return d;
    return nil;
}
- (FourCharCode)appleEventCodeForKey:(NSString *)k {
    NSDictionary *i = [self _bn_keyInfo:k];
    if ([i[@"element"] boolValue]) return [self classDescriptionForKey:k].appleEventCode;
    return [i[@"code"] unsignedIntValue];
}
- (NSString *)keyWithAppleEventCode:(FourCharCode)c {
    for (NSScriptClassDescription *d = self; d; d = d.superclassDescription)
        for (NSString *k in d->_keys)
            if ([d appleEventCodeForKey:k] == c) return k;
    return nil;
}
- (NSString *)defaultSubcontainerAttributeKey { return nil; }
- (BOOL)isLocationRequiredToCreateForKey:(NSString *)k { return NO; }
- (BOOL)hasPropertyForKey:(NSString *)k { return [self _bn_keyInfo:k] != nil; }
- (BOOL)hasOrderedToManyRelationshipForKey:(NSString *)k { return [[self _bn_keyInfo:k][@"element"] boolValue]; }
- (BOOL)hasReadablePropertyForKey:(NSString *)k {
    NSString *a = [self _bn_keyInfo:k][@"access"];
    return [self _bn_keyInfo:k] && ![a isEqual:@"w"];
}
- (BOOL)hasWritablePropertyForKey:(NSString *)k {
    NSString *a = [self _bn_keyInfo:k][@"access"];
    return [self _bn_keyInfo:k] && ![a isEqual:@"r"];
}
- (NSArray<NSString *> *)attributeKeys {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *k in _keys) if (![_keys[k][@"element"] boolValue]) [a addObject:k];
    return a;
}
- (NSArray<NSString *> *)toManyRelationshipKeys {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *k in _keys) if ([_keys[k][@"element"] boolValue]) [a addObject:k];
    return a;
}
@end

/* ---- command descriptions ---- */

@implementation NSScriptCommandDescription {
    NSString *_suiteName, *_commandName, *_className, *_returnType;
    FourCharCode _classCode, _code, _returnCode;
    NSMutableArray<NSString *> *_argNames;
    NSMutableDictionary<NSString *, NSDictionary *> *_args;   /* name -> {code, type, optional} */
}
- (instancetype)initWithSuiteName:(NSString *)suite commandName:(NSString *)name dictionary:(NSDictionary *)decl {
    if ((self = [super init])) {
        _suiteName = [suite copy];
        _commandName = [name copy];
        _className = decl[@"CommandClass"] ?: @"NSScriptCommand";
        _classCode = code_from(decl[@"AppleEventClassCode"] ?: @"");
        _code = code_from(decl[@"AppleEventCode"] ?: @"");
        _returnType = decl[@"ResultAppleEventCode"] ? decl[@"Type"] : nil;
        _argNames = [NSMutableArray array];
        _args = [NSMutableDictionary dictionary];
        NSDictionary *args = decl[@"Arguments"];
        for (NSString *k in args) {
            [_argNames addObject:k];
            NSDictionary *a = args[k];
            _args[k] = @{@"code" : @(code_from(a[@"AppleEventCode"] ?: @"")), @"type" : a[@"Type"] ?: @"",
                         @"optional" : @([a[@"Optional"] boolValue])};
        }
    }
    return self;
}
- (instancetype)initWithBNTag:(BNSdefTag *)t suite:(NSString *)suite {
    if ((self = [super init])) {
        NSString *code = t.attrs[@"code"] ?: @"";
        if (code.length != 8) return nil;
        _suiteName = [suite copy];
        _commandName = t.attrs[@"name"];
        _className = child(t, @"cocoa").attrs[@"class"] ?: @"NSScriptCommand";
        _classCode = code_from([code substringToIndex:4]);
        _code = code_from([code substringFromIndex:4]);
        BNSdefTag *result = child(t, @"result");
        _returnType = result.attrs[@"type"];
        _argNames = [NSMutableArray array];
        _args = [NSMutableDictionary dictionary];
        for (BNSdefTag *c in t.children) {
            if (![c.name isEqual:@"parameter"]) continue;
            NSString *key = child(c, @"cocoa").attrs[@"key"] ?: c.attrs[@"name"];
            if (!key) continue;
            [_argNames addObject:key];
            _args[key] = @{@"code" : @(code_from(c.attrs[@"code"] ?: @"")), @"type" : c.attrs[@"type"] ?: @"",
                           @"optional" : @([c.attrs[@"optional"] isEqual:@"yes"])};
        }
    }
    return self;
}
- (NSString *)suiteName { return _suiteName; }
- (NSString *)commandName { return _commandName; }
- (FourCharCode)appleEventClassCode { return _classCode; }
- (FourCharCode)appleEventCode { return _code; }
- (NSString *)commandClassName { return _className; }
- (NSString *)returnType { return _returnType; }
- (FourCharCode)appleEventCodeForReturnType { return _returnCode; }
- (NSArray<NSString *> *)argumentNames { return [_argNames copy]; }
- (NSString *)typeForArgumentWithName:(NSString *)n { return _args[n][@"type"]; }
- (FourCharCode)appleEventCodeForArgumentWithName:(NSString *)n { return [_args[n][@"code"] unsignedIntValue]; }
- (BOOL)isOptionalArgumentWithName:(NSString *)n { return [_args[n][@"optional"] boolValue]; }
- (NSScriptCommand *)createCommandInstance {
    Class c = NSClassFromString(_className);
    if (![c isSubclassOfClass:[NSScriptCommand class]]) c = [NSScriptCommand class];
    return [[c alloc] initWithCommandDescription:self];
}
@end

/* ---- commands ---- */

static NSScriptCommand *currentCommand;

@implementation NSScriptCommand {
    NSScriptCommandDescription *_description;
    id _directParameter;
    NSScriptObjectSpecifier *_receivers;
    NSDictionary *_arguments;
    NSAppleEventDescriptor *_appleEvent;
    BOOL _suspended;
    id _result;
}
@synthesize scriptErrorNumber = _scriptErrorNumber, scriptErrorString = _scriptErrorString,
            scriptErrorOffendingObjectDescriptor = _scriptErrorOffendingObjectDescriptor,
            scriptErrorExpectedTypeDescriptor = _scriptErrorExpectedTypeDescriptor;
- (instancetype)init { return [self initWithCommandDescription:(id _Nonnull)nil]; }
- (instancetype)initWithCommandDescription:(NSScriptCommandDescription *)d {
    if ((self = [super init])) _description = d;
    return self;
}
- (NSScriptCommandDescription *)commandDescription { return _description; }
- (id)directParameter { return _directParameter; }
- (void)setDirectParameter:(id)p { _directParameter = p; }
- (NSScriptObjectSpecifier *)receiversSpecifier { return _receivers; }
- (void)setReceiversSpecifier:(NSScriptObjectSpecifier *)r { _receivers = r; }
- (NSDictionary *)arguments { return _arguments; }
- (void)setArguments:(NSDictionary *)a { _arguments = [a copy]; }
- (NSAppleEventDescriptor *)appleEvent { return _appleEvent; }
- (void)_bn_setAppleEvent:(NSAppleEventDescriptor *)e { _appleEvent = e; }

static id evaluate(id o) {
    if ([o isKindOfClass:[NSScriptObjectSpecifier class]]) return [o objectsByEvaluatingSpecifier];
    if ([o isKindOfClass:[NSArray class]]) {
        NSMutableArray *a = [NSMutableArray array];
        for (id e in o) [a addObject:evaluate(e) ?: [NSNull null]];
        return a;
    }
    return o;
}
- (id)evaluatedReceivers { return _receivers ? [_receivers objectsByEvaluatingSpecifier] : nil; }
- (NSDictionary *)evaluatedArguments {
    if (!_arguments) return nil;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *k in _arguments) {
        id v = evaluate(_arguments[k]);
        if (!v) {
            _scriptErrorNumber = NSArgumentEvaluationScriptError;
            return nil;
        }
        d[k] = v;
    }
    return d;
}
- (BOOL)isWellFormed {
    if (!_description) return YES;
    for (NSString *n in _description.argumentNames)
        if (![_description isOptionalArgumentWithName:n] && !_arguments[n]) return NO;
    return YES;
}
- (id)performDefaultImplementation { return nil; }

/* The receivers' handler for the command if their class description names
 * one, else the command's own default implementation. */
- (id)executeCommand {
    NSScriptCommand *saved = currentCommand;
    currentCommand = self;
    id result = nil;
    if (!self.isWellFormed) {
        _scriptErrorNumber = NSRequiredArgumentsMissingScriptError;
    } else {
        id receivers = self.evaluatedReceivers;
        if (_receivers && !receivers) {
            _scriptErrorNumber = NSReceiverEvaluationScriptError;
        } else {
            NSArray *targets = !receivers ? @[] : [receivers isKindOfClass:[NSArray class]] ? receivers : @[receivers];
            BOOL handled = NO;
            NSMutableArray *results = [NSMutableArray array];
            for (id t in targets) {
                SEL s = [[NSScriptClassDescription classDescriptionForClass:[t class]] selectorForCommand:_description];
                if (s && [t respondsToSelector:s]) {
                    id r = ((id(*)(id, SEL, id))objc_msgSend)(t, s, self);
                    if (r) [results addObject:r];
                    handled = YES;
                }
            }
            if (handled) result = results.count == 1 ? results[0] : results.count ? results : nil;
            else result = [self performDefaultImplementation];
        }
    }
    currentCommand = saved;
    if (_suspended) return _result;
    return result;
}
+ (NSScriptCommand *)currentCommand { return currentCommand; }
- (void)suspendExecution { _suspended = YES; }
- (void)resumeExecutionWithResult:(id)result {
    _suspended = NO;
    _result = result;
}
@end

/* ---- object specifiers ---- */

/* Whether valueForKey: can answer without raising: a getter, or an
 * instance variable with the key's name. */
static BOOL has_key(id o, NSString *key) {
    if (!o || !key.length) return NO;
    if ([o respondsToSelector:NSSelectorFromString(key)]) return YES;
    NSString *is = [@"is" stringByAppendingString:[[key substringToIndex:1].uppercaseString stringByAppendingString:[key substringFromIndex:1]]];
    if ([o respondsToSelector:NSSelectorFromString(is)]) return YES;
    if ([o respondsToSelector:@selector(objectForKey:)]) return YES;
    return class_getInstanceVariable([o class], key.UTF8String) ||
           class_getInstanceVariable([o class], [@"_" stringByAppendingString:key].UTF8String);
}

static id top_container(void) {
    Class app = NSClassFromString(@"NSApplication");
    return app ? ((id(*)(id, SEL))objc_msgSend)(app, @selector(sharedApplication)) : nil;
}

@implementation NSScriptObjectSpecifier {
    NSScriptObjectSpecifier *_container;
    __weak NSScriptObjectSpecifier *_child;
    NSString *_key;
    NSScriptClassDescription *_containerClass;
    BOOL _testing, _range;
    NSInteger _evaluationError;
}
- (instancetype)initWithContainerSpecifier:(NSScriptObjectSpecifier *)container key:(NSString *)key {
    return [self initWithContainerClassDescription:container.keyClassDescription containerSpecifier:container key:key];
}
- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)desc
                               containerSpecifier:(NSScriptObjectSpecifier *)container
                                              key:(NSString *)key {
    if ((self = [super init])) {
        _containerClass = desc;
        _container = container;
        container.childSpecifier = self;
        _key = [key copy];
    }
    return self;
}
- (NSScriptObjectSpecifier *)childSpecifier { return _child; }
- (void)setChildSpecifier:(NSScriptObjectSpecifier *)c { _child = c; }
- (NSScriptObjectSpecifier *)containerSpecifier { return _container; }
- (void)setContainerSpecifier:(NSScriptObjectSpecifier *)c { _container = c; }
- (BOOL)containerIsObjectBeingTested { return _testing; }
- (void)setContainerIsObjectBeingTested:(BOOL)b { _testing = b; }
- (BOOL)containerIsRangeContainerObject { return _range; }
- (void)setContainerIsRangeContainerObject:(BOOL)b { _range = b; }
- (NSString *)key { return _key; }
- (void)setKey:(NSString *)k { _key = [k copy]; }
- (NSScriptClassDescription *)containerClassDescription { return _containerClass; }
- (void)setContainerClassDescription:(NSScriptClassDescription *)d { _containerClass = d; }
- (NSScriptClassDescription *)keyClassDescription { return [_containerClass classDescriptionForKey:_key]; }
- (NSInteger)evaluationErrorNumber { return _evaluationError; }
- (void)setEvaluationErrorNumber:(NSInteger)e { _evaluationError = e; }
- (NSScriptObjectSpecifier *)evaluationErrorSpecifier { return _evaluationError ? self : nil; }

- (NSInteger *)indicesOfObjectsByEvaluatingWithContainer:(id)container count:(NSInteger *)n {
    if (n) *n = -1;
    return NULL;
}
/* The key's value in each container; a subclass picks among the elements. */
- (id)_bn_pick:(id)value { return value; }
- (id)objectsByEvaluatingWithContainers:(id)containers {
    if ([containers isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id c in containers) {
            id v = [self objectsByEvaluatingWithContainers:c];
            if (v) [out addObject:v];
        }
        return out;
    }
    if (!has_key(containers, _key)) {
        _evaluationError = NSUnknownKeySpecifierError;
        return nil;
    }
    return [self _bn_pick:[containers valueForKey:_key]];
}
- (id)objectsByEvaluatingSpecifier {
    id containers = _container ? _container.objectsByEvaluatingSpecifier : top_container();
    if (!containers) {
        _evaluationError = _container ? NSContainerSpecifierError : NSNoTopLevelContainersSpecifierError;
        return nil;
    }
    return [self objectsByEvaluatingWithContainers:containers];
}

/* 'obj ' records: want (class), from (container), form, seld. */
+ (NSScriptObjectSpecifier *)objectSpecifierWithDescriptor:(NSAppleEventDescriptor *)d {
    if (d.descriptorType != typeObjectSpecifier && d.descriptorType != typeAERecord) return nil;
    NSAppleEventDescriptor *from = [d descriptorForKeyword:keyAEContainer];
    NSScriptObjectSpecifier *container = from.descriptorType == typeObjectSpecifier
                                             ? [self objectSpecifierWithDescriptor:from] : nil;
    NSScriptClassDescription *cdesc = container ? container.keyClassDescription
                                                : [NSScriptClassDescription classDescriptionForClass:[top_container() class]];
    FourCharCode want = [d descriptorForKeyword:keyAEDesiredClass].typeCodeValue;
    FourCharCode form = [d descriptorForKeyword:keyAEKeyForm].enumCodeValue;
    NSAppleEventDescriptor *seld = [d descriptorForKeyword:keyAEKeyData];
    NSString *key;
    if (form == 'prop') key = [cdesc keyWithAppleEventCode:seld.typeCodeValue];
    else key = [cdesc keyWithAppleEventCode:want];
    if (!key) return nil;
    switch (form) {
    case 'prop': return [[NSPropertySpecifier alloc] initWithContainerClassDescription:cdesc containerSpecifier:container key:key];
    case 'indx': {
        NSInteger i = seld.int32Value;
        return [[NSIndexSpecifier alloc] initWithContainerClassDescription:cdesc containerSpecifier:container key:key
                                                                     index:i > 0 ? i - 1 : i];
    }
    case 'name':
        return [[NSNameSpecifier alloc] initWithContainerClassDescription:cdesc containerSpecifier:container key:key
                                                                     name:seld.stringValue ?: @""];
    case 'ID  ':
        return [[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:cdesc containerSpecifier:container key:key
                                                                     uniqueID:object_from(seld) ?: [NSNull null]];
    }
    return nil;
}
- (FourCharCode)_bn_form { return 'prop'; }
- (NSAppleEventDescriptor *)_bn_seld { return [NSAppleEventDescriptor descriptorWithTypeCode:[_containerClass appleEventCodeForKey:_key]]; }
- (NSAppleEventDescriptor *)descriptor {
    NSAppleEventDescriptor *d = [[NSAppleEventDescriptor alloc] initRecordDescriptor];
    FourCharCode want = [self _bn_form] == 'prop' ? 'prop' : self.keyClassDescription.appleEventCode;
    [d setDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:want] forKeyword:keyAEDesiredClass];
    [d setDescriptor:_container.descriptor ?: [NSAppleEventDescriptor nullDescriptor] forKeyword:keyAEContainer];
    [d setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:[self _bn_form]] forKeyword:keyAEKeyForm];
    [d setDescriptor:[self _bn_seld] ?: [NSAppleEventDescriptor nullDescriptor] forKeyword:keyAEKeyData];
    [d _bn_setType:typeObjectSpecifier];
    return d;
}
@end

@implementation NSPropertySpecifier
@end

@implementation NSIndexSpecifier
@synthesize index = _index;
- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)d containerSpecifier:(NSScriptObjectSpecifier *)c
                                              key:(NSString *)k index:(NSInteger)i {
    if ((self = [super initWithContainerClassDescription:d containerSpecifier:c key:k])) _index = i;
    return self;
}
- (id)_bn_pick:(id)v {
    if (![v isKindOfClass:[NSArray class]]) return nil;
    NSArray *a = v;
    NSInteger i = _index < 0 ? (NSInteger)a.count + _index : _index;
    if (i < 0 || i >= (NSInteger)a.count) {
        self.evaluationErrorNumber = NSInvalidIndexSpecifierError;
        return nil;
    }
    return a[(NSUInteger)i];
}
- (FourCharCode)_bn_form { return 'indx'; }
- (NSAppleEventDescriptor *)_bn_seld { return [NSAppleEventDescriptor descriptorWithInt32:(SInt32)(_index >= 0 ? _index + 1 : _index)]; }
@end

@implementation NSNameSpecifier
@synthesize name = _name;
- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)d containerSpecifier:(NSScriptObjectSpecifier *)c
                                              key:(NSString *)k name:(NSString *)n {
    if ((self = [super initWithContainerClassDescription:d containerSpecifier:c key:k])) _name = [n copy];
    return self;
}
- (id)_bn_pick:(id)v {
    for (id e in [v isKindOfClass:[NSArray class]] ? v : @[])
        if (has_key(e, @"name") && [[e valueForKey:@"name"] isEqual:_name]) return e;
    return nil;
}
- (FourCharCode)_bn_form { return 'name'; }
- (NSAppleEventDescriptor *)_bn_seld { return [NSAppleEventDescriptor descriptorWithString:_name ?: @""]; }
@end

@implementation NSUniqueIDSpecifier
@synthesize uniqueID = _uniqueID;
- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)d containerSpecifier:(NSScriptObjectSpecifier *)c
                                              key:(NSString *)k uniqueID:(id)u {
    if ((self = [super initWithContainerClassDescription:d containerSpecifier:c key:k])) _uniqueID = [u copy];
    return self;
}
- (id)_bn_pick:(id)v {
    for (id e in [v isKindOfClass:[NSArray class]] ? v : @[]) {
        id u = has_key(e, @"uniqueID") ? [e valueForKey:@"uniqueID"] : nil;
        if ([u isEqual:_uniqueID] || ([u description] && [[u description] isEqual:[_uniqueID description]])) return e;
    }
    return nil;
}
- (FourCharCode)_bn_form { return 'ID  '; }
- (NSAppleEventDescriptor *)_bn_seld { return descriptor_from(_uniqueID); }
@end

/* ---- the standard commands ---- */

/* count: the elements of the class asked for ("ObjectClass", a class
 * code) in the receivers, or the receivers themselves. */
@implementation NSCountCommand
- (id)performDefaultImplementation {
    id r = self.evaluatedReceivers;
    if (!r && [self.directParameter isKindOfClass:[NSArray class]]) r = self.directParameter;
    if ([r isKindOfClass:[NSArray class]]) return @([r count]);
    NSNumber *want = self.arguments[@"ObjectClass"];
    if (r && want) {
        NSScriptClassDescription *d = [NSScriptClassDescription classDescriptionForClass:[r class]];
        NSString *key = [d keyWithAppleEventCode:want.unsignedIntValue];
        if (key && has_key(r, key)) {
            id v = [r valueForKey:key];
            return @([v isKindOfClass:[NSArray class]] ? [v count] : v != nil);
        }
    }
    return @(r ? 1 : 0);
}
@end

@implementation NSExistsCommand
- (id)performDefaultImplementation {
    id r = self.evaluatedReceivers;
    if ([r isKindOfClass:[NSArray class]]) return @([r count] > 0);
    return @(r != nil);
}
@end

@implementation NSGetCommand
- (id)performDefaultImplementation {
    id r = self.evaluatedReceivers;
    if (self.receiversSpecifier && !r) self.scriptErrorNumber = errAENoSuchObject;
    return r;
}
@end

/* set: the value ("Value") on the receivers' key, in their container. */
@implementation NSSetCommand
- (NSScriptObjectSpecifier *)keySpecifier { return self.receiversSpecifier; }
- (id)performDefaultImplementation {
    NSScriptObjectSpecifier *spec = self.receiversSpecifier;
    id value = self.evaluatedArguments[@"Value"];
    id container = spec.containerSpecifier ? spec.containerSpecifier.objectsByEvaluatingSpecifier : top_container();
    if (!spec || !container) {
        self.scriptErrorNumber = NSReceiverEvaluationScriptError;
        return nil;
    }
    NSScriptClassDescription *d = spec.containerClassDescription ?: [NSScriptClassDescription classDescriptionForClass:[container class]];
    if (d && ![d hasWritablePropertyForKey:spec.key]) {
        self.scriptErrorNumber = NSOperationNotSupportedForKeyScriptError;
        return nil;
    }
    [container setValue:value forKey:spec.key];
    return nil;
}
@end

@implementation NSQuitCommand
- (id)performDefaultImplementation {
    id app = top_container();
    if ([app respondsToSelector:@selector(terminate:)]) [app performSelector:@selector(terminate:) withObject:nil];
    return nil;
}
@end

/* close, delete, make, move and duplicate need the receivers to handle
 * them (their class description names the method); by default they
 * report that the operation is not supported. */
@implementation NSCloseCommand
- (id)performDefaultImplementation {
    id r = self.evaluatedReceivers;
    for (id o in [r isKindOfClass:[NSArray class]] ? r : r ? @[r] : @[])
        if ([o respondsToSelector:@selector(close)]) [o performSelector:@selector(close)];
    return nil;
}
@end
@implementation NSDeleteCommand
- (id)performDefaultImplementation {
    self.scriptErrorNumber = NSOperationNotSupportedForKeyScriptError;
    return nil;
}
@end
@implementation NSCreateCommand
- (NSScriptClassDescription *)createClassDescription {
    NSNumber *c = self.arguments[@"ObjectClass"];
    return c ? classesByCode[c] : nil;
}
- (NSDictionary *)resolvedKeyDictionary { return self.evaluatedArguments[@"KeyDictionary"] ?: @{}; }
- (id)performDefaultImplementation {
    self.scriptErrorNumber = NSOperationNotSupportedForKeyScriptError;
    return nil;
}
@end
@implementation NSMoveCommand
- (id)performDefaultImplementation {
    self.scriptErrorNumber = NSOperationNotSupportedForKeyScriptError;
    return nil;
}
@end
@implementation NSCloneCommand
- (id)performDefaultImplementation {
    self.scriptErrorNumber = NSOperationNotSupportedForKeyScriptError;
    return nil;
}
@end

/* ---- NSObject's scripting ---- */

@implementation NSObject (NSScriptObjectSpecifiers)
- (NSScriptObjectSpecifier *)objectSpecifier { return nil; }
- (NSArray<NSNumber *> *)indicesOfObjectsByEvaluatingObjectSpecifier:(NSScriptObjectSpecifier *)s { return nil; }
@end

@implementation NSObject (NSScriptClassDescription)
- (FourCharCode)classCode { return [NSScriptClassDescription classDescriptionForClass:[self class]].appleEventCode; }
- (NSString *)className { return NSStringFromClass([self class]); }
@end

@implementation NSObject (NSScripting)
- (id)scriptingValueForSpecifier:(NSScriptObjectSpecifier *)s { return [s objectsByEvaluatingWithContainers:self]; }
- (NSDictionary *)scriptingProperties {
    NSScriptClassDescription *d = [NSScriptClassDescription classDescriptionForClass:[self class]];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *k in d.attributeKeys) {
        id v = has_key(self, k) ? [self valueForKey:k] : nil;
        if (v) out[k] = v;
    }
    return out;
}
- (void)setScriptingProperties:(NSDictionary *)props {
    for (NSString *k in props) [self setValue:props[k] forKey:k];
}
@end
