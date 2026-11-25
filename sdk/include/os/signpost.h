/* bitten SDK: <os/signpost.h>. Signposts are accepted and dropped. */
#ifndef BITTEN_OS_SIGNPOST_H
#define BITTEN_OS_SIGNPOST_H
#include <os/log.h>
typedef uint64_t os_signpost_id_t;
#define OS_SIGNPOST_ID_NULL ((os_signpost_id_t)0)
#define OS_SIGNPOST_ID_INVALID ((os_signpost_id_t)~0)
#define OS_SIGNPOST_ID_EXCLUSIVE ((os_signpost_id_t)0xEEEEB0B5B2B2EEEE)
typedef enum : uint8_t {
    OS_SIGNPOST_EVENT = 0x00,
    OS_SIGNPOST_INTERVAL_BEGIN = 0x01,
    OS_SIGNPOST_INTERVAL_END = 0x02,
} os_signpost_type_t;
bool os_signpost_enabled(os_log_t log);
os_signpost_id_t os_signpost_id_generate(os_log_t log);
void _os_signpost_emit_with_name_impl(void *dso, os_log_t log, os_signpost_type_t type, os_signpost_id_t spid,
                                      const char *name, const char *format, uint8_t *buf, uint32_t size);
#endif
