#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#import <WebKit/WebArchive.h>
#import <WebKit/WebResource.h>
#endif
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <crt_externs.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>

#import "TextutilWebDelegate.h"

enum {
    TextutilCommandNone = 0,
    TextutilCommandHelp = 1,
    TextutilCommandInfo = 2,
    TextutilCommandConvert = 3,
    TextutilCommandCat = 4,
};

#define TEXTUTIL_STRCASEEQ(left, right) ([(left) compare:(right) options:NSCaseInsensitiveSearch] == NSOrderedSame)
#if TARGET_OS_IPHONE
#define TEXTUTIL_IOS_UNSUPPORTED_DOCUMENT_TYPE(type) \
    ((unsigned char)[NSOpenDocumentTextDocumentType isEqualToString:(type)] || \
     (unsigned char)[NSWordMLTextDocumentType isEqualToString:(type)])
#define TEXTUTIL_IOS_PRIVATE_READONLY_DOCUMENT_TYPE(type) \
    ((unsigned char)[NSDocFormatTextDocumentType isEqualToString:(type)] || \
     (unsigned char)[NSOfficeOpenXMLTextDocumentType isEqualToString:(type)])
#endif

#if TARGET_OS_IPHONE
#define NSDocFormatTextDocumentType @"NSDocFormat"
#define NSOfficeOpenXMLTextDocumentType @"NSOfficeOpenXML"
#define NSOpenDocumentTextDocumentType @"NSOpenDocument"
#define NSWordMLTextDocumentType @"NSWordML"
#define NSWebArchiveTextDocumentType @"NSWebArchive"
#define NSMacSimpleTextDocumentType @"NSMacSimpleText"
#define NSWebResourceLoadDelegateDocumentOption @"WebResourceLoadDelegate"
#define NSExcludedElementsDocumentAttribute @"ExcludedElements"
#define NSPrefixSpacesDocumentAttribute @"PrefixSpaces"
#define NSTextEncodingNameDocumentAttribute @"TextEncodingName"
#define NSTextEncodingNameDocumentOption @"TextEncodingName"
#define NSBaseURLDocumentOption @"BaseURL"
#define NSTimeoutDocumentOption @"Timeout"
#define NSTextSizeMultiplierDocumentOption @"TextSizeMultiplier"
#define NSTitleDocumentAttribute @"NSTitleDocumentAttribute"
#define NSAuthorDocumentAttribute @"NSAuthorDocumentAttribute"
#define NSSubjectDocumentAttribute @"NSSubjectDocumentAttribute"
#define NSKeywordsDocumentAttribute @"NSKeywordsDocumentAttribute"
#define NSCommentDocumentAttribute @"NSCommentDocumentAttribute"
#define NSEditorDocumentAttribute @"NSEditorDocumentAttribute"
#define NSCompanyDocumentAttribute @"NSCompanyDocumentAttribute"
#define NSCopyrightDocumentAttribute @"NSCopyrightDocumentAttribute"
#define NSCreationTimeDocumentAttribute @"NSCreationTimeDocumentAttribute"
#define NSModificationTimeDocumentAttribute @"NSModificationTimeDocumentAttribute"
#define NSDocumentTypeDocumentAttribute @"DocumentType"
#define NSDefaultAttributesDocumentOption @"DefaultAttributes"
#define NSFontAttributeName @"NSFont"
#define NSParagraphStyleAttributeName @"NSParagraphStyle"

@interface NSObject (TextutilOfficeImport)
- (id)searchableAttributesForOfficeFileAtURL:(NSURL *)url error:(NSError **)error;
@end
#endif

static int printUsage(char toStandardError);
static int printErrorString(const char *message);
static void printErrorStringAndExit(const char *message) __attribute__((noreturn, unused));
static int printReadError(NSString *path, NSError *error);
static void printReadErrorAndExit(NSString *path, NSError *error) __attribute__((noreturn, unused));
static int printWriteError(NSString *path, NSError *error);
static void printWriteErrorAndExit(NSString *path, NSError *error) __attribute__((noreturn, unused));
static BOOL parseTwoDigitDecimal(const char **cursor, unsigned char *value);
static NSDate *createDateFromISOString(NSString *string);
#if TARGET_OS_IPHONE
static UIFont *chooseFontForPlainTextConversion(NSString *fontName, double fontSize);
static NSData *createMainResourceOnlyWebArchiveData(NSData *htmlData, NSString *path, CFStringRef textEncodingName);
static NSAttributedString *createAttributedStringFromOfficeImportText(NSString *path, NSString *documentType, NSDictionary **documentAttributes, NSError **error);
#else
static NSFont *chooseFontForPlainTextConversion(NSString *fontName, double fontSize);
#endif
static int printFileInfo(NSAttributedString *attributedString, NSString *path, NSDictionary *documentAttributes);
static NSMutableDictionary *copyDocumentAttributesWithOverrides(NSDictionary *sourceAttributes, NSDictionary *overrideAttributes, char stripMetadata);
static void writeAttributedStringOutput(NSAttributedString *attributedString, NSString *path, NSDictionary *documentAttributes, char doNotStoreSubresources);

static int printUsage(char toStandardError)
{
    FILE *stream;
    char **programName;

    if (toStandardError) {
        stream = stderr;
    } else {
        stream = stdout;
    }
    programName = _NSGetProgname();
    return fprintf(
        stream,
        "%s: [command_option] [other_options] file...\n"
        "Command options are (-help is the default):\n"
        " -help          show this message and exit\n"
        " -info          display information about each file\n"
        " -convert fmt   convert each input file to format (txt, rtf, rtfd,\n"
        "                html, doc, docx, odt, wordml, or webarchive)\n"
        " -cat fmt       concatenate input files into one output file\n"
        "There are some additional optional arguments:\n"
        " -extension ext alternate extension for all output files\n"
        " -output path   alternate file name for first output file\n"
        " -stdin         read from stdin instead of files\n"
        " -stdout        send first output file to stdout\n"
        " -encoding IANA_name|NSStringEncoding\n"
        "                encoding used for plain text or html output files\n"
        "                (default encoding is UTF-8)\n"
        " -inputencoding IANA_name|NSStringEncoding\n"
        "                encoding used to interpret plain text input files\n"
        "                (by default encoding will be detected from BOM)\n"
        " -format fmt    force input files to be interpreted in this format\n"
        " -font font     specify font used for converting plain to rich text\n"
        " -fontsize size specify font size for converting plain to rich text\n"
        " --             specifies that all further arguments are file names\n"
        "\n"
        " -noload        do not load subsidiary resources for html files\n"
        " -nostore       do not write out subsidiary resources for html files\n"
        " -baseurl url   base URL for subsidiary resources in html files\n"
        " -timeout t     time in seconds to wait for html resources to load\n"
        " -textsizemultiplier x\n"
        "                factor to apply to font sizes in html files\n"
        " -excludedelements \"(tag1, tag2, ...)\"\n"
        "                html elements to exclude from html output files\n"
        " -prefixspaces n\n"
        "                number of spaces to indent nested html output\n"
        "\n"
        " -strip         do not copy metadata attributes to output files\n"
        " -title val     title metadata attribute for output files\n"
        " -author val    author metadata attribute for output files\n"
        " -subject val   subject metadata attribute for output files\n"
        " -keywords \"(val1, val2, ...)\"\n"
        "                keywords metadata attribute for output files\n"
        " -comment val   comment metadata attribute for output files\n"
        " -editor val    last editor metadata attribute for output files\n"
        " -company val   company metadata attribute for output files\n"
        " -creationtime yyyy-mm-ddThh:mm:ssZ\n"
        "                creation time metadata attribute for output files\n"
        " -modificationtime yyyy-mm-ddThh:mm:ssZ\n"
        "                modification time metadata attribute for output files\n",
        *programName);
}

static int printErrorString(const char *message)
{
    return fputs(message, stderr);
}

