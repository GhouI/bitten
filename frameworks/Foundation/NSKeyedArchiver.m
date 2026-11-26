/* NSCoder and keyed archiving in the NSKeyedArchiver format: a property
 * list {$archiver, $version, $top: {root: UID}, $objects: [...]}, where
 * $objects[0] is "$null", strings, numbers and data are stored as
 * themselves and other objects as dictionaries of their encoded keys with
 * a "$class" UID naming {$classname, $classes}. UIDs are written as
 * {CF$UID: n} (XML); read from binary archives they arrive as numbers.
 * Also NSInputStream and NSOutputStream over memory and files. */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>

@implementation NSObject (NSCoderMethods)
- (Class)classForCoder { return [self class]; }
- (id)awakeAfterUsingCoder:(NSCoder *)coder { return self; }
@end

@implementation NSCoder
- (BOOL)allowsKeyedCoding { return NO; }
- (BOOL)requiresSecureCoding { return NO; }
- (void)encodeObject:(id)object {}
- (id)decodeObject { return nil; }
- (void)encodeObject:(id)object forKey:(NSString *)key {}
- (void)encodeConditionalObject:(id)object forKey:(NSString *)key { [self encodeObject:object forKey:key]; }
- (void)encodeBool:(BOOL)v forKey:(NSString *)key { [self encodeObject:@(v) forKey:key]; }
- (void)encodeInt:(int)v forKey:(NSString *)key { [self encodeObject:@(v) forKey:key]; }
- (void)encodeInt32:(int32_t)v forKey:(NSString *)key { [self encodeObject:@(v) forKey:key]; }
- (void)encodeInt64:(int64_t)v forKey:(NSString *)key { [self encodeObject:@(v) forKey:key]; }
- (void)encodeInteger:(NSInteger)v forKey:(NSString *)key { [self encodeObject:@(v) forKey:key]; }
- (void)encodeFloat:(float)v forKey:(NSString *)key { [self encodeObject:@(v) forKey:key]; }
- (void)encodeDouble:(double)v forKey:(NSString *)key { [self encodeObject:@(v) forKey:key]; }
- (void)encodeBytes:(const uint8_t *)bytes length:(NSUInteger)length forKey:(NSString *)key {
    [self encodeObject:[NSData dataWithBytes:bytes length:length] forKey:key];
}
- (BOOL)containsValueForKey:(NSString *)key { return NO; }
- (id)decodeObjectForKey:(NSString *)key { return nil; }
- (id)decodeObjectOfClass:(Class)cls forKey:(NSString *)key {
    id o = [self decodeObjectForKey:key];
    return !cls || [o isKindOfClass:cls] ? o : nil;
}
- (id)decodeObjectOfClasses:(NSSet<Class> *)classes forKey:(NSString *)key {
    id o = [self decodeObjectForKey:key];
    if (!classes) return o;
    for (Class c in classes)
        if ([o isKindOfClass:c]) return o;
    return nil;
}
- (id)decodeArrayOfObjectsOfClass:(Class)cls forKey:(NSString *)key {
    id o = [self decodeObjectForKey:key];
    return [o isKindOfClass:[NSArray class]] ? o : nil;
}
- (id)decodeDictionaryWithKeysOfClass:(Class)k objectsOfClass:(Class)v forKey:(NSString *)key {
    id o = [self decodeObjectForKey:key];
    return [o isKindOfClass:[NSDictionary class]] ? o : nil;
}
- (BOOL)decodeBoolForKey:(NSString *)key { return [[self decodeObjectForKey:key] boolValue]; }
- (int)decodeIntForKey:(NSString *)key { return [[self decodeObjectForKey:key] intValue]; }
- (int32_t)decodeInt32ForKey:(NSString *)key { return [[self decodeObjectForKey:key] intValue]; }
- (int64_t)decodeInt64ForKey:(NSString *)key { return [[self decodeObjectForKey:key] longLongValue]; }
- (NSInteger)decodeIntegerForKey:(NSString *)key { return [[self decodeObjectForKey:key] integerValue]; }
- (float)decodeFloatForKey:(NSString *)key { return [[self decodeObjectForKey:key] floatValue]; }
- (double)decodeDoubleForKey:(NSString *)key { return [[self decodeObjectForKey:key] doubleValue]; }
- (const uint8_t *)decodeBytesForKey:(NSString *)key returnedLength:(NSUInteger *)length {
    NSData *d = [self decodeObjectForKey:key];
    if (length) *length = d.length;
    return d.bytes;
}
- (void)failWithError:(NSError *)error {}
- (NSError *)error { return nil; }
- (NSDecodingFailurePolicy)decodingFailurePolicy { return NSDecodingFailurePolicySetErrorAndReturn; }
@end

