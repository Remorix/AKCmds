#pragma once

#import <Foundation/Foundation.h>

#include <sys/types.h>

FOUNDATION_EXPORT NSString *const LSUserApplicationType;
FOUNDATION_EXPORT NSString *const LSBlockUntilCompleteKey;
FOUNDATION_EXPORT NSString *const LSFileProviderStringKey;
FOUNDATION_EXPORT NSString *const LSRequireOpenInPlaceKey;
FOUNDATION_EXPORT NSString *const UIApplicationOpenURLOptionsAnnotationKey;

@interface LSBundleProxy : NSObject
+ (instancetype)bundleProxyForIdentifier:(NSString *)identifier;
+ (instancetype)bundleProxyForURL:(NSURL *)url;
@property (nonatomic, readonly) NSURL *bundleURL;
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *canonicalExecutablePath;
@property (nonatomic, readonly) NSUUID *cacheGUID;
@property (nonatomic, readonly) NSString *localizedShortName;
@property (nonatomic, readonly) unsigned int sequenceNumber;
@end

@interface LSApplicationProxy : LSBundleProxy
+ (instancetype)applicationProxyForBundleURL:(NSURL *)url;
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *itemName;
@property (nonatomic, readonly, getter=isLaunchProhibited) BOOL launchProhibited;
@property (nonatomic, readonly) BOOL supportsOpenInPlace;
- (NSSet *)claimedDocumentContentTypes;
- (NSString *)handlerRankOfClaimForContentType:(NSString *)type;
- (NSString *)localizedNameForContext:(id)context;
@end

@interface LSDocumentProxy : NSObject
+ (instancetype)documentProxyForURL:(NSURL *)url;
+ (instancetype)documentProxyForName:(NSString *)name
                                type:(NSString *)type
                            MIMEType:(NSString *)mimeType;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (NSArray *)applicationsAvailableForOpeningDocument:(id)document;
- (NSArray *)applicationsAvailableForOpeningURL:(NSURL *)url;
- (id)operationToOpenResource:(id)resource
             usingApplication:(id)application
     uniqueDocumentIdentifier:(id)uniqueDocumentIdentifier
                     userInfo:(id)userInfo;
- (id)operationToOpenResource:(id)resource
             usingApplication:(id)application
     uniqueDocumentIdentifier:(id)uniqueDocumentIdentifier
                     userInfo:(id)userInfo
                     delegate:(id)delegate;
- (id)operationToOpenResource:(id)resource
             usingApplication:(id)application
     uniqueDocumentIdentifier:(id)uniqueDocumentIdentifier
             isContentManaged:(BOOL)isContentManaged
             sourceAuditToken:(const void *)sourceAuditToken
                     userInfo:(id)userInfo
                      options:(id)options
                     delegate:(id)delegate;
- (LSApplicationProxy *)applicationForUserActivityType:(NSString *)activityType;
- (void)openUserActivity:(NSUserActivity *)activity
    withApplicationProxy:(LSApplicationProxy *)applicationProxy
       completionHandler:(void (^)(BOOL success, NSError *error))completion;
- (void)openUserActivity:(NSUserActivity *)activity
    withApplicationProxy:(LSApplicationProxy *)applicationProxy
                 options:(NSDictionary *)options
       completionHandler:(void (^)(BOOL success, NSError *error))completion;
- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(NSDictionary *)options error:(NSError **)error;
- (BOOL)openURL:(NSURL *)url withOptions:(NSDictionary *)options error:(NSError **)error;
- (void)openApplicationWithBundleID:(NSString *)bundleID;
@end

typedef long FBSOpenApplicationErrorCode;
FOUNDATION_EXPORT NSString *FBSOpenApplicationErrorCodeToString(FBSOpenApplicationErrorCode code);

@interface FBSOpenApplicationOptions : NSObject
+ (instancetype)optionsWithDictionary:(NSDictionary *)dictionary;
@end

@interface FBSOpenApplicationService : NSObject
+ (instancetype)serviceWithDefaultShellEndpoint;
- (void)openApplication:(NSString *)bundleIdentifier
            withOptions:(id)options
             completion:(void (^)(id processHandle, NSError *error))completion;
@end

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (unsigned int)createClientPort;
- (void)cleanupClientPort:(unsigned int)clientPort;
- (void)openApplication:(id)application
                options:(id)options
             clientPort:(unsigned int)clientPort
             withResult:(void (^)(NSError *error))result;
- (void)openURL:(NSURL *)url
     application:(NSString *)bundleIdentifier
         options:(NSDictionary *)options
      clientPort:(unsigned int)clientPort
      withResult:(void (^)(NSError *error))callback;
- (void)terminateApplication:(id)application
                   forReason:(int)reason
                   andReport:(BOOL)report
             withDescription:(id)description
                  completion:(void (^)(BOOL success, NSError *error))completion;
- (int)pidForApplication:(id)application;
- (id)processHandleForApplication:(id)application;
@end

enum {
    BKSApplicationStateUnknown                   = 0,
    BKSApplicationStateTerminated                = (1 << 0),
    BKSApplicationStateBackgroundTaskSuspended   = (1 << 1),
    BKSApplicationStateBackgroundRunning         = (1 << 2),
    BKSApplicationStateForegroundRunning         = (1 << 3),
    BKSApplicationStateProcessServer             = (1 << 4),
    BKSApplicationStateForegroundRunningObscured = (1 << 5),
};
typedef uint32_t BKSApplicationState;

@interface BKSApplicationStateMonitor : NSObject
- (BKSApplicationState)mostElevatedApplicationStateForPID:(pid_t)pid;
- (void)invalidate;
@end

FOUNDATION_EXPORT NSString *const FBSActivateForEventOptionTypeBackgroundContentFetching;
FOUNDATION_EXPORT NSString *const FBSDebugOptionKeyArguments;
FOUNDATION_EXPORT NSString *const FBSDebugOptionKeyDebugOnNextLaunch;
FOUNDATION_EXPORT NSString *const FBSDebugOptionKeyEnvironment;
FOUNDATION_EXPORT NSString *const FBSDebugOptionKeyStandardErrorPath;
FOUNDATION_EXPORT NSString *const FBSDebugOptionKeyStandardOutPath;
FOUNDATION_EXPORT NSString *const FBSDebugOptionKeyWaitForDebugger;
FOUNDATION_EXPORT NSString *const FBSOpenApplicationOptionKeyActivateForEvent;
FOUNDATION_EXPORT NSString *const FBSOpenApplicationOptionKeyActivateSuspended;
FOUNDATION_EXPORT NSString *const FBSOpenApplicationOptionKeyDebuggingOptions;
FOUNDATION_EXPORT NSString *const FBSOpenApplicationOptionKeyLSCacheGUID;
FOUNDATION_EXPORT NSString *const FBSOpenApplicationOptionKeyLSSequenceNumber;
FOUNDATION_EXPORT NSString *const FBSOpenApplicationOptionKeyLaunchIntent;
FOUNDATION_EXPORT NSString *const FBSOpenApplicationOptionKeyPayloadAnnotation;
FOUNDATION_EXPORT NSString *const FBSOpenApplicationOptionKeyPayloadURL;
FOUNDATION_EXPORT NSString *const FBSOpenApplicationOptionKeyPromptUnlockDevice;
FOUNDATION_EXPORT NSString *const FBSOpenApplicationOptionKeyUnlockDevice;
FOUNDATION_EXPORT NSString *const FBSOpenApplicationWithNewScene;