static void printErrorStringAndExit(const char *message)
{
    printErrorString(message);
    exit(1);
}

static int printReadError(NSString *path, NSError *error)
{
    const char *displayPath;
    NSString *reason;

    if (path) {
        displayPath = [path fileSystemRepresentation];
    } else {
        displayPath = "from stdin";
    }
    fprintf(stderr, "Error reading %s.", displayPath);
    if (!error) {
        return fputc('\n', stderr);
    }
    reason = [error localizedFailureReason];
    if (!reason) {
        reason = [error localizedDescription];
        if (!reason) {
            return fputc('\n', stderr);
        }
    }
    return fprintf(stderr, "  %s\n", reason.UTF8String);
}

static void printReadErrorAndExit(NSString *path, NSError *error)
{
    printReadError(path, error);
    exit(1);
}

static int printWriteError(NSString *path, NSError *error)
{
    const char *displayPath;
    NSString *reason;

    if (path) {
        displayPath = [path fileSystemRepresentation];
    } else {
        displayPath = "to stdout";
    }
    fprintf(stderr, "Error writing %s.", displayPath);
    if (!error) {
        return fputc('\n', stderr);
    }
    reason = [error localizedFailureReason];
    if (!reason) {
        reason = [error localizedDescription];
        if (!reason) {
            return fputc('\n', stderr);
        }
    }
    return fprintf(stderr, "  %s\n", reason.UTF8String);
}

static void printWriteErrorAndExit(NSString *path, NSError *error)
{
    printWriteError(path, error);
    exit(1);
}

static BOOL parseTwoDigitDecimal(const char **cursor, unsigned char *value)
{
    const char *start;
    int firstDigit;
    int secondDigit;

    start = *cursor;
    *cursor = start + 1;
    firstDigit = start[0];
    if ((unsigned int)(firstDigit - '0') > 9) {
        return NO;
    }
    *cursor = start + 2;
    secondDigit = start[1];
    if ((unsigned int)(secondDigit - '0') > 9) {
        return NO;
    }
    *value = (unsigned char)(10 * (firstDigit - '0') + (secondDigit - '0'));
    return YES;
}

static NSDate *createDateFromISOString(NSString *string)
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    const char *cursor;
    int character;
    unsigned int year;
    unsigned char month;
    unsigned char day;
    unsigned char hour;
    unsigned char minute;
    unsigned char second;
    CFGregorianDate gregorianDate;
    CFDateRef date;

    cursor = string.UTF8String;
    character = *cursor;
    year = 0;
    if (character && (unsigned int)(character - '0') <= 9) {
        do {
            year = (unsigned int)(character + 10 * year - '0');
            character = *++cursor;
        } while (character && (unsigned int)(character - '0') < 10);
    }
    if ((char)character != '-') {
        return nil;
    }
    ++cursor;
    if (!parseTwoDigitDecimal(&cursor, &month)) {
        return nil;
    }
    if (*cursor != '-') {
        return nil;
    }
    ++cursor;
    if (!parseTwoDigitDecimal(&cursor, &day)) {
        return nil;
    }
    if (*cursor != 'T') {
        return nil;
    }
    ++cursor;
    if (!parseTwoDigitDecimal(&cursor, &hour)) {
        return nil;
    }
    if (*cursor != ':') {
        return nil;
    }
    ++cursor;
    if (!parseTwoDigitDecimal(&cursor, &minute)) {
        return nil;
    }
    if (*cursor != ':') {
        return nil;
    }
    ++cursor;
    if (!parseTwoDigitDecimal(&cursor, &second)) {
        return nil;
    }
    if (*cursor != 'Z' || cursor[1] != '\0') {
        return nil;
    }
    gregorianDate.year = year;
    gregorianDate.month = month;
    gregorianDate.day = day;
    gregorianDate.hour = hour;
    gregorianDate.minute = minute;
    gregorianDate.second = second;
    date = CFDateCreate(NULL, CFGregorianDateGetAbsoluteTime(gregorianDate, NULL));
#pragma clang diagnostic pop
    return CFBridgingRelease(date);
}

static
/* Consider use CTFontRef */
#if TARGET_OS_IPHONE
UIFont *
#else
NSFont *
#endif
chooseFontForPlainTextConversion(NSString *fontName, double fontSize)
{
#if TARGET_OS_IPHONE
    UIFont *font;
    NSArray *availableFamilies;
    NSRange spaceRange;
    NSRange dashRange;
    NSRange splitRange;
    NSString *candidateFamily;
    NSString *styleName;
    NSArray *matchingFonts;
    NSString *candidateFontName;

    font = [UIFont fontWithName:fontName size:fontSize];
    if (font) {
        return font;
    }
    availableFamilies = [UIFont familyNames];
    spaceRange = [fontName rangeOfString:@" " options:NSBackwardsSearch];
    dashRange = [fontName rangeOfString:@"-" options:NSBackwardsSearch];
    splitRange = dashRange;
    if (spaceRange.length && dashRange.length) {
        if (spaceRange.location > dashRange.location) {
            splitRange = spaceRange;
        }
    } else if (spaceRange.length) {
        splitRange = spaceRange;
    } else if (!dashRange.length) {
        splitRange = NSMakeRange(NSNotFound, 0);
    }
    if (!splitRange.length) {
        font = [UIFont fontWithName:@"Helvetica" size:fontSize];
        if (!font) {
            return [UIFont systemFontOfSize:fontSize];
        }
        return font;
    }
    candidateFamily = [fontName substringToIndex:splitRange.location];
    while (![availableFamilies containsObject:candidateFamily]) {
        spaceRange = [candidateFamily rangeOfString:@" " options:NSBackwardsSearch];
        dashRange = [candidateFamily rangeOfString:@"-" options:NSBackwardsSearch];
        splitRange = dashRange;
        if (spaceRange.length && dashRange.length) {
            if (spaceRange.location > dashRange.location) {
                splitRange = spaceRange;
            }
        } else if (spaceRange.length) {
            splitRange = spaceRange;
        } else if (!dashRange.length) {
            splitRange = NSMakeRange(NSNotFound, 0);
        }
        if (!splitRange.length) {
            font = [UIFont fontWithName:@"Helvetica" size:fontSize];
            if (!font) {
                return [UIFont systemFontOfSize:fontSize];
            }
            return font;
        }
        candidateFamily = [candidateFamily substringToIndex:splitRange.location];
    }
    styleName = [fontName substringFromIndex:splitRange.location + splitRange.length];
    matchingFonts = [UIFont fontNamesForFamilyName:candidateFamily];
    for (candidateFontName in matchingFonts) {
        if (TEXTUTIL_STRCASEEQ(candidateFontName, fontName)
         || [candidateFontName rangeOfString:styleName options:NSCaseInsensitiveSearch].length) {
            font = [UIFont fontWithName:candidateFontName size:fontSize];
            if (font) {
                return font;
            }
        }
    }
    if (matchingFonts.count) {
        font = [UIFont fontWithName:matchingFonts[0] size:fontSize];
        if (font) {
            return font;
        }
    }
    font = [UIFont fontWithName:@"Helvetica" size:fontSize];
    if (!font) {
        return [UIFont systemFontOfSize:fontSize];
    }
    return font;
#else
    NSFontManager *fontManager;
    NSFont *font;
    NSArray *availableFamilies;
    NSRange spaceRange;
    NSRange dashRange;
    NSRange splitRange;
    NSString *candidateFamily;
    NSString *styleName;
    NSArray *availableMembers;
    NSEnumerator *enumerator;
    NSArray *member;

    fontManager = [NSFontManager sharedFontManager];
    font = [fontManager fontWithFamily:fontName traits:0 weight:0 size:fontSize];
    if (font) {
        return font;
    }
    availableFamilies = [fontManager availableFontFamilies];
    spaceRange = [fontName rangeOfString:@" " options:NSBackwardsSearch];
    dashRange = [fontName rangeOfString:@"-" options:NSBackwardsSearch];
    splitRange = dashRange;
    if (spaceRange.length && dashRange.length) {
        if (spaceRange.location > dashRange.location) {
            splitRange = spaceRange;
        }
    } else if (spaceRange.length) {
        splitRange = spaceRange;
    } else if (!dashRange.length) {
        splitRange = NSMakeRange(NSNotFound, 0);
    }
    if (!splitRange.length) {
        font = [NSFont fontWithName:@"Helvetica" size:fontSize];
        if (!font) {
            return [NSFont userFontOfSize:fontSize];
        }
        return font;
    }
    candidateFamily = [fontName substringToIndex:splitRange.location];
    if (![availableFamilies containsObject:candidateFamily]) {
        do {
            spaceRange = [candidateFamily rangeOfString:@" " options:NSBackwardsSearch];
            dashRange = [candidateFamily rangeOfString:@"-" options:NSBackwardsSearch];
            splitRange = dashRange;
            if (spaceRange.length && dashRange.length) {
                if (spaceRange.location > dashRange.location) {
                    splitRange = spaceRange;
                }
            } else if (spaceRange.length) {
                splitRange = spaceRange;
            } else if (!dashRange.length) {
                splitRange = NSMakeRange(NSNotFound, 0);
            }
            if (!splitRange.length) {
                font = [NSFont fontWithName:@"Helvetica" size:fontSize];
                if (!font) {
                    return [NSFont userFontOfSize:fontSize];
                }
                return font;
            }
            candidateFamily = [candidateFamily substringToIndex:splitRange.location];
        } while (![availableFamilies containsObject:candidateFamily]);
    }
    styleName = [fontName substringFromIndex:splitRange.location + splitRange.length];
    availableMembers = [fontManager availableMembersOfFontFamily:candidateFamily];
    enumerator = [availableMembers objectEnumerator];
    while ((member = [enumerator nextObject])) {
        if (TEXTUTIL_STRCASEEQ(member[1], styleName)) {
            font = [fontManager fontWithFamily:candidateFamily
                                        traits:(NSFontTraitMask)[member[3] integerValue]
                                        weight:(NSInteger)[member[2] integerValue]
                                          size:fontSize];
            if (font) {
                return font;
            }
            break;
        }
    }
    if (availableMembers.count) {
        member = availableMembers[0];
        font = [fontManager fontWithFamily:candidateFamily
                                    traits:(NSFontTraitMask)[member[3] integerValue]
                                    weight:(NSInteger)[member[2] integerValue]
                                      size:fontSize];
        if (font) {
            return font;
        }
    }
    font = [NSFont fontWithName:@"Helvetica" size:fontSize];
    if (!font) {
        return [NSFont userFontOfSize:fontSize];
    }
    return font;
#endif
}