static NSDictionary *uid(NSUInteger n) { return @{@"CF$UID" : @(n)}; }
static BOOL is_uid(id o, NSUInteger *n) {
    if ([o isKindOfClass:[NSDictionary class]] && [o count] == 1 && [o[@"CF$UID"] isKindOfClass:[NSNumber class]]) {
        if (n) *n = [o[@"CF$UID"] unsignedIntegerValue];
        return YES;
    }
    if ([o isKindOfClass:[NSNumber class]]) {
        if (n) *n = [o unsignedIntegerValue];
        return YES;
    }
    return NO;
}
static BOOL is_plain(id o) {
    return [o isKindOfClass:[NSString class]] || [o isKindOfClass:[NSNumber class]] || [o isKindOfClass:[NSData class]];
}

@implementation NSKeyedArchiver {
    NSMutableArray *_objects;
    NSMutableDictionary *_current;
    NSMutableDictionary *_seen;
    NSMutableDictionary *_classUIDs;
    NSMutableDictionary *_top;
    NSData *_encoded;
    BOOL _secure;
    NSPropertyListFormat _format;
    __weak id<NSKeyedArchiverDelegate> _delegate;
}
+ (NSData *)archivedDataWithRootObject:(id)root requiringSecureCoding:(BOOL)secure error:(NSError **)error {
    NSKeyedArchiver *a = [[NSKeyedArchiver alloc] initRequiringSecureCoding:secure];
    [a encodeObject:root forKey:NSKeyedArchiveRootObjectKey];
    [a finishEncoding];
    if (!a.encodedData && error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:4866 userInfo:nil];
    return a.encodedData;
}
+ (NSData *)archivedDataWithRootObject:(id)root { return [self archivedDataWithRootObject:root requiringSecureCoding:NO error:NULL]; }
+ (BOOL)archiveRootObject:(id)root toFile:(NSString *)path {
    return [[self archivedDataWithRootObject:root] writeToFile:path atomically:YES];
}
- (instancetype)initRequiringSecureCoding:(BOOL)secure {
    self = [super init];
    _objects = [NSMutableArray arrayWithObject:@"$null"];
    _seen = [NSMutableDictionary dictionary];
    _classUIDs = [NSMutableDictionary dictionary];
    _top = [NSMutableDictionary dictionary];
    _current = _top;
    _secure = secure;
    _format = NSPropertyListXMLFormat_v1_0;
    return self;
}
- (instancetype)init { return [self initRequiringSecureCoding:NO]; }
- (BOOL)allowsKeyedCoding { return YES; }
- (BOOL)requiresSecureCoding { return _secure; }
- (void)setRequiresSecureCoding:(BOOL)b { _secure = b; }
- (NSPropertyListFormat)outputFormat { return _format; }
- (void)setOutputFormat:(NSPropertyListFormat)f { _format = f; }
- (id<NSKeyedArchiverDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSKeyedArchiverDelegate>)d { _delegate = d; }
- (NSUInteger)_bn_classUID:(Class)cls {
    NSString *name = NSStringFromClass(cls);
    NSNumber *n = _classUIDs[name];
    if (n) return n.unsignedIntegerValue;
    NSMutableArray *chain = [NSMutableArray array];
    for (Class c = cls; c; c = class_getSuperclass(c)) [chain addObject:NSStringFromClass(c)];
    [_objects addObject:@{@"$classname" : name, @"$classes" : chain}];
    _classUIDs[name] = @(_objects.count - 1);
    return _objects.count - 1;
}
/* The class an object archives as: the public collection or string
 * class rather than its private concrete one. */
