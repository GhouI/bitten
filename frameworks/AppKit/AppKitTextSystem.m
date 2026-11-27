/* The text system: key interpretation (NSResponder's interpretKeyEvents:,
 * NSTextInputContext for NSTextInputClient views), NSText and NSTextView
 * (an editable attributed string with a caret and selection), and the
 * NSTextContainer, NSLayoutManager, NSTextAttachment and NSTextRange
 * objects around them. */

#import <AppKit/AppKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <math.h>

/* ---- key bindings: what a key press means to the text system ---- */

enum {
    K_UP = 0xF700, K_DOWN = 0xF701, K_LEFT = 0xF702, K_RIGHT = 0xF703, K_DELETE_FWD = 0xF728, K_HOME = 0xF729,
    K_END = 0xF72B, K_PGUP = 0xF72C, K_PGDN = 0xF72D,
};
/* The command a key means, or NULL for text to insert. */
static SEL command_for(NSEvent *e) {
    NSString *chars = e.charactersIgnoringModifiers;
    if (!chars.length) return NULL;
    unichar c = [chars characterAtIndex:0];
    NSEventModifierFlags m = e.modifierFlags;
    BOOL shift = (m & NSEventModifierFlagShift) != 0, cmd = (m & NSEventModifierFlagCommand) != 0,
         opt = (m & NSEventModifierFlagOption) != 0, ctl = (m & NSEventModifierFlagControl) != 0;
#define S(plain, shifted) (shift ? @selector(shifted) : @selector(plain))
    switch (c) {
    case '\r': case 3: return opt ? @selector(insertNewlineIgnoringFieldEditor:) : @selector(insertNewline:);
    case '\n': return @selector(insertLineBreak:);
    case '\t': return shift ? @selector(insertBacktab:) : @selector(insertTab:);
    case 25: return @selector(insertBacktab:);
    case 27: return @selector(cancelOperation:);
    case 127: case 8:
        return opt ? @selector(deleteWordBackward:) : cmd ? @selector(deleteToBeginningOfLine:) : @selector(deleteBackward:);
    case K_DELETE_FWD: return opt ? @selector(deleteWordForward:) : @selector(deleteForward:);
    case K_LEFT:
        if (cmd) return S(moveToBeginningOfLine:, moveToBeginningOfLineAndModifySelection:);
        if (opt) return S(moveWordLeft:, moveWordLeftAndModifySelection:);
        return S(moveLeft:, moveLeftAndModifySelection:);
    case K_RIGHT:
        if (cmd) return S(moveToEndOfLine:, moveToEndOfLineAndModifySelection:);
        if (opt) return S(moveWordRight:, moveWordRightAndModifySelection:);
        return S(moveRight:, moveRightAndModifySelection:);
    case K_UP:
        if (cmd) return S(moveToBeginningOfDocument:, moveToBeginningOfDocumentAndModifySelection:);
        return S(moveUp:, moveUpAndModifySelection:);
    case K_DOWN:
        if (cmd) return S(moveToEndOfDocument:, moveToEndOfDocumentAndModifySelection:);
        return S(moveDown:, moveDownAndModifySelection:);
    case K_HOME: return @selector(scrollToBeginningOfDocument:);
    case K_END: return @selector(scrollToEndOfDocument:);
    case K_PGUP: return @selector(scrollPageUp:);
    case K_PGDN: return @selector(scrollPageDown:);
    default: break;
    }
#undef S
    if (ctl) {
        switch (c) {
        case 'a': return @selector(moveToBeginningOfParagraph:);
        case 'e': return @selector(moveToEndOfParagraph:);
        case 'b': return @selector(moveBackward:);
        case 'f': return @selector(moveForward:);
        case 'p': return @selector(moveUp:);
        case 'n': return @selector(moveDown:);
        case 'd': return @selector(deleteForward:);
        case 'h': return @selector(deleteBackward:);
        case 'k': return @selector(deleteToEndOfParagraph:);
        case 'o': return @selector(insertNewlineIgnoringFieldEditor:);
        case 't': return @selector(transpose:);
        case 'l': return @selector(centerSelectionInVisibleArea:);
        default: return @selector(noop:);
        }
    }
    if (cmd) return @selector(noop:);
    if (c >= 0xF700 && c <= 0xF8FF) return @selector(noop:);
    return NULL;
}

@implementation NSResponder (BittenTextInput)
- (void)interpretKeyEvents:(NSArray<NSEvent *> *)events {
    for (NSEvent *e in events) {
        if (e.type != NSEventTypeKeyDown) continue;
        SEL cmd = command_for(e);
        if (cmd) [self doCommandBySelector:cmd];
        else if (e.characters.length) [self insertText:e.characters];
    }
}
- (void)doCommandBySelector:(SEL)sel {
    if (sel == @selector(noop:)) return;
    if ([self respondsToSelector:sel]) ((void (*)(id, SEL, id))objc_msgSend)(self, sel, nil);
    else [self.nextResponder doCommandBySelector:sel];
}
- (void)insertText:(id)text { [self.nextResponder insertText:text]; }
- (void)flushBufferedKeyEvents {}
@end

/* ---- NSTextInputContext ---- */

static NSTextInputContext *current_context;

@implementation NSTextInputContext {
    __weak id<NSTextInputClient> _client;
    BOOL _acceptsGlyphInfo;
    NSArray<NSString *> *_allowedLocales;
    NSString *_selectedSource;
}
+ (NSTextInputContext *)currentInputContext { return current_context; }
- (instancetype)initWithClient:(id<NSTextInputClient>)client {
    self = [super init];
    _client = client;
    _selectedSource = @"com.apple.keylayout.US";
    return self;
}
- (id<NSTextInputClient>)client { return _client; }
- (BOOL)acceptsGlyphInfo { return _acceptsGlyphInfo; }
- (void)setAcceptsGlyphInfo:(BOOL)b { _acceptsGlyphInfo = b; }
- (NSArray<NSString *> *)allowedInputSourceLocales { return _allowedLocales; }
- (void)setAllowedInputSourceLocales:(NSArray<NSString *> *)a { _allowedLocales = [a copy]; }
- (NSArray<NSTextInputSourceIdentifier> *)keyboardInputSources { return @[ _selectedSource ]; }
- (NSTextInputSourceIdentifier)selectedKeyboardInputSource { return _selectedSource; }
- (void)setSelectedKeyboardInputSource:(NSTextInputSourceIdentifier)s { _selectedSource = [s copy]; }
+ (NSString *)localizedNameForInputSource:(NSTextInputSourceIdentifier)s { return @"U.S."; }
- (void)activate { current_context = self; }
- (void)deactivate {
    if (current_context == self) current_context = nil;
}
/* Key presses become insertText:replacementRange: or doCommandBySelector:
 * on the client. There is no input method, so no marked text. */
