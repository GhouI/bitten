/* XPC connections within the process. There are no XPC services to reach
 * here: a connection to a named service never connects, so messages sent
 * through its proxies go to their error handlers (NSXPCConnectionInvalid)
 * and the connection is invalidated. A connection to an anonymous
 * listener's endpoint does connect: the listener's delegate is asked to
 * accept a connection for the other side, and from then on each side's
 * proxies send straight to the other side's exported object.
 *
 * A proxy is a small object that conforms to the remote interface's
 * protocol (Swift casts check that) and hands every message it does not
 * itself implement either to the peer's exported object or to a sink whose
 * catch-all method reports the error. XPC methods return void, so the
 * catch-all can ignore its arguments. */
#import <Foundation/Foundation.h>
#include <objc/runtime.h>
#include <unistd.h>

static NSError *xpc_error(NSInteger code) {
    NSString *msg = code == NSXPCConnectionInterrupted ? @"Couldn’t communicate with a helper application."
                                                       : @"The connection to the service was invalidated.";
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey : msg}];
}

@interface NSXPCConnection ()
- (void)_bn_failed;
- (id)_bn_peerObject;
- (NSXPCInterface *)_bn_remoteInterface;
- (void)_bn_setPeer:(NSXPCConnection *)peer;
@end

/* ---- interfaces ---- */

@implementation NSXPCInterface {
    Protocol *_protocol;
    NSMutableDictionary<NSString *, NSSet *> *_classes;
    NSMutableDictionary<NSString *, NSXPCInterface *> *_interfaces;
}
+ (NSXPCInterface *)interfaceWithProtocol:(Protocol *)p {
    NSXPCInterface *i = [self new];
    i->_protocol = p;
    return i;
}
- (instancetype)init {
    if ((self = [super init])) {
        _classes = [NSMutableDictionary dictionary];
        _interfaces = [NSMutableDictionary dictionary];
    }
    return self;
}
- (Protocol *)protocol { return _protocol; }
- (void)setProtocol:(Protocol *)p { _protocol = p; }
static NSString *slot(SEL s, NSUInteger arg, BOOL reply) {
    return [NSString stringWithFormat:@"%s/%lu/%d", sel_getName(s), (unsigned long)arg, reply];
}
- (void)setClasses:(NSSet<Class> *)c forSelector:(SEL)s argumentIndex:(NSUInteger)a ofReply:(BOOL)r {
    _classes[slot(s, a, r)] = [c copy];
}
- (NSSet<Class> *)classesForSelector:(SEL)s argumentIndex:(NSUInteger)a ofReply:(BOOL)r {
    return _classes[slot(s, a, r)] ?: [NSSet set];
}
- (void)setInterface:(NSXPCInterface *)i forSelector:(SEL)s argumentIndex:(NSUInteger)a ofReply:(BOOL)r {
    _interfaces[slot(s, a, r)] = i;
}
- (NSXPCInterface *)interfaceForSelector:(SEL)s argumentIndex:(NSUInteger)a ofReply:(BOOL)r {
    return _interfaces[slot(s, a, r)];
}
- (NSString *)description {
    return [NSString stringWithFormat:@"<NSXPCInterface: %p> Protocol: %s", (void *)self,
                                      _protocol ? protocol_getName(_protocol) : "(none)"];
}
@end

/* ---- proxies ---- */

/* Every message it gets reports the connection's failure. */
@interface BNXPCSink : NSObject {
@public
    void (^_errorHandler)(NSError *);
    __weak NSXPCConnection *_connection;
}
@end

static void sink_message(BNXPCSink *self, SEL _cmd) {
    void (^h)(NSError *) = self->_errorHandler;
    NSXPCConnection *c = self->_connection;
    if (h) dispatch_async(dispatch_get_global_queue(0, 0), ^{ h(xpc_error(NSXPCConnectionInvalid)); });
    [c _bn_failed];
}

@implementation BNXPCSink
+ (BOOL)resolveInstanceMethod:(SEL)sel {
    class_addMethod(self, sel, (IMP)sink_message, "v@:");
    return YES;
}
@end

@interface BNXPCProxy : NSObject <NSXPCProxyCreating> {
@public
    NSXPCConnection *_connection;
    void (^_errorHandler)(NSError *);
    Protocol *_protocol;
}
@end

