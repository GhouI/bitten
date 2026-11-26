// Apple event descriptors (values, coercions, lists, records, events), the
// Apple event manager dispatching events sent to this process, script
// commands with arguments and receivers, and object specifiers.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); exit(1); } } while (0)

@interface Handler : NSObject
@property int calls;
@property NSString *got;
@end
@implementation Handler
- (void)handleURL:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply {
    self.calls++;
    self.got = [event paramDescriptorForKeyword:keyDirectObject].stringValue;
    CHECK([NSAppleEventManager sharedAppleEventManager].currentAppleEvent == event);
    [reply setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:@"handled"] forKeyword:keyDirectObject];
}
@end

@interface Item : NSObject
@property NSString *name, *uniqueID;
@end
@implementation Item
@end
@interface Root : NSObject
@property NSArray<Item *> *items;
@property NSString *title;
@end
@implementation Root
@end

@interface Greet : NSScriptCommand
@end
@implementation Greet
- (id)performDefaultImplementation {
    NSDictionary *a = self.evaluatedArguments;
    if (!a[@"who"]) {
        self.scriptErrorNumber = NSArgumentsWrongScriptError;
        return nil;
    }
    CHECK([NSScriptCommand currentCommand] == self);
    return [NSString stringWithFormat:@"%@, %@", self.directParameter ?: @"Hello", a[@"who"]];
}
@end

