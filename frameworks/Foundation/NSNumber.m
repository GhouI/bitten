#import "FoundationInternal.h"

static inline CFNumberRef CFN(NSNumber *n) { return (__bridge CFNumberRef)n; }
static BOOL is_boolean(NSNumber *n) { return CFGetTypeID(CFN(n)) == CFBooleanGetTypeID(); }

#define MAKE(Name, CType, CFType)                                                    \
    +(NSNumber *)numberWith##Name : (CType)value {                                   \
        return (__bridge_transfer NSNumber *)CFNumberCreate(NULL, CFType, &value);   \
    }
#define GET(name, CType, CFType)                                                     \
    -(CType)name {                                                                   \
        if (is_boolean(self)) return (CType)CFBooleanGetValue((__bridge CFBooleanRef)self); \
        CType v = 0;                                                                 \
        CFNumberGetValue(CFN(self), CFType, &v);                                     \
        return v;                                                                    \
    }

@implementation NSValue (Foundation)
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@implementation NSNumber (Foundation)
MAKE(Char, char, kCFNumberCharType)
MAKE(Short, short, kCFNumberShortType)
MAKE(Int, int, kCFNumberIntType)
MAKE(Long, long, kCFNumberLongType)
MAKE(LongLong, long long, kCFNumberLongLongType)
MAKE(Float, float, kCFNumberFloatType)
MAKE(Double, double, kCFNumberDoubleType)
MAKE(Integer, NSInteger, kCFNumberNSIntegerType)
+ (NSNumber *)numberWithUnsignedChar:(unsigned char)v { short w = v; return [self numberWithShort:w]; }
+ (NSNumber *)numberWithUnsignedShort:(unsigned short)v { int w = v; return [self numberWithInt:w]; }
+ (NSNumber *)numberWithUnsignedInt:(unsigned int)v { long long w = v; return [self numberWithLongLong:w]; }
+ (NSNumber *)numberWithUnsignedLong:(unsigned long)v { return [self numberWithLongLong:(long long)v]; }
+ (NSNumber *)numberWithUnsignedLongLong:(unsigned long long)v { return [self numberWithLongLong:(long long)v]; }
+ (NSNumber *)numberWithUnsignedInteger:(NSUInteger)v { return [self numberWithLongLong:(long long)v]; }
/* Instances are CF numbers: the initializers hand back the shared kind. */
- (NSNumber *)initWithChar:(char)value { return [NSNumber numberWithChar:value]; }
- (NSNumber *)initWithUnsignedChar:(unsigned char)value { return [NSNumber numberWithUnsignedChar:value]; }
- (NSNumber *)initWithShort:(short)value { return [NSNumber numberWithShort:value]; }
- (NSNumber *)initWithUnsignedShort:(unsigned short)value { return [NSNumber numberWithUnsignedShort:value]; }
- (NSNumber *)initWithInt:(int)value { return [NSNumber numberWithInt:value]; }
- (NSNumber *)initWithUnsignedInt:(unsigned int)value { return [NSNumber numberWithUnsignedInt:value]; }
- (NSNumber *)initWithLongLong:(long long)value { return [NSNumber numberWithLongLong:value]; }
- (NSNumber *)initWithUnsignedLongLong:(unsigned long long)value { return [NSNumber numberWithUnsignedLongLong:value]; }
- (NSNumber *)initWithFloat:(float)value { return [NSNumber numberWithFloat:value]; }
- (NSNumber *)initWithDouble:(double)value { return [NSNumber numberWithDouble:value]; }
- (NSNumber *)initWithBool:(BOOL)value { return [NSNumber numberWithBool:value]; }
- (NSNumber *)initWithInteger:(NSInteger)value { return [NSNumber numberWithInteger:value]; }
- (NSNumber *)initWithUnsignedInteger:(NSUInteger)value { return [NSNumber numberWithUnsignedInteger:value]; }
- (NSNumber *)initWithLong:(long)value { return [NSNumber numberWithLong:value]; }
- (NSNumber *)initWithUnsignedLong:(unsigned long)value { return [NSNumber numberWithUnsignedLong:value]; }
+ (NSNumber *)numberWithBool:(BOOL)v { return (__bridge NSNumber *)(v ? kCFBooleanTrue : kCFBooleanFalse); }

