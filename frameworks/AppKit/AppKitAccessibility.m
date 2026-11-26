/* The NSAccessibility protocol's properties on responders and menu items,
 * kept as associated values (no assistive technology reads them here). */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@implementation NSResponder (BittenAccessibility)
- (NSString *)accessibilityLabel { return objc_getAssociatedObject(self, @selector(accessibilityLabel)); }
- (void)setAccessibilityLabel:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityLabel), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityTitle { return objc_getAssociatedObject(self, @selector(accessibilityTitle)); }
- (void)setAccessibilityTitle:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityTitle), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityHelp { return objc_getAssociatedObject(self, @selector(accessibilityHelp)); }
- (void)setAccessibilityHelp:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityHelp), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (id)accessibilityValue { return objc_getAssociatedObject(self, @selector(accessibilityValue)); }
- (void)setAccessibilityValue:(id)v { objc_setAssociatedObject(self, @selector(accessibilityValue), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSAccessibilityRole)accessibilityRole { return objc_getAssociatedObject(self, @selector(accessibilityRole)); }
- (void)setAccessibilityRole:(NSAccessibilityRole)v { objc_setAssociatedObject(self, @selector(accessibilityRole), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilitySubrole { return objc_getAssociatedObject(self, @selector(accessibilitySubrole)); }
- (void)setAccessibilitySubrole:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilitySubrole), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityRoleDescription { return objc_getAssociatedObject(self, @selector(accessibilityRoleDescription)); }
- (void)setAccessibilityRoleDescription:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityRoleDescription), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityIdentifier { return objc_getAssociatedObject(self, @selector(accessibilityIdentifier)); }
- (void)setAccessibilityIdentifier:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityIdentifier), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityPlaceholderValue { return objc_getAssociatedObject(self, @selector(accessibilityPlaceholderValue)); }
- (void)setAccessibilityPlaceholderValue:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityPlaceholderValue), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityValueDescription { return objc_getAssociatedObject(self, @selector(accessibilityValueDescription)); }
- (void)setAccessibilityValueDescription:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityValueDescription), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilityChildren { return objc_getAssociatedObject(self, @selector(accessibilityChildren)); }
- (void)setAccessibilityChildren:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityChildren), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilityCustomActions { return objc_getAssociatedObject(self, @selector(accessibilityCustomActions)); }
- (void)setAccessibilityCustomActions:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityCustomActions), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilitySelectedChildren { return objc_getAssociatedObject(self, @selector(accessibilitySelectedChildren)); }
- (void)setAccessibilitySelectedChildren:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilitySelectedChildren), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (id)accessibilityParent { return objc_getAssociatedObject(self, @selector(accessibilityParent)); }
- (void)setAccessibilityParent:(id)v { objc_setAssociatedObject(self, @selector(accessibilityParent), v, OBJC_ASSOCIATION_ASSIGN); }
- (id)accessibilityMinValue { return objc_getAssociatedObject(self, @selector(accessibilityMinValue)); }
- (void)setAccessibilityMinValue:(id)v { objc_setAssociatedObject(self, @selector(accessibilityMinValue), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (id)accessibilityMaxValue { return objc_getAssociatedObject(self, @selector(accessibilityMaxValue)); }
- (void)setAccessibilityMaxValue:(id)v { objc_setAssociatedObject(self, @selector(accessibilityMaxValue), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSArray *)accessibilityRows { return objc_getAssociatedObject(self, @selector(accessibilityRows)); }
- (void)setAccessibilityRows:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityRows), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilitySelectedRows { return objc_getAssociatedObject(self, @selector(accessibilitySelectedRows)); }
- (void)setAccessibilitySelectedRows:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilitySelectedRows), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilityVisibleRows { return objc_getAssociatedObject(self, @selector(accessibilityVisibleRows)); }
- (void)setAccessibilityVisibleRows:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityVisibleRows), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilitySelectedText { return objc_getAssociatedObject(self, @selector(accessibilitySelectedText)); }
- (void)setAccessibilitySelectedText:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilitySelectedText), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSNumber *)accessibilityOrientation { return objc_getAssociatedObject(self, @selector(accessibilityOrientation)); }
- (void)setAccessibilityOrientation:(NSNumber *)v { objc_setAssociatedObject(self, @selector(accessibilityOrientation), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSNumber *)accessibilityIndex { return objc_getAssociatedObject(self, @selector(accessibilityIndex)); }
- (void)setAccessibilityIndex:(NSNumber *)v { objc_setAssociatedObject(self, @selector(accessibilityIndex), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityElement {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityElement));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityElement:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityElement), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityEnabled {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityEnabled));
    return v ? v.boolValue : YES;
}
- (void)setAccessibilityEnabled:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityEnabled), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityHidden {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityHidden));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityHidden:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityHidden), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilitySelected {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilitySelected));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilitySelected:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilitySelected), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityFocused {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityFocused));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityFocused:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityFocused), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityExpanded {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityExpanded));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityExpanded:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityExpanded), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSRect)accessibilityFrame { return NSZeroRect; }
- (BOOL)accessibilityPerformPress { return NO; }
- (BOOL)accessibilityPerformIncrement { return NO; }
- (BOOL)accessibilityPerformDecrement { return NO; }
- (id)accessibilityHitTest:(NSPoint)p { return self; }
- (id)accessibilityFocusedUIElement { return self; }
- (BOOL)isAccessibilityBridgeActive { return NO; }
@end

