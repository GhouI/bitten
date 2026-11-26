/* bitten SDK: the part of Foundation that bitten implements so far.
 * Written from the public API documentation; grows with the framework. */
#ifndef BITTEN_FOUNDATION_H
#define BITTEN_FOUNDATION_H
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <objc/runtime.h>
#include <objc/NSObject.h>
#include <CoreFoundation/CoreFoundation.h>

#include <CoreGraphics/CGGeometry.h>
#include <dispatch/dispatch.h>
typedef CGPoint NSPoint;
typedef CGSize NSSize;
typedef CGRect NSRect;
typedef struct NSEdgeInsets { CGFloat top, left, bottom, right; } NSEdgeInsets;
static inline NSRect NSMakeRect(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { return CGRectMake(x, y, w, h); }
static inline NSPoint NSMakePoint(CGFloat x, CGFloat y) { return CGPointMake(x, y); }
static inline NSSize NSMakeSize(CGFloat w, CGFloat h) { return CGSizeMake(w, h); }
extern const NSPoint NSZeroPoint;
extern const NSSize NSZeroSize;
extern const NSRect NSZeroRect;
extern const NSEdgeInsets NSEdgeInsetsZero;
typedef NS_ENUM(NSUInteger, NSRectEdge) {
    NSRectEdgeMinX = 0, NSRectEdgeMinY = 1, NSRectEdgeMaxX = 2, NSRectEdgeMaxY = 3,
    NSMinXEdge = NSRectEdgeMinX, NSMinYEdge = NSRectEdgeMinY, NSMaxXEdge = NSRectEdgeMaxX, NSMaxYEdge = NSRectEdgeMaxY
};
static inline NSEdgeInsets NSEdgeInsetsMake(CGFloat top, CGFloat left, CGFloat bottom, CGFloat right) {
    NSEdgeInsets e = {top, left, bottom, right};
    return e;
}
BOOL NSEdgeInsetsEqual(NSEdgeInsets a, NSEdgeInsets b);
static inline CGFloat NSMinX(NSRect r) { return r.origin.x; }
static inline CGFloat NSMinY(NSRect r) { return r.origin.y; }
static inline CGFloat NSMaxX(NSRect r) { return r.origin.x + r.size.width; }
static inline CGFloat NSMaxY(NSRect r) { return r.origin.y + r.size.height; }
static inline CGFloat NSMidX(NSRect r) { return r.origin.x + r.size.width / 2; }
static inline CGFloat NSMidY(NSRect r) { return r.origin.y + r.size.height / 2; }
static inline CGFloat NSWidth(NSRect r) { return r.size.width; }
static inline CGFloat NSHeight(NSRect r) { return r.size.height; }
static inline BOOL NSPointInRect(NSPoint p, NSRect r) {
    return p.x >= r.origin.x && p.y >= r.origin.y && p.x < r.origin.x + r.size.width &&
           p.y < r.origin.y + r.size.height;
}
static inline BOOL NSEqualRects(NSRect a, NSRect b) {
    return a.origin.x == b.origin.x && a.origin.y == b.origin.y && a.size.width == b.size.width &&
           a.size.height == b.size.height;
}
static inline BOOL NSEqualSizes(NSSize a, NSSize b) { return a.width == b.width && a.height == b.height; }
static inline BOOL NSEqualPoints(NSPoint a, NSPoint b) { return a.x == b.x && a.y == b.y; }
static inline BOOL NSIsEmptyRect(NSRect r) { return !(r.size.width > 0 && r.size.height > 0); }
NSRect NSOffsetRect(NSRect r, CGFloat dx, CGFloat dy);
NSRect NSInsetRect(NSRect r, CGFloat dx, CGFloat dy);
NSRect NSIntegralRect(NSRect r);
NSRect NSUnionRect(NSRect a, NSRect b);
NSRect NSIntersectionRect(NSRect a, NSRect b);
BOOL NSIntersectsRect(NSRect a, NSRect b);
BOOL NSContainsRect(NSRect a, NSRect b);
BOOL NSMouseInRect(NSPoint p, NSRect r, BOOL flipped);
void NSDivideRect(NSRect r, NSRect *slice, NSRect *rem, CGFloat amount, NSRectEdge edge);
NSString *NSStringFromRect(NSRect r);
NSString *NSStringFromPoint(NSPoint p);
NSString *NSStringFromSize(NSSize s);
NSRect NSRectFromString(NSString *s);
NSPoint NSPointFromString(NSString *s);
NSSize NSSizeFromString(NSString *s);
typedef double NSTimeInterval NS_SWIFT_NAME(TimeInterval);
typedef unsigned short unichar;
typedef struct _NSZone NSZone;
enum { NSNotFound = NSIntegerMax };
typedef struct _NSRange {
    NSUInteger location, length;
} NSRange;
static inline NSRange NSMakeRange(NSUInteger loc, NSUInteger len) {
    NSRange r = {loc, len};
    return r;
}
static inline NSUInteger NSMaxRange(NSRange r) { return r.location + r.length; }
static inline BOOL NSLocationInRange(NSUInteger loc, NSRange r) { return loc - r.location < r.length; }
static inline BOOL NSEqualRanges(NSRange a, NSRange b) { return a.location == b.location && a.length == b.length; }
NSRange NSUnionRange(NSRange a, NSRange b);
NSRange NSIntersectionRange(NSRange a, NSRange b);
@class NSString;
NSString *NSStringFromRange(NSRange r);
NSRange NSRangeFromString(NSString *s);
/* NSDecimal: (-1)^isNegative * mantissa * 10^exponent, the mantissa a
 * 128-bit integer in 16-bit words, least significant first. Swift calls it
 * Decimal. */
#define NSDecimalMaxSize 8
#define NSDecimalNoScale 32767
typedef struct {
    signed int _exponent : 8;
    unsigned int _length : 4;
    unsigned int _isNegative : 1;
    unsigned int _isCompact : 1;
    unsigned int _reserved : 18;
    unsigned short _mantissa[NSDecimalMaxSize];
} NSDecimal;
typedef NS_CLOSED_ENUM(NSUInteger, NSRoundingMode) {
    NSRoundPlain NS_SWIFT_NAME(plain), NSRoundDown NS_SWIFT_NAME(down), NSRoundUp NS_SWIFT_NAME(up),
    NSRoundBankers NS_SWIFT_NAME(bankers)
};
typedef NS_CLOSED_ENUM(NSUInteger, NSCalculationError) {
    NSCalculationNoError = 0, NSCalculationLossOfPrecision, NSCalculationUnderflow, NSCalculationOverflow,
    NSCalculationDivideByZero
};
void NSDecimalRound(NSDecimal *result, const NSDecimal *number, NSInteger scale, NSRoundingMode roundingMode);
typedef NS_CLOSED_ENUM(NSInteger, NSComparisonResult) {
    NSOrderedAscending = -1, NSOrderedSame = 0, NSOrderedDescending = 1
} NS_SWIFT_NAME(ComparisonResult);
typedef NSComparisonResult (^NSComparator)(id a, id b);
typedef NSUInteger NSStringEncoding;
enum {
    NSASCIIStringEncoding = 1,
    NSUTF8StringEncoding = 4,
    NSISOLatin1StringEncoding = 5,
    NSMacOSRomanStringEncoding = 30,
    NSUTF16StringEncoding = 10,
    NSUTF16LittleEndianStringEncoding = 0x94000100,
    NSUTF16BigEndianStringEncoding = 0x90000100
};
typedef NS_OPTIONS(NSUInteger, NSStringCompareOptions) {
    NSCaseInsensitiveSearch NS_SWIFT_NAME(caseInsensitive) = 1,
    NSLiteralSearch NS_SWIFT_NAME(literal) = 2,
    NSBackwardsSearch NS_SWIFT_NAME(backwards) = 4,
    NSAnchoredSearch NS_SWIFT_NAME(anchored) = 8,
    NSNumericSearch NS_SWIFT_NAME(numeric) = 64,
    NSDiacriticInsensitiveSearch NS_SWIFT_NAME(diacriticInsensitive) = 128,
    NSWidthInsensitiveSearch NS_SWIFT_NAME(widthInsensitive) = 256,
    NSForcedOrderingSearch NS_SWIFT_NAME(forcedOrdering) = 512,
    NSRegularExpressionSearch NS_SWIFT_NAME(regularExpression) = 1024
} NS_SWIFT_NAME(NSString.CompareOptions);

#define NS_FORMAT_FUNCTION(F, A) __attribute__((format(__NSString__, F, A)))
#define NS_REQUIRES_NIL_TERMINATION __attribute__((sentinel))

#pragma clang assume_nonnull begin

@class NSString, NSMutableString, NSArray<ObjectType>, NSMutableArray<ObjectType>,
    NSDictionary<KeyType, ObjectType>, NSMutableDictionary<KeyType, ObjectType>, NSData, NSNumber, NSError,
    NSEnumerator<ObjectType>, NSCharacterSet, NSDate, NSURL, NSSet<ObjectType>, NSNotification;

@protocol NSCopying
- (id)copyWithZone:(NSZone *)zone;
@end
@protocol NSMutableCopying
- (id)mutableCopyWithZone:(NSZone *)zone;
@end

typedef struct {
    unsigned long state;
    id __unsafe_unretained _Nullable *_Nullable itemsPtr;
    unsigned long *_Nullable mutationsPtr;
    unsigned long extra[5];
} NSFastEnumerationState;
@protocol NSFastEnumeration
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained[])buffer
                                    count:(NSUInteger)len;
@end


