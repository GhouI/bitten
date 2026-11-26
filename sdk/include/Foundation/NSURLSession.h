/* bitten SDK: Foundation's URL loading system: requests and responses,
 * URLSession with data, upload, download and WebSocket tasks, its
 * configuration, delegates and metrics, and the cache, cookie and
 * credential classes it refers to. Included from Foundation.h. */
#ifndef BITTEN_FOUNDATION_NSURLSESSION_H
#define BITTEN_FOUNDATION_NSURLSESSION_H
#include <Security/SecProtocolTypes.h>

#pragma clang assume_nonnull begin

/* ---- errors ---- */

enum : NSInteger {
    NSURLErrorUnknown = -1,
    NSURLErrorCancelled = -999,
    NSURLErrorBadURL = -1000,
    NSURLErrorTimedOut = -1001,
    NSURLErrorUnsupportedURL = -1002,
    NSURLErrorCannotFindHost = -1003,
    NSURLErrorCannotConnectToHost = -1004,
    NSURLErrorNetworkConnectionLost = -1005,
    NSURLErrorDNSLookupFailed = -1006,
    NSURLErrorHTTPTooManyRedirects = -1007,
    NSURLErrorResourceUnavailable = -1008,
    NSURLErrorNotConnectedToInternet = -1009,
    NSURLErrorRedirectToNonExistentLocation = -1010,
    NSURLErrorBadServerResponse = -1011,
    NSURLErrorUserCancelledAuthentication = -1012,
    NSURLErrorUserAuthenticationRequired = -1013,
    NSURLErrorZeroByteResource = -1014,
    NSURLErrorCannotDecodeRawData = -1015,
    NSURLErrorCannotDecodeContentData = -1016,
    NSURLErrorCannotParseResponse = -1017,
    NSURLErrorFileDoesNotExist = -1100,
    NSURLErrorFileIsDirectory = -1101,
    NSURLErrorNoPermissionsToReadFile = -1102,
    NSURLErrorDataLengthExceedsMaximum = -1103,
    NSURLErrorSecureConnectionFailed = -1200,
    NSURLErrorServerCertificateHasBadDate = -1201,
    NSURLErrorServerCertificateUntrusted = -1202,
    NSURLErrorServerCertificateHasUnknownRoot = -1203,
    NSURLErrorServerCertificateNotYetValid = -1204,
    NSURLErrorClientCertificateRejected = -1205,
    NSURLErrorClientCertificateRequired = -1206,
    NSURLErrorCannotLoadFromNetwork = -2000,
    NSURLErrorCannotCreateFile = -3000,
    NSURLErrorCannotOpenFile = -3001,
    NSURLErrorCannotCloseFile = -3002,
    NSURLErrorCannotWriteToFile = -3003,
    NSURLErrorCannotRemoveFile = -3004,
    NSURLErrorCannotMoveFile = -3005,
    NSURLErrorDownloadDecodingFailedMidStream = -3006,
    NSURLErrorDownloadDecodingFailedToComplete = -3007,
};
extern NSString *const NSURLErrorBackgroundTaskCancelledReasonKey;
extern NSString *const NSURLSessionDownloadTaskResumeData;
extern NSString *const NSURLErrorNetworkUnavailableReasonKey;

/* ---- requests ---- */

typedef NS_ENUM(NSUInteger, NSURLRequestCachePolicy) {
    NSURLRequestUseProtocolCachePolicy = 0,
    NSURLRequestReloadIgnoringLocalCacheData = 1,
    NSURLRequestReloadIgnoringLocalAndRemoteCacheData = 4,
    NSURLRequestReloadIgnoringCacheData = NSURLRequestReloadIgnoringLocalCacheData,
    NSURLRequestReturnCacheDataElseLoad = 2,
    NSURLRequestReturnCacheDataDontLoad = 3,
    NSURLRequestReloadRevalidatingCacheData = 5,
} NS_SWIFT_NAME(NSURLRequest.CachePolicy);
typedef NS_ENUM(NSUInteger, NSURLRequestNetworkServiceType) {
    NSURLNetworkServiceTypeDefault = 0,
    NSURLNetworkServiceTypeVoIP = 1,
    NSURLNetworkServiceTypeVideo = 2,
    NSURLNetworkServiceTypeBackground = 3,
    NSURLNetworkServiceTypeVoice = 4,
    NSURLNetworkServiceTypeResponsiveData = 6,
    NSURLNetworkServiceTypeAVStreaming = 8,
    NSURLNetworkServiceTypeResponsiveAV = 9,
    NSURLNetworkServiceTypeCallSignaling = 11,
} NS_SWIFT_NAME(NSURLRequest.NetworkServiceType);
typedef NS_ENUM(NSUInteger, NSURLRequestAttribution) {
    NSURLRequestAttributionDeveloper = 0,
    NSURLRequestAttributionUser = 1,
} NS_SWIFT_NAME(NSURLRequest.Attribution);

