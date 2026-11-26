/* bitten SDK: the TLS protocol objects of Security.framework as Swift sees
 * them (sec_protocol_options_t, sec_protocol_metadata_t), for
 * Network.framework's NWProtocolTLS. They are Objective-C objects conforming
 * to OS_sec_protocol_*; C code sees opaque pointers. bitten has no TLS
 * implementation yet, so no such object is ever created. */
#ifndef BITTEN_SEC_PROTOCOL_OBJECT_H
#define BITTEN_SEC_PROTOCOL_OBJECT_H
#if __OBJC__
#import <objc/NSObject.h>
@protocol OS_sec_protocol_options <NSObject> @end
@protocol OS_sec_protocol_metadata <NSObject> @end
typedef NSObject<OS_sec_protocol_options> *sec_protocol_options_t;
typedef NSObject<OS_sec_protocol_metadata> *sec_protocol_metadata_t;
#else
typedef struct sec_protocol_options_s *sec_protocol_options_t;
typedef struct sec_protocol_metadata_s *sec_protocol_metadata_t;
#endif
#endif