static Class archive_class(id o) {
    if ([o isKindOfClass:[NSMutableArray class]] && ![o isKindOfClass:[NSArray class]]) return [NSArray class];
    if ([o isKindOfClass:[NSArray class]]) return [o isKindOfClass:[NSMutableArray class]] ? [NSMutableArray class] : [NSArray class];
    if ([o isKindOfClass:[NSDictionary class]]) return [o isKindOfClass:[NSMutableDictionary class]] ? [NSMutableDictionary class] : [NSDictionary class];
    if ([o isKindOfClass:[NSSet class]]) return [o isKindOfClass:[NSMutableSet class]] ? [NSMutableSet class] : [NSSet class];
    if ([o isKindOfClass:[NSDate class]]) return [NSDate class];
    if ([o isKindOfClass:[NSURL class]]) return [NSURL class];
    return [o classForCoder];
}
- (NSUInteger)_bn_encode:(id)object {
    if (!object) return 0;
    id<NSKeyedArchiverDelegate> d = _delegate;
    if ([d respondsToSelector:@selector(archiver:willEncodeObject:)]) object = [d archiver:self willEncodeObject:object];
    if (!object) return 0;
    NSValue *ident = [NSValue valueWithNonretainedObject:object];
    NSNumber *seen = _seen[ident];
    if (seen) return seen.unsignedIntegerValue;
    if (is_plain(object)) {
        [_objects addObject:object];
        _seen[ident] = @(_objects.count - 1);
        return _objects.count - 1;
    }
    NSUInteger index = _objects.count;
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [_objects addObject:dict];
    _seen[ident] = @(index);
    NSMutableDictionary *saved = _current;
    _current = dict;
    if ([object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSSet class]]) {
        NSMutableArray *refs = [NSMutableArray array];
        for (id o in object) [refs addObject:uid([self _bn_encode:o])];
        dict[@"NS.objects"] = refs;
    } else if ([object isKindOfClass:[NSDictionary class]]) {
        NSMutableArray *keys = [NSMutableArray array], *values = [NSMutableArray array];
        for (id k in object) {
            [keys addObject:uid([self _bn_encode:k])];
            [values addObject:uid([self _bn_encode:object[k]])];
        }
        dict[@"NS.keys"] = keys;
        dict[@"NS.objects"] = values;
    } else if ([object isKindOfClass:[NSDate class]]) {
        dict[@"NS.time"] = @([object timeIntervalSinceReferenceDate]);
    } else if ([object isKindOfClass:[NSURL class]]) {
        dict[@"NS.base"] = uid(0);
        dict[@"NS.relative"] = uid([self _bn_encode:[object absoluteString]]);
    } else if ([object respondsToSelector:@selector(encodeWithCoder:)]) {
        [object encodeWithCoder:self];
    } else {
        _current = saved;
        [NSException raise:NSInvalidArchiveOperationException
                    format:@"*** -[NSKeyedArchiver encodeObject:]: %@ does not conform to NSCoding", [object class]];
    }
    dict[@"$class"] = uid([self _bn_classUID:archive_class(object)]);
    _current = saved;
    return index;
}
- (void)encodeObject:(id)object forKey:(NSString *)key {
    if (!key) return;
    _current[key] = uid([self _bn_encode:object]);
}
- (void)encodeBool:(BOOL)v forKey:(NSString *)key { _current[key] = @(v); }
- (void)encodeInt:(int)v forKey:(NSString *)key { _current[key] = @(v); }
- (void)encodeInt32:(int32_t)v forKey:(NSString *)key { _current[key] = @(v); }
- (void)encodeInt64:(int64_t)v forKey:(NSString *)key { _current[key] = @(v); }
- (void)encodeInteger:(NSInteger)v forKey:(NSString *)key { _current[key] = @(v); }
- (void)encodeFloat:(float)v forKey:(NSString *)key { _current[key] = @(v); }
- (void)encodeDouble:(double)v forKey:(NSString *)key { _current[key] = @(v); }
- (void)encodeBytes:(const uint8_t *)bytes length:(NSUInteger)length forKey:(NSString *)key {
    _current[key] = [NSData dataWithBytes:bytes length:length];
}
- (void)finishEncoding {
    if (_encoded) return;
    NSDictionary *plist = @{@"$archiver" : @"NSKeyedArchiver", @"$version" : @100000, @"$top" : _top, @"$objects" : _objects};
    _encoded = [NSPropertyListSerialization dataWithPropertyList:plist format:_format options:0 error:NULL];
    id<NSKeyedArchiverDelegate> d = _delegate;
    if ([d respondsToSelector:@selector(archiverDidFinish:)]) [d archiverDidFinish:self];
}
- (NSData *)encodedData {
    [self finishEncoding];
    return _encoded;
}
@end

