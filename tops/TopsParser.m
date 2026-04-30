#import "TopsParser.h"

#import "Find.h"
#import "Replace.h"
#import "TokenizedTopsInput.h"

#import "Common.h"

typedef struct _ReplacemethodInfo {
    BOOL searchIsMetatokenSelector;
    BOOL replacementIsMetatokenSelector;
    BOOL usesSameReplacement;
    BOOL shouldGenerateSelectorRules;
    BOOL shouldGenerateDeclarationRules;
    BOOL shouldGenerateCallRules;
    BOOL shouldGenerateImplementationRules;
    unsigned char pad;
    NSString *replacementSelector;
    NSString *searchSelector;
} _ReplacemethodInfo;

static NSCharacterSet *gNonWhitespaceCharacterSet = nil;

@implementation TopsParser

- (instancetype)init
{
    self = [super init];
    if (self) {
        string = [[NSMutableString alloc] init];
        parsedSourceFilenames = [[NSMutableArray alloc] init];
        parsedRules = [[NSMutableArray alloc] init];
        position = 0;
        parsedClassFilename = nil;
        parsedFlags = (_Flags){ 0 };
        containsScriptFileInput = NO;
    }
    return self;
}

- (instancetype)initWithCommandLineArguments:(NSArray *)arguments
{
    NSInteger lastIndex;
    NSInteger index;
    BOOL valid;
    NSFileManager *fileManager;

    lastIndex = (NSInteger)[arguments count] - 1;
    self = [self init];
    valid = YES;
    if (!lastIndex) {
        fileManager = [NSFileManager defaultManager];
        if (!valid || ![string length] || ![self parse]) {
            return nil;
        }
        return self;
    }

    index = 1;
    while (1) {
        NSString *argument;

        argument = [arguments objectAtIndex:index];
        if ([argument isEqualToString:@"-dont"] || [argument isEqualToString:@"dont"]) {
            parsedFlags.dont = YES;
        } else if ([argument isEqualToString:@"-verbose"] || [argument isEqualToString:@"verbose"]) {
            parsedFlags.verbose = YES;
        } else if ([argument isEqualToString:@"-semiverbose"] || [argument isEqualToString:@"semiverbose"]) {
            parsedFlags.semiVerbose = YES;
        } else if ([argument isEqualToString:@"-nocontext"] || [argument isEqualToString:@"nocontext"]) {
            parsedFlags.noContext = YES;
        } else if ([argument isEqualToString:@"-nofileinfo"] || [argument isEqualToString:@"nofileinfo"]) {
            parsedFlags.noFileInfo = YES;
        } else if ([argument isEqualToString:@"-help"] || [argument isEqualToString:@"help"]) {
            parsedFlags.help = YES;
            valid = YES;
            break;
        } else if ([argument isEqualToString:@"-scriptfile"] || [argument isEqualToString:@"scriptfile"]) {
            NSString *scriptString;

            if (++index > lastIndex) {
                valid = NO;
                break;
            }
            scriptString = [NSString stringWithContentsOfFile:[arguments objectAtIndex:index]
                                                     encoding:NSNEXTSTEPStringEncoding
                                                        error:nil];
            if (!scriptString) {
                valid = NO;
                break;
            }
            containsScriptFileInput = YES;
            [string appendFormat:@" %@ ", scriptString];
        } else if ([argument isEqualToString:@"-find"] ||
                   [argument isEqualToString:@"find"] ||
                   [argument isEqualToString:@"-replace"] ||
                   [argument isEqualToString:@"replace"] ||
                   [argument isEqualToString:@"-replacemethod"] ||
                   [argument isEqualToString:@"replacemethod"] ||
                   [argument isEqualToString:@"error"] ||
                   [argument isEqualToString:@"warning"] ||
                   [argument isEqualToString:@"message"]) {
            if (++index > lastIndex) {
                valid = NO;
                break;
            }
            [string appendFormat:@" %@ \"%@\"", argument, [arguments objectAtIndex:index]];
        } else if ([argument isEqualToString:@"-classfile"]) {
            if (++index > lastIndex) {
                valid = NO;
                break;
            }
            parsedClassFilename = [arguments objectAtIndex:index];
        } else if ([argument hasPrefix:@"-"]) {
            valid = NO;
            break;
        } else if ([argument isEqualToString:@"isOneOf"]) {
            NSString *setArgument;
            NSArray *elements;
            BOOL allQuotedStrings;

            if (++index > lastIndex) {
                valid = NO;
                break;
            }
            setArgument = [arguments objectAtIndex:index];
            allQuotedStrings = NO;
            if ([setArgument hasPrefix:@"{"] &&
                [setArgument hasSuffix:@"}"] &&
                ![setArgument containsString:@"("]) {
                NSString *innerSet;

                innerSet = [setArgument substringWithRange:NSMakeRange(1, [setArgument length] - 2)];
                elements = [innerSet componentsSeparatedByString:@","];
                if ([elements count]) {
                    allQuotedStrings = YES;
                    for (NSString *element in elements) {
                        NSString *trimmedElement;

                        trimmedElement = [element stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                        if ([trimmedElement length] < 2 ||
                            ![trimmedElement hasPrefix:@"\""] ||
                            ![trimmedElement hasSuffix:@"\""]) {
                            allQuotedStrings = NO;
                            break;
                        }
                    }
                }
            }
            if (allQuotedStrings) {
                [NSException raise:@"TOPS PARSING ERROR" format:@""];
            }
            [string appendFormat:@" isOneOf %@", setArgument];
        } else if ([argument isEqualToString:@"within"]) {
            NSString *currentToken;

            if (++index > lastIndex) {
                valid = NO;
                break;
            }
            currentToken = [arguments objectAtIndex:index];
            [string appendFormat:@" within %@", currentToken];
            while (![argument hasSuffix:@"}"]) {
                if (++index > lastIndex) {
                    valid = NO;
                    break;
                }
                currentToken = [arguments objectAtIndex:index];
                [string appendFormat:@" %@", currentToken];
            }
            if (!valid) {
                break;
            }
        } else if ([argument isEqualToString:@"with"]) {
            if (++index > lastIndex) {
                valid = NO;
                break;
            }
            [string appendFormat:@" with \"%@\"", [arguments objectAtIndex:index]];
            if ([argument hasSuffix:@"}"]) {
                while (![argument hasSuffix:@"}"]) {
                    if (++index > lastIndex) {
                        valid = NO;
                        break;
                    }
                    [string appendFormat:@" %@", [arguments objectAtIndex:index]];
                }
                if (!valid) {
                    break;
                }
            }
        } else if ([argument isEqualToString:@"where"]) {
            NSString *currentToken;

            if (++index > lastIndex) {
                valid = NO;
                break;
            }
            currentToken = [arguments objectAtIndex:index];
            if ([argument hasPrefix:@"("]) {
                [string appendFormat:@" where %@", currentToken];
            } else {
                [string appendFormat:@" where \"%@\"", currentToken];
            }
        } else {
            [parsedSourceFilenames addObject:argument];
        }

        if (++index > lastIndex) {
            valid = YES;
            break;
        }
    }

    fileManager = [NSFileManager defaultManager];
    for (index = (NSInteger)[parsedSourceFilenames count] - 1; index >= 0; index--) {
        NSString *path;

        path = [parsedSourceFilenames objectAtIndex:(NSUInteger)index];
        if (![fileManager fileExistsAtPath:path]) {
            printf("File %s does not exist\n\n", [path UTF8String]);
            return nil;
        }
    }

    if (!valid) {
        return nil;
    }
    if (parsedFlags.help && ![string length]) {
        return self;
    }
    if (![string length] || ![self parse]) {
        return nil;
    }
    return self;
}

- (void)error:(NSString *)message, ...
{
    va_list args;
    NSString *formattedMessage;
    NSString *fullMessage;
    NSUInteger remainingLength;
    NSMutableString *preview;

    va_start(args, message);
    formattedMessage = [[NSString alloc] initWithFormat:message arguments:args];
    va_end(args);

    fullMessage = [[NSString alloc] initWithFormat:@"%@, character position = %lu",
                                                   formattedMessage,
                                                   (unsigned long)position];
    if ([string length] > position) {
        remainingLength = [string length] - position - 1;
    } else {
        remainingLength = 0;
    }
    if (remainingLength >= 80) {
        remainingLength = 80;
    }
    preview = [[string substringWithRange:NSMakeRange(position, remainingLength)] mutableCopy];
    ns_printf(@"%@\n%@",
              fullMessage,
              preview);
    [NSException raise:@"TOPS PARSING ERROR" format:@"%@", fullMessage];
}

- (void)skipWhitespaceAndComments
{
    if (!gNonWhitespaceCharacterSet) {
        gNonWhitespaceCharacterSet = [[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet];
    }

    if (position >= [string length]) {
        return;
    }

    while (1) {
        NSRange nonWhitespaceRange;

        nonWhitespaceRange = [string rangeOfCharacterFromSet:gNonWhitespaceCharacterSet
                                                     options:0
                                                       range:NSMakeRange(position, [string length] - position)];
        if (nonWhitespaceRange.location == NSNotFound) {
            position = [string length];
            return;
        }

        position = nonWhitespaceRange.location;
        if ([string rangeOfString:@"/*"
                          options:NSAnchoredSearch
                            range:NSMakeRange(position, [string length] - position)].length == 0) {
            return;
        }

        nonWhitespaceRange = [string rangeOfString:@"*/"
                                           options:0
                                             range:NSMakeRange(position, [string length] - position)];
        if (!nonWhitespaceRange.length) {
            [self error:@"Unterminated comment..."];
            position = [string length];
            return;
        }

        position = nonWhitespaceRange.location + nonWhitespaceRange.length;
        if (position >= [string length]) {
            return;
        }
    }
}

- (BOOL)parseNextQuotedArgumentIntoString:(NSString **)outString optional:(BOOL)optional
{
    NSRange openQuoteRange;
    NSRange closeQuoteRange;
    NSMutableString *quotedString;
    NSRange escapedQuoteRange;

    [self skipWhitespaceAndComments];
    if (position < [string length]) {
        openQuoteRange = [string rangeOfString:@"\""
                                       options:NSAnchoredSearch
                                         range:NSMakeRange(position, [string length] - position)];
        if (openQuoteRange.length) {
            closeQuoteRange.location = openQuoteRange.location;
            do {
                closeQuoteRange = [string rangeOfString:@"\""
                                                options:0
                                                  range:NSMakeRange(closeQuoteRange.location + 1,
                                                                    [string length] - closeQuoteRange.location - 1)];
                if (!closeQuoteRange.length) {
                    [self error:@"Unterminated quoted argument..."];
                    return NO;
                }
            } while ([string characterAtIndex:closeQuoteRange.location - 1] == '\\');

            position = closeQuoteRange.location + 1;
            quotedString = [[NSMutableString alloc] initWithString:
                            [string substringWithRange:NSMakeRange(openQuoteRange.location,
                                                                  closeQuoteRange.location - openQuoteRange.location + 1)]];
            escapedQuoteRange = [quotedString rangeOfString:@"\\\""
                                                    options:NSBackwardsSearch
                                                      range:NSMakeRange(0, [quotedString length])];
            while (escapedQuoteRange.length) {
                [quotedString deleteCharactersInRange:NSMakeRange(escapedQuoteRange.location, 1)];
                if (!escapedQuoteRange.location) {
                    break;
                }
                escapedQuoteRange = [quotedString rangeOfString:@"\\\""
                                                        options:NSBackwardsSearch
                                                          range:NSMakeRange(0, escapedQuoteRange.location)];
            }
            *outString = [quotedString substringWithRange:NSMakeRange(1, [quotedString length] - 2)];
            return YES;
        }
    }

    if (!optional) {
        if (position >= [string length] && containsScriptFileInput) {
            [NSException raise:@"TOPS PARSING ERROR" format:@""];
            return NO;
        }
        [self error:@"Expected '\"'..."];
    }
    return NO;
}

- (BOOL)parseKeyword:(NSString *)keyword optional:(BOOL)optional
{
    NSRange keywordRange;

    [self skipWhitespaceAndComments];
    if (position < [string length]) {
        keywordRange = [string rangeOfString:keyword
                                     options:NSAnchoredSearch
                                       range:NSMakeRange(position, [string length] - position)];
        if (keywordRange.length) {
            position = keywordRange.location + keywordRange.length;
            return YES;
        }
    }

    if (!optional) {
        [self error:@"Expected '%@'", keyword];
    }
    return NO;
}

- (int)nextRuleType
{
    [self skipWhitespaceAndComments];
    if (position < [string length]) {
        if ([self parseKeyword:@"-find" optional:YES] || [self parseKeyword:@"find" optional:YES]) {
            return 2;
        }
        if ([self parseKeyword:@"-replacemethod" optional:YES] || [self parseKeyword:@"replacemethod" optional:YES]) {
            return 8;
        }
        if ([self parseKeyword:@"-replace" optional:YES] || [self parseKeyword:@"replace" optional:YES]) {
            return 4;
        }
        if ([self parseKeyword:@"-nocontext" optional:YES]) {
            return 16;
        }
        if ([self parseKeyword:@"-verbose" optional:YES]) {
            return 32;
        }
        if ([self parseKeyword:@"-semiverbose" optional:YES]) {
            return 64;
        }
        if ([self parseKeyword:@"-dont" optional:YES]) {
            return 128;
        }
        if ([self parseKeyword:@"-nofileinfo" optional:YES]) {
            return 256;
        }
        [self error:@"Expected rule type specifier or flag..."];
    }
    return 0x2000;
}

- (NSDictionary *)generateMetatokenCacheFromMetarules
{
    NSMutableDictionary *metatokenCache;

    metatokenCache = [NSMutableDictionary dictionary];
    if ([self parseKeyword:@"{" optional:YES]) {
        do {
            @autoreleasepool {
                NSString *patternString;
                NSString *replacementString;

                patternString = nil;
                replacementString = nil;
                if ([self nextRuleType] == 4) {
                    [self parseNextQuotedArgumentIntoString:&patternString optional:NO];
                    [self parseKeyword:@"with" optional:YES];
                    [self parseNextQuotedArgumentIntoString:&replacementString optional:NO];
                    [metatokenCache setObject:replacementString forKey:patternString];
                } else {
                    [self error:@"Expected replace rule or '}'"];
                }
            }
        } while (![self parseKeyword:@"}" optional:YES]);
    }
    return metatokenCache;
}

- (NSDictionary *)parseRuleClausesWithMask:(NSUInteger)mask patternString:(NSString *)patternString
{
    NSMutableDictionary *whereClauses;
    NSMutableDictionary *withinClauses;
    NSMutableDictionary *reportClauses;
    NSString *reportString;

    whereClauses = [NSMutableDictionary dictionary];
    withinClauses = [NSMutableDictionary dictionary];
    reportClauses = [NSMutableDictionary dictionary];
    reportString = nil;

    if (position >= [string length]) {
        return [NSMutableDictionary dictionaryWithObjectsAndKeys:
                whereClauses, @"whereClauses",
                withinClauses, @"withinClauses",
                reportClauses, @"reportClauses",
                nil];
    }

    while (1) {
        BOOL parsedClause;

        @autoreleasepool {
            if ([self parseKeyword:@"where" optional:YES]) {
                if ((mask & 0x200) == 0) {
                    [self error:@"Where clauses not allowed in this context..."];
                }
                [self parseWhereClausesIntoDictionary:whereClauses patternString:patternString];
                parsedClause = YES;
            } else if ([self parseKeyword:@"within" optional:YES]) {
                if ((mask & 0x400) == 0) {
                    [self error:@"Within clauses are not allowed in this context..."];
                }
                [self parseWithinClauseIntoDictionary:withinClauses];
                parsedClause = YES;
            } else if ([self parseKeyword:@"warning" optional:YES]) {
                if ((mask & 0x800) == 0) {
                    [self error:@"Warning clauses are not allowed in this context..."];
                }
                [self parseNextQuotedArgumentIntoString:&reportString optional:NO];
                [reportClauses setObject:reportString forKey:@"warning"];
                parsedClause = YES;
            } else if ([self parseKeyword:@"error" optional:YES]) {
                if ((mask & 0x800) == 0) {
                    [self error:@"Error clauses are not allowed in this context..."];
                }
                [self parseNextQuotedArgumentIntoString:&reportString optional:NO];
                [reportClauses setObject:reportString forKey:@"error"];
                parsedClause = YES;
            } else {
                parsedClause = NO;
            }
        }

        if (position >= [string length] || !parsedClause) {
            return [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    whereClauses, @"whereClauses",
                    withinClauses, @"withinClauses",
                    reportClauses, @"reportClauses",
                    nil];
        }
    }
}

- (void)prepareCachedSelectorsForSelectorRule:(NSMutableArray *)rule
                                permanentCopy:(NSArray *)permanentCopy
                                        cache:(NSDictionary *)cache
{
    NSUInteger index;

    @autoreleasepool {
        for (index = 0; index < [permanentCopy count]; index++) {
            NSMutableString *selectorString;
            NSArray *components;
            NSUInteger componentIndex;

            selectorString = [rule objectAtIndex:index];
            components = [cache objectForKey:[permanentCopy objectAtIndex:index]];
            [selectorString setString:@""];
            if ([components count]) {
                if ([components count] == 1) {
                    [selectorString setString:[components objectAtIndex:0]];
                } else {
                    for (componentIndex = 0; componentIndex < [components count]; componentIndex += 2) {
                        [selectorString appendFormat:@"%@:", [components objectAtIndex:componentIndex]];
                    }
                }
            }
        }
    }
}

- (void)prepareCachedSelectorsForDeclarationRule:(NSMutableArray *)rule
                                   permanentCopy:(NSArray *)permanentCopy
                                           cache:(NSDictionary *)cache
                                  metatokenCache:(NSDictionary *)metatokenCache
                                     replacement:(BOOL)replacement
{
    NSUInteger index;

    @autoreleasepool {
        for (index = 0; index < [permanentCopy count]; index++) {
            NSMutableString *selectorString;
            NSArray *components;
            NSUInteger componentIndex;

            selectorString = [rule objectAtIndex:index];
            components = [cache objectForKey:[permanentCopy objectAtIndex:index]];
            [selectorString setString:@""];
            if (![components count]) {
                continue;
            }
            if ([components count] == 1) {
                [selectorString setString:[components objectAtIndex:0]];
                continue;
            }

            for (componentIndex = 0; componentIndex < [components count]; componentIndex += 2) {
                NSString *parameterToken;
                NSString *separator;

                parameterToken = [components objectAtIndex:componentIndex + 1];
                [selectorString appendFormat:@"%@:", [components objectAtIndex:componentIndex]];
                if ([parameterToken length]) {
                    NSString *parameterName;
                    NSString *typeToken;
                    NSString *valueToken;
                    NSString *resolvedTypeToken;
                    NSString *resolvedValueToken;

                    parameterName = [parameterToken substringWithRange:NSMakeRange(1, [parameterToken length] - 2)];
                    typeToken = [NSString stringWithFormat:@"<mtype %@_type>", parameterName];
                    valueToken = [NSString stringWithFormat:@"<token %@_param>", parameterName];
                    resolvedTypeToken = [metatokenCache objectForKey:[TokenizedTopsInput identifierForMetaTokenString:typeToken]];
                    resolvedValueToken = [metatokenCache objectForKey:[TokenizedTopsInput identifierForMetaTokenString:valueToken]];
                    if (!replacement || !resolvedTypeToken) {
                        resolvedTypeToken = typeToken;
                    }
                    if (!replacement || !resolvedValueToken) {
                        resolvedValueToken = valueToken;
                    }
                    separator = (componentIndex < [components count] - 2) ? @" " : @"";
                    [selectorString appendFormat:@"%@%@%@",
                                               resolvedTypeToken,
                                               resolvedValueToken,
                                               separator];
                } else {
                    separator = (componentIndex < [components count] - 2) ? @" " : @"";
                    [selectorString appendFormat:@"<mtype _tops_type%ld><token _tops_param%ld>%@",
                                               (long)componentIndex,
                                               (long)componentIndex,
                                               separator];
                }
            }
        }
    }
}

- (void)prepareCachedSelectorsForCallRule:(NSMutableArray *)rule
                            permanentCopy:(NSArray *)permanentCopy
                                    cache:(NSDictionary *)cache
                           metatokenCache:(NSDictionary *)metatokenCache
                              replacement:(BOOL)replacement
{
    NSUInteger index;

    @autoreleasepool {
        for (index = 0; index < [permanentCopy count]; index++) {
            NSMutableString *selectorString;
            NSArray *components;
            NSUInteger componentIndex;

            selectorString = [rule objectAtIndex:index];
            components = [cache objectForKey:[permanentCopy objectAtIndex:index]];
            [selectorString setString:@""];
            if (![components count]) {
                continue;
            }
            if ([components count] == 1) {
                [selectorString setString:[components objectAtIndex:0]];
                continue;
            }

            for (componentIndex = 0; componentIndex < [components count]; componentIndex += 2) {
                NSString *parameterToken;
                NSString *separator;

                parameterToken = [components objectAtIndex:componentIndex + 1];
                [selectorString appendFormat:@"%@:", [components objectAtIndex:componentIndex]];
                if ([parameterToken length]) {
                    NSString *parameterName;
                    NSString *argumentToken;
                    NSString *resolvedArgumentToken;

                    parameterName = [parameterToken substringWithRange:NSMakeRange(1, [parameterToken length] - 2)];
                    argumentToken = [NSString stringWithFormat:@"<%@_arg>", parameterName];
                    resolvedArgumentToken = [metatokenCache objectForKey:[TokenizedTopsInput identifierForMetaTokenString:argumentToken]];
                    if (!replacement || !resolvedArgumentToken) {
                        resolvedArgumentToken = argumentToken;
                    }
                    separator = (componentIndex < [components count] - 2) ? @" " : @"";
                    [selectorString appendFormat:@"%@%@", resolvedArgumentToken, separator];
                } else {
                    separator = (componentIndex < [components count] - 2) ? @" " : @"";
                    [selectorString appendFormat:@"<_tops_arg%ld>%@", (long)componentIndex, separator];
                }
            }
        }
    }
}

- (void)generateSelectorRule:(NSMutableArray *)rules
                      search:(NSMutableArray *)search
                     replace:(NSMutableArray *)replace
                  permSearch:(NSArray *)permSearch
                 permReplace:(NSArray *)permReplace
                       cache:(NSDictionary *)cache
                        info:(void *)info
                     clauses:(NSDictionary *)clauses
{
    _ReplacemethodInfo *replaceInfo;
    Replace *rule;

    replaceInfo = (_ReplacemethodInfo *)info;
    [self prepareCachedSelectorsForSelectorRule:search permanentCopy:permSearch cache:cache];
    [self prepareCachedSelectorsForSelectorRule:replace permanentCopy:permReplace cache:cache];
    rule = [[Replace alloc] initWithPatternStringNonrecursive:
            [NSString stringWithFormat:@"@selector(%@)", replaceInfo->searchSelector]
                                                        replacementString:
            [NSString stringWithFormat:@"@selector(%@)", replaceInfo->replacementSelector]
                                                                whereDict:
            [[NSDictionary alloc] initWithDictionary:[clauses objectForKey:@"whereClauses"]
                                           copyItems:YES]
                                                                errorDict:[clauses objectForKey:@"reportClauses"]
                                                               withinDict:[clauses objectForKey:@"withinClauses"]];
    if (rule) {
        [rules addObject:rule];
    } else {
        [self error:@"Error occured generating @selector(...) rule for replacemethod"];
    }
}

- (void)generateDeclarationRule:(NSMutableArray *)rules
                         search:(NSMutableArray *)search
                        replace:(NSMutableArray *)replace
                     permSearch:(NSArray *)permSearch
                    permReplace:(NSArray *)permReplace
                          cache:(NSDictionary *)cache
                           info:(void *)info
                        clauses:(NSDictionary *)clauses
                 metatokenCache:(NSDictionary *)metatokenCache
{
    _ReplacemethodInfo *replaceInfo;
    NSString *searchPattern;
    NSString *resolvedReturnType;
    NSString *replacePattern;
    Replace *rule;
    NSString *implementationBinding;
    NSString *searchImplementationPattern;
    NSString *replacePrefix;

    replaceInfo = (_ReplacemethodInfo *)info;
    [self prepareCachedSelectorsForDeclarationRule:search
                                     permanentCopy:permSearch
                                             cache:cache
                                    metatokenCache:metatokenCache
                                       replacement:NO];
    [self prepareCachedSelectorsForDeclarationRule:replace
                                     permanentCopy:permReplace
                                             cache:cache
                                    metatokenCache:metatokenCache
                                       replacement:YES];

    searchPattern = [NSString stringWithFormat:@"<_tops_plusOrMinus _tops_start> <mtype rettype>%@;",
                                               replaceInfo->searchSelector];
    resolvedReturnType = [metatokenCache objectForKey:[TokenizedTopsInput identifierForMetaTokenString:@"<rettype>"]];
    if (!resolvedReturnType) {
        resolvedReturnType = @"<rettype>";
    }
    replacePattern = [NSString stringWithFormat:@"<_tops_plusOrMinus _tops_start> %@%@;",
                                                resolvedReturnType,
                                                replaceInfo->replacementSelector];
    rule = [[Replace alloc] initWithPatternStringNonrecursive:searchPattern
                                                                 replacementString:replacePattern
                                                                         whereDict:[clauses objectForKey:@"whereClauses"]
                                                                         errorDict:[clauses objectForKey:@"reportClauses"]
                                                                        withinDict:[clauses objectForKey:@"withinClauses"]];
    if (rule) {
        [rules addObject:rule];
    } else {
        [self error:@"Error occured generating declaration rule for replacemethod..."];
    }

    implementationBinding = [metatokenCache objectForKey:[TokenizedTopsInput identifierForMetaTokenString:@"<implementation>"]];
    searchImplementationPattern = [NSString stringWithFormat:@"%@<w _tops_w1>{<w _tops_w2><b implementation><w _tops_w3>}",
                                                             [searchPattern substringWithRange:NSMakeRange(0, [searchPattern length] - 1)]];
    replacePrefix = [replacePattern substringWithRange:NSMakeRange(0, [replacePattern length] - 1)];
    if (!implementationBinding) {
        implementationBinding = @"<implementation>";
    }
    rule = [[Replace alloc] initWithPatternStringNonrecursive:searchImplementationPattern
                                                                 replacementString:[NSString stringWithFormat:@"%@<w _tops_w1>{<w _tops_w2>%@<w _tops_w3>}",
                                                                                    replacePrefix,
                                                                                    implementationBinding]
                                                                         whereDict:[clauses objectForKey:@"whereClauses"]
                                                                         errorDict:[clauses objectForKey:@"reportClauses"]
                                                                        withinDict:[clauses objectForKey:@"withinClauses"]];
    if (rule) {
        [rules addObject:rule];
    } else {
        [self error:@"Error occured generating implementation rule for replacemethod..."];
    }
}

- (void)generateCallRule:(NSMutableArray *)rules
                  search:(NSMutableArray *)search
                 replace:(NSMutableArray *)replace
              permSearch:(NSArray *)permSearch
             permReplace:(NSArray *)permReplace
                   cache:(NSDictionary *)cache
                    info:(void *)info
                 clauses:(NSDictionary *)clauses
          metatokenCache:(NSDictionary *)metatokenCache
{
    _ReplacemethodInfo *replaceInfo;
    NSString *callBinding;
    NSString *receiverBinding;
    NSString *searchPattern;
    NSString *replacePattern;
    Replace *rule;

    replaceInfo = (_ReplacemethodInfo *)info;
    [self prepareCachedSelectorsForCallRule:search
                              permanentCopy:permSearch
                                      cache:cache
                             metatokenCache:metatokenCache
                                replacement:NO];
    [self prepareCachedSelectorsForCallRule:replace
                              permanentCopy:permReplace
                                      cache:cache
                             metatokenCache:metatokenCache
                                replacement:YES];

    callBinding = [metatokenCache objectForKey:[TokenizedTopsInput identifierForMetaTokenString:@"<call>"]];
    receiverBinding = [metatokenCache objectForKey:[TokenizedTopsInput identifierForMetaTokenString:@"<receiver>"]];
    searchPattern = [NSString stringWithFormat:@"[<receiver> %@]", replaceInfo->searchSelector];
    if (!receiverBinding) {
        receiverBinding = @"<receiver>";
    }
    replacePattern = [NSString stringWithFormat:@"[%@ %@]", receiverBinding, replaceInfo->replacementSelector];
    if (callBinding) {
        replacePattern = [[[[TokenizedTopsInput alloc] initWithString:callBinding]
                           tokensByReplacingMetaTokensWithBindings:
                           [NSDictionary dictionaryWithObjectsAndKeys:replacePattern, @"<call>", nil]] stringContents];
    }

    rule = [[Replace alloc] initWithPatternString:searchPattern
                                                    replacementString:replacePattern
                                                            whereDict:[[NSDictionary alloc]
                                                                       initWithDictionary:[clauses objectForKey:@"whereClauses"]
                                                                               copyItems:YES]
                                                            errorDict:[clauses objectForKey:@"reportClauses"]
                                                           withinDict:[clauses objectForKey:@"withinClauses"]];
    if (rule) {
        [rules addObject:rule];
    } else {
        [self error:@"Error occured generating call rule for replacemethod..."];
    }
}

- (void)parseReplacemethodRuleIntoArray:(NSMutableArray *)rules
{
    _ReplacemethodInfo info;
    NSMutableArray *searchSelectors;
    NSMutableArray *replaceSelectors;
    NSMutableArray *permanentSearch;
    NSMutableArray *permanentReplace;
    NSMutableDictionary *selectorCache;
    NSString *searchString;
    NSDictionary *metatokenCache;
    NSDictionary *clauses;
    NSArray *replacePermanentCopy;

    info = (_ReplacemethodInfo){ NO, NO, NO, YES, YES, YES, YES, 0, nil, nil };
    searchString = nil;

    @autoreleasepool {
        searchSelectors = [NSMutableArray array];
        replaceSelectors = [NSMutableArray array];
        permanentSearch = [NSMutableArray array];
        permanentReplace = [NSMutableArray array];
        selectorCache = [NSMutableDictionary dictionary];

        [self parseNextQuotedArgumentIntoString:&searchString optional:NO];
        info.searchSelector = searchString;
        if ([searchString length] &&
            [searchString hasSuffix:@">"] &&
            [searchString rangeOfString:@":"].length == 0) {
            info.searchIsMetatokenSelector = YES;
        }

        [self parseKeyword:@"with" optional:YES];
        if ([self parseKeyword:@"same" optional:YES]) {
            info.replacementSelector = info.searchIsMetatokenSelector ? @"<_tops_replacewithsame>" : searchString;
            info.usesSameReplacement = YES;
        } else {
            {
                NSString *replacementSelector;

                replacementSelector = nil;
                [self parseNextQuotedArgumentIntoString:&replacementSelector optional:NO];
                info.replacementSelector = replacementSelector;
            }
        }

        if ([info.replacementSelector length] &&
            [info.replacementSelector hasSuffix:@">"] &&
            [info.replacementSelector rangeOfString:@":"].length == 0) {
            info.replacementIsMetatokenSelector = YES;
        }

        metatokenCache = [self generateMetatokenCacheFromMetarules];
        clauses = [self parseRuleClausesWithMask:3584 patternString:searchString];
        [self cacheSelectorsInDictIntoArray:searchSelectors
                               replaceArray:replaceSelectors
                                  whereDict:[clauses objectForKey:@"whereClauses"]
                                       info:&info];

        if (!info.searchIsMetatokenSelector) {
            searchString = [searchString mutableCopy];
            info.searchSelector = searchString;
            [searchSelectors addObject:searchString];
        }
        if (!info.replacementIsMetatokenSelector) {
            info.replacementSelector = [info.replacementSelector mutableCopy];
            [replaceSelectors addObject:info.replacementSelector];
        }

        [self cacheSelectorComponentsFromArray:searchSelectors
                                  inDictionary:selectorCache
                                         array:permanentSearch];
        replacePermanentCopy = permanentSearch;
        if (!info.usesSameReplacement) {
            [self cacheSelectorComponentsFromArray:replaceSelectors
                                      inDictionary:selectorCache
                                             array:permanentReplace];
            replacePermanentCopy = permanentReplace;
        }

        if (info.shouldGenerateSelectorRules) {
            [self generateSelectorRule:rules
                                search:searchSelectors
                               replace:replaceSelectors
                            permSearch:permanentSearch
                           permReplace:replacePermanentCopy
                                 cache:selectorCache
                                  info:&info
                               clauses:clauses];
        }
        if (info.shouldGenerateCallRules) {
            [self generateCallRule:rules
                            search:searchSelectors
                           replace:replaceSelectors
                        permSearch:permanentSearch
                       permReplace:replacePermanentCopy
                             cache:selectorCache
                              info:&info
                           clauses:clauses
                    metatokenCache:metatokenCache];
        }
        if (info.shouldGenerateImplementationRules || info.shouldGenerateDeclarationRules) {
            [self generateDeclarationRule:rules
                                   search:searchSelectors
                                  replace:replaceSelectors
                               permSearch:permanentSearch
                              permReplace:replacePermanentCopy
                                    cache:selectorCache
                                     info:&info
                                  clauses:clauses
                           metatokenCache:metatokenCache];
        }
    }
}

- (BOOL)parse
{
    position = 0;
    while (1) {
        int ruleType;

        @autoreleasepool {
            ruleType = [self nextRuleType];
            if (ruleType <= 31) {
                if (ruleType > 7) {
                    if (ruleType == 8) {
                        [self parseReplacemethodRuleIntoArray:parsedRules];
                    } else if (ruleType == 16) {
                        parsedFlags.noContext = YES;
                    }
                } else if (ruleType == 2) {
                    [parsedRules addObject:[self parseFindRule]];
                } else if (ruleType == 4) {
                    [parsedRules addObject:[self parseReplaceRule]];
                }
            } else if (ruleType <= 127) {
                if (ruleType == 32) {
                    if (!parsedFlags.semiVerbose && !parsedFlags.verbose) {
                        parsedFlags.verbose = YES;
                    }
                } else if (ruleType == 64) {
                    if (!parsedFlags.semiVerbose && !parsedFlags.verbose) {
                        parsedFlags.semiVerbose = YES;
                    }
                }
            } else if (ruleType == 128) {
                parsedFlags.dont = YES;
            } else if (ruleType == 256) {
                parsedFlags.noFileInfo = YES;
            } else if (ruleType == 0x2000) {
                return YES;
            } else if (ruleType == 0x1000) {
                return NO;
            }
        }
    }
}

- (id)parseFindRule
{
    NSString *patternString;
    NSDictionary *clauses;
    Find *rule;

    patternString = nil;
    [self parseNextQuotedArgumentIntoString:&patternString optional:NO];
    clauses = [self parseRuleClausesWithMask:512 patternString:patternString];
    rule = [[Find alloc] initWithPatternString:patternString
                                                         whereDict:[clauses objectForKey:@"whereClauses"]];
    if (!rule) {
        [self error:@"Error instantiating find rule..."];
    }
    return rule;
}

- (id)parseReplaceRule
{
    NSString *searchString;
    NSString *replacementString;
    NSDictionary *clauses;
    Replace *rule;

    searchString = nil;
    replacementString = nil;
    [self parseNextQuotedArgumentIntoString:&searchString optional:NO];
    [self parseKeyword:@"with" optional:YES];
    if ([self parseKeyword:@"same" optional:YES]) {
        replacementString = searchString;
    } else {
        [self parseNextQuotedArgumentIntoString:&replacementString optional:NO];
    }

    clauses = [self parseRuleClausesWithMask:3584 patternString:searchString];
    rule = [[Replace alloc] initWithPatternString:searchString
                                                     replacementString:replacementString
                                                             whereDict:[clauses objectForKey:@"whereClauses"]
                                                             errorDict:[clauses objectForKey:@"reportClauses"]
                                                            withinDict:[clauses objectForKey:@"withinClauses"]];
    if (!rule) {
        [self error:@"Error instantiating replace rule..."];
    }
    return rule;
}

- (void)parseWhereClausesIntoDictionary:(NSMutableDictionary *)whereClauses patternString:(NSString *)patternString
{
    TokenizedTopsInput *patternTokens;
    BOOL isTupleClause;
    NSString *whereSymbol;
    NSMutableArray *symbols;
    NSMutableDictionary *entriesByHashKey;
    NSString *firstWhereSymbol;
    NSUInteger firstWhereSymbolPosition;
    NSUInteger symbolIndex;

    @autoreleasepool {
        patternTokens = [[TokenizedTopsInput alloc] initWithString:patternString];
        isTupleClause = [self parseKeyword:@"(" optional:YES];
        whereSymbol = nil;
        symbols = [NSMutableArray array];
        entriesByHashKey = [NSMutableDictionary dictionary];
        firstWhereSymbol = nil;
        firstWhereSymbolPosition = [patternTokens numTokens] + 1;

        if (isTupleClause) {
            if (![self parseKeyword:@")" optional:YES]) {
                do {
                    [self parseNextQuotedArgumentIntoString:&whereSymbol optional:NO];
                    [symbols addObject:[TokenizedTopsInput identifierForMetaTokenString:whereSymbol]];
                    [self parseKeyword:@"," optional:YES];
                } while (![self parseKeyword:@")" optional:YES]);
            }
        } else {
            [self parseNextQuotedArgumentIntoString:&whereSymbol optional:NO];
            [symbols addObject:[TokenizedTopsInput identifierForMetaTokenString:whereSymbol]];
        }

        if (![symbols count]) {
            [self error:@"No symbols specified for where clause..."];
        }

        for (symbolIndex = 0; symbolIndex < [symbols count]; symbolIndex++) {
            TokenizedInput *symbolTokens;
            NSUInteger symbolTokenCount;
            NSUInteger patternTokenCount;

            symbolTokens = [[TokenizedTopsInput alloc] initWithString:[symbols objectAtIndex:symbolIndex]];
            symbolTokenCount = [symbolTokens numTokens];
            patternTokenCount = [patternTokens numTokens];
            if (symbolTokenCount && patternTokenCount >= symbolTokenCount) {
                NSUInteger patternIndex;
                NSUInteger maxPatternIndex;

                maxPatternIndex = patternTokenCount - symbolTokenCount + 1;
                for (patternIndex = 0; patternIndex < maxPatternIndex; patternIndex++) {
                    NSUInteger candidateIndex;

                    for (candidateIndex = 0; candidateIndex < symbolTokenCount; candidateIndex++) {
                        if (![[patternTokens substringAtIndex:(patternIndex + candidateIndex)]
                              isEqualToString:[symbolTokens substringAtIndex:candidateIndex]]) {
                            break;
                        }
                    }
                    if (candidateIndex == symbolTokenCount) {
                        if (patternIndex < firstWhereSymbolPosition) {
                            firstWhereSymbol = [symbols objectAtIndex:symbolIndex];
                            firstWhereSymbolPosition = patternIndex;
                        }
                        break;
                    }
                }
            }
        }

        if (!firstWhereSymbol) {
            [self error:@"At least one where symbol must appear in the where clause search pattern..."];
        }

        [self parseKeyword:@"isOneOf" optional:NO];
        [self parseKeyword:@"{" optional:NO];
        if (![self parseKeyword:@"}" optional:YES]) {
            do {
                NSMutableDictionary *bindingEntry;

                @autoreleasepool {
                    NSUInteger entryIndex;
                    TokenizedTopsInput *firstWhereTokens;
                    NSString *hashKey;
                    NSMutableArray *entries;

                    bindingEntry = [NSMutableDictionary dictionary];
                    if (isTupleClause) {
                        [self parseKeyword:@"(" optional:NO];
                    }
                    for (entryIndex = 0; entryIndex < [symbols count]; entryIndex++) {
                        NSString *entryValue;

                        [self parseNextQuotedArgumentIntoString:&entryValue optional:NO];
                        [bindingEntry setObject:[entryValue mutableCopy] forKey:[symbols objectAtIndex:entryIndex]];
                        [self parseKeyword:@"," optional:YES];
                    }

                    firstWhereTokens = [[TokenizedTopsInput alloc] initWithString:[bindingEntry objectForKey:firstWhereSymbol]];
                    hashKey = @"UnhashableWhereDictEntry";
                    if ([firstWhereTokens tokenTypeAtIndex:0] == 2) {
                        hashKey = [firstWhereTokens substringAtIndex:0];
                    }
                    entries = [entriesByHashKey objectForKey:hashKey];
                    if (entries) {
                        [entries addObject:bindingEntry];
                    } else {
                        [entriesByHashKey setObject:[NSMutableArray arrayWithObject:bindingEntry] forKey:hashKey];
                    }
                    if (isTupleClause) {
                        [self parseKeyword:@")" optional:NO];
                    }
                    [self parseKeyword:@"," optional:YES];
                }
            } while (![self parseKeyword:@"}" optional:YES]);
        }

        [whereClauses setObject:entriesByHashKey forKey:firstWhereSymbol];
    }
}

- (void)parseWithinClauseIntoDictionary:(NSMutableDictionary *)withinClauses
{
    NSString *bindingName;
    NSMutableArray *rules;

    bindingName = nil;
    @autoreleasepool {
        rules = [NSMutableArray array];
        [self parseKeyword:@"(" optional:NO];
        [self parseNextQuotedArgumentIntoString:&bindingName optional:NO];
        [self parseKeyword:@")" optional:NO];
        [self parseKeyword:@"{" optional:NO];
        do {
            @autoreleasepool {
                switch ([self nextRuleType]) {
                    case 8:
                        [self parseReplacemethodRuleIntoArray:rules];
                        break;
                    case 4:
                        [rules addObject:[self parseReplaceRule]];
                        break;
                    case 2:
                        [rules addObject:[self parseFindRule]];
                        break;
                    default:
                        [self error:@"Illegal rule type found inside a within clause..."];
                        break;
                }
            }
        } while (![self parseKeyword:@"}" optional:YES]);
        [withinClauses setObject:rules forKey:bindingName];
    }
}

- (void)cacheSelectorComponentsFromArray:(NSArray *)parts
                            inDictionary:(NSMutableDictionary *)dictionary
                                   array:(NSMutableArray *)selectors
{
    NSUInteger index;

    @autoreleasepool {
        for (index = 0; index < [parts count]; index++) {
            NSString *selector;

            selector = [parts objectAtIndex:index];
            if (![dictionary objectForKey:selector]) {
                NSArray *colonParts;
                NSMutableArray *components;
                NSUInteger partIndex;

                colonParts = [selector componentsSeparatedByString:@":"];
                components = [NSMutableArray array];
                for (partIndex = 0; partIndex < [colonParts count]; partIndex++) {
                    NSString *part;
                    NSRange metaRange;
                    NSString *metaToken;
                    NSUInteger suffixStart;
                    NSString *literal;

                    part = [colonParts objectAtIndex:partIndex];
                    metaRange = [TokenizedTopsInput rangeOfMetaTokenInString:part];
                    if (metaRange.location == NSNotFound) {
                        metaToken = @"";
                        suffixStart = 0;
                    } else {
                        metaToken = [part substringWithRange:metaRange];
                        suffixStart = metaRange.location + metaRange.length;
                    }

                    literal = @"";
                    if (suffixStart < [part length]) {
                        NSRange literalRange;

                        literalRange = [part rangeOfCharacterFromSet:[[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet]
                                                             options:0
                                                               range:NSMakeRange(suffixStart, [part length] - suffixStart)];
                        if (literalRange.length) {
                            literal = [part substringFromIndex:literalRange.location];
                        }
                    }

                    if (partIndex != 0) {
                        [components addObject:metaToken];
                    }
                    if ([colonParts count] == 1 || partIndex < [colonParts count] - 1) {
                        [components addObject:literal];
                    }
                }
                [dictionary setObject:components forKey:selector];
            }

            [selectors addObject:[[NSMutableString alloc] initWithString:selector]];
        }
    }
}

- (void)cacheSelectorsInDictIntoArray:(NSMutableArray *)dictionary
                         replaceArray:(NSMutableArray *)replaceArray
                            whereDict:(NSDictionary *)whereDict
                                 info:(void *)info
{
    _ReplacemethodInfo *replaceInfo;
    NSEnumerator *outerEnumerator;
    id outerObject;

    replaceInfo = (_ReplacemethodInfo *)info;
    @autoreleasepool {
        outerEnumerator = [whereDict objectEnumerator];
        while ((outerObject = [outerEnumerator nextObject])) {
            NSEnumerator *innerEnumerator;
            id innerObject;

            innerEnumerator = [outerObject objectEnumerator];
            while ((innerObject = [innerEnumerator nextObject])) {
                NSEnumerator *bindingEnumerator;
                NSDictionary *binding;

                bindingEnumerator = [innerObject objectEnumerator];
                while ((binding = [bindingEnumerator nextObject])) {
                    NSEnumerator *keyEnumerator;
                    NSString *key;

                    keyEnumerator = [binding keyEnumerator];
                    while ((key = [keyEnumerator nextObject])) {
                        NSString *value;

                        value = [binding objectForKey:key];
                        if ([key isEqualToString:replaceInfo->searchSelector]) {
                            [dictionary addObject:value];
                        }
                        if ([key isEqualToString:replaceInfo->replacementSelector]) {
                            [replaceArray addObject:value];
                        }
                    }
                    if (replaceInfo->usesSameReplacement) {
                        NSMutableString *sameReplacement;

                        sameReplacement = [[NSMutableString alloc] init];
                        [(NSMutableDictionary *)binding setObject:sameReplacement forKey:@"<_tops_replacewithsame>"];
                        [replaceArray addObject:sameReplacement];
                    }
                }
            }
        }
    }
}

- (NSMutableArray *)parsedSourceFilenames
{
    return parsedSourceFilenames;
}

- (NSString *)parsedClassFilename
{
    return parsedClassFilename;
}

- (TopsParserFlags)parsedFlags
{
    return *(uint32_t *)&parsedFlags.dont | ((uint64_t)*(uint16_t *)&parsedFlags.noFileInfo << 32);
}

- (NSMutableArray *)parsedRules
{
    return parsedRules;
}

@end