@implementation BNXPCProxy
/* A subclass of the proxy that conforms to the interface's protocol. */
+ (Class)_bn_classFor:(Protocol *)p {
    if (!p) return self;
    NSString *name = [NSString stringWithFormat:@"BNXPCProxy_%s", protocol_getName(p)];
    @synchronized(self) {
        Class c = NSClassFromString(name);
        if (c) return c;
        c = objc_allocateClassPair(self, name.UTF8String, 0);
        if (!c) return self;
        class_addProtocol(c, p);
        objc_registerClassPair(c);
        return c;
    }
}
- (BOOL)conformsToProtocol:(Protocol *)p {
    return (_protocol && (p == _protocol || protocol_conformsToProtocol(_protocol, p))) || [super conformsToProtocol:p];
}
- (BOOL)respondsToSelector:(SEL)sel {
    if ([super respondsToSelector:sel]) return YES;
    if (!_protocol) return NO;
    for (int req = 0; req < 2; req++)
        if (protocol_getMethodDescription(_protocol, sel, req, YES).name) return YES;
    return NO;
}
- (id)forwardingTargetForSelector:(SEL)sel {
    id peer = [_connection _bn_peerObject];
    if (peer && [peer respondsToSelector:sel]) return peer;
    BNXPCSink *sink = [BNXPCSink new];
    sink->_errorHandler = _errorHandler;
    sink->_connection = _connection;
    return sink;
}
- (id)remoteObjectProxy { return [_connection remoteObjectProxy]; }
- (id)remoteObjectProxyWithErrorHandler:(void (^)(NSError *))h { return [_connection remoteObjectProxyWithErrorHandler:h]; }
- (id)synchronousRemoteObjectProxyWithErrorHandler:(void (^)(NSError *))h {
    return [_connection synchronousRemoteObjectProxyWithErrorHandler:h];
}
- (NSString *)description {
    return [NSString stringWithFormat:@"<NSXPCConnection remote proxy %p: %s>", (void *)self,
                                      _protocol ? protocol_getName(_protocol) : "(no interface)"];
}
@end

/* ---- endpoints and listeners ---- */

@interface NSXPCListenerEndpoint () {
@public
    __weak NSXPCListener *_listener;
}
@end
@implementation NSXPCListenerEndpoint
@end

@interface NSXPCListener ()
- (NSXPCConnection *)_bn_connect:(NSXPCConnection *)client;
@end

@implementation NSXPCListener {
    __weak id<NSXPCListenerDelegate> _delegate;
    NSXPCListenerEndpoint *_endpoint;
    NSString *_name;
    BOOL _resumed, _invalid, _service;
}
+ (NSXPCListener *)serviceListener {
    static NSXPCListener *l;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        l = [NSXPCListener new];
        l->_service = YES;
    });
    return l;
}
+ (NSXPCListener *)anonymousListener { return [self new]; }
- (instancetype)init {
    if ((self = [super init])) {
        _endpoint = [NSXPCListenerEndpoint new];
        _endpoint->_listener = self;
    }
    return self;
}
- (instancetype)initWithMachServiceName:(NSString *)name {
    if ((self = [self init])) _name = [name copy];
    return self;
}
- (id<NSXPCListenerDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSXPCListenerDelegate>)d { _delegate = d; }
- (NSXPCListenerEndpoint *)endpoint { return _endpoint; }
/* A service's listener runs forever, as in a real XPC service; no one
 * connects to it here. */
- (void)resume {
    _resumed = YES;
    if (_service) dispatch_main();
}
- (void)activate { [self resume]; }
- (void)suspend { _resumed = NO; }
- (void)invalidate { _invalid = YES; }
- (void)setConnectionCodeSigningRequirement:(NSString *)r {}
- (NSXPCConnection *)_bn_connect:(NSXPCConnection *)client {
    id<NSXPCListenerDelegate> d = _delegate;
    if (_invalid || !d) return nil;
    NSXPCConnection *server = [NSXPCConnection new];
    [server _bn_setPeer:client];
    if (![d respondsToSelector:@selector(listener:shouldAcceptNewConnection:)] || ![d listener:self shouldAcceptNewConnection:server])
        return nil;
    return server;
}
@end

/* ---- connections ---- */

static __thread __unsafe_unretained NSXPCConnection *current;