@implementation NSKeyedUnarchiver {
    NSArray *_objects;
    NSDictionary *_current;
    NSMutableDictionary *_decoded;
    NSDictionary *_top;
    BOOL _secure;
    NSError *_error;
    NSDecodingFailurePolicy _policy;
    __weak id<NSKeyedUnarchiverDelegate> _delegate;
}
+ (id)unarchivedObjectOfClass:(Class)cls fromData:(NSData *)data error:(NSError **)error {
    return [self unarchivedObjectOfClasses:cls ? [NSSet setWithObject:cls] : nil fromData:data error:error];
}
+ (id)unarchivedObjectOfClasses:(NSSet<Class> *)classes fromData:(NSData *)data error:(NSError **)error {
    NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:error];
    if (!u) return nil;
    id root = [u decodeObjectOfClasses:classes forKey:NSKeyedArchiveRootObjectKey];
    [u finishDecoding];
    if (!root && error && !*error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:4864 userInfo:nil];
    return root;
}
+ (id)unarchivedArrayOfObjectsOfClass:(Class)cls fromData:(NSData *)data error:(NSError **)error {
    return [self unarchivedObjectOfClasses:[NSSet setWithObjects:[NSArray class], cls, nil] fromData:data error:error];
}
+ (id)unarchiveObjectWithData:(NSData *)data { return [self unarchivedObjectOfClasses:nil fromData:data error:NULL]; }
+ (id)unarchiveTopLevelObjectWithData:(NSData *)data error:(NSError **)error {
    return [self unarchivedObjectOfClasses:nil fromData:data error:error];
}
+ (id)unarchiveObjectWithFile:(NSString *)path { return [self unarchiveObjectWithData:[NSData dataWithContentsOfFile:path]]; }
- (instancetype)initForReadingFromData:(NSData *)data error:(NSError **)error {
    self = [super init];
    id plist = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL] : nil;
    if (![plist isKindOfClass:[NSDictionary class]] || ![plist[@"$objects"] isKindOfClass:[NSArray class]]) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:4864 userInfo:nil];
        return nil;
    }
    _objects = plist[@"$objects"];
    _top = plist[@"$top"];
    _current = _top;
    _decoded = [NSMutableDictionary dictionary];
    _secure = YES;
    return self;
}
- (instancetype)initForReadingWithData:(NSData *)data { return [self initForReadingFromData:data error:NULL]; }
- (BOOL)allowsKeyedCoding { return YES; }
- (BOOL)requiresSecureCoding { return _secure; }
- (void)setRequiresSecureCoding:(BOOL)b { _secure = b; }
- (NSDecodingFailurePolicy)decodingFailurePolicy { return _policy; }
- (void)setDecodingFailurePolicy:(NSDecodingFailurePolicy)p { _policy = p; }
- (id<NSKeyedUnarchiverDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSKeyedUnarchiverDelegate>)d { _delegate = d; }
- (NSError *)error { return _error; }
- (void)failWithError:(NSError *)error { _error = error; }
- (void)finishDecoding {}
- (BOOL)containsValueForKey:(NSString *)key { return _current[key] != nil; }
- (id)_bn_object:(NSUInteger)index {
    if (index == 0 || index >= _objects.count) return nil;
    id done = _decoded[@(index)];
    if (done) return done == [NSNull null] ? nil : done;
    id raw = _objects[index];
    if (is_plain(raw) && ![raw isKindOfClass:[NSDictionary class]]) return raw;
    if (![raw isKindOfClass:[NSDictionary class]]) return nil;
    NSUInteger cu;
    if (!is_uid(raw[@"$class"], &cu) || cu >= _objects.count) return nil;
    NSDictionary *cls = _objects[cu];
    NSString *name = cls[@"$classname"];
    id<NSKeyedUnarchiverDelegate> d = _delegate;
    Class c = NSClassFromString(name);
    if (!c && [d respondsToSelector:@selector(unarchiver:cannotDecodeObjectOfClassName:originalClasses:)])
        c = [d unarchiver:self cannotDecodeObjectOfClassName:name originalClasses:cls[@"$classes"]];
    id result = nil;
    NSDictionary *saved = _current;
    _current = raw;
    if ([name isEqualToString:@"NSArray"] || [name isEqualToString:@"NSMutableArray"] ||
        [name isEqualToString:@"NSSet"] || [name isEqualToString:@"NSMutableSet"]) {
        NSMutableArray *a = [NSMutableArray array];
        for (id r in raw[@"NS.objects"]) {
            NSUInteger i;
            id o = is_uid(r, &i) ? [self _bn_object:i] : nil;
            if (o) [a addObject:o];
        }
        BOOL set = [name hasSuffix:@"Set"], mutable = [name hasPrefix:@"NSMutable"];
        result = set ? (mutable ? [NSMutableSet setWithArray:a] : [NSSet setWithArray:a]) : (mutable ? a : [a copy]);
    } else if ([name isEqualToString:@"NSDictionary"] || [name isEqualToString:@"NSMutableDictionary"]) {
        NSArray *ks = raw[@"NS.keys"], *vs = raw[@"NS.objects"];
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        for (NSUInteger i = 0; i < ks.count && i < vs.count; i++) {
            NSUInteger a, b;
            id k = is_uid(ks[i], &a) ? [self _bn_object:a] : nil, v = is_uid(vs[i], &b) ? [self _bn_object:b] : nil;
            if (k && v) m[k] = v;
        }
        result = [name hasPrefix:@"NSMutable"] ? m : [m copy];
    } else if ([name isEqualToString:@"NSDate"]) {
        result = [NSDate dateWithTimeIntervalSinceReferenceDate:[raw[@"NS.time"] doubleValue]];
    } else if ([name isEqualToString:@"NSURL"]) {
        NSUInteger r;
        NSString *s = is_uid(raw[@"NS.relative"], &r) ? [self _bn_object:r] : nil;
        result = s ? [NSURL URLWithString:s] : nil;
    } else if ([name isEqualToString:@"NSString"] || [name isEqualToString:@"NSMutableString"]) {
        result = raw[@"NS.string"];
    } else if (c && [c instancesRespondToSelector:@selector(initWithCoder:)]) {
        _decoded[@(index)] = [NSNull null];  /* cycles decode as nil */
        result = [[c alloc] initWithCoder:self];
        if ([result respondsToSelector:@selector(awakeAfterUsingCoder:)]) result = [result awakeAfterUsingCoder:self];
    }
    _current = saved;
    if ([d respondsToSelector:@selector(unarchiver:didDecodeObject:)]) result = [d unarchiver:self didDecodeObject:result];
    _decoded[@(index)] = result ?: [NSNull null];
    return result;
}
- (id)decodeObjectForKey:(NSString *)key {
    id r = _current[key];
    NSUInteger i;
    if (!r) return nil;
    if (!is_uid(r, &i)) return is_plain(r) ? r : nil;
    return [self _bn_object:i];
}
- (BOOL)decodeBoolForKey:(NSString *)key { return [_current[key] boolValue]; }
- (int)decodeIntForKey:(NSString *)key { return [_current[key] intValue]; }
- (int32_t)decodeInt32ForKey:(NSString *)key { return [_current[key] intValue]; }
- (int64_t)decodeInt64ForKey:(NSString *)key { return [_current[key] longLongValue]; }
- (NSInteger)decodeIntegerForKey:(NSString *)key { return [_current[key] integerValue]; }
- (float)decodeFloatForKey:(NSString *)key { return [_current[key] floatValue]; }
- (double)decodeDoubleForKey:(NSString *)key { return [_current[key] doubleValue]; }
- (const uint8_t *)decodeBytesForKey:(NSString *)key returnedLength:(NSUInteger *)length {
    NSData *d = _current[key];
    if (![d isKindOfClass:[NSData class]]) d = nil;
    if (length) *length = d.length;
    return d.bytes;
}
@end