static int printFileInfo(NSAttributedString *attributedString, NSString *path, NSDictionary *documentAttributes)
{
    const char *pathName;
    NSString *documentType;
    const char *typeName;
    const char *pluralSuffix;
    struct stat fileStatus;
    NSString *string;
    NSUInteger stringLength;
    NSUInteger lineStart;
    NSUInteger lineEnd;
    NSUInteger contentsEnd;
    int result;
    id value;

    pathName = [path fileSystemRepresentation];
    string = [attributedString string];
    stringLength = (NSUInteger)attributedString.length;
    printf("File:  %s\n", pathName);
    documentType = [documentAttributes objectForKey:NSDocumentTypeDocumentAttribute];
    if (documentType) {
        if ((unsigned char)[NSPlainTextDocumentType isEqual:documentType]) {
            typeName = "  Type:  plain text";
        } else if ((unsigned char)[NSRTFTextDocumentType isEqual:documentType]) {
            typeName = "  Type:  rich text format (RTF)";
        } else if ((unsigned char)[NSRTFDTextDocumentType isEqual:documentType]) {
            typeName = "  Type:  rich text with graphics format (RTFD)";
        } else if ((unsigned char)[NSMacSimpleTextDocumentType isEqual:documentType]) {
            typeName = "  Type:  SimpleText format";
        } else if ((unsigned char)[NSHTMLTextDocumentType isEqual:documentType]) {
            typeName = "  Type:  HTML";
        } else if ((unsigned char)[NSDocFormatTextDocumentType isEqual:documentType]) {
            typeName = "  Type:  Word format";
        } else if ((unsigned char)[NSOfficeOpenXMLTextDocumentType isEqual:documentType]) {
            typeName = "  Type:  Office Open XML format";
        } else if ((unsigned char)[NSOpenDocumentTextDocumentType isEqual:documentType]) {
            typeName = "  Type:  Open Document format";
        } else if ((unsigned char)[NSWordMLTextDocumentType isEqual:documentType]) {
            typeName = "  Type:  Word XML format";
        } else {
            typeName = "  Type:  web archive";
            if (![(id)NSWebArchiveTextDocumentType isEqual:documentType]) {
                typeName = "  Type:  unknown";
            }
        }
    } else {
        typeName = "  Type:  unknown";
    }
    puts(typeName);
    pluralSuffix = "s";
    if (!stat(pathName, &fileStatus)) {
        const char *bytePluralSuffix;

        bytePluralSuffix = "s";
        if (fileStatus.st_size == 1) {
            bytePluralSuffix = "";
        }
        printf("  Size:  %lld byte%s\n", fileStatus.st_size, bytePluralSuffix);
    }
    if (stringLength == 1) {
        pluralSuffix = "";
    }
    printf("  Length:  %lu character%s\n", (unsigned long)stringLength, pluralSuffix);
    value = [documentAttributes objectForKey:NSTitleDocumentAttribute];
    if (value) {
        printf("  Title:  %s\n", [value UTF8String]);
    }
    value = [documentAttributes objectForKey:NSAuthorDocumentAttribute];
    if (value) {
        printf("  Author:  %s\n", [value UTF8String]);
    }
    value = [documentAttributes objectForKey:NSEditorDocumentAttribute];
    if (value) {
        printf("  Last Editor:  %s\n", [value UTF8String]);
    }
    value = [documentAttributes objectForKey:NSCompanyDocumentAttribute];
    if (value) {
        printf("  Company:  %s\n", [value UTF8String]);
    }
    value = [documentAttributes objectForKey:NSCopyrightDocumentAttribute];
    if (value) {
        printf("  Copyright:  %s\n", [value UTF8String]);
    }
    value = [documentAttributes objectForKey:NSSubjectDocumentAttribute];
    if (value) {
        printf("  Subject:  %s\n", [value UTF8String]);
    }
    value = [documentAttributes objectForKey:NSKeywordsDocumentAttribute];
    if (value) {
        printf("  Keywords:  %s\n", [value componentsJoinedByString:@", "].UTF8String);
    }
    value = [documentAttributes objectForKey:NSCommentDocumentAttribute];
    if (value) {
        printf("  Comment:  %s\n", [value UTF8String]);
    }
    value = [documentAttributes objectForKey:NSCreationTimeDocumentAttribute];
    if (value) {
        printf("  Created:  %s\n", [[value description] UTF8String]);
    }
    result = 0;
    value = [documentAttributes objectForKey:NSModificationTimeDocumentAttribute];
    if (value) {
        result = printf("  Last Modified:  %s\n", [[value description] UTF8String]);
    }
    if (!stringLength) {
        return result;
    }
    lineStart = 0;
    lineEnd = 0;
    contentsEnd = 0;
    [string getLineStart:&lineStart end:&lineEnd contentsEnd:&contentsEnd forRange:NSMakeRange(0, 0)];
    result = (int)contentsEnd;
    if (contentsEnd < 31) {
        if (!contentsEnd) {
            return result;
        }
        if (lineStart >= stringLength) {
            result = printf("  Contents:  %s\n", attributedString.string.UTF8String);
            return result;
        }
        result = printf("  Contents:  %s...\n", [attributedString.string substringToIndex:contentsEnd].UTF8String);
        return result;
    }
    result = printf("  Contents:  %s...\n", [attributedString.string substringToIndex:30].UTF8String);
    return result;
}

