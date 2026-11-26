/* NSHost: this machine's (or a named host's) names and addresses, from
 * gethostname and getaddrinfo. */
#import "FoundationInternal.h"
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>

@implementation NSHost {
    NSArray<NSString *> *_names;
    NSArray<NSString *> *_addresses;
}

static NSArray<NSString *> *addresses_of(const char *name) {
    NSMutableArray *out = [NSMutableArray array];
    struct addrinfo hints = {0}, *res = NULL;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(name, NULL, &hints, &res) != 0) return out;
    for (struct addrinfo *a = res; a; a = a->ai_next) {
        char buf[INET6_ADDRSTRLEN] = "";
        if (a->ai_family == AF_INET)
            inet_ntop(AF_INET, &((struct sockaddr_in *)a->ai_addr)->sin_addr, buf, sizeof buf);
        else if (a->ai_family == AF_INET6)
            inet_ntop(AF_INET6, &((struct sockaddr_in6 *)a->ai_addr)->sin6_addr, buf, sizeof buf);
        NSString *s = [NSString stringWithUTF8String:buf];
        if (s.length && ![out containsObject:s]) [out addObject:s];
    }
    freeaddrinfo(res);
    return out;
}

+ (instancetype)currentHost {
    static NSHost *current;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        char name[256] = "localhost";
        gethostname(name, sizeof name - 1);
        current = [NSHost new];
        NSString *n = [NSString stringWithUTF8String:name];
        current->_names = [n isEqualToString:@"localhost"] ? @[ n ] : @[ n, @"localhost" ];
        NSMutableArray *addrs = [addresses_of(name) mutableCopy];
        for (NSString *a in @[ @"127.0.0.1", @"::1" ])
            if (![addrs containsObject:a]) [addrs addObject:a];
        current->_addresses = addrs;
    });
    return current;
}
+ (instancetype)hostWithName:(NSString *)name {
    if (!name) return nil;
    NSArray *addrs = addresses_of(name.UTF8String);
    if (!addrs.count) return nil;
    NSHost *h = [NSHost new];
    h->_names = @[ name ];
    h->_addresses = addrs;
    return h;
}
+ (instancetype)hostWithAddress:(NSString *)address {
    if (!address) return nil;
    NSHost *h = [NSHost new];
    h->_addresses = @[ address ];
    char host[NI_MAXHOST] = "";
    struct addrinfo hints = {0}, *res = NULL;
    hints.ai_flags = AI_NUMERICHOST;
    if (getaddrinfo(address.UTF8String, NULL, &hints, &res) == 0 && res) {
        if (getnameinfo(res->ai_addr, res->ai_addrlen, host, sizeof host, NULL, 0, NI_NAMEREQD) == 0)
            h->_names = @[ [NSString stringWithUTF8String:host] ];
        freeaddrinfo(res);
    }
    if (!h->_names) h->_names = @[];
    return h;
}
- (NSString *)name { return _names.firstObject; }
- (NSArray<NSString *> *)names { return _names; }
- (NSString *)address { return _addresses.firstObject; }
- (NSArray<NSString *> *)addresses { return _addresses; }
- (NSString *)localizedName { return _names.firstObject; }
- (BOOL)isEqualToHost:(NSHost *)host {
    for (NSString *a in _addresses)
        if ([host.addresses containsObject:a]) return YES;
    return NO;
}
@end
