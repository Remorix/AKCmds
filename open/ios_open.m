#import "open_internal.h"

#include <dispatch/dispatch.h>
#include <errno.h>
#include <getopt.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

BOOL gVerbose            = NO;
BOOL gHideInternalSDKs   = NO;
NSString *gSDKFilter     = nil;
BOOL gBackground         = NO;
BOOL gWait               = NO;
BOOL gFresh              = NO;
BOOL gDefaultTextEditor  = NO;
BOOL gTextEdit           = NO;
BOOL gHideApp            = NO;
BOOL gNewInstance        = NO;
BOOL gExcludeFromRecents = NO;
BOOL gReadStdin          = NO;
BOOL gArgsSeen           = NO;
BOOL gReveal             = NO;
BOOL gHeaderMode         = NO;
BOOL gCancelled          = NO;
BOOL gUnlockDevice       = NO;
NSURL *gStdinURL         = nil;
NSURL *gStdoutURL        = nil;
NSURL *gStderrURL        = nil;
NSMutableDictionary *gEnvVars = nil;
static BOOL gLaunchIntent = NO;

static NSString *const kIOSTextEditBundleID = @"com.apple.TextEdit";
static NSString *const kIOSFilzaBundleID    = @"com.tigisoftware.Filza";
static NSString *const kIOSPlainTextUTI     = @"public.text";
static NSString *const kIOSPlainTextMIME    = @"text/plain";
static NSString *const kIOSPrivateTmpDir    = @"/private/tmp";
static NSString *const kIOSTmpDir           = @"/tmp";
static NSString *const kIOSJBTmpDir         = @"/var/jb/tmp";
static NSString *const kIOSFilzaRevealPrefix = @"filza://view";
static NSString *const kIOSSavedApplicationStateDir =
    @"/var/mobile/Library/Saved Application State";

@interface AKOpenResourceOperationDelegate : NSObject {
    dispatch_semaphore_t _semaphore;
    NSError *_error;
    NSURL *_copiedURL;
    BOOL _completed;
}
- (NSError *)error;
- (NSURL *)copiedURL;
- (BOOL)completed;
- (BOOL)waitForCompletionWithTimeout:(dispatch_time_t)timeout;
@end

@implementation AKOpenResourceOperationDelegate

- (instancetype)init {
    self = [super init];
    if (self)
        _semaphore = dispatch_semaphore_create(0);
    return self;
}

- (void)dealloc {
    [_error release];
    [_copiedURL release];
    if (_semaphore)
        dispatch_release(_semaphore);
    [super dealloc];
}

- (NSError *)error {
    return _error;
}

- (NSURL *)copiedURL {
    return _copiedURL;
}

- (BOOL)completed {
    return _completed;
}

- (BOOL)waitForCompletionWithTimeout:(dispatch_time_t)timeout {
    return dispatch_semaphore_wait(_semaphore, timeout) == 0;
}

- (void)openResourceOperation:(id)operation didFailWithError:(NSError *)error {
    (void)operation;
    if (_error != error) {
        [_error release];
        _error = [error retain];
    }
}

- (void)openResourceOperationDidComplete:(id)operation {
    (void)operation;
    _completed = YES;
    dispatch_semaphore_signal(_semaphore);
}

- (void)openResourceOperation:(id)operation didFinishCopyingResource:(id)resource {
    (void)operation;
    if (_copiedURL != resource) {
        [_copiedURL release];
        _copiedURL = [resource retain];
    }
}

@end

static id parseJSONPropertyListArgument(const char *arg,
                                        NSString *optionName) {
    NSString *text = stringFromArg(arg);
    if (![text length]) {
        dieWithError([NSString stringWithFormat:
            @"The %@ option requires a non-empty JSON value.", optionName]);
    }

    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        dieWithError([NSString stringWithFormat:
            @"The %@ option was not valid UTF-8.", optionName]);
    }

    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data
                                                options:NSJSONReadingAllowFragments
                                                  error:&error];
    if (!object) {
        dieWithError([NSString stringWithFormat:
            @"Unable to parse %@ JSON: %@", optionName, error]);
    }
    return object;
}

static void printUsage(const char *prog) {
    fprintf(stderr,
        "Usage: %s [-e] [-t] [-f] [-W] [-g] [-b <bundle identifier>] [-a <application>] "
        "[-u URL] [filenames] [--args arguments]\n"
        "       %s [-h] [-s <partial SDK name>] [headers]\n"
        "       %s [--help]\n"
        "\n"
        "iOS notes:\n"
        "      -e                    Opens with TextEdit if com.apple.TextEdit is available.\n"
        "                            iOS imports a copy into the app for editing; edits do not\n"
        "                            write back to the original file. Successful opens print the\n"
        "                            imported destination path when LaunchServices reports it.\n"
        "      -t                    Opens with the default plain-text editor from LaunchServices.\n"
        "                            iOS imports a copy into the app for editing; edits do not\n"
        "                            write back to the original file. Successful opens print the\n"
        "                            imported destination path when LaunchServices reports it.\n"
        "      -f                    Reads stdin to a temporary .txt file and opens it in TextEdit.\n"
        "      -F                    Terminates the target application and clears its saved\n"
        "                            application state before relaunching or opening documents.\n"
        "                            Requires an explicit app on iOS.\n"
        "      -R                    Reveals the specified path in Filza when a usable Filza\n"
        "                            installation is available.\n"
        "      -h, --header          Searches iOS SDK and include roots for matching headers,\n"
        "                            then opens the resolved paths. Without an explicit app,\n"
        "                            iOS opens the resolved headers in the default plain-text\n"
        "                            editor.\n"
        "      -s <partial SDK name> Limits -h header search to SDKs whose names contain the\n"
        "                            supplied substring.\n"
        "      -g                    Launches the target application suspended when an explicit app is known.\n"
        "      -n                    Requests a new scene when the target application supports it.\n"
        "      -W                    Waits for explicitly launched applications to terminate.\n"
        "      --unlock              Requests device unlock for explicit FrontBoard launches.\n"
        "      --intent              Requests the iOS LaunchIntent flag for explicit app or\n"
        "                            user-activity launches.\n"
        "      --userActivity type   Opens the application for the specified user activity type.\n"
        "      --userActivityTitle title\n"
        "                            Sets NSUserActivity.title for the user activity launch.\n"
        "      --userActivityWebpageURL URL\n"
        "                            Sets NSUserActivity.webpageURL for the user activity launch.\n"
        "      --userActivityInfo KEY=VALUE\n"
        "                            Adds a string entry to NSUserActivity.userInfo. May be repeated.\n"
        "      --annotation JSON     Adds a property-list annotation payload for iOS explicit-app\n"
        "                            URL and document opens. JSON may be an object, array,\n"
        "                            string, number, true, false, or null.\n"
        "      -a application        Opens with the named application.\n"
        "      -b bundle identifier  Opens with the specified bundle identifier.\n"
        "      -u URL                Opens the specified URL.\n"
        "      --args                Passes remaining arguments to the launched application.\n"
        "      --env VAR=VALUE       Adds an environment variable for the launched application.\n"
        "      -o path               Redirects stdout for the launched application.\n"
        "      -E path               Redirects stderr for the launched application.\n"
        "\n"
        "Unsupported on iOS: -j, -x, -i\n",
        prog, prog, prog);
}

static LSApplicationProxy *findApplicationByBundleIdentifier(NSArray *apps, NSString *bundleIdentifier) {
    if (!bundleIdentifier.length)
        return nil;

    for (LSApplicationProxy *candidate in apps) {
        NSString *identifier = [candidate applicationIdentifier];
        if ([identifier isEqualToString:bundleIdentifier])
            return candidate;
    }
    return nil;
}

static LSApplicationProxy *findApplicationByName(NSArray *apps, NSString *name) {
    if (!name.length)
        return nil;

    for (NSUInteger pass = 0; pass < 2; ++pass) {
        for (LSApplicationProxy *candidate in apps) {
            NSString *localized = [candidate localizedNameForContext:nil];
            NSString *itemName  = [candidate itemName];
            NSString *shortName = [candidate localizedShortName];
            NSArray *choices = @[ localized ?: @"", itemName ?: @"", shortName ?: @"" ];
            for (NSString *choice in choices) {
                if (!choice.length)
                    continue;
                if (pass == 0) {
                    if ([name isEqualToString:choice])
                        return candidate;
                } else if ([name caseInsensitiveCompare:choice] == NSOrderedSame) {
                    return candidate;
                }
            }
        }
    }

    return nil;
}