__attribute__((swift_bridge("Swift.String")))
@interface NSString : NSObject <NSCopying, NSMutableCopying>
+ (instancetype)string;
+ (nullable instancetype)stringWithUTF8String:(const char *)cString;
+ (nullable instancetype)stringWithCString:(const char *)cString encoding:(NSStringEncoding)encoding;
+ (instancetype)stringWithString:(NSString *)string;
+ (instancetype)stringWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (nullable instancetype)initWithUTF8String:(const char *)cString;
- (nullable instancetype)initWithCString:(const char *)cString encoding:(NSStringEncoding)encoding;
- (nullable instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)length encoding:(NSStringEncoding)encoding;
- (nullable instancetype)initWithData:(NSData *)data encoding:(NSStringEncoding)encoding;
- (instancetype)initWithString:(NSString *)string;
- (instancetype)initWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (instancetype)initWithFormat:(NSString *)format arguments:(va_list)args NS_FORMAT_FUNCTION(1, 0);
+ (instancetype)stringWithCharacters:(const unichar *)characters length:(NSUInteger)length;
- (instancetype)initWithCharacters:(const unichar *)characters length:(NSUInteger)length;
@property (readonly) NSUInteger length;
- (unichar)characterAtIndex:(NSUInteger)index;
- (void)getCharacters:(unichar *)buffer range:(NSRange)range;
@property (readonly, nullable) const char *UTF8String;
- (nullable const char *)cStringUsingEncoding:(NSStringEncoding)encoding;
- (NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)encoding;
- (nullable NSData *)dataUsingEncoding:(NSStringEncoding)encoding;
- (nullable NSData *)dataUsingEncoding:(NSStringEncoding)encoding allowLossyConversion:(BOOL)lossy;
- (BOOL)canBeConvertedToEncoding:(NSStringEncoding)encoding;
- (BOOL)isEqualToString:(NSString *)string;
- (NSComparisonResult)compare:(NSString *)string;
- (NSComparisonResult)compare:(NSString *)string options:(NSStringCompareOptions)mask;
- (NSComparisonResult)caseInsensitiveCompare:(NSString *)string;
- (BOOL)hasPrefix:(NSString *)prefix;
- (BOOL)hasSuffix:(NSString *)suffix;
- (BOOL)containsString:(NSString *)string;
- (NSRange)rangeOfString:(NSString *)string;
- (NSRange)rangeOfString:(NSString *)string options:(NSStringCompareOptions)mask;
- (NSString *)substringFromIndex:(NSUInteger)from;
- (NSString *)substringToIndex:(NSUInteger)to;
- (NSString *)substringWithRange:(NSRange)range;
- (NSString *)stringByAppendingString:(NSString *)string;
- (NSString *)stringByAppendingFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target withString:(NSString *)replacement;
- (NSArray *)componentsSeparatedByString:(NSString *)separator;
@property (readonly, copy) NSString *lowercaseString;
@property (readonly, copy) NSString *uppercaseString;
@property (readonly) int intValue;
@property (readonly) NSInteger integerValue;
@property (readonly) long long longLongValue;
@property (readonly) double doubleValue;
@property (readonly) float floatValue;
@property (readonly) BOOL boolValue;
@property (readonly, copy) NSString *lastPathComponent;
@property (readonly, copy) NSString *pathExtension;
@property (readonly, copy) NSString *stringByDeletingLastPathComponent;
@property (readonly, copy) NSString *stringByDeletingPathExtension;
- (NSString *)stringByAppendingPathComponent:(NSString *)component;
- (NSString *)stringByAppendingPathExtension:(NSString *)extension;
@property (readonly, copy) NSArray<NSString *> *pathComponents;
@property (readonly, getter=isAbsolutePath) BOOL absolutePath;
@property (readonly, copy) NSString *stringByExpandingTildeInPath;
@property (readonly, copy) NSString *stringByStandardizingPath;
@property (readonly) const char *fileSystemRepresentation;
@property (readonly, copy) NSString *capitalizedString;
- (NSString *)stringByTrimmingCharactersInSet:(NSCharacterSet *)set;
- (NSArray<NSString *> *)componentsSeparatedByCharactersInSet:(NSCharacterSet *)set;
- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set;
- (NSString *)stringByPaddingToLength:(NSUInteger)length withString:(NSString *)pad startingAtIndex:(NSUInteger)index;
+ (nullable instancetype)stringWithContentsOfFile:(NSString *)path encoding:(NSStringEncoding)enc error:(NSError **)error;
- (nullable instancetype)initWithContentsOfFile:(NSString *)path encoding:(NSStringEncoding)enc error:(NSError **)error;
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically encoding:(NSStringEncoding)enc error:(NSError **)error;
@end

@interface NSMutableString : NSString
+ (instancetype)stringWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (void)appendString:(NSString *)string;
- (void)appendFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (void)setString:(NSString *)string;
- (void)insertString:(NSString *)string atIndex:(NSUInteger)index;
- (void)deleteCharactersInRange:(NSRange)range;
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string;
@end

@interface NSValue : NSObject <NSCopying>
@end

@interface NSNumber : NSValue
+ (NSNumber *)numberWithChar:(char)value;
+ (NSNumber *)numberWithUnsignedChar:(unsigned char)value;
+ (NSNumber *)numberWithShort:(short)value;
+ (NSNumber *)numberWithUnsignedShort:(unsigned short)value;
+ (NSNumber *)numberWithInt:(int)value;
+ (NSNumber *)numberWithUnsignedInt:(unsigned int)value;
+ (NSNumber *)numberWithLong:(long)value;
+ (NSNumber *)numberWithUnsignedLong:(unsigned long)value;
+ (NSNumber *)numberWithLongLong:(long long)value;
+ (NSNumber *)numberWithUnsignedLongLong:(unsigned long long)value;
+ (NSNumber *)numberWithFloat:(float)value;
+ (NSNumber *)numberWithDouble:(double)value;
+ (NSNumber *)numberWithBool:(BOOL)value;
+ (NSNumber *)numberWithInteger:(NSInteger)value;
+ (NSNumber *)numberWithUnsignedInteger:(NSUInteger)value;
- (NSNumber *)initWithChar:(char)value NS_SWIFT_NAME(init(value:));
- (NSNumber *)initWithUnsignedChar:(unsigned char)value NS_SWIFT_NAME(init(value:));
- (NSNumber *)initWithShort:(short)value NS_SWIFT_NAME(init(value:));
- (NSNumber *)initWithUnsignedShort:(unsigned short)value NS_SWIFT_NAME(init(value:));
- (NSNumber *)initWithInt:(int)value NS_SWIFT_NAME(init(value:));
- (NSNumber *)initWithUnsignedInt:(unsigned int)value NS_SWIFT_NAME(init(value:));
- (NSNumber *)initWithLongLong:(long long)value NS_SWIFT_NAME(init(value:));
- (NSNumber *)initWithUnsignedLongLong:(unsigned long long)value NS_SWIFT_NAME(init(value:));
- (NSNumber *)initWithFloat:(float)value NS_SWIFT_NAME(init(value:));
- (NSNumber *)initWithDouble:(double)value NS_SWIFT_NAME(init(value:));
- (NSNumber *)initWithBool:(BOOL)value NS_SWIFT_NAME(init(value:));
- (NSNumber *)initWithInteger:(NSInteger)value NS_SWIFT_NAME(init(value:));
- (NSNumber *)initWithUnsignedInteger:(NSUInteger)value NS_SWIFT_NAME(init(value:));
- (NSNumber *)initWithLong:(long)value __attribute__((availability(swift, unavailable)));
- (NSNumber *)initWithUnsignedLong:(unsigned long)value __attribute__((availability(swift, unavailable)));
@property (readonly) char charValue;
@property (readonly) int intValue;
@property (readonly) unsigned int unsignedIntValue;
@property (readonly) long longValue;
@property (readonly) unsigned long unsignedLongValue;
@property (readonly) long long longLongValue;
@property (readonly) unsigned long long unsignedLongLongValue;
@property (readonly) float floatValue;
@property (readonly) double doubleValue;
@property (readonly) BOOL boolValue;
@property (readonly) NSInteger integerValue;
@property (readonly) NSUInteger unsignedIntegerValue;
@property (readonly, copy) NSString *stringValue;
@property (readonly) const char *objCType;
- (NSComparisonResult)compare:(NSNumber *)other;
- (BOOL)isEqualToNumber:(NSNumber *)number;
@end

__attribute__((swift_bridge("Swift.Array")))
@interface NSArray<__covariant ObjectType> : NSObject <NSCopying, NSMutableCopying, NSFastEnumeration>
+ (instancetype)array;
+ (instancetype)arrayWithObject:(ObjectType)object;
+ (instancetype)arrayWithObjects:(const ObjectType[])objects count:(NSUInteger)count;
+ (instancetype)arrayWithObjects:(ObjectType)first, ... NS_REQUIRES_NIL_TERMINATION;
+ (instancetype)arrayWithArray:(NSArray<ObjectType> *)array;
- (instancetype)initWithObjects:(const ObjectType[])objects count:(NSUInteger)count;
- (instancetype)initWithArray:(NSArray<ObjectType> *)array;
@property (readonly) NSUInteger count;
- (ObjectType)objectAtIndex:(NSUInteger)index;
- (ObjectType)objectAtIndexedSubscript:(NSUInteger)index;
@property (readonly) ObjectType firstObject;
@property (readonly) ObjectType lastObject;
- (BOOL)containsObject:(ObjectType)object;
- (NSUInteger)indexOfObject:(ObjectType)object;
- (NSUInteger)indexOfObjectIdenticalTo:(ObjectType)anObject;
- (NSArray<ObjectType> *)arrayByAddingObject:(ObjectType)object;
- (NSArray<ObjectType> *)subarrayWithRange:(NSRange)range;
- (NSString *)componentsJoinedByString:(NSString *)separator;
- (BOOL)isEqualToArray:(NSArray<ObjectType> *)other;
- (void)enumerateObjectsUsingBlock:(void (^)(ObjectType obj, NSUInteger idx, BOOL *stop))block;
- (NSArray<ObjectType> *)sortedArrayUsingComparator:(NSComparator)comparator;
- (NSArray<ObjectType> *)sortedArrayUsingSelector:(SEL)comparator;
- (NSEnumerator<ObjectType> *)objectEnumerator;
- (NSEnumerator<ObjectType> *)reverseObjectEnumerator;
- (NSUInteger)indexOfObjectPassingTest:(BOOL (^)(ObjectType obj, NSUInteger idx, BOOL *stop))predicate;
@end