@implementation NSXPCConnection {
    NSString *_serviceName;
    NSXPCListenerEndpoint *_endpoint, *_connectTo;
    NSXPCInterface *_exportedInterface, *_remoteInterface;
    id _exportedObject;
    void (^_interruption)(void);
    void (^_invalidation)(void);
    __weak NSXPCConnection *_peer;
    NSXPCConnection *_server;   /* the accepting side, kept by the client */
    BOOL _resumed, _invalid;
}
- (instancetype)init {
    if ((self = [super init])) _endpoint = [NSXPCListenerEndpoint new];
    return self;
}
- (instancetype)initWithServiceName:(NSString *)name {
    if ((self = [self init])) _serviceName = [name copy];
    return self;
}
- (instancetype)initWithMachServiceName:(NSString *)name options:(NSXPCConnectionOptions)options {
    if ((self = [self init])) _serviceName = [name copy];
    return self;
}
- (instancetype)initWithListenerEndpoint:(NSXPCListenerEndpoint *)endpoint {
    if ((self = [self init])) _connectTo = endpoint;
    return self;
}
- (void)_bn_setPeer:(NSXPCConnection *)peer {
    _peer = peer;
    _resumed = YES;
}
- (NSString *)serviceName { return _serviceName; }
- (NSXPCListenerEndpoint *)endpoint { return _endpoint; }
- (NSXPCInterface *)exportedInterface { return _exportedInterface; }
- (void)setExportedInterface:(NSXPCInterface *)i { _exportedInterface = i; }
- (id)exportedObject { return _exportedObject; }
- (void)setExportedObject:(id)o { _exportedObject = o; }
- (NSXPCInterface *)remoteObjectInterface { return _remoteInterface; }
- (void)setRemoteObjectInterface:(NSXPCInterface *)i { _remoteInterface = i; }
- (NSXPCInterface *)_bn_remoteInterface { return _remoteInterface; }
- (void (^)(void))interruptionHandler { return _interruption; }
- (void)setInterruptionHandler:(void (^)(void))h { _interruption = [h copy]; }
- (void (^)(void))invalidationHandler { return _invalidation; }
- (void)setInvalidationHandler:(void (^)(void))h { _invalidation = [h copy]; }

- (id)_bn_proxy:(void (^)(NSError *))handler {
    Protocol *p = _remoteInterface.protocol;
    BNXPCProxy *proxy = [[BNXPCProxy _bn_classFor:p] new];
    proxy->_connection = self;
    proxy->_errorHandler = [handler copy];
    proxy->_protocol = p;
    return proxy;
}
- (id)remoteObjectProxy { return [self _bn_proxy:nil]; }
- (id)remoteObjectProxyWithErrorHandler:(void (^)(NSError *))h { return [self _bn_proxy:h]; }
- (id)synchronousRemoteObjectProxyWithErrorHandler:(void (^)(NSError *))h { return [self _bn_proxy:h]; }

/* The other side's exported object, if connected. */
- (id)_bn_peerObject {
    if (_invalid || !_resumed) return nil;
    NSXPCConnection *peer = _peer;
    if (!peer || peer->_invalid) return nil;
    current = peer;
    return peer->_exportedObject;
}

- (void)resume {
    if (_resumed || _invalid) return;
    _resumed = YES;
    if (_connectTo) {
        NSXPCListener *l = _connectTo->_listener;
        NSXPCConnection *server = [l _bn_connect:self];
        if (server) {
            _server = server;
            _peer = server;
        } else {
            [self _bn_failed];
        }
    }
}
- (void)activate { [self resume]; }
- (void)suspend { _resumed = NO; }
/* A message could not be delivered: the connection is done for. */
- (void)_bn_failed {
    if (_peer && !_peer->_invalid && !_invalid) return;
    [self invalidate];
}
- (void)invalidate {
    void (^h)(void);
    @synchronized(self) {
        if (_invalid) return;
        _invalid = YES;
        h = _invalidation;
        _invalidation = nil;
        _interruption = nil;
    }
    if (h) dispatch_async(dispatch_get_global_queue(0, 0), h);
    NSXPCConnection *peer = _peer;
    if (peer && !peer->_invalid) [peer invalidate];
    _server = nil;
}
- (int)auditSessionIdentifier { return 0; }
- (pid_t)processIdentifier { return _peer ? getpid() : 0; }
- (uid_t)effectiveUserIdentifier { return geteuid(); }
- (gid_t)effectiveGroupIdentifier { return getegid(); }
+ (NSXPCConnection *)currentConnection { return current; }
- (void)scheduleSendBarrierBlock:(void (^)(void))block { dispatch_async(dispatch_get_global_queue(0, 0), block); }
- (void)setCodeSigningRequirement:(NSString *)r {}
- (NSString *)description {
    return [NSString stringWithFormat:@"<NSXPCConnection: %p> connection to %@", (void *)self,
                                      _serviceName ?: (_connectTo ? @"anonymous listener" : @"(peer)")];
}
@end