static LSApplicationProxy *findApplicationByPath(NSArray *apps, NSString *path) {
    if (!path.length)
        return nil;

    NSString *standardized = [path stringByStandardizingPath];
    NSString *resolvedUserPath = [standardized stringByResolvingSymlinksInPath];
    for (LSApplicationProxy *candidate in apps) {
        NSString *bundlePath = [[[candidate bundleURL] path] stringByStandardizingPath];
        NSString *execPath   = [[candidate canonicalExecutablePath] stringByStandardizingPath];
        NSString *resolvedBundlePath = [bundlePath stringByResolvingSymlinksInPath];
        NSString *resolvedExecPath = [execPath stringByResolvingSymlinksInPath];
        if ((bundlePath.length
             && ([bundlePath isEqualToString:standardized]
                 || [bundlePath isEqualToString:resolvedUserPath]
                 || [resolvedBundlePath isEqualToString:standardized]
                 || [resolvedBundlePath isEqualToString:resolvedUserPath]))
            || (execPath.length
                && ([execPath isEqualToString:standardized]
                    || [execPath isEqualToString:resolvedUserPath]
                    || [resolvedExecPath isEqualToString:standardized]
                    || [resolvedExecPath isEqualToString:resolvedUserPath]))) {
            return candidate;
        }
    }

    return nil;
}

static BOOL plistDeclaredActivityListContainsType(id activityList, NSString *activityType) {
    if (!activityType.length || !activityList)
        return NO;

    if ([activityList isKindOfClass:[NSString class]])
        return [activityType isEqualToString:activityList];

    if ([activityList isKindOfClass:[NSArray class]] || [activityList isKindOfClass:[NSSet class]]) {
        for (id value in activityList) {
            if ([value isKindOfClass:[NSString class]]
                && [activityType isEqualToString:value]) {
                return YES;
            }
        }
        return NO;
    }

    if ([activityList isKindOfClass:[NSDictionary class]]) {
        if ([(NSDictionary *)activityList objectForKey:activityType])
            return YES;
        for (id value in [(NSDictionary *)activityList allValues]) {
            if ([value isKindOfClass:[NSString class]]
                && [activityType isEqualToString:value]) {
                return YES;
            }
        }
    }

    return NO;
}

static BOOL infoPlistDeclaresUserActivityType(NSDictionary *infoPlist, NSString *activityType) {
    if (!infoPlist || !activityType.length)
        return NO;

    if (plistDeclaredActivityListContainsType(infoPlist[@"NSUserActivityTypes"], activityType))
        return YES;

    NSString *documentActivityType = infoPlist[@"NSUbiquitousDocumentUserActivityType"];
    if ([documentActivityType isKindOfClass:[NSString class]]
        && [activityType isEqualToString:documentActivityType]) {
        return YES;
    }

    NSArray *documentTypes = infoPlist[@"CFBundleDocumentTypes"];
    if ([documentTypes isKindOfClass:[NSArray class]]) {
        for (id documentType in documentTypes) {
            if (![documentType isKindOfClass:[NSDictionary class]])
                continue;
            NSString *type = documentType[@"NSUbiquitousDocumentUserActivityType"];
            if ([type isKindOfClass:[NSString class]]
                && [activityType isEqualToString:type]) {
                return YES;
            }
        }
    }

    return NO;
}

static NSArray *findApplicationsByUserActivityType(NSArray *apps, NSString *activityType) {
    if (!activityType.length)
        return @[];

    NSMutableArray *matches = [NSMutableArray array];
    for (LSApplicationProxy *candidate in apps) {
        NSString *bundlePath = [[candidate bundleURL] path];
        if (!bundlePath.length)
            continue;

        NSString *infoPlistPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
        if (!infoPlist)
            continue;

        if (infoPlistDeclaresUserActivityType(infoPlist, activityType))
            [matches addObject:candidate];
    }

    return matches;
}

static NSMutableDictionary *buildLaunchOptions(NSArray *appArgs,
                                               LSApplicationProxy *targetProxy,
                                               NSURL *payloadURL,
                                               id annotation) {
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    NSMutableDictionary *debugOptions = [NSMutableDictionary dictionary];

    if (gBackground)
        options[FBSOpenApplicationOptionKeyActivateSuspended] = @YES;
    if (gNewInstance)
        options[FBSOpenApplicationWithNewScene] = @YES;
    if (gUnlockDevice) {
        options[FBSOpenApplicationOptionKeyUnlockDevice] = @YES;
        options[FBSOpenApplicationOptionKeyPromptUnlockDevice] = @YES;
    }
    if (payloadURL)
        options[FBSOpenApplicationOptionKeyPayloadURL] = payloadURL;
    if (annotation)
        options[FBSOpenApplicationOptionKeyPayloadAnnotation] = annotation;
    if (appArgs.count)
        debugOptions[FBSDebugOptionKeyArguments] = appArgs;
    if ([gEnvVars count])
        debugOptions[FBSDebugOptionKeyEnvironment] = gEnvVars;
    if (gStdoutURL)
        debugOptions[FBSDebugOptionKeyStandardOutPath] = [gStdoutURL path];
    if (gStderrURL)
        debugOptions[FBSDebugOptionKeyStandardErrorPath] = [gStderrURL path];
    if ([debugOptions count])
        options[FBSOpenApplicationOptionKeyDebuggingOptions] = debugOptions;

    if (targetProxy) {
        NSUUID *cacheGUID = [targetProxy cacheGUID];
        if ([targetProxy respondsToSelector:@selector(sequenceNumber)])
            options[FBSOpenApplicationOptionKeyLSSequenceNumber] =
                [NSNumber numberWithUnsignedInt:[targetProxy sequenceNumber]];
        if (cacheGUID)
            options[FBSOpenApplicationOptionKeyLSCacheGUID] = [cacheGUID UUIDString];
        if (payloadURL
            && [payloadURL isFileURL]
            && [[targetProxy applicationIdentifier] isEqualToString:kIOSTextEditBundleID]) {
            options[FBSOpenApplicationOptionKeyLaunchIntent] = @1;
            options[FBSOpenApplicationWithNewScene] = @YES;
        }
    }

    return options;
}

static NSString *savedApplicationStatePathForBundleIdentifier(NSString *bundleIdentifier) {
    if (!bundleIdentifier.length)
        return nil;
    return [kIOSSavedApplicationStateDir stringByAppendingPathComponent:
            [bundleIdentifier stringByAppendingString:@".savedState"]];
}

static NSError *clearSavedApplicationStateForBundleIdentifier(NSString *bundleIdentifier) {
    NSString *savedStatePath = savedApplicationStatePathForBundleIdentifier(bundleIdentifier);
    if (!savedStatePath.length)
        return nil;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:savedStatePath isDirectory:&isDirectory])
        return nil;

    NSError *error = nil;
    if ([fileManager removeItemAtPath:savedStatePath error:&error])
        return nil;
    return error;
}

static NSError *terminateApplication(id application, NSString *bundleIdentifier) {
    (void)application;
    if (!bundleIdentifier.length)
        return nil;

    id target = bundleIdentifier;
    FBSSystemService *service = [FBSSystemService sharedService];
    id processHandle = [service processHandleForApplication:target];
    BOOL isRunning = NO;
    if (processHandle && [processHandle respondsToSelector:@selector(isValid)])
        isRunning = [processHandle isValid];
    if (!isRunning)
        return nil;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *terminationError = nil;
    __block BOOL terminationSucceeded = NO;

    [service terminateApplication:target
                        forReason:5
                        andReport:NO
                  withDescription:@"Terminated by LaunchApp"
                       completion:^(BOOL success, NSError *error) {
                           terminationSucceeded = success;
                           if (error)
                               terminationError = [error retain];
                           dispatch_semaphore_signal(semaphore);
                       }];

    if (dispatch_semaphore_wait(semaphore,
                                dispatch_time(DISPATCH_TIME_NOW, 30LL * NSEC_PER_SEC)) != 0) {
        dispatch_release(semaphore);
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:
            @"Timed out waiting for FrontBoard to terminate the target application."
                                                           forKey:NSLocalizedDescriptionKey];
        return [NSError errorWithDomain:@"AKCmdsOpen"
                                   code:ETIMEDOUT
                               userInfo:userInfo];
    }

    dispatch_release(semaphore);

    if (terminationError)
        return [terminationError autorelease];
    if (!terminationSucceeded) {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:
            @"FrontBoard reported that the application did not terminate."
                                                           forKey:NSLocalizedDescriptionKey];
        return [NSError errorWithDomain:@"AKCmdsOpen"
                                   code:ESRCH
                               userInfo:userInfo];
    }

    for (NSUInteger attempt = 0; attempt < 40; attempt++) {
        id currentHandle = [service processHandleForApplication:target];
        BOOL stillRunning = NO;
        if (currentHandle && [currentHandle respondsToSelector:@selector(isValid)])
            stillRunning = [currentHandle isValid];
        if (!stillRunning)
            return nil;
        [NSThread sleepForTimeInterval:0.25];
    }

    {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:
            @"Timed out waiting for the target application to fully terminate."
                                                           forKey:NSLocalizedDescriptionKey];
        return [NSError errorWithDomain:@"AKCmdsOpen"
                                   code:ETIMEDOUT
                               userInfo:userInfo];
    }

    return nil;
}