@interface NSMutableArray<ObjectType> : NSArray<ObjectType>
+ (instancetype)arrayWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (void)addObject:(ObjectType)object;
- (void)addObjectsFromArray:(NSArray<ObjectType> *)array;
- (void)insertObject:(ObjectType)object atIndex:(NSUInteger)index;
- (void)removeObjectAtIndex:(NSUInteger)index;
- (void)removeLastObject;
- (void)removeObject:(ObjectType)object;
- (void)removeObjectIdenticalTo:(ObjectType)anObject;
- (void)removeAllObjects;
- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(ObjectType)object;
- (void)setObject:(ObjectType)object atIndexedSubscript:(NSUInteger)index;
- (void)sortUsingComparator:(NSComparator)comparator;
@end

__attribute__((swift_bridge("Swift.Dictionary")))
@interface NSDictionary<__covariant KeyType, __covariant ObjectType> : NSObject <NSCopying, NSMutableCopying, NSFastEnumeration>
+ (instancetype)dictionary;
+ (instancetype)dictionaryWithObject:(ObjectType)object forKey:(KeyType<NSCopying>)key;
+ (instancetype)dictionaryWithObjects:(const ObjectType[])objects forKeys:(const KeyType<NSCopying>[])keys count:(NSUInteger)count;
+ (instancetype)dictionaryWithDictionary:(NSDictionary<KeyType, ObjectType> *)dictionary;
- (instancetype)initWithObjects:(const ObjectType[])objects forKeys:(const KeyType<NSCopying>[])keys count:(NSUInteger)count;
- (instancetype)initWithDictionary:(NSDictionary<KeyType, ObjectType> *)dictionary;
@property (readonly) NSUInteger count;
- (nullable ObjectType)objectForKey:(KeyType)key;
- (nullable ObjectType)objectForKeyedSubscript:(KeyType)key;
@property (readonly, copy) NSArray<KeyType> *allKeys;
@property (readonly, copy) NSArray<ObjectType> *allValues;
- (BOOL)isEqualToDictionary:(NSDictionary<KeyType, ObjectType> *)other;
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(KeyType key, ObjectType obj, BOOL *stop))block;
- (NSEnumerator<KeyType> *)keyEnumerator;
- (NSEnumerator<ObjectType> *)objectEnumerator;
- (NSArray<KeyType> *)allKeysForObject:(ObjectType)object;
@end

@interface NSMutableDictionary<KeyType, ObjectType> : NSDictionary<KeyType, ObjectType>
+ (instancetype)dictionaryWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (void)setObject:(ObjectType)object forKey:(KeyType<NSCopying>)key;
- (void)setObject:(ObjectType)object forKeyedSubscript:(KeyType<NSCopying>)key;
- (void)removeObjectForKey:(KeyType)key;
- (void)removeAllObjects;
- (void)addEntriesFromDictionary:(NSDictionary<KeyType, ObjectType> *)other;
@end

@interface NSNull : NSObject <NSCopying>
+ (NSNull *)null;
@end

@interface NSAutoreleasePool : NSObject
- (void)drain;
@end


@interface NSEnumerator<ObjectType> : NSObject <NSFastEnumeration>
- (ObjectType)nextObject;
@property (readonly, copy) NSArray<ObjectType> *allObjects;
@end

@interface NSValue (Creation)
+ (NSValue *)valueWithBytes:(const void *)value objCType:(const char *)type;
+ (NSValue *)valueWithPointer:(const void *)pointer;
+ (NSValue *)valueWithNonretainedObject:(id)object;
+ (NSValue *)valueWithRange:(NSRange)range;
- (void)getValue:(void *)value;
@property (readonly) const char *objCType;
@property (readonly) void *pointerValue;
@property (readonly) id nonretainedObjectValue;
@property (readonly) NSRange rangeValue;
- (BOOL)isEqualToValue:(NSValue *)value;
@end

@interface NSValue (NSValueGeometryExtensions)
+ (NSValue *)valueWithPoint:(NSPoint)point;
+ (NSValue *)valueWithSize:(NSSize)size;
+ (NSValue *)valueWithRect:(NSRect)rect;
+ (NSValue *)valueWithEdgeInsets:(NSEdgeInsets)insets;
@property (readonly) NSPoint pointValue;
@property (readonly) NSSize sizeValue;
@property (readonly) NSRect rectValue;
@property (readonly) NSEdgeInsets edgeInsetsValue;
@end

typedef NS_OPTIONS(NSUInteger, NSDataBase64EncodingOptions) {
    NSDataBase64Encoding64CharacterLineLength NS_SWIFT_NAME(lineLength64Characters) = 1,
    NSDataBase64Encoding76CharacterLineLength NS_SWIFT_NAME(lineLength76Characters) = 2,
    NSDataBase64EncodingEndLineWithCarriageReturn NS_SWIFT_NAME(endLineWithCarriageReturn) = 16,
    NSDataBase64EncodingEndLineWithLineFeed NS_SWIFT_NAME(endLineWithLineFeed) = 32
} NS_SWIFT_NAME(NSData.Base64EncodingOptions);
typedef NS_OPTIONS(NSUInteger, NSDataBase64DecodingOptions) {
    NSDataBase64DecodingIgnoreUnknownCharacters NS_SWIFT_NAME(ignoreUnknownCharacters) = 1
} NS_SWIFT_NAME(NSData.Base64DecodingOptions);
typedef NS_OPTIONS(NSUInteger, NSDataReadingOptions) {
    NSDataReadingMappedIfSafe NS_SWIFT_NAME(mappedIfSafe) = 1,
    NSDataReadingUncached NS_SWIFT_NAME(uncached) = 2,
    NSDataReadingMappedAlways NS_SWIFT_NAME(alwaysMapped) = 8
} NS_SWIFT_NAME(NSData.ReadingOptions);
typedef NS_OPTIONS(NSUInteger, NSDataWritingOptions) {
    NSDataWritingAtomic NS_SWIFT_NAME(atomic) = 1,
    NSDataWritingWithoutOverwriting NS_SWIFT_NAME(withoutOverwriting) = 2,
    NSDataWritingFileProtectionNone NS_SWIFT_NAME(noFileProtection) = 0x10000000,
    NSDataWritingFileProtectionComplete NS_SWIFT_NAME(completeFileProtection) = 0x20000000,
    NSDataWritingFileProtectionMask NS_SWIFT_NAME(fileProtectionMask) = 0xf0000000
} NS_SWIFT_NAME(NSData.WritingOptions);
typedef NS_OPTIONS(NSUInteger, NSDataSearchOptions) {
    NSDataSearchBackwards NS_SWIFT_NAME(backwards) = 1,
    NSDataSearchAnchored NS_SWIFT_NAME(anchored) = 2
} NS_SWIFT_NAME(NSData.SearchOptions);
__attribute__((swift_bridge("Foundation.Data")))
@interface NSData : NSObject <NSCopying, NSMutableCopying>
+ (instancetype)data;
+ (instancetype)dataWithBytes:(const void *)bytes length:(NSUInteger)length;
+ (instancetype)dataWithData:(NSData *)data;
+ (instancetype)dataWithContentsOfFile:(NSString *)path;
- (instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)length;
- (instancetype)initWithData:(NSData *)data;
- (instancetype)initWithContentsOfFile:(NSString *)path;
- (instancetype)initWithBase64EncodedString:(NSString *)string options:(NSDataBase64DecodingOptions)options;
@property (readonly) NSUInteger length;
@property (readonly) const void *bytes;
- (void)getBytes:(void *)buffer length:(NSUInteger)length;
- (void)getBytes:(void *)buffer range:(NSRange)range;
- (NSData *)subdataWithRange:(NSRange)range;
- (BOOL)isEqualToData:(NSData *)other;
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically;
- (NSString *)base64EncodedStringWithOptions:(NSDataBase64EncodingOptions)options;
@end
@interface NSMutableData : NSData
+ (instancetype)dataWithCapacity:(NSUInteger)capacity;
+ (instancetype)dataWithLength:(NSUInteger)length;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithLength:(NSUInteger)length;
@property (readonly) void *mutableBytes;
@property NSUInteger length;
- (void)appendBytes:(const void *)bytes length:(NSUInteger)length;
- (void)appendData:(NSData *)other;
- (void)increaseLengthBy:(NSUInteger)extra;
- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)bytes;
- (void)resetBytesInRange:(NSRange)range;
- (void)setData:(NSData *)data;
@end

__attribute__((swift_bridge("Foundation.Date")))
@interface NSDate : NSObject <NSCopying>
+ (instancetype)date;
+ (instancetype)dateWithTimeIntervalSinceNow:(NSTimeInterval)seconds;
+ (instancetype)dateWithTimeIntervalSince1970:(NSTimeInterval)seconds;
+ (instancetype)dateWithTimeIntervalSinceReferenceDate:(NSTimeInterval)seconds;
+ (NSDate *)distantFuture;
+ (NSDate *)distantPast;
+ (NSTimeInterval)timeIntervalSinceReferenceDate;
- (instancetype)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)seconds;
- (instancetype)initWithTimeIntervalSince1970:(NSTimeInterval)seconds;
- (instancetype)initWithTimeIntervalSinceNow:(NSTimeInterval)seconds;
@property (readonly) NSTimeInterval timeIntervalSinceReferenceDate;
@property (readonly) NSTimeInterval timeIntervalSince1970;
@property (readonly) NSTimeInterval timeIntervalSinceNow;
- (NSTimeInterval)timeIntervalSinceDate:(NSDate *)other;
- (instancetype)dateByAddingTimeInterval:(NSTimeInterval)seconds;
- (NSComparisonResult)compare:(NSDate *)other;
- (NSDate *)earlierDate:(NSDate *)other;
- (NSDate *)laterDate:(NSDate *)other;
- (BOOL)isEqualToDate:(NSDate *)other;
@end
#define NSTimeIntervalSince1970 978307200.0