static NSMutableDictionary *copyDocumentAttributesWithOverrides(NSDictionary *sourceAttributes, NSDictionary *overrideAttributes, char stripMetadata)
{
    NSMutableDictionary *attributes;
    NSArray *keys;

    attributes = [NSMutableDictionary dictionaryWithDictionary:sourceAttributes];
    if (stripMetadata) {
        keys = [NSArray arrayWithObjects:
            NSTitleDocumentAttribute,
            NSCompanyDocumentAttribute,
            NSCopyrightDocumentAttribute,
            NSSubjectDocumentAttribute,
            NSAuthorDocumentAttribute,
            NSKeywordsDocumentAttribute,
            NSCommentDocumentAttribute,
            NSEditorDocumentAttribute,
            NSCreationTimeDocumentAttribute,
            NSModificationTimeDocumentAttribute,
            @"NSManagerDocumentAttribute",
            nil];
        [attributes removeObjectsForKeys:keys];
    }
    [attributes addEntriesFromDictionary:overrideAttributes];
    return attributes;
}

#if TARGET_OS_IPHONE
static NSData *createMainResourceOnlyWebArchiveData(NSData *htmlData, NSString *path, CFStringRef textEncodingName)
{
    NSString *resourceURL;
    NSString *encodingName;
    NSDictionary *webMainResource;
    NSDictionary *webArchive;

    resourceURL = path;
    if (!resourceURL) {
        resourceURL = @"";
    }
    encodingName = (__bridge NSString *)textEncodingName;
    if (!encodingName) {
        encodingName = @"UTF-8";
    }
    webMainResource = [NSDictionary dictionaryWithObjectsAndKeys:
        resourceURL, @"WebResourceURL",
        @"", @"WebResourceFrameName",
        htmlData, @"WebResourceData",
        @"text/html", @"WebResourceMIMEType",
        encodingName, @"WebResourceTextEncodingName",
        nil];
    webArchive = [NSDictionary dictionaryWithObject:webMainResource forKey:@"WebMainResource"];
    return [NSPropertyListSerialization dataWithPropertyList:webArchive
                                                      format:NSPropertyListBinaryFormat_v1_0
                                                     options:0
                                                       error:nil];
}

