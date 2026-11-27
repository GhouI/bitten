// The text system: key interpretation into commands and text, input
// contexts for NSTextInputClient views, NSTextView editing, and the
// NSString line and composed-character helpers it relies on.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

static NSEvent *key(NSString *chars, NSEventModifierFlags mods) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:mods timestamp:0
                        windowNumber:0 context:nil characters:chars charactersIgnoringModifiers:chars
                           isARepeat:NO keyCode:0];
}

@interface Client : NSView <NSTextInputClient>
@property (strong) NSMutableString *typed;
@property (strong) NSMutableArray *commands;
@end
@implementation Client
- (void)insertText:(id)s replacementRange:(NSRange)r { [self.typed appendString:s]; }
- (void)doCommandBySelector:(SEL)sel { [self.commands addObject:NSStringFromSelector(sel)]; }
- (void)setMarkedText:(id)s selectedRange:(NSRange)a replacementRange:(NSRange)b {}
- (void)unmarkText {}
- (NSRange)selectedRange { return NSMakeRange(0, 0); }
- (NSRange)markedRange { return NSMakeRange(NSNotFound, 0); }
- (BOOL)hasMarkedText { return NO; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)r actualRange:(NSRangePointer)a { return nil; }
- (NSArray *)validAttributesForMarkedText { return @[]; }
- (NSRect)firstRectForCharacterRange:(NSRange)r actualRange:(NSRangePointer)a { return NSZeroRect; }
- (NSUInteger)characterIndexForPoint:(NSPoint)p { return 0; }
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Client *c = [[Client alloc] initWithFrame:NSZeroRect];
        c.typed = [NSMutableString string];
        c.commands = [NSMutableArray array];
        NSTextInputContext *ctx = c.inputContext;
        CHECK(ctx && ctx.client == c && c.inputContext == ctx);
        CHECK([ctx handleEvent:key(@"h", 0)] && [ctx handleEvent:key(@"i", 0)]);
        [ctx handleEvent:key(@"\r", 0)];
        [ctx handleEvent:key(@"\x7f", 0)];
        unichar left = 0xF702;
        [ctx handleEvent:key([NSString stringWithCharacters:&left length:1], NSEventModifierFlagShift)];
        CHECK([c.typed isEqualToString:@"hi"]);
        CHECK([c.commands isEqual:(@[ @"insertNewline:", @"deleteBackward:", @"moveLeftAndModifySelection:" ])]);
        CHECK(![[[NSView alloc] initWithFrame:NSZeroRect] inputContext]);

        NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        for (NSString *s in @[ @"a", @"b", @"c" ]) [tv keyDown:key(s, 0)];
        CHECK([tv.string isEqualToString:@"abc"] && tv.selectedRange.location == 3);
        [tv keyDown:key([NSString stringWithCharacters:&left length:1], 0)];
        [tv keyDown:key(@"\x7f", 0)];
        CHECK([tv.string isEqualToString:@"ac"] && tv.selectedRange.location == 1);
        [tv keyDown:key(@"\r", 0)];
        [tv insertText:@"xyz"];
        CHECK([tv.string isEqualToString:@"a\nxyzc"]);
        [tv moveUp:nil];
        CHECK(tv.selectedRange.location == 1);
        tv.string = @"reset";
        CHECK([tv.textStorage.string isEqualToString:@"reset"] && tv.selectedRange.location == 5);
        tv.editable = NO;
        [tv insertText:@"!"];
        CHECK([tv.string isEqualToString:@"reset"]);

        NSString *s = @"one\r\ntwo\nthree";
        NSUInteger start, end, contents;
        [s getLineStart:&start end:&end contentsEnd:&contents forRange:NSMakeRange(6, 0)];
        CHECK(start == 5 && contents == 8 && end == 9);
        [s getLineStart:&start end:&end contentsEnd:&contents forRange:NSMakeRange(1, 0)];
        CHECK(start == 0 && contents == 3 && end == 5);
        NSString *e = @"éx";
        CHECK(NSEqualRanges([e rangeOfComposedCharacterSequenceAtIndex:0], NSMakeRange(0, 2)));
        // NSTextView's text settings: alignment shapes the text and what
        // is typed next; programmatic edits and range attributes.
        NSTextView *tv2 = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 50)];
        tv2.string = @"hello";
        tv2.alignment = NSTextAlignmentCenter;
        CHECK(tv2.alignment == NSTextAlignmentCenter);
        NSParagraphStyle *ps = [tv2.textStorage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
        CHECK(ps.alignment == NSTextAlignmentCenter);
        CHECK(((NSParagraphStyle *)tv2.typingAttributes[NSParagraphStyleAttributeName]).alignment == NSTextAlignmentCenter);
        [tv2 replaceCharactersInRange:NSMakeRange(0, 1) withString:@"j"];
        CHECK([tv2.string isEqualToString:@"jello"]);
        NSColor *red = NSColor.redColor;
        [tv2 setTextColor:red range:NSMakeRange(1, 2)];
        CHECK([tv2.textStorage attribute:NSForegroundColorAttributeName atIndex:1 effectiveRange:NULL] == red);
        [tv2 setAlignment:NSTextAlignmentRight range:NSMakeRange(0, 2)];
        ps = [tv2.textStorage attribute:NSParagraphStyleAttributeName atIndex:4 effectiveRange:NULL];
        CHECK(ps.alignment == NSTextAlignmentRight); /* the whole paragraph */
        tv2.automaticQuoteSubstitutionEnabled = YES;
        CHECK(tv2.isAutomaticQuoteSubstitutionEnabled && !tv2.isGrammarCheckingEnabled);
        NSColor *blue = NSColor.blueColor;
        tv2.selectedTextAttributes = @{NSForegroundColorAttributeName : blue};
        CHECK(tv2.selectedTextAttributes[NSForegroundColorAttributeName] == blue);
        // A text field made in code is bezeled, not bordered; the two exclude each other.
        NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        CHECK(field.isBezeled && !field.isBordered && field.drawsBackground);
        field.bordered = YES;
        CHECK(field.isBordered && !field.isBezeled);
        field.bezeled = YES;
        CHECK(field.isBezeled && !field.isBordered);
        // x86-64 macOS keeps AppKit's original alignment values.
        CHECK(NSTextAlignmentRight == 1 && NSTextAlignmentCenter == 2);
        puts("appkit text ok");
    }
    return 0;
}