__attribute__((swift_bridge("Foundation.URLRequest")))
@interface NSURLRequest : NSObject <NSCopying, NSMutableCopying>
+ (instancetype)requestWithURL:(NSURL *)URL;
+ (instancetype)requestWithURL:(NSURL *)URL cachePolicy:(NSURLRequestCachePolicy)cachePolicy
               timeoutInterval:(NSTimeInterval)timeoutInterval;
- (instancetype)initWithURL:(NSURL *)URL;
- (instancetype)initWithURL:(NSURL *)URL cachePolicy:(NSURLRequestCachePolicy)cachePolicy
            timeoutInterval:(NSTimeInterval)timeoutInterval;
@property (nullable, readonly, copy) NSURL *URL;
@property (readonly) NSURLRequestCachePolicy cachePolicy;
@property (readonly) NSTimeInterval timeoutInterval;
@property (nullable, readonly, copy) NSURL *mainDocumentURL;
@property (readonly) NSURLRequestNetworkServiceType networkServiceType;
@property (readonly) BOOL allowsCellularAccess;
@property (readonly) BOOL allowsExpensiveNetworkAccess;
@property (readonly) BOOL allowsConstrainedNetworkAccess;
@property (readonly) BOOL assumesHTTP3Capable;
@property (readonly) NSURLRequestAttribution attribution;
@property (readonly) BOOL requiresDNSSECValidation;
@property (nullable, readonly, copy) NSString *HTTPMethod;
@property (nullable, readonly, copy) NSDictionary<NSString *, NSString *> *allHTTPHeaderFields;
- (nullable NSString *)valueForHTTPHeaderField:(NSString *)field;
@property (nullable, readonly, copy) NSData *HTTPBody;
@property (readonly) BOOL HTTPShouldHandleCookies;
@property (readonly) BOOL HTTPShouldUsePipelining;
@end

@interface NSMutableURLRequest : NSURLRequest
@property (nullable, copy) NSURL *URL;
@property NSURLRequestCachePolicy cachePolicy;
@property NSTimeInterval timeoutInterval;
@property (nullable, copy) NSURL *mainDocumentURL;
@property NSURLRequestNetworkServiceType networkServiceType;
@property BOOL allowsCellularAccess;
@property BOOL allowsExpensiveNetworkAccess;
@property BOOL allowsConstrainedNetworkAccess;
@property BOOL assumesHTTP3Capable;
@property NSURLRequestAttribution attribution;
@property BOOL requiresDNSSECValidation;
@property (copy) NSString *HTTPMethod;
@property (nullable, copy) NSDictionary<NSString *, NSString *> *allHTTPHeaderFields;
- (void)setValue:(nullable NSString *)value forHTTPHeaderField:(NSString *)field;
- (void)addValue:(NSString *)value forHTTPHeaderField:(NSString *)field;
@property (nullable, copy) NSData *HTTPBody;
@property BOOL HTTPShouldHandleCookies;
@property BOOL HTTPShouldUsePipelining;
@end

/* ---- responses ---- */

NS_SWIFT_NAME(URLResponse)
@interface NSURLResponse : NSObject <NSCopying>
- (instancetype)initWithURL:(NSURL *)URL MIMEType:(nullable NSString *)MIMEType
      expectedContentLength:(NSInteger)length textEncodingName:(nullable NSString *)name;
@property (nullable, readonly, copy) NSURL *URL;
@property (nullable, readonly, copy) NSString *MIMEType;
@property (readonly) long long expectedContentLength;
@property (nullable, readonly, copy) NSString *textEncodingName;
@property (nullable, readonly, copy) NSString *suggestedFilename;
@end

