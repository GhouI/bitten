/* NSPasteboard: named pasteboards of items, each item data by type. The
 * general pasteboard is this process's own; when $BITTEN_CLIPBOARD names a
 * file, plain text written to it is also saved there and read back from it,
 * so a host can bridge it to a real clipboard. */
#import <AppKit/AppKit.h>
#include <stdlib.h>

NSPasteboardType const NSPasteboardTypeString = @"public.utf8-plain-text";
NSPasteboardType const NSPasteboardTypePNG = @"public.png";
NSPasteboardType const NSPasteboardTypeTIFF = @"public.tiff";
NSPasteboardType const NSPasteboardTypeFileURL = @"public.file-url";
NSPasteboardType const NSPasteboardTypeURL = @"public.url";
NSPasteboardType const NSPasteboardTypeRTF = @"public.rtf";
NSPasteboardType const NSPasteboardTypeRTFD = @"com.apple.flat-rtfd";
NSPasteboardType const NSPasteboardTypeHTML = @"public.html";
NSPasteboardType const NSPasteboardTypePDF = @"com.adobe.pdf";
NSPasteboardType const NSPasteboardTypeColor = @"com.apple.cocoa.pasteboard.color";
NSPasteboardType const NSPasteboardTypeFont = @"com.apple.cocoa.pasteboard.character-formatting";
NSPasteboardType const NSPasteboardTypeRuler = @"com.apple.cocoa.pasteboard.paragraph-formatting";
NSPasteboardType const NSPasteboardTypeSound = @"com.apple.cocoa.pasteboard.sound";
NSPasteboardType const NSPasteboardTypeTabularText = @"public.utf8-tab-separated-values-text";
NSPasteboardType const NSPasteboardTypeMultipleTextSelection = @"com.apple.cocoa.pasteboard.multiple-text-selection";
NSPasteboardType const NSPasteboardTypeFindPanelSearchOptions = @"com.apple.cocoa.pasteboard.find-panel-search-options";
NSPasteboardName const NSPasteboardNameGeneral = @"Apple CFPasteboard general";
NSPasteboardName const NSPasteboardNameFind = @"Apple CFPasteboard find";
NSPasteboardName const NSPasteboardNameFont = @"Apple CFPasteboard font";
NSPasteboardName const NSPasteboardNameRuler = @"Apple CFPasteboard ruler";
NSPasteboardName const NSPasteboardNameDrag = @"Apple CFPasteboard drag";

@implementation NSPasteboardItem {
  @public
    NSMutableDictionary<NSPasteboardType, id> *_values;
    NSMutableArray<NSPasteboardType> *_order;
}
- (instancetype)init {
    if ((self = [super init])) {
        _values = [NSMutableDictionary dictionary];
        _order = [NSMutableArray array];
    }
    return self;
}
- (NSArray<NSPasteboardType> *)types { return [_order copy]; }
- (NSPasteboardType)availableTypeFromArray:(NSArray<NSPasteboardType> *)types {
    for (NSPasteboardType t in types) if (_values[t]) return t;
    return nil;
}
- (BOOL)_set:(id)v type:(NSPasteboardType)t {
    if (!v || !t) return NO;
    if (!_values[t]) [_order addObject:t];
    _values[t] = v;
    return YES;
}
- (BOOL)setData:(NSData *)data forType:(NSPasteboardType)type { return [self _set:[data copy] type:type]; }
- (BOOL)setString:(NSString *)string forType:(NSPasteboardType)type { return [self _set:[string copy] type:type]; }
- (BOOL)setPropertyList:(id)plist forType:(NSPasteboardType)type { return [self _set:plist type:type]; }
- (NSData *)dataForType:(NSPasteboardType)type {
    id v = _values[type];
    if ([v isKindOfClass:[NSData class]]) return v;
    if ([v isKindOfClass:[NSString class]]) return [(NSString *)v dataUsingEncoding:NSUTF8StringEncoding];
    return nil;
}
- (NSString *)stringForType:(NSPasteboardType)type {
    id v = _values[type];
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSData class]]) return [[NSString alloc] initWithData:v encoding:NSUTF8StringEncoding];
    return nil;
}
- (id)propertyListForType:(NSPasteboardType)type { return _values[type]; }
- (NSArray<NSPasteboardType> *)writableTypesForPasteboard:(NSPasteboard *)pasteboard { return self.types; }
- (id)pasteboardPropertyListForType:(NSPasteboardType)type { return _values[type]; }
+ (NSArray<NSPasteboardType> *)readableTypesForPasteboard:(NSPasteboard *)pasteboard { return @[]; }
@end

static NSMutableDictionary<NSPasteboardName, NSPasteboard *> *boards;