int main(void) {
    /* Values. */
    NSAppleEventDescriptor *s = [NSAppleEventDescriptor descriptorWithString:@"héllo"];
    CHECK(s.descriptorType == typeUnicodeText && [s.stringValue isEqual:@"héllo"] && s.data.length == 10);
    NSAppleEventDescriptor *i = [NSAppleEventDescriptor descriptorWithInt32:42];
    CHECK(i.int32Value == 42 && i.doubleValue == 42 && [i.stringValue isEqual:@"42"]);
    CHECK([NSAppleEventDescriptor descriptorWithString:@"17"].int32Value == 17);
    CHECK([NSAppleEventDescriptor descriptorWithBoolean:YES].booleanValue);
    CHECK(![NSAppleEventDescriptor descriptorWithBoolean:NO].booleanValue);
    CHECK([NSAppleEventDescriptor descriptorWithDouble:2.5].doubleValue == 2.5);
    CHECK([NSAppleEventDescriptor descriptorWithTypeCode:'abcd'].typeCodeValue == 'abcd');
    CHECK([NSAppleEventDescriptor descriptorWithEnumCode:'yes '].enumCodeValue == 'yes ');
    NSDate *when = [NSDate dateWithTimeIntervalSinceReferenceDate:700000000];
    CHECK([[NSAppleEventDescriptor descriptorWithDate:when].dateValue isEqual:when]);
    NSURL *file = [NSURL fileURLWithPath:@"/tmp/a b.txt"];
    CHECK([[NSAppleEventDescriptor descriptorWithFileURL:file].fileURLValue.path isEqual:@"/tmp/a b.txt"]);
    CHECK([NSAppleEventDescriptor nullDescriptor].descriptorType == typeNull);
    CHECK([[NSAppleEventDescriptor descriptorWithString:@"x"] coerceToDescriptorType:typeLongDateTime] == nil);

    /* Lists are one-based; records are by keyword. */
    NSAppleEventDescriptor *list = [NSAppleEventDescriptor listDescriptor];
    [list insertDescriptor:[NSAppleEventDescriptor descriptorWithInt32:1] atIndex:0];
    [list insertDescriptor:[NSAppleEventDescriptor descriptorWithInt32:2] atIndex:0];
    [list insertDescriptor:[NSAppleEventDescriptor descriptorWithInt32:0] atIndex:1];
    CHECK(list.numberOfItems == 3 && [list descriptorAtIndex:1].int32Value == 0 && [list descriptorAtIndex:3].int32Value == 2);
    [list removeDescriptorAtIndex:1];
    CHECK(list.numberOfItems == 2 && [list descriptorAtIndex:1].int32Value == 1);
    NSAppleEventDescriptor *rec = [NSAppleEventDescriptor recordDescriptor];
    [rec setDescriptor:s forKeyword:'name'];
    [rec setDescriptor:i forKeyword:'size'];
    [rec setDescriptor:[NSAppleEventDescriptor descriptorWithInt32:7] forKeyword:'size'];
    CHECK(rec.isRecordDescriptor && rec.numberOfItems == 2 && [rec descriptorForKeyword:'size'].int32Value == 7);
    CHECK([rec keywordForDescriptorAtIndex:1] == 'name');
    [rec removeDescriptorWithKeyword:'name'];
    CHECK(rec.numberOfItems == 1 && ![rec descriptorForKeyword:'name']);

    /* Events and the manager. */
    NSAppleEventDescriptor *ev = [NSAppleEventDescriptor appleEventWithEventClass:kInternetEventClass eventID:kAEGetURL
                                                                 targetDescriptor:[NSAppleEventDescriptor currentProcessDescriptor]
                                                                         returnID:kAutoGenerateReturnID
                                                                    transactionID:kAnyTransactionID];
    [ev setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:@"myapp://open?x=1"] forKeyword:keyDirectObject];
    CHECK(ev.eventClass == 'GURL' && ev.eventID == 'GURL' && ev.returnID > 0 && ev.descriptorType == typeAppleEvent);
    Handler *h = [Handler new];
    NSAppleEventManager *m = [NSAppleEventManager sharedAppleEventManager];
    CHECK(m == [NSAppleEventManager sharedAppleEventManager]);
    [m setEventHandler:h andSelector:@selector(handleURL:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
    NSError *err = nil;
    NSAppleEventDescriptor *reply = [ev sendEventWithOptions:NSAppleEventSendDefaultOptions timeout:NSAppleEventTimeOutDefault error:&err];
    CHECK(h.calls == 1 && [h.got isEqual:@"myapp://open?x=1"] && !err);
    CHECK([[reply paramDescriptorForKeyword:keyDirectObject].stringValue isEqual:@"handled"]);
    CHECK(m.currentAppleEvent == nil);
    [m removeEventHandlerForEventClass:kInternetEventClass andEventID:kAEGetURL];
    reply = [ev sendEventWithOptions:0 timeout:1 error:&err];
    CHECK(!reply && err.code == errAEEventNotHandled && h.calls == 1);
    NSAppleEventDescriptor *away = [NSAppleEventDescriptor appleEventWithEventClass:kCoreEventClass eventID:kAEOpenApplication
                                                                   targetDescriptor:[NSAppleEventDescriptor descriptorWithBundleIdentifier:@"com.example.elsewhere"]
                                                                           returnID:kAutoGenerateReturnID
                                                                      transactionID:kAnyTransactionID];
    err = nil;
    CHECK(![away sendEventWithOptions:0 timeout:1 error:&err] && err.code == procNotFound);

    /* A script command from a description. */
    NSScriptCommandDescription *greet = [[NSScriptCommandDescription alloc]
        initWithSuiteName:@"Test" commandName:@"greet"
               dictionary:@{@"CommandClass" : @"Greet", @"AppleEventClassCode" : @"tsts", @"AppleEventCode" : @"grit",
                            @"Arguments" : @{@"who" : @{@"AppleEventCode" : @"whoo", @"Type" : @"NSString"}}}];
    CHECK(greet.appleEventClassCode == 'tsts' && greet.appleEventCode == 'grit' && [greet.commandClassName isEqual:@"Greet"]);
    CHECK([greet appleEventCodeForArgumentWithName:@"who"] == 'whoo' && ![greet isOptionalArgumentWithName:@"who"]);
    NSScriptCommand *cmd = [greet createCommandInstance];
    CHECK([cmd isKindOfClass:[Greet class]] && cmd.commandDescription == greet);
    CHECK(!cmd.isWellFormed);
    [cmd executeCommand];
    CHECK(cmd.scriptErrorNumber == NSRequiredArgumentsMissingScriptError);
    cmd = [greet createCommandInstance];
    cmd.arguments = @{@"who" : @"world"};
    cmd.directParameter = @"Hi";
    CHECK([[cmd executeCommand] isEqual:@"Hi, world"] && cmd.scriptErrorNumber == 0);
    CHECK([NSScriptCommand currentCommand] == nil);

    /* Object specifiers over a model. */
    Item *a = [Item new], *b = [Item new], *c = [Item new];
    a.name = @"alpha"; a.uniqueID = @"id-a";
    b.name = @"beta"; b.uniqueID = @"id-b";
    c.name = @"gamma"; c.uniqueID = @"id-c";
    Root *root = [Root new];
    root.items = @[a, b, c];
    root.title = @"Things";
    NSScriptClassDescription *rootDesc = [[NSScriptClassDescription alloc]
        initWithSuiteName:@"Test" className:@"root"
               dictionary:@{@"AppleEventCode" : @"root", @"Attributes" : @{@"title" : @{@"AppleEventCode" : @"titl", @"Type" : @"NSString"}},
                            @"ToManyRelationships" : @{@"items" : @{@"Type" : @"item"}}}];
    CHECK([rootDesc appleEventCodeForKey:@"title"] == 'titl' && [[rootDesc keyWithAppleEventCode:'titl'] isEqual:@"title"]);
    CHECK([rootDesc hasPropertyForKey:@"title"] && [rootDesc hasOrderedToManyRelationshipForKey:@"items"]);
    NSIndexSpecifier *second = [[NSIndexSpecifier alloc] initWithContainerClassDescription:rootDesc containerSpecifier:nil
                                                                                       key:@"items" index:1];
    CHECK([second objectsByEvaluatingWithContainers:root] == b);
    second.index = -1;
    CHECK([second objectsByEvaluatingWithContainers:root] == c);
    second.index = 9;
    CHECK([second objectsByEvaluatingWithContainers:root] == nil && second.evaluationErrorNumber == NSInvalidIndexSpecifierError);
    NSNameSpecifier *named = [[NSNameSpecifier alloc] initWithContainerClassDescription:rootDesc containerSpecifier:nil
                                                                                     key:@"items" name:@"gamma"];
    CHECK([named objectsByEvaluatingWithContainers:root] == c);
    NSUniqueIDSpecifier *byID = [[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:rootDesc containerSpecifier:nil
                                                                                            key:@"items" uniqueID:@"id-a"];
    CHECK([byID.uniqueID isEqual:@"id-a"] && [byID objectsByEvaluatingWithContainers:root] == a);
    NSPropertySpecifier *title = [[NSPropertySpecifier alloc] initWithContainerClassDescription:rootDesc containerSpecifier:nil
                                                                                             key:@"title"];
    CHECK([[title objectsByEvaluatingWithContainers:root] isEqual:@"Things"]);
    NSPropertySpecifier *bogus = [[NSPropertySpecifier alloc] initWithContainerClassDescription:rootDesc containerSpecifier:nil
                                                                                             key:@"nothing"];
    CHECK([bogus objectsByEvaluatingWithContainers:root] == nil && bogus.evaluationErrorNumber == NSUnknownKeySpecifierError);
    /* Specifiers to descriptors and back. */
    NSAppleEventDescriptor *sd = named.descriptor;
    CHECK(sd.descriptorType == typeObjectSpecifier && [[sd descriptorForKeyword:keyAEKeyData].stringValue isEqual:@"gamma"]);
    CHECK([sd descriptorForKeyword:keyAEKeyForm].enumCodeValue == 'name');
    CHECK(a.objectSpecifier == nil);

    printf("appleevents ok\n");
    return 0;
}