static NSAttributedString *createAttributedStringFromOfficeImportText(NSString *path, NSString *documentType, NSDictionary **documentAttributes, NSError **error)
{
    static Class importerClass;
    static dispatch_once_t onceToken;
    id importer;
    id searchableAttributes;
    NSString *textContent;
    NSDictionary *attributes;

    if (![NSDocFormatTextDocumentType isEqualToString:documentType]
     && ![NSOfficeOpenXMLTextDocumentType isEqualToString:documentType]) {
        return nil;
    }
    dispatch_once(&onceToken, ^{
        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/OfficeImport.framework"] load];
        importerClass = objc_getClass("OISpotlightImporter");
    });
    if (!importerClass) {
        return nil;
    }
    importer = [[importerClass alloc] init];
    if (!importer) {
        return nil;
    }
    searchableAttributes = [importer searchableAttributesForOfficeFileAtURL:[NSURL fileURLWithPath:path] error:error];
    if (!searchableAttributes) {
        return nil;
    }
    textContent = nil;
    if ([searchableAttributes respondsToSelector:NSSelectorFromString(@"textContent")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        textContent = [searchableAttributes performSelector:NSSelectorFromString(@"textContent")];
#pragma clang diagnostic pop
    }
    if (!textContent.length) {
        NSDictionary *attributeDictionary;

        attributeDictionary = nil;
        if ([searchableAttributes respondsToSelector:@selector(attributes)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            attributeDictionary = [searchableAttributes performSelector:@selector(attributes)];
#pragma clang diagnostic pop
        }
        textContent = [attributeDictionary objectForKey:@"kMDItemTextContent"];
        if (!textContent.length) {
            return nil;
        }
    }
    attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        NSPlainTextDocumentType, NSDocumentTypeDocumentAttribute,
        [NSNumber numberWithUnsignedInteger:NSUTF8StringEncoding], NSCharacterEncodingDocumentAttribute,
        @"UTF-8", NSTextEncodingNameDocumentAttribute,
        nil];
    if (documentAttributes) {
        *documentAttributes = attributes;
    }
    return [[NSAttributedString alloc] initWithString:textContent];
}
#endif

static void writeAttributedStringOutput(NSAttributedString *attributedString, NSString *path, NSDictionary *documentAttributes, char doNotStoreSubresources)
{
    NSString *documentType;
    NSString *sourceDocumentType;
    NSURL *url;
    NSUInteger length;
    NSError *error;

    documentType = [documentAttributes objectForKey:NSDocumentTypeDocumentAttribute];
    sourceDocumentType = [documentAttributes objectForKey:@"_SourceDocumentType"];
    if (path) {
        url = [NSURL fileURLWithPath:path];
    } else {
        url = nil;
    }
    error = nil;
    length = (NSUInteger)attributedString.length;
#if TARGET_OS_IPHONE
    if (TEXTUTIL_IOS_UNSUPPORTED_DOCUMENT_TYPE(documentType)) {
        printWriteErrorAndExit(path, error);
    }
    if (TEXTUTIL_IOS_PRIVATE_READONLY_DOCUMENT_TYPE(documentType)) {
        printWriteErrorAndExit(path, error);
    }
#endif
    if ((unsigned char)[NSRTFDTextDocumentType isEqualToString:documentType]) {
        NSFileWrapper *fileWrapper;

        fileWrapper = [attributedString fileWrapperFromRange:NSMakeRange(0, length) documentAttributes:documentAttributes error:&error];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if (path && fileWrapper && (unsigned char)[fileWrapper writeToURL:url options:NSFileWrapperWritingAtomic originalContentsURL:nil error:&error]) {
            return;
        }
#pragma clang diagnostic pop
        printWriteErrorAndExit(path, error);
    }
    if (doNotStoreSubresources && (unsigned char)[NSWebArchiveTextDocumentType isEqualToString:documentType]) {
        if (![(id)NSHTMLTextDocumentType isEqualToString:sourceDocumentType]) {
            printWriteErrorAndExit(path, error);
        }
        NSMutableDictionary *htmlAttributes;
        CFStringRef textEncodingName;
        NSData *data;
#if !TARGET_OS_IPHONE
        WebResource *webResource;
        WebArchive *webArchive;
#endif
        NSData *archiveData;
        NSUInteger archiveLength;

        htmlAttributes = [NSMutableDictionary dictionaryWithDictionary:documentAttributes];
        [htmlAttributes removeObjectForKey:@"_SourceDocumentType"];
        textEncodingName = (__bridge CFStringRef)[documentAttributes objectForKey:NSTextEncodingNameDocumentAttribute];
        if (!textEncodingName) {
            NSNumber *encodingNumber;
            NSUInteger encodingValue;

            encodingNumber = [documentAttributes objectForKey:NSCharacterEncodingDocumentAttribute];
            encodingValue = (NSUInteger)encodingNumber.unsignedIntegerValue;
            if (encodingValue) {
                textEncodingName = CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(encodingValue));
            } else {
                textEncodingName = CFSTR("UTF-8");
            }
        }
        [htmlAttributes setObject:NSHTMLTextDocumentType forKey:NSDocumentTypeDocumentAttribute];
        data = [attributedString dataFromRange:NSMakeRange(0, length) documentAttributes:htmlAttributes error:&error];
        if (!data || !data.length) {
            printWriteErrorAndExit(path, error);
        }
#if TARGET_OS_IPHONE
        archiveData = createMainResourceOnlyWebArchiveData(data, path, textEncodingName);
#else
        webResource = [[WebResource alloc] initWithData:data
                                                    URL:url
                                               MIMEType:@"text/html"
                                       textEncodingName:(__bridge NSString *)textEncodingName
                                              frameName:nil];
        if (!webResource) {
            printWriteErrorAndExit(path, error);
        }
        webArchive = [[WebArchive alloc] initWithMainResource:webResource subresources:nil subframeArchives:nil];
        if (!webArchive) {
            printWriteErrorAndExit(path, error);
        }
        archiveData = [webArchive data];
#endif
        archiveLength = (NSUInteger)archiveData.length;
        if (!archiveData || !archiveLength) {
            printWriteErrorAndExit(path, error);
        }
        if (path) {
            if (![archiveData writeToURL:url options:NSDataWritingAtomic error:&error]) {
                printWriteErrorAndExit(path, error);
            }
        } else {
            fwrite([archiveData bytes], 1, archiveLength, stdout);
        }
        return;
    }
    if (doNotStoreSubresources || ![(id)NSHTMLTextDocumentType isEqualToString:documentType]) {
        if (path && (unsigned char)[NSPlainTextDocumentType isEqualToString:documentType]) {
            NSNumber *encodingNumber;
            NSUInteger encodingValue;
            NSStringEncoding encoding;

            encodingNumber = [documentAttributes objectForKey:NSCharacterEncodingDocumentAttribute];
            encodingValue = (NSUInteger)encodingNumber.unsignedIntegerValue;
            encoding = NSUTF8StringEncoding;
            if (encodingValue) {
                encoding = (NSStringEncoding)encodingValue;
            }
            if (![[attributedString string] writeToURL:url atomically:YES encoding:encoding error:&error]) {
                printWriteErrorAndExit(path, error);
            }
            return;
        }
        {
            NSData *data;
            NSUInteger dataLength;
            NSMutableDictionary *serializedAttributes;

            serializedAttributes = [NSMutableDictionary dictionaryWithDictionary:documentAttributes];
            [serializedAttributes removeObjectForKey:@"_SourceDocumentType"];
            data = [attributedString dataFromRange:NSMakeRange(0, length) documentAttributes:serializedAttributes error:&error];
            dataLength = (NSUInteger)data.length;
            if (!data) {
                printWriteErrorAndExit(path, error);
            }
            if (!path) {
                fwrite([data bytes], 1, dataLength, stdout);
                return;
            }
            if (![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
                printWriteErrorAndExit(path, error);
            }
            return;
        }
    }
    {
        NSFileWrapper *fileWrapper;
        NSMutableDictionary *serializedAttributes;

        serializedAttributes = [NSMutableDictionary dictionaryWithDictionary:documentAttributes];
        [serializedAttributes removeObjectForKey:@"_SourceDocumentType"];
        fileWrapper = [attributedString fileWrapperFromRange:NSMakeRange(0, length) documentAttributes:serializedAttributes error:&error];
        if (!fileWrapper) {
            printWriteErrorAndExit(path, error);
        }
        if (![(id)fileWrapper isDirectory]) {
            NSData *data;
            NSUInteger dataLength;

            data = [attributedString dataFromRange:NSMakeRange(0, length) documentAttributes:serializedAttributes error:&error];
            dataLength = (NSUInteger)data.length;
            if (!data || !dataLength) {
                printWriteErrorAndExit(path, error);
            }
            if (!path) {
                fwrite([data bytes], 1, dataLength, stdout);
                return;
            }
            if (![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
                printWriteErrorAndExit(path, error);
            }
            return;
        }
        {
            NSDictionary *fileWrappers;
            NSArray *allKeys;
            NSFileWrapper *indexWrapper;
            NSData *regularFileContents;
            NSUInteger regularFileLength;

            fileWrappers = [fileWrapper fileWrappers];
            allKeys = [fileWrappers allKeys];
            indexWrapper = [fileWrappers objectForKey:@"index.html"];
            if (!indexWrapper || ![(id)indexWrapper isRegularFile]) {
                printWriteErrorAndExit(path, error);
            }
            regularFileContents = [indexWrapper regularFileContents];
            regularFileLength = (NSUInteger)regularFileContents.length;
            if (!regularFileContents || !regularFileLength) {
                printWriteErrorAndExit(path, error);
            }
            if (path) {
                NSString *key;

                for (key in allKeys) {
                    if (![@"index.html" isEqualToString:key]) {
                        NSFileWrapper *subfileWrapper;
                        NSString *parentPath;
                        NSString *subpath;

                        subfileWrapper = [fileWrappers objectForKey:key];
                        parentPath = [path stringByDeletingLastPathComponent];
                        subpath = [parentPath stringByAppendingPathComponent:key];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                        [subfileWrapper writeToURL:[NSURL fileURLWithPath:subpath] options:NSFileWrapperWritingAtomic originalContentsURL:nil error:nil];
#pragma clang diagnostic pop
                    }
                }
                if (![regularFileContents writeToURL:url options:NSDataWritingAtomic error:&error]) {
                    printWriteErrorAndExit(path, error);
                }
            } else {
                fwrite([regularFileContents bytes], 1, regularFileLength, stdout);
            }
        }
    }
}

int main(int argc, const char *argv[])
{
    NSArray *arguments;
    NSMutableArray *inputPaths;
    NSMutableDictionary *readOptions;
    NSMutableDictionary *outputAttributes;
    NSUInteger argumentCount;
    NSUInteger index;
    BOOL treatRemainingArgumentsAsFiles;
    NSUInteger command;
    NSString *outputExtension;
    NSString *defaultOutputExtension;
    NSString *outputPath;
    BOOL outputToStandardOutput;
    BOOL readFromStandardInput;
    BOOL stripMetadata;
    BOOL doNotStoreSubresources;
    NSString *fontName;
    double fontSize;
    NSMutableData *standardInputData;
    NSString *errorString;

    (void)argc;
    (void)argv;

    @autoreleasepool {
    arguments = [[NSProcessInfo processInfo] arguments];
    inputPaths = [NSMutableArray array];
    argumentCount = (NSUInteger)arguments.count;
    readOptions = [NSMutableDictionary dictionary];
    outputAttributes = [NSMutableDictionary dictionary];
    if (argumentCount > 1) {
        fontSize = 0.0;
        index = 1;
        treatRemainingArgumentsAsFiles = NO;
        outputPath = nil;
        outputExtension = nil;
        defaultOutputExtension = nil;
        command = TextutilCommandNone;
        readFromStandardInput = NO;
        fontName = nil;
        doNotStoreSubresources = NO;
        stripMetadata = NO;
        outputToStandardOutput = NO;
        standardInputData = nil;
        while (1) {
            NSString *argument;

            argument = arguments[index];
            if (!argument.length) {
                goto add_input_argument;
            }
            if (treatRemainingArgumentsAsFiles) {
                break;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-help")) {
                if (command) {
                    printErrorStringAndExit("Multiple commands specified.\n");
                }
                command = TextutilCommandHelp;
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-info")) {
                if (command) {
                    printErrorStringAndExit("Multiple commands specified.\n");
                }
                command = TextutilCommandInfo;
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-convert") || TEXTUTIL_STRCASEEQ(argument, @"-cat")) {
                NSString *formatArgument;
                NSString *documentType;

                if (command) {
                    printErrorStringAndExit("Multiple commands specified.\n");
                }
                ++index;
                if (index >= argumentCount) {
                    printErrorStringAndExit("No output format specified.\n");
                }
                command = TEXTUTIL_STRCASEEQ(argument, @"-convert") ? TextutilCommandConvert : TextutilCommandCat;
                formatArgument = arguments[index];
                documentType = NSPlainTextDocumentType;
                defaultOutputExtension = @"txt";
                if (TEXTUTIL_STRCASEEQ(formatArgument, @"txt")) {
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"html")) {
                    documentType = NSHTMLTextDocumentType;
                    defaultOutputExtension = @"html";
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"rtf")) {
                    documentType = NSRTFTextDocumentType;
                    defaultOutputExtension = @"rtf";
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"rtfd")) {
                    documentType = NSRTFDTextDocumentType;
                    defaultOutputExtension = @"rtfd";
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"doc")) {
                    documentType = NSDocFormatTextDocumentType;
                    defaultOutputExtension = @"doc";
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"docx")) {
                    documentType = NSOfficeOpenXMLTextDocumentType;
                    defaultOutputExtension = @"docx";
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"odt")) {
                    documentType = NSOpenDocumentTextDocumentType;
                    defaultOutputExtension = @"odt";
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"wordml")) {
                    documentType = NSWordMLTextDocumentType;
                    defaultOutputExtension = @"xml";
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"webarchive")) {
                    documentType = NSWebArchiveTextDocumentType;
                    defaultOutputExtension = @"webarchive";
                } else {
                    printErrorStringAndExit("Invalid output format.\n");
                }
