#import "Tops.h"
#import "ClassHierarchy.h"
#import "Common.h"
#import "TokenizedTopsInput.h"
#import "TopsParser.h"
#include <stdio.h>

static const NSStringEncoding kTopsStringEncoding = NSNEXTSTEPStringEncoding;
static const char *const kTopsUsageText =
    "tops [-help] [-dont] [-semiverbose] [-verbose] [-nocontext] [-nofileinfo]\n"
    "     (-scriptfile script_name)                                      |    \n"
    "     (find <search_pattern>                                              \n"
    "         [where (<symbol>...) isOneOf {(<match>...)...}] ...)       |    \n"
    "     (replace <search_pattern> with <replacement_pattern> | same         \n"
    "         [where (<symbol>...) isOneOf {(<match>...)...}]...              \n"
    "         [within (<symbol>) {...}]...                                    \n"
    "         [error <message>]                                               \n"
    "         [warning <message>])                                       |    \n"
    "     (replacemethod <selector> with <new_selector>                       \n"
    "         { [replace <symbol> with <symbol_replacement>]... }             \n"
    "         [where (<symbol>...) isOneOf {(<match> ...)...}]...             \n"
    "         [within (<symbol>) {...}]...                                    \n"
    "         [error <message>]                                               \n"
    "         [warning <message>])                                            \n"
    "     [-classfile classfile]                                              \n"
    "     [filename ...]                                                      ";