@implementation NSMenuItem (BittenAccessibility)
- (NSString *)accessibilityLabel { return objc_getAssociatedObject(self, @selector(accessibilityLabel)); }
- (void)setAccessibilityLabel:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityLabel), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityTitle { return objc_getAssociatedObject(self, @selector(accessibilityTitle)); }
- (void)setAccessibilityTitle:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityTitle), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityHelp { return objc_getAssociatedObject(self, @selector(accessibilityHelp)); }
- (void)setAccessibilityHelp:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityHelp), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (id)accessibilityValue { return objc_getAssociatedObject(self, @selector(accessibilityValue)); }
- (void)setAccessibilityValue:(id)v { objc_setAssociatedObject(self, @selector(accessibilityValue), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSAccessibilityRole)accessibilityRole { return objc_getAssociatedObject(self, @selector(accessibilityRole)); }
- (void)setAccessibilityRole:(NSAccessibilityRole)v { objc_setAssociatedObject(self, @selector(accessibilityRole), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilitySubrole { return objc_getAssociatedObject(self, @selector(accessibilitySubrole)); }
- (void)setAccessibilitySubrole:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilitySubrole), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityRoleDescription { return objc_getAssociatedObject(self, @selector(accessibilityRoleDescription)); }
- (void)setAccessibilityRoleDescription:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityRoleDescription), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityIdentifier { return objc_getAssociatedObject(self, @selector(accessibilityIdentifier)); }
- (void)setAccessibilityIdentifier:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityIdentifier), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityPlaceholderValue { return objc_getAssociatedObject(self, @selector(accessibilityPlaceholderValue)); }
- (void)setAccessibilityPlaceholderValue:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityPlaceholderValue), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityValueDescription { return objc_getAssociatedObject(self, @selector(accessibilityValueDescription)); }
- (void)setAccessibilityValueDescription:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityValueDescription), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilityChildren { return objc_getAssociatedObject(self, @selector(accessibilityChildren)); }
- (void)setAccessibilityChildren:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityChildren), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilityCustomActions { return objc_getAssociatedObject(self, @selector(accessibilityCustomActions)); }
- (void)setAccessibilityCustomActions:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityCustomActions), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilitySelectedChildren { return objc_getAssociatedObject(self, @selector(accessibilitySelectedChildren)); }
- (void)setAccessibilitySelectedChildren:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilitySelectedChildren), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (id)accessibilityParent { return objc_getAssociatedObject(self, @selector(accessibilityParent)); }
- (void)setAccessibilityParent:(id)v { objc_setAssociatedObject(self, @selector(accessibilityParent), v, OBJC_ASSOCIATION_ASSIGN); }
- (id)accessibilityMinValue { return objc_getAssociatedObject(self, @selector(accessibilityMinValue)); }
- (void)setAccessibilityMinValue:(id)v { objc_setAssociatedObject(self, @selector(accessibilityMinValue), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (id)accessibilityMaxValue { return objc_getAssociatedObject(self, @selector(accessibilityMaxValue)); }
- (void)setAccessibilityMaxValue:(id)v { objc_setAssociatedObject(self, @selector(accessibilityMaxValue), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSArray *)accessibilityRows { return objc_getAssociatedObject(self, @selector(accessibilityRows)); }
- (void)setAccessibilityRows:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityRows), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilitySelectedRows { return objc_getAssociatedObject(self, @selector(accessibilitySelectedRows)); }
- (void)setAccessibilitySelectedRows:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilitySelectedRows), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilityVisibleRows { return objc_getAssociatedObject(self, @selector(accessibilityVisibleRows)); }
- (void)setAccessibilityVisibleRows:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityVisibleRows), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilitySelectedText { return objc_getAssociatedObject(self, @selector(accessibilitySelectedText)); }
- (void)setAccessibilitySelectedText:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilitySelectedText), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSNumber *)accessibilityOrientation { return objc_getAssociatedObject(self, @selector(accessibilityOrientation)); }
- (void)setAccessibilityOrientation:(NSNumber *)v { objc_setAssociatedObject(self, @selector(accessibilityOrientation), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSNumber *)accessibilityIndex { return objc_getAssociatedObject(self, @selector(accessibilityIndex)); }
- (void)setAccessibilityIndex:(NSNumber *)v { objc_setAssociatedObject(self, @selector(accessibilityIndex), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityElement {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityElement));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityElement:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityElement), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityEnabled {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityEnabled));
    return v ? v.boolValue : YES;
}
- (void)setAccessibilityEnabled:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityEnabled), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityHidden {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityHidden));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityHidden:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityHidden), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilitySelected {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilitySelected));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilitySelected:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilitySelected), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityFocused {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityFocused));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityFocused:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityFocused), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityExpanded {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityExpanded));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityExpanded:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityExpanded), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSRect)accessibilityFrame { return NSZeroRect; }
- (BOOL)accessibilityPerformPress { return NO; }
- (BOOL)accessibilityPerformIncrement { return NO; }
- (BOOL)accessibilityPerformDecrement { return NO; }
- (id)accessibilityHitTest:(NSPoint)p { return self; }
- (id)accessibilityFocusedUIElement { return self; }
- (BOOL)isAccessibilityBridgeActive { return NO; }
@end