typedef NSString *NSErrorDomain;
extern NSString *const NSCocoaErrorDomain, *const NSPOSIXErrorDomain, *const NSOSStatusErrorDomain;
extern NSErrorDomain const NSURLErrorDomain;
extern NSString *const NSURLErrorFailingURLErrorKey, *const NSURLErrorFailingURLStringErrorKey;
extern NSString *const NSLocalizedDescriptionKey, *const NSLocalizedFailureReasonErrorKey,
    *const NSUnderlyingErrorKey, *const NSFilePathErrorKey;
extern NSString *const NSURLErrorKey, *const NSLocalizedRecoverySuggestionErrorKey,
    *const NSLocalizedRecoveryOptionsErrorKey, *const NSRecoveryAttempterErrorKey, *const NSHelpAnchorErrorKey,
    *const NSMultipleUnderlyingErrorsKey, *const NSStringEncodingErrorKey, *const NSLocalizedFailureErrorKey;
enum {
    NSFileNoSuchFileError = 4, NSFileReadNoSuchFileError = 260, NSFileReadUnsupportedSchemeError = 262, NSFileReadNoPermissionError = 257,
    NSFileReadUnknownError = 256, NSFileReadInapplicableStringEncodingError = 261,
    NSFileWriteUnknownError = 512, NSFileWriteNoPermissionError = 513, NSFileWriteFileExistsError = 516,
    NSPropertyListReadCorruptError = 3840
};
@interface NSError : NSObject <NSCopying>
+ (instancetype)errorWithDomain:(NSErrorDomain)domain code:(NSInteger)code userInfo:(nullable NSDictionary *)userInfo;
- (instancetype)initWithDomain:(NSErrorDomain)domain code:(NSInteger)code userInfo:(nullable NSDictionary *)userInfo;
@property (readonly, copy) NSErrorDomain domain;
@property (readonly) NSInteger code;
@property (nullable, readonly, copy) NSDictionary *userInfo;
@property (readonly, copy) NSString *localizedDescription;
@property (readonly, copy) NSString *localizedFailureReason;
@end
@interface NSError (BittenSwift)
+ (NSError *)_bn_errorWithDomain:(NSString *)domain code:(NSInteger)code
                        filePath:(nullable NSString *)path underlyingPOSIX:(int)posix;
@end

__attribute__((swift_bridge("Swift.Set")))
@interface NSSet<__covariant ObjectType> : NSObject <NSCopying, NSMutableCopying, NSFastEnumeration>
+ (instancetype)set;
+ (instancetype)setWithObject:(ObjectType)object;
+ (instancetype)setWithObjects:(const ObjectType[])objects count:(NSUInteger)count;
+ (instancetype)setWithObjects:(ObjectType)first, ... NS_REQUIRES_NIL_TERMINATION;
+ (instancetype)setWithArray:(NSArray<ObjectType> *)array;
- (instancetype)initWithObjects:(const ObjectType[])objects count:(NSUInteger)count;
- (instancetype)initWithArray:(NSArray<ObjectType> *)array;
- (instancetype)initWithSet:(NSSet<ObjectType> *)set;
@property (readonly) NSUInteger count;
- (BOOL)containsObject:(ObjectType)object;
- (ObjectType)member:(ObjectType)object;
@property (readonly, copy) NSArray<ObjectType> *allObjects;
- (ObjectType)anyObject;
- (BOOL)isEqualToSet:(NSSet<ObjectType> *)other;
- (BOOL)isSubsetOfSet:(NSSet<ObjectType> *)other;
- (BOOL)intersectsSet:(NSSet<ObjectType> *)other;
- (void)enumerateObjectsUsingBlock:(void (^)(ObjectType obj, BOOL *stop))block;
- (NSSet<ObjectType> *)setByAddingObject:(ObjectType)object;
@end
@interface NSMutableSet<ObjectType> : NSSet<ObjectType>
+ (instancetype)setWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (void)addObject:(ObjectType)object;
- (void)removeObject:(ObjectType)object;
- (void)removeAllObjects;
- (void)addObjectsFromArray:(NSArray<ObjectType> *)array;
- (void)unionSet:(NSSet<ObjectType> *)other;
- (void)minusSet:(NSSet<ObjectType> *)other;
- (void)intersectSet:(NSSet<ObjectType> *)other;
@end

@interface NSCharacterSet : NSObject <NSCopying, NSMutableCopying>
@property (class, readonly, copy) NSCharacterSet *whitespaceCharacterSet NS_SWIFT_NAME(whitespaces);
@property (class, readonly, copy) NSCharacterSet *whitespaceAndNewlineCharacterSet NS_SWIFT_NAME(whitespacesAndNewlines);
@property (class, readonly, copy) NSCharacterSet *newlineCharacterSet NS_SWIFT_NAME(newlines);
@property (class, readonly, copy) NSCharacterSet *decimalDigitCharacterSet NS_SWIFT_NAME(decimalDigits);
@property (class, readonly, copy) NSCharacterSet *letterCharacterSet NS_SWIFT_NAME(letters);
@property (class, readonly, copy) NSCharacterSet *alphanumericCharacterSet NS_SWIFT_NAME(alphanumerics);
@property (class, readonly, copy) NSCharacterSet *uppercaseLetterCharacterSet NS_SWIFT_NAME(uppercaseLetters);
@property (class, readonly, copy) NSCharacterSet *lowercaseLetterCharacterSet NS_SWIFT_NAME(lowercaseLetters);
@property (class, readonly, copy) NSCharacterSet *punctuationCharacterSet NS_SWIFT_NAME(punctuationCharacters);
@property (class, readonly, copy) NSCharacterSet *controlCharacterSet NS_SWIFT_NAME(controlCharacters);
+ (instancetype)characterSetWithCharactersInString:(NSString *)string;
+ (instancetype)characterSetWithRange:(NSRange)range;
- (BOOL)characterIsMember:(unichar)character;
@property (readonly, copy) NSCharacterSet *invertedSet;
@end
@interface NSMutableCharacterSet : NSCharacterSet
- (void)addCharactersInString:(NSString *)string;
- (void)addCharactersInRange:(NSRange)range;
- (void)removeCharactersInString:(NSString *)string;
- (void)removeCharactersInRange:(NSRange)range;
- (void)formUnionWithCharacterSet:(NSCharacterSet *)other;
- (void)invert;
@end

typedef NSString *NSExceptionName;
extern NSExceptionName const NSGenericException, NSRangeException, NSInvalidArgumentException,
    NSInternalInconsistencyException, NSMallocException;
@interface NSException : NSObject <NSCopying>
+ (NSException *)exceptionWithName:(NSExceptionName)name reason:(NSString *)reason userInfo:(NSDictionary *)userInfo;
+ (void)raise:(NSExceptionName)name format:(NSString *)format, ... NS_FORMAT_FUNCTION(2, 3) __attribute__((noreturn));
- (instancetype)initWithName:(NSExceptionName)name reason:(NSString *)reason userInfo:(NSDictionary *)userInfo;
@property (readonly, copy) NSExceptionName name;
@property (readonly, copy) NSString *reason;
@property (nullable, readonly, copy) NSDictionary *userInfo;
- (void)raise __attribute__((noreturn));
@end

typedef struct {
    NSInteger majorVersion, minorVersion, patchVersion;
} NSOperatingSystemVersion;
NS_SWIFT_NAME(ProcessInfo)
@interface NSProcessInfo : NSObject
@property (class, readonly, strong) NSProcessInfo *processInfo;
@property (readonly, copy) NSArray<NSString *> *arguments;
@property (readonly, copy) NSDictionary<NSString *, NSString *> *environment;
@property (copy) NSString *processName;
@property (readonly) int processIdentifier;
@property (readonly, copy) NSString *hostName;
@property (readonly, copy) NSString *operatingSystemVersionString;
@property (readonly) NSOperatingSystemVersion operatingSystemVersion;
@property (readonly) NSUInteger processorCount;
@property (readonly) NSUInteger activeProcessorCount;
@property (readonly) unsigned long long physicalMemory;
@property (readonly) NSTimeInterval systemUptime;
@property (readonly, copy) NSString *globallyUniqueString;
@property (readonly, copy) NSString *userName;
- (BOOL)isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)version;
@end

typedef NSString *NSFileAttributeKey;
extern NSFileAttributeKey const NSFileSize, NSFileType, NSFileModificationDate, NSFileCreationDate,
    NSFilePosixPermissions, NSFileOwnerAccountID, NSFileGroupOwnerAccountID;
extern NSString *const NSFileTypeRegular, *const NSFileTypeDirectory, *const NSFileTypeSymbolicLink,
    *const NSFileTypeUnknown;
typedef NS_ENUM(NSUInteger, NSSearchPathDirectory) {
    NSApplicationDirectory = 1, NSDemoApplicationDirectory, NSDeveloperApplicationDirectory, NSAdminApplicationDirectory,
    NSLibraryDirectory, NSDeveloperDirectory, NSUserDirectory, NSDocumentationDirectory, NSDocumentDirectory,
    NSCoreServiceDirectory, NSAutosavedInformationDirectory = 11, NSDesktopDirectory = 12, NSCachesDirectory = 13,
    NSApplicationSupportDirectory = 14, NSDownloadsDirectory = 15, NSInputMethodsDirectory = 16, NSMoviesDirectory = 17,
    NSMusicDirectory = 18, NSPicturesDirectory = 19, NSPrinterDescriptionDirectory = 20, NSSharedPublicDirectory = 21,
    NSPreferencePanesDirectory = 22, NSApplicationScriptsDirectory = 23, NSItemReplacementDirectory = 99,
    NSAllApplicationsDirectory = 100, NSAllLibrariesDirectory = 101, NSTrashDirectory = 102
};
typedef NS_OPTIONS(NSUInteger, NSSearchPathDomainMask) {
    NSUserDomainMask = 1, NSLocalDomainMask = 2, NSNetworkDomainMask = 4, NSSystemDomainMask = 8, NSAllDomainsMask = 0x0ffff
};
NSArray<NSString *> *NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory directory, NSSearchPathDomainMask domainMask, BOOL expandTilde);
typedef NS_OPTIONS(NSUInteger, NSDirectoryEnumerationOptions) {
    NSDirectoryEnumerationSkipsSubdirectoryDescendants = 1, NSDirectoryEnumerationSkipsPackageDescendants = 2,
    NSDirectoryEnumerationSkipsHiddenFiles = 4
};
NS_SWIFT_NAME(FileManager)
@interface NSFileManager : NSObject
- (NSArray<NSURL *> *)URLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domainMask;
- (nullable NSURL *)URLForDirectory:(NSSearchPathDirectory)directory inDomain:(NSSearchPathDomainMask)domain
                  appropriateForURL:(nullable NSURL *)url create:(BOOL)shouldCreate error:(NSError **)error;