GET(charValue, char, kCFNumberCharType)
GET(intValue, int, kCFNumberIntType)
GET(longValue, long, kCFNumberLongType)
GET(longLongValue, long long, kCFNumberLongLongType)
GET(floatValue, float, kCFNumberFloatType)
GET(doubleValue, double, kCFNumberDoubleType)
GET(integerValue, NSInteger, kCFNumberNSIntegerType)
- (unsigned int)unsignedIntValue { return (unsigned int)self.longLongValue; }
- (short)shortValue { return (short)self.longLongValue; }
- (unsigned short)unsignedShortValue { return (unsigned short)self.longLongValue; }
- (unsigned long)unsignedLongValue { return (unsigned long)self.longLongValue; }
- (unsigned long long)unsignedLongLongValue { return (unsigned long long)self.longLongValue; }
- (NSUInteger)unsignedIntegerValue { return (NSUInteger)self.longLongValue; }
- (BOOL)boolValue {
    if (is_boolean(self)) return CFBooleanGetValue((__bridge CFBooleanRef)self);
    return CFNumberIsFloatType(CFN(self)) ? self.doubleValue != 0.0 : self.longLongValue != 0;
}
- (const char *)objCType {
    if (is_boolean(self)) return "c";
    switch (CFNumberGetType(CFN(self))) {
    case kCFNumberSInt8Type: case kCFNumberCharType: return "c";
    case kCFNumberSInt16Type: case kCFNumberShortType: return "s";
    case kCFNumberSInt32Type: case kCFNumberIntType: return "i";
    case kCFNumberFloat32Type: case kCFNumberFloatType: return "f";
    case kCFNumberFloat64Type: case kCFNumberDoubleType: case kCFNumberCGFloatType: return "d";
    default: return "q";
    }
}
- (NSString *)stringValue {
    if (is_boolean(self)) return self.boolValue ? @"1" : @"0";
    if (CFNumberIsFloatType(CFN(self))) {
        char buf[64];
        double v = self.doubleValue;
        /* shortest representation that reads back as the same value */
        for (int precision = 1; precision <= 17; precision++) {
            snprintf(buf, sizeof buf, "%.*g", precision, v);
            if (strtod(buf, NULL) == v) break;
        }
        return [NSString stringWithUTF8String:buf];
    }
    return [NSString stringWithFormat:@"%lld", self.longLongValue];
}
- (NSString *)description { return self.stringValue; }
- (NSComparisonResult)compare:(NSNumber *)other {
    if (!other) BNRaise("NSInvalidArgumentException", "-[NSNumber compare:]: nil argument");
    if (is_boolean(self) || is_boolean(other) || CFNumberIsFloatType(CFN(self)) || CFNumberIsFloatType(CFN(other))) {
        double a = self.doubleValue, b = other.doubleValue;
        return a < b ? NSOrderedAscending : a > b ? NSOrderedDescending : NSOrderedSame;
    }
    long long a = self.longLongValue, b = other.longLongValue;
    return a < b ? NSOrderedAscending : a > b ? NSOrderedDescending : NSOrderedSame;
}
- (BOOL)isEqualToNumber:(NSNumber *)other { return other && [self compare:other] == NSOrderedSame; }
- (BOOL)isEqual:(id)other {
    return other == self || ([other isKindOfClass:[NSNumber class]] && [self compare:other] == NSOrderedSame);
}
- (NSUInteger)hash {
    double d = self.doubleValue;
    long long i = (long long)d;
    return (double)i == d ? (NSUInteger)i : (NSUInteger)(d * 2654435761.0);
}
- (id)copyWithZone:(NSZone *)zone { return self; }
@end