- (BOOL)handleEvent:(NSEvent *)event {
    id<NSTextInputClient> c = _client;
    if (!c || event.type != NSEventTypeKeyDown) return NO;
    SEL cmd = command_for(event);
    if (cmd) {
        if (cmd != @selector(noop:)) [c doCommandBySelector:cmd];
        else return NO;
    } else if (event.characters.length) {
        [c insertText:event.characters replacementRange:NSMakeRange(NSNotFound, 0)];
    } else {
        return NO;
    }
    return YES;
}
- (void)discardMarkedText {
    id<NSTextInputClient> c = _client;
    if ([c hasMarkedText]) [c unmarkText];
}
- (void)invalidateCharacterCoordinates {}
@end

@implementation NSView (BittenInputContext)
- (NSTextInputContext *)inputContext {
    if (![self conformsToProtocol:@protocol(NSTextInputClient)]) return nil;
    NSTextInputContext *c = objc_getAssociatedObject(self, @selector(inputContext));
    if (!c) {
        c = [[NSTextInputContext alloc] initWithClient:(id<NSTextInputClient>)self];
        objc_setAssociatedObject(self, @selector(inputContext), c, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return c;
}
@end

/* ---- text containers, layout managers, attachments, ranges ---- */

@implementation NSTextContainer {
    NSSize _size;
    CGFloat _padding;
    BOOL _widthTracks, _heightTracks;
    __weak NSTextView *_textView;
    __weak NSLayoutManager *_layoutManager;
    NSLineBreakMode _lineBreakMode;
    NSUInteger _maximumNumberOfLines;
}
- (instancetype)initWithSize:(NSSize)size {
    self = [super init];
    _size = size;
    _padding = 5;
    _lineBreakMode = NSLineBreakByWordWrapping;
    return self;
}
- (instancetype)init { return [self initWithSize:NSMakeSize(1e7, 1e7)]; }
- (instancetype)initWithContainerSize:(NSSize)size { return [self initWithSize:size]; }
- (NSSize)size { return _size; }
- (void)setSize:(NSSize)s { _size = s; }
- (NSSize)containerSize { return _size; }
- (void)setContainerSize:(NSSize)s { _size = s; }
- (CGFloat)lineFragmentPadding { return _padding; }
- (void)setLineFragmentPadding:(CGFloat)p { _padding = p; }
- (BOOL)widthTracksTextView { return _widthTracks; }
- (void)setWidthTracksTextView:(BOOL)b { _widthTracks = b; }
- (BOOL)heightTracksTextView { return _heightTracks; }
- (void)setHeightTracksTextView:(BOOL)b { _heightTracks = b; }
- (NSTextView *)textView { return _textView; }
- (void)setTextView:(NSTextView *)v { _textView = v; }
- (NSLayoutManager *)layoutManager { return _layoutManager; }
- (void)setLayoutManager:(NSLayoutManager *)m { _layoutManager = m; }
- (NSLineBreakMode)lineBreakMode { return _lineBreakMode; }
- (void)setLineBreakMode:(NSLineBreakMode)m { _lineBreakMode = m; }
- (NSUInteger)maximumNumberOfLines { return _maximumNumberOfLines; }
- (void)setMaximumNumberOfLines:(NSUInteger)n { _maximumNumberOfLines = n; }
@end

@implementation NSLayoutManager {
    __unsafe_unretained NSMutableAttributedString *_textStorage;
    NSMutableArray<NSTextContainer *> *_containers;
    BOOL _allowsNonContiguousLayout;
}
- (instancetype)init {
    self = [super init];
    _containers = [NSMutableArray array];
    return self;
}
- (NSMutableAttributedString *)textStorage { return _textStorage; }
- (void)setTextStorage:(NSMutableAttributedString *)s { _textStorage = s; }
- (NSArray<NSTextContainer *> *)textContainers { return [_containers copy]; }
- (void)addTextContainer:(NSTextContainer *)c {
    [_containers addObject:c];
    c.layoutManager = self;
}
- (void)removeTextContainerAtIndex:(NSUInteger)i { [_containers removeObjectAtIndex:i]; }
- (BOOL)allowsNonContiguousLayout { return _allowsNonContiguousLayout; }
- (void)setAllowsNonContiguousLayout:(BOOL)b { _allowsNonContiguousLayout = b; }
- (void)ensureLayoutForTextContainer:(NSTextContainer *)c {}
- (void)ensureLayoutForCharacterRange:(NSRange)r {}
- (NSUInteger)numberOfGlyphs { return _textStorage.length; }
- (NSRange)glyphRangeForTextContainer:(NSTextContainer *)c { return NSMakeRange(0, _textStorage.length); }
- (NSRange)glyphRangeForCharacterRange:(NSRange)r actualCharacterRange:(NSRangePointer)actual {
    if (actual) *actual = r;
    return r;
}
- (NSRange)characterRangeForGlyphRange:(NSRange)r actualGlyphRange:(NSRangePointer)actual {
    if (actual) *actual = r;
    return r;
}
- (NSRect)usedRectForTextContainer:(NSTextContainer *)c {
    NSAttributedString *s = _textStorage;
    if (!s.length) return NSZeroRect;
    CGFloat w = c.size.width - 2 * c.lineFragmentPadding;
    NSRect r = [s boundingRectWithSize:NSMakeSize(w > 0 && w < 1e6 ? w : 0, 1e7)
                               options:NSStringDrawingUsesLineFragmentOrigin
                               context:nil];
    r.size.width += 2 * c.lineFragmentPadding;
    return r;
}
- (NSRect)boundingRectForGlyphRange:(NSRange)r inTextContainer:(NSTextContainer *)c {
    return [self usedRectForTextContainer:c];
}
- (CGFloat)defaultLineHeightForFont:(NSFont *)font { return ceil(font.ascender - font.descender + font.leading); }
- (void)invalidateLayoutForCharacterRange:(NSRange)r actualCharacterRange:(NSRangePointer)actual {
    if (actual) *actual = r;
}
- (void)invalidateDisplayForCharacterRange:(NSRange)r {}
@end

@implementation NSTextAttachment {
    NSData *_contents;
    NSString *_fileType;
    NSImage *_image;
    NSRect _bounds;
    id _fileWrapper;
    id _attachmentCell;
}
- (instancetype)initWithData:(NSData *)data ofType:(NSString *)uti {
    self = [super init];
    _contents = data;
    _fileType = [uti copy];
    return self;
}
- (instancetype)init { return [self initWithData:nil ofType:nil]; }
- (instancetype)initWithFileWrapper:(id )w {
    self = [self initWithData:nil ofType:nil];
    _fileWrapper = w;
    return self;
}
+ (NSAttributedString *)_bn_attachmentString { return nil; }
- (NSData *)contents { return _contents; }
- (void)setContents:(NSData *)d { _contents = d; }
- (NSString *)fileType { return _fileType; }
- (void)setFileType:(NSString *)t { _fileType = [t copy]; }
- (NSImage *)image {
    if (!_image && _contents) _image = [[NSImage alloc] initWithData:_contents];
    return _image;
}
- (void)setImage:(NSImage *)i { _image = i; }
- (NSRect)bounds {
    if (NSIsEmptyRect(_bounds) && self.image) return NSMakeRect(0, 0, self.image.size.width, self.image.size.height);
    return _bounds;
}
- (void)setBounds:(NSRect)b { _bounds = b; }
- (id )fileWrapper { return _fileWrapper; }
- (void)setFileWrapper:(id )w { _fileWrapper = w; }
- (id)attachmentCell { return _attachmentCell; }
- (void)setAttachmentCell:(id)c { _attachmentCell = c; }
@end

@implementation NSTextRange {
    id<NSTextLocation> _location, _end;
}
- (instancetype)initWithLocation:(id<NSTextLocation>)location endLocation:(id<NSTextLocation>)end {
    if (end && [location compare:end] == NSOrderedDescending) return nil;
    self = [super init];
    _location = location;
    _end = end ?: location;
    return self;
}
- (instancetype)initWithLocation:(id<NSTextLocation>)location { return [self initWithLocation:location endLocation:nil]; }
- (id<NSTextLocation>)location { return _location; }
- (id<NSTextLocation>)endLocation { return _end; }
- (BOOL)isEmpty { return [_location compare:_end] == NSOrderedSame; }
- (BOOL)isEqualToTextRange:(NSTextRange *)o {
    return [_location compare:o.location] == NSOrderedSame && [_end compare:o.endLocation] == NSOrderedSame;
}
- (BOOL)containsLocation:(id<NSTextLocation>)l {
    return [_location compare:l] != NSOrderedDescending && [l compare:_end] == NSOrderedAscending;
}
- (BOOL)containsRange:(NSTextRange *)r {
    return [_location compare:r.location] != NSOrderedDescending && [r.endLocation compare:_end] != NSOrderedDescending;
}
- (BOOL)intersectsWithTextRange:(NSTextRange *)r {
    return [_location compare:r.endLocation] == NSOrderedAscending && [r.location compare:_end] == NSOrderedAscending;
}
@end

/* ---- NSText and NSTextView ---- */

@implementation NSText
@end

@implementation NSTextView {
    NSMutableAttributedString *_storage;
    NSTextContainer *_container;
    NSLayoutManager *_layoutManager;
    NSRange _selected;
    NSRange _marked;
    NSSize _inset, _minSize, _maxSize;
    NSColor *_insertionPointColor, *_backgroundColor, *_textColor;
    NSFont *_font;
    NSDictionary *_typingAttributes;
    BOOL _editable, _selectable, _rich, _drawsBackground, _allowsUndo, _hResizable, _vResizable, _fieldEditor,
        _usesFindBar, _importsGraphics, _continuousSpellChecking;
    __weak id<NSTextViewDelegate> _delegate;
}
- (instancetype)initWithFrame:(NSRect)frame textContainer:(NSTextContainer *)container {
    self = [super initWithFrame:frame];
    _storage = [[NSMutableAttributedString alloc] initWithString:@""];
    _container = container ?: [[NSTextContainer alloc] initWithSize:NSMakeSize(frame.size.width, 1e7)];
    _container.textView = self;
    _container.widthTracksTextView = YES;
    _layoutManager = [NSLayoutManager new];
    _layoutManager.textStorage = _storage;
    [_layoutManager addTextContainer:_container];
    _editable = _selectable = _rich = _drawsBackground = YES;
    _vResizable = YES;
    _maxSize = NSMakeSize(1e7, 1e7);
    _backgroundColor = NSColor.textBackgroundColor;
    _insertionPointColor = NSColor.textColor;
    return self;
}
- (instancetype)initWithFrame:(NSRect)frame { return [self initWithFrame:frame textContainer:nil]; }
- (instancetype)initUsingTextLayoutManager:(BOOL)b { return [self initWithFrame:NSZeroRect]; }
+ (instancetype)scrollableTextView {
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    sv.documentView = tv;
    sv.hasVerticalScroller = YES;
    return (NSTextView *)sv;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return _selectable; }
- (NSMutableAttributedString *)textStorage { return _storage; }
- (NSTextContainer *)textContainer { return _container; }
- (void)setTextContainer:(NSTextContainer *)c {
    _container = c;
    c.textView = self;
}
- (NSLayoutManager *)layoutManager { return _layoutManager; }
- (id)textLayoutManager { return nil; }
- (NSString *)string { return _storage.string; }
- (NSFont *)font { return _font ?: [NSFont userFixedPitchFontOfSize:0] ?: [NSFont systemFontOfSize:13]; }
- (void)setFont:(NSFont *)f {
    _font = f;
    if (_storage.length && f) [_storage addAttribute:NSFontAttributeName value:f range:NSMakeRange(0, _storage.length)];
    self.needsDisplay = YES;
}
- (NSColor *)textColor { return _textColor ?: NSColor.textColor; }
- (void)setTextColor:(NSColor *)c {
    _textColor = c;
    if (_storage.length && c)
        [_storage addAttribute:NSForegroundColorAttributeName value:c range:NSMakeRange(0, _storage.length)];
    self.needsDisplay = YES;
}
- (NSDictionary *)_bn_attributes {
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:_typingAttributes ?: @{}];
    if (!d[NSFontAttributeName]) d[NSFontAttributeName] = self.font;
    if (!d[NSForegroundColorAttributeName]) d[NSForegroundColorAttributeName] = self.textColor;
    return d;
}
- (NSDictionary *)typingAttributes { return self._bn_attributes; }
- (void)setTypingAttributes:(NSDictionary *)a { _typingAttributes = [a copy]; }
- (void)setString:(NSString *)s {
    [_storage setAttributedString:[[NSAttributedString alloc] initWithString:s ?: @"" attributes:self._bn_attributes]];
    _selected = NSMakeRange(_storage.length, 0);
    [self _bn_changed:NO];
}
- (BOOL)isEditable { return _editable; }
- (void)setEditable:(BOOL)b {
    _editable = b;
    if (b) _selectable = YES;
}
- (BOOL)isSelectable { return _selectable; }
- (void)setSelectable:(BOOL)b { _selectable = b; }
- (BOOL)isRichText { return _rich; }
- (void)setRichText:(BOOL)b { _rich = b; }
- (BOOL)importsGraphics { return _importsGraphics; }
- (void)setImportsGraphics:(BOOL)b { _importsGraphics = b; }
- (BOOL)isFieldEditor { return _fieldEditor; }
- (void)setFieldEditor:(BOOL)b { _fieldEditor = b; }
- (BOOL)drawsBackground { return _drawsBackground; }
- (void)setDrawsBackground:(BOOL)b { _drawsBackground = b; }
- (NSColor *)backgroundColor { return _backgroundColor; }
- (void)setBackgroundColor:(NSColor *)c { _backgroundColor = c; }
- (NSColor *)insertionPointColor { return _insertionPointColor; }
- (void)setInsertionPointColor:(NSColor *)c { _insertionPointColor = c; }
- (BOOL)allowsUndo { return _allowsUndo; }
- (void)setAllowsUndo:(BOOL)b { _allowsUndo = b; }
- (BOOL)usesFindBar { return _usesFindBar; }
- (void)setUsesFindBar:(BOOL)b { _usesFindBar = b; }
- (BOOL)isContinuousSpellCheckingEnabled { return _continuousSpellChecking; }
- (void)setContinuousSpellCheckingEnabled:(BOOL)b { _continuousSpellChecking = b; }
- (void)setAutomaticQuoteSubstitutionEnabled:(BOOL)b {}
- (void)setAutomaticDashSubstitutionEnabled:(BOOL)b {}
- (void)setAutomaticTextReplacementEnabled:(BOOL)b {}
- (void)setAutomaticSpellingCorrectionEnabled:(BOOL)b {}
- (void)setAutomaticLinkDetectionEnabled:(BOOL)b {}
- (void)setAutomaticDataDetectionEnabled:(BOOL)b {}
- (void)setAutomaticTextCompletionEnabled:(BOOL)b {}
- (void)setGrammarCheckingEnabled:(BOOL)b {}
- (void)setSmartInsertDeleteEnabled:(BOOL)b {}
- (void)setDisplaysLinkToolTips:(BOOL)b {}
- (void)setUsesFontPanel:(BOOL)b {}
- (void)setUsesRuler:(BOOL)b {}
- (void)setAllowsImageEditing:(BOOL)b {}
- (BOOL)isHorizontallyResizable { return _hResizable; }
- (void)setHorizontallyResizable:(BOOL)b { _hResizable = b; }
- (BOOL)isVerticallyResizable { return _vResizable; }
- (void)setVerticallyResizable:(BOOL)b { _vResizable = b; }
- (NSSize)minSize { return _minSize; }
- (void)setMinSize:(NSSize)s { _minSize = s; }
- (NSSize)maxSize { return _maxSize; }
- (void)setMaxSize:(NSSize)s { _maxSize = s; }
- (NSSize)textContainerInset { return _inset; }
- (void)setTextContainerInset:(NSSize)s {
    _inset = s;
    self.needsDisplay = YES;
}
- (NSPoint)textContainerOrigin { return NSMakePoint(_inset.width, _inset.height); }
- (id<NSTextViewDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSTextViewDelegate>)d { _delegate = d; }
- (NSRange)selectedRange { return _selected; }
- (void)setSelectedRange:(NSRange)r {
    NSUInteger n = _storage.length;
    if (r.location > n) r.location = n;
    if (NSMaxRange(r) > n) r.length = n - r.location;
    _selected = r;
    self.needsDisplay = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:NSTextViewDidChangeSelectionNotification object:self];
}
- (NSArray<NSValue *> *)selectedRanges { return @[ [NSValue valueWithRange:_selected] ]; }
- (void)setSelectedRanges:(NSArray<NSValue *> *)r { if (r.count) self.selectedRange = r[0].rangeValue; }
- (void)selectAll:(id)sender { self.selectedRange = NSMakeRange(0, _storage.length); }
- (void)scrollRangeToVisible:(NSRange)r {
    NSRect line = [self _bn_rectForIndex:MIN(r.location, _storage.length)];
    [self scrollRectToVisible:line];
}
/* Grows or shrinks to the text when resizable. */
- (void)sizeToFit {
    NSRect used = [_layoutManager usedRectForTextContainer:_container];
    NSRect f = self.frame;
    if (_vResizable) f.size.height = MIN(_maxSize.height, MAX(_minSize.height, used.size.height + 2 * _inset.height));
    if (_hResizable) f.size.width = MIN(_maxSize.width, MAX(_minSize.width, used.size.width + 2 * _inset.width));
    if (!NSEqualRects(f, self.frame)) self.frame = f;
}
- (void)setFrame:(NSRect)f {
    [super setFrame:f];
    if (_container.widthTracksTextView)
        _container.size = NSMakeSize(MAX(0, f.size.width - 2 * _inset.width), _container.size.height);
}
- (void)_bn_changed:(BOOL)byUser {
    if (_vResizable || _hResizable) [self sizeToFit];
    self.needsDisplay = YES;
    if (byUser) {
        id<NSTextViewDelegate> d = _delegate;
        NSNotification *n = [NSNotification notificationWithName:NSTextDidChangeNotification object:self];
        if ([d respondsToSelector:@selector(textDidChange:)]) [d textDidChange:n];
        [[NSNotificationCenter defaultCenter] postNotification:n];
    }
}
- (BOOL)shouldChangeTextInRange:(NSRange)r replacementString:(NSString *)s {
    if (!_editable) return NO;
    id<NSTextViewDelegate> d = _delegate;
    if ([d respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementString:)])
        return [d textView:self shouldChangeTextInRange:r replacementString:s];
    return YES;
}
- (void)didChangeText { [self _bn_changed:YES]; }
- (void)_bn_replace:(NSRange)r with:(NSString *)s {
    if (![self shouldChangeTextInRange:r replacementString:s]) return;
    [_storage replaceCharactersInRange:r
                  withAttributedString:[[NSAttributedString alloc] initWithString:s attributes:self._bn_attributes]];
    _selected = NSMakeRange(r.location + s.length, 0);
    [self didChangeText];
}
- (void)insertText:(id)text {
    NSString *s = [text isKindOfClass:[NSAttributedString class]] ? [text string] : text;
    [self _bn_replace:_marked.length ? _marked : _selected with:s ?: @""];
    _marked = NSMakeRange(NSNotFound, 0);
}
- (void)insertText:(id)text replacementRange:(NSRange)r {
    if (r.location != NSNotFound) _selected = r;
    [self insertText:text];
}
- (void)keyDown:(NSEvent *)e {
    if (!_selectable) {
        [super keyDown:e];
        return;
    }
    [self interpretKeyEvents:@[ e ]];
}
- (void)doCommandBySelector:(SEL)sel {
    id<NSTextViewDelegate> d = _delegate;
    if ([d respondsToSelector:@selector(textView:doCommandBySelector:)] && [d textView:self doCommandBySelector:sel]) return;
    [super doCommandBySelector:sel];
}
- (void)insertNewline:(id)s {
    if (_fieldEditor) [self.window makeFirstResponder:nil];
    else [self insertText:@"\n"];
}
- (void)insertLineBreak:(id)s { [self insertText:@"\n"]; }
- (void)insertNewlineIgnoringFieldEditor:(id)s { [self insertText:@"\n"]; }
- (void)insertTab:(id)s { [self insertText:@"\t"]; }
- (void)deleteBackward:(id)s {
    if (_selected.length) [self _bn_replace:_selected with:@""];
    else if (_selected.location > 0) {
        NSRange r = [_storage.string rangeOfComposedCharacterSequenceAtIndex:_selected.location - 1];
        [self _bn_replace:r with:@""];
    }
}
- (void)deleteForward:(id)s {
    if (_selected.length) [self _bn_replace:_selected with:@""];
    else if (_selected.location < _storage.length) {
        NSRange r = [_storage.string rangeOfComposedCharacterSequenceAtIndex:_selected.location];
        [self _bn_replace:r with:@""];
    }
}
- (void)moveLeft:(id)s {
    NSUInteger i = _selected.length ? _selected.location : (_selected.location ? _selected.location - 1 : 0);
    self.selectedRange = NSMakeRange(i, 0);
}
- (void)moveRight:(id)s {
    NSUInteger i = _selected.length ? NSMaxRange(_selected) : MIN(_selected.location + 1, _storage.length);
    self.selectedRange = NSMakeRange(i, 0);
}
- (void)moveBackward:(id)s { [self moveLeft:s]; }
- (void)moveForward:(id)s { [self moveRight:s]; }
- (void)moveToBeginningOfDocument:(id)s { self.selectedRange = NSMakeRange(0, 0); }
- (void)moveToEndOfDocument:(id)s { self.selectedRange = NSMakeRange(_storage.length, 0); }
- (NSRange)_bn_lineAt:(NSUInteger)i {
    NSString *str = _storage.string;
    NSUInteger start, end;
    [str getLineStart:&start end:NULL contentsEnd:&end forRange:NSMakeRange(MIN(i, str.length), 0)];
    return NSMakeRange(start, end - start);
}
- (void)moveToBeginningOfLine:(id)s { self.selectedRange = NSMakeRange([self _bn_lineAt:_selected.location].location, 0); }
- (void)moveToEndOfLine:(id)s { self.selectedRange = NSMakeRange(NSMaxRange([self _bn_lineAt:_selected.location]), 0); }
- (void)moveToBeginningOfParagraph:(id)s { [self moveToBeginningOfLine:s]; }
- (void)moveToEndOfParagraph:(id)s { [self moveToEndOfLine:s]; }
- (void)moveUp:(id)s {
    NSRange line = [self _bn_lineAt:_selected.location];
    if (line.location == 0) return [self moveToBeginningOfDocument:s];
    NSRange prev = [self _bn_lineAt:line.location - 1];
    self.selectedRange = NSMakeRange(prev.location + MIN(_selected.location - line.location, prev.length), 0);
}
- (void)moveDown:(id)s {
    NSRange line = [self _bn_lineAt:_selected.location];
    NSUInteger next = NSMaxRange(line) + 1;
    if (next > _storage.length) return [self moveToEndOfDocument:s];
    NSRange n = [self _bn_lineAt:next];
    self.selectedRange = NSMakeRange(n.location + MIN(_selected.location - line.location, n.length), 0);
}
- (void)deleteToEndOfParagraph:(id)s {
    NSRange line = [self _bn_lineAt:_selected.location];
    NSUInteger end = NSMaxRange(line);
    [self _bn_replace:NSMakeRange(_selected.location, end > _selected.location ? end - _selected.location : MIN(1, _storage.length - _selected.location)) with:@""];
}
- (void)deleteToBeginningOfLine:(id)s {
    NSRange line = [self _bn_lineAt:_selected.location];
    [self _bn_replace:NSMakeRange(line.location, _selected.location - line.location) with:@""];
}
- (void)cancelOperation:(id)s {}
- (void)scrollToBeginningOfDocument:(id)s { [self scrollRangeToVisible:NSMakeRange(0, 0)]; }
- (void)scrollToEndOfDocument:(id)s { [self scrollRangeToVisible:NSMakeRange(_storage.length, 0)]; }
- (void)copy:(id)sender {
    if (!_selected.length) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:[_storage.string substringWithRange:_selected] forType:NSPasteboardTypeString];
}
- (void)cut:(id)sender {
    [self copy:sender];
    if (_editable) [self _bn_replace:_selected with:@""];
}
- (void)paste:(id)sender {
    NSString *s = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    if (s) [self insertText:s];
}
/* NSTextInputClient. */
- (void)setMarkedText:(id)text selectedRange:(NSRange)sel replacementRange:(NSRange)r {
    NSString *s = [text isKindOfClass:[NSAttributedString class]] ? [text string] : text;
    NSRange target = r.location != NSNotFound ? r : (_marked.length ? _marked : _selected);
    [_storage replaceCharactersInRange:target withString:s ?: @""];
    _marked = NSMakeRange(target.location, s.length);
    _selected = NSMakeRange(target.location + sel.location, sel.length);
    self.needsDisplay = YES;
}
- (void)unmarkText { _marked = NSMakeRange(NSNotFound, 0); }
- (BOOL)hasMarkedText { return _marked.location != NSNotFound && _marked.length > 0; }
- (NSRange)markedRange { return self.hasMarkedText ? _marked : NSMakeRange(NSNotFound, 0); }
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText { return @[]; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)r actualRange:(NSRangePointer)actual {
    NSUInteger n = _storage.length;
    if (r.location >= n) return nil;
    r.length = MIN(r.length, n - r.location);
    if (actual) *actual = r;
    return [_storage attributedSubstringFromRange:r];
}
- (NSRect)_bn_rectForIndex:(NSUInteger)i {
    NSString *str = _storage.string;
    NSFont *f = self.font;
    CGFloat lh = ceil(f.ascender - f.descender);
    NSUInteger line = 0, start = 0;
    for (NSUInteger k = 0; k < i && k < str.length; k++)
        if ([str characterAtIndex:k] == '\n') {
            line++;
            start = k + 1;
        }
    NSString *prefix = [str substringWithRange:NSMakeRange(start, MIN(i, str.length) - start)];
    CGFloat x = [prefix sizeWithAttributes:self._bn_attributes].width;
    return NSMakeRect(_inset.width + _container.lineFragmentPadding + x, _inset.height + line * lh, 1, lh);
}
- (NSRect)firstRectForCharacterRange:(NSRange)r actualRange:(NSRangePointer)actual {
    if (actual) *actual = r;
    NSRect local = [self _bn_rectForIndex:r.location];
    return self.window ? [self.window convertRectToScreen:[self convertRect:local toView:nil]] : local;
}
- (NSUInteger)characterIndexForPoint:(NSPoint)screenPoint { return _selected.location; }
- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds;
    if (_drawsBackground && _backgroundColor) {
        [_backgroundColor setFill];
        NSRectFill(dirty);
    }
    CGFloat pad = _container.lineFragmentPadding;
    NSRect textRect = NSMakeRect(_inset.width + pad, _inset.height, MAX(0, b.size.width - 2 * (_inset.width + pad)),
                                 MAX(0, b.size.height - 2 * _inset.height));
    if (_selected.length) {
        NSRect a = [self _bn_rectForIndex:_selected.location], z = [self _bn_rectForIndex:NSMaxRange(_selected)];
        [NSColor.selectedTextBackgroundColor setFill];
        if (a.origin.y == z.origin.y) NSRectFill(NSMakeRect(a.origin.x, a.origin.y, z.origin.x - a.origin.x, a.size.height));
        else NSRectFill(NSMakeRect(textRect.origin.x, a.origin.y, textRect.size.width, NSMaxY(z) - a.origin.y));
    }
    if (_storage.length) [_storage drawInRect:textRect];
    if (_editable && self.window.firstResponder == self && !_selected.length) {
        [_insertionPointColor setFill];
        NSRectFill([self _bn_rectForIndex:_selected.location]);
    }
}
@end