@property (readonly, copy) NSURL *homeDirectoryForCurrentUser;
- (BOOL)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates
                  attributes:(nullable NSDictionary *)attributes error:(NSError **)error;
- (BOOL)removeItemAtURL:(NSURL *)URL error:(NSError **)error;
- (BOOL)copyItemAtURL:(NSURL *)srcURL toURL:(NSURL *)dstURL error:(NSError **)error;
- (BOOL)moveItemAtURL:(NSURL *)srcURL toURL:(NSURL *)dstURL error:(NSError **)error;
- (nullable NSArray<NSURL *> *)contentsOfDirectoryAtURL:(NSURL *)url includingPropertiesForKeys:(nullable NSArray *)keys
                                                options:(NSDirectoryEnumerationOptions)mask error:(NSError **)error;
@property (class, readonly, strong) NSFileManager *defaultManager;
@property (readonly, copy) NSString *currentDirectoryPath;
- (BOOL)changeCurrentDirectoryPath:(NSString *)path;
- (BOOL)fileExistsAtPath:(NSString *)path;
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory;
- (BOOL)isReadableFileAtPath:(NSString *)path;
- (BOOL)isWritableFileAtPath:(NSString *)path;
- (BOOL)isExecutableFileAtPath:(NSString *)path;
- (NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;
- (NSArray<NSString *> *)subpathsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)intermediates attributes:(nullable NSDictionary *)attributes error:(NSError **)error;
- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary *)attributes;
- (NSData *)contentsAtPath:(NSString *)path;
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)copyItemAtPath:(NSString *)source toPath:(NSString *)destination error:(NSError **)error;
- (BOOL)moveItemAtPath:(NSString *)source toPath:(NSString *)destination error:(NSError **)error;
- (BOOL)createSymbolicLinkAtPath:(NSString *)path withDestinationPath:(NSString *)destination error:(NSError **)error;
- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path error:(NSError **)error;
- (NSDictionary<NSFileAttributeKey, id> *)attributesOfItemAtPath:(NSString *)path error:(NSError **)error;
@property (readonly, copy) NSURL *temporaryDirectory;
@end
NSString *NSTemporaryDirectory(void);
NSString *NSHomeDirectory(void);
NSString *NSUserName(void);

__attribute__((swift_bridge("Foundation.URL")))
@interface NSURL : NSObject <NSCopying>
- (BOOL)checkResourceIsReachableAndReturnError:(NSError **)error NS_SWIFT_NOTHROW;
- (BOOL)checkPromisedItemIsReachableAndReturnError:(NSError **)error NS_SWIFT_NOTHROW;
+ (nullable instancetype)URLWithString:(NSString *)string;
+ (instancetype)fileURLWithPath:(NSString *)path;
+ (instancetype)fileURLWithPath:(NSString *)path isDirectory:(BOOL)isDirectory;
- (nullable instancetype)initWithString:(NSString *)string;
- (instancetype)initFileURLWithPath:(NSString *)path;
@property (nullable, readonly, copy) NSString *absoluteString;
@property (nullable, readonly, copy) NSString *scheme;
@property (nullable, readonly, copy) NSString *host;
@property (nullable, readonly, copy) NSNumber *port;
@property (nullable, readonly, copy) NSString *path;
@property (nullable, readonly, copy) NSString *query;
@property (nullable, readonly, copy) NSString *fragment;
@property (readonly, copy) NSString *lastPathComponent;
@property (readonly, copy) NSString *pathExtension;
@property (readonly, getter=isFileURL) BOOL fileURL;
- (NSURL *)URLByAppendingPathComponent:(NSString *)component;
@property (nullable, readonly, copy) NSURL *URLByDeletingLastPathComponent;
@end

typedef NSUInteger NSJSONReadingOptions;
typedef NSUInteger NSJSONWritingOptions;
enum { NSJSONReadingMutableContainers = 1, NSJSONReadingMutableLeaves = 2, NSJSONReadingFragmentsAllowed = 4 };
enum { NSJSONWritingPrettyPrinted = 1, NSJSONWritingSortedKeys = 2, NSJSONWritingFragmentsAllowed = 4,
       NSJSONWritingWithoutEscapingSlashes = 8 };
NS_SWIFT_NAME(JSONSerialization)
@interface NSJSONSerialization : NSObject
+ (BOOL)isValidJSONObject:(id)object;
+ (NSData *)dataWithJSONObject:(id)object options:(NSJSONWritingOptions)options error:(NSError **)error;
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)options error:(NSError **)error;
@end

typedef NS_OPTIONS(NSUInteger, NSPropertyListMutabilityOptions) {
    NSPropertyListImmutable = 0,
    NSPropertyListMutableContainers = 1,
    NSPropertyListMutableContainersAndLeaves = 2
};
typedef NSPropertyListMutabilityOptions NSPropertyListReadOptions;
typedef NSUInteger NSPropertyListWriteOptions;
typedef NS_ENUM(NSUInteger, NSPropertyListFormat) {
    NSPropertyListOpenStepFormat = 1,
    NSPropertyListXMLFormat_v1_0 = 100,
    NSPropertyListBinaryFormat_v1_0 = 200
};
NS_SWIFT_NAME(PropertyListSerialization)
@interface NSPropertyListSerialization : NSObject
+ (BOOL)propertyList:(id)plist isValidForFormat:(NSPropertyListFormat)format;
+ (nullable NSData *)dataWithPropertyList:(id)plist format:(NSPropertyListFormat)format
                                  options:(NSPropertyListWriteOptions)opt error:(NSError **)error;
+ (nullable id)propertyListWithData:(NSData *)data options:(NSPropertyListReadOptions)opt
                             format:(nullable NSPropertyListFormat *)format error:(NSError **)error;
@end

NS_SWIFT_NAME(Bundle)
@interface NSBundle : NSObject
@property (class, readonly, strong) NSBundle *mainBundle;
+ (nullable instancetype)bundleWithPath:(NSString *)path;
+ (nullable instancetype)bundleWithURL:(NSURL *)url;
+ (NSBundle *)bundleForClass:(Class)aClass;
+ (nullable NSBundle *)bundleWithIdentifier:(NSString *)identifier;
@property (class, readonly, copy) NSArray<NSBundle *> *allBundles;
@property (class, readonly, copy) NSArray<NSBundle *> *allFrameworks;
- (nullable instancetype)initWithPath:(NSString *)path;
- (nullable instancetype)initWithURL:(NSURL *)url;
@property (readonly, copy) NSString *bundlePath;
@property (readonly, copy) NSURL *bundleURL;
@property (nullable, readonly, copy) NSString *resourcePath;
@property (nullable, readonly, copy) NSURL *resourceURL;
@property (nullable, readonly, copy) NSString *executablePath;
@property (nullable, readonly, copy) NSURL *executableURL;
@property (nullable, readonly, copy) NSString *privateFrameworksPath;
@property (nullable, readonly, copy) NSURL *privateFrameworksURL;
@property (nullable, readonly, copy) NSString *sharedFrameworksPath;
@property (nullable, readonly, copy) NSString *builtInPlugInsPath;
@property (nullable, readonly, copy) NSURL *builtInPlugInsURL;
@property (nullable, readonly, copy) NSURL *appStoreReceiptURL;
@property (nullable, readonly, copy) NSString *bundleIdentifier;
@property (nullable, readonly, copy) NSDictionary<NSString *, id> *infoDictionary;
@property (nullable, readonly, copy) NSDictionary<NSString *, id> *localizedInfoDictionary;
- (nullable id)objectForInfoDictionaryKey:(NSString *)key;
@property (nullable, readonly) Class principalClass;
@property (readonly, copy) NSArray<NSString *> *localizations;
@property (readonly, copy) NSArray<NSString *> *preferredLocalizations;
@property (nullable, readonly, copy) NSString *developmentLocalization;
- (BOOL)load;
@property (readonly, getter=isLoaded) BOOL loaded;
- (BOOL)unload;
- (BOOL)loadAndReturnError:(NSError **)error;
- (nullable NSString *)pathForResource:(nullable NSString *)name ofType:(nullable NSString *)ext;
- (nullable NSString *)pathForResource:(nullable NSString *)name ofType:(nullable NSString *)ext inDirectory:(nullable NSString *)subpath;
- (NSArray<NSString *> *)pathsForResourcesOfType:(nullable NSString *)ext inDirectory:(nullable NSString *)subpath;
- (nullable NSURL *)URLForResource:(nullable NSString *)name withExtension:(nullable NSString *)ext;
- (nullable NSURL *)URLForResource:(nullable NSString *)name withExtension:(nullable NSString *)ext subdirectory:(nullable NSString *)subpath;
- (nullable NSArray<NSURL *> *)URLsForResourcesWithExtension:(nullable NSString *)ext subdirectory:(nullable NSString *)subpath;
- (NSString *)localizedStringForKey:(NSString *)key value:(nullable NSString *)value table:(nullable NSString *)tableName;
@end
#define NSLocalizedString(key, comment) [NSBundle.mainBundle localizedStringForKey:(key) value:@"" table:nil]

