/* WebKit without a browser engine. Web views take HTML and show its text
 * (tags dropped, blocks on their own lines, entities decoded) drawn with
 * CoreText, then tell their delegates the load finished. No script runs:
 * user scripts and content rules are kept, evaluateJavaScript fails.
 * URLs other than file: ones fail to load. WKWebView and the legacy
 * WebView both work this way. */
#ifndef BITTEN_WEBKIT_H
#define BITTEN_WEBKIT_H
#import <AppKit/AppKit.h>

#pragma clang assume_nonnull begin

/* Foundation's URL loading classes, as far as WebKit names them. */
@class NSURLRequest;

extern NSString *const WKErrorDomain;
typedef NS_ENUM(NSInteger, WKErrorCode) { WKErrorUnknown = 1, WKErrorJavaScriptExceptionOccurred = 4 };
typedef NS_ENUM(NSInteger, WKUserScriptInjectionTime) {
    WKUserScriptInjectionTimeAtDocumentStart,
    WKUserScriptInjectionTimeAtDocumentEnd,
};
typedef NS_ENUM(NSInteger, WKNavigationActionPolicy) { WKNavigationActionPolicyCancel, WKNavigationActionPolicyAllow };
typedef NS_ENUM(NSInteger, WKNavigationType) {
    WKNavigationTypeLinkActivated, WKNavigationTypeFormSubmitted, WKNavigationTypeBackForward,
    WKNavigationTypeReload, WKNavigationTypeFormResubmitted, WKNavigationTypeOther = -1,
};

@interface WKUserScript : NSObject <NSCopying>
- (instancetype)initWithSource:(NSString *)source injectionTime:(WKUserScriptInjectionTime)injectionTime
              forMainFrameOnly:(BOOL)forMainFrameOnly;
@property (readonly, copy) NSString *source;
@property (readonly) WKUserScriptInjectionTime injectionTime;
@property (readonly, getter=isForMainFrameOnly) BOOL forMainFrameOnly;
@end

@interface WKContentRuleList : NSObject
@property (readonly, copy) NSString *identifier;
@end

@interface WKContentRuleListStore : NSObject
+ (nullable instancetype)defaultStore;
+ (nullable instancetype)storeWithURL:(NSURL *)url;
- (void)compileContentRuleListForIdentifier:(nullable NSString *)identifier
                     encodedContentRuleList:(nullable NSString *)encodedContentRuleList
                          completionHandler:(void (^)(WKContentRuleList *_Nullable, NSError *_Nullable))completionHandler;
- (void)lookUpContentRuleListForIdentifier:(nullable NSString *)identifier
                         completionHandler:(void (^)(WKContentRuleList *_Nullable, NSError *_Nullable))completionHandler;
- (void)removeContentRuleListForIdentifier:(nullable NSString *)identifier
                         completionHandler:(void (^)(NSError *_Nullable))completionHandler;
@end

@protocol WKScriptMessageHandler;
@interface WKUserContentController : NSObject
@property (readonly, copy) NSArray<WKUserScript *> *userScripts;
- (void)addUserScript:(WKUserScript *)userScript;
- (void)removeAllUserScripts;
- (void)addContentRuleList:(WKContentRuleList *)contentRuleList;
- (void)removeContentRuleList:(WKContentRuleList *)contentRuleList;
- (void)removeAllContentRuleLists;
- (void)addScriptMessageHandler:(id<WKScriptMessageHandler>)handler name:(NSString *)name;
- (void)removeScriptMessageHandlerForName:(NSString *)name;
@end

@interface WKPreferences : NSObject
@property BOOL javaScriptEnabled, javaScriptCanOpenWindowsAutomatically, plugInsEnabled;
@property CGFloat minimumFontSize;
@end

@interface WKWebViewConfiguration : NSObject <NSCopying>
@property (strong) WKUserContentController *userContentController;
@property (strong) WKPreferences *preferences;
@property (nullable, copy) NSString *applicationNameForUserAgent;
@end

