/* bitten SDK: XPC connections, listeners and interfaces. Included from
 * Foundation.h. */
#ifndef BITTEN_FOUNDATION_NSXPCCONNECTION_H
#define BITTEN_FOUNDATION_NSXPCCONNECTION_H

#pragma clang assume_nonnull begin

@class NSXPCInterface, NSXPCListener, NSXPCListenerEndpoint, NSXPCConnection;

enum {
    NSXPCConnectionInterrupted = 4097,
    NSXPCConnectionInvalid = 4099,
    NSXPCConnectionReplyInvalid = 4101,
    NSXPCConnectionCodeSigningRequirementFailure = 4102,
    NSXPCConnectionErrorMinimum = 4096,
    NSXPCConnectionErrorMaximum = 4224,
};

@protocol NSXPCProxyCreating
- (id)remoteObjectProxy;
- (id)remoteObjectProxyWithErrorHandler:(void (^)(NSError *error))handler;
@optional
- (id)synchronousRemoteObjectProxyWithErrorHandler:(void (^)(NSError *error))handler;
@end

typedef NS_OPTIONS(NSUInteger, NSXPCConnectionOptions) {
    NSXPCConnectionPrivileged = (1 << 12UL)
};

@interface NSXPCConnection : NSObject <NSXPCProxyCreating>
- (instancetype)initWithServiceName:(NSString *)serviceName;
@property (nullable, readonly, copy) NSString *serviceName;
- (instancetype)initWithMachServiceName:(NSString *)name options:(NSXPCConnectionOptions)options;
- (instancetype)initWithListenerEndpoint:(NSXPCListenerEndpoint *)endpoint;
@property (readonly, retain) NSXPCListenerEndpoint *endpoint;
@property (nullable, retain) NSXPCInterface *exportedInterface;
@property (nullable, retain) id exportedObject;
@property (nullable, retain) NSXPCInterface *remoteObjectInterface;
@property (readonly, retain) id remoteObjectProxy;
- (id)remoteObjectProxyWithErrorHandler:(void (^)(NSError *error))handler;
- (id)synchronousRemoteObjectProxyWithErrorHandler:(void (^)(NSError *error))handler;
@property (nullable, copy) void (^interruptionHandler)(void);
@property (nullable, copy) void (^invalidationHandler)(void);
- (void)resume;
- (void)suspend;
- (void)activate;
- (void)invalidate;
@property (readonly) int auditSessionIdentifier;
@property (readonly) pid_t processIdentifier;
@property (readonly) uid_t effectiveUserIdentifier;
@property (readonly) gid_t effectiveGroupIdentifier;
+ (nullable NSXPCConnection *)currentConnection;
- (void)scheduleSendBarrierBlock:(void (^)(void))block;
- (void)setCodeSigningRequirement:(NSString *)requirement;
@end

@protocol NSXPCListenerDelegate <NSObject>
@optional
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection;
@end

@interface NSXPCListener : NSObject
+ (NSXPCListener *)serviceListener;
+ (NSXPCListener *)anonymousListener;
- (instancetype)initWithMachServiceName:(NSString *)name;
@property (nullable, weak) id<NSXPCListenerDelegate> delegate;
@property (readonly, retain) NSXPCListenerEndpoint *endpoint;
- (void)resume;
- (void)suspend;
- (void)activate;
- (void)invalidate;
- (void)setConnectionCodeSigningRequirement:(NSString *)requirement;
@end

@interface NSXPCInterface : NSObject
+ (NSXPCInterface *)interfaceWithProtocol:(Protocol *)protocol;
@property (assign) Protocol *protocol;
- (void)setClasses:(NSSet<Class> *)classes forSelector:(SEL)sel argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply;
- (NSSet<Class> *)classesForSelector:(SEL)sel argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply;
- (void)setInterface:(NSXPCInterface *)ifc forSelector:(SEL)sel argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply;
- (nullable NSXPCInterface *)interfaceForSelector:(SEL)sel argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply;
@end

@interface NSXPCListenerEndpoint : NSObject
@end

#pragma clang assume_nonnull end
#endif