extern NSString *const NSGlobalDomain, *const NSArgumentDomain, *const NSRegistrationDomain;
extern NSString *const NSUserDefaultsDidChangeNotification;
NS_SWIFT_NAME(UserDefaults)
@interface NSUserDefaults : NSObject
@property (class, readonly, strong) NSUserDefaults *standardUserDefaults;
+ (void)resetStandardUserDefaults;
- (instancetype)init;
- (nullable instancetype)initWithSuiteName:(nullable NSString *)suitename;
- (nullable id)objectForKey:(NSString *)defaultName;
- (void)setObject:(nullable id)value forKey:(NSString *)defaultName NS_SWIFT_NAME(set(_:forKey:));
- (void)removeObjectForKey:(NSString *)defaultName;
- (nullable NSString *)stringForKey:(NSString *)defaultName;
- (nullable NSArray *)arrayForKey:(NSString *)defaultName;
- (nullable NSDictionary<NSString *, id> *)dictionaryForKey:(NSString *)defaultName;
- (nullable NSData *)dataForKey:(NSString *)defaultName;
- (nullable NSArray<NSString *> *)stringArrayForKey:(NSString *)defaultName;
- (NSInteger)integerForKey:(NSString *)defaultName;
- (float)floatForKey:(NSString *)defaultName;
- (double)doubleForKey:(NSString *)defaultName;
- (BOOL)boolForKey:(NSString *)defaultName;
- (nullable NSURL *)URLForKey:(NSString *)defaultName NS_SWIFT_NAME(url(forKey:));
- (void)setInteger:(NSInteger)value forKey:(NSString *)defaultName NS_SWIFT_NAME(set(_:forKey:));
- (void)setFloat:(float)value forKey:(NSString *)defaultName NS_SWIFT_NAME(set(_:forKey:));
- (void)setDouble:(double)value forKey:(NSString *)defaultName NS_SWIFT_NAME(set(_:forKey:));
- (void)setBool:(BOOL)value forKey:(NSString *)defaultName NS_SWIFT_NAME(set(_:forKey:));
- (void)setURL:(nullable NSURL *)url forKey:(NSString *)defaultName NS_SWIFT_NAME(set(_:forKey:));
- (void)registerDefaults:(NSDictionary<NSString *, id> *)registrationDictionary;
- (void)addSuiteNamed:(NSString *)suiteName;
- (void)removeSuiteNamed:(NSString *)suiteName;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
@property (readonly, copy) NSArray<NSString *> *volatileDomainNames;
- (NSDictionary<NSString *, id> *)volatileDomainForName:(NSString *)domainName;
- (void)setVolatileDomain:(NSDictionary<NSString *, id> *)domain forName:(NSString *)domainName;
- (void)removeVolatileDomainForName:(NSString *)domainName;
- (nullable NSDictionary<NSString *, id> *)persistentDomainForName:(NSString *)domainName;
- (void)setPersistentDomain:(NSDictionary<NSString *, id> *)domain forName:(NSString *)domainName;
- (void)removePersistentDomainForName:(NSString *)domainName;
- (BOOL)synchronize;
- (BOOL)objectIsForcedForKey:(NSString *)key;
- (BOOL)objectIsForcedForKey:(NSString *)key inDomain:(NSString *)domain;
@end

typedef NSString *NSNotificationName NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(NSNotification.Name);
__attribute__((swift_bridge("Foundation.Notification")))
@interface NSNotification : NSObject <NSCopying>
+ (instancetype)notificationWithName:(NSNotificationName)name object:(nullable id)object;
+ (instancetype)notificationWithName:(NSNotificationName)name object:(nullable id)object
                            userInfo:(nullable NSDictionary *)userInfo;
- (instancetype)initWithName:(NSNotificationName)name object:(nullable id)object
                    userInfo:(nullable NSDictionary *)userInfo;
@property (readonly, copy) NSNotificationName name;
@property (nullable, readonly, strong) id object;
@property (nullable, readonly, copy) NSDictionary *userInfo;
@end
@class NSOperationQueue;
NS_SWIFT_NAME(NotificationCenter)
@interface NSNotificationCenter : NSObject
@property (class, readonly, strong) NSNotificationCenter *defaultCenter;
- (void)addObserver:(id)observer selector:(SEL)selector name:(nullable NSNotificationName)name object:(nullable id)object;
- (id<NSObject>)addObserverForName:(nullable NSNotificationName)name object:(nullable id)object
                             queue:(nullable NSOperationQueue *)queue usingBlock:(void (^)(NSNotification *note))block
    NS_SWIFT_NAME(addObserver(forName:object:queue:using:));
- (void)removeObserver:(id)observer;
- (void)removeObserver:(id)observer name:(nullable NSNotificationName)name object:(nullable id)object;
- (void)postNotification:(NSNotification *)notification;
- (void)postNotificationName:(NSNotificationName)name object:(nullable id)object NS_SWIFT_NAME(post(name:object:));
- (void)postNotificationName:(NSNotificationName)name object:(nullable id)object userInfo:(nullable NSDictionary *)userInfo
    NS_SWIFT_NAME(post(name:object:userInfo:));
@end
typedef NSString *NSDistributedNotificationCenterType;
typedef NS_ENUM(NSUInteger, NSNotificationSuspensionBehavior) {
    NSNotificationSuspensionBehaviorDrop = 1, NSNotificationSuspensionBehaviorCoalesce = 2,
    NSNotificationSuspensionBehaviorHold = 3, NSNotificationSuspensionBehaviorDeliverImmediately = 4
};
typedef NS_OPTIONS(NSUInteger, NSDistributedNotificationOptions) {
    NSDistributedNotificationDeliverImmediately = 1, NSDistributedNotificationPostToAllSessions = 2
};
NS_SWIFT_NAME(DistributedNotificationCenter)
@interface NSDistributedNotificationCenter : NSNotificationCenter
+ (NSDistributedNotificationCenter *)notificationCenterForType:(NSDistributedNotificationCenterType)type;
+ (NSDistributedNotificationCenter *)defaultCenter;
- (void)addObserver:(id)observer selector:(SEL)selector name:(nullable NSNotificationName)name
             object:(nullable NSString *)object suspensionBehavior:(NSNotificationSuspensionBehavior)behavior;
- (void)postNotificationName:(NSNotificationName)name object:(nullable NSString *)object
                    userInfo:(nullable NSDictionary *)userInfo deliverImmediately:(BOOL)deliverImmediately;
- (void)postNotificationName:(NSNotificationName)name object:(nullable NSString *)object
                    userInfo:(nullable NSDictionary *)userInfo options:(NSDistributedNotificationOptions)options;
@property BOOL suspended;
@end

typedef NS_ENUM(NSInteger, NSQualityOfService) {
    NSQualityOfServiceUserInteractive = 0x21,
    NSQualityOfServiceUserInitiated = 0x19,
    NSQualityOfServiceUtility = 0x11,
    NSQualityOfServiceBackground = 0x09,
    NSQualityOfServiceDefault = -1
};
typedef NS_ENUM(NSInteger, NSOperationQueuePriority) {
    NSOperationQueuePriorityVeryLow = -8, NSOperationQueuePriorityLow = -4, NSOperationQueuePriorityNormal = 0,
    NSOperationQueuePriorityHigh = 4, NSOperationQueuePriorityVeryHigh = 8
};
NS_SWIFT_NAME(Operation)
@interface NSOperation : NSObject
- (void)start;
- (void)main;
@property (readonly, getter=isCancelled) BOOL cancelled;
- (void)cancel;
@property (readonly, getter=isExecuting) BOOL executing;
@property (readonly, getter=isFinished) BOOL finished;
@property (readonly, getter=isConcurrent) BOOL concurrent;
@property (readonly, getter=isAsynchronous) BOOL asynchronous;
@property (readonly, getter=isReady) BOOL ready;
- (void)addDependency:(NSOperation *)op;
- (void)removeDependency:(NSOperation *)op;
@property (readonly, copy) NSArray<NSOperation *> *dependencies;
@property NSOperationQueuePriority queuePriority;
@property (nullable, copy) void (^completionBlock)(void);
- (void)waitUntilFinished;
@property double threadPriority;
@property NSQualityOfService qualityOfService;
@property (nullable, copy) NSString *name;
@end
NS_SWIFT_NAME(BlockOperation)
@interface NSBlockOperation : NSOperation
+ (instancetype)blockOperationWithBlock:(void (^)(void))block;
- (void)addExecutionBlock:(void (^)(void))block;
@property (readonly, copy) NSArray<void (^)(void)> *executionBlocks;
@end
#define NSOperationQueueDefaultMaxConcurrentOperationCount (-1)
NS_SWIFT_NAME(OperationQueue)
@interface NSOperationQueue : NSObject
- (void)addOperation:(NSOperation *)op;
- (void)addOperations:(NSArray<NSOperation *> *)ops waitUntilFinished:(BOOL)wait;
- (void)addOperationWithBlock:(void (^)(void))block;
- (void)addBarrierBlock:(void (^)(void))barrier;
@property NSInteger maxConcurrentOperationCount;
@property (getter=isSuspended) BOOL suspended;
@property (nullable, copy) NSString *name;
@property NSQualityOfService qualityOfService;
@property (nullable, assign) dispatch_queue_t underlyingQueue;
- (void)cancelAllOperations;
- (void)waitUntilAllOperationsAreFinished;
@property (class, readonly, strong, nullable) NSOperationQueue *currentQueue;
@property (class, readonly, strong) NSOperationQueue *mainQueue;
@property (readonly, copy) NSArray<__kindof NSOperation *> *operations;
@property (readonly) NSUInteger operationCount;
@end