@interface WKNavigation : NSObject
@end
@interface WKNavigationAction : NSObject
@property (readonly, copy) NSURLRequest *request;
@property (readonly) WKNavigationType navigationType;
@end

@class WKWebView, WKScriptMessage;
@protocol WKScriptMessageHandler <NSObject>
- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message;
@end
@protocol WKNavigationDelegate <NSObject>
@optional
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler;
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(null_unspecified WKNavigation *)navigation;
- (void)webView:(WKWebView *)webView didCommitNavigation:(null_unspecified WKNavigation *)navigation;
- (void)webView:(WKWebView *)webView didFinishNavigation:(null_unspecified WKNavigation *)navigation;
- (void)webView:(WKWebView *)webView didFailNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error;
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(null_unspecified WKNavigation *)navigation
      withError:(NSError *)error;
@end
@protocol WKUIDelegate <NSObject>
@end

@interface WKWebView : NSView
- (instancetype)initWithFrame:(NSRect)frame configuration:(WKWebViewConfiguration *)configuration;
@property (readonly, copy) WKWebViewConfiguration *configuration;
@property (nullable, weak) id<WKNavigationDelegate> navigationDelegate;
@property (nullable, weak) id<WKUIDelegate> UIDelegate;
@property (nullable, readonly, copy) NSString *title;
@property (nullable, readonly, copy) NSURL *URL;
@property (readonly, getter=isLoading) BOOL loading;
@property (readonly) double estimatedProgress;
@property (nullable, copy) NSString *customUserAgent;
@property BOOL allowsBackForwardNavigationGestures, allowsMagnification;
- (nullable WKNavigation *)loadHTMLString:(NSString *)string baseURL:(nullable NSURL *)baseURL;
- (nullable WKNavigation *)loadRequest:(NSURLRequest *)request;
- (nullable WKNavigation *)loadFileURL:(NSURL *)URL allowingReadAccessToURL:(NSURL *)readAccessURL;
- (nullable WKNavigation *)loadData:(NSData *)data MIMEType:(NSString *)MIMEType
              characterEncodingName:(NSString *)characterEncodingName baseURL:(NSURL *)baseURL;
- (void)stopLoading;
- (nullable WKNavigation *)reload;
- (void)evaluateJavaScript:(NSString *)javaScriptString
         completionHandler:(void (^_Nullable)(_Nullable id, NSError *_Nullable error))completionHandler;
/* The text the view shows, for tests and accessibility. */
@property (readonly, copy) NSString *_bn_text;
@end

/* ---- the legacy WebView ---- */

@interface WebPreferences : NSObject
+ (WebPreferences *)standardPreferences;
- (instancetype)initWithIdentifier:(nullable NSString *)identifier;
@property (readonly, copy) NSString *identifier;
@property (getter=isJavaScriptEnabled) BOOL javaScriptEnabled;
@property BOOL javaScriptCanOpenWindowsAutomatically;
@property (getter=arePlugInsEnabled) BOOL plugInsEnabled;
@end

@class WebView;
@interface WebFrame : NSObject
@property (readonly, weak) WebView *webView;
- (void)loadHTMLString:(NSString *)string baseURL:(nullable NSURL *)URL;
- (void)loadRequest:(NSURLRequest *)request;
- (void)stopLoading;
- (void)reload;
@end

@interface WebView : NSView
- (instancetype)initWithFrame:(NSRect)frame frameName:(nullable NSString *)frameName groupName:(nullable NSString *)groupName;
@property (readonly, strong) WebFrame *mainFrame;
@property (nullable, weak) id frameLoadDelegate, policyDelegate, UIDelegate, resourceLoadDelegate;
@property (null_resettable, strong) WebPreferences *preferences;
@property BOOL drawsBackground;
- (void)stopLoading:(nullable id)sender;
@property (readonly, copy) NSString *_bn_text;
@end

#pragma clang assume_nonnull end
#endif