static const char *const kTopsHelpExtensionText =
    "       -help        you're looking at it buddy...                          \n"
    "       -dont        simply lists matches without any substitution          \n"
    "       -verbose     gives a little more output                             \n"
    "       -semiverbose gives a little less output                             \n"
    "       -nocontext   print exactly what -find matches                       \n"
    "       -nofileinfo  do not print file name and line number of matches      \n"
    "       -scriptfile  causes tops to use the scripts in <sfile>              \n"
    "                                                                           \n"
    "       find         performs a simple grep for <pattern> for each          \n"
    "                    possibility listed in the where qualification          \n"
    "       replace        substitutes <pattern> with <replacement> in <file>   \n"
    "       error        inserts a line containing #error <message> before      \n"
    "                    lines matching <pattern>                               \n"
    "       warning      inserts a line containing #warning <message> before    \n"
    "                    lines matching <pattern>                               \n"
    "                                                                           \n"
    "       #name        matches any C identifier                               \n"
    "       ##exp        matches any succession of C tokens with matching parens\n"
    "                    exp must start with lowercase letter                   \n"
    "       ##Cxxx       matches C expressions                                  \n"
    "       ##Wxxx       matches whitespace; must start with capital W          \n"
    "       /* */        Comments.  Everything in comments, both in scriptfile  \n"
    "                    and the file you are topsifying, is ignored.           \n"
    "                                                                           \n"
    "                                                                           \n"
    "       /*                                                                  \n"
    "        * Substitute all occurances of 'NXRect' with 'NSRect'              \n"
    "        */                                                                 \n"
    "       subst \"NXRect\"                                                    \n"
    "       with  \"NSRect\"                                                    \n"
    "                                                                           \n"
    "       /*                                                                  \n"
    "        * Substitute all calls to 'crap' with calls to 'dung'              \n"
    "        */                                                                 \n"
    "       subst \"[##obj crap]\"                                              \n"
    "       with  \"[##obj dung]\"                                              \n"
    "                                                                           \n"
    "       /*                                                                  \n"
    "        * Change to new dictionary api calls                               \n"
    "        */                                                                 \n"
    "       subst \"[##dict insert:##key :##value]\"                            \n"
    "       with  \"[##dict setObject:##value forKey:##key]\"                   \n"
    "                                                                           \n"
    "       /*                                                                  \n"
    "        * Substitute past tense versions of some method calls              \n"
    "        */                                                                 \n"
    "       subst \"[##obj ##method]\"                                          \n"
    "       with  \"[##obj ##replacement_method]\"                              \n"
    "       where (\"##method\", \"##replacement_method\") isOneOf {            \n"
    "           (\"eat\", \"ate\"),                                             \n"
    "           (\"sit\", \"sat\"),                                             \n"
    "           (\"run\", \"ran\"),                                             \n"
    "           (\"sleep\", \"slept\")                                          \n"
    "       }                                                                   \n"
    "                                                                           \n"
    "       /*                                                                  \n"
    "        * Change a few method declarations to take 'NSRect' instead of     \n"
    "        * 'NXRect *'                                                       \n"
    "        */                                                                 \n"
    "       subst \"- ##method;\"                                               \n"
    "       with  \"- ##replacement_method;\"                                   \n"
    "       where (\"##method\", \"##replacement_method\") isOneOf {            \n"
    "            (\"(const NXRect *)paperRect\",                                \n"
    "             \"(NSRect)paperRect\"),                                       \n"
    "            (\"calcDrawInfo:(const NXRect *)#aRect\",                      \n"
    "             \"calcDrawInfo:(NSRect)#aRect\"),                             \n"
    "            (\"drawKnob:(const NXRect*)#knobRect\",                        \n"
    "             \"drawKnob:(NSRect)#knobRect\"),                              \n"
    "       }                                                                   \n"
    "                                                                           \n"
    "       /*                                                                  \n"
    "        * Dereference args that used to be pointers for drawAt:, drawIn,   \n"
    "        * and rect:inView:                                                 \n"
    "        */                                                                 \n"
    "       subst \"[##obj ##method]\"                                          \n"
    "       with  \"[##obj ##replacement_method]\"                              \n"
    "       where (\"##method\", \"##replacement_method\") isOneOf {            \n"
    "           (\"drawAt:##point\", \"drawAt:*##point\"),                      \n"
    "           (\"drawIn:##rect\", \"drawIn:*##rect\"),                        \n"
    "           (\"rect:##rect inView:##view\", \"rect:*##rect inView:##view\") \n"
    "       }                                                                   \n"
    "                                                                           \n"
    "       /*                                                                  \n"
    "        * Convert all methods taking 'const NXRect *' to 'NSRect' and      \n"
    "        * make the necessary changes to the args in the body of the        \n"
    "        * methods while preserving whitespace                              \n"
    "        */                                                                 \n"
    "       subst \"- ##meth1:(const NXRect *)#arg##meth2##W1{##W2##body##W3}\" \n"
    "       with  \"- ##meth1:(NSRect)#arg##meth2##W1{##W2##body##W3}\"         \n"
    "       within (\"##body\") {                                               \n"
    "           subst \"#arg->\"                                                \n"
    "           with  \"*#arg.\"                                                \n"
    "                                                                           \n"
    "           subst \"#arg\"                                                  \n"
    "           with  \"&#arg\"                                                 \n"
    "       }                                                                   \n"
    "                                                                           \n"
    "       /*                                                                  \n"
    "        * Convert all methods taking 'const NXRect *', 'const NXPoint *',  \n"
    "        * or 'const NXSize *' to 'NSRect', 'NSPoint', or 'NSSize',         \n"
    "        * respectively, and make the necessary changes to the args in      \n"
    "        * the body of the methods while preserving whitespace              \n"
    "        */                                                                 \n"
    "       subst \"- ##method:##ptrType#arg##methodEnd##W1{##W2##body##W3}\"   \n"
    "       with  \"- ##method:##newType#arg##methodEnd##W1{##W2##body##W3}\"   \n"
    "       where (\"##ptrType\", \"##newType\") isOneOf {                      \n"
    "           (\"(const NXRect *)\", \"(NSRect)\"),                           \n"
    "           (\"(const NXPoint *)\", \"(NSPoint)\"),                         \n"
    "           (\"(const NXSize *)\", \"(NSSize)\")                            \n"
    "       }                                                                   \n"
    "       within (\"##body\") {                                               \n"
    "           subst \"#arg->\"                                                \n"
    "           with  \"*#arg.\"                                                \n"
    "                                                                           \n"
    "           subst \"#arg\"                                                  \n"
    "           with  \"&#arg\"                                                 \n"
    "       }                                                                   \n"
    "                                                                           ";
static const char *const kTopsProgressHeader =
    "[0%................25%................50%................75%..............100%]\n";

@interface NSObject (TopsRuleApplying)
- (TokenizedInput *)applyToTok:(TokenizedInput *)tokens
                        silent:(BOOL)silent
                      numFound:(NSUInteger *)numFound
                    numChanges:(NSUInteger *)numChanges;
