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
typedef CGPoint NSPoint;
typedef CGSize NSSize;
typedef CGRect NSRect;
typedef struct NSEdgeInsets { CGFloat top, left, bottom, right; } NSEdgeInsets;
static inline NSRect NSMakeRect(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { return CGRectMake(x, y, w, h); }
static inline NSPoint NSMakePoint(CGFloat x, CGFloat y) { return CGPointMake(x, y); }
static inline NSSize NSMakeSize(CGFloat w, CGFloat h) { return CGSizeMake(w, h); }
#define NSZeroRect CGRectZero
static inline BOOL NSPointInRect(NSPoint p, NSRect r) {
    return p.x >= r.origin.x && p.y >= r.origin.y && p.x < r.origin.x + r.size.width &&
           p.y < r.origin.y + r.size.height;
}
static inline BOOL NSEqualRects(NSRect a, NSRect b) {
    return a.origin.x == b.origin.x && a.origin.y == b.origin.y && a.size.width == b.size.width &&
           a.size.height == b.size.height;
}
#define NSZeroPoint CGPointZero
#define NSZeroSize CGSizeZero
typedef double NSTimeInterval;
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
    id __unsafe_unretained *itemsPtr;
    unsigned long *mutationsPtr;
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
extern NSString *const NSLocalizedDescriptionKey, *const NSLocalizedFailureReasonErrorKey,
    *const NSUnderlyingErrorKey, *const NSFilePathErrorKey;
enum {
    NSFileNoSuchFileError = 4, NSFileReadNoSuchFileError = 260, NSFileReadNoPermissionError = 257,
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
@interface NSPropertyListSerialization : NSObject
+ (BOOL)propertyList:(id)plist isValidForFormat:(NSPropertyListFormat)format;
+ (nullable NSData *)dataWithPropertyList:(id)plist format:(NSPropertyListFormat)format
                                  options:(NSPropertyListWriteOptions)opt error:(NSError **)error;
+ (nullable id)propertyListWithData:(NSData *)data options:(NSPropertyListReadOptions)opt
                             format:(nullable NSPropertyListFormat *)format error:(NSError **)error;
@end

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
@interface NSUserDefaults : NSObject
@property (class, readonly, strong) NSUserDefaults *standardUserDefaults;
+ (void)resetStandardUserDefaults;
- (instancetype)init;
- (nullable instancetype)initWithSuiteName:(nullable NSString *)suitename;
- (nullable id)objectForKey:(NSString *)defaultName;
- (void)setObject:(nullable id)value forKey:(NSString *)defaultName;
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
- (nullable NSURL *)URLForKey:(NSString *)defaultName;
- (void)setInteger:(NSInteger)value forKey:(NSString *)defaultName;
- (void)setFloat:(float)value forKey:(NSString *)defaultName;
- (void)setDouble:(double)value forKey:(NSString *)defaultName;
- (void)setBool:(BOOL)value forKey:(NSString *)defaultName;
- (void)setURL:(nullable NSURL *)url forKey:(NSString *)defaultName;
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

typedef NSString *NSNotificationName;
@interface NSNotification : NSObject <NSCopying>
+ (instancetype)notificationWithName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)userInfo;
@property (readonly, copy) NSNotificationName name;
@property (readonly, strong) id object;
@property (nullable, readonly, copy) NSDictionary *userInfo;
@end
@interface NSNotificationCenter : NSObject
@property (class, readonly, strong) NSNotificationCenter *defaultCenter;
- (void)addObserver:(id)observer selector:(SEL)selector name:(NSNotificationName)name object:(id)object;
- (id)addObserverForName:(NSNotificationName)name object:(id)object queue:(id)queue usingBlock:(void (^)(NSNotification *note))block;
- (void)removeObserver:(id)observer;
- (void)removeObserver:(id)observer name:(NSNotificationName)name object:(id)object;
- (void)postNotification:(NSNotification *)notification;
- (void)postNotificationName:(NSNotificationName)name object:(id)object;
- (void)postNotificationName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)userInfo;
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
