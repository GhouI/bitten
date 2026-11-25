/* bitten SDK: <os/log.h>, unified logging. Written from the public
 * documentation; messages go to stderr (see src/libsystem/oslog.c). */
#ifndef BITTEN_OS_LOG_H
#define BITTEN_OS_LOG_H
#include <stdbool.h>
#include <stdint.h>
#include <os/object.h>

#pragma clang assume_nonnull begin
OS_OBJECT_DECL_SWIFT_CLASS(os_log, OSLog);

typedef enum : uint8_t {
    OS_LOG_TYPE_DEFAULT = 0x00,
    OS_LOG_TYPE_INFO = 0x01,
    OS_LOG_TYPE_DEBUG = 0x02,
    OS_LOG_TYPE_ERROR = 0x10,
    OS_LOG_TYPE_FAULT = 0x11,
} os_log_type_t;

extern struct os_log_s _os_log_default;
extern struct os_log_s _os_log_disabled;
#define OS_LOG_DEFAULT ((os_log_t)&_os_log_default)
#define OS_LOG_DISABLED ((os_log_t)&_os_log_disabled)

/* bitten: the default and disabled handles as objects, for Swift (which
 * cannot import the OS_LOG_DEFAULT macro). */
os_log_t _bitten_os_log_default(void);
os_log_t _bitten_os_log_disabled(void);
os_log_t os_log_create(const char *subsystem, const char *category);
bool os_log_type_enabled(os_log_t oslog, os_log_type_t type);
void _os_log_impl(void *dso, os_log_t log, os_log_type_t type, const char *format, uint8_t *buf, uint32_t size);
void _os_log_error_impl(void *dso, os_log_t log, os_log_type_t type, const char *format, uint8_t *buf, uint32_t size);
void _os_log_fault_impl(void *dso, os_log_t log, os_log_type_t type, const char *format, uint8_t *buf, uint32_t size);
void _os_log_debug_impl(void *dso, os_log_t log, os_log_type_t type, const char *format, uint8_t *buf, uint32_t size);
#pragma clang assume_nonnull end
#endif
