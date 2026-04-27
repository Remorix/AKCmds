#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <objc/message.h>
#else
#import <AppKit/AppKit.h>
#endif
#import <CoreFoundation/CoreFoundation.h>
#import <langinfo.h>
#import <locale.h>
#import <stdlib.h>

#if TARGET_OS_IPHONE
extern NSAttributedStringDocumentType NSWebArchiveTextDocumentType;
#define kAppleWebArchivePasteboardType "Apple Web Archive pasteboard type"
#define kGeneralPasteboardName "com.apple.UIKit.pboard.general"
#define kNamedBoardPreferencesDomain "pbcopy.pboards"
#define kRTFScale 1.299f
#endif

int main(int argc, char *argv[])
{
    (void)argc;

    @autoreleasepool {
        NSStringEncoding encoding;
        NSStringEncoding convertedEncoding;
        NSString *programName;
        NSUserDefaults *defaults;
        NSArray *arguments;
        BOOL isPbcopy;
#if TARGET_OS_IPHONE
        BOOL useStoredNamedBoard;
        NSString *pasteboardName;
#else
        NSPasteboard *pasteboard;
#endif
        CFStringRef charsetName;
        CFStringEncoding cfEncoding;
        NSString *name;

        setlocale(LC_ALL, "");

        charsetName = CFStringCreateWithCString(NULL, nl_langinfo(CODESET), kCFStringEncodingUTF8);
        cfEncoding = CFStringConvertIANACharSetNameToEncoding(charsetName);
        if (charsetName != NULL) {
            CFRelease(charsetName);
        }

        convertedEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding);
        if (cfEncoding == kCFStringEncodingASCII
            || cfEncoding == kCFStringEncodingInvalidId
            || CFStringConvertNSStringEncodingToEncoding(convertedEncoding) == kCFStringEncodingInvalidId) {
            encoding = [NSString defaultCStringEncoding];
        } else {
            encoding = convertedEncoding;
        }

        programName = [[NSString stringWithCString:argv[0] encoding:encoding] lastPathComponent];
        defaults = [NSUserDefaults standardUserDefaults];
        arguments = [[NSProcessInfo processInfo] arguments];
        isPbcopy = [programName isEqualToString:@"pbcopy"];

        if ([arguments containsObject:@"-help"]
            || [arguments containsObject:@"-h"]
            || [arguments containsObject:@"-H"]) {
            if (isPbcopy) {
                NSLog(@"Usage: %@ [%@]", programName, @"-help");
            } else {
                NSLog(@"Usage: %@ [%@] [-%@ %@|%@|%@]",
                      programName,
                      @"-help",
                      @"Prefer",
                      @"rtf",
                      @"ps",
                      @"txt");
            }

            exit(0);
        }

        name = [defaults objectForKey:@"pboard"];

#if TARGET_OS_IPHONE
        useStoredNamedBoard = NO;
        pasteboardName = @kGeneralPasteboardName;

        if ([name isEqualToString:@"ruler"]) {
            useStoredNamedBoard = YES;
            pasteboardName = @"NSRulerPboard";
        } else if ([name isEqualToString:@"find"]) {
            useStoredNamedBoard = YES;
            pasteboardName = @"NSFindPboard";
        } else if ([name isEqualToString:@"font"]) {
            useStoredNamedBoard = YES;
            pasteboardName = @"NSFontPboard";
        }

#else
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if ([name isEqualToString:@"ruler"]) {
            pasteboard = [NSPasteboard pasteboardWithName:NSRulerPboard];
        } else if ([name isEqualToString:@"find"]) {
            pasteboard = [NSPasteboard pasteboardWithName:NSFindPboard];
        } else if ([name isEqualToString:@"font"]) {
            pasteboard = [NSPasteboard pasteboardWithName:NSFontPboard];
        } else {
            pasteboard = [NSPasteboard pasteboardWithName:NSGeneralPboard];
        }
#pragma clang diagnostic pop
#endif

#if TARGET_OS_IPHONE
        NSData *(^plainUTF8DataForString)(NSString *) = ^NSData *(NSString *value) {
            if (value == nil) {
                return nil;
            }
            return [value dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
        };
        NSAttributedString *(^attributedStringFromDataAndType)(NSData *, NSAttributedStringDocumentType) = ^NSAttributedString *(NSData *value, NSAttributedStringDocumentType documentType) {
            if (value == nil) {
                return nil;
            }
            return [[NSAttributedString alloc] initWithData:value
                                                    options:@{
                                                        NSDocumentTypeDocumentOption: documentType,
                                                    }
                                         documentAttributes:nil
                                                      error:nil];
        };
        NSData *(^outputDataFromAttributedString)(NSAttributedString *, NSString *) = ^NSData *(NSAttributedString *attributedString, NSString *preferredType) {
            if (attributedString == nil) {
                return nil;
            }
            if ([preferredType isEqualToString:@"rtf"]) {
                return [attributedString dataFromRange:NSMakeRange(0, attributedString.length)
                                    documentAttributes:@{
                                        NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType,
                                    }
                                                 error:nil];
            }
            return [[attributedString string] dataUsingEncoding:encoding allowLossyConversion:YES];
        };
        NSDictionary *(^richRTFPayload)(NSData *, NSString *) = ^NSDictionary *(NSData *rtfInputData, NSString *fallbackString) {
            NSMutableDictionary *payload;
            NSAttributedString *attributedString;
            NSData *plainData;

            payload = [NSMutableDictionary dictionary];
            attributedString = attributedStringFromDataAndType(rtfInputData, NSRTFTextDocumentType);
            if (attributedString != nil) {
                NSMutableAttributedString *scaledAttributedString;
                NSData *htmlData;
                NSData *webArchiveData;
                NSData *flatRTFDData;

                // Match TextEdit's size normalization for rich text.
                scaledAttributedString = [[NSMutableAttributedString alloc] initWithAttributedString:attributedString];
                [attributedString enumerateAttribute:NSFontAttributeName
                                             inRange:NSMakeRange(0, [attributedString length])
                                             options:0
                                          usingBlock:^(id value, NSRange range, BOOL *stop) {
                    UIFont *font;
                    UIFont *scaledFont;

                    (void)stop;
                    font = value;
                    if (![font isKindOfClass:[UIFont class]]) {
                        return;
                    }

                    scaledFont = [font fontWithSize:[font pointSize] * kRTFScale];
                    if (scaledFont != nil) {
                        [scaledAttributedString addAttribute:NSFontAttributeName
                                                       value:scaledFont
                                                       range:range];
                    }
                }];
                attributedString = scaledAttributedString;

                payload[@"public.rtf"] = [attributedString dataFromRange:NSMakeRange(0, attributedString.length)
                                                       documentAttributes:@{
                                                           NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType,
                                                       }
                                                                    error:nil] ?: rtfInputData;
                htmlData = [attributedString dataFromRange:NSMakeRange(0, attributedString.length)
                                        documentAttributes:@{
                                            NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
                                        }
                                                     error:nil];
                webArchiveData = [attributedString dataFromRange:NSMakeRange(0, attributedString.length)
                                               documentAttributes:@{
                                                   NSDocumentTypeDocumentAttribute: NSWebArchiveTextDocumentType,
                                               }
                                                            error:nil];
                flatRTFDData = [attributedString dataFromRange:NSMakeRange(0, attributedString.length)
                                            documentAttributes:@{
                                                NSDocumentTypeDocumentAttribute: NSRTFDTextDocumentType,
                                            }
                                                         error:nil];
                if (htmlData != nil) {
                    payload[@"public.html"] = htmlData;
                }
                if (webArchiveData != nil) {
                    payload[@"com.apple.webarchive"] = webArchiveData;
                }
                if (flatRTFDData != nil) {
                    payload[@"com.apple.flat-rtfd"] = flatRTFDData;
                }
                plainData = plainUTF8DataForString([attributedString string] ?: @"");
            } else {
                payload[@"public.rtf"] = rtfInputData;
                plainData = plainUTF8DataForString(fallbackString);
            }

            if (plainData != nil) {
                payload[@"public.utf8-plain-text"] = plainData;
                payload[@"public.plain-text"] = plainData;
            }
            return payload;
        };
        NSArray *(^candidateTypesForPreference)(NSString *, BOOL) = ^NSArray *(NSString *preferredType, BOOL includePrivateRTFD) {
            NSMutableArray *candidateTypes;

            candidateTypes = [NSMutableArray array];
            if ([preferredType isEqualToString:@"rtf"]) {
                [candidateTypes addObjectsFromArray:@[
                    @"public.rtf",
                    @kAppleWebArchivePasteboardType,
                    @"public.html",
                    @"com.apple.webarchive",
                    @"com.apple.flat-rtfd",
                ]];
                if (includePrivateRTFD) {
                    [candidateTypes addObject:@"com.apple.rtfd"];
                }
                [candidateTypes addObjectsFromArray:@[
                    @"public.utf8-plain-text",
                    @"public.plain-text",
                ]];
            } else if ([preferredType isEqualToString:@"ps"]) {
                [candidateTypes addObjectsFromArray:@[
                    @"com.adobe.encapsulated-postscript",
                    @"public.utf8-plain-text",
                    @"public.plain-text",
                ]];
            } else {
                [candidateTypes addObjectsFromArray:@[
                    @"public.utf8-plain-text",
                    @"public.plain-text",
                    @"com.adobe.encapsulated-postscript",
                    @kAppleWebArchivePasteboardType,
                    @"public.rtf",
                    @"public.html",
                    @"com.apple.webarchive",
                    @"com.apple.flat-rtfd",
                ]];
                if (includePrivateRTFD) {
                    [candidateTypes addObject:@"com.apple.rtfd"];
                }
            }
            return candidateTypes;
        };
        NSData *(^outputDataForRepresentation)(NSString *, NSData *, NSString *) = ^NSData *(NSString *representationType, NSData *representationData, NSString *preferredType) {
            NSAttributedString *attributedString;

            if ([representationType isEqualToString:@"public.rtf"]) {
                if ([preferredType isEqualToString:@"rtf"]) {
                    return representationData;
                }
                attributedString = attributedStringFromDataAndType(representationData, NSRTFTextDocumentType);
                return outputDataFromAttributedString(attributedString, preferredType);
            }
            if ([representationType isEqualToString:@"public.html"]
                || [representationType isEqualToString:@kAppleWebArchivePasteboardType]) {
                attributedString = attributedStringFromDataAndType(representationData, NSHTMLTextDocumentType);
                return outputDataFromAttributedString(attributedString, preferredType);
            }
            if ([representationType isEqualToString:@"com.apple.webarchive"]) {
                attributedString = attributedStringFromDataAndType(representationData, NSWebArchiveTextDocumentType);
                return outputDataFromAttributedString(attributedString, preferredType);
            }
            if ([representationType isEqualToString:@"com.apple.flat-rtfd"]
                || [representationType isEqualToString:@"com.apple.rtfd"]) {
                attributedString = attributedStringFromDataAndType(representationData, NSRTFDTextDocumentType);
                return outputDataFromAttributedString(attributedString, preferredType);
            }
            if ([representationType isEqualToString:@"public.utf8-plain-text"]
                || [representationType isEqualToString:@"public.plain-text"]) {
                NSString *outputString;

                outputString = [[NSString alloc] initWithData:representationData encoding:NSUTF8StringEncoding];
                return [outputString dataUsingEncoding:encoding allowLossyConversion:YES];
            }
            return representationData;
        };
#endif

#if !TARGET_OS_IPHONE
        if (pasteboard == nil) {
            exit(1);
        }
#endif

        if (isPbcopy) {
            NSData *inputData;
            NSString *string;
            NSString *type;

            inputData = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
            string = [[NSString alloc] initWithData:inputData encoding:encoding];
            if (string == nil) {
                string = [[NSString alloc] initWithData:inputData
                                               encoding:[NSString defaultCStringEncoding]];
            }

#if TARGET_OS_IPHONE
            if (string == nil && [inputData length] == 0) {
                string = @"";
            }

            if ([string hasPrefix:@"%!PS-Adobe-2.0 EPSF-"]) {
                type = @"com.adobe.encapsulated-postscript";
            } else if ([string hasPrefix:@"{\\rtf"]) {
                type = @"public.rtf";
            } else {
                type = @"public.utf8-plain-text";
            }

            if (useStoredNamedBoard) {
                NSMutableDictionary *boardItem;
                BOOL syncSuccess;

                boardItem = [NSMutableDictionary dictionary];
                if ([type isEqualToString:@"public.rtf"]) {
                    [boardItem addEntriesFromDictionary:richRTFPayload(inputData, string)];
                } else if ([type isEqualToString:@"com.adobe.encapsulated-postscript"]) {
                    NSData *plainData;

                    boardItem[@"com.adobe.encapsulated-postscript"] = inputData;
                    plainData = plainUTF8DataForString(string);
                    if (plainData != nil) {
                        boardItem[@"public.utf8-plain-text"] = plainData;
                        boardItem[@"public.plain-text"] = plainData;
                    }
                } else {
                    NSData *plainData;

                    if (string == nil) {
                        exit(1);
                    }
                    plainData = plainUTF8DataForString(string);
                    if (plainData == nil) {
                        exit(1);
                    }
                    boardItem[@"public.utf8-plain-text"] = plainData;
                    boardItem[@"public.plain-text"] = plainData;
                }

                if ([boardItem count] == 0) {
                    exit(1);
                }

                CFPreferencesSetValue((__bridge CFStringRef)pasteboardName,
                                      (__bridge CFPropertyListRef)boardItem,
                                      CFSTR(kNamedBoardPreferencesDomain),
                                      CFSTR("mobile"),
                                      kCFPreferencesAnyHost);
                syncSuccess = CFPreferencesSynchronize(CFSTR(kNamedBoardPreferencesDomain),
                                                      CFSTR("mobile"),
                                                      kCFPreferencesAnyHost);
                if (!syncSuccess) {
                    exit(1);
                }
                exit(0);
            } else {
                id connection;
                id item;
                id itemCollection;
                id endpoint;
                SEL allocSelector;
                SEL defaultConnectionSelector;
                SEL itemWithObjectSelector;
                SEL initWithDataTypeSelector;
                SEL initWithItemsSelector;
                SEL setNameSelector;
                SEL dataConsumersEndpointSelector;
                SEL saveSelector;
                SEL addDataRepresentationTypeSelector;
                NSError *saveError;

                dlopen("/System/Library/PrivateFrameworks/Pasteboard.framework/Pasteboard", RTLD_LAZY);

                allocSelector = NSSelectorFromString(@"alloc");
                defaultConnectionSelector = NSSelectorFromString(@"defaultConnection");
                itemWithObjectSelector = NSSelectorFromString(@"itemWithObject:");
                initWithDataTypeSelector = NSSelectorFromString(@"initWithData:type:");
                initWithItemsSelector = NSSelectorFromString(@"initWithItems:");
                setNameSelector = NSSelectorFromString(@"setName:");
                dataConsumersEndpointSelector = NSSelectorFromString(@"dataConsumersEndpoint");
                saveSelector = NSSelectorFromString(@"savePasteboard:dataProviderEndpoint:error:");
                addDataRepresentationTypeSelector = NSSelectorFromString(@"addDataRepresentationType:loader:");

                connection = ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"PBServerConnection"), defaultConnectionSelector);

                if ([type isEqualToString:@"public.rtf"]) {
                    NSDictionary *richPayload;
                    NSData *htmlData;
                    NSData *flatRTFDData;
                    NSData *plainData;
                    richPayload = richRTFPayload(inputData, string);
                    htmlData = richPayload[@"public.html"];
                    flatRTFDData = richPayload[@"com.apple.flat-rtfd"];
                    plainData = richPayload[@"public.utf8-plain-text"];
                    if (htmlData != nil) {
                        item = ((id (*)(id, SEL, id, id))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"PBItem"), allocSelector), initWithDataTypeSelector, htmlData, @kAppleWebArchivePasteboardType);
                    } else if (flatRTFDData != nil) {
                        item = ((id (*)(id, SEL, id, id))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"PBItem"), allocSelector), initWithDataTypeSelector, flatRTFDData, @"com.apple.flat-rtfd");
                    } else if (plainData != nil) {
                        item = ((id (*)(id, SEL, id, id))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"PBItem"), allocSelector), initWithDataTypeSelector, plainData, @"public.utf8-plain-text");
                    }
                    if (item != nil && flatRTFDData != nil && htmlData != nil) {
                        ((void (*)(id, SEL, id, id))objc_msgSend)(item, addDataRepresentationTypeSelector, @"com.apple.flat-rtfd", ^NSProgress *(void (^completion)(NSData *, NSError *)) {
                            completion(flatRTFDData, nil);
                            return nil;
                        });
                    }
                    if (item != nil && plainData != nil) {
                        ((void (*)(id, SEL, id, id))objc_msgSend)(item, addDataRepresentationTypeSelector, @"public.utf8-plain-text", ^NSProgress *(void (^completion)(NSData *, NSError *)) {
                            completion(plainData, nil);
                            return nil;
                        });
                    }
                    if (item == nil) {
                        item = ((id (*)(id, SEL, id, id))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"PBItem"), allocSelector), initWithDataTypeSelector, inputData, type);
                    }
                } else if ([type isEqualToString:@"com.adobe.encapsulated-postscript"]) {
                    if (string != nil) {
                        item = ((id (*)(id, SEL, id))objc_msgSend)(NSClassFromString(@"PBItem"), itemWithObjectSelector, string);
                        ((void (*)(id, SEL, id, id))objc_msgSend)(item, addDataRepresentationTypeSelector, @"com.adobe.encapsulated-postscript", ^NSProgress *(void (^completion)(NSData *, NSError *)) {
                            completion(inputData, nil);
                            return nil;
                        });
                    } else {
                        item = ((id (*)(id, SEL, id, id))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"PBItem"), allocSelector), initWithDataTypeSelector, inputData, type);
                    }
                } else {
                    if (string == nil) {
                        exit(1);
                    }

                    item = ((id (*)(id, SEL, id))objc_msgSend)(NSClassFromString(@"PBItem"), itemWithObjectSelector, string);
                }

                if (item == nil) {
                    exit(1);
                }

                itemCollection = ((id (*)(id, SEL, id))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"PBItemCollection"), allocSelector), initWithItemsSelector, @[item]);
                ((void (*)(id, SEL, id))objc_msgSend)(itemCollection, setNameSelector, pasteboardName);
                endpoint = ((id (*)(id, SEL))objc_msgSend)(itemCollection, dataConsumersEndpointSelector);
                saveError = nil;
                ((void (*)(id, SEL, id, id, NSError **))objc_msgSend)(connection, saveSelector, itemCollection, endpoint, &saveError);
                if (saveError != nil) {
                    exit(1);
                }
            }