NS_SWIFT_NAME(HTTPURLResponse)
@interface NSHTTPURLResponse : NSURLResponse
- (nullable instancetype)initWithURL:(NSURL *)url statusCode:(NSInteger)statusCode
                         HTTPVersion:(nullable NSString *)HTTPVersion
                        headerFields:(nullable NSDictionary<NSString *, NSString *> *)headerFields;
@property (readonly) NSInteger statusCode;
@property (readonly, copy) NSDictionary *allHeaderFields;
- (nullable NSString *)valueForHTTPHeaderField:(NSString *)field;
+ (NSString *)localizedStringForStatusCode:(NSInteger)statusCode;
@end

/* ---- caches, cookies, credentials ---- */

NS_SWIFT_NAME(CachedURLResponse)
@interface NSCachedURLResponse : NSObject
- (instancetype)initWithResponse:(NSURLResponse *)response data:(NSData *)data;
@property (readonly, copy) NSURLResponse *response;
@property (readonly, copy) NSData *data;
@end

NS_SWIFT_NAME(URLCache)
@interface NSURLCache : NSObject
@property (class, strong) NSURLCache *sharedURLCache NS_SWIFT_NAME(shared);
- (instancetype)initWithMemoryCapacity:(NSUInteger)memoryCapacity diskCapacity:(NSUInteger)diskCapacity
                          diskPath:(nullable NSString *)path;
- (instancetype)initWithMemoryCapacity:(NSUInteger)memoryCapacity diskCapacity:(NSUInteger)diskCapacity
                      directoryURL:(nullable NSURL *)directoryURL;
