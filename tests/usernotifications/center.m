// UserNotifications: authorization, settings, categories, delivery with
// and without a time-interval trigger, listing and removing, the delegate.
#import <UserNotifications/UserNotifications.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

static BOOL wait_for(dispatch_semaphore_t s) {
    return dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0;
}

/* Delegate calls arrive on the main queue: run the main run loop while
 * waiting, as an app's main thread would. */
static BOOL wait_main(dispatch_semaphore_t s) {
    for (int i = 0; i < 500; i++) {
        if (dispatch_semaphore_wait(s, DISPATCH_TIME_NOW) == 0) return YES;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return NO;
}

@interface Delegate : NSObject <UNUserNotificationCenterDelegate>
@property (assign) dispatch_semaphore_t presented;   // plain pointers in C here
@property (copy) NSString *lastTitle;
@end
@implementation Delegate
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    self.lastTitle = notification.request.content.title;
    dispatch_semaphore_signal(self.presented);
}
@end

int main(void) {
    UNUserNotificationCenter *c = [UNUserNotificationCenter currentNotificationCenter];
    CHECK(c == [UNUserNotificationCenter currentNotificationCenter]);
    CHECK([UNNotificationDefaultActionIdentifier isEqual:@"com.apple.UNNotificationDefaultActionIdentifier"]);

    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    __block UNAuthorizationStatus status = -1;
    [c getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        status = settings.authorizationStatus;
        dispatch_semaphore_signal(s);
    }];
    CHECK(wait_for(s) && status == UNAuthorizationStatusNotDetermined);
    __block BOOL granted = NO;
    [c requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound
                     completionHandler:^(BOOL ok, NSError *error) { granted = ok && !error; dispatch_semaphore_signal(s); }];
    CHECK(wait_for(s) && granted);
    [c getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        status = settings.authorizationStatus;
        dispatch_semaphore_signal(s);
    }];
    CHECK(wait_for(s) && status == UNAuthorizationStatusAuthorized);

    UNNotificationAction *open = [UNNotificationAction actionWithIdentifier:@"open" title:@"Open"
                                                                    options:UNNotificationActionOptionForeground];
    UNNotificationCategory *cat = [UNNotificationCategory categoryWithIdentifier:@"done" actions:@[open]
                                                               intentIdentifiers:@[] options:0];
    [c setNotificationCategories:[NSSet setWithObject:cat]];
    __block NSUInteger ncat = 0;
    [c getNotificationCategoriesWithCompletionHandler:^(NSSet *cats) { ncat = cats.count; dispatch_semaphore_signal(s); }];
    CHECK(wait_for(s) && ncat == 1);

    Delegate *d = [Delegate new];
    d.presented = dispatch_semaphore_create(0);
    c.delegate = d;

    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = @"Build finished";
    content.body = @"All tests passed";
    content.sound = [UNNotificationSound defaultSound];
    content.categoryIdentifier = @"done";
    CHECK([content.title isEqual:@"Build finished"] && [content.subtitle isEqual:@""]);
    UNNotificationContent *frozen = [content copy];
    content.title = @"changed";
    CHECK([frozen.title isEqual:@"Build finished"]);

    UNNotificationRequest *now = [UNNotificationRequest requestWithIdentifier:@"a" content:frozen trigger:nil];
    __block NSError *addError = (NSError *)@"unset";
    [c addNotificationRequest:now withCompletionHandler:^(NSError *e) { addError = e; dispatch_semaphore_signal(s); }];
    CHECK(wait_for(s) && addError == nil);
    CHECK(wait_main(d.presented) && [d.lastTitle isEqual:@"Build finished"]);

    UNTimeIntervalNotificationTrigger *soon = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.05 repeats:NO];
    content.title = @"Later";
    [c addNotificationRequest:[UNNotificationRequest requestWithIdentifier:@"b" content:content trigger:soon]
        withCompletionHandler:nil];
    __block NSUInteger npending = 0;
    [c getPendingNotificationRequestsWithCompletionHandler:^(NSArray *r) { npending = r.count; dispatch_semaphore_signal(s); }];
    CHECK(wait_for(s) && npending == 1);
    CHECK(wait_main(d.presented) && [d.lastTitle isEqual:@"Later"]);

    __block NSUInteger ndelivered = 0;
    [c getDeliveredNotificationsWithCompletionHandler:^(NSArray *n) { ndelivered = n.count; dispatch_semaphore_signal(s); }];
    CHECK(wait_for(s) && ndelivered == 2);
    [c removeDeliveredNotificationsWithIdentifiers:@[@"a"]];
    [c getDeliveredNotificationsWithCompletionHandler:^(NSArray *n) { ndelivered = n.count; dispatch_semaphore_signal(s); }];
    CHECK(wait_for(s) && ndelivered == 1);
    [c getPendingNotificationRequestsWithCompletionHandler:^(NSArray *r) { npending = r.count; dispatch_semaphore_signal(s); }];
    CHECK(wait_for(s) && npending == 0);
    puts("usernotifications ok");
    return 0;
}