typedef NS_OPTIONS(NSUInteger, NSPointerFunctionsOptions) {
    NSPointerFunctionsStrongMemory = 0, NSPointerFunctionsOpaqueMemory = 2, NSPointerFunctionsMallocMemory = 3,
    NSPointerFunctionsMachVirtualMemory = 4, NSPointerFunctionsWeakMemory = 5,
    NSPointerFunctionsObjectPersonality = 0, NSPointerFunctionsOpaquePersonality = 1 << 8,
    NSPointerFunctionsObjectPointerPersonality = 2 << 8, NSPointerFunctionsCStringPersonality = 3 << 8,
    NSPointerFunctionsStructPersonality = 4 << 8, NSPointerFunctionsIntegerPersonality = 5 << 8,
    NSPointerFunctionsCopyIn = 1 << 16
};
typedef NSPointerFunctionsOptions NSHashTableOptions;
typedef NSPointerFunctionsOptions NSMapTableOptions;
@interface NSPointerFunctions : NSObject
+ (NSPointerFunctions *)pointerFunctionsWithOptions:(NSPointerFunctionsOptions)options;
- (instancetype)initWithOptions:(NSPointerFunctionsOptions)options;
@property (readonly) BOOL usesWeakReadAndWriteBarriers;
@end
@interface NSHashTable<ObjectType> : NSObject <NSCopying, NSFastEnumeration>
- (instancetype)initWithOptions:(NSPointerFunctionsOptions)options capacity:(NSUInteger)initialCapacity;
+ (NSHashTable<ObjectType> *)hashTableWithOptions:(NSPointerFunctionsOptions)options;
+ (NSHashTable<ObjectType> *)weakObjectsHashTable;
@property (readonly, copy) NSPointerFunctions *pointerFunctions;
@property (readonly) NSUInteger count;
- (nullable ObjectType)member:(nullable ObjectType)object;
- (NSEnumerator<ObjectType> *)objectEnumerator;
- (void)addObject:(nullable ObjectType)object;
- (void)removeObject:(nullable ObjectType)object;
- (void)removeAllObjects;
@property (readonly, copy) NSArray<ObjectType> *allObjects;
@property (nullable, nonatomic, readonly) ObjectType anyObject;
- (BOOL)containsObject:(nullable ObjectType)anObject;
- (BOOL)intersectsHashTable:(NSHashTable<ObjectType> *)other;
- (BOOL)isEqualToHashTable:(NSHashTable<ObjectType> *)other;
- (BOOL)isSubsetOfHashTable:(NSHashTable<ObjectType> *)other;
- (void)intersectHashTable:(NSHashTable<ObjectType> *)other;
- (void)unionHashTable:(NSHashTable<ObjectType> *)other;
- (void)minusHashTable:(NSHashTable<ObjectType> *)other;
@property (readonly, copy) NSSet<ObjectType> *setRepresentation;
@end
@interface NSMapTable<KeyType, ObjectType> : NSObject <NSCopying, NSFastEnumeration>
- (instancetype)initWithKeyOptions:(NSPointerFunctionsOptions)keyOptions
                      valueOptions:(NSPointerFunctionsOptions)valueOptions capacity:(NSUInteger)initialCapacity;
+ (NSMapTable<KeyType, ObjectType> *)mapTableWithKeyOptions:(NSPointerFunctionsOptions)keyOptions
                                               valueOptions:(NSPointerFunctionsOptions)valueOptions;
+ (NSMapTable<KeyType, ObjectType> *)strongToStrongObjectsMapTable;
+ (NSMapTable<KeyType, ObjectType> *)weakToStrongObjectsMapTable;
+ (NSMapTable<KeyType, ObjectType> *)strongToWeakObjectsMapTable;
+ (NSMapTable<KeyType, ObjectType> *)weakToWeakObjectsMapTable;
- (nullable ObjectType)objectForKey:(nullable KeyType)aKey;
- (void)removeObjectForKey:(nullable KeyType)aKey;
- (void)setObject:(nullable ObjectType)anObject forKey:(nullable KeyType)aKey;
@property (readonly) NSUInteger count;
- (NSEnumerator<KeyType> *)keyEnumerator;
- (nullable NSEnumerator<ObjectType> *)objectEnumerator;
- (void)removeAllObjects;
- (NSDictionary<KeyType, ObjectType> *)dictionaryRepresentation;
@end

typedef NSString *NSRunLoopMode NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(RunLoop.Mode);
extern NSRunLoopMode const NSDefaultRunLoopMode NS_SWIFT_NAME(RunLoop.Mode.default);
extern NSRunLoopMode const NSRunLoopCommonModes NS_SWIFT_NAME(RunLoop.Mode.common);
extern NSRunLoopMode const NSModalPanelRunLoopMode NS_SWIFT_NAME(RunLoop.Mode.modalPanel);
extern NSRunLoopMode const NSEventTrackingRunLoopMode NS_SWIFT_NAME(RunLoop.Mode.eventTracking);
@class NSTimer;
NS_SWIFT_NAME(RunLoop)
@interface NSRunLoop : NSObject
@property (class, readonly, strong) NSRunLoop *currentRunLoop;
@property (class, readonly, strong) NSRunLoop *mainRunLoop;
@property (nullable, readonly, copy) NSRunLoopMode currentMode;
- (void)addTimer:(NSTimer *)timer forMode:(NSRunLoopMode)mode;
- (nullable NSDate *)limitDateForMode:(NSRunLoopMode)mode;
- (void)acceptInputForMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limitDate;
- (void)run;
- (void)runUntilDate:(NSDate *)limitDate;
- (BOOL)runMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limitDate;
- (void)performInModes:(NSArray<NSRunLoopMode> *)modes block:(void (^)(void))block;
- (void)performBlock:(void (^)(void))block;
- (void)performSelector:(SEL)aSelector target:(id)target argument:(nullable id)arg order:(NSUInteger)order
                  modes:(NSArray<NSRunLoopMode> *)modes;
@end
NS_SWIFT_NAME(Timer)
@interface NSTimer : NSObject
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget selector:(SEL)aSelector
                          userInfo:(nullable id)userInfo repeats:(BOOL)yesOrNo;
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget selector:(SEL)aSelector
                                   userInfo:(nullable id)userInfo repeats:(BOOL)yesOrNo;
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer *timer))block;
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats
                                      block:(void (^)(NSTimer *timer))block;
- (instancetype)initWithFireDate:(NSDate *)date interval:(NSTimeInterval)interval repeats:(BOOL)repeats
                           block:(void (^)(NSTimer *timer))block;
- (instancetype)initWithFireDate:(NSDate *)date interval:(NSTimeInterval)ti target:(id)t selector:(SEL)s
                        userInfo:(nullable id)ui repeats:(BOOL)rep;
- (void)fire;
@property (copy) NSDate *fireDate;
@property (readonly) NSTimeInterval timeInterval;
@property NSTimeInterval tolerance;
- (void)invalidate;
@property (readonly, getter=isValid) BOOL valid;
@property (nullable, readonly, retain) id userInfo;
@end
typedef NS_OPTIONS(NSUInteger, NSKeyValueObservingOptions) {
    NSKeyValueObservingOptionNew NS_SWIFT_NAME(new) = 0x01,
    NSKeyValueObservingOptionOld NS_SWIFT_NAME(old) = 0x02,
    NSKeyValueObservingOptionInitial NS_SWIFT_NAME(initial) = 0x04,
    NSKeyValueObservingOptionPrior NS_SWIFT_NAME(prior) = 0x08
};

@interface NSObject (NSComparisonMethods)
- (BOOL)isEqualTo:(nullable id)object;
- (BOOL)isLessThanOrEqualTo:(nullable id)object;
- (BOOL)isLessThan:(nullable id)object;
- (BOOL)isGreaterThanOrEqualTo:(nullable id)object;
- (BOOL)isGreaterThan:(nullable id)object;
- (BOOL)isNotEqualTo:(nullable id)object;
- (BOOL)doesContain:(id)object;
- (BOOL)isLike:(NSString *)object;
- (BOOL)isCaseInsensitiveLike:(NSString *)object;
@end

typedef NSString *NSKeyValueChangeKey NS_TYPED_ENUM;
extern NSKeyValueChangeKey const NSKeyValueChangeKindKey NS_SWIFT_NAME(NSKeyValueChangeKey.kindKey);
extern NSKeyValueChangeKey const NSKeyValueChangeNewKey NS_SWIFT_NAME(NSKeyValueChangeKey.newKey);
extern NSKeyValueChangeKey const NSKeyValueChangeOldKey NS_SWIFT_NAME(NSKeyValueChangeKey.oldKey);
extern NSKeyValueChangeKey const NSKeyValueChangeIndexesKey NS_SWIFT_NAME(NSKeyValueChangeKey.indexesKey);
extern NSKeyValueChangeKey const NSKeyValueChangeNotificationIsPriorKey NS_SWIFT_NAME(NSKeyValueChangeKey.notificationIsPriorKey);
typedef NS_ENUM(NSUInteger, NSKeyValueChange) {
    NSKeyValueChangeSetting = 1, NSKeyValueChangeInsertion = 2, NSKeyValueChangeRemoval = 3,
    NSKeyValueChangeReplacement = 4
};

extern NSNotificationName const NSUndoManagerCheckpointNotification, NSUndoManagerWillUndoChangeNotification,
    NSUndoManagerWillRedoChangeNotification, NSUndoManagerDidUndoChangeNotification,
    NSUndoManagerDidRedoChangeNotification, NSUndoManagerDidOpenUndoGroupNotification,
    NSUndoManagerWillCloseUndoGroupNotification, NSUndoManagerDidCloseUndoGroupNotification;