- (nullable NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request;
- (void)storeCachedResponse:(NSCachedURLResponse *)cachedResponse forRequest:(NSURLRequest *)request;
- (void)removeCachedResponseForRequest:(NSURLRequest *)request;
- (void)removeAllCachedResponses;
@property NSUInteger memoryCapacity;
@property NSUInteger diskCapacity;
@property (readonly) NSUInteger currentMemoryUsage;
@property (readonly) NSUInteger currentDiskUsage;
@end

typedef NSString *NSHTTPCookiePropertyKey NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(HTTPCookiePropertyKey);
extern NSHTTPCookiePropertyKey const NSHTTPCookieName, NSHTTPCookieValue, NSHTTPCookieDomain, NSHTTPCookiePath,
    NSHTTPCookieExpires, NSHTTPCookieSecure, NSHTTPCookieMaximumAge, NSHTTPCookieOriginURL, NSHTTPCookieVersion;
typedef NS_ENUM(NSUInteger, NSHTTPCookieAcceptPolicy) {
    NSHTTPCookieAcceptPolicyAlways, NSHTTPCookieAcceptPolicyNever, NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain
} NS_SWIFT_NAME(HTTPCookie.AcceptPolicy);

NS_SWIFT_NAME(HTTPCookie)
@interface NSHTTPCookie : NSObject
+ (nullable NSHTTPCookie *)cookieWithProperties:(NSDictionary<NSHTTPCookiePropertyKey, id> *)properties;
- (nullable instancetype)initWithProperties:(NSDictionary<NSHTTPCookiePropertyKey, id> *)properties;
+ (NSDictionary<NSString *, NSString *> *)requestHeaderFieldsWithCookies:(NSArray<NSHTTPCookie *> *)cookies;
+ (NSArray<NSHTTPCookie *> *)cookiesWithResponseHeaderFields:(NSDictionary<NSString *, NSString *> *)headerFields
                                                      forURL:(NSURL *)URL;
@property (nullable, readonly, copy) NSDictionary<NSHTTPCookiePropertyKey, id> *properties;
@property (readonly, copy) NSString *name;
@property (readonly, copy) NSString *value;
@property (readonly, copy) NSString *domain;
@property (readonly, copy) NSString *path;
@property (nullable, readonly, copy) NSDate *expiresDate;
@property (readonly, getter=isSecure) BOOL secure;
@property (readonly, getter=isSessionOnly) BOOL sessionOnly;
@property (readonly, getter=isHTTPOnly) BOOL HTTPOnly;
@end

NS_SWIFT_NAME(HTTPCookieStorage)
@interface NSHTTPCookieStorage : NSObject
@property (class, readonly, strong) NSHTTPCookieStorage *sharedHTTPCookieStorage NS_SWIFT_NAME(shared);
@property (nullable, readonly, copy) NSArray<NSHTTPCookie *> *cookies;
- (void)setCookie:(NSHTTPCookie *)cookie;
- (void)deleteCookie:(NSHTTPCookie *)cookie;
- (void)removeCookiesSinceDate:(NSDate *)date;
- (nullable NSArray<NSHTTPCookie *> *)cookiesForURL:(NSURL *)URL;
- (void)setCookies:(NSArray<NSHTTPCookie *> *)cookies forURL:(nullable NSURL *)URL mainDocumentURL:(nullable NSURL *)mainDocumentURL;
@property NSHTTPCookieAcceptPolicy cookieAcceptPolicy;
@end

typedef NS_ENUM(NSUInteger, NSURLCredentialPersistence) {
    NSURLCredentialPersistenceNone, NSURLCredentialPersistenceForSession, NSURLCredentialPersistencePermanent,
    NSURLCredentialPersistenceSynchronizable
} NS_SWIFT_NAME(URLCredential.Persistence);
NS_SWIFT_NAME(URLCredential)
@interface NSURLCredential : NSObject <NSCopying>
+ (NSURLCredential *)credentialWithUser:(NSString *)user password:(NSString *)password
                            persistence:(NSURLCredentialPersistence)persistence;
- (instancetype)initWithUser:(NSString *)user password:(NSString *)password
                 persistence:(NSURLCredentialPersistence)persistence;
+ (NSURLCredential *)credentialForTrust:(id)trust;
- (instancetype)initWithTrust:(id)trust;
@property (nullable, readonly, copy) NSString *user;
@property (nullable, readonly, copy) NSString *password;
@property (readonly) BOOL hasPassword;
@property (readonly) NSURLCredentialPersistence persistence;
@end

extern NSString *const NSURLProtectionSpaceHTTP, *const NSURLProtectionSpaceHTTPS;
extern NSString *const NSURLAuthenticationMethodDefault, *const NSURLAuthenticationMethodHTTPBasic,
    *const NSURLAuthenticationMethodHTTPDigest, *const NSURLAuthenticationMethodServerTrust,
    *const NSURLAuthenticationMethodClientCertificate;
NS_SWIFT_NAME(URLProtectionSpace)
@interface NSURLProtectionSpace : NSObject <NSCopying>
- (instancetype)initWithHost:(NSString *)host port:(NSInteger)port protocol:(nullable NSString *)protocol
                       realm:(nullable NSString *)realm authenticationMethod:(nullable NSString *)authenticationMethod;
@property (readonly, copy) NSString *host;
@property (readonly) NSInteger port;
@property (nullable, readonly, copy) NSString *protocol;
@property (nullable, readonly, copy) NSString *realm;
@property (readonly, copy) NSString *authenticationMethod;
@property (nullable, readonly) id serverTrust;
@end
NS_SWIFT_NAME(URLAuthenticationChallenge)
@interface NSURLAuthenticationChallenge : NSObject
@property (readonly, copy) NSURLProtectionSpace *protectionSpace;
@property (nullable, readonly, copy) NSURLCredential *proposedCredential;
@property (readonly) NSInteger previousFailureCount;
@property (nullable, readonly, copy) NSURLResponse *failureResponse;
@property (nullable, readonly, copy) NSError *error;
@end

/* ---- sessions ---- */

@class NSURLSession, NSURLSessionTask, NSURLSessionDataTask, NSURLSessionUploadTask, NSURLSessionDownloadTask,
    NSURLSessionWebSocketTask, NSURLSessionTaskMetrics, NSURLSessionWebSocketMessage;

extern const int64_t NSURLSessionTransferSizeUnknown;
extern const float NSURLSessionTaskPriorityDefault, NSURLSessionTaskPriorityLow, NSURLSessionTaskPriorityHigh;

typedef NS_ENUM(NSInteger, NSURLSessionTaskState) {
    NSURLSessionTaskStateRunning = 0,
    NSURLSessionTaskStateSuspended = 1,
    NSURLSessionTaskStateCanceling = 2,
    NSURLSessionTaskStateCompleted = 3,
} NS_SWIFT_NAME(URLSessionTask.State);
typedef NS_ENUM(NSInteger, NSURLSessionAuthChallengeDisposition) {
    NSURLSessionAuthChallengeUseCredential = 0,
    NSURLSessionAuthChallengePerformDefaultHandling = 1,
    NSURLSessionAuthChallengeCancelAuthenticationChallenge = 2,
    NSURLSessionAuthChallengeRejectProtectionSpace = 3,
} NS_SWIFT_NAME(URLSession.AuthChallengeDisposition);
typedef NS_ENUM(NSInteger, NSURLSessionResponseDisposition) {
    NSURLSessionResponseCancel = 0,
    NSURLSessionResponseAllow = 1,
    NSURLSessionResponseBecomeDownload = 2,
    NSURLSessionResponseBecomeStream = 3,
} NS_SWIFT_NAME(URLSession.ResponseDisposition);
typedef NS_ENUM(NSInteger, NSURLSessionDelayedRequestDisposition) {
    NSURLSessionDelayedRequestContinueLoading = 0,
    NSURLSessionDelayedRequestUseNewRequest = 1,
    NSURLSessionDelayedRequestCancel = 2,
} NS_SWIFT_NAME(URLSession.DelayedRequestDisposition);
typedef NS_ENUM(NSInteger, NSURLSessionMultipathServiceType) {
    NSURLSessionMultipathServiceTypeNone = 0,
    NSURLSessionMultipathServiceTypeHandover = 1,
    NSURLSessionMultipathServiceTypeInteractive = 2,
    NSURLSessionMultipathServiceTypeAggregate = 3,
} NS_SWIFT_NAME(URLSessionConfiguration.MultipathServiceType);
typedef NS_ENUM(NSInteger, NSURLSessionWebSocketMessageType) {
    NSURLSessionWebSocketMessageTypeData = 0,
    NSURLSessionWebSocketMessageTypeString = 1,
} NS_SWIFT_NAME(URLSessionWebSocketTask.__MessageType);
typedef NS_ENUM(NSInteger, NSURLSessionWebSocketCloseCode) {
    NSURLSessionWebSocketCloseCodeInvalid = 0,
    NSURLSessionWebSocketCloseCodeNormalClosure = 1000,
    NSURLSessionWebSocketCloseCodeGoingAway = 1001,
    NSURLSessionWebSocketCloseCodeProtocolError = 1002,
    NSURLSessionWebSocketCloseCodeUnsupportedData = 1003,
    NSURLSessionWebSocketCloseCodeNoStatusReceived = 1005,
    NSURLSessionWebSocketCloseCodeAbnormalClosure = 1006,
    NSURLSessionWebSocketCloseCodeInvalidFramePayloadData = 1007,
    NSURLSessionWebSocketCloseCodePolicyViolation = 1008,
    NSURLSessionWebSocketCloseCodeMessageTooBig = 1009,
    NSURLSessionWebSocketCloseCodeMandatoryExtensionMissing = 1010,
    NSURLSessionWebSocketCloseCodeInternalServerError = 1011,
    NSURLSessionWebSocketCloseCodeTLSHandshakeFailure = 1015,
} NS_SWIFT_NAME(URLSessionWebSocketTask.CloseCode);
typedef NS_ENUM(NSInteger, NSURLSessionTaskMetricsResourceFetchType) {
    NSURLSessionTaskMetricsResourceFetchTypeUnknown,
    NSURLSessionTaskMetricsResourceFetchTypeNetworkLoad,
    NSURLSessionTaskMetricsResourceFetchTypeServerPush,
    NSURLSessionTaskMetricsResourceFetchTypeLocalCache,
} NS_SWIFT_NAME(URLSessionTaskMetrics.ResourceFetchType);
typedef NS_ENUM(NSInteger, NSURLSessionTaskMetricsDomainResolutionProtocol) {
    NSURLSessionTaskMetricsDomainResolutionProtocolUnknown,
    NSURLSessionTaskMetricsDomainResolutionProtocolUDP,
    NSURLSessionTaskMetricsDomainResolutionProtocolTCP,
    NSURLSessionTaskMetricsDomainResolutionProtocolTLS,
    NSURLSessionTaskMetricsDomainResolutionProtocolHTTPS,
} NS_SWIFT_NAME(URLSessionTaskMetrics.DomainResolutionProtocol);

NS_SWIFT_NAME(URLSessionConfiguration)
@interface NSURLSessionConfiguration : NSObject <NSCopying>
@property (class, readonly, strong) NSURLSessionConfiguration *defaultSessionConfiguration NS_SWIFT_NAME(default);
@property (class, readonly, strong) NSURLSessionConfiguration *ephemeralSessionConfiguration NS_SWIFT_NAME(ephemeral);
+ (NSURLSessionConfiguration *)backgroundSessionConfigurationWithIdentifier:(NSString *)identifier
    NS_SWIFT_NAME(background(withIdentifier:));
@property (nullable, readonly, copy) NSString *identifier;
@property NSURLRequestCachePolicy requestCachePolicy;
@property NSTimeInterval timeoutIntervalForRequest;
@property NSTimeInterval timeoutIntervalForResource;
@property NSURLRequestNetworkServiceType networkServiceType;
@property BOOL allowsCellularAccess;
@property BOOL allowsExpensiveNetworkAccess;
@property BOOL allowsConstrainedNetworkAccess;
@property BOOL requiresDNSSECValidation;
@property BOOL waitsForConnectivity;
@property (getter=isDiscretionary) BOOL discretionary;
@property (nullable, copy) NSString *sharedContainerIdentifier;
@property BOOL sessionSendsLaunchEvents;
@property (nullable, copy) NSDictionary *connectionProxyDictionary;
@property tls_protocol_version_t TLSMinimumSupportedProtocolVersion;
@property tls_protocol_version_t TLSMaximumSupportedProtocolVersion;
@property BOOL HTTPShouldUsePipelining;
@property BOOL HTTPShouldSetCookies;
@property NSHTTPCookieAcceptPolicy HTTPCookieAcceptPolicy;
@property (nullable, copy) NSDictionary *HTTPAdditionalHeaders;
@property NSInteger HTTPMaximumConnectionsPerHost;
@property (nullable, strong) NSHTTPCookieStorage *HTTPCookieStorage;
@property (nullable, strong) id URLCredentialStorage;
@property (nullable, strong) NSURLCache *URLCache;
@property BOOL shouldUseExtendedBackgroundIdleMode;
@property (copy) NSArray<Class> *protocolClasses;
@property NSURLSessionMultipathServiceType multipathServiceType;
@end

NS_SWIFT_NAME(URLSessionDelegate)
@protocol NSURLSessionDelegate <NSObject>
@optional
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(nullable NSError *)error;
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
    completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
                                NSURLCredential *_Nullable credential))completionHandler;
- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session;
@end

NS_SWIFT_NAME(URLSessionTaskDelegate)
@protocol NSURLSessionTaskDelegate <NSURLSessionDelegate>
@optional
- (void)URLSession:(NSURLSession *)session didCreateTask:(NSURLSessionTask *)task;
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willBeginDelayedRequest:(NSURLRequest *)request
          completionHandler:(void (^)(NSURLSessionDelayedRequestDisposition disposition,
                                      NSURLRequest *_Nullable newRequest))completionHandler;
- (void)URLSession:(NSURLSession *)session taskIsWaitingForConnectivity:(NSURLSessionTask *)task;
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response
                    newRequest:(NSURLRequest *)request
             completionHandler:(void (^)(NSURLRequest *_Nullable))completionHandler;
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
      completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
                                  NSURLCredential *_Nullable credential))completionHandler;
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent
    totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics;
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didCompleteWithError:(nullable NSError *)error;
@end

NS_SWIFT_NAME(URLSessionDataDelegate)
@protocol NSURLSessionDataDelegate <NSURLSessionTaskDelegate>
@optional
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveResponse:(NSURLResponse *)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler;
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didBecomeDownloadTask:(NSURLSessionDownloadTask *)downloadTask;
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data;
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    willCacheResponse:(NSCachedURLResponse *)proposedResponse
    completionHandler:(void (^)(NSCachedURLResponse *_Nullable cachedResponse))completionHandler;