/* Writing Tools (an Apple Intelligence feature) is not offered here; the
 * settings are kept so they read back. Shared by text fields and views. */
static const char k_writing_allows, k_writing_behavior, k_writing_options, k_completion;
#define WRITING_TOOLS                                                                                         \
    -(BOOL)allowsWritingTools {                                                                               \
        NSNumber *n = objc_getAssociatedObject(self, &k_writing_allows);                                      \
        return n ? n.boolValue : YES;                                                                         \
    }                                                                                                         \
    -(void)setAllowsWritingTools : (BOOL)b {                                                                  \
        objc_setAssociatedObject(self, &k_writing_allows, @(b), OBJC_ASSOCIATION_RETAIN_NONATOMIC);           \
    }                                                                                                         \
    -(NSWritingToolsBehavior)writingToolsBehavior {                                                           \
        return [objc_getAssociatedObject(self, &k_writing_behavior) integerValue];                            \
    }                                                                                                         \
    -(void)setWritingToolsBehavior : (NSWritingToolsBehavior)b {                                              \
        objc_setAssociatedObject(self, &k_writing_behavior, @(b), OBJC_ASSOCIATION_RETAIN_NONATOMIC);         \
    }                                                                                                         \
    -(NSWritingToolsResultOptions)allowedWritingToolsResultOptions {                                          \
        return [objc_getAssociatedObject(self, &k_writing_options) unsignedIntegerValue];                     \
    }                                                                                                         \
    -(void)setAllowedWritingToolsResultOptions : (NSWritingToolsResultOptions)o {                             \
        objc_setAssociatedObject(self, &k_writing_options, @(o), OBJC_ASSOCIATION_RETAIN_NONATOMIC);          \
    }
