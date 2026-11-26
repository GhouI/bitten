/* NSItemProvider: representations registered by type identifier (data,
 * files or objects), loaded asynchronously on a global queue. Type
 * conformance is by identifier, with public.data and public.item covering
 * everything. */
#import "FoundationInternal.h"

@interface _BNItemRep : NSObject {
  @public
    NSString *_type;
    NSProgress * (^_data)(void (^)(NSData *, NSError *));
    NSProgress * (^_file)(void (^)(NSURL *, BOOL, NSError *));
}
@end
@implementation _BNItemRep
@end

static BOOL conforms(NSString *have, NSString *want) {
    if ([have isEqualToString:want]) return YES;
    if ([want isEqualToString:@"public.data"] || [want isEqualToString:@"public.item"] ||
        [want isEqualToString:@"public.content"])
        return YES;
    if ([want isEqualToString:@"public.image"])
        return [have hasPrefix:@"public.png"] || [have hasPrefix:@"public.jpeg"] || [have hasPrefix:@"public.tiff"] ||
               [have hasPrefix:@"public.heic"] || [have isEqualToString:@"com.compuserve.gif"];
    if ([want isEqualToString:@"public.text"] || [want isEqualToString:@"public.plain-text"])
        return [have hasPrefix:@"public.utf8-plain-text"] || [have hasPrefix:@"public.plain-text"];
    return NO;
}