#if TARGET_OS_IPHONE
                if (TEXTUTIL_IOS_UNSUPPORTED_DOCUMENT_TYPE(documentType)
                 || TEXTUTIL_IOS_PRIVATE_READONLY_DOCUMENT_TYPE(documentType)) {
                    printErrorStringAndExit("Invalid output format.\n");
                }
#endif
                outputAttributes[NSDocumentTypeDocumentAttribute] = documentType;
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-output")) {
                if (outputPath || outputToStandardOutput) {
                    printErrorStringAndExit("Multiple output file destinations specified.\n");
                }
                ++index;
                if (index >= argumentCount || ![arguments[index] length]) {
                    printErrorStringAndExit("No output file name specified.\n");
                }
                outputPath = arguments[index];
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-stdin")) {
                readFromStandardInput = YES;
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-stdout")) {
                if (outputPath) {
                    printErrorStringAndExit("Multiple output file destinations specified.\n");
                }
                outputToStandardOutput = YES;
                outputPath = nil;
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-extension")) {
                ++index;
                if (outputExtension) {
                    printErrorStringAndExit("Multiple extensions specified.\n");
                }
                if (index >= argumentCount || ![arguments[index] length]) {
                    printErrorStringAndExit("No extension specified.\n");
                }
                outputExtension = arguments[index];
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-encoding")) {
                NSString *encodingName;
                NSInteger integerEncoding;
                CFStringEncoding cfEncoding;
                NSUInteger stringEncoding;

                if (outputAttributes[NSCharacterEncodingDocumentAttribute]
                 || outputAttributes[NSTextEncodingNameDocumentAttribute]) {
                    printErrorStringAndExit("Multiple output encodings specified.\n");
                }
                ++index;
                if (index >= argumentCount) {
                    printErrorStringAndExit("No output encoding specified.\n");
                }
                encodingName = arguments[index];
                integerEncoding = encodingName.integerValue;
                cfEncoding = CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)encodingName);
                if (cfEncoding == kCFStringEncodingInvalidId) {
                    stringEncoding = (NSUInteger)integerEncoding;
                } else {
                    stringEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding);
                }
                if (!stringEncoding) {
                    printErrorStringAndExit("Invalid output encoding.\n");
                }
                outputAttributes[NSCharacterEncodingDocumentAttribute] = [NSNumber numberWithUnsignedInteger:stringEncoding];
                if (cfEncoding != kCFStringEncodingInvalidId || !encodingName.integerValue) {
                    outputAttributes[NSTextEncodingNameDocumentAttribute] = encodingName;
                }
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-inputencoding")) {
                NSString *encodingName;
                NSInteger integerEncoding;
                CFStringEncoding cfEncoding;

                if ([readOptions objectForKey:NSCharacterEncodingDocumentOption]
                 || [readOptions objectForKey:NSTextEncodingNameDocumentOption]) {
                    errorString = @"Multiple input encodings specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No input encoding specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                encodingName = arguments[index];
                integerEncoding = encodingName.integerValue;
                cfEncoding = CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)encodingName);
                if (cfEncoding != kCFStringEncodingInvalidId) {
                    [readOptions setObject:[NSNumber numberWithInteger:(NSInteger)CFStringConvertEncodingToNSStringEncoding(cfEncoding)]
                                    forKey:NSCharacterEncodingDocumentOption];
                    if (!encodingName.integerValue) {
                        [readOptions setObject:encodingName forKey:NSTextEncodingNameDocumentOption];
                    }
                } else {
                    [readOptions setObject:[NSNumber numberWithInteger:integerEncoding] forKey:NSCharacterEncodingDocumentOption];
                    if (!encodingName.integerValue) {
                        [readOptions setObject:encodingName forKey:NSTextEncodingNameDocumentOption];
                    }
                }
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-format")) {
                NSString *formatArgument;
                NSString *documentType;

                if ([readOptions objectForKey:NSDocumentTypeDocumentOption]) {
                    printErrorStringAndExit("Multiple input formats specified.\n");
                }
                ++index;
                if (index >= argumentCount) {
                    printErrorStringAndExit("No input format specified.\n");
                }
                formatArgument = arguments[index];
                if (TEXTUTIL_STRCASEEQ(formatArgument, @"txt")) {
                    documentType = NSPlainTextDocumentType;
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"html")) {
                    documentType = NSHTMLTextDocumentType;
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"rtf")) {
                    documentType = NSRTFTextDocumentType;
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"rtfd")) {
                    documentType = NSRTFDTextDocumentType;
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"doc")) {
                    documentType = NSDocFormatTextDocumentType;
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"docx")) {
                    documentType = NSOfficeOpenXMLTextDocumentType;
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"odt")) {
                    documentType = NSOpenDocumentTextDocumentType;
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"wordml")) {
                    documentType = NSWordMLTextDocumentType;
                } else if (TEXTUTIL_STRCASEEQ(formatArgument, @"webarchive")) {
                    documentType = NSWebArchiveTextDocumentType;
                } else {
                    printErrorStringAndExit("Invalid input format.\n");
                }
#if TARGET_OS_IPHONE
                if (TEXTUTIL_IOS_UNSUPPORTED_DOCUMENT_TYPE(documentType)) {
                    printErrorStringAndExit("Invalid input format.\n");
                }
