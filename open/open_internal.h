#pragma once

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if TARGET_OS_IPHONE
#import "ios_extern.h"
#else
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import "extern.h"
#endif

extern BOOL gVerbose;
extern BOOL gHideInternalSDKs;
extern NSString *gSDKFilter;
extern BOOL gBackground;
extern BOOL gWait;
extern BOOL gFresh;
extern BOOL gDefaultTextEditor;
extern BOOL gTextEdit;
extern BOOL gHideApp;
extern BOOL gNewInstance;
extern BOOL gExcludeFromRecents;
extern BOOL gReadStdin;
extern BOOL gArgsSeen;
extern BOOL gReveal;
extern BOOL gHeaderMode;
extern BOOL gCancelled;
extern NSURL *gStdinURL;
extern NSURL *gStdoutURL;
extern NSURL *gStderrURL;
extern NSMutableDictionary *gEnvVars;

@interface HeaderOpenState : NSObject
@property (nonatomic, retain) NSMutableArray      *remainingHeaders;
@property (nonatomic, retain) NSMutableDictionary *headersToHeaderPaths;
@property (nonatomic, retain) NSArray             *searchRoots;
@property (nonatomic, assign) BOOL                 finished;
- (instancetype)initWithRemainingHeaders:(NSArray *)headers;
- (void)visitPath:(NSString *)path;
- (void)visitHeader:(NSString *)name atPath:(NSString *)fullPath;
- (void)performFastPathSearch;
@end

NSString *stringFromArg(const char *cstr);
void dieWithError(NSString *msg) __attribute__((noreturn));
NSString *joinArrayWithConjunction(NSArray *items, NSString *conj);
NSMutableArray *mapArrayWithSelector(NSArray *array, SEL sel);
void checkFilesExistForArguments(NSArray *urls, NSArray *origArgs);

void scanHeadersDirectory(id dir, HeaderOpenState *state);
void scanFrameworksDirectory(id dir, HeaderOpenState *state);
NSMutableArray *getSDKPathsForPlatform(NSURL *platformURL);