@implementation NSItemProvider {
    NSMutableArray<_BNItemRep *> *_reps;
    NSString *_suggestedName;
}
- (instancetype)init {
    if ((self = [super init])) _reps = [NSMutableArray array];
    return self;
}
- (id)copyWithZone:(NSZone *)zone {
    NSItemProvider *c = [NSItemProvider new];
    c->_reps = [_reps mutableCopy];
    c->_suggestedName = _suggestedName;
    return c;
}
- (instancetype)initWithObject:(id<NSItemProviderWriting>)object {
    if ((self = [self init])) [self registerObject:object visibility:NSItemProviderRepresentationVisibilityAll];
    return self;
}
- (instancetype)initWithContentsOfURL:(NSURL *)url {
    if (!url) return nil;
    if ((self = [self init])) {
        NSString *ext = url.pathExtension.lowercaseString;
        NSString *type = [ext isEqualToString:@"png"] ? @"public.png"
                         : [ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"] ? @"public.jpeg"
                         : [ext isEqualToString:@"txt"] ? @"public.utf8-plain-text"
                                                        : @"public.data";
        NSURL *u = url;
        [self registerFileRepresentationForTypeIdentifier:type fileOptions:0
                                               visibility:NSItemProviderRepresentationVisibilityAll
                                              loadHandler:^NSProgress *(void (^done)(NSURL *, BOOL, NSError *)) {
                                                  done(u, NO, nil);
                                                  return nil;
                                              }];
        _suggestedName = url.lastPathComponent.stringByDeletingPathExtension;
    }
    return self;
}
- (instancetype)initWithItem:(id)item typeIdentifier:(NSString *)typeIdentifier {
    if ((self = [self init]) && item && typeIdentifier) {
        id it = item;
        [self registerDataRepresentationForTypeIdentifier:typeIdentifier
                                               visibility:NSItemProviderRepresentationVisibilityAll
                                              loadHandler:^NSProgress *(void (^done)(NSData *, NSError *)) {
                                                  NSData *d = [it isKindOfClass:[NSData class]] ? it
                                                              : [it isKindOfClass:[NSString class]]
                                                                  ? [(NSString *)it dataUsingEncoding:NSUTF8StringEncoding]
                                                                  : nil;
                                                  done(d, nil);
                                                  return nil;
                                              }];
    }
    return self;
}
- (void)registerDataRepresentationForTypeIdentifier:(NSString *)type visibility:(NSItemProviderRepresentationVisibility)v
                                        loadHandler:(NSProgress * (^)(void (^)(NSData *, NSError *)))handler {
    _BNItemRep *r = [_BNItemRep new];
    r->_type = [type copy];
    r->_data = [handler copy];
    [_reps addObject:r];
}
- (void)registerFileRepresentationForTypeIdentifier:(NSString *)type fileOptions:(NSItemProviderFileOptions)options
                                         visibility:(NSItemProviderRepresentationVisibility)v
                                        loadHandler:(NSProgress * (^)(void (^)(NSURL *, BOOL, NSError *)))handler {
    _BNItemRep *r = [_BNItemRep new];
    r->_type = [type copy];
    r->_file = [handler copy];
    [_reps addObject:r];
}
- (void)registerObject:(id<NSItemProviderWriting>)object visibility:(NSItemProviderRepresentationVisibility)v {
    id o = object;
    NSArray *types = [[o class] respondsToSelector:@selector(writableTypeIdentifiersForItemProvider)]
                         ? [[o class] writableTypeIdentifiersForItemProvider]
                         : ([o isKindOfClass:[NSString class]] ? @[ @"public.utf8-plain-text" ] : @[]);
    for (NSString *t in types) {
        [self registerDataRepresentationForTypeIdentifier:t visibility:v
                                              loadHandler:^NSProgress *(void (^done)(NSData *, NSError *)) {
                                                  if ([o isKindOfClass:[NSString class]]) {
                                                      done([(NSString *)o dataUsingEncoding:NSUTF8StringEncoding], nil);
                                                      return nil;
                                                  }
                                                  return [o loadDataWithTypeIdentifier:t forItemProviderCompletionHandler:done];
                                              }];
    }
}
- (NSArray<NSString *> *)registeredTypeIdentifiers {
    NSMutableArray *a = [NSMutableArray array];
    for (_BNItemRep *r in _reps) if (![a containsObject:r->_type]) [a addObject:r->_type];
    return a;
}
- (_BNItemRep *)_rep:(NSString *)type {
    for (_BNItemRep *r in _reps) if (conforms(r->_type, type)) return r;
    return nil;
}
- (BOOL)hasItemConformingToTypeIdentifier:(NSString *)type { return [self _rep:type] != nil; }
- (BOOL)hasRepresentationConformingToTypeIdentifier:(NSString *)type fileOptions:(NSItemProviderFileOptions)o {
    return [self _rep:type] != nil;
}
static NSError *unavailable(NSString *type) {
    return [NSError errorWithDomain:@"NSItemProviderErrorDomain" code:-1000
                           userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"No %@ representation", type]}];
}
- (NSProgress *)loadDataRepresentationForTypeIdentifier:(NSString *)type
                                      completionHandler:(void (^)(NSData *, NSError *))done {
    _BNItemRep *r = [self _rep:type];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (!r) done(nil, unavailable(type));
        else if (r->_data) r->_data(done);
        else r->_file(^(NSURL *url, BOOL coordinated, NSError *error) {
            done(url ? [NSData dataWithContentsOfFile:url.path] : nil, error);
        });
    });
    return nil;
}
- (NSProgress *)loadFileRepresentationForTypeIdentifier:(NSString *)type
                                      completionHandler:(void (^)(NSURL *, NSError *))done {
    _BNItemRep *r = [self _rep:type];
    NSString *name = _suggestedName;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (!r) {
            done(nil, unavailable(type));
        } else if (r->_file) {
            r->_file(^(NSURL *url, BOOL coordinated, NSError *error) { done(url, error); });
        } else {
            /* A data representation: written to a temporary file for the call. */
            r->_data(^(NSData *data, NSError *error) {
                if (!data) {
                    done(nil, error ?: unavailable(type));
                    return;
                }
                NSString *path = [NSTemporaryDirectory()
                    stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", name ?: @"item", [NSUUID UUID].UUIDString]];
                [data writeToFile:path atomically:YES];
                NSURL *u = [NSURL fileURLWithPath:path];
                done(u, nil);
                [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            });
        }
    });
    return nil;
}
- (NSProgress *)loadInPlaceFileRepresentationForTypeIdentifier:(NSString *)type
                                            completionHandler:(void (^)(NSURL *, BOOL, NSError *))done {
    return [self loadFileRepresentationForTypeIdentifier:type completionHandler:^(NSURL *url, NSError *error) {
        done(url, NO, error);
    }];
}
- (BOOL)canLoadObjectOfClass:(Class)cls {
    if (cls == [NSString class]) return [self _rep:@"public.utf8-plain-text"] != nil;
    if ([cls respondsToSelector:@selector(readableTypeIdentifiersForItemProvider)])
        for (NSString *t in [cls readableTypeIdentifiersForItemProvider])
            if ([self _rep:t]) return YES;
    return NO;
}
- (NSProgress *)loadObjectOfClass:(Class)cls completionHandler:(void (^)(id, NSError *))done {
    NSArray *types = cls == [NSString class] ? @[ @"public.utf8-plain-text" ]
                     : [cls respondsToSelector:@selector(readableTypeIdentifiersForItemProvider)]
                         ? [cls readableTypeIdentifiersForItemProvider]
                         : @[];
    for (NSString *t in types) {
        if (![self _rep:t]) continue;
        [self loadDataRepresentationForTypeIdentifier:t completionHandler:^(NSData *data, NSError *error) {
            if (!data) {
                done(nil, error);
                return;
            }
            if (cls == [NSString class]) {
                done([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], nil);
                return;
            }
            NSError *e = nil;
            id o = [cls objectWithItemProviderData:data typeIdentifier:t error:&e];
            done(o, e);
        }];
        return nil;
    }
    dispatch_async(dispatch_get_global_queue(0, 0), ^{ done(nil, unavailable(NSStringFromClass(cls))); });
    return nil;
}
- (void)loadItemForTypeIdentifier:(NSString *)type options:(NSDictionary *)options
                completionHandler:(void (^)(id, NSError *))done {
    if (!done) return;
    [self loadDataRepresentationForTypeIdentifier:type completionHandler:^(NSData *data, NSError *error) {
        done(data, error);
    }];
}
- (NSString *)suggestedName { return _suggestedName; }
- (void)setSuggestedName:(NSString *)n { _suggestedName = [n copy]; }
@end