NS_SWIFT_NAME(UndoManager)
@interface NSUndoManager : NSObject
- (void)beginUndoGrouping;
- (void)endUndoGrouping;
@property (readonly) NSInteger groupingLevel;
- (void)disableUndoRegistration;
- (void)enableUndoRegistration;
@property (readonly, getter=isUndoRegistrationEnabled) BOOL undoRegistrationEnabled;
@property BOOL groupsByEvent;
@property NSUInteger levelsOfUndo;
@property (copy) NSArray<NSRunLoopMode> *runLoopModes;
- (void)undo;
- (void)redo;
- (void)undoNestedGroup;
@property (readonly) BOOL canUndo;
@property (readonly) BOOL canRedo;
@property (readonly, getter=isUndoing) BOOL undoing;
@property (readonly, getter=isRedoing) BOOL redoing;
- (void)removeAllActions;
- (void)removeAllActionsWithTarget:(id)target;
- (void)registerUndoWithTarget:(id)target selector:(SEL)selector object:(nullable id)anObject;
- (void)registerUndoWithTarget:(id)target handler:(void (^)(id target))undoHandler NS_REFINED_FOR_SWIFT;
- (void)setActionName:(NSString *)actionName;
@property (readonly, copy) NSString *undoActionName;
@property (readonly, copy) NSString *redoActionName;
@property (readonly, copy) NSString *undoMenuItemTitle;
@property (readonly, copy) NSString *redoMenuItemTitle;
@end

@interface NSObject (NSDelayedPerforming)
- (void)performSelector:(SEL)aSelector withObject:(nullable id)anArgument afterDelay:(NSTimeInterval)delay
                inModes:(NSArray<NSRunLoopMode> *)modes;
- (void)performSelector:(SEL)aSelector withObject:(nullable id)anArgument afterDelay:(NSTimeInterval)delay;
+ (void)cancelPreviousPerformRequestsWithTarget:(id)aTarget selector:(SEL)aSelector object:(nullable id)anArgument;
+ (void)cancelPreviousPerformRequestsWithTarget:(id)aTarget;
@end
@interface NSObject (NSThreadPerformAdditions)
- (void)performSelectorOnMainThread:(SEL)aSelector withObject:(nullable id)arg waitUntilDone:(BOOL)wait
                              modes:(nullable NSArray<NSString *> *)array;
- (void)performSelectorOnMainThread:(SEL)aSelector withObject:(nullable id)arg waitUntilDone:(BOOL)wait;
- (void)performSelectorInBackground:(SEL)aSelector withObject:(nullable id)arg;
@end
@interface NSObject (NSKeyValueCoding)
- (nullable id)valueForKey:(NSString *)key;
- (void)setValue:(nullable id)value forKey:(NSString *)key;
- (nullable id)valueForKeyPath:(NSString *)keyPath;
- (void)setValue:(nullable id)value forKeyPath:(NSString *)keyPath;
- (nullable id)valueForUndefinedKey:(NSString *)key;
- (void)setValue:(nullable id)value forUndefinedKey:(NSString *)key;
@end
@interface NSObject (NSKeyValueObserving)
- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object
                        change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change context:(nullable void *)context;
@end
@interface NSObject (NSKeyValueObserverRegistration)
- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options
            context:(nullable void *)context;
- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath context:(nullable void *)context;
- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath;
@end
@interface NSObject (NSKeyValueObserverNotification)
- (void)willChangeValueForKey:(NSString *)key;
- (void)didChangeValueForKey:(NSString *)key;
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key;
@end

typedef NSString *NSURLResourceKey NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(URLResourceKey);
extern NSURLResourceKey const NSURLNameKey NS_SWIFT_NAME(URLResourceKey.nameKey);
extern NSURLResourceKey const NSURLLocalizedNameKey NS_SWIFT_NAME(URLResourceKey.localizedNameKey);
extern NSURLResourceKey const NSURLIsRegularFileKey NS_SWIFT_NAME(URLResourceKey.isRegularFileKey);
extern NSURLResourceKey const NSURLIsDirectoryKey NS_SWIFT_NAME(URLResourceKey.isDirectoryKey);
extern NSURLResourceKey const NSURLIsSymbolicLinkKey NS_SWIFT_NAME(URLResourceKey.isSymbolicLinkKey);
extern NSURLResourceKey const NSURLIsVolumeKey NS_SWIFT_NAME(URLResourceKey.isVolumeKey);
extern NSURLResourceKey const NSURLIsPackageKey NS_SWIFT_NAME(URLResourceKey.isPackageKey);
extern NSURLResourceKey const NSURLIsApplicationKey NS_SWIFT_NAME(URLResourceKey.isApplicationKey);
extern NSURLResourceKey const NSURLIsHiddenKey NS_SWIFT_NAME(URLResourceKey.isHiddenKey);
extern NSURLResourceKey const NSURLIsReadableKey NS_SWIFT_NAME(URLResourceKey.isReadableKey);
extern NSURLResourceKey const NSURLIsWritableKey NS_SWIFT_NAME(URLResourceKey.isWritableKey);
extern NSURLResourceKey const NSURLIsExecutableKey NS_SWIFT_NAME(URLResourceKey.isExecutableKey);
extern NSURLResourceKey const NSURLCreationDateKey NS_SWIFT_NAME(URLResourceKey.creationDateKey);
extern NSURLResourceKey const NSURLContentAccessDateKey NS_SWIFT_NAME(URLResourceKey.contentAccessDateKey);
extern NSURLResourceKey const NSURLContentModificationDateKey NS_SWIFT_NAME(URLResourceKey.contentModificationDateKey);
extern NSURLResourceKey const NSURLAttributeModificationDateKey NS_SWIFT_NAME(URLResourceKey.attributeModificationDateKey);
extern NSURLResourceKey const NSURLFileSizeKey NS_SWIFT_NAME(URLResourceKey.fileSizeKey);
extern NSURLResourceKey const NSURLFileAllocatedSizeKey NS_SWIFT_NAME(URLResourceKey.fileAllocatedSizeKey);
extern NSURLResourceKey const NSURLTotalFileSizeKey NS_SWIFT_NAME(URLResourceKey.totalFileSizeKey);
extern NSURLResourceKey const NSURLTotalFileAllocatedSizeKey NS_SWIFT_NAME(URLResourceKey.totalFileAllocatedSizeKey);
extern NSURLResourceKey const NSURLContentTypeKey NS_SWIFT_NAME(URLResourceKey.contentTypeKey);
extern NSURLResourceKey const NSURLIsExcludedFromBackupKey NS_SWIFT_NAME(URLResourceKey.isExcludedFromBackupKey);
extern NSURLResourceKey const NSURLPathKey NS_SWIFT_NAME(URLResourceKey.pathKey);
extern NSURLResourceKey const NSURLParentDirectoryURLKey NS_SWIFT_NAME(URLResourceKey.parentDirectoryURLKey);
extern NSURLResourceKey const NSURLFileResourceTypeKey NS_SWIFT_NAME(URLResourceKey.fileResourceTypeKey);
extern NSURLResourceKey const NSURLTypeIdentifierKey NS_SWIFT_NAME(URLResourceKey.typeIdentifierKey);
extern NSURLResourceKey const NSURLLinkCountKey NS_SWIFT_NAME(URLResourceKey.linkCountKey);
extern NSURLResourceKey const NSURLFileSecurityKey NS_SWIFT_NAME(URLResourceKey.fileSecurityKey);
extern NSURLResourceKey const NSURLQuarantinePropertiesKey NS_SWIFT_NAME(URLResourceKey.quarantinePropertiesKey);
extern NSURLResourceKey const NSURLVolumeAvailableCapacityKey NS_SWIFT_NAME(URLResourceKey.volumeAvailableCapacityKey);
extern NSURLResourceKey const NSURLVolumeTotalCapacityKey NS_SWIFT_NAME(URLResourceKey.volumeTotalCapacityKey);
extern NSURLResourceKey const NSURLIsUbiquitousItemKey NS_SWIFT_NAME(URLResourceKey.isUbiquitousItemKey);
extern NSURLResourceKey const NSURLFileProtectionKey NS_SWIFT_NAME(URLResourceKey.fileProtectionKey);
extern NSURLResourceKey const NSURLAddedToDirectoryDateKey NS_SWIFT_NAME(URLResourceKey.addedToDirectoryDateKey);

NS_SWIFT_NAME(Host)
@interface NSHost : NSObject
+ (instancetype)currentHost;
+ (nullable instancetype)hostWithName:(nullable NSString *)name;
+ (nullable instancetype)hostWithAddress:(NSString *)address;
- (BOOL)isEqualToHost:(NSHost *)aHost;
@property (nullable, readonly, copy) NSString *name;
@property (readonly, copy) NSArray<NSString *> *names;
@property (nullable, readonly, copy) NSString *address;
@property (readonly, copy) NSArray<NSString *> *addresses;
@property (nullable, readonly, copy) NSString *localizedName;
@end

@protocol NSLocking
- (void)lock;
- (void)unlock;
@end
@interface NSLock : NSObject <NSLocking>
- (BOOL)tryLock;
@property (copy) NSString *name;
@end
@interface NSRecursiveLock : NSObject <NSLocking>
- (BOOL)tryLock;
@property (copy) NSString *name;
@end
@interface NSCondition : NSObject <NSLocking>
- (void)wait;
- (BOOL)waitUntilDate:(NSDate *)limit;
- (void)signal;
- (void)broadcast;
@property (copy) NSString *name;
@end

NS_SWIFT_NAME(Thread)
@interface NSThread : NSObject
@property (class, readonly, strong) NSThread *currentThread;
@property (class, readonly, strong) NSThread *mainThread;
@property (class, readonly) BOOL isMainThread;
+ (void)sleepForTimeInterval:(NSTimeInterval)seconds;
+ (void)sleepUntilDate:(NSDate *)date;
+ (void)detachNewThreadWithBlock:(void (^)(void))block;
+ (void)detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)argument;
@property (readonly, strong) NSMutableDictionary *threadDictionary;
@property (copy) NSString *name;
@property (readonly) BOOL isMainThread;
@end

@interface NSUUID : NSObject <NSCopying>
+ (instancetype)UUID;
- (instancetype)initWithUUIDString:(NSString *)string;
@property (readonly, copy) NSString *UUIDString;
@end

void NSLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void NSLogv(NSString *format, va_list args) NS_FORMAT_FUNCTION(1, 0);
NSString *NSStringFromClass(Class cls);
NSString *NSStringFromSelector(SEL sel);
Class NSClassFromString(NSString *name);
SEL NSSelectorFromString(NSString *name);
#pragma clang assume_nonnull end
#endif