@end

NS_SWIFT_NAME(URLSessionDownloadDelegate)
@protocol NSURLSessionDownloadDelegate <NSURLSessionTaskDelegate>
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
    didFinishDownloadingToURL:(NSURL *)location;
@optional
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
         didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten
    totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite;
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
    didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes;
@end

NS_SWIFT_NAME(URLSessionWebSocketDelegate)
@protocol NSURLSessionWebSocketDelegate <NSURLSessionTaskDelegate>
@optional
- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
    didOpenWithProtocol:(nullable NSString *)protocol;
- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
    didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode reason:(nullable NSData *)reason;
@end

NS_SWIFT_NAME(URLSession)
@interface NSURLSession : NSObject
@property (class, readonly, strong) NSURLSession *sharedSession NS_SWIFT_NAME(shared);
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration;
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                  delegate:(nullable id<NSURLSessionDelegate>)delegate
                             delegateQueue:(nullable NSOperationQueue *)queue;
@property (readonly, retain) NSOperationQueue *delegateQueue;
@property (nullable, readonly, retain) id<NSURLSessionDelegate> delegate;
@property (readonly, copy) NSURLSessionConfiguration *configuration;
@property (nullable, copy) NSString *sessionDescription;
- (void)finishTasksAndInvalidate;
- (void)invalidateAndCancel;
- (void)resetWithCompletionHandler:(void (^)(void))completionHandler;
- (void)flushWithCompletionHandler:(void (^)(void))completionHandler;
- (void)getTasksWithCompletionHandler:(void (^)(NSArray<NSURLSessionDataTask *> *dataTasks,
                                                NSArray<NSURLSessionUploadTask *> *uploadTasks,
                                                NSArray<NSURLSessionDownloadTask *> *downloadTasks))completionHandler;