@end

static NSFileHandle *statusFileHandle = nil;
static NSUInteger statusProgressDots = 0;

static void tops_printf(NSString *format, ...)
{
    va_list args;

    if (!statusFileHandle) {
        statusFileHandle = NSFileHandle.fileHandleWithStandardOutput;
    }

    va_start(args, format);
    ns_vfprintf(statusFileHandle, format, args);
    va_end(args);
}

@implementation Tops

@synthesize performSubstitutions;
@synthesize showFileInfo;
@synthesize showSubstitutionContext;
@synthesize showSubstitutions;
@synthesize showProgress;
@synthesize currentSourceFilename;
@synthesize classHierarchy;

- (instancetype)init {
    self = [super init];
    if (self) {
        sourceFiles = nil;
        rules = nil;

        performSubstitutions = YES;
        showFileInfo = YES;
        showSubstitutionContext = NO;
        showSubstitutions = YES;
        showProgress = NO;

        classHierarchy = nil;
        classHierarchySourceFilename = nil;
    }
    return self;
}

#if !__has_feature(objc_arc)
- (void)dealloc
{
    [sourceFiles release];
    [rules release];
    [classHierarchy release];
    [classHierarchySourceFilename release];
    [super dealloc];
}
#endif

- (instancetype)initWithCommandLine {
    self = [self init];
    if (!self) {
        return nil;
    }

    BOOL helpRequested = NO;
    if (![self parseCommandLineWithHelpRequest:&helpRequested]) {
        [self printHelp];
#if !__has_feature(objc_arc)
        [self release];
#endif
        return nil;
    }

    if (classHierarchySourceFilename) {
        classHierarchy = [[ClassHierarchy alloc] initWithFile:classHierarchySourceFilename];
        if (!classHierarchy) {
            ns_errorf(@"***Bad class hierarchy");
            [self printHelp];
#if !__has_feature(objc_arc)
            [self release];
#endif
            return nil;
        }
    }

    if (helpRequested) {
        [self printHelp];
#if !__has_feature(objc_arc)
        [self release];
#endif
        return nil;
    }

    return self;
}

- (void)printHelp {
    puts(kTopsUsageText);
}

- (void)printHelpExtension
{
    puts(kTopsHelpExtensionText);
}

- (BOOL)parseCommandLineWithHelpRequest:(BOOL *)withHelpRequest
{
    TopsParser *parser = nil;

    @try {
        parser = [[TopsParser alloc] initWithCommandLineArguments:[[NSProcessInfo processInfo] arguments]];
    } @catch (__unused NSException *exception) {
        ns_printf(@"An error occured parsing rules");
        return NO;
    }
    if (!parser) {
        return NO;
    }

    uint64_t flags = [parser parsedFlags];
    performSubstitutions = (flags & TopsParserFlagDont) == 0;
    showFileInfo = (flags & TopsParserFlagNoFileInfo) == 0;
    showSubstitutionContext = (flags & TopsParserFlagNoContext) == 0;
    showSubstitutions = (flags & (TopsParserFlagDont | TopsParserFlagVerbose)) != 0;
    showProgress = (flags & (TopsParserFlagVerbose | TopsParserFlagSemiVerbose)) != 0;
    *withHelpRequest = (flags & TopsParserFlagHelp) != 0;

#if __has_feature(objc_arc)
    rules = [parser parsedRules];
    sourceFiles = [parser parsedSourceFilenames];
    classHierarchySourceFilename = [parser parsedClassFilename];
#else
    rules = [[parser parsedRules] retain];
    sourceFiles = [[parser parsedSourceFilenames] retain];
    classHierarchySourceFilename = [[parser parsedClassFilename] retain];
    [parser release];
#endif

    return YES;
}