@implementation NSMenu (BittenAccessibility)
- (NSString *)accessibilityLabel { return objc_getAssociatedObject(self, @selector(accessibilityLabel)); }
- (void)setAccessibilityLabel:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityLabel), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityTitle { return objc_getAssociatedObject(self, @selector(accessibilityTitle)); }
- (void)setAccessibilityTitle:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityTitle), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityHelp { return objc_getAssociatedObject(self, @selector(accessibilityHelp)); }
- (void)setAccessibilityHelp:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityHelp), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (id)accessibilityValue { return objc_getAssociatedObject(self, @selector(accessibilityValue)); }
- (void)setAccessibilityValue:(id)v { objc_setAssociatedObject(self, @selector(accessibilityValue), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSAccessibilityRole)accessibilityRole { return objc_getAssociatedObject(self, @selector(accessibilityRole)); }
- (void)setAccessibilityRole:(NSAccessibilityRole)v { objc_setAssociatedObject(self, @selector(accessibilityRole), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilitySubrole { return objc_getAssociatedObject(self, @selector(accessibilitySubrole)); }
- (void)setAccessibilitySubrole:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilitySubrole), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityRoleDescription { return objc_getAssociatedObject(self, @selector(accessibilityRoleDescription)); }
- (void)setAccessibilityRoleDescription:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityRoleDescription), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityIdentifier { return objc_getAssociatedObject(self, @selector(accessibilityIdentifier)); }
- (void)setAccessibilityIdentifier:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityIdentifier), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityPlaceholderValue { return objc_getAssociatedObject(self, @selector(accessibilityPlaceholderValue)); }
- (void)setAccessibilityPlaceholderValue:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityPlaceholderValue), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityValueDescription { return objc_getAssociatedObject(self, @selector(accessibilityValueDescription)); }
- (void)setAccessibilityValueDescription:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityValueDescription), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilityChildren { return objc_getAssociatedObject(self, @selector(accessibilityChildren)); }
- (void)setAccessibilityChildren:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityChildren), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilityCustomActions { return objc_getAssociatedObject(self, @selector(accessibilityCustomActions)); }
- (void)setAccessibilityCustomActions:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityCustomActions), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilitySelectedChildren { return objc_getAssociatedObject(self, @selector(accessibilitySelectedChildren)); }
- (void)setAccessibilitySelectedChildren:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilitySelectedChildren), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (id)accessibilityParent { return objc_getAssociatedObject(self, @selector(accessibilityParent)); }
- (void)setAccessibilityParent:(id)v { objc_setAssociatedObject(self, @selector(accessibilityParent), v, OBJC_ASSOCIATION_ASSIGN); }
- (id)accessibilityMinValue { return objc_getAssociatedObject(self, @selector(accessibilityMinValue)); }
- (void)setAccessibilityMinValue:(id)v { objc_setAssociatedObject(self, @selector(accessibilityMinValue), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (id)accessibilityMaxValue { return objc_getAssociatedObject(self, @selector(accessibilityMaxValue)); }
- (void)setAccessibilityMaxValue:(id)v { objc_setAssociatedObject(self, @selector(accessibilityMaxValue), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSArray *)accessibilityRows { return objc_getAssociatedObject(self, @selector(accessibilityRows)); }
- (void)setAccessibilityRows:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityRows), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilitySelectedRows { return objc_getAssociatedObject(self, @selector(accessibilitySelectedRows)); }
- (void)setAccessibilitySelectedRows:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilitySelectedRows), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilityVisibleRows { return objc_getAssociatedObject(self, @selector(accessibilityVisibleRows)); }
- (void)setAccessibilityVisibleRows:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityVisibleRows), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilitySelectedText { return objc_getAssociatedObject(self, @selector(accessibilitySelectedText)); }
- (void)setAccessibilitySelectedText:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilitySelectedText), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSNumber *)accessibilityOrientation { return objc_getAssociatedObject(self, @selector(accessibilityOrientation)); }
- (void)setAccessibilityOrientation:(NSNumber *)v { objc_setAssociatedObject(self, @selector(accessibilityOrientation), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSNumber *)accessibilityIndex { return objc_getAssociatedObject(self, @selector(accessibilityIndex)); }
- (void)setAccessibilityIndex:(NSNumber *)v { objc_setAssociatedObject(self, @selector(accessibilityIndex), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityElement {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityElement));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityElement:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityElement), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityEnabled {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityEnabled));
    return v ? v.boolValue : YES;
}
- (void)setAccessibilityEnabled:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityEnabled), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityHidden {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityHidden));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityHidden:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityHidden), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilitySelected {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilitySelected));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilitySelected:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilitySelected), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityFocused {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityFocused));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityFocused:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityFocused), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityExpanded {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityExpanded));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityExpanded:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityExpanded), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSRect)accessibilityFrame { return NSZeroRect; }
- (BOOL)accessibilityPerformPress { return NO; }
- (BOOL)accessibilityPerformIncrement { return NO; }
- (BOOL)accessibilityPerformDecrement { return NO; }
- (id)accessibilityHitTest:(NSPoint)p { return self; }
- (id)accessibilityFocusedUIElement { return self; }
- (BOOL)isAccessibilityBridgeActive { return NO; }
@end

