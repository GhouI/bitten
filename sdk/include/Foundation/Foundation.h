/* bitten SDK: the part of Foundation that bitten implements so far.
 * Written from the public API documentation; grows with the framework. */
#ifndef BITTEN_FOUNDATION_H
#define BITTEN_FOUNDATION_H
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <objc/runtime.h>
#include <CoreFoundation/CoreFoundation.h>

typedef long NSInteger;
typedef unsigned long NSUInteger;
typedef double CGFloat;
typedef double NSTimeInterval;
typedef unsigned short unichar;
typedef struct _NSZone NSZone;
#define NSIntegerMax 0x7fffffffffffffffL
#define NSUIntegerMax (~0UL)
enum { NSNotFound = NSIntegerMax };
typedef struct _NSRange {
    NSUInteger location, length;
} NSRange;
static inline NSRange NSMakeRange(NSUInteger loc, NSUInteger len) {
    NSRange r = {loc, len};
    return r;
}
static inline NSUInteger NSMaxRange(NSRange r) { return r.location + r.length; }
typedef enum : NSInteger { NSOrderedAscending = -1, NSOrderedSame = 0, NSOrderedDescending = 1 } NSComparisonResult;
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
typedef NSUInteger NSStringCompareOptions;
enum { NSCaseInsensitiveSearch = 1, NSLiteralSearch = 2, NSBackwardsSearch = 4 };

#define NS_FORMAT_FUNCTION(F, A) __attribute__((format(__NSString__, F, A)))
#define NS_REQUIRES_NIL_TERMINATION __attribute__((sentinel))

@class NSString, NSMutableString, NSArray, NSMutableArray, NSDictionary, NSMutableDictionary, NSData,
    NSNumber, NSError, NSEnumerator;

@protocol NSObject
- (BOOL)isEqual:(id)object;
- (NSUInteger)hash;
- (Class)class;
- (Class)superclass;
- (id)self;
- (BOOL)isKindOfClass:(Class)cls;
- (BOOL)isMemberOfClass:(Class)cls;
- (BOOL)respondsToSelector:(SEL)sel;
- (BOOL)conformsToProtocol:(Protocol *)protocol;
- (id)performSelector:(SEL)sel;
- (id)performSelector:(SEL)sel withObject:(id)object;
- (NSString *)description;
@optional
- (NSString *)debugDescription;
@end

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

__attribute__((objc_root_class))
@interface NSObject <NSObject> {
    Class isa;
}
+ (void)load;
+ (void)initialize;
+ (instancetype)alloc;
+ (instancetype)allocWithZone:(NSZone *)zone;
+ (instancetype)new;
+ (Class)class;
+ (Class)superclass;
+ (BOOL)isSubclassOfClass:(Class)cls;
+ (BOOL)instancesRespondToSelector:(SEL)sel;
+ (BOOL)conformsToProtocol:(Protocol *)protocol;
+ (BOOL)resolveInstanceMethod:(SEL)sel;
+ (BOOL)resolveClassMethod:(SEL)sel;
+ (NSString *)description;
- (instancetype)init;
- (void)dealloc;
- (id)copy;
- (id)mutableCopy;
- (id)forwardingTargetForSelector:(SEL)sel;
- (void)doesNotRecognizeSelector:(SEL)sel;
- (IMP)methodForSelector:(SEL)sel;
@end

@interface NSString : NSObject <NSCopying, NSMutableCopying>
+ (instancetype)string;
+ (instancetype)stringWithUTF8String:(const char *)cString;
+ (instancetype)stringWithCString:(const char *)cString encoding:(NSStringEncoding)encoding;
+ (instancetype)stringWithString:(NSString *)string;
+ (instancetype)stringWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (instancetype)initWithUTF8String:(const char *)cString;
- (instancetype)initWithCString:(const char *)cString encoding:(NSStringEncoding)encoding;
- (instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)length encoding:(NSStringEncoding)encoding;
- (instancetype)initWithData:(NSData *)data encoding:(NSStringEncoding)encoding;
- (instancetype)initWithString:(NSString *)string;
- (instancetype)initWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (instancetype)initWithFormat:(NSString *)format arguments:(va_list)args NS_FORMAT_FUNCTION(1, 0);
- (instancetype)initWithCharacters:(const unichar *)characters length:(NSUInteger)length;
@property (readonly) NSUInteger length;
- (unichar)characterAtIndex:(NSUInteger)index;
- (void)getCharacters:(unichar *)buffer range:(NSRange)range;
@property (readonly) const char *UTF8String;
- (const char *)cStringUsingEncoding:(NSStringEncoding)encoding;
- (NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)encoding;
- (NSData *)dataUsingEncoding:(NSStringEncoding)encoding;
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

@interface NSDictionary<__covariant KeyType, __covariant ObjectType> : NSObject <NSCopying, NSMutableCopying, NSFastEnumeration>
+ (instancetype)dictionary;
+ (instancetype)dictionaryWithObject:(ObjectType)object forKey:(KeyType<NSCopying>)key;
+ (instancetype)dictionaryWithObjects:(const ObjectType[])objects forKeys:(const KeyType<NSCopying>[])keys count:(NSUInteger)count;
+ (instancetype)dictionaryWithDictionary:(NSDictionary<KeyType, ObjectType> *)dictionary;
- (instancetype)initWithObjects:(const ObjectType[])objects forKeys:(const KeyType<NSCopying>[])keys count:(NSUInteger)count;
- (instancetype)initWithDictionary:(NSDictionary<KeyType, ObjectType> *)dictionary;
@property (readonly) NSUInteger count;
- (ObjectType)objectForKey:(KeyType)key;
- (ObjectType)objectForKeyedSubscript:(KeyType)key;
@property (readonly, copy) NSArray<KeyType> *allKeys;
@property (readonly, copy) NSArray<ObjectType> *allValues;
- (BOOL)isEqualToDictionary:(NSDictionary<KeyType, ObjectType> *)other;
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(KeyType key, ObjectType obj, BOOL *stop))block;
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

void NSLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void NSLogv(NSString *format, va_list args) NS_FORMAT_FUNCTION(1, 0);
NSString *NSStringFromClass(Class cls);
NSString *NSStringFromSelector(SEL sel);
Class NSClassFromString(NSString *name);
SEL NSSelectorFromString(NSString *name);
#endif