NSString *const NSKeyedArchiveRootObjectKey = @"root";
NSExceptionName const NSInvalidArchiveOperationException = @"NSInvalidArchiveOperationException";
NSExceptionName const NSInvalidUnarchiveOperationException = @"NSInvalidUnarchiveOperationException";

/* ---- streams ---- */

@implementation NSStream
- (void)open {}
- (void)close {}
- (id<NSStreamDelegate>)delegate { return nil; }
- (void)setDelegate:(id<NSStreamDelegate>)d {}
- (id)propertyForKey:(NSStreamPropertyKey)key { return nil; }
- (BOOL)setProperty:(id)property forKey:(NSStreamPropertyKey)key { return NO; }
- (void)scheduleInRunLoop:(NSRunLoop *)rl forMode:(NSString *)mode {}
- (void)removeFromRunLoop:(NSRunLoop *)rl forMode:(NSString *)mode {}
- (NSStreamStatus)streamStatus { return NSStreamStatusNotOpen; }
- (NSError *)streamError { return nil; }
@end

@implementation NSInputStream {
    NSData *_data;
    NSString *_path;
    FILE *_file;
    NSUInteger _pos;
    NSStreamStatus _status;
    NSError *_error;
    __weak id<NSStreamDelegate> _delegate;
}
+ (instancetype)inputStreamWithData:(NSData *)data { return [[self alloc] initWithData:data]; }
+ (instancetype)inputStreamWithFileAtPath:(NSString *)path { return [[self alloc] initWithFileAtPath:path]; }
+ (instancetype)inputStreamWithURL:(NSURL *)url { return [[self alloc] initWithURL:url]; }
- (instancetype)initWithData:(NSData *)data {
    self = [super init];
    _data = [data copy] ?: [NSData data];
    return self;
}
- (instancetype)initWithFileAtPath:(NSString *)path {
    self = [super init];
    _path = [path copy];
    return self;
}
- (instancetype)initWithURL:(NSURL *)url { return url.isFileURL ? [self initWithFileAtPath:url.path] : nil; }
- (id<NSStreamDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSStreamDelegate>)d { _delegate = d; }
- (void)open {
    if (_status != NSStreamStatusNotOpen) return;
    if (_path) {
        _file = fopen(_path.fileSystemRepresentation, "rb");
        if (!_file) {
            _status = NSStreamStatusError;
            _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            return;
        }
    }
    _status = NSStreamStatusOpen;
}
- (void)close {
    if (_file) fclose(_file);
    _file = NULL;
    _status = NSStreamStatusClosed;
}
- (void)dealloc {
    if (_file) fclose(_file);
}
- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len {
    if (_status != NSStreamStatusOpen && _status != NSStreamStatusAtEnd) return -1;
    if (_file) {
        size_t n = fread(buffer, 1, len, _file);
        if (n == 0 && feof(_file)) _status = NSStreamStatusAtEnd;
        if (n == 0 && ferror(_file)) {
            _status = NSStreamStatusError;
            return -1;
        }
        return (NSInteger)n;
    }
    NSUInteger n = MIN(len, _data.length - _pos);
    memcpy(buffer, (const uint8_t *)_data.bytes + _pos, n);
    _pos += n;
    if (_pos >= _data.length) _status = NSStreamStatusAtEnd;
    return (NSInteger)n;
}
- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)len {
    if (_file || !_data) return NO;
    *buffer = (uint8_t *)_data.bytes + _pos;
    *len = _data.length - _pos;
    return YES;
}
- (BOOL)hasBytesAvailable {
    if (_status != NSStreamStatusOpen) return NO;
    if (_file) return !feof(_file);
    return _pos < _data.length;
}
- (NSStreamStatus)streamStatus { return _status; }
- (NSError *)streamError { return _error; }
@end

