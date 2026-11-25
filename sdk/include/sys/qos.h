/* bitten SDK: <sys/qos.h>, quality-of-service classes. */
#ifndef BITTEN_SYS_QOS_H
#define BITTEN_SYS_QOS_H
#include <sys/cdefs.h>

typedef enum : unsigned int {
    QOS_CLASS_USER_INTERACTIVE = 0x21,
    QOS_CLASS_USER_INITIATED = 0x19,
    QOS_CLASS_DEFAULT = 0x15,
    QOS_CLASS_UTILITY = 0x11,
    QOS_CLASS_BACKGROUND = 0x09,
    QOS_CLASS_UNSPECIFIED = 0x00,
} qos_class_t;
#define QOS_MIN_RELATIVE_PRIORITY (-15)

__BEGIN_DECLS
qos_class_t qos_class_self(void);
qos_class_t qos_class_main(void);
__END_DECLS
#endif