static NSError *prepareFreshLaunchForApplication(id application, NSString *bundleIdentifier) {
    NSError *error = terminateApplication(application, bundleIdentifier);
    if (error)
        return error;

    // TextEdit can restore from recently-written scene state even after the
    // termination callback fires, so fresh relaunches need a conservative
    // settle window before and after clearing Saved Application State.
    [NSThread sleepForTimeInterval:5.0];

    error = clearSavedApplicationStateForBundleIdentifier(bundleIdentifier);
    if (error)
        return error;

    [NSThread sleepForTimeInterval:5.0];

    return nil;
}

static NSError *launchApplicationWithBundleIdentifier(NSString *bundleIdentifier, NSDictionary *options) {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *launchError = nil;

    FBSOpenApplicationService *service =
        [FBSOpenApplicationService serviceWithDefaultShellEndpoint];
    FBSOpenApplicationOptions *serviceOptions =
        [FBSOpenApplicationOptions optionsWithDictionary:options ?: @{}];

    [service openApplication:bundleIdentifier
                 withOptions:serviceOptions
                  completion:^(id processHandle, NSError *error) {
                      (void)processHandle;
                      if (error)
                          launchError = [error retain];
                      dispatch_semaphore_signal(semaphore);
                  }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    dispatch_release(semaphore);

    return [launchError autorelease];
}

static NSError *openURLWithWorkspace(LSApplicationWorkspace *workspace,
                                     NSURL *url,
                                     id annotation) {
    NSError *error = nil;
    BOOL success = NO;
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    if (annotation)
        options[UIApplicationOpenURLOptionsAnnotationKey] = annotation;

    if ([url isFileURL])
        success = [workspace openURL:url withOptions:options error:&error];
    else
        success = [workspace openSensitiveURL:url withOptions:options error:&error];

    if (success)
        return nil;
    return error;
}

static NSArray *applicationsAvailableForDocumentURL(LSApplicationWorkspace *workspace,
                                                    NSURL *url,
                                                    NSString *typeIdentifier,
                                                    NSString *mimeType) {
    if (!workspace || !url || ![url isFileURL])
        return @[];

    LSDocumentProxy *document = nil;
    if (typeIdentifier.length) {
        NSString *name = [url lastPathComponent];
        if (!name.length)
            name = @"untitled.txt";
        document = [LSDocumentProxy documentProxyForName:name
                                                    type:typeIdentifier
                                                MIMEType:mimeType];
    } else {
        document = [LSDocumentProxy documentProxyForURL:url];
    }

    if (!document)
        return @[];
    return [workspace applicationsAvailableForOpeningDocument:document] ?: @[];
}

static LSApplicationProxy *defaultTextEditorForURL(LSApplicationWorkspace *workspace, NSURL *url) {
    id first = [applicationsAvailableForDocumentURL(workspace,
                                                    url,
                                                    kIOSPlainTextUTI,
                                                    kIOSPlainTextMIME) firstObject];
    if ([first isKindOfClass:[LSApplicationProxy class]])
        return first;
    return nil;
}

static NSError *openDocumentURLWithWorkspace(LSApplicationWorkspace *workspace,
                                             NSURL *url,
                                             LSApplicationProxy *targetProxy,
                                             id annotation,
                                             BOOL replaceSourceWithCopiedFile) {
    NSString *bundleIdentifier = [targetProxy applicationIdentifier]
        ?: [targetProxy bundleIdentifier];
    if (!workspace || !url || !bundleIdentifier.length) {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:
            @"Document open request was missing required arguments."
                                                           forKey:NSLocalizedDescriptionKey];
        return [NSError errorWithDomain:@"AKCmdsOpen"
                                   code:EINVAL
                               userInfo:userInfo];
    }

    AKOpenResourceOperationDelegate *delegate =
        [[[AKOpenResourceOperationDelegate alloc] init] autorelease];
    id operation = [workspace operationToOpenResource:url
                                     usingApplication:bundleIdentifier
                             uniqueDocumentIdentifier:nil
                                             userInfo:annotation
                                             delegate:delegate];
    if (!operation) {
        NSDictionary *errorUserInfo = [NSDictionary dictionaryWithObject:
            @"LaunchServices did not create a document-open operation."
                                                          forKey:NSLocalizedDescriptionKey];
        return [NSError errorWithDomain:@"AKCmdsOpen"
                                   code:ENOENT
                               userInfo:errorUserInfo];
    }

    if ([operation respondsToSelector:@selector(start)])
        [operation start];

    if (![delegate waitForCompletionWithTimeout:dispatch_time(DISPATCH_TIME_NOW, 30LL * NSEC_PER_SEC)]) {
        NSDictionary *errorUserInfo = [NSDictionary dictionaryWithObject:
            @"Timed out waiting for LaunchServices to finish the document-open operation."
                                                              forKey:NSLocalizedDescriptionKey];
        return [NSError errorWithDomain:@"AKCmdsOpen"
                                   code:ETIMEDOUT
                               userInfo:errorUserInfo];
    }

    if ([delegate error])
        return [delegate error];

    NSURL *copiedURL = [delegate copiedURL];
    if ((gDefaultTextEditor || (gTextEdit && !gReadStdin))
        && copiedURL
        && [copiedURL isFileURL]) {
        fprintf(stdout, "Imported copy for editing: %s\n",
                [[[copiedURL path] description] UTF8String]);
    }

    if (replaceSourceWithCopiedFile) {
        if (!copiedURL || ![copiedURL isFileURL]) {
            NSDictionary *errorUserInfo = [NSDictionary dictionaryWithObject:
                @"LaunchServices did not report the copied Inbox file for stdin input."
                                                              forKey:NSLocalizedDescriptionKey];
            return [NSError errorWithDomain:@"AKCmdsOpen"
                                       code:ENOENT
                                   userInfo:errorUserInfo];
        }

        const char *sourcePath = [[url path] fileSystemRepresentation];
        const char *copiedPath = [[copiedURL path] fileSystemRepresentation];
        if (unlink(sourcePath) == -1) {
            int e = errno;
            NSDictionary *errorUserInfo = [NSDictionary dictionaryWithObject:
                [NSString stringWithFormat:@"Unable to unlink temporary stdin file %s: %s",
                                           sourcePath, strerror(e)]
                                                              forKey:NSLocalizedDescriptionKey];
            return [NSError errorWithDomain:@"AKCmdsOpen"
                                       code:e
                                   userInfo:errorUserInfo];
        }
        if (symlink(copiedPath, sourcePath) == -1) {
            int e = errno;
            NSDictionary *errorUserInfo = [NSDictionary dictionaryWithObject:
                [NSString stringWithFormat:@"Unable to redirect temporary stdin file %s to %s: %s",
                                           sourcePath, copiedPath, strerror(e)]
                                                              forKey:NSLocalizedDescriptionKey];
            return [NSError errorWithDomain:@"AKCmdsOpen"
                                       code:e
                                   userInfo:errorUserInfo];
        }
    }

    return nil;
}

