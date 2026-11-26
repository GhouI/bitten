/* bitten SDK: dispatch objects as Swift sees them. Dispatch objects are
 * Objective-C objects whose classes are named OS_dispatch_<type> (see
 * src/frameworks/dispatch); Swift imports them under their Swift names
 * (DispatchQueue, DispatchSource...) and mangles them by their Objective-C
 * names. Sources are also protocols (DispatchSourceTimer...), as in Apple's
 * headers. Only the Dispatch Clang module includes this file, for the
 * Swift overlay (overlays/Dispatch); C and Objective-C code in bitten uses
 * <dispatch/dispatch.h>, where dispatch objects are plain pointers. */
#ifndef BITTEN_DISPATCH_SWIFT_H
#define BITTEN_DISPATCH_SWIFT_H
#if __OBJC__
#import <objc/NSObject.h>

#pragma clang assume_nonnull begin
/* Dispatch objects come from their factory functions (below), never from
 * -init, which Swift does not see, as in Apple's <os/object.h>. */
__attribute__((swift_name("DispatchObject"))) @interface OS_dispatch_object : NSObject
- (instancetype)init __attribute__((availability(swift, unavailable, message="Unavailable in Swift")));
@end
__attribute__((swift_name("DispatchQueue"))) @interface OS_dispatch_queue : OS_dispatch_object @end
__attribute__((swift_name("DispatchGroup"))) @interface OS_dispatch_group : OS_dispatch_object @end
__attribute__((swift_name("DispatchSemaphore"))) @interface OS_dispatch_semaphore : OS_dispatch_object @end
__attribute__((swift_name("__DispatchData"))) @interface OS_dispatch_data : OS_dispatch_object @end
__attribute__((swift_name("__OS_dispatch_queue_attr"))) @interface OS_dispatch_queue_attr : OS_dispatch_object @end

__attribute__((swift_name("DispatchSourceProtocol"))) @protocol OS_dispatch_source <NSObject> @end
__attribute__((swift_name("DispatchSourceTimer"))) @protocol OS_dispatch_source_timer <OS_dispatch_source> @end
__attribute__((swift_name("DispatchSourceRead"))) @protocol OS_dispatch_source_read <OS_dispatch_source> @end
__attribute__((swift_name("DispatchSourceWrite"))) @protocol OS_dispatch_source_write <OS_dispatch_source> @end
__attribute__((swift_name("DispatchSourceFileSystemObject"))) @protocol OS_dispatch_source_vnode <OS_dispatch_source> @end
__attribute__((swift_name("DispatchSourceSignal"))) @protocol OS_dispatch_source_signal <OS_dispatch_source> @end
__attribute__((swift_name("DispatchSourceProcess"))) @protocol OS_dispatch_source_proc <OS_dispatch_source> @end
__attribute__((swift_name("DispatchSourceUserDataAdd"))) @protocol OS_dispatch_source_data_add <OS_dispatch_source> @end
__attribute__((swift_name("DispatchSourceUserDataOr"))) @protocol OS_dispatch_source_data_or <OS_dispatch_source> @end

__attribute__((swift_name("DispatchSource")))
@interface OS_dispatch_source : OS_dispatch_object <OS_dispatch_source, OS_dispatch_source_timer,
    OS_dispatch_source_read, OS_dispatch_source_write, OS_dispatch_source_vnode,
    OS_dispatch_source_signal, OS_dispatch_source_proc, OS_dispatch_source_data_add,
    OS_dispatch_source_data_or>
@end

/* Initializers Swift code calls, as in Apple's headers. Each names the C
 * function by its symbol (asm label), so these declarations never meet the
 * ones in <dispatch/dispatch.h>. */
#define BITTEN_DISPATCH_SWIFT(sym, name) __asm__("_" #sym) __attribute__((swift_name(name)))
OS_dispatch_queue *_Nonnull __bitten_dispatch_queue_create_with_target(const char *_Nullable label,
    OS_dispatch_queue_attr *_Nullable attr, OS_dispatch_queue *_Nullable target)
    BITTEN_DISPATCH_SWIFT(dispatch_queue_create_with_target, "DispatchQueue.init(__label:attr:queue:)")
    __attribute__((ns_returns_retained));
OS_dispatch_group *_Nonnull __bitten_dispatch_group_create(void)
    BITTEN_DISPATCH_SWIFT(dispatch_group_create, "DispatchGroup.init()") __attribute__((ns_returns_retained));
void __bitten_dispatch_group_enter(OS_dispatch_group *group)
    BITTEN_DISPATCH_SWIFT(dispatch_group_enter, "DispatchGroup.enter(self:)");
void __bitten_dispatch_group_leave(OS_dispatch_group *group)
    BITTEN_DISPATCH_SWIFT(dispatch_group_leave, "DispatchGroup.leave(self:)");
OS_dispatch_semaphore *_Nonnull __bitten_dispatch_semaphore_create(long value)
    BITTEN_DISPATCH_SWIFT(dispatch_semaphore_create, "DispatchSemaphore.init(value:)") __attribute__((ns_returns_retained));
#undef BITTEN_DISPATCH_SWIFT
#pragma clang assume_nonnull end

#endif
#endif