- (void)getAllTasksWithCompletionHandler:(void (^)(NSArray<__kindof NSURLSessionTask *> *tasks))completionHandler;

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url;
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL;
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData;
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request;
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url;
- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData;
- (NSURLSessionWebSocketTask *)webSocketTaskWithURL:(NSURL *)url;
- (NSURLSessionWebSocketTask *)webSocketTaskWithURL:(NSURL *)url protocols:(NSArray<NSString *> *)protocols;
- (NSURLSessionWebSocketTask *)webSocketTaskWithRequest:(NSURLRequest *)request;

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *_Nullable data, NSURLResponse *_Nullable response,
                                                        NSError *_Nullable error))completionHandler;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *_Nullable data, NSURLResponse *_Nullable response,
                                                    NSError *_Nullable error))completionHandler;
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL
                                completionHandler:(void (^)(NSData *_Nullable data, NSURLResponse *_Nullable response,
                                                            NSError *_Nullable error))completionHandler;
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(nullable NSData *)bodyData
                                completionHandler:(void (^)(NSData *_Nullable data, NSURLResponse *_Nullable response,
                                                            NSError *_Nullable error))completionHandler;
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                    completionHandler:(void (^)(NSURL *_Nullable location,
                                                                NSURLResponse *_Nullable response,
                                                                NSError *_Nullable error))completionHandler;
- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url
                                completionHandler:(void (^)(NSURL *_Nullable location, NSURLResponse *_Nullable response,
                                                            NSError *_Nullable error))completionHandler;
@end

NS_SWIFT_NAME(URLSessionTask)
@interface NSURLSessionTask : NSObject <NSCopying>
@property (readonly) NSUInteger taskIdentifier;
@property (nullable, readonly, copy) NSURLRequest *originalRequest;
@property (nullable, readonly, copy) NSURLRequest *currentRequest;
@property (nullable, readonly, copy) NSURLResponse *response;
@property (nullable, retain) id<NSURLSessionTaskDelegate> delegate;
@property (readonly, strong) NSProgress *progress;
@property (nullable, copy) NSDate *earliestBeginDate;
@property int64_t countOfBytesClientExpectsToSend;
@property int64_t countOfBytesClientExpectsToReceive;
@property (readonly) int64_t countOfBytesSent;
@property (readonly) int64_t countOfBytesReceived;
@property (readonly) int64_t countOfBytesExpectedToSend;
@property (readonly) int64_t countOfBytesExpectedToReceive;
@property (nullable, copy) NSString *taskDescription;
- (void)cancel;
@property (readonly) NSURLSessionTaskState state;
@property (nullable, readonly, copy) NSError *error;
- (void)suspend;
- (void)resume;
@property float priority;
@property BOOL prefersIncrementalDelivery;
@end

NS_SWIFT_NAME(URLSessionDataTask)
@interface NSURLSessionDataTask : NSURLSessionTask
@end
NS_SWIFT_NAME(URLSessionUploadTask)
@interface NSURLSessionUploadTask : NSURLSessionDataTask
@end
NS_SWIFT_NAME(URLSessionDownloadTask)
@interface NSURLSessionDownloadTask : NSURLSessionTask
- (void)cancelByProducingResumeData:(void (^)(NSData *_Nullable resumeData))completionHandler;
@end

