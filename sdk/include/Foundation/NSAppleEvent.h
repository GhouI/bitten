/* bitten SDK: Apple event descriptors and the Apple event manager, and the
 * Cocoa scripting classes (script commands, class descriptions, object
 * specifiers). Included from Foundation.h. */
#ifndef BITTEN_FOUNDATION_NSAPPLEEVENT_H
#define BITTEN_FOUNDATION_NSAPPLEEVENT_H

#include <sys/types.h>

#pragma clang assume_nonnull begin

typedef uint32_t FourCharCode;
typedef uint32_t OSType;
typedef int32_t SInt32;
typedef FourCharCode DescType;
typedef FourCharCode AEKeyword;
typedef FourCharCode AEEventClass;
typedef FourCharCode AEEventID;
typedef int16_t AEReturnID;
typedef int32_t AETransactionID;
typedef int16_t OSErr;
typedef struct AEDesc {
    DescType descriptorType;
    void *_Nullable dataHandle;
} AEDesc;
typedef AEDesc AppleEvent;
typedef AEDesc AEDescList;
typedef AEDesc AERecord;

enum {
    kAutoGenerateReturnID = -1,
    kAnyTransactionID = 0,
};
enum {
    typeNull = 'null', typeBoolean = 'bool', typeTrue = 'true', typeFalse = 'fals', typeSInt16 = 'shor',
    typeSInt32 = 'long', typeUInt32 = 'magn', typeSInt64 = 'comp', typeIEEE32BitFloatingPoint = 'sing',
    typeIEEE64BitFloatingPoint = 'doub', typeEnumerated = 'enum', typeType = 'type', typeKeyword = 'keyw',
    typeUnicodeText = 'utxt', typeUTF8Text = 'utf8', typeUTF16ExternalRepresentation = 'ut16', typeChar = 'TEXT',
    typeAEList = 'list', typeAERecord = 'reco', typeAppleEvent = 'aevt', typeLongDateTime = 'ldt ',
    typeFileURL = 'furl', typeApplicationURL = 'aprl', typeKernelProcessID = 'kpid',
    typeApplicationBundleID = 'bund', typeProcessSerialNumber = 'psn ', typeObjectSpecifier = 'obj ',
    typeData = 'tdta', typeWildCard = '****',
};
enum {
    keyDirectObject = '----', keyErrorNumber = 'errn', keyErrorString = 'errs', keyAEResult = '----',
    keyEventClassAttr = 'evcl', keyEventIDAttr = 'evid', keyAddressAttr = 'addr', keyReturnIDAttr = 'rtid',
    keyTransactionIDAttr = 'tran', keyEventSourceAttr = 'esrc', keySenderPIDAttr = 'spid',
    keyAEDesiredClass = 'want', keyAEContainer = 'from', keyAEKeyForm = 'form', keyAEKeyData = 'seld',
};
enum {
    kCoreEventClass = 'aevt', kAEOpenApplication = 'oapp', kAEReopenApplication = 'rapp', kAEOpenDocuments = 'odoc',
    kAEPrintDocuments = 'pdoc', kAEOpenContents = 'ocon', kAEQuitApplication = 'quit', kAEAnswer = 'ansr',
    kAEApplicationDied = 'obit', kAEShowPreferences = 'pref', kInternetEventClass = 'GURL', kAEGetURL = 'GURL',
    kAECoreSuite = 'core', kAEGetData = 'getd', kAESetData = 'setd', kAECreateElement = 'crel', kAEDelete = 'delo',
    kAEDoObjectsExist = 'doex', kAECountElements = 'cnte', kAEClose = 'clos', kAESave = 'save', kAEMove = 'move',
    kAEDuplicate = 'clon',
};
enum {
    errAEEventNotHandled = -1708, errAEDescNotFound = -1701, errAECoercionFail = -1700, errAEWrongDataType = -1703,
    errAEEventFailed = -10000, errAETimeout = -1712, errAENoSuchObject = -1728, errAEEventNotPermitted = -10004,
    procNotFound = -600,
};

