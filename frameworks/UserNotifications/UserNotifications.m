/* UserNotifications. There is no notification server in a container:
 * authorization is granted (the program asked, and nothing here could
 * refuse), and a delivered notification is written to standard error and
 * kept, so programs that list or remove their notifications see them.
 * Requests with a time-interval trigger are delivered when it fires.
 * Completion handlers run on a global queue, as Apple's do; the delegate
 * hears of each delivery on the main queue. Written from Apple's public
 * documentation. */
#import <UserNotifications/UserNotifications.h>
#include <dispatch/dispatch.h>
#include <stdio.h>

NSString *const UNNotificationDefaultActionIdentifier = @"com.apple.UNNotificationDefaultActionIdentifier";
NSString *const UNNotificationDismissActionIdentifier = @"com.apple.UNNotificationDismissActionIdentifier";
NSString *const UNErrorDomain = @"UNErrorDomain";

static dispatch_queue_t background(void) { return dispatch_get_global_queue(0, 0); }

@interface UNNotificationContent (BittenStorage)
- (void)setValue:(id)v forBNKey:(int)key;
@end

@implementation UNNotificationSound {
    NSString *_name;
    BOOL _critical;
}
+ (instancetype)_soundNamed:(NSString *)name critical:(BOOL)critical {
    UNNotificationSound *s = [self new];
    s->_name = [name copy];
    s->_critical = critical;
    return s;
}
+ (UNNotificationSound *)defaultSound { return [self _soundNamed:@"default" critical:NO]; }
+ (UNNotificationSound *)defaultCriticalSound { return [self _soundNamed:@"default" critical:YES]; }
+ (instancetype)soundNamed:(NSString *)name { return [self _soundNamed:name critical:NO]; }
+ (instancetype)criticalSoundNamed:(NSString *)name { return [self _soundNamed:name critical:YES]; }
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@implementation UNNotificationAttachment
+ (instancetype)attachmentWithIdentifier:(NSString *)identifier URL:(NSURL *)URL options:(NSDictionary *)options
                                   error:(NSError **)error {
    UNNotificationAttachment *a = [self new];
    a->_identifier = identifier.length ? [identifier copy] : [[NSUUID UUID] UUIDString];
    a->_URL = [URL copy];
    a->_type = @"public.data";
    return a;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@implementation UNNotificationContent
- (instancetype)init {
    if ((self = [super init])) {
        _title = _subtitle = _body = _categoryIdentifier = _threadIdentifier = @"";
        _userInfo = @{};
        _attachments = @[];
        _interruptionLevel = UNNotificationInterruptionLevelActive;
    }
    return self;
}
- (void)_bn_copyInto:(UNNotificationContent *)c {
    c->_title = _title; c->_subtitle = _subtitle; c->_body = _body;
    c->_categoryIdentifier = _categoryIdentifier; c->_threadIdentifier = _threadIdentifier;
    c->_badge = _badge; c->_sound = _sound; c->_userInfo = _userInfo; c->_attachments = _attachments;
    c->_targetContentIdentifier = _targetContentIdentifier; c->_interruptionLevel = _interruptionLevel;
    c->_relevanceScore = _relevanceScore; c->_filterCriteria = _filterCriteria;
}
- (id)copyWithZone:(NSZone *)zone {
    UNNotificationContent *c = [UNNotificationContent new];
    [self _bn_copyInto:c];
    return c;
}
- (id)mutableCopyWithZone:(NSZone *)zone {
    UNMutableNotificationContent *c = [UNMutableNotificationContent new];
    [self _bn_copyInto:c];
    return c;
}
@end

@implementation UNMutableNotificationContent
@dynamic title, subtitle, body, categoryIdentifier, threadIdentifier, badge, sound, userInfo, attachments,
    targetContentIdentifier, interruptionLevel, relevanceScore, filterCriteria;
/* The storage is the superclass's; these are its setters. */
- (NSString *)title { return [super title]; }
- (void)setTitle:(NSString *)v { [self setValue:v ?: @"" forBNKey:0]; }
- (NSString *)subtitle { return [super subtitle]; }
- (void)setSubtitle:(NSString *)v { [self setValue:v ?: @"" forBNKey:1]; }
- (NSString *)body { return [super body]; }
- (void)setBody:(NSString *)v { [self setValue:v ?: @"" forBNKey:2]; }
- (NSString *)categoryIdentifier { return [super categoryIdentifier]; }
- (void)setCategoryIdentifier:(NSString *)v { [self setValue:v ?: @"" forBNKey:3]; }
- (NSString *)threadIdentifier { return [super threadIdentifier]; }
- (void)setThreadIdentifier:(NSString *)v { [self setValue:v ?: @"" forBNKey:4]; }
- (NSNumber *)badge { return [super badge]; }
- (void)setBadge:(NSNumber *)v { [self setValue:v forBNKey:5]; }
- (UNNotificationSound *)sound { return [super sound]; }
- (void)setSound:(UNNotificationSound *)v { [self setValue:v forBNKey:6]; }
- (NSDictionary *)userInfo { return [super userInfo]; }
- (void)setUserInfo:(NSDictionary *)v { [self setValue:v ?: @{} forBNKey:7]; }
- (NSArray *)attachments { return [super attachments]; }
- (void)setAttachments:(NSArray *)v { [self setValue:v ?: @[] forBNKey:8]; }
- (NSString *)targetContentIdentifier { return [super targetContentIdentifier]; }
- (void)setTargetContentIdentifier:(NSString *)v { [self setValue:v forBNKey:9]; }
- (NSString *)filterCriteria { return [super filterCriteria]; }
- (void)setFilterCriteria:(NSString *)v { [self setValue:v forBNKey:10]; }
- (UNNotificationInterruptionLevel)interruptionLevel { return [super interruptionLevel]; }
- (void)setInterruptionLevel:(UNNotificationInterruptionLevel)v { [self setValue:@(v) forBNKey:11]; }
- (double)relevanceScore { return [super relevanceScore]; }
- (void)setRelevanceScore:(double)v { [self setValue:@(v) forBNKey:12]; }
@end

@implementation UNNotificationContent (BittenStorage)
- (void)setValue:(id)v forBNKey:(int)key {
    switch (key) {
    case 0: _title = [v copy]; break;
    case 1: _subtitle = [v copy]; break;
    case 2: _body = [v copy]; break;
    case 3: _categoryIdentifier = [v copy]; break;
    case 4: _threadIdentifier = [v copy]; break;
    case 5: _badge = [v copy]; break;
    case 6: _sound = v; break;
    case 7: _userInfo = [v copy]; break;
    case 8: _attachments = [v copy]; break;
    case 9: _targetContentIdentifier = [v copy]; break;
    case 10: _filterCriteria = [v copy]; break;
    case 11: _interruptionLevel = [v unsignedIntegerValue]; break;
    case 12: _relevanceScore = [v doubleValue]; break;
    }
}
@end

@implementation UNNotificationTrigger
- (id)copyWithZone:(NSZone *)zone { return self; }
@end
@implementation UNPushNotificationTrigger
@end
@implementation UNTimeIntervalNotificationTrigger {
    NSTimeInterval _interval;
    BOOL _repeats;
}
+ (instancetype)triggerWithTimeInterval:(NSTimeInterval)timeInterval repeats:(BOOL)repeats {
    UNTimeIntervalNotificationTrigger *t = [self new];
    t->_interval = timeInterval;
    t->_repeats = repeats;
    return t;
}
- (NSTimeInterval)timeInterval { return _interval; }
- (BOOL)repeats { return _repeats; }
- (NSDate *)nextTriggerDate { return [NSDate dateWithTimeIntervalSinceNow:_interval]; }
@end
@implementation UNCalendarNotificationTrigger {
    id _components;
    BOOL _repeats;
}
+ (instancetype)triggerWithDateMatchingComponents:(NSDateComponents *)dateComponents repeats:(BOOL)repeats {
    UNCalendarNotificationTrigger *t = [self new];
    t->_components = dateComponents;
    t->_repeats = repeats;
    return t;
}
- (NSDateComponents *)dateComponents { return _components; }
- (BOOL)repeats { return _repeats; }
@end

@implementation UNNotificationRequest
+ (instancetype)requestWithIdentifier:(NSString *)identifier content:(UNNotificationContent *)content
                              trigger:(UNNotificationTrigger *)trigger {
    UNNotificationRequest *r = [self new];
    r->_identifier = [identifier copy];
    r->_content = [content copy];
    r->_trigger = trigger;
    return r;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@implementation UNNotification
+ (instancetype)_bn_notificationWithRequest:(UNNotificationRequest *)request {
    UNNotification *n = [self new];
    n->_request = request;
    n->_date = [NSDate date];
    return n;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@implementation UNNotificationResponse
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@implementation UNNotificationAction
+ (instancetype)actionWithIdentifier:(NSString *)identifier title:(NSString *)title
                             options:(UNNotificationActionOptions)options {
    UNNotificationAction *a = [self new];
    a->_identifier = [identifier copy];
    a->_title = [title copy];
    a->_options = options;
    return a;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
@end
@implementation UNTextInputNotificationAction
+ (instancetype)actionWithIdentifier:(NSString *)identifier title:(NSString *)title
                             options:(UNNotificationActionOptions)options
                textInputButtonTitle:(NSString *)button textInputPlaceholder:(NSString *)placeholder {
    UNTextInputNotificationAction *a = [self actionWithIdentifier:identifier title:title options:options];
    a->_textInputButtonTitle = [button copy];
    a->_textInputPlaceholder = [placeholder copy];
    return a;
}
@end

@implementation UNNotificationCategory
+ (instancetype)categoryWithIdentifier:(NSString *)identifier actions:(NSArray *)actions
                     intentIdentifiers:(NSArray *)intentIdentifiers options:(UNNotificationCategoryOptions)options {
    UNNotificationCategory *c = [self new];
    c->_identifier = [identifier copy];
    c->_actions = [actions copy] ?: @[];
    c->_intentIdentifiers = [intentIdentifiers copy] ?: @[];
    c->_options = options;
    return c;
}
- (NSUInteger)hash { return _identifier.hash; }
- (BOOL)isEqual:(id)o {
    return [o isKindOfClass:[UNNotificationCategory class]] && [((UNNotificationCategory *)o).identifier isEqual:_identifier];
}
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@implementation UNNotificationSettings
+ (instancetype)_bn_settingsAuthorized:(BOOL)authorized {
    UNNotificationSettings *s = [self new];
    UNNotificationSetting on = authorized ? UNNotificationSettingEnabled : UNNotificationSettingDisabled;
    s->_authorizationStatus = authorized ? UNAuthorizationStatusAuthorized : UNAuthorizationStatusNotDetermined;
    s->_soundSetting = s->_badgeSetting = s->_alertSetting = s->_notificationCenterSetting = on;
    s->_lockScreenSetting = s->_timeSensitiveSetting = on;
    s->_carPlaySetting = s->_criticalAlertSetting = s->_announcementSetting = UNNotificationSettingNotSupported;
    s->_scheduledDeliverySetting = s->_directMessagesSetting = UNNotificationSettingNotSupported;
    s->_alertStyle = authorized ? UNAlertStyleBanner : UNAlertStyleNone;
    return s;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@implementation UNUserNotificationCenter {
    NSMutableDictionary<NSString *, UNNotificationRequest *> *_pending;
    NSMutableArray<UNNotification *> *_delivered;
    NSSet<UNNotificationCategory *> *_categories;
    BOOL _authorized;
}

+ (UNUserNotificationCenter *)currentNotificationCenter {
    static UNUserNotificationCenter *center;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        center = [UNUserNotificationCenter new];
        center->_pending = [NSMutableDictionary dictionary];
        center->_delivered = [NSMutableArray array];
        center->_categories = [NSSet set];
    });
    return center;
}

- (BOOL)supportsContentExtensions { return NO; }

- (void)requestAuthorizationWithOptions:(UNAuthorizationOptions)options
                      completionHandler:(void (^)(BOOL, NSError *))completionHandler {
    @synchronized(self) { _authorized = YES; }
    if (completionHandler) dispatch_async(background(), ^{ completionHandler(YES, nil); });
}

- (void)getNotificationSettingsWithCompletionHandler:(void (^)(UNNotificationSettings *))completionHandler {
    BOOL authorized;
    @synchronized(self) { authorized = _authorized; }
    UNNotificationSettings *s = [UNNotificationSettings _bn_settingsAuthorized:authorized];
    if (completionHandler) dispatch_async(background(), ^{ completionHandler(s); });
}

- (void)setNotificationCategories:(NSSet<UNNotificationCategory *> *)categories {
    @synchronized(self) { _categories = [categories copy] ?: [NSSet set]; }
}

- (void)getNotificationCategoriesWithCompletionHandler:(void (^)(NSSet<UNNotificationCategory *> *))completionHandler {
    NSSet *c;
    @synchronized(self) { c = _categories; }
    if (completionHandler) dispatch_async(background(), ^{ completionHandler(c); });
}

- (void)_bn_deliver:(UNNotificationRequest *)request {
    UNNotification *n = [UNNotification _bn_notificationWithRequest:request];
    @synchronized(self) {
        if (!_pending[request.identifier] && request.trigger) return;   /* removed before it fired */
        if (![request.trigger repeats]) [_pending removeObjectForKey:request.identifier];
        NSUInteger i = [_delivered indexOfObjectPassingTest:^BOOL(UNNotification *d, NSUInteger idx, BOOL *stop) {
            return [d.request.identifier isEqual:request.identifier];
        }];
        if (i != NSNotFound) [_delivered removeObjectAtIndex:i];
        [_delivered addObject:n];
    }
    UNNotificationContent *c = request.content;
    fprintf(stderr, "notification: %s%s%s%s%s\n", c.title.UTF8String, c.subtitle.length ? " - " : "",
            c.subtitle.UTF8String, c.body.length ? ": " : "", c.body.UTF8String);
    id<UNUserNotificationCenterDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(userNotificationCenter:willPresentNotification:withCompletionHandler:)])
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate userNotificationCenter:self willPresentNotification:n
                       withCompletionHandler:^(UNNotificationPresentationOptions options) {}];
        });
    UNNotificationTrigger *t = request.trigger;
    if ([t isKindOfClass:[UNTimeIntervalNotificationTrigger class]] && t.repeats) [self _bn_schedule:request];
}