NS_REFINED_FOR_SWIFT
@interface NSURLSessionWebSocketMessage : NSObject
- (instancetype)initWithData:(NSData *)data;
- (instancetype)initWithString:(NSString *)string;
@property (readonly) NSURLSessionWebSocketMessageType type;
@property (nullable, readonly, copy) NSData *data;
@property (nullable, readonly, copy) NSString *string;
@end

NS_SWIFT_NAME(URLSessionWebSocketTask)
@interface NSURLSessionWebSocketTask : NSURLSessionTask
- (void)sendMessage:(NSURLSessionWebSocketMessage *)message
    completionHandler:(void (^)(NSError *_Nullable error))completionHandler NS_REFINED_FOR_SWIFT;
- (void)receiveMessageWithCompletionHandler:(void (^)(NSURLSessionWebSocketMessage *_Nullable message,
                                                      NSError *_Nullable error))completionHandler NS_REFINED_FOR_SWIFT;
- (void)sendPingWithPongReceiveHandler:(void (^)(NSError *_Nullable error))pongReceiveHandler;
- (void)cancelWithCloseCode:(NSURLSessionWebSocketCloseCode)closeCode reason:(nullable NSData *)reason;
@property NSInteger maximumMessageSize;
@property (readonly) NSURLSessionWebSocketCloseCode closeCode;
@property (nullable, readonly, copy) NSData *closeReason;
@end

NS_SWIFT_NAME(URLSessionTaskTransactionMetrics)
@interface NSURLSessionTaskTransactionMetrics : NSObject
@property (readonly, copy) NSURLRequest *request;
@property (nullable, readonly, copy) NSURLResponse *response;
@property (nullable, readonly, copy) NSDate *fetchStartDate;
@property (nullable, readonly, copy) NSDate *domainLookupStartDate;
@property (nullable, readonly, copy) NSDate *domainLookupEndDate;
@property (nullable, readonly, copy) NSDate *connectStartDate;
@property (nullable, readonly, copy) NSDate *secureConnectionStartDate;
@property (nullable, readonly, copy) NSDate *secureConnectionEndDate;
@property (nullable, readonly, copy) NSDate *connectEndDate;
@property (nullable, readonly, copy) NSDate *requestStartDate;
@property (nullable, readonly, copy) NSDate *requestEndDate;
@property (nullable, readonly, copy) NSDate *responseStartDate;
@property (nullable, readonly, copy) NSDate *responseEndDate;
@property (nullable, readonly, copy) NSString *networkProtocolName;
@property (readonly, getter=isProxyConnection) BOOL proxyConnection;
@property (readonly, getter=isReusedConnection) BOOL reusedConnection;
@property (readonly) NSURLSessionTaskMetricsResourceFetchType resourceFetchType;
@property (readonly) int64_t countOfRequestHeaderBytesSent;
@property (readonly) int64_t countOfRequestBodyBytesSent;
@property (readonly) int64_t countOfRequestBodyBytesBeforeEncoding;
@property (readonly) int64_t countOfResponseHeaderBytesReceived;
@property (readonly) int64_t countOfResponseBodyBytesReceived;
@property (readonly) int64_t countOfResponseBodyBytesAfterDecoding;
@property (nullable, readonly, copy) NSString *localAddress;
@property (nullable, readonly, copy) NSNumber *localPort NS_REFINED_FOR_SWIFT;
@property (nullable, readonly, copy) NSString *remoteAddress;
@property (nullable, readonly, copy) NSNumber *remotePort NS_REFINED_FOR_SWIFT;
@property (nullable, readonly, copy) NSNumber *negotiatedTLSProtocolVersion NS_REFINED_FOR_SWIFT;
@property (nullable, readonly, copy) NSNumber *negotiatedTLSCipherSuite NS_REFINED_FOR_SWIFT;
@property (readonly, getter=isCellular) BOOL cellular;
@property (readonly, getter=isExpensive) BOOL expensive;
@property (readonly, getter=isConstrained) BOOL constrained;
@property (readonly, getter=isMultipath) BOOL multipath;
@property (readonly) NSURLSessionTaskMetricsDomainResolutionProtocol domainResolutionProtocol;
@end

NS_SWIFT_NAME(URLSessionTaskMetrics)
@interface NSURLSessionTaskMetrics : NSObject
@property (readonly, copy) NSArray<NSURLSessionTaskTransactionMetrics *> *transactionMetrics;
@property (readonly) NSUInteger redirectCount;
@end

#pragma clang assume_nonnull end
#endif
