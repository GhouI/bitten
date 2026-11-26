/* bitten SDK: UserNotifications. Written from the public documentation;
 * the implementation is frameworks/UserNotifications. */
#ifndef BITTEN_USERNOTIFICATIONS_H
#define BITTEN_USERNOTIFICATIONS_H
#import <Foundation/Foundation.h>

#pragma clang assume_nonnull begin
@class NSDateComponents;

typedef NS_OPTIONS(NSUInteger, UNAuthorizationOptions) {
    UNAuthorizationOptionBadge = 1 << 0, UNAuthorizationOptionSound = 1 << 1, UNAuthorizationOptionAlert = 1 << 2,
    UNAuthorizationOptionCarPlay = 1 << 3, UNAuthorizationOptionCriticalAlert = 1 << 4,
    UNAuthorizationOptionProvidesAppNotificationSettings = 1 << 5, UNAuthorizationOptionProvisional = 1 << 6,
};
typedef NS_ENUM(NSInteger, UNAuthorizationStatus) {
    UNAuthorizationStatusNotDetermined = 0, UNAuthorizationStatusDenied, UNAuthorizationStatusAuthorized,
    UNAuthorizationStatusProvisional, UNAuthorizationStatusEphemeral,
};
typedef NS_ENUM(NSInteger, UNNotificationSetting) {
    UNNotificationSettingNotSupported = 0, UNNotificationSettingDisabled, UNNotificationSettingEnabled,
};
typedef NS_ENUM(NSInteger, UNAlertStyle) { UNAlertStyleNone = 0, UNAlertStyleBanner, UNAlertStyleAlert };
typedef NS_OPTIONS(NSUInteger, UNNotificationPresentationOptions) {
    UNNotificationPresentationOptionBadge = 1 << 0, UNNotificationPresentationOptionSound = 1 << 1,
    UNNotificationPresentationOptionAlert = 1 << 2, UNNotificationPresentationOptionList = 1 << 3,
    UNNotificationPresentationOptionBanner = 1 << 4,
};
typedef NS_OPTIONS(NSUInteger, UNNotificationActionOptions) {
    UNNotificationActionOptionAuthenticationRequired = 1 << 0, UNNotificationActionOptionDestructive = 1 << 1,
    UNNotificationActionOptionForeground = 1 << 2,
};
typedef NS_OPTIONS(NSUInteger, UNNotificationCategoryOptions) {
    UNNotificationCategoryOptionCustomDismissAction = 1 << 0, UNNotificationCategoryOptionAllowInCarPlay = 1 << 1,
    UNNotificationCategoryOptionHiddenPreviewsShowTitle = 1 << 2,
    UNNotificationCategoryOptionHiddenPreviewsShowSubtitle = 1 << 3, UNNotificationCategoryOptionAllowAnnouncement = 1 << 4,
};
typedef NS_ENUM(NSUInteger, UNNotificationInterruptionLevel) {
    UNNotificationInterruptionLevelPassive = 0, UNNotificationInterruptionLevelActive,
    UNNotificationInterruptionLevelTimeSensitive, UNNotificationInterruptionLevelCritical,
};

extern NSString *const UNNotificationDefaultActionIdentifier;
extern NSString *const UNNotificationDismissActionIdentifier;
extern NSString *const UNErrorDomain;

@interface UNNotificationSound : NSObject <NSCopying>
@property (class, readonly, copy) UNNotificationSound *defaultSound;
@property (class, readonly, copy) UNNotificationSound *defaultCriticalSound;
+ (instancetype)soundNamed:(NSString *)name;
+ (instancetype)criticalSoundNamed:(NSString *)name;
@end

@interface UNNotificationAttachment : NSObject <NSCopying>
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSURL *URL;
@property (readonly, copy) NSString *type;
+ (nullable instancetype)attachmentWithIdentifier:(NSString *)identifier URL:(NSURL *)URL
                                          options:(nullable NSDictionary *)options error:(NSError **)error;
@end

@interface UNNotificationContent : NSObject <NSCopying, NSMutableCopying>
@property (readonly, copy) NSString *title, *subtitle, *body, *categoryIdentifier, *threadIdentifier;
@property (readonly, copy, nullable) NSNumber *badge;
@property (readonly, copy, nullable) UNNotificationSound *sound;
@property (readonly, copy) NSDictionary *userInfo;
@property (readonly, copy) NSArray<UNNotificationAttachment *> *attachments;
@property (readonly, copy, nullable) NSString *targetContentIdentifier;
@property (readonly) UNNotificationInterruptionLevel interruptionLevel;
@property (readonly) double relevanceScore;
@property (readonly, copy, nullable) NSString *filterCriteria;
@end

@interface UNMutableNotificationContent : UNNotificationContent
@property (copy) NSString *title, *subtitle, *body, *categoryIdentifier, *threadIdentifier;
@property (copy, nullable) NSNumber *badge;
@property (copy, nullable) UNNotificationSound *sound;
@property (copy) NSDictionary *userInfo;
@property (copy) NSArray<UNNotificationAttachment *> *attachments;
@property (copy, nullable) NSString *targetContentIdentifier;
@property UNNotificationInterruptionLevel interruptionLevel;
@property double relevanceScore;
@property (copy, nullable) NSString *filterCriteria;
@end

