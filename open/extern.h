#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

typedef const struct __LSASN *LSASNRef;
typedef void (^LSOpenURLsCompletionHandler)(LSASNRef app, Boolean alreadyRunning, CFErrorRef error);

extern LSRolesMask LSGetOpenRoles(void);
extern CFArrayRef LSCopyApplicationURLsForBundleIdentifier(CFStringRef inBundleIdentifier,
                                                           CFErrorRef *outError);
extern CFURLRef LSCopyDefaultApplicationURLForContentType(CFStringRef inContentType,
                                                          LSRolesMask inRoleMask,
                                                          CFErrorRef *outError);
extern CFURLRef LSCopyDefaultApplicationURLForURL(CFURLRef inURL,
                                                  LSRolesMask inRoleMask,
                                                  CFErrorRef *outError);
extern void _LSOpenURLsWithCompletionHandler(CFArrayRef urls,
                                             CFURLRef appURL,
                                             CFDictionaryRef options,
                                             LSOpenURLsCompletionHandler handler);
extern Boolean _LSASNExtractHighAndLowParts(LSASNRef app, UInt32 *outHigh, UInt32 *outLow);

extern NSString *const _kLSOpenOptionWaitForApplicationToCheckInKey;
extern NSString *const _kLSOpenOptionHideKey;
extern NSString *const _kLSOpenOptionActivateKey;
extern NSString *const _kLSOpenOptionAddToRecentsKey;
extern NSString *const _kLSOpenOptionArgumentsKey;
extern NSString *const _kLSOpenOptionEnvironmentVariablesKey;
extern NSString *const _kLSOpenOptionAEParamKeyKey;
extern NSString *const _kLSOpenOptionAEParamDescKey;
extern NSString *const _kLSOpenOptionLaunchStdInPathKey;
extern NSString *const _kLSOpenOptionLaunchStdOutPathKey;
extern NSString *const _kLSOpenOptionLaunchStdErrPathKey;
extern NSString *const _kLSOpenOptionPreferRunningInstanceKey;