@implementation NSPasteboard {
    NSString *_name;
    NSMutableArray<NSPasteboardItem *> *_items;
    NSInteger _changeCount;
}
+ (NSPasteboard *)pasteboardWithName:(NSPasteboardName)name {
    @synchronized(self) {
        if (!boards) boards = [NSMutableDictionary dictionary];
        NSPasteboard *pb = boards[name];
        if (!pb) {
            pb = [NSPasteboard new];
            pb->_name = [name copy];
            pb->_items = [NSMutableArray array];
            boards[name] = pb;
        }
        return pb;
    }
}
+ (NSPasteboard *)generalPasteboard { return [self pasteboardWithName:NSPasteboardNameGeneral]; }
+ (NSPasteboard *)pasteboardWithUniqueName { return [self pasteboardWithName:[NSUUID UUID].UUIDString]; }
- (NSPasteboardName)name { return _name; }
- (NSInteger)changeCount { return _changeCount; }
- (void)releaseGlobally {
    @synchronized([NSPasteboard class]) { [boards removeObjectForKey:_name]; }
}
- (BOOL)_isGeneral { return [_name isEqualToString:NSPasteboardNameGeneral]; }
/* The host's clipboard file, for the general pasteboard's text. */
- (NSString *)_clipboardPath {
    const char *p = getenv("BITTEN_CLIPBOARD");
    return [self _isGeneral] && p && *p ? @(p) : nil;
}
- (void)_syncOut {
    NSString *path = [self _clipboardPath];
    NSString *text = [_items.firstObject stringForType:NSPasteboardTypeString];
    if (path && text) [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}
- (void)_syncIn {
    NSString *path = [self _clipboardPath];
    if (!path) return;
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    if (!text || [text isEqualToString:[_items.firstObject stringForType:NSPasteboardTypeString]]) return;
    NSPasteboardItem *item = [NSPasteboardItem new];
    [item setString:text forType:NSPasteboardTypeString];
    _items = [NSMutableArray arrayWithObject:item];
    _changeCount++;
}
- (NSInteger)clearContents {
    [_items removeAllObjects];
    return ++_changeCount;
}
- (NSInteger)declareTypes:(NSArray<NSPasteboardType> *)types owner:(id)owner {
    [self clearContents];
    [_items addObject:[NSPasteboardItem new]];
    return _changeCount;
}
- (NSInteger)addTypes:(NSArray<NSPasteboardType> *)types owner:(id)owner {
    if (!_items.count) [_items addObject:[NSPasteboardItem new]];
    return _changeCount;
}
- (NSPasteboardItem *)_first {
    if (!_items.count) [_items addObject:[NSPasteboardItem new]];
    return _items[0];
}
- (BOOL)writeObjects:(NSArray<id<NSPasteboardWriting>> *)objects {
    for (id o in objects) {
        if ([o isKindOfClass:[NSPasteboardItem class]]) {
            [_items addObject:o];
            continue;
        }
        NSPasteboardItem *item = [NSPasteboardItem new];
        if ([o isKindOfClass:[NSString class]]) {
            [item setString:o forType:NSPasteboardTypeString];
        } else if ([o isKindOfClass:[NSURL class]]) {
            NSURL *u = o;
            [item setString:u.absoluteString forType:u.isFileURL ? NSPasteboardTypeFileURL : NSPasteboardTypeURL];
            [item setString:u.absoluteString forType:NSPasteboardTypeString];
        } else if ([o respondsToSelector:@selector(writableTypesForPasteboard:)]) {
            for (NSPasteboardType t in [o writableTypesForPasteboard:self]) {
                id v = [o pasteboardPropertyListForType:t];
                if (v) [item setPropertyList:v forType:t];
            }
        }
        [_items addObject:item];
    }
    _changeCount++;
    [self _syncOut];
    return YES;
}
- (NSArray *)readObjectsForClasses:(NSArray<Class> *)classes options:(NSDictionary *)options {
    [self _syncIn];
    NSMutableArray *out = [NSMutableArray array];
    for (NSPasteboardItem *item in _items) {
        for (Class c in classes) {
            id v = nil;
            if (c == [NSString class]) v = [item stringForType:NSPasteboardTypeString];
            else if (c == [NSURL class]) {
                NSString *s = [item stringForType:NSPasteboardTypeFileURL] ?: [item stringForType:NSPasteboardTypeURL];
                v = s ? [NSURL URLWithString:s] : nil;
            } else if (c == [NSPasteboardItem class]) v = item;
            if (v) {
                [out addObject:v];
                break;
            }
        }
    }
    return out;
}
- (NSArray<NSPasteboardItem *> *)pasteboardItems {
    [self _syncIn];
    return [_items copy];
}
- (BOOL)canReadItemWithDataConformingToTypes:(NSArray<NSString *> *)types {
    [self _syncIn];
    for (NSPasteboardItem *i in _items) if ([i availableTypeFromArray:types]) return YES;
    return NO;
}
- (BOOL)canReadObjectForClasses:(NSArray<Class> *)classes options:(NSDictionary *)options {
    return [self readObjectsForClasses:classes options:options].count > 0;
}
- (NSArray<NSPasteboardType> *)types {
    [self _syncIn];
    return _items.count ? _items[0].types : @[];
}
- (NSPasteboardType)availableTypeFromArray:(NSArray<NSPasteboardType> *)types {
    [self _syncIn];
    return [_items.firstObject availableTypeFromArray:types];
}
- (BOOL)setData:(NSData *)data forType:(NSPasteboardType)type {
    BOOL ok = [[self _first] setData:data forType:type];
    _changeCount++;
    return ok;
}
- (BOOL)setPropertyList:(id)plist forType:(NSPasteboardType)type {
    BOOL ok = [[self _first] setPropertyList:plist forType:type];
    _changeCount++;
    return ok;
}
- (BOOL)setString:(NSString *)string forType:(NSPasteboardType)type {
    BOOL ok = [[self _first] setString:string forType:type];
    _changeCount++;
    [self _syncOut];
    return ok;
}
- (NSData *)dataForType:(NSPasteboardType)type {
    [self _syncIn];
    return [_items.firstObject dataForType:type];
}
- (id)propertyListForType:(NSPasteboardType)type {
    [self _syncIn];
    return [_items.firstObject propertyListForType:type];
}
- (NSString *)stringForType:(NSPasteboardType)type {
    [self _syncIn];
    return [_items.firstObject stringForType:type];
}
@end
