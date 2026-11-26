/* NSViewController and NSWindowController: a view loaded on first use
 * (there are no nib files: loadView makes a plain view unless a subclass
 * provides one), the appearance callbacks, child controllers, and windows
 * that show a controller's view. */
#import <AppKit/AppKit.h>

@implementation NSViewController {
    NSView *_view;
    NSString *_title;
    id _representedObject;
    NSString *_nibName;
    NSBundle *_nibBundle;
    NSSize _preferredContentSize;
    NSMutableArray<NSViewController *> *_children;
    __unsafe_unretained NSViewController *_parent;
}
- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super init])) {
        _nibName = [nibNameOrNil copy];
        _nibBundle = nibBundleOrNil;
        _children = [NSMutableArray array];
    }
    return self;
}
- (instancetype)init { return [self initWithNibName:nil bundle:nil]; }

- (NSView *)view {
    if (!_view) {
        [self loadView];
        if (!_view) _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        [self viewDidLoad];
    }
    return _view;
}
- (void)setView:(NSView *)view { _view = view; }
- (NSView *)viewIfLoaded { return _view; }
- (BOOL)isViewLoaded { return _view != nil; }
- (void)loadView {}
- (void)loadViewIfNeeded { (void)[self view]; }
- (void)viewDidLoad {}
- (void)viewWillAppear {}
- (void)viewDidAppear {}
- (void)viewWillDisappear {}
- (void)viewDidDisappear {}
- (void)viewWillLayout {}
- (void)viewDidLayout {}
- (void)updateViewConstraints {}

- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)title { _title = [title copy]; }
- (id)representedObject { return _representedObject; }
- (void)setRepresentedObject:(id)o { _representedObject = o; }
- (NSString *)nibName { return _nibName; }
- (NSBundle *)nibBundle { return _nibBundle; }
- (NSSize)preferredContentSize { return _preferredContentSize; }
- (void)setPreferredContentSize:(NSSize)s { _preferredContentSize = s; }

- (NSArray<NSViewController *> *)childViewControllers { return [_children copy]; }
- (NSViewController *)parentViewController { return _parent; }
- (void)addChildViewController:(NSViewController *)child {
    [child removeFromParentViewController];
    [_children addObject:child];
    child->_parent = self;
}
- (void)removeFromParentViewController {
    if (!_parent) return;
    [_parent->_children removeObjectIdenticalTo:self];
    _parent = nil;
}
@end

@implementation NSWindow (NSViewControllerContent)
- (NSViewController *)contentViewController { return _contentViewController; }
- (void)setContentViewController:(NSViewController *)controller {
    _contentViewController = controller;
    if (!controller) return;
    NSView *v = controller.view;
    NSSize preferred = controller.preferredContentSize;
    if (preferred.width > 0 && preferred.height > 0) [self setContentSize:preferred];
    self.contentView = v;
    if (controller.title && !self.title.length) self.title = controller.title;
}
@end

@implementation NSWindowController {
    NSWindow *_window;
    NSViewController *_contentViewController;
    NSString *_windowNibName;
    __unsafe_unretained id _owner;
}
- (instancetype)initWithWindow:(NSWindow *)window {
    if ((self = [super init])) _window = window;
    return self;
}
- (instancetype)initWithWindowNibName:(NSString *)windowNibName {
    if ((self = [super init])) _windowNibName = [windowNibName copy];
    return self;
}
- (instancetype)init { return [self initWithWindow:nil]; }
- (NSWindow *)window {
    if (!_window) {
        [self windowWillLoad];
        [self loadWindow];
        if (_window) [self windowDidLoad];
    }
    return _window;
}
- (void)setWindow:(NSWindow *)window { _window = window; }
- (BOOL)isWindowLoaded { return _window != nil; }
- (id)owner { return _owner ?: self; }
- (void)setOwner:(id)owner { _owner = owner; }
- (void)loadWindow {}
- (void)windowWillLoad {}
- (void)windowDidLoad {}
- (NSViewController *)contentViewController { return _contentViewController; }
- (void)setContentViewController:(NSViewController *)controller {
    _contentViewController = controller;
    self.window.contentViewController = controller;
}
- (void)showWindow:(id)sender { [self.window makeKeyAndOrderFront:sender]; }
- (void)close { [_window close]; }
@end