static NSError *openUserActivityWithWorkspace(LSApplicationWorkspace *workspace,
                                              NSString *activityType,
                                              LSApplicationProxy *targetProxy,
                                              NSString *activityTitle,
                                              NSURL *webpageURL,
                                              NSDictionary *userInfo,
                                              NSDictionary *options) {
    if (!workspace || !activityType.length || !targetProxy) {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:
            @"User activity open request was missing required arguments."
                                                           forKey:NSLocalizedDescriptionKey];
        return [NSError errorWithDomain:@"AKCmdsOpen"
                                   code:EINVAL
                               userInfo:userInfo];
    }

    NSUserActivity *activity =
        [[[NSUserActivity alloc] initWithActivityType:activityType] autorelease];
    if (!activity) {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:
            @"Unable to create the requested NSUserActivity."
                                                           forKey:NSLocalizedDescriptionKey];
        return [NSError errorWithDomain:@"AKCmdsOpen"
                                   code:ENOMEM
                               userInfo:userInfo];
    }

    if ([activityTitle length])
        activity.title = activityTitle;
    if (webpageURL)
        activity.webpageURL = webpageURL;
    if ([userInfo count]) {
        [activity addUserInfoEntriesFromDictionary:userInfo];
        activity.requiredUserInfoKeys = [NSSet setWithArray:[userInfo allKeys]];
        activity.needsSave = YES;
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *activityError = nil;
    __block BOOL completed = NO;
    __block BOOL success = NO;

    if ([options count]) {
        SEL selector = @selector(openUserActivity:withApplicationProxy:options:completionHandler:);
        if (![workspace respondsToSelector:selector]) {
            dispatch_release(semaphore);
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:
                @"This system does not support launch-option user activity opens."
                                                               forKey:NSLocalizedDescriptionKey];
            return [NSError errorWithDomain:@"AKCmdsOpen"
                                       code:ENOTSUP
                                   userInfo:userInfo];
        }

        [workspace openUserActivity:activity
               withApplicationProxy:targetProxy
                            options:options
                  completionHandler:^(BOOL ok, NSError *error) {
                      completed = YES;
                      success = ok;
                      if (error)
                          activityError = [error retain];
                      dispatch_semaphore_signal(semaphore);
                  }];
    } else {
        [workspace openUserActivity:activity
               withApplicationProxy:targetProxy
                  completionHandler:^(BOOL ok, NSError *error) {
                      completed = YES;
                      success = ok;
                      if (error)
                          activityError = [error retain];
                      dispatch_semaphore_signal(semaphore);
                  }];
    }

    if (dispatch_semaphore_wait(semaphore,
                                dispatch_time(DISPATCH_TIME_NOW, 30LL * NSEC_PER_SEC)) != 0) {
        [activityError release];
        dispatch_release(semaphore);
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:
            @"Timed out waiting for LaunchServices to finish the user activity open."
                                                           forKey:NSLocalizedDescriptionKey];
        return [NSError errorWithDomain:@"AKCmdsOpen"
                                   code:ETIMEDOUT
                               userInfo:userInfo];
    }

    dispatch_release(semaphore);

    if (!completed) {
        [activityError release];
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:
            @"LaunchServices did not report a user activity completion result."
                                                           forKey:NSLocalizedDescriptionKey];
        return [NSError errorWithDomain:@"AKCmdsOpen"
                                   code:EIO
                               userInfo:userInfo];
    }

    if (!success) {
        if (activityError)
            return [activityError autorelease];
        return [NSError errorWithDomain:@"AKCmdsOpen"
                                   code:EIO
                               userInfo:[NSDictionary dictionaryWithObject:
                                         @"LaunchServices rejected the user activity open request."
                                                                    forKey:NSLocalizedDescriptionKey]];
    }

    [activityError release];
    return nil;
}

static BOOL explicitFileOpenNeedsFrontBoard(NSArray *appArgs) {
    return (gBackground
            || gNewInstance
            || gUnlockDevice
            || gWait
            || [appArgs count]
            || [gEnvVars count]
            || gStdoutURL
            || gStderrURL);
}

static BOOL allURLsAreFileURLs(NSArray *urls) {
    for (NSURL *url in urls) {
        if (![url isFileURL])
            return NO;
    }
    return YES;
}

static void waitForLaunchedApplications(NSArray *bundleIdentifiers) {
    if (!bundleIdentifiers.count)
        return;

    FBSSystemService *service = [FBSSystemService sharedService];
    BKSApplicationStateMonitor *monitor = [[BKSApplicationStateMonitor alloc] init];
    NSSet *uniqueBundleIdentifiers = [NSSet setWithArray:bundleIdentifiers];

    for (NSString *bundleIdentifier in uniqueBundleIdentifiers) {
        pid_t pid = 0;
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30.0];
        while ([deadline timeIntervalSinceNow] > 0.0) {
            pid = (pid_t)[service pidForApplication:bundleIdentifier];
            if (pid > 0)
                break;
            [NSThread sleepForTimeInterval:0.1];
        }

        if (pid <= 0)
            continue;

        for (;;) {
            BKSApplicationState state = [monitor mostElevatedApplicationStateForPID:pid];
            if (state == BKSApplicationStateUnknown || state == BKSApplicationStateTerminated)
                break;
            [NSThread sleepForTimeInterval:0.2];
        }
    }

    [monitor invalidate];
    [monitor release];
}

