/* Shared by the Foundation implementation files. */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* An unrecoverable API misuse (the cases where macOS raises NSException). */
void BNRaise(const char *name, const char *format, ...) __attribute__((noreturn, format(printf, 2, 3)));
/* printf-style formatting with %@ support; returns malloc'd UTF-8. */
char *BNFormatUTF8(NSString *format, va_list args);
NSString *BNDescribe(id object);
CFStringEncoding BNCFEncoding(NSStringEncoding encoding);

static inline CFStringRef CFS(NSString *s) { return (__bridge CFStringRef)s; }
