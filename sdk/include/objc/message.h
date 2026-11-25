/* bitten SDK: <objc/message.h>. The messengers are declared with C
 * variadic prototypes; cast them to the method's real type to call them. */
#ifndef BITTEN_OBJC_MESSAGE_H
#define BITTEN_OBJC_MESSAGE_H
#include <objc/objc.h>

struct objc_super {
#ifdef __OBJC__
    __unsafe_unretained id receiver;
    __unsafe_unretained Class super_class;
#else
    id receiver;
    Class super_class;
#endif
};

__BEGIN_DECLS
id objc_msgSend(id self, SEL op, ...) OBJC_SWIFT_UNAVAILABLE("calls through the messenger are not typed");
id objc_msgSendSuper(struct objc_super *super, SEL op, ...)
    OBJC_SWIFT_UNAVAILABLE("calls through the messenger are not typed");
void objc_msgSend_stret(void) OBJC_SWIFT_UNAVAILABLE("calls through the messenger are not typed");
struct objc_method;
id method_invoke(id receiver, struct objc_method *m, ...)
    OBJC_SWIFT_UNAVAILABLE("calls through the messenger are not typed");
__END_DECLS
#endif