typedef NS_OPTIONS(NSUInteger, NSAppleEventSendOptions) {
    NSAppleEventSendNoReply = 0x00000001,
    NSAppleEventSendQueueReply = 0x00000002,
    NSAppleEventSendWaitForReply = 0x00000003,
    NSAppleEventSendNeverInteract = 0x00000010,
    NSAppleEventSendCanInteract = 0x00000020,
    NSAppleEventSendAlwaysInteract = 0x00000030,
    NSAppleEventSendCanSwitchLayer = 0x00000040,
    NSAppleEventSendDontRecord = 0x00001000,
    NSAppleEventSendDontExecute = 0x00002000,
    NSAppleEventSendDontAnnotate = 0x00010000,
    NSAppleEventSendDefaultOptions = NSAppleEventSendWaitForReply | NSAppleEventSendCanInteract,
};
static const double NSAppleEventTimeOutDefault = -1.0;
static const double NSAppleEventTimeOutNone = -2.0;

/* A typed value: a scalar or string with its type code, a list, a record
 * of values by keyword, or an Apple event (parameters and attributes by
 * keyword). */
@interface NSAppleEventDescriptor : NSObject <NSCopying>
+ (NSAppleEventDescriptor *)nullDescriptor;
+ (nullable NSAppleEventDescriptor *)descriptorWithDescriptorType:(DescType)descriptorType
                                                             bytes:(nullable const void *)bytes
                                                            length:(NSUInteger)byteCount;
+ (nullable NSAppleEventDescriptor *)descriptorWithDescriptorType:(DescType)descriptorType data:(nullable NSData *)data;
+ (NSAppleEventDescriptor *)descriptorWithBoolean:(Boolean)boolean;
+ (NSAppleEventDescriptor *)descriptorWithEnumCode:(OSType)enumerator;
+ (NSAppleEventDescriptor *)descriptorWithInt32:(SInt32)signedInt;
+ (NSAppleEventDescriptor *)descriptorWithDouble:(double)doubleValue;
+ (NSAppleEventDescriptor *)descriptorWithTypeCode:(OSType)typeCode;
+ (NSAppleEventDescriptor *)descriptorWithString:(NSString *)string;
+ (NSAppleEventDescriptor *)descriptorWithDate:(NSDate *)date;
+ (NSAppleEventDescriptor *)descriptorWithFileURL:(NSURL *)fileURL;
+ (NSAppleEventDescriptor *)appleEventWithEventClass:(AEEventClass)eventClass eventID:(AEEventID)eventID
                                    targetDescriptor:(nullable NSAppleEventDescriptor *)targetDescriptor
                                            returnID:(AEReturnID)returnID
                                       transactionID:(AETransactionID)transactionID;
+ (NSAppleEventDescriptor *)listDescriptor;
+ (NSAppleEventDescriptor *)recordDescriptor;
+ (NSAppleEventDescriptor *)currentProcessDescriptor;
+ (NSAppleEventDescriptor *)descriptorWithProcessIdentifier:(pid_t)processIdentifier;
+ (NSAppleEventDescriptor *)descriptorWithBundleIdentifier:(NSString *)bundleIdentifier;
+ (NSAppleEventDescriptor *)descriptorWithApplicationURL:(NSURL *)applicationURL;

- (instancetype)initWithAEDescNoCopy:(const AEDesc *)aeDesc;
- (nullable instancetype)initWithDescriptorType:(DescType)descriptorType bytes:(nullable const void *)bytes
                                         length:(NSUInteger)byteCount;
- (nullable instancetype)initWithDescriptorType:(DescType)descriptorType data:(nullable NSData *)data;
- (instancetype)initWithEventClass:(AEEventClass)eventClass eventID:(AEEventID)eventID
                  targetDescriptor:(nullable NSAppleEventDescriptor *)targetDescriptor
                          returnID:(AEReturnID)returnID
                     transactionID:(AETransactionID)transactionID;
- (instancetype)initListDescriptor;
- (instancetype)initRecordDescriptor;

@property (nullable, readonly) const AEDesc *aeDesc __attribute__((objc_returns_inner_pointer));
@property (readonly) DescType descriptorType;
@property (readonly, copy) NSData *data;
@property (readonly) Boolean booleanValue;
@property (readonly) OSType enumCodeValue;
@property (readonly) SInt32 int32Value;
@property (readonly) double doubleValue;
@property (readonly) OSType typeCodeValue;
@property (nullable, readonly, copy) NSString *stringValue;
@property (nullable, readonly, copy) NSDate *dateValue;
@property (nullable, readonly, copy) NSURL *fileURLValue;
@property (readonly) AEEventClass eventClass;
@property (readonly) AEEventID eventID;
@property (readonly) AEReturnID returnID;
@property (readonly) AETransactionID transactionID;
@property (readonly) BOOL isRecordDescriptor;

