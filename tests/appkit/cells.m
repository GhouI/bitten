// Cells: text and image cells hold their values and draw them; controls
// hand out a cell of their +cellClass (a program's subclass included).
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

@interface CentredCell : NSTextFieldCell
@end
@implementation CentredCell
- (NSRect)titleRectForBounds:(NSRect)r { return NSInsetRect(r, 0, 2); }
@end
@interface CentredField : NSTextField
@end
@implementation CentredField
+ (void)load { [self setCellClass:[CentredCell class]]; }
@end

int main(void) {
    @autoreleasepool {
        NSTextFieldCell *t = [[NSTextFieldCell alloc] initTextCell:@"Hello"];
        CHECK([t.stringValue isEqualToString:@"Hello"]);
        CHECK(t.type == NSTextCellType && t.isEnabled);
        t.alignment = NSTextAlignmentCenter;
        t.intValue = 42;
        CHECK(t.integerValue == 42 && [t.stringValue isEqualToString:@"42"]);
        t.stringValue = @"Wide text";
        NSSize s = t.cellSize;
        CHECK(s.width > 20 && s.height > 8);

        NSButtonCell *b = [[NSButtonCell alloc] initTextCell:@"OK"];
        CHECK(b.alignment == NSTextAlignmentCenter);
        NSCell *copy = [b copy];
        CHECK([copy isKindOfClass:[NSButtonCell class]] && [copy.title isEqualToString:@"OK"]);

        CentredField *f = [[CentredField alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        CHECK([f.cell isKindOfClass:[CentredCell class]]);
        CHECK(((NSCell *)f.cell).controlView == f);
        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 50, 20)];
        CHECK([button.cell isKindOfClass:[NSButtonCell class]]);

        // Drawing: a text cell puts ink in its frame.
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGContextRef c = CGBitmapContextCreate(NULL, 100, 30, 8, 400, rgb,
                                               kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        CGContextSetRGBFillColor(c, 1, 1, 1, 1);
        CGContextFillRect(c, CGRectMake(0, 0, 100, 30));
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:c flipped:NO]];
        t.textColor = [NSColor blackColor];
        [t drawWithFrame:NSMakeRect(0, 0, 100, 30) inView:f];
        const unsigned char *px = CGBitmapContextGetData(c);
        int ink = 0;
        for (int i = 0; i < 100 * 30; i++) ink += px[i * 4] < 0x80;
        CHECK(ink > 20);
        printf("ok\n");
    }
    return 0;
}