- (NSData *)dataByApplyingRulesToData:(NSData *)data numFound:(NSUInteger *)numFound numChanges:(NSUInteger *)numChanges
{
    NSUInteger totalRules = [rules count];
    NSString *string = [[NSString alloc] initWithData:data encoding:kTopsStringEncoding];
    TokenizedInput *tokens = [[TokenizedInput alloc] initWithString:string];
    TokenizedInput *currentTokens;

    currentRuleIndex = 0;
    *numFound = 0;
    *numChanges = 0;
    currentTokens = tokens;

    while (currentRuleIndex < totalRules) {
        @autoreleasepool {
            id rule = [rules objectAtIndex:currentRuleIndex];
            currentTokens = [rule applyToTok:currentTokens
                                      silent:NO
                                    numFound:numFound
                                  numChanges:numChanges];
            if (showProgress) {
                [self updateStatusBar];
            }
        }
        currentRuleIndex++;
    }

    if (showProgress) {
        [self updateStatusBar];
    }
    if (!performSubstitutions) {
        return data;
    }

    return [[currentTokens stringContents] dataUsingEncoding:kTopsStringEncoding];
}

- (void)applyRules
{
    if (![rules count]) {
        ns_errorf(@"***No rules specified");
        return;
    }

    if ([sourceFiles count]) {
        [self applyRulesToAllSourceFiles];
    } else {
        [self applyRulesToStandardInput];
    }
}

- (void)applyRulesToAllSourceFiles
{
    if (![rules count]) {
        ns_errorf(@"***No rules specified");
        return;
    }
    if (![sourceFiles count]) {
        return;
    }

    NSInteger filesLeft = (NSInteger)[sourceFiles count] - 1;
    for (NSUInteger index = 0; index < [sourceFiles count]; index++, filesLeft--) {
        @autoreleasepool {
            NSString *path = [sourceFiles objectAtIndex:index];
            if (showProgress) {
                if (filesLeft < 2) {
                    if (filesLeft == 1) {
                        tops_printf(@"Processing %@ (1 file left)", path);
                    } else {
                        tops_printf(@"Processing %@ (last file)", path);
                    }
                } else {
                    tops_printf(@"Processing %@ (%d files left)", path, (int)filesLeft);
                }
            }
            [self applyRulesToSourceFileWithPath:path];
        }
    }
}

- (void)applyRulesToSourceFileWithPath:(NSString *)path
{
    if (![rules count]) {
        ns_errorf(@"***No rules specified");
        return;
    }

    NSUInteger numFound = 0;
    NSUInteger numChanges = 0;

    currentSourceFilename = path;
    NSData *originalData = [[NSData alloc] initWithContentsOfFile:path];
    if (!originalData) {
        ns_errorf(@"***Could not read %@", path);
        return;
    }

    NSData *updatedData = [self dataByApplyingRulesToData:originalData
                                                 numFound:&numFound
                                               numChanges:&numChanges];
    if (showProgress && numFound) {
        tops_printf(@"%@: %d occurrences found", path, (int)numFound);
    }
    if (numChanges && performSubstitutions) {
        if ([updatedData writeToFile:path atomically:YES]) {
            if (showProgress) {
                tops_printf(@"%@ written", path);
            }
            return;
        }
        ns_errorf(@"***Could not write %@", path);
    }
}

- (void)applyRulesToStandardInput
{
    if (![rules count]) {
        ns_errorf(@"***No rules specified");
        return;
    }

    @autoreleasepool {
        NSFileHandle *standardInput = NSFileHandle.fileHandleWithStandardInput;
        NSFileHandle *standardOutput = NSFileHandle.fileHandleWithStandardOutput;
        NSData *inputData = [standardInput readDataToEndOfFile];
        NSUInteger numFound = 0;
        NSUInteger numChanges = 0;

        currentSourceFilename = @"StandardInput";
        [standardOutput writeData:[self dataByApplyingRulesToData:inputData
                                                         numFound:&numFound
                                                       numChanges:&numChanges]];
        if (showProgress && numFound) {
            tops_printf(@"%d occurrences", (int)numFound);
        }
    }
}

- (void)updateStatusBar
{
    NSUInteger totalRules = [rules count];

    if (currentRuleIndex == 0) {
        printf("%s", kTopsProgressHeader);
        putchar('[');
        statusProgressDots = 0;
        return;
    }

    if (currentRuleIndex == totalRules) {
        while (statusProgressDots <= 76) {
            putchar('.');
            statusProgressDots++;
        }
        puts("]");
        return;
    }

    double ruleWidth = 77.0 / (double)totalRules;
    while (statusProgressDots < (NSUInteger)(ruleWidth * (double)currentRuleIndex)) {
        putchar('.');
        fflush(stdout);
        statusProgressDots++;
    }
}

@end