@implementation NSCell (BittenAccessibility)
- (NSString *)accessibilityLabel { return objc_getAssociatedObject(self, @selector(accessibilityLabel)); }
- (void)setAccessibilityLabel:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityLabel), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityTitle { return objc_getAssociatedObject(self, @selector(accessibilityTitle)); }
- (void)setAccessibilityTitle:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityTitle), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityHelp { return objc_getAssociatedObject(self, @selector(accessibilityHelp)); }
- (void)setAccessibilityHelp:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityHelp), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (id)accessibilityValue { return objc_getAssociatedObject(self, @selector(accessibilityValue)); }
- (void)setAccessibilityValue:(id)v { objc_setAssociatedObject(self, @selector(accessibilityValue), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSAccessibilityRole)accessibilityRole { return objc_getAssociatedObject(self, @selector(accessibilityRole)); }
- (void)setAccessibilityRole:(NSAccessibilityRole)v { objc_setAssociatedObject(self, @selector(accessibilityRole), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilitySubrole { return objc_getAssociatedObject(self, @selector(accessibilitySubrole)); }
- (void)setAccessibilitySubrole:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilitySubrole), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityRoleDescription { return objc_getAssociatedObject(self, @selector(accessibilityRoleDescription)); }
- (void)setAccessibilityRoleDescription:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityRoleDescription), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityIdentifier { return objc_getAssociatedObject(self, @selector(accessibilityIdentifier)); }
- (void)setAccessibilityIdentifier:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityIdentifier), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityPlaceholderValue { return objc_getAssociatedObject(self, @selector(accessibilityPlaceholderValue)); }
- (void)setAccessibilityPlaceholderValue:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityPlaceholderValue), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilityValueDescription { return objc_getAssociatedObject(self, @selector(accessibilityValueDescription)); }
- (void)setAccessibilityValueDescription:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilityValueDescription), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilityChildren { return objc_getAssociatedObject(self, @selector(accessibilityChildren)); }
- (void)setAccessibilityChildren:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityChildren), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilityCustomActions { return objc_getAssociatedObject(self, @selector(accessibilityCustomActions)); }
- (void)setAccessibilityCustomActions:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityCustomActions), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilitySelectedChildren { return objc_getAssociatedObject(self, @selector(accessibilitySelectedChildren)); }
- (void)setAccessibilitySelectedChildren:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilitySelectedChildren), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (id)accessibilityParent { return objc_getAssociatedObject(self, @selector(accessibilityParent)); }
- (void)setAccessibilityParent:(id)v { objc_setAssociatedObject(self, @selector(accessibilityParent), v, OBJC_ASSOCIATION_ASSIGN); }
- (id)accessibilityMinValue { return objc_getAssociatedObject(self, @selector(accessibilityMinValue)); }
- (void)setAccessibilityMinValue:(id)v { objc_setAssociatedObject(self, @selector(accessibilityMinValue), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (id)accessibilityMaxValue { return objc_getAssociatedObject(self, @selector(accessibilityMaxValue)); }
- (void)setAccessibilityMaxValue:(id)v { objc_setAssociatedObject(self, @selector(accessibilityMaxValue), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSArray *)accessibilityRows { return objc_getAssociatedObject(self, @selector(accessibilityRows)); }
- (void)setAccessibilityRows:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityRows), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilitySelectedRows { return objc_getAssociatedObject(self, @selector(accessibilitySelectedRows)); }
- (void)setAccessibilitySelectedRows:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilitySelectedRows), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray *)accessibilityVisibleRows { return objc_getAssociatedObject(self, @selector(accessibilityVisibleRows)); }
- (void)setAccessibilityVisibleRows:(NSArray *)v { objc_setAssociatedObject(self, @selector(accessibilityVisibleRows), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)accessibilitySelectedText { return objc_getAssociatedObject(self, @selector(accessibilitySelectedText)); }
- (void)setAccessibilitySelectedText:(NSString *)v { objc_setAssociatedObject(self, @selector(accessibilitySelectedText), v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSNumber *)accessibilityOrientation { return objc_getAssociatedObject(self, @selector(accessibilityOrientation)); }
- (void)setAccessibilityOrientation:(NSNumber *)v { objc_setAssociatedObject(self, @selector(accessibilityOrientation), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSNumber *)accessibilityIndex { return objc_getAssociatedObject(self, @selector(accessibilityIndex)); }
- (void)setAccessibilityIndex:(NSNumber *)v { objc_setAssociatedObject(self, @selector(accessibilityIndex), v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityElement {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityElement));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityElement:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityElement), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityEnabled {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityEnabled));
    return v ? v.boolValue : YES;
}
- (void)setAccessibilityEnabled:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityEnabled), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityHidden {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityHidden));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityHidden:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityHidden), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilitySelected {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilitySelected));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilitySelected:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilitySelected), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityFocused {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityFocused));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityFocused:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityFocused), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isAccessibilityExpanded {
    NSNumber *v = objc_getAssociatedObject(self, @selector(isAccessibilityExpanded));
    return v ? v.boolValue : NO;
}
- (void)setAccessibilityExpanded:(BOOL)v { objc_setAssociatedObject(self, @selector(isAccessibilityExpanded), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSRect)accessibilityFrame { return NSZeroRect; }
- (BOOL)accessibilityPerformPress { return NO; }
- (BOOL)accessibilityPerformIncrement { return NO; }
- (BOOL)accessibilityPerformDecrement { return NO; }
- (id)accessibilityHitTest:(NSPoint)p { return self; }
- (id)accessibilityFocusedUIElement { return self; }
- (BOOL)isAccessibilityBridgeActive { return NO; }
@end