@implementation NSOutputStream {
    NSMutableData *_memory;
    uint8_t *_buffer;
    NSUInteger _capacity, _written;
    NSString *_path;
    BOOL _append;
    FILE *_file;
    NSStreamStatus _status;
    NSError *_error;
    __weak id<NSStreamDelegate> _delegate;
}
+ (instancetype)outputStreamToMemory { return [[self alloc] initToMemory]; }
+ (instancetype)outputStreamToFileAtPath:(NSString *)path append:(BOOL)append {
    return [[self alloc] initToFileAtPath:path append:append];
}
+ (instancetype)outputStreamToBuffer:(uint8_t *)buffer capacity:(NSUInteger)capacity {
    return [[self alloc] initToBuffer:buffer capacity:capacity];
}
+ (instancetype)outputStreamWithURL:(NSURL *)url append:(BOOL)append { return [[self alloc] initWithURL:url append:append]; }
- (instancetype)initToMemory {
    self = [super init];
    _memory = [NSMutableData data];
    return self;
}
- (instancetype)initToBuffer:(uint8_t *)buffer capacity:(NSUInteger)capacity {
    self = [super init];
    _buffer = buffer;
    _capacity = capacity;
    return self;
}
- (instancetype)initToFileAtPath:(NSString *)path append:(BOOL)append {
    self = [super init];
    _path = [path copy];
    _append = append;
    return self;
}
- (instancetype)initWithURL:(NSURL *)url append:(BOOL)append {
    return url.isFileURL ? [self initToFileAtPath:url.path append:append] : nil;
}
- (id<NSStreamDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSStreamDelegate>)d { _delegate = d; }
- (void)open {
    if (_status != NSStreamStatusNotOpen) return;
    if (_path) {
        _file = fopen(_path.fileSystemRepresentation, _append ? "ab" : "wb");
        if (!_file) {
            _status = NSStreamStatusError;
            _error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            return;
        }
    }
    _status = NSStreamStatusOpen;
}
- (void)close {
    if (_file) fclose(_file);
    _file = NULL;
    _status = NSStreamStatusClosed;
}
- (void)dealloc {
    if (_file) fclose(_file);
}
- (NSInteger)write:(const uint8_t *)bytes maxLength:(NSUInteger)len {
    if (_status != NSStreamStatusOpen) return -1;
    if (_file) {
        size_t n = fwrite(bytes, 1, len, _file);
        return n == 0 && len ? -1 : (NSInteger)n;
    }
    if (_buffer) {
        NSUInteger n = MIN(len, _capacity - _written);
        memcpy(_buffer + _written, bytes, n);
        _written += n;
        if (_written >= _capacity) _status = NSStreamStatusAtEnd;
        return (NSInteger)n;
    }
    [_memory appendBytes:bytes length:len];
    return (NSInteger)len;
}
- (BOOL)hasSpaceAvailable { return _status == NSStreamStatusOpen && (!_buffer || _written < _capacity); }
- (id)propertyForKey:(NSStreamPropertyKey)key {
    if ([key isEqualToString:NSStreamDataWrittenToMemoryStreamKey]) return _memory ? [_memory copy] : nil;
    return nil;
}
- (NSStreamStatus)streamStatus { return _status; }
- (NSError *)streamError { return _error; }
@end

NSStreamPropertyKey const NSStreamDataWrittenToMemoryStreamKey = @"NSStreamDataWrittenToMemoryStreamKey";
NSStreamPropertyKey const NSStreamFileCurrentOffsetKey = @"NSStreamFileCurrentOffsetKey";