- (void)_bn_schedule:(UNNotificationRequest *)request {
    NSTimeInterval s = [(UNTimeIntervalNotificationTrigger *)request.trigger timeInterval];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), background(), ^{
        [self _bn_deliver:request];
    });
}

- (void)addNotificationRequest:(UNNotificationRequest *)request withCompletionHandler:(void (^)(NSError *))completionHandler {
    UNNotificationTrigger *t = request.trigger;
    if ([t isKindOfClass:[UNTimeIntervalNotificationTrigger class]]) {
        @synchronized(self) { _pending[request.identifier] = request; }
        [self _bn_schedule:request];
    } else if (t && ![t isKindOfClass:[UNPushNotificationTrigger class]]) {
        @synchronized(self) { _pending[request.identifier] = request; }   /* calendar: kept, not fired */
    } else {
        [self _bn_deliver:request];
    }
    if (completionHandler) dispatch_async(background(), ^{ completionHandler(nil); });
}

- (void)getPendingNotificationRequestsWithCompletionHandler:(void (^)(NSArray<UNNotificationRequest *> *))completionHandler {
    NSArray *a;
    @synchronized(self) { a = _pending.allValues; }
    if (completionHandler) dispatch_async(background(), ^{ completionHandler(a); });
}

- (void)removePendingNotificationRequestsWithIdentifiers:(NSArray<NSString *> *)identifiers {
    @synchronized(self) {
        for (NSString *i in identifiers) [_pending removeObjectForKey:i];
    }
}

- (void)removeAllPendingNotificationRequests {
    @synchronized(self) { [_pending removeAllObjects]; }
}

- (void)getDeliveredNotificationsWithCompletionHandler:(void (^)(NSArray<UNNotification *> *))completionHandler {
    NSArray *a;
    @synchronized(self) { a = [_delivered copy]; }
    if (completionHandler) dispatch_async(background(), ^{ completionHandler(a); });
}

- (void)removeDeliveredNotificationsWithIdentifiers:(NSArray<NSString *> *)identifiers {
    @synchronized(self) {
        NSMutableArray *kept = [NSMutableArray array];
        for (UNNotification *n in _delivered)
            if (![identifiers containsObject:n.request.identifier]) [kept addObject:n];
        _delivered = kept;
    }
}

- (void)removeAllDeliveredNotifications {
    @synchronized(self) { [_delivered removeAllObjects]; }
}

- (void)setBadgeCount:(NSInteger)newBadgeCount withCompletionHandler:(void (^)(NSError *))completionHandler {
    if (completionHandler) dispatch_async(background(), ^{ completionHandler(nil); });
}
@end