- (void)setParamDescriptor:(NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword;
- (nullable NSAppleEventDescriptor *)paramDescriptorForKeyword:(AEKeyword)keyword;
- (void)removeParamDescriptorWithKeyword:(AEKeyword)keyword;
- (void)setAttributeDescriptor:(NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword;
- (nullable NSAppleEventDescriptor *)attributeDescriptorForKeyword:(AEKeyword)keyword;

@property (readonly) NSInteger numberOfItems;
- (void)insertDescriptor:(NSAppleEventDescriptor *)descriptor atIndex:(NSInteger)index;
- (nullable NSAppleEventDescriptor *)descriptorAtIndex:(NSInteger)index;
- (void)removeDescriptorAtIndex:(NSInteger)index;
- (void)setDescriptor:(NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword;
- (nullable NSAppleEventDescriptor *)descriptorForKeyword:(AEKeyword)keyword;
- (void)removeDescriptorWithKeyword:(AEKeyword)keyword;
- (AEKeyword)keywordForDescriptorAtIndex:(NSInteger)index;
- (nullable NSAppleEventDescriptor *)coerceToDescriptorType:(DescType)descriptorType;

/* Events for this process are dispatched to its handlers; others fail. */
- (nullable NSAppleEventDescriptor *)sendEventWithOptions:(NSAppleEventSendOptions)sendOptions
                                                  timeout:(NSTimeInterval)timeoutInSeconds
                                                    error:(NSError *_Nullable *_Nullable)error;
@end

typedef const struct __NSAppleEventManagerSuspension *NSAppleEventManagerSuspensionID;
extern NSNotificationName const NSAppleEventManagerWillProcessFirstEventNotification;

@interface NSAppleEventManager : NSObject
+ (NSAppleEventManager *)sharedAppleEventManager;
- (void)setEventHandler:(id)handler andSelector:(SEL)handleEventSelector forEventClass:(AEEventClass)eventClass
             andEventID:(AEEventID)eventID;
- (void)removeEventHandlerForEventClass:(AEEventClass)eventClass andEventID:(AEEventID)eventID;
- (OSErr)dispatchRawAppleEvent:(const AppleEvent *)theAppleEvent withRawReply:(AppleEvent *)theReply
                 handlerRefCon:(void *_Nullable)handlerRefCon;
@property (nullable, readonly, retain) NSAppleEventDescriptor *currentAppleEvent;
@property (nullable, readonly, retain) NSAppleEventDescriptor *currentReplyAppleEvent;
- (nullable NSAppleEventManagerSuspensionID)suspendCurrentAppleEvent;
- (NSAppleEventDescriptor *)appleEventForSuspensionID:(NSAppleEventManagerSuspensionID)suspensionID;
- (NSAppleEventDescriptor *)replyAppleEventForSuspensionID:(NSAppleEventManagerSuspensionID)suspensionID;
- (void)setCurrentAppleEventAndReplyEventWithSuspensionID:(NSAppleEventManagerSuspensionID)suspensionID;
- (void)resumeWithSuspensionID:(NSAppleEventManagerSuspensionID)suspensionID;
/* bitten: hands an event to its handler (or to the scripting commands);
 * returns the reply. */
- (NSAppleEventDescriptor *)_bn_dispatchEvent:(NSAppleEventDescriptor *)event;
@end

/* ---- Cocoa scripting ---- */

@class NSScriptObjectSpecifier, NSScriptCommandDescription, NSScriptCommand;

@interface NSClassDescription : NSObject
+ (void)registerClassDescription:(NSClassDescription *)description forClass:(Class)aClass;
+ (void)invalidateClassDescriptionCache;
+ (nullable NSClassDescription *)classDescriptionForClass:(Class)aClass;
@property (readonly, copy) NSArray<NSString *> *attributeKeys;
@property (readonly, copy) NSArray<NSString *> *toOneRelationshipKeys;
@property (readonly, copy) NSArray<NSString *> *toManyRelationshipKeys;
- (nullable NSString *)inverseForRelationshipKey:(NSString *)relationshipKey;
@end

@interface NSScriptClassDescription : NSClassDescription
+ (nullable NSScriptClassDescription *)classDescriptionForClass:(Class)aClass;
- (nullable instancetype)initWithSuiteName:(NSString *)suiteName className:(NSString *)className
                                dictionary:(nullable NSDictionary *)classDeclaration;
@property (nullable, readonly, copy) NSString *suiteName;
@property (nullable, readonly, copy) NSString *className;
@property (nullable, readonly, copy) NSString *implementationClassName;
@property (nullable, readonly, retain) NSScriptClassDescription *superclassDescription;
@property (readonly) FourCharCode appleEventCode;
- (BOOL)matchesAppleEventCode:(FourCharCode)appleEventCode;
- (BOOL)supportsCommand:(NSScriptCommandDescription *)commandDescription;
- (nullable SEL)selectorForCommand:(NSScriptCommandDescription *)commandDescription;
- (nullable NSString *)typeForKey:(NSString *)key;
- (nullable NSScriptClassDescription *)classDescriptionForKey:(NSString *)key;
- (FourCharCode)appleEventCodeForKey:(NSString *)key;
- (nullable NSString *)keyWithAppleEventCode:(FourCharCode)appleEventCode;
@property (nullable, readonly, copy) NSString *defaultSubcontainerAttributeKey;
- (BOOL)isLocationRequiredToCreateForKey:(NSString *)toManyRelationshipKey;
- (BOOL)hasPropertyForKey:(NSString *)key;
- (BOOL)hasOrderedToManyRelationshipForKey:(NSString *)key;
- (BOOL)hasReadablePropertyForKey:(NSString *)key;
- (BOOL)hasWritablePropertyForKey:(NSString *)key;
@end

@interface NSScriptCommandDescription : NSObject
- (nullable instancetype)initWithSuiteName:(NSString *)suiteName commandName:(NSString *)commandName
                                dictionary:(nullable NSDictionary *)commandDeclaration;
@property (readonly, copy) NSString *suiteName;
@property (readonly, copy) NSString *commandName;
@property (readonly) FourCharCode appleEventClassCode;
@property (readonly) FourCharCode appleEventCode;
@property (readonly, copy) NSString *commandClassName;
@property (nullable, readonly, copy) NSString *returnType;
@property (readonly) FourCharCode appleEventCodeForReturnType;
@property (readonly, copy) NSArray<NSString *> *argumentNames;
- (nullable NSString *)typeForArgumentWithName:(NSString *)argumentName;
- (FourCharCode)appleEventCodeForArgumentWithName:(NSString *)argumentName;
- (BOOL)isOptionalArgumentWithName:(NSString *)argumentName;
- (NSScriptCommand *)createCommandInstance;
@end

enum {
    NSNoScriptError = 0,
    NSReceiverEvaluationScriptError,
    NSKeySpecifierEvaluationScriptError,
    NSArgumentEvaluationScriptError,
    NSReceiversCantHandleCommandScriptError,
    NSRequiredArgumentsMissingScriptError,
    NSArgumentsWrongScriptError,
    NSUnknownKeyScriptError,
    NSInternalScriptError,
    NSOperationNotSupportedForKeyScriptError,
    NSCannotCreateScriptCommandError,
};

@interface NSScriptCommand : NSObject
- (instancetype)initWithCommandDescription:(NSScriptCommandDescription *)commandDef;
@property (readonly, retain) NSScriptCommandDescription *commandDescription;
@property (nullable, retain) id directParameter;
@property (nullable, retain) NSScriptObjectSpecifier *receiversSpecifier;
@property (nullable, readonly, retain) id evaluatedReceivers;
@property (nullable, copy) NSDictionary<NSString *, id> *arguments;
@property (nullable, readonly, copy) NSDictionary<NSString *, id> *evaluatedArguments;
@property (readonly, getter=isWellFormed) BOOL wellFormed;
- (nullable id)performDefaultImplementation;
- (nullable id)executeCommand;
@property NSInteger scriptErrorNumber;
@property (nullable, retain) NSAppleEventDescriptor *scriptErrorOffendingObjectDescriptor;
@property (nullable, retain) NSAppleEventDescriptor *scriptErrorExpectedTypeDescriptor;
@property (nullable, copy) NSString *scriptErrorString;
+ (nullable NSScriptCommand *)currentCommand;
@property (nullable, readonly, copy) NSAppleEventDescriptor *appleEvent;
- (void)suspendExecution;
- (void)resumeExecutionWithResult:(nullable id)result;
@end

/* The standard suite's commands. */
@interface NSCountCommand : NSScriptCommand
@end
@interface NSExistsCommand : NSScriptCommand
@end
@interface NSGetCommand : NSScriptCommand
@end
@interface NSSetCommand : NSScriptCommand
@property (readonly, retain) NSScriptObjectSpecifier *keySpecifier;
@end
@interface NSQuitCommand : NSScriptCommand
@end
@interface NSCloseCommand : NSScriptCommand
@end
@interface NSDeleteCommand : NSScriptCommand
@end
@interface NSCreateCommand : NSScriptCommand
@property (readonly, retain) NSScriptClassDescription *createClassDescription;
@property (readonly, copy) NSDictionary *resolvedKeyDictionary;
@end
@interface NSMoveCommand : NSScriptCommand
@end
@interface NSCloneCommand : NSScriptCommand
@end

typedef NS_ENUM(NSInteger, NSInsertionPosition) {
    NSPositionAfter, NSPositionBefore, NSPositionBeginning, NSPositionEnd, NSPositionReplace
};
typedef NS_ENUM(NSInteger, NSWhoseSubelementIdentifier) {
    NSIndexSubelement = 0, NSEverySubelement = 1, NSMiddleSubelement = 2, NSRandomSubelement = 3, NSNoSubelement = 4
};
enum {
    NSNoSpecifierError = 0, NSNoTopLevelContainersSpecifierError, NSContainerSpecifierError,
    NSUnknownKeySpecifierError, NSInvalidIndexSpecifierError, NSInternalSpecifierError,
    NSOperationNotSupportedForKeySpecifierError,
};

@interface NSScriptObjectSpecifier : NSObject
+ (nullable NSScriptObjectSpecifier *)objectSpecifierWithDescriptor:(NSAppleEventDescriptor *)descriptor;
- (instancetype)initWithContainerSpecifier:(NSScriptObjectSpecifier *)container key:(NSString *)property;
- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDesc
                               containerSpecifier:(nullable NSScriptObjectSpecifier *)container
                                              key:(NSString *)property;
@property (nullable, assign) NSScriptObjectSpecifier *childSpecifier;
@property (nullable, retain) NSScriptObjectSpecifier *containerSpecifier;
@property BOOL containerIsObjectBeingTested;
@property BOOL containerIsRangeContainerObject;
@property (copy) NSString *key;
@property (nullable, retain) NSScriptClassDescription *containerClassDescription;
@property (nullable, readonly, retain) NSScriptClassDescription *keyClassDescription;
- (nullable NSInteger *)indicesOfObjectsByEvaluatingWithContainer:(id)container count:(NSInteger *)numRefs;
- (nullable id)objectsByEvaluatingWithContainers:(id)containers;
@property (nullable, readonly, retain) id objectsByEvaluatingSpecifier;
@property NSInteger evaluationErrorNumber;
@property (nullable, readonly, retain) NSScriptObjectSpecifier *evaluationErrorSpecifier;
@property (nullable, readonly, copy) NSAppleEventDescriptor *descriptor;
@end

@interface NSPropertySpecifier : NSScriptObjectSpecifier
@end

@interface NSIndexSpecifier : NSScriptObjectSpecifier
- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDesc
                               containerSpecifier:(nullable NSScriptObjectSpecifier *)container
                                              key:(NSString *)property
                                            index:(NSInteger)index;
@property NSInteger index;
@end

@interface NSNameSpecifier : NSScriptObjectSpecifier
- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDesc
                               containerSpecifier:(nullable NSScriptObjectSpecifier *)container
                                              key:(NSString *)property
                                             name:(NSString *)name;
@property (copy) NSString *name;
@end

@interface NSUniqueIDSpecifier : NSScriptObjectSpecifier
- (instancetype)initWithContainerClassDescription:(NSScriptClassDescription *)classDesc
                               containerSpecifier:(nullable NSScriptObjectSpecifier *)container
                                              key:(NSString *)property
                                         uniqueID:(id)uniqueID;
@property (copy) id uniqueID;
@end

@interface NSObject (NSScriptObjectSpecifiers)
@property (nullable, readonly, retain) NSScriptObjectSpecifier *objectSpecifier;
- (nullable NSArray<NSNumber *> *)indicesOfObjectsByEvaluatingObjectSpecifier:(NSScriptObjectSpecifier *)specifier;
@end

@interface NSObject (NSScriptClassDescription)
@property (readonly) FourCharCode classCode;
@property (readonly, copy) NSString *className;
@end

@interface NSObject (NSScripting)
- (nullable id)scriptingValueForSpecifier:(NSScriptObjectSpecifier *)objectSpecifier;
@property (nullable, copy) NSDictionary<NSString *, id> *scriptingProperties;
@end

#pragma clang assume_nonnull end
#endif
