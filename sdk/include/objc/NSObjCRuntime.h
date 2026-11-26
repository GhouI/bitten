/* bitten SDK: <objc/NSObjCRuntime.h>, the integer types the Objective-C
 * headers share. */
#ifndef BITTEN_OBJC_NSOBJCRUNTIME_H
#define BITTEN_OBJC_NSOBJCRUNTIME_H
#include <objc/objc.h>
typedef long NSInteger;
typedef unsigned long NSUInteger;
#define NSIntegerMax 0x7fffffffffffffffL
#define NSIntegerMin (-NSIntegerMax - 1)
#define NSUIntegerMax (~0UL)

/* Enumerations as the Swift importer expects them: NS_ENUM becomes a Swift
 * enum, NS_OPTIONS an OptionSet struct (the difference is in the mangled
 * names of everything that mentions them). */
#define NS_ENUM(_type, _name) enum __attribute__((enum_extensibility(open))) _name : _type _name; \
    enum __attribute__((enum_extensibility(open))) _name : _type
#define NS_CLOSED_ENUM(_type, _name) enum __attribute__((enum_extensibility(closed))) _name : _type _name; \
    enum __attribute__((enum_extensibility(closed))) _name : _type
#define NS_OPTIONS(_type, _name) enum __attribute__((flag_enum, enum_extensibility(open))) _name : _type _name; \
    enum __attribute__((flag_enum, enum_extensibility(open))) _name : _type
#define NS_SWIFT_NAME(_name) __attribute__((swift_name(#_name)))
#define NS_NOESCAPE __attribute__((noescape))
#define NS_REFINED_FOR_SWIFT __attribute__((swift_private))
#endif