int main(int argc, const char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSMutableArray *extraURLs = [NSMutableArray array];
    NSMutableArray *appArgs   = nil;
    NSString *userActivityType = nil;
    NSString *userActivityTitle = nil;
    NSURL *userActivityWebpageURL = nil;
    NSMutableDictionary *userActivityInfo = nil;
    id launchAnnotation = nil;

    char **normalizedArgv = calloc((size_t)argc + 1, sizeof(char *));
    if (!normalizedArgv) {
        fputs("open: out of memory\n", stderr);
        [pool release];
        return 1;
    }

    for (int i = 0; i < argc; ++i) {
        if (strcmp(argv[i], "-intent") == 0)
            normalizedArgv[i] = (char *)"--intent";
        else if (strcmp(argv[i], "-userActivity") == 0)
            normalizedArgv[i] = (char *)"--userActivity";
        else if (strcmp(argv[i], "-userActivityTitle") == 0)
            normalizedArgv[i] = (char *)"--userActivityTitle";
        else if (strcmp(argv[i], "-userActivityWebpageURL") == 0)
            normalizedArgv[i] = (char *)"--userActivityWebpageURL";
        else if (strcmp(argv[i], "-userActivityInfo") == 0)
            normalizedArgv[i] = (char *)"--userActivityInfo";
        else
            normalizedArgv[i] = (char *)argv[i];
    }

    int argc2 = argc;
    const char **argv2 = (const char **)normalizedArgv;
    const char **scanArgv = argv2;
    for (int remaining = argc; remaining > 0; --remaining, ++scanArgv) {
        char *arg = (char *)*scanArgv;
        if (gArgsSeen) {
            if (!appArgs)
                appArgs = [NSMutableArray array];
            NSString *s = stringFromArg(arg);
            if (s)
                [appArgs addObject:s];
            *arg = '\0';
            --argc2;
        } else if (strcmp(arg, "--args") == 0) {
            gArgsSeen = YES;
            *arg = '\0';
            --argc2;
        }
    }

    struct option longopts[] = {
        { "new",        no_argument,       (int *)&gNewInstance,        1 },
        { "background", no_argument,       (int *)&gBackground,         1 },
        { "hide",       no_argument,       (int *)&gHideApp,            1 },
        { "reveal",     no_argument,       (int *)&gReveal,             1 },
        { "wait-apps",  no_argument,       (int *)&gWait,               1 },
        { "no-recents", no_argument,       (int *)&gExcludeFromRecents, 1 },
        { "header",     no_argument,       NULL, 'h' },
        { "fresh",      no_argument,       (int *)&gFresh,              1 },
        { "unlock",     no_argument,       (int *)&gUnlockDevice,       1 },
        { "intent",     no_argument,       (int *)&gLaunchIntent,       1 },
        { "userActivity", required_argument, NULL, 'Y' },
        { "userActivityTitle", required_argument, NULL, 'Z' },
        { "userActivityWebpageURL", required_argument, NULL, 'P' },
        { "userActivityInfo", required_argument, NULL, 'U' },
        { "annotation", required_argument, NULL, 'J' },
        { "stdin",      required_argument, NULL, 'i' },
        { "stdout",     required_argument, NULL, 'o' },
        { "stderr",     required_argument, NULL, 'E' },
        { "env",        required_argument, NULL, 'V' },
        { "url",        required_argument, NULL, 'u' },
        { "help",       no_argument,       NULL, 'k' },
        { NULL, 0, NULL, 0 }
    };

    NSString *appName = nil;
    NSString *bundleIdentifier = nil;

    int ch;
    while ((ch = getopt_long(argc2, (char *const *)argv2,
                             "etfFb:a:s:WRnghHvjxi:o:E:u:Y:Z:P:U:J:", longopts, NULL)) != -1) {
        switch (ch) {
            case 0:
                break;
            case 'E':
                [gStderrURL release];
                gStderrURL = [[NSURL fileURLWithFileSystemRepresentation:optarg
                                                             isDirectory:NO
                                                         relativeToURL:nil] retain];
                break;
            case 'F': gFresh = YES; break;
            case 'H': gHeaderMode = YES; gHideInternalSDKs = YES; break;
            case 'J':
                [launchAnnotation release];
                launchAnnotation = [parseJSONPropertyListArgument(optarg, @"--annotation") retain];
                break;
            case 'R': gReveal = YES; break;
            case 'P': {
                NSString *arg = stringFromArg(optarg);
                NSURL *url = arg.length ? [NSURL URLWithString:arg] : nil;
                if (!url || ![url scheme]) {
                    dieWithError([NSString stringWithFormat:
                        @"Unable to interpret '%s' as a URL", optarg]);
                }
                [userActivityWebpageURL release];
                userActivityWebpageURL = [url retain];
                break;
            }
            case 'U': {
                NSString *item = [NSString stringWithUTF8String:optarg];
                NSRange range = [item rangeOfString:@"="];
                if (range.location == NSNotFound || range.location == 0) {
                    dieWithError([NSString stringWithFormat:
                        @"The --userActivityInfo option requires KEY=VALUE, got '%@'",
                        item ?: @""]);
                }
                NSString *key = [item substringToIndex:range.location];
                if ([key isEqualToString:@"NSUserActivityDocumentURLKey"]
                    || [key isEqualToString:@"NSUserActivityDocumentURL"]) {
                    dieWithError(
                        @"NSUserActivityDocumentURLKey is not supported on the iOS "
                         "user-activity open path. The system strips that payload.");
                }
                NSString *value = [item substringFromIndex:range.location + 1];
                if (!userActivityInfo)
                    userActivityInfo = [[NSMutableDictionary dictionary] retain];
                userActivityInfo[key] = value ?: @"";
                break;
            }
            case 'V': {
                if (optarg && *optarg) {
                    char *eq = strchr(optarg, '=');
                    NSString *key = nil;
                    NSString *val = nil;
                    if (eq) {
                        ptrdiff_t keyLength = eq - optarg;
                        if (keyLength >= 1) {
                            key = [[[NSString alloc] initWithBytes:optarg
                                                             length:(NSUInteger)keyLength
                                                           encoding:NSUTF8StringEncoding] autorelease];
                            val = [[[NSString alloc] initWithCString:eq + 1
                                                             encoding:NSUTF8StringEncoding] autorelease];
                        }
                    } else {
                        key = [NSString stringWithUTF8String:optarg];
                        val = @"";
                    }

                    if (!key) {
                        fputs([[NSString stringWithFormat:
                            @"Ignoring incorrectly formatted environment variable %s", optarg] UTF8String],
                              stderr);
                        fputc('\n', stderr);
                        break;
                    }

                    if (!gEnvVars)
                        gEnvVars = [[NSMutableDictionary dictionary] retain];
                    gEnvVars[key] = val ?: @"";
                }
                break;
            }
            case 'W': gWait = YES; break;
            case 'a':
                appName = [NSString stringWithUTF8String:optarg];
                break;
            case 'b':
                bundleIdentifier = [NSString stringWithUTF8String:optarg];
                break;
            case 'e': gTextEdit = YES; break;
            case 'f': gReadStdin = YES; break;
            case 'g': gBackground = YES; break;
            case 'h': gHeaderMode = YES; gHideInternalSDKs = NO; break;
            case 'i':
                [gStdinURL release];
                gStdinURL = [[NSURL fileURLWithFileSystemRepresentation:optarg
                                                            isDirectory:NO
                                                        relativeToURL:nil] retain];
                break;
            case 'j': gHideApp = YES; break;
            case 'n': gNewInstance = YES; break;
            case 'o':
                [gStdoutURL release];
                gStdoutURL = [[NSURL fileURLWithFileSystemRepresentation:optarg
                                                             isDirectory:NO
                                                         relativeToURL:nil] retain];
                break;
            case 's':
                gSDKFilter = [NSString stringWithUTF8String:optarg];
                break;
            case 't': gDefaultTextEditor = YES; break;
            case 'u': {
                NSString *s = stringFromArg(optarg);
                NSURL *url = s ? [NSURL URLWithString:s] : nil;
                if (!url || ![url scheme]) {
                    dieWithError([NSString stringWithFormat:
                        @"Unable to interpret '%s' as a URL", optarg]);
                }
                [extraURLs addObject:url];
                break;
            }
            case 'v': gVerbose = YES; break;
            case 'x': gExcludeFromRecents = YES; break;
            case 'Y':
                userActivityType = [NSString stringWithUTF8String:optarg];
                break;
            case 'Z':
                userActivityTitle = [NSString stringWithUTF8String:optarg];
                break;
            case 'k':
                printUsage(getprogname());
                free(normalizedArgv);
                [pool release];
                return 0;
            default:
                printUsage(getprogname());
                free(normalizedArgv);
                [pool release];
                return 1;
        }
    }

    if (gHideApp || gExcludeFromRecents || gStdinURL) {
        if (gHideApp)
            dieWithError(@"The -j option is not supported on iOS.");
        if (gExcludeFromRecents)
            dieWithError(@"The -x option is not supported on iOS.");
        if (gStdinURL)
            dieWithError(@"The -i option is not supported on iOS.");
    }

    if (userActivityType && ![userActivityType length])
        dieWithError(@"The --userActivity option requires a non-empty activity type.");

    if (!userActivityType
        && (userActivityTitle
            || userActivityWebpageURL
            || [userActivityInfo count])) {
        dieWithError(
            @"The --userActivityTitle, --userActivityWebpageURL, "
             "and --userActivityInfo options "
             "require --userActivity on iOS.");
    }

    if ((appName && bundleIdentifier)
        || ((appName || bundleIdentifier) && (gTextEdit || gDefaultTextEditor || gReadStdin))) {
        dieWithError(@"Conflicting application-selection options were provided.");
    }

    if (gReveal) {
        if (gTextEdit || gDefaultTextEditor || gReadStdin)
            dieWithError(@"The -R option cannot be combined with -e, -t, or -f on iOS.");
        if (userActivityType)
            dieWithError(@"The -R option cannot be combined with --userActivity on iOS.");
        if (launchAnnotation)
            dieWithError(@"The --annotation option is not supported with -R on iOS.");
        if (appName || bundleIdentifier)
            dieWithError(@"The -R option does not accept -a or -b on iOS.");
        if (gFresh || gBackground || gNewInstance || gLaunchIntent || gUnlockDevice || gWait
            || [appArgs count] || [gEnvVars count] || gStdoutURL || gStderrURL) {
            dieWithError(@"The -R option is not supported with additional launch options on iOS.");
        }
        if ([extraURLs count])
            dieWithError(@"The -R option only supports a single file path on iOS.");
    }

    NSMutableArray *rawArgs = [NSMutableArray array];
    for (int i = optind; i < argc2; ++i) {
        if (!argv2[i] || !argv2[i][0])
            continue;
        NSString *arg = stringFromArg(argv2[i]);
        if (arg)
            [rawArgs addObject:arg];
    }

    if (gHeaderMode) {
        NSMutableArray *searchRoots = [NSMutableArray array];
        NSMutableArray *sdkDirectories = [NSMutableArray array];
        NSFileManager *fm = [NSFileManager defaultManager];
        const char *sdkRootEnv = getenv("SDKROOT");

        if (sdkRootEnv && *sdkRootEnv) {
            NSString *sdkRoot = [fm stringWithFileSystemRepresentation:sdkRootEnv
                                                                length:strlen(sdkRootEnv)];
            if ([[sdkRoot pathExtension] isEqualToString:@"sdk"]
                && (!gHideInternalSDKs
                    || [[sdkRoot lastPathComponent] rangeOfString:@".Internal"
                                                           options:NSCaseInsensitiveSearch].location
                        == NSNotFound)
                && [fm fileExistsAtPath:sdkRoot isDirectory:NULL]) {
                [sdkDirectories addObject:sdkRoot];
            }
        }

        BOOL useVarJB = NO;
        struct stat varJBStat;
        if (lstat("/var/jb", &varJBStat) == 0 && S_ISLNK(varJBStat.st_mode)) {
            char linkTarget[PATH_MAX];
            ssize_t linkLength = readlink("/var/jb", linkTarget, sizeof(linkTarget) - 1);
            if (linkLength > 0) {
                linkTarget[linkLength] = '\0';
                useVarJB = (strncmp(linkTarget, "/private/preboot/", strlen("/private/preboot/")) == 0);
            }
        }

        NSMutableArray *sdkParentDirs = [NSMutableArray array];
        if (useVarJB) {
            [sdkParentDirs addObject:@"/var/jb/usr/share/SDKs"];
        } else {
            [sdkParentDirs addObject:@"/usr/share/SDKs"];
        }

        for (NSString *sdkParentDir in sdkParentDirs) {
            BOOL isDirectory = NO;
            if (![fm fileExistsAtPath:sdkParentDir isDirectory:&isDirectory] || !isDirectory)
                continue;

            NSArray *entries = [fm contentsOfDirectoryAtPath:sdkParentDir error:nil];
            for (NSString *entry in entries) {
                if (![[entry pathExtension] isEqualToString:@"sdk"])
                    continue;
                if (gHideInternalSDKs
                    && [entry rangeOfString:@".Internal"
                                     options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    continue;
                }
                if (gSDKFilter && [entry rangeOfString:gSDKFilter].location == NSNotFound)
                    continue;
                NSString *sdkDir = [sdkParentDir stringByAppendingPathComponent:entry];
                BOOL sdkIsDir = NO;
                if ([fm fileExistsAtPath:sdkDir isDirectory:&sdkIsDir] && sdkIsDir)
                    [sdkDirectories addObject:sdkDir];
            }
        }

        [sdkDirectories sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [[b lastPathComponent] compare:[a lastPathComponent]];
        }];

        NSArray *plainRoots = useVarJB
            ? @[ @"/usr/include",
                 @"/usr/local/include",
                 @"/System/Library/Frameworks",
                 @"/System/Library/PrivateFrameworks",
                 @"/var/jb/usr/include",
                 @"/var/jb/usr/local/include" ]
            : @[ @"/usr/include",
                 @"/usr/local/include",
                 @"/System/Library/Frameworks",
                 @"/System/Library/PrivateFrameworks" ];
        for (NSString *root in plainRoots) {
            BOOL isDirectory = NO;
            if ([fm fileExistsAtPath:root isDirectory:&isDirectory] && isDirectory)
                [searchRoots addObject:root];
        }

        NSArray *sdkSubdirs = @[ @"System/Library/Frameworks",
                                 @"System/Library/PrivateFrameworks",
                                 @"usr/include",
                                 @"usr/local/include",
                                 @"Developer/Library/Frameworks" ];
        for (NSString *sdkDir in sdkDirectories) {
            for (NSString *subdir in sdkSubdirs) {
                NSString *root = [sdkDir stringByAppendingPathComponent:subdir];
                BOOL isDirectory = NO;
                if ([fm fileExistsAtPath:root isDirectory:&isDirectory] && isDirectory)
                    [searchRoots addObject:root];
            }
        }

        HeaderOpenState *state = [[[HeaderOpenState alloc]
            initWithRemainingHeaders:[NSMutableArray arrayWithArray:rawArgs]]
            autorelease];
        state.searchRoots = searchRoots;
        [state performFastPathSearch];

        if (!state.finished) {
            for (NSString *root in searchRoots) {
                if ([root hasSuffix:@"Frameworks"])
                    scanFrameworksDirectory(root, state);
                else
                    scanHeadersDirectory(root, state);
                if (state.finished)
                    break;
            }
        }

        NSDictionary *headerMap = [state headersToHeaderPaths];
        NSMutableArray *notFound = [NSMutableArray array];
        for (NSString *header in rawArgs) {
            if (![[headerMap objectForKey:header] count])
                [notFound addObject:header];
        }

        if (notFound.count) {
            NSString *plural = notFound.count == 1 ? @"" : @"s";
            NSString *list = joinArrayWithConjunction(notFound, @"or");
            dieWithError([NSString stringWithFormat:
                @"Unable to find header file%@ matching %@", plural, list]);
        }

        NSMutableArray *chosen = [NSMutableArray array];
        NSCharacterSet *sepSet = [[NSCharacterSet whitespaceAndNewlineCharacterSet] mutableCopy];
        [(NSMutableCharacterSet *)sepSet addCharactersInString:@","];
        NSCharacterSet *immutable = [sepSet copy];
        [sepSet release];

        for (NSString *header in rawArgs) {
            NSArray *hits = headerMap[header];
            if (hits.count == 1) {
                [chosen addObject:hits[0]];
                continue;
            }

            printf("%s?\n", [header UTF8String]);
            puts("[0]\tcancel");
            puts("[1]\tall");
            putchar('\n');
            for (NSUInteger idx = 0; idx < hits.count; ++idx)
                printf("[%lu]\t%s\n", (unsigned long)(idx + 2), [hits[idx] UTF8String]);

            printf("\nWhich header(s) for \"%s\"? ", [header UTF8String]);
            fflush(stdout);

            NSMutableArray *selected = [NSMutableArray array];
            int selectionCount = 0;
            while (selectionCount < 1) {
                char lineBuf[1024];
                bzero(lineBuf, sizeof(lineBuf));
                if (!fgets(lineBuf, sizeof(lineBuf), stdin))
                    dieWithError(@"Cancelled.");
                while (!strchr(lineBuf, '\n') && fgets(lineBuf, sizeof(lineBuf), stdin))
                    ;
                NSString *line = [NSString stringWithUTF8String:lineBuf];
                if (!line)
                    break;
                NSScanner *scanner = [NSScanner scannerWithString:line];
                [scanner setCharactersToBeSkipped:immutable];
                selectionCount = 0;
                while (![scanner isAtEnd]) {
                    int value = -1;
                    if (![scanner scanInt:&value])
                        break;
                    ++selectionCount;
                    if (value == 1) {
                        [selected addObjectsFromArray:hits];
                    } else if (value == 0) {
                        gCancelled = YES;
                        break;
                    } else if (value < 2 || (NSUInteger)value >= hits.count + 2) {
                        NSString *msg = [NSString stringWithFormat:
                            @"Please enter values in the range 0 through %lu",
                            (unsigned long)(hits.count + 1)];
                        fputs([msg UTF8String], stderr);
                        fputc('\n', stderr);
                        [scanner setScanLocation:line.length];
                        selectionCount = 0;
                    } else {
                        [selected addObject:hits[value - 2]];
                    }
                }
            }
            if (selectionCount >= 1)
                [chosen addObjectsFromArray:selected];
        }
        [immutable release];

        NSMutableArray *deduped = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (NSString *path in chosen) {
            if (![seen member:path]) {
                [seen addObject:path];
                [deduped addObject:path];
            }
        }
        rawArgs = deduped;

        if (!appName && !bundleIdentifier && !gTextEdit && !gDefaultTextEditor
            && !gReadStdin && !gReveal) {
            gDefaultTextEditor = YES;
        }
    }

    if (userActivityType) {
        if (gTextEdit || gDefaultTextEditor || gReadStdin)
            dieWithError(@"The --userActivity option cannot be combined with -e, -t, or -f on iOS.");
        if ([extraURLs count] || [rawArgs count])
            dieWithError(
                @"The --userActivity option does not accept file or URL operands on iOS. "
                 "Use --userActivityWebpageURL and --userActivityInfo instead.");
        if (gBackground)
            dieWithError(@"The -g option is not supported with --userActivity on iOS.");
        if (launchAnnotation)
            dieWithError(@"The --annotation option is not supported with --userActivity on iOS.");
    }

    NSMutableArray *pendingURLs = [NSMutableArray array];
    NSMutableArray *fileArgs = [NSMutableArray array];
    NSMutableArray *bundleLaunchIdentifiers = [NSMutableArray array];
    NSURL *stdinTempURL = nil;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *tempDirCandidates = @[kIOSPrivateTmpDir, kIOSTmpDir, kIOSJBTmpDir];
    NSString *stdinTempDir = nil;
    for (NSString *candidate in tempDirCandidates) {
        BOOL isDirectory = NO;
        if (![fileManager fileExistsAtPath:candidate isDirectory:&isDirectory] || !isDirectory)
            continue;
        if (access([candidate fileSystemRepresentation], W_OK | X_OK) == 0) {
            stdinTempDir = candidate;
            break;
        }
    }

    LSApplicationWorkspace *workspace = [LSApplicationWorkspace defaultWorkspace];
    NSArray *installedApplications = [workspace allInstalledApplications] ?: @[];
    LSApplicationProxy *explicitTargetProxy = nil;

    if (gTextEdit || gReadStdin) {
        explicitTargetProxy = findApplicationByBundleIdentifier(installedApplications,
                                                                kIOSTextEditBundleID);
        if (!explicitTargetProxy)
            dieWithError(@"TextEdit is not available on this device.");
    } else if (gDefaultTextEditor) {
        explicitTargetProxy = nil;
    } else if (bundleIdentifier) {
        explicitTargetProxy = findApplicationByBundleIdentifier(installedApplications,
                                                                bundleIdentifier);
        if (!explicitTargetProxy) {
            dieWithError([NSString stringWithFormat:
                @"Unable to find application with bundle identifier '%@'",
                bundleIdentifier]);
        }
    } else if (appName) {
        explicitTargetProxy = findApplicationByName(installedApplications, appName);
        if (!explicitTargetProxy) {
            dieWithError([NSString stringWithFormat:
                @"Unable to find application named '%@'",
                appName]);
        }
    }

    if (gReadStdin) {
        if (!stdinTempDir) {
            dieWithError([NSString stringWithFormat:
                @"Unable to find a writable temporary directory. Tried %@.",
                [tempDirCandidates componentsJoinedByString:@", "]]);
        }

        char tmpPath[PATH_MAX];
        snprintf(tmpPath, sizeof(tmpPath), "%s/open_XXXXXXXX.txt",
                 [stdinTempDir fileSystemRepresentation]);
        int fd = mkstemps(tmpPath, 4);
        if (fd == -1) {
            int e = errno;
            dieWithError([NSString stringWithFormat:
                @"Unable to open temporary file.  The error was %d: %s", e, strerror(e)]);
        }

        char buffer[0x1000];
        size_t n;
        while ((n = fread(buffer, 1, sizeof(buffer), stdin)) > 0) {
            for (size_t written = 0; written < n; ) {
                ssize_t w = write(fd, buffer + written, n - written);
                if (w < 0) {
                    int e = errno;
                    close(fd);
                    dieWithError([NSString stringWithFormat:
                        @"Unable to write to temporary file %s.  The error was %d: %s",
                        tmpPath, e, strerror(e)]);
                }
                written += (size_t)w;
            }
        }

        if (close(fd) == -1) {
            int e = errno;
            dieWithError([NSString stringWithFormat:
                @"Unable to close temporary file %s.  The error was %d: %s",
                tmpPath, e, strerror(e)]);
        }

        if (chmod(tmpPath, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH) == -1) {
            int e = errno;
            dieWithError([NSString stringWithFormat:
                @"Unable to adjust permissions on temporary file %s.  The error was %d: %s",
                tmpPath, e, strerror(e)]);
        }

        NSURL *stdinURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:tmpPath]
                                     isDirectory:NO];
        stdinTempURL = stdinURL;
        [pendingURLs addObject:stdinURL];
        [fileArgs addObject:[stdinURL path]];
    }

    for (NSString *rawArg in rawArgs) {
        NSString *expanded = [rawArg stringByExpandingTildeInPath];
        BOOL isDirectory = NO;

        if ([fileManager fileExistsAtPath:expanded isDirectory:&isDirectory]) {
            if (!explicitTargetProxy && !gReveal) {
                LSApplicationProxy *pathApp = findApplicationByPath(installedApplications, expanded);
                if (pathApp) {
                    NSString *identifier = [pathApp applicationIdentifier];
                    if (![bundleLaunchIdentifiers containsObject:identifier])
                        [bundleLaunchIdentifiers addObject:identifier];
                    continue;
                }
            }

            [pendingURLs addObject:[NSURL fileURLWithPath:expanded isDirectory:isDirectory]];
            [fileArgs addObject:expanded];
            continue;
        }

        NSURL *url = [NSURL URLWithString:rawArg];
        if ([rawArg containsString:@":"]
            && url
            && [[url scheme] length] > 0) {
            [pendingURLs addObject:url];
            continue;
        }

        dieWithError([NSString stringWithFormat:
            @"The file %@ does not exist.", expanded]);
    }

    [pendingURLs addObjectsFromArray:extraURLs];

    if (gReveal) {
        if (![pendingURLs count])
            dieWithError(@"The -R option requires a file path on iOS.");
        if ([pendingURLs count] > 1) {
            dieWithError(
                @"The -R option currently supports only a single file path on iOS.");
        }

        NSURL *targetURL = [pendingURLs firstObject];
        if (![targetURL isFileURL])
            dieWithError(@"The -R option only supports file paths on iOS.");

        LSApplicationProxy *filzaProxy = findApplicationByBundleIdentifier(installedApplications,
                                                                           kIOSFilzaBundleID);
        if (!filzaProxy || [filzaProxy isLaunchProhibited]) {
            dieWithError(
                @"The -R option requires a usable Filza installation on iOS.");
        }

        NSString *filzaBundlePath = [[filzaProxy bundleURL] path];
        if (!filzaBundlePath.length) {
            dieWithError(
                @"The -R option requires a usable Filza installation on iOS.");
        }

        NSDictionary *filzaInfoPlist =
            [NSDictionary dictionaryWithContentsOfFile:
                [filzaBundlePath stringByAppendingPathComponent:@"Info.plist"]];
        BOOL filzaSupportsRevealURL = NO;
        NSArray *urlTypes = [filzaInfoPlist objectForKey:@"CFBundleURLTypes"];
        if ([urlTypes isKindOfClass:[NSArray class]]) {
            for (id typeEntry in urlTypes) {
                if (![typeEntry isKindOfClass:[NSDictionary class]])
                    continue;
                NSArray *schemes = [typeEntry objectForKey:@"CFBundleURLSchemes"];
                if (![schemes isKindOfClass:[NSArray class]])
                    continue;
                for (id scheme in schemes) {
                    if ([scheme isKindOfClass:[NSString class]]
                        && [(NSString *)scheme caseInsensitiveCompare:@"filza"] == NSOrderedSame) {
                        filzaSupportsRevealURL = YES;
                        break;
                    }
                }
                if (filzaSupportsRevealURL)
                    break;
            }
        }

        if (!filzaSupportsRevealURL) {
            dieWithError(
                @"The -R option requires a usable Filza installation on iOS.");
        }

        NSString *targetPath = [targetURL path];
        NSString *encodedPath =
            [targetPath stringByAddingPercentEncodingWithAllowedCharacters:
                [NSCharacterSet URLPathAllowedCharacterSet]];
        NSURL *filzaRevealURL = nil;
        if (encodedPath.length) {
            filzaRevealURL = [NSURL URLWithString:
                [kIOSFilzaRevealPrefix stringByAppendingString:encodedPath]];
        }
        if (!filzaRevealURL) {
            dieWithError([NSString stringWithFormat:
                @"Unable to construct a Filza reveal URL for %@",
                targetPath]);
        }

        [pendingURLs removeAllObjects];
        [pendingURLs addObject:filzaRevealURL];
        explicitTargetProxy = filzaProxy;
    }

    if (gDefaultTextEditor) {
        for (NSURL *url in pendingURLs) {
            if (![url isFileURL])
                dieWithError(@"The -t option only supports file paths on iOS.");
        }

        NSURL *resolutionURL = nil;
        for (NSURL *url in pendingURLs) {
            if ([url isFileURL]) {
                resolutionURL = url;
                break;
            }
        }
        if (!resolutionURL) {
            resolutionURL = [NSURL fileURLWithPath:
                [(stdinTempDir ?: kIOSPrivateTmpDir) stringByAppendingPathComponent:@"untitled.txt"]
                                       isDirectory:NO];
        }

        explicitTargetProxy = defaultTextEditorForURL(workspace, resolutionURL);
        if (!explicitTargetProxy)
            dieWithError(@"Unable to determine the default plain-text editor.");
    }

    if (userActivityType && !explicitTargetProxy) {
        NSArray *matches = findApplicationsByUserActivityType(installedApplications,
                                                              userActivityType);
        if ([matches count] > 1) {
            NSMutableArray *descriptions = [NSMutableArray array];
            for (LSApplicationProxy *candidate in matches) {
                NSString *displayName = [candidate localizedNameForContext:nil]
                    ?: [candidate itemName]
                    ?: [candidate applicationIdentifier];
                [descriptions addObject:[NSString stringWithFormat:@"%@ (%@)",
                                        displayName ?: @"<unknown>",
                                        [candidate applicationIdentifier] ?: @"<unknown>"]];
            }
            dieWithError([NSString stringWithFormat:
                @"Multiple applications declare user activity type '%@': %@",
                userActivityType,
                [descriptions componentsJoinedByString:@", "]]);
        }

        explicitTargetProxy = [workspace applicationForUserActivityType:userActivityType];
        if (!explicitTargetProxy) {
            if ([matches count] == 1) {
                explicitTargetProxy = [matches firstObject];
            }
        }
        if (!explicitTargetProxy) {
            dieWithError([NSString stringWithFormat:
                @"Unable to find an application for user activity type '%@'",
                userActivityType]);
        }
    }

    if ([explicitTargetProxy isLaunchProhibited]) {
        NSString *displayName = [explicitTargetProxy localizedNameForContext:nil]
            ?: [explicitTargetProxy itemName]
            ?: [explicitTargetProxy applicationIdentifier];
        dieWithError([NSString stringWithFormat:
            @"The application '%@' cannot be launched on this device.", displayName]);
    }

    if (!explicitTargetProxy && !pendingURLs.count && !bundleLaunchIdentifiers.count && !userActivityType) {
        printUsage(getprogname());
        [pool release];
        free(normalizedArgv);
        return 1;
    }

    if (launchAnnotation && !pendingURLs.count) {
        dieWithError(@"The --annotation option requires a file path or URL operand on iOS.");
    }
    if (launchAnnotation && !explicitTargetProxy) {
        dieWithError(
            @"The --annotation option is only supported for explicit application opens on iOS. "
             "Use -a, -b, -e, -t, or -f.");
    }
    if (launchAnnotation && pendingURLs.count > 1) {
        dieWithError(
            @"The --annotation option currently supports only a single file path or URL operand on iOS.");
    }
    if (gFresh && !explicitTargetProxy && !bundleLaunchIdentifiers.count) {
        dieWithError(@"The -F option requires an explicit application on iOS.");
    }

    if ((gDefaultTextEditor || (gTextEdit && !gReadStdin)) && pendingURLs.count) {
        fputs("Note: on iOS, -e and -t import a copy into the target app for editing. "
              "Edits do not write back to the original path.\n",
              stderr);
    }

    BOOL requiresExplicitApplication = (gBackground
                                        || gNewInstance
                                        || gUnlockDevice
                                        || gLaunchIntent
                                        || gWait
                                        || [appArgs count]
                                        || [gEnvVars count]
                                        || gStdoutURL
                                        || gStderrURL);
    if (requiresExplicitApplication
        && !explicitTargetProxy
        && !bundleLaunchIdentifiers.count) {
        dieWithError(@"The requested launch options require an explicit application on iOS.");
    }

    if (gLaunchIntent
        && !userActivityType
        && explicitTargetProxy
        && pendingURLs.count
        && allURLsAreFileURLs(pendingURLs)
        && !explicitFileOpenNeedsFrontBoard(appArgs)) {
        dieWithError(@"The --intent option is not supported for local file document opens on iOS.");
    }

    NSMutableArray *launchedBundleIdentifiers = [NSMutableArray array];

    if (userActivityType) {
        NSString *targetBundleIdentifier = [explicitTargetProxy applicationIdentifier]
            ?: [explicitTargetProxy bundleIdentifier];
        if (gFresh) {
            NSError *freshError = prepareFreshLaunchForApplication(explicitTargetProxy,
                                                                   targetBundleIdentifier);
            if (freshError) {
                dieWithError([NSString stringWithFormat:
                    @"Failed to prepare a fresh launch for %@: %@",
                    targetBundleIdentifier ?: @"<unknown>",
                    freshError]);
            }
        }
        NSMutableDictionary *activityOptions =
            [buildLaunchOptions(appArgs, explicitTargetProxy, nil, nil) mutableCopy];
        NSMutableDictionary *activityUserInfo = nil;
        if ([userActivityInfo count])
            activityUserInfo = [[userActivityInfo mutableCopy] autorelease];
        else
            activityUserInfo = [NSMutableDictionary dictionary];
        if (gLaunchIntent)
            activityOptions[FBSOpenApplicationOptionKeyLaunchIntent] = @1;
        NSError *activityError =
            openUserActivityWithWorkspace(workspace,
                                          userActivityType,
                                          explicitTargetProxy,
                                          userActivityTitle,
                                          userActivityWebpageURL,
                                          activityUserInfo,
                                          activityOptions);
        [activityOptions release];
        if (activityError) {
            dieWithError([NSString stringWithFormat:
                @"Failed to open user activity %@ with %@: %@",
                userActivityType,
                targetBundleIdentifier ?: @"<unknown>",
                activityError]);
        }
        if (targetBundleIdentifier)
            [launchedBundleIdentifiers addObject:targetBundleIdentifier];
    } else if (explicitTargetProxy) {
        NSString *targetBundleIdentifier = [explicitTargetProxy applicationIdentifier]
            ?: [explicitTargetProxy bundleIdentifier];
        BOOL needsFrontBoard = explicitFileOpenNeedsFrontBoard(appArgs);

        if (gFresh) {
            NSError *freshError = prepareFreshLaunchForApplication(explicitTargetProxy,
                                                                   targetBundleIdentifier);
            if (freshError) {
                dieWithError([NSString stringWithFormat:
                    @"Failed to prepare a fresh launch for %@: %@",
                    targetBundleIdentifier ?: @"<unknown>",
                    freshError]);
            }
        }

        if ([pendingURLs count] > 1) {
            BOOL onlyFileURLs = allURLsAreFileURLs(pendingURLs);
            if (!onlyFileURLs || needsFrontBoard) {
                dieWithError(
                    @"Opening multiple URLs with a single explicit application is only "
                     "supported on iOS for local file paths without additional launch options.");
            }
        }

        if (!pendingURLs.count) {
            NSDictionary *launchOptions =
                buildLaunchOptions(appArgs, explicitTargetProxy, nil, launchAnnotation);
            NSError *launchError = launchApplicationWithBundleIdentifier(targetBundleIdentifier,
                                                                         launchOptions);
            if (launchError) {
                dieWithError([NSString stringWithFormat:
                    @"Failed to launch %@ with error: %@",
                    targetBundleIdentifier, launchError]);
            }
        } else {
            for (NSURL *url in pendingURLs) {
                if ([url isFileURL] && !needsFrontBoard) {
                    BOOL replaceSourceWithCopiedFile = NO;
                    if (stdinTempURL && [[url path] isEqualToString:[stdinTempURL path]])
                        replaceSourceWithCopiedFile = YES;
                    NSError *openError =
                        openDocumentURLWithWorkspace(workspace,
                                                    url,
                                                    explicitTargetProxy,
                                                    launchAnnotation,
                                                    replaceSourceWithCopiedFile);
                    if (openError) {
                        dieWithError([NSString stringWithFormat:
                            @"Failed to open %@ with %@: %@",
                            [url absoluteString], targetBundleIdentifier, openError]);
                    }
                } else {
                    NSError *launchError = nil;
                    NSDictionary *launchOptions =
                        buildLaunchOptions(appArgs,
                                           explicitTargetProxy,
                                           url,
                                           launchAnnotation);
                    launchError =
                        launchApplicationWithBundleIdentifier(targetBundleIdentifier, launchOptions);
                    if (launchError) {
                        dieWithError([NSString stringWithFormat:
                            @"Failed to open %@ with %@: %@",
                            [url absoluteString], targetBundleIdentifier, launchError]);
                    }
                }
            }
        }

        [launchedBundleIdentifiers addObject:targetBundleIdentifier];
    } else {
        for (NSString *launchBundleIdentifier in bundleLaunchIdentifiers) {
            LSApplicationProxy *proxy =
                findApplicationByBundleIdentifier(installedApplications, launchBundleIdentifier);
            if (gFresh) {
                NSError *freshError = prepareFreshLaunchForApplication(proxy,
                                                                       launchBundleIdentifier);
                if (freshError) {
                    dieWithError([NSString stringWithFormat:
                        @"Failed to prepare a fresh launch for %@: %@",
                        launchBundleIdentifier,
                        freshError]);
                }
            }
            NSDictionary *launchOptions = buildLaunchOptions(appArgs,
                                                             proxy,
                                                             nil,
                                                             launchAnnotation);
            NSError *launchError = launchApplicationWithBundleIdentifier(launchBundleIdentifier,
                                                                         launchOptions);
            if (launchError) {
                dieWithError([NSString stringWithFormat:
                    @"Failed to launch %@ with error: %@",
                    launchBundleIdentifier, launchError]);
            }
            [launchedBundleIdentifiers addObject:launchBundleIdentifier];
        }

        for (NSURL *url in pendingURLs) {
            NSError *openError = openURLWithWorkspace(workspace, url, launchAnnotation);
            if (openError) {
                dieWithError([NSString stringWithFormat:
                    @"Failed to open %@ with error: %@",
                    [url absoluteString], openError]);
            }
        }
    }

    if (gWait) {
        if (!launchedBundleIdentifiers.count)
            dieWithError(@"The -W option is only supported for explicitly launched applications on iOS.");
        waitForLaunchedApplications(launchedBundleIdentifiers);
    }

    free(normalizedArgv);
    [pool release];
    return 0;
}
