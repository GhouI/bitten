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
#endif
