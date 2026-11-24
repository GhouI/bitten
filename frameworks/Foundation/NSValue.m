#import "FoundationInternal.h"

/* NSNumber is CoreFoundation-backed; every other NSValue is this class. */
@interface BNConcreteValue : NSValue {
  @public
    void *_bytes;
    size_t _size;
    char *_type;
}
@end

static size_t size_of_type(const char *type) {
    switch (type[0]) {
    case 'c': case 'C': case 'B': return 1;
    case 's': case 'S': return 2;
    case 'i': case 'I': case 'f': return 4;
    case 'l': case 'L': case 'q': case 'Q': case 'd': case '^': case '@': case '#': case ':': case '*': return 8;
    case 'D': return 16;
    }
    if (!strncmp(type, "{_NSRange=", 10)) return sizeof(NSRange);
    if (!strncmp(type, "{CGPoint=", 9) || !strncmp(type, "{CGSize=", 8)) return 16;
    if (!strncmp(type, "{CGRect=", 8)) return 32;
    return 0;
}

@implementation BNConcreteValue
- (void)dealloc {
    free(_bytes);
    free(_type);
}
- (void)getValue:(void *)value { memcpy(value, _bytes, _size); }
- (const char *)objCType { return _type; }
- (void *)pointerValue { return _size >= sizeof(void *) ? *(void **)_bytes : NULL; }
- (id)nonretainedObjectValue { return (__bridge id)self.pointerValue; }
- (NSRange)rangeValue {
    NSRange r = {0, 0};
    if (_size >= sizeof r) memcpy(&r, _bytes, sizeof r);
    return r;
}
- (BOOL)isEqualToValue:(NSValue *)other {
    if (![other isKindOfClass:[BNConcreteValue class]]) return NO;
    BNConcreteValue *o = (BNConcreteValue *)other;
    return o->_size == _size && !strcmp(o->_type, _type) && !memcmp(o->_bytes, _bytes, _size);
}
- (BOOL)isEqual:(id)other { return other == self || ([other isKindOfClass:[NSValue class]] && [self isEqualToValue:other]); }
- (NSUInteger)hash {
    NSUInteger h = _size;
    for (size_t i = 0; i < _size; i++) h = h * 31 + ((unsigned char *)_bytes)[i];
    return h;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description {
    if (!strncmp(_type, "{_NSRange=", 10)) {
        NSRange r = self.rangeValue;
        return [NSString stringWithFormat:@"NSRange: {%lu, %lu}", r.location, r.length];
    }
    return [NSString stringWithFormat:@"<%s: %p>", object_getClassName(self), self];
}
@end

@implementation NSValue (Creation)
@dynamic objCType, pointerValue, nonretainedObjectValue, rangeValue;
- (void)getValue:(void *)value {
    BNRaise("NSInvalidArgumentException", "-[%s getValue:]: not supported for this kind of value", object_getClassName(self));
}
- (BOOL)isEqualToValue:(NSValue *)value { return [self isEqual:value]; }
+ (NSValue *)valueWithBytes:(const void *)value objCType:(const char *)type {
    size_t size = size_of_type(type);
    if (!size) BNRaise("NSInvalidArgumentException", "+[NSValue valueWithBytes:objCType:]: unsupported type encoding '%s'", type);
    BNConcreteValue *v = [BNConcreteValue new];
    v->_size = size;
    v->_bytes = malloc(size);
    memcpy(v->_bytes, value, size);
    v->_type = strdup(type);
    return v;
}
+ (NSValue *)valueWithPointer:(const void *)pointer { return [self valueWithBytes:&pointer objCType:"^v"]; }
+ (NSValue *)valueWithNonretainedObject:(id)object {
    void *p = (__bridge void *)object;
    return [self valueWithBytes:&p objCType:"^v"];
}
+ (NSValue *)valueWithRange:(NSRange)range { return [self valueWithBytes:&range objCType:"{_NSRange=QQ}"]; }
@end