#endif
                [readOptions setObject:documentType forKey:NSDocumentTypeDocumentOption];
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-font")) {
                ++index;
                if (fontName) {
                    errorString = @"Multiple fonts specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                if (index >= argumentCount || ![arguments[index] length]) {
                    errorString = @"No font specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                fontName = arguments[index];
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-fontsize")) {
                NSString *sizeArgument;

                if (fontSize > 0.0) {
                    errorString = @"Multiple font sizes specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No font size specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                sizeArgument = arguments[index];
                fontSize = sizeArgument.doubleValue;
                if (fontSize <= 0.0) {
                    errorString = @"Invalid font size.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"--")) {
                treatRemainingArgumentsAsFiles = YES;
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-noload")) {
                [readOptions setObject:[[TextutilWebDelegate alloc] init] forKey:NSWebResourceLoadDelegateDocumentOption];
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-nostore")) {
                doNotStoreSubresources = YES;
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-baseurl")) {
                NSString *baseURLString;
                NSURL *baseURL;

                if ([readOptions objectForKey:NSBaseURLDocumentOption]) {
                    errorString = @"Multiple base URLs specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No base URL specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                baseURLString = arguments[index];
                baseURL = [[NSURL alloc] initWithString:baseURLString relativeToURL:nil];
                if (!baseURL) {
                    errorString = @"Invalid base URL.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                [readOptions setObject:baseURL forKey:NSBaseURLDocumentOption];
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-timeout")) {
                NSString *timeoutArgument;
                CFMutableStringRef mutableCopy;
                double timeoutValue;

                if ([readOptions objectForKey:NSTimeoutDocumentOption]) {
                    errorString = @"Multiple timeout values specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No timeout value specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                timeoutArgument = arguments[index];
                timeoutValue = timeoutArgument.doubleValue;
                if (timeoutValue == 0.0) {
                    mutableCopy = (__bridge_retained CFMutableStringRef)[timeoutArgument mutableCopy];
                    CFStringTrim(mutableCopy, CFSTR("0"));
                    if (CFStringGetLength(mutableCopy) > 1
                     || (CFStringGetLength(mutableCopy) == 1 && CFStringGetCharacterAtIndex(mutableCopy, 0) != '.')) {
                        CFRelease(mutableCopy);
                        errorString = @"Invalid timeout value.\n";
                        printErrorString(errorString.UTF8String);
                        exit(1);
                    }
                    CFRelease(mutableCopy);
                }
                [readOptions setObject:[NSNumber numberWithDouble:timeoutValue] forKey:NSTimeoutDocumentOption];
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-textsizemultiplier")) {
                NSString *multiplierArgument;
                double multiplierValue;

                if ([readOptions objectForKey:NSTextSizeMultiplierDocumentOption]) {
                    errorString = @"Multiple multiplier values specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No multiplier value specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                multiplierArgument = arguments[index];
                multiplierValue = multiplierArgument.doubleValue;
                if (multiplierValue <= 0.0) {
                    errorString = @"Invalid multiplier value.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                [readOptions setObject:[NSNumber numberWithDouble:multiplierValue] forKey:NSTextSizeMultiplierDocumentOption];
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-excludedelements")) {
                NSString *propertyListString;
                NSArray *propertyList;
                NSInteger listIndex;

                if (outputAttributes[NSExcludedElementsDocumentAttribute]) {
                    errorString = @"Multiple excluded elements lists specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No excluded elements list specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                propertyListString = arguments[index];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                propertyList = [propertyListString propertyList];
#pragma clang diagnostic pop
                if (!propertyList || ![propertyList isKindOfClass:[NSArray class]]) {
                    errorString = @"Invalid excluded element list.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                for (listIndex = (NSInteger)propertyList.count - 1; listIndex != -1; --listIndex) {
                    if (![propertyList[(NSUInteger)listIndex] isKindOfClass:[NSString class]]) {
                        errorString = @"Invalid excluded element list.\n";
                        printErrorString(errorString.UTF8String);
                        exit(1);
                    }
                }
                outputAttributes[NSExcludedElementsDocumentAttribute] = propertyList;
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-prefixspaces")) {
                NSString *prefixArgument;
                NSInteger prefixValue;

                if (outputAttributes[NSPrefixSpacesDocumentAttribute]) {
                    errorString = @"Multiple prefix values specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No prefix value specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                prefixArgument = arguments[index];
                prefixValue = prefixArgument.integerValue;
                if (prefixValue < 0 || (prefixValue == 0 && TEXTUTIL_STRCASEEQ(@"0", prefixArgument))) {
                    errorString = @"Invalid prefix value.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                outputAttributes[NSPrefixSpacesDocumentAttribute] = [NSNumber numberWithInteger:prefixValue];
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-strip")) {
                stripMetadata = YES;
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-title")) {
                if (outputAttributes[NSTitleDocumentAttribute]) {
                    errorString = @"Multiple titles specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No title specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                outputAttributes[NSTitleDocumentAttribute] = arguments[index];
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-author")) {
                if (outputAttributes[NSAuthorDocumentAttribute]) {
                    errorString = @"Multiple authors specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No author specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                outputAttributes[NSAuthorDocumentAttribute] = arguments[index];
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-subject")) {
                if (outputAttributes[NSSubjectDocumentAttribute]) {
                    errorString = @"Multiple subjects specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No subject specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                outputAttributes[NSSubjectDocumentAttribute] = arguments[index];
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-keywords")) {
                NSString *propertyListString;
                NSArray *propertyList;
                NSInteger listIndex;

                if (outputAttributes[NSKeywordsDocumentAttribute]) {
                    errorString = @"Multiple keyword lists specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No keyword list specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                propertyListString = arguments[index];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                propertyList = [propertyListString propertyList];
#pragma clang diagnostic pop
                if (!propertyList || ![propertyList isKindOfClass:[NSArray class]] || !propertyList.count) {
                    errorString = @"Invalid keyword list.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                for (listIndex = (NSInteger)propertyList.count - 1; listIndex != -1; --listIndex) {
                    if (![propertyList[(NSUInteger)listIndex] isKindOfClass:[NSString class]]) {
                        errorString = @"Invalid keyword list.\n";
                        printErrorString(errorString.UTF8String);
                        exit(1);
                    }
                }
                outputAttributes[NSKeywordsDocumentAttribute] = propertyList;
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-comment")) {
                if (outputAttributes[NSCommentDocumentAttribute]) {
                    errorString = @"Multiple comments specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No comment specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                outputAttributes[NSCommentDocumentAttribute] = arguments[index];
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-editor")) {
                if (outputAttributes[NSEditorDocumentAttribute]) {
                    errorString = @"Multiple editors specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No editor specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                outputAttributes[NSEditorDocumentAttribute] = arguments[index];
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-company")) {
                if (outputAttributes[NSCompanyDocumentAttribute]) {
                    errorString = @"Multiple companies specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No company specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                outputAttributes[NSCompanyDocumentAttribute] = arguments[index];
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-creationtime")) {
                NSDate *creationTime;

                if (outputAttributes[NSCreationTimeDocumentAttribute]) {
                    errorString = @"Multiple creation times specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No creation time specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                creationTime = createDateFromISOString(arguments[index]);
                if (!creationTime) {
                    errorString = @"Invalid creation time.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                outputAttributes[NSCreationTimeDocumentAttribute] = creationTime;
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-modificationtime")) {
                NSDate *modificationTime;

                if (outputAttributes[NSModificationTimeDocumentAttribute]) {
                    errorString = @"Multiple modification times specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                ++index;
                if (index >= argumentCount) {
                    errorString = @"No modification time specified.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                modificationTime = createDateFromISOString(arguments[index]);
                if (!modificationTime) {
                    errorString = @"Invalid modification time.\n";
                    printErrorString(errorString.UTF8String);
                    exit(1);
                }
                outputAttributes[NSModificationTimeDocumentAttribute] = modificationTime;
                goto parser_advance;
            }
            if (TEXTUTIL_STRCASEEQ(argument, @"-noversion")) {
                outputAttributes[@"NoCocoaVersion"] = [NSNumber numberWithInteger:1];
                goto parser_advance;
            }

add_input_argument:
            [inputPaths addObject:argument];

parser_advance:
            if (++index >= argumentCount) {
                break;
            }
        }
        while (index < argumentCount) {
            [inputPaths addObject:arguments[index]];
            ++index;
        }
    } else {
        fontSize = 0.0;
        fontName = nil;
        outputExtension = nil;
        defaultOutputExtension = nil;
        outputPath = nil;
        outputToStandardOutput = NO;
        readFromStandardInput = NO;
        stripMetadata = NO;
        doNotStoreSubresources = NO;
        command = TextutilCommandNone;
        standardInputData = nil;
    }

    if (!outputExtension) {
        outputExtension = defaultOutputExtension;
    }
    if (!outputAttributes[NSCharacterEncodingDocumentAttribute]) {
        outputAttributes[NSCharacterEncodingDocumentAttribute] = [NSNumber numberWithUnsignedInteger:NSUTF8StringEncoding];
        outputAttributes[NSTextEncodingNameDocumentAttribute] = @"UTF-8";
    }
    if (!outputAttributes[NSPrefixSpacesDocumentAttribute]) {
        outputAttributes[NSPrefixSpacesDocumentAttribute] = [NSNumber numberWithInteger:2];
    }
    if (!fontName) {
        fontName = @"Helvetica";
    }
    {
        double effectiveFontSize;
#if TARGET_OS_IPHONE
        UIFont *font;
#else
        NSFont *font;
#endif
        NSParagraphStyle *paragraphStyle;
        NSDictionary *defaultAttributes;

        effectiveFontSize = fontSize > 0.0 ? fontSize : 12.0;
        font = chooseFontForPlainTextConversion(fontName, effectiveFontSize);
        paragraphStyle = [NSParagraphStyle defaultParagraphStyle];
        defaultAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
            paragraphStyle, NSParagraphStyleAttributeName,
            font, NSFontAttributeName,
            nil];
        [readOptions setObject:defaultAttributes forKey:NSDefaultAttributesDocumentOption];
    }

    if (readFromStandardInput) {
        int byte;
        int bufferCount;
        unsigned char buffer[256];

        standardInputData = [NSMutableData data];
        if (inputPaths.count) {
            printErrorStringAndExit("Input files and stdin both specified.\n");
        }
        byte = getchar();
        if (byte != EOF) {
            bufferCount = 0;
            do {
                buffer[bufferCount++] = (unsigned char)byte;
                if (bufferCount >= 256) {
                    [standardInputData appendBytes:buffer length:(NSUInteger)bufferCount];
                    bufferCount = 0;
                }
                byte = getchar();
            } while (byte != EOF);
            if (bufferCount > 0) {
                [standardInputData appendBytes:buffer length:(NSUInteger)bufferCount];
            }
        }
    }

    if (command <= TextutilCommandHelp) {
        printUsage(0);
        exit(0);
    }

    if (command == TextutilCommandInfo) {
        NSUInteger count;
        NSUInteger pathIndex;

        count = standardInputData ? 1U : inputPaths.count;
        if (!count) {
            printErrorStringAndExit("No input files specified.\n");
        }
        for (pathIndex = 0; pathIndex != count; ++pathIndex) {
            @autoreleasepool {
                NSDictionary *documentAttributes;
                NSError *error;
                NSAttributedString *attributedString;
                NSString *path;

                documentAttributes = nil;
                error = nil;
                if (standardInputData) {
                    textutilBaseURLForWebResources = nil;
                    attributedString = [[NSAttributedString alloc] initWithData:standardInputData
                                                                        options:readOptions
                                                             documentAttributes:&documentAttributes
                                                                          error:&error];
                    path = @"stdin";
                } else {
                    path = inputPaths[pathIndex];
                    textutilBaseURLForWebResources = [NSURL fileURLWithPath:path];
                    attributedString = [[NSAttributedString alloc] initWithURL:textutilBaseURLForWebResources
                                                                       options:readOptions
                                                            documentAttributes:&documentAttributes
                                                                         error:&error];
#if TARGET_OS_IPHONE
                    if (!attributedString) {
                        attributedString = createAttributedStringFromOfficeImportText(path, [readOptions objectForKey:NSDocumentTypeDocumentOption], &documentAttributes, &error);
                    }
#endif
                }
                if (attributedString) {
                    printFileInfo(attributedString, path, documentAttributes);
                } else {
                    printReadError(path, error);
                }
            }
        }
        exit(0);
    }

    if (!outputExtension) {
        printErrorStringAndExit("No extension specified.\n");
    }

    if (command == TextutilCommandCat) {
        NSMutableAttributedString *combinedString;
        NSMutableDictionary *combinedAttributes;
        NSUInteger count;
        NSUInteger pathIndex;
        BOOL usedDocumentAttributes;

        count = standardInputData ? 1U : inputPaths.count;
        if (!count) {
            printErrorStringAndExit("No input files specified.\n");
        }
        if (!outputPath && !outputToStandardOutput) {
            outputPath = [@"out" stringByAppendingPathExtension:outputExtension];
        }
        combinedString = [[NSMutableAttributedString alloc] init];
        combinedAttributes = nil;
        usedDocumentAttributes = NO;
        for (pathIndex = 0; pathIndex != count; ++pathIndex) {
            @autoreleasepool {
                NSDictionary *documentAttributes;
                NSError *error;
                NSAttributedString *attributedString;
                NSString *path;

                documentAttributes = nil;
                error = nil;
                if (standardInputData) {
                    textutilBaseURLForWebResources = nil;
                    attributedString = [[NSAttributedString alloc] initWithData:standardInputData
                                                                        options:readOptions
                                                             documentAttributes:&documentAttributes
                                                                          error:&error];
                    path = @"stdin";
                } else {
                    path = inputPaths[pathIndex];
                    textutilBaseURLForWebResources = [NSURL fileURLWithPath:path];
                    attributedString = [[NSAttributedString alloc] initWithURL:textutilBaseURLForWebResources
                                                                       options:readOptions
                                                            documentAttributes:&documentAttributes
                                                                         error:&error];
                }
                if (!attributedString) {
                    printReadError(path, error);
                    exit(1);
                }
                if (!usedDocumentAttributes) {
                    combinedAttributes = [copyDocumentAttributesWithOverrides(documentAttributes, outputAttributes, stripMetadata) mutableCopy];
                    [combinedAttributes setObject:[documentAttributes objectForKey:NSDocumentTypeDocumentAttribute]
                                           forKey:@"_SourceDocumentType"];
                    usedDocumentAttributes = YES;
                }
                [combinedString appendAttributedString:attributedString];
            }
        }
        writeAttributedStringOutput(combinedString, outputPath, combinedAttributes, (char)doNotStoreSubresources);
        exit(0);
    }

    if (command == TextutilCommandConvert) {
        NSUInteger count;
        NSUInteger pathIndex;

        count = standardInputData ? 1U : inputPaths.count;
        if (!count) {
            printErrorStringAndExit("No input files specified.\n");
        }
        for (pathIndex = 0; pathIndex != count; ++pathIndex) {
            @autoreleasepool {
                NSDictionary *documentAttributes;
                NSError *error;
                NSAttributedString *attributedString;
                NSString *path;
                NSString *effectiveOutputPath;
                NSMutableDictionary *effectiveAttributes;

                documentAttributes = nil;
                error = nil;
                if (standardInputData) {
                    if (!outputPath && !outputToStandardOutput) {
                        outputPath = [@"out" stringByAppendingPathExtension:outputExtension];
                    }
                    textutilBaseURLForWebResources = nil;
                    attributedString = [[NSAttributedString alloc] initWithData:standardInputData
                                                                        options:readOptions
                                                             documentAttributes:&documentAttributes
                                                                          error:&error];
                    path = @"stdin";
                    effectiveOutputPath = outputPath;
                } else {
                    path = inputPaths[pathIndex];
                    if (pathIndex || (!outputToStandardOutput && !outputPath)) {
                        effectiveOutputPath = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:outputExtension];
                        outputPath = effectiveOutputPath;
                    } else {
                        effectiveOutputPath = outputPath;
                    }
                    textutilBaseURLForWebResources = [NSURL fileURLWithPath:path];
                    attributedString = [[NSAttributedString alloc] initWithURL:textutilBaseURLForWebResources
                                                                       options:readOptions
                                                            documentAttributes:&documentAttributes
                                                                         error:&error];
#if TARGET_OS_IPHONE
                    if (!attributedString
                     && (unsigned char)[NSPlainTextDocumentType isEqualToString:[outputAttributes objectForKey:NSDocumentTypeDocumentAttribute]]) {
                        attributedString = createAttributedStringFromOfficeImportText(path, [readOptions objectForKey:NSDocumentTypeDocumentOption], &documentAttributes, &error);
                    }
#endif
                }
                if (attributedString) {
                    effectiveAttributes = copyDocumentAttributesWithOverrides(documentAttributes, outputAttributes, stripMetadata);
                    [effectiveAttributes setObject:[documentAttributes objectForKey:NSDocumentTypeDocumentAttribute]
                                            forKey:@"_SourceDocumentType"];
                    writeAttributedStringOutput(attributedString, effectiveOutputPath, effectiveAttributes, (char)doNotStoreSubresources);
                } else {
                    printReadError(path, error);
                }
            }
        }
        exit(0);
    }
    exit(0);
    }
}