@interface UNNotificationTrigger : NSObject <NSCopying>
@property (readonly) BOOL repeats;
@end
@interface UNPushNotificationTrigger : UNNotificationTrigger
@end
@interface UNTimeIntervalNotificationTrigger : UNNotificationTrigger
@property (readonly) NSTimeInterval timeInterval;
+ (instancetype)triggerWithTimeInterval:(NSTimeInterval)timeInterval repeats:(BOOL)repeats;
- (nullable NSDate *)nextTriggerDate;
@end
@interface UNCalendarNotificationTrigger : UNNotificationTrigger
@property (readonly, copy) NSDateComponents *dateComponents;
+ (instancetype)triggerWithDateMatchingComponents:(NSDateComponents *)dateComponents repeats:(BOOL)repeats;
@end

@interface UNNotificationRequest : NSObject <NSCopying>
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) UNNotificationContent *content;
@property (readonly, copy, nullable) UNNotificationTrigger *trigger;
+ (instancetype)requestWithIdentifier:(NSString *)identifier content:(UNNotificationContent *)content
                              trigger:(nullable UNNotificationTrigger *)trigger;
@end

@interface UNNotification : NSObject <NSCopying>
@property (readonly, copy) NSDate *date;
@property (readonly, copy) UNNotificationRequest *request;
@end

@interface UNNotificationResponse : NSObject <NSCopying>
@property (readonly, copy) UNNotification *notification;
@property (readonly, copy) NSString *actionIdentifier;
@end

@interface UNNotificationAction : NSObject <NSCopying>
@property (readonly, copy) NSString *identifier, *title;
@property (readonly) UNNotificationActionOptions options;
+ (instancetype)actionWithIdentifier:(NSString *)identifier title:(NSString *)title
                             options:(UNNotificationActionOptions)options;
@end
@interface UNTextInputNotificationAction : UNNotificationAction
@property (readonly, copy) NSString *textInputButtonTitle, *textInputPlaceholder;
+ (instancetype)actionWithIdentifier:(NSString *)identifier title:(NSString *)title
                             options:(UNNotificationActionOptions)options
                textInputButtonTitle:(NSString *)textInputButtonTitle
                textInputPlaceholder:(NSString *)textInputPlaceholder;
@end

@interface UNNotificationCategory : NSObject <NSCopying>
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSArray<UNNotificationAction *> *actions;
@property (readonly, copy) NSArray<NSString *> *intentIdentifiers;
@property (readonly) UNNotificationCategoryOptions options;
+ (instancetype)categoryWithIdentifier:(NSString *)identifier actions:(NSArray<UNNotificationAction *> *)actions
                     intentIdentifiers:(NSArray<NSString *> *)intentIdentifiers
                               options:(UNNotificationCategoryOptions)options;
@end

@interface UNNotificationSettings : NSObject <NSCopying>
@property (readonly) UNAuthorizationStatus authorizationStatus;
@property (readonly) UNNotificationSetting soundSetting, badgeSetting, alertSetting, notificationCenterSetting,
    lockScreenSetting, carPlaySetting, criticalAlertSetting, announcementSetting, timeSensitiveSetting,
    scheduledDeliverySetting, directMessagesSetting;
@property (readonly) UNAlertStyle alertStyle;
@property (readonly) BOOL providesAppNotificationSettings;
@end

@class UNUserNotificationCenter;
@protocol UNUserNotificationCenterDelegate <NSObject>
@optional
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler;
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler;
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    openSettingsForNotification:(nullable UNNotification *)notification;
@end

@interface UNUserNotificationCenter : NSObject
@property (nullable, weak) id<UNUserNotificationCenterDelegate> delegate;
@property (readonly) BOOL supportsContentExtensions;
+ (UNUserNotificationCenter *)currentNotificationCenter;
- (void)requestAuthorizationWithOptions:(UNAuthorizationOptions)options
                      completionHandler:(void (^)(BOOL granted, NSError *_Nullable error))completionHandler;
- (void)setNotificationCategories:(NSSet<UNNotificationCategory *> *)categories;
- (void)getNotificationCategoriesWithCompletionHandler:(void (^)(NSSet<UNNotificationCategory *> *categories))completionHandler;
- (void)getNotificationSettingsWithCompletionHandler:(void (^)(UNNotificationSettings *settings))completionHandler;
- (void)addNotificationRequest:(UNNotificationRequest *)request
         withCompletionHandler:(nullable void (^)(NSError *_Nullable error))completionHandler;
- (void)getPendingNotificationRequestsWithCompletionHandler:(void (^)(NSArray<UNNotificationRequest *> *requests))completionHandler;
- (void)removePendingNotificationRequestsWithIdentifiers:(NSArray<NSString *> *)identifiers;
- (void)removeAllPendingNotificationRequests;
- (void)getDeliveredNotificationsWithCompletionHandler:(void (^)(NSArray<UNNotification *> *notifications))completionHandler;
- (void)removeDeliveredNotificationsWithIdentifiers:(NSArray<NSString *> *)identifiers;
- (void)removeAllDeliveredNotifications;
- (void)setBadgeCount:(NSInteger)newBadgeCount withCompletionHandler:(nullable void (^)(NSError *_Nullable error))completionHandler;
@end

#pragma clang assume_nonnull end
#endif