#else
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            if ([string hasPrefix:@"%!PS-Adobe-2.0 EPSF-"]) {
                type = NSPostScriptPboardType;
            } else if ([string hasPrefix:@"{\\rtf"]) {
                type = NSRTFPboardType;
            } else {
                type = NSStringPboardType;
            }
#pragma clang diagnostic pop

            [pasteboard declareTypes:[NSArray arrayWithObject:type] owner:nil];
            [pasteboard setString:string forType:type];
#endif
        } else {
            NSString *type;
            NSString *preferred;
            NSArray *preferredTypes;

            preferred = [defaults objectForKey:@"Prefer"];
            if (![preferred length]) {
                preferred = [defaults objectForKey:@"prefer"];
            }

#if TARGET_OS_IPHONE
            NSArray *availableTypes;
            NSArray *candidateTypes;
            NSData *outputData;
            __block NSData *loadedData;

            outputData = nil;
            loadedData = nil;

            if (useStoredNamedBoard) {
                NSDictionary *boardContents;
                NSDictionary *boardItem;
                id storedTypes;

                boardContents = CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)pasteboardName,
                                                                         CFSTR(kNamedBoardPreferencesDomain),
                                                                         CFSTR("mobile"),
                                                                         kCFPreferencesAnyHost));
                if (![boardContents isKindOfClass:[NSDictionary class]]) {
                    exit(1);
                }
                storedTypes = [boardContents objectForKey:@"types"];
                if ([storedTypes isKindOfClass:[NSDictionary class]]) {
                    boardItem = storedTypes;
                } else {
                    boardItem = boardContents;
                }
                if (![boardItem isKindOfClass:[NSDictionary class]]) {
                    exit(1);
                }
                availableTypes = [boardItem allKeys];
                candidateTypes = candidateTypesForPreference(preferred, NO);

                type = nil;
                for (NSString *candidate in candidateTypes) {
                    if ([availableTypes containsObject:candidate]) {
                        type = candidate;
                        break;
                    }
                }

                if (type == nil) {
                    exit(1);
                }

                loadedData = [boardItem objectForKey:type];
                if (![loadedData isKindOfClass:[NSData class]]) {
                    exit(1);
                }
            } else {
                id connection;
                id itemCollection;
                id item;
                SEL defaultConnectionSelector;
                SEL pasteboardWithNameSelector;
                SEL itemsSelector;
                SEL firstObjectSelector;
                SEL availableTypesSelector;
                SEL loadRepresentationSelector;
                SEL loadObjectSelector;
                NSError *fetchError;
                dispatch_semaphore_t semaphore;
                __block NSError *loadError;
                __block id loadedObject;

                dlopen("/System/Library/PrivateFrameworks/Pasteboard.framework/Pasteboard", RTLD_LAZY);

                defaultConnectionSelector = NSSelectorFromString(@"defaultConnection");
                pasteboardWithNameSelector = NSSelectorFromString(@"pasteboardWithName:error:");
                itemsSelector = NSSelectorFromString(@"items");
                firstObjectSelector = NSSelectorFromString(@"firstObject");
                availableTypesSelector = NSSelectorFromString(@"availableTypes");
                loadRepresentationSelector = NSSelectorFromString(@"loadRepresentationAsType:completionBlock:");
                loadObjectSelector = NSSelectorFromString(@"loadObjectOfClass:completionBlock:");

                connection = ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"PBServerConnection"), defaultConnectionSelector);
                fetchError = nil;
                itemCollection = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(connection, pasteboardWithNameSelector, pasteboardName, &fetchError);
                if (itemCollection == nil) {
                    exit(1);
                }

                item = ((id (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(itemCollection, itemsSelector), firstObjectSelector);
                if (item == nil) {
                    exit(1);
                }

                availableTypes = ((id (*)(id, SEL))objc_msgSend)(item, availableTypesSelector);
                if ([preferred isEqualToString:@"rtf"]) {
                    semaphore = dispatch_semaphore_create(0);
                    loadedObject = nil;
                    loadError = nil;
                    ((void (*)(id, SEL, id, id))objc_msgSend)(item, loadObjectSelector, [NSAttributedString class], ^(id object, NSError *error) {
                        loadedObject = object;
                        loadError = error;
                        dispatch_semaphore_signal(semaphore);
                    });
                    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                    if ([loadedObject isKindOfClass:[NSAttributedString class]] && loadError == nil) {
                        NSAttributedString *attributedString;

                        attributedString = loadedObject;
                        outputData = [attributedString dataFromRange:NSMakeRange(0, attributedString.length)
                                                  documentAttributes:@{
                                                      NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType,
                                                  }
                                                               error:nil];
                    }

                    candidateTypes = candidateTypesForPreference(preferred, YES);
                } else if ([preferred isEqualToString:@"ps"]) {
                    candidateTypes = candidateTypesForPreference(preferred, YES);
                } else {
                    semaphore = dispatch_semaphore_create(0);
                    loadedObject = nil;
                    loadError = nil;
                    ((void (*)(id, SEL, id, id))objc_msgSend)(item, loadObjectSelector, [NSString class], ^(id object, NSError *error) {
                        loadedObject = object;
                        loadError = error;
                        dispatch_semaphore_signal(semaphore);
                    });
                    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                    if ([loadedObject isKindOfClass:[NSString class]] && loadError == nil) {
                        outputData = [loadedObject dataUsingEncoding:encoding allowLossyConversion:YES];
                    }

                    candidateTypes = candidateTypesForPreference(preferred, YES);
                }

                if (outputData == nil) {
                    type = nil;
                    for (NSString *candidate in candidateTypes) {
                        if ([availableTypes containsObject:candidate]) {
                            type = candidate;
                            break;
                        }
                    }

                    if (type == nil) {
                        exit(1);
                    }

                    semaphore = dispatch_semaphore_create(0);
                    loadedData = nil;
                    loadError = nil;
                    ((void (*)(id, SEL, id, id))objc_msgSend)(item, loadRepresentationSelector, type, ^(NSData *data, NSError *error) {
                        loadedData = data;
                        loadError = error;
                        dispatch_semaphore_signal(semaphore);
                    });
                    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                    if (loadedData == nil || loadError != nil) {
                        exit(1);
                    }
                }
            }

            if (outputData == nil) {
                outputData = outputDataForRepresentation(type, loadedData, preferred);
            }

            if (outputData != nil) {
                [[NSFileHandle fileHandleWithStandardOutput] writeData:outputData];
            }
#else
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            if ([preferred length]) {
                preferredTypes = [NSArray arrayWithObjects:preferred,
                                                           NSStringPboardType,
                                                           NSPostScriptPboardType,
                                                           NSRTFPboardType,
                                                           nil];
            } else {
                preferredTypes = [NSArray arrayWithObjects:NSStringPboardType,
                                                           NSPostScriptPboardType,
                                                           NSRTFPboardType,
                                                           nil];
            }
#pragma clang diagnostic pop

            type = [pasteboard availableTypeFromArray:preferredTypes];
            if (type != nil) {
                NSData *outputData;

                outputData = [[pasteboard stringForType:type] dataUsingEncoding:encoding
                                                         allowLossyConversion:YES];
                [[NSFileHandle fileHandleWithStandardOutput] writeData:outputData];
            }
#endif
        }
    }

    return 0;
}