@implementation NSTextField (BittenWritingTools)
WRITING_TOOLS
- (BOOL)isAutomaticTextCompletionEnabled { return [objc_getAssociatedObject(self, &k_completion) boolValue]; }
- (void)setAutomaticTextCompletionEnabled:(BOOL)b {
    objc_setAssociatedObject(self, &k_completion, @(b), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end
/* The rest of NSText's and NSTextView's settings. Alignment, writing
 * direction and the default paragraph style shape the text (as a paragraph
 * style on the whole text and on what is typed next); the others are kept
 * and reported back. */
static const char k_tv_align, k_tv_direction, k_tv_paragraph, k_tv_marked, k_tv_selectedAttrs, k_tv_link,
    k_tv_flags, k_tv_prediction, k_tv_bgchange;
@implementation NSTextView (BittenTextSettings)
- (void)_bn_applyParagraphStyle {
    NSMutableParagraphStyle *p = [(self.defaultParagraphStyle ?: NSParagraphStyle.defaultParagraphStyle) mutableCopy];
    p.alignment = self.alignment;
    p.baseWritingDirection = self.baseWritingDirection;
    NSMutableDictionary *typing = [self.typingAttributes mutableCopy];
    typing[NSParagraphStyleAttributeName] = p;
    self.typingAttributes = typing;
    NSMutableAttributedString *storage = self.textStorage;
    if (storage.length) [storage addAttribute:NSParagraphStyleAttributeName value:p range:NSMakeRange(0, storage.length)];
    self.needsDisplay = YES;
}
- (NSTextAlignment)alignment { return [objc_getAssociatedObject(self, &k_tv_align) integerValue]; }
- (void)setAlignment:(NSTextAlignment)a {
    objc_setAssociatedObject(self, &k_tv_align, @(a), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self _bn_applyParagraphStyle];
}
- (NSWritingDirection)baseWritingDirection {
    NSNumber *n = objc_getAssociatedObject(self, &k_tv_direction);
    return n ? n.integerValue : NSWritingDirectionNatural;
}
- (void)setBaseWritingDirection:(NSWritingDirection)d {
    objc_setAssociatedObject(self, &k_tv_direction, @(d), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self _bn_applyParagraphStyle];
}
- (NSParagraphStyle *)defaultParagraphStyle { return objc_getAssociatedObject(self, &k_tv_paragraph); }
- (void)setDefaultParagraphStyle:(NSParagraphStyle *)p {
    objc_setAssociatedObject(self, &k_tv_paragraph, [p copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (p) objc_setAssociatedObject(self, &k_tv_align, @(p.alignment), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self _bn_applyParagraphStyle];
}
- (NSDictionary *)markedTextAttributes { return objc_getAssociatedObject(self, &k_tv_marked) ?: @{}; }
- (void)setMarkedTextAttributes:(NSDictionary *)a { objc_setAssociatedObject(self, &k_tv_marked, [a copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSDictionary *)selectedTextAttributes {
    return objc_getAssociatedObject(self, &k_tv_selectedAttrs) ?: @{NSBackgroundColorAttributeName : NSColor.selectedTextBackgroundColor};
}
- (void)setSelectedTextAttributes:(NSDictionary *)a {
    objc_setAssociatedObject(self, &k_tv_selectedAttrs, [a copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSDictionary *)linkTextAttributes {
    return objc_getAssociatedObject(self, &k_tv_link) ?: @{NSForegroundColorAttributeName : NSColor.linkColor,
                                                            NSUnderlineStyleAttributeName : @1};
}
- (void)setLinkTextAttributes:(NSDictionary *)a { objc_setAssociatedObject(self, &k_tv_link, [a copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
/* on/off settings kept as bits */
enum { TV_RULER = 1, TV_RULER_VISIBLE = 2, TV_INSPECTOR = 4, TV_QUOTES = 8, TV_DASHES = 16, TV_REPLACE = 32,
       TV_SPELLING = 64, TV_LINKS = 128, TV_DATA = 256, TV_COMPLETION = 512, TV_GRAMMAR = 1024, TV_SMART = 2048 };
static BOOL tv_flag(id tv, unsigned bit) { return ([objc_getAssociatedObject(tv, &k_tv_flags) unsignedIntValue] & bit) != 0; }
static void tv_set_flag(id tv, unsigned bit, BOOL on) {
    unsigned v = [objc_getAssociatedObject(tv, &k_tv_flags) unsignedIntValue];
    v = on ? v | bit : v & ~bit;
    objc_setAssociatedObject(tv, &k_tv_flags, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)usesRuler { return tv_flag(self, TV_RULER); }
- (void)setUsesRuler:(BOOL)b { tv_set_flag(self, TV_RULER, b); }
- (BOOL)isRulerVisible { return tv_flag(self, TV_RULER_VISIBLE); }
- (void)setRulerVisible:(BOOL)b { tv_set_flag(self, TV_RULER_VISIBLE, b); }
- (BOOL)usesInspectorBar { return tv_flag(self, TV_INSPECTOR); }
- (void)setUsesInspectorBar:(BOOL)b { tv_set_flag(self, TV_INSPECTOR, b); }
- (BOOL)isAutomaticQuoteSubstitutionEnabled { return tv_flag(self, TV_QUOTES); }
- (void)setAutomaticQuoteSubstitutionEnabled:(BOOL)b { tv_set_flag(self, TV_QUOTES, b); }
- (BOOL)isAutomaticDashSubstitutionEnabled { return tv_flag(self, TV_DASHES); }
- (void)setAutomaticDashSubstitutionEnabled:(BOOL)b { tv_set_flag(self, TV_DASHES, b); }
- (BOOL)isAutomaticTextReplacementEnabled { return tv_flag(self, TV_REPLACE); }
- (void)setAutomaticTextReplacementEnabled:(BOOL)b { tv_set_flag(self, TV_REPLACE, b); }
- (BOOL)isAutomaticSpellingCorrectionEnabled { return tv_flag(self, TV_SPELLING); }
- (void)setAutomaticSpellingCorrectionEnabled:(BOOL)b { tv_set_flag(self, TV_SPELLING, b); }
- (BOOL)isAutomaticLinkDetectionEnabled { return tv_flag(self, TV_LINKS); }
- (void)setAutomaticLinkDetectionEnabled:(BOOL)b { tv_set_flag(self, TV_LINKS, b); }
- (BOOL)isAutomaticDataDetectionEnabled { return tv_flag(self, TV_DATA); }
- (void)setAutomaticDataDetectionEnabled:(BOOL)b { tv_set_flag(self, TV_DATA, b); }
- (BOOL)isAutomaticTextCompletionEnabled { return tv_flag(self, TV_COMPLETION); }
- (void)setAutomaticTextCompletionEnabled:(BOOL)b { tv_set_flag(self, TV_COMPLETION, b); }
- (BOOL)isGrammarCheckingEnabled { return tv_flag(self, TV_GRAMMAR); }
- (void)setGrammarCheckingEnabled:(BOOL)b { tv_set_flag(self, TV_GRAMMAR, b); }
- (BOOL)smartInsertDeleteEnabled { return tv_flag(self, TV_SMART); }
- (void)setSmartInsertDeleteEnabled:(BOOL)b { tv_set_flag(self, TV_SMART, b); }
- (BOOL)allowsDocumentBackgroundColorChange { return [objc_getAssociatedObject(self, &k_tv_bgchange) boolValue]; }
- (void)setAllowsDocumentBackgroundColorChange:(BOOL)b {
    objc_setAssociatedObject(self, &k_tv_bgchange, @(b), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSInteger)inlinePredictionType { return [objc_getAssociatedObject(self, &k_tv_prediction) integerValue]; }
- (void)setInlinePredictionType:(NSInteger)t {
    objc_setAssociatedObject(self, &k_tv_prediction, @(t), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)setMathExpressionCompletionType:(NSInteger)t {}
- (id)textContentStorage { return nil; } /* TextKit 1 only */
- (void)setSelectedRange:(NSRange)r affinity:(NSInteger)a stillSelecting:(BOOL)still { self.selectedRange = r; }
/* paragraph settings for part of the text */
- (void)_bn_paragraphs:(NSRange)r change:(void (^)(NSMutableParagraphStyle *))change {
    NSMutableAttributedString *storage = self.textStorage;
    if (NSMaxRange(r) > storage.length) return;
    if (!r.length) { /* an empty range sets what is typed there next */
        NSMutableDictionary *typing = [self.typingAttributes mutableCopy];
        NSMutableParagraphStyle *p = [(typing[NSParagraphStyleAttributeName] ?: NSParagraphStyle.defaultParagraphStyle) mutableCopy];
        change(p);
        typing[NSParagraphStyleAttributeName] = p;
        self.typingAttributes = typing;
        return;
    }
    NSRange whole = [storage.string paragraphRangeForRange:r];
    [storage enumerateAttribute:NSParagraphStyleAttributeName inRange:whole options:0
                     usingBlock:^(id value, NSRange sub, BOOL *stop) {
                         NSMutableParagraphStyle *p = [(value ?: NSParagraphStyle.defaultParagraphStyle) mutableCopy];
                         change(p);
                         [storage addAttribute:NSParagraphStyleAttributeName value:p range:sub];
                     }];
    self.needsDisplay = YES;
}
- (void)setAlignment:(NSTextAlignment)a range:(NSRange)r {
    [self _bn_paragraphs:r change:^(NSMutableParagraphStyle *p) { p.alignment = a; }];
}
- (void)setBaseWritingDirection:(NSWritingDirection)d range:(NSRange)r {
    [self _bn_paragraphs:r change:^(NSMutableParagraphStyle *p) { p.baseWritingDirection = d; }];
}
- (NSAttributedString *)attributedString { return [self.textStorage copy] ?: [[NSAttributedString alloc] init]; }
/* replaces text as typing would: asks first, then reports the change */
- (BOOL)performValidatedReplacementInRange:(NSRange)r withAttributedString:(NSAttributedString *)s {
    if (NSMaxRange(r) > self.textStorage.length) return NO;
    if (![self shouldChangeTextInRange:r replacementString:s.string]) return NO;
    [self.textStorage replaceCharactersInRange:r withAttributedString:s ?: [[NSAttributedString alloc] init]];
    self.selectedRange = NSMakeRange(r.location + s.length, 0);
    [self didChangeText];
    return YES;
}
- (void)showFindIndicatorForRange:(NSRange)r { [self scrollRangeToVisible:r]; }
- (void)breakUndoCoalescing {}
- (void)invalidateTextContainerOrigin {}
- (void)updateInsertionPointStateAndRestartTimer:(BOOL)restart { self.needsDisplay = YES; }
- (void)alignLeft:(id)sender { [self setAlignment:NSTextAlignmentLeft range:self.selectedRange]; }
- (void)alignRight:(id)sender { [self setAlignment:NSTextAlignmentRight range:self.selectedRange]; }
- (void)alignCenter:(id)sender { [self setAlignment:NSTextAlignmentCenter range:self.selectedRange]; }
- (void)alignJustified:(id)sender { [self setAlignment:NSTextAlignmentJustified range:self.selectedRange]; }
/* programmatic edits: no delegate check, as in AppKit */
- (void)replaceCharactersInRange:(NSRange)r withString:(NSString *)s {
    NSMutableAttributedString *storage = self.textStorage;
    if (NSMaxRange(r) > storage.length) return;
    [storage replaceCharactersInRange:r withAttributedString:[[NSAttributedString alloc] initWithString:s ?: @""
                                                                                            attributes:self.typingAttributes]];
    self.needsDisplay = YES;
}
- (void)delete:(id)sender {
    NSRange r = self.selectedRange;
    if (r.length && [self shouldChangeTextInRange:r replacementString:@""]) {
        [self.textStorage deleteCharactersInRange:r];
        self.selectedRange = NSMakeRange(r.location, 0);
        [self didChangeText];
    }
}
- (id)_bn_undoManager {
    return [self respondsToSelector:@selector(undoManager)] ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(undoManager)) : nil;
}
- (void)undo:(id)sender { ((void (*)(id, SEL))objc_msgSend)(self._bn_undoManager, @selector(undo)); }
- (void)redo:(id)sender { ((void (*)(id, SEL))objc_msgSend)(self._bn_undoManager, @selector(redo)); }
- (void)setFont:(NSFont *)font range:(NSRange)r {
    if (font && NSMaxRange(r) <= self.textStorage.length) [self.textStorage addAttribute:NSFontAttributeName value:font range:r];
    self.needsDisplay = YES;
}
- (void)setTextColor:(NSColor *)color range:(NSRange)r {
    if (NSMaxRange(r) > self.textStorage.length) return;
    if (color) [self.textStorage addAttribute:NSForegroundColorAttributeName value:color range:r];
    else [self.textStorage removeAttribute:NSForegroundColorAttributeName range:r];
    self.needsDisplay = YES;
}
@end

@implementation NSTextView (BittenWritingTools)
WRITING_TOOLS
- (BOOL)usesAdaptiveColorMappingForDarkAppearance {
    return [objc_getAssociatedObject(self, @selector(usesAdaptiveColorMappingForDarkAppearance)) boolValue];
}
- (void)setUsesAdaptiveColorMappingForDarkAppearance:(BOOL)b {
    objc_setAssociatedObject(self, @selector(usesAdaptiveColorMappingForDarkAppearance), @(b), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

/* The cell class set for a control class (cells: AppKitCells.m). */
@implementation NSControl (BittenCellClass)
+ (Class)cellClass { return objc_getAssociatedObject(self, @selector(cellClass)); }
+ (void)setCellClass:(Class)c { objc_setAssociatedObject(self, @selector(cellClass), c, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isContinuous { return [objc_getAssociatedObject(self, @selector(isContinuous)) boolValue]; }
- (void)setContinuous:(BOOL)b {
    objc_setAssociatedObject(self, @selector(isContinuous), @(b), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end
