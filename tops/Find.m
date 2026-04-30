#import "Find.h"

#import "ClassHierarchy.h"
#import "Common.h"
#import "Tops.h"

static const NSUInteger kWhereClauseTokenTypesByPatternType[] = { 4, 4, 5, 4 };

@implementation Find

- (instancetype)initWithPatternString:(NSString *)patternString whereDict:(NSDictionary *)aWhereDict
{
    self = [super init];
    if (self) {
        whereDict = [aWhereDict count] ? aWhereDict : nil;
        patternTok = [[TokenizedTopsInput alloc] initWithString:patternString delegate:self];
        if (![patternTok numTokens]) {
            return nil;
        }
    }
    return self;
}

- (id)ruleByReplacingMetaTokensWithBindings:(NSDictionary *)bindings
{
    NSString *patternString;
    NSDictionary *resolvedWhereDict;

    patternString = [[patternTok tokensByReplacingMetaTokensWithBindings:bindings] stringContents];
    resolvedWhereDict = whereDict ? [self whereDictForBindings:bindings] : nil;
    return [[Find alloc] initWithPatternString:patternString whereDict:resolvedWhereDict];
}

- (NSRange)tokenRangeOfMatch:(TokenizedInput *)inputTok
                    position:(NSUInteger)position
                    bindings:(NSMutableDictionary *)bindings
                    anchored:(BOOL)anchored
{
    NSUInteger tokenCount;
    NSUInteger tokenIndex;
    NSUInteger charPosition;
    NSString *inputString;

    tokenCount = [inputTok numTokens];
    if (tokenCount <= position) {
        return NSMakeRange(NSNotFound, 0);
    }

    charPosition = [inputTok subrangeAtIndex:position].location;
    inputString = [inputTok stringContents];
    for (tokenIndex = 0; tokenIndex < [patternTok numTokens]; tokenIndex++) {
        if ([patternTok tokenTypeAtIndex:tokenIndex] == 2) {
            NSRange foundRange;

            foundRange = [inputString rangeOfString:[patternTok substringAtIndex:tokenIndex]
                                            options:0
                                              range:NSMakeRange(charPosition, [inputString length] - charPosition)];
            if (foundRange.location == NSNotFound) {
                return NSMakeRange(NSNotFound, 0);
            }
            charPosition = foundRange.location;
        }
    }

    return [self tokenRangeOfMatchOfPatternTok:patternTok
                                      inputTok:inputTok
                                      position:position
                                      bindings:bindings
                                      anchored:anchored];
}

- (TokenizedInput *)applyToTok:(TokenizedInput *)tokens
                        silent:(BOOL)silent
                      numFound:(NSUInteger *)numFound
                    numChanges:(NSUInteger *)numChanges
{
    NSRange matchRange;

    (void)numChanges;
    @autoreleasepool {
        matchRange = [self tokenRangeOfMatch:tokens position:0 bindings:nil anchored:NO];
        while (matchRange.length) {
            if (!silent) {
                BOOL showContext;
                BOOL showFileInfo;

                showContext = [gCurrentTops showSubstitutionContext];
                showFileInfo = [gCurrentTops showFileInfo];
                if (showContext) {
                    if (showFileInfo) {
                        ns_printf(@"%@:%d:%@",
                                  [gCurrentTops currentSourceFilename],
                                  (int)[tokens lineAtIndex:matchRange.location],
                                  [tokens lineIncluding:matchRange.location]);
                    } else {
                        ns_printf(@"%@", [tokens lineIncluding:matchRange.location]);
                    }
                } else if (showFileInfo) {
                    ns_printf(@"%@:%d:%@",
                              [gCurrentTops currentSourceFilename],
                              (int)[tokens lineAtIndex:matchRange.location],
                              [tokens substringFromTokenRange:matchRange includeSurroundingWhitepsace:NO]);
                } else {
                    ns_printf(@"%@", [tokens substringFromTokenRange:matchRange includeSurroundingWhitepsace:NO]);
                }
            }

            if (numFound) {
                ++*numFound;
            }
            matchRange = [self tokenRangeOfMatch:tokens
                                        position:(matchRange.location + matchRange.length)
                                        bindings:nil
                                        anchored:NO];
        }
    }

    return tokens;
}

- (void)setTokenTypesForTokens:(TokenizedTopsInput *)tokensToClassify
{
    NSUInteger tokenCount;
    NSUInteger index;

    tokenCount = [tokensToClassify numTokens];
    [tokensToClassify setDefaultTokenTypes];
    if (!whereDict || tokenCount == 0) {
        return;
    }

    for (index = 0; index < tokenCount; index++) {
        if ([whereDict objectForKey:[tokensToClassify substringAtIndex:index]]) {
            NSUInteger tokenType;

            tokenType = [tokensToClassify tokenTypeAtIndex:index];
            if (tokenType > 3) {
                tokenType = 5;
            } else {
                tokenType = kWhereClauseTokenTypesByPatternType[tokenType];
            }
            [tokensToClassify setTokenType:tokenType atIndex:index];
        }
    }
}

- (BOOL)interpretMetatokens
{
    return YES;
}

- (NSRange)tokenRangeOfMatchOfPatternTok:(TokenizedInput *)pattern
                                inputTok:(TokenizedInput *)inputTok
                                position:(NSUInteger)position
                                bindings:(NSMutableDictionary *)bindings
                                anchored:(BOOL)anchored
{
    NSUInteger inputTokenCount;
    BOOL patternHasDuplicateMetaTokens;
    BOOL allowUnanchoredExpressionMatch;
    BOOL scopeConsumesWhitespace;

    inputTokenCount = [inputTok numTokens];
    patternHasDuplicateMetaTokens = [(TokenizedTopsInput *)pattern containsDuplicatedMetaTokens];
    scopeConsumesWhitespace = NO;
    allowUnanchoredExpressionMatch = !anchored;

    while (position < inputTokenCount) {
        NSUInteger startPosition;
        NSUInteger patternIndex;
        NSUInteger inputIndex;
        TokenizedTopsInput *currentPattern;

        startPosition = position;
        patternIndex = 0;
        inputIndex = position;
        currentPattern = (TokenizedTopsInput *)pattern;

        while (1) {
            NSUInteger tokenType;
            NSUInteger nextPatternIndex;

            tokenType = [currentPattern tokenTypeAtIndex:patternIndex];
            switch (tokenType) {
                case 0:
                case 3: {
                    NSString *inputString;
                    NSString *patternString;

                    inputString = [inputTok substringAtIndex:inputIndex];
                    patternString = [currentPattern substringAtIndex:patternIndex];
                    if (tokenType == 3 &&
                        (([inputString characterAtIndex:0] != '"') ||
                         ([inputString characterAtIndex:[inputString length] - 1] != '"'))) {
                        break;
                    }

                    inputIndex++;
                    [bindings setObject:inputString forKey:patternString];

                    nextPatternIndex = patternIndex + 1;
                    if (nextPatternIndex >= [currentPattern numTokens]) {
                        return NSMakeRange(startPosition, inputIndex - startPosition);
                    }
                    if (patternHasDuplicateMetaTokens) {
                        currentPattern = [currentPattern tokensByReplacingToken:patternString withString:inputString];
                    }
                    patternIndex = nextPatternIndex;
                    if (inputIndex < inputTokenCount) {
                        continue;
                    }
                    return NSMakeRange(NSNotFound, 0);
                }

                case 1: {
                    NSString *className;
                    NSString *inputString;
                    NSString *patternString;

                    className = [(TokenizedTopsInput *)currentPattern classOfClassTokenAtIndex:patternIndex];
                    inputString = [inputTok substringAtIndex:inputIndex];
                    patternString = [currentPattern substringAtIndex:patternIndex];
                    if (![inputString isEqualToString:@"ROOT"] &&
                        ![[gCurrentTops classHierarchy] class:inputString descendsFrom:className] &&
                        ![inputString isEqualToString:className]) {
                        break;
                    }

                    [bindings setObject:inputString forKey:patternString];
                    inputIndex++;

                    nextPatternIndex = patternIndex + 1;
                    if (nextPatternIndex >= [currentPattern numTokens]) {
                        return NSMakeRange(startPosition, inputIndex - startPosition);
                    }
                    patternIndex = nextPatternIndex;
                    if (inputIndex < inputTokenCount) {
                        continue;
                    }
                    return NSMakeRange(NSNotFound, 0);
                }

                case 2: {
                    if ([currentPattern tokenModifiersAtIndex:patternIndex] != 4) {
                        if ([inputTok subrangeAtIndex:inputIndex].length != [currentPattern subrangeAtIndex:patternIndex].length) {
                            break;
                        }
                        if ([inputTok char:0 atIndex:inputIndex] != [currentPattern char:0 atIndex:patternIndex]) {
                            break;
                        }
                        if ([currentPattern subrangeAtIndex:patternIndex].length != 1 &&
                            ![[inputTok substringAtIndex:inputIndex] isEqualToString:[currentPattern substringAtIndex:patternIndex]]) {
                            break;
                        }
                    } else if (![[inputTok substringAtIndex:inputIndex] isEqualToString:[currentPattern substringAtIndex:patternIndex]]) {
                        break;
                    }

                    inputIndex++;
                    nextPatternIndex = patternIndex + 1;
                    if (nextPatternIndex >= [currentPattern numTokens]) {
                        return NSMakeRange(startPosition, inputIndex - startPosition);
                    }
                    patternIndex = nextPatternIndex;
                    if (inputIndex < inputTokenCount) {
                        continue;
                    }
                    return NSMakeRange(NSNotFound, 0);
                }

                case 4:
                case 5: {
                    NSDictionary *candidatesByKey;
                    NSMutableArray *candidateBindings;
                    NSArray *unhashableBindings;
                    NSUInteger candidateIndex;

                    candidatesByKey = [whereDict objectForKey:[currentPattern substringAtIndex:patternIndex]];
                    candidateBindings = [NSMutableArray array];
                    if ([candidatesByKey objectForKey:[inputTok substringAtIndex:inputIndex]]) {
                        [candidateBindings addObjectsFromArray:[candidatesByKey objectForKey:[inputTok substringAtIndex:inputIndex]]];
                    }
                    unhashableBindings = [candidatesByKey objectForKey:@"UnhashableWhereDictEntry"];
                    if (unhashableBindings) {
                        [candidateBindings addObjectsFromArray:unhashableBindings];
                    }
                    if (![candidateBindings count]) {
                        break;
                    }

                    for (candidateIndex = 0; candidateIndex < [candidateBindings count]; candidateIndex++) {
                        NSRange recursiveRange;
                        TokenizedTopsInput *replacedPattern;
                        TokenizedTopsInput *subtokens;

                        @autoreleasepool {
                            subtokens = (TokenizedTopsInput *)[currentPattern subtokensFromIndex:patternIndex];
                            replacedPattern = [subtokens tokensByReplacingMetaTokensWithBindings:[candidateBindings objectAtIndex:candidateIndex]];
                            recursiveRange = [self tokenRangeOfMatchOfPatternTok:
                                              replacedPattern
                                                                      inputTok:inputTok
                                                                      position:inputIndex
                                                                      bindings:bindings
                                                                      anchored:YES];
                        }
                        if (recursiveRange.length) {
                            NSEnumerator *keyEnumerator;
                            NSString *key;
                            NSDictionary *candidateBinding;

                            candidateBinding = [candidateBindings objectAtIndex:candidateIndex];
                            keyEnumerator = [candidateBinding keyEnumerator];
                            while ((key = [keyEnumerator nextObject])) {
                                NSString *value;

                                value = [[[[TokenizedTopsInput alloc] initWithString:[candidateBinding objectForKey:key]
                                                                           delegate:self]
                                          tokensByReplacingMetaTokensWithBindings:bindings] stringContents];
                                if (patternHasDuplicateMetaTokens) {
                                    currentPattern = [currentPattern tokensByReplacingToken:key withString:value];
                                }
                                [bindings setObject:value forKey:key];
                            }
                            return NSMakeRange(startPosition, inputIndex - startPosition + recursiveRange.length);
                        }
                    }
                    break;
                }

                case 6:
                case 7:
                case 8:
                case 10: {
                    NSUInteger followingType;
                    NSRange captureRange;
                    NSArray *untilTokens;
                    NSString *captureKey;
                    NSString *captureValue;

                    if (tokenType == 10) {
                        scopeConsumesWhitespace = YES;
                    }

                    nextPatternIndex = patternIndex + 1;
                    if (nextPatternIndex >= [currentPattern numTokens]) {
                        followingType = 2;
                    } else {
                        followingType = [currentPattern tokenTypeAtIndex:nextPatternIndex];
                        if ((followingType - 4 >= 2) && followingType != 2) {
                            if (followingType != 9 ||
                                nextPatternIndex + 1 >= [currentPattern numTokens] ||
                                [currentPattern tokenTypeAtIndex:nextPatternIndex + 1] != 2) {
                                NSUInteger maxRangeLength;
                                NSString *tokenString;
                                NSString *preview;
                                NSString *suffix;

                                maxRangeLength = [currentPattern numTokens] - nextPatternIndex;
                                if (maxRangeLength >= 8) {
                                    maxRangeLength = 8;
                                }
                                tokenString = [currentPattern substringAtIndex:patternIndex];
                                preview = [currentPattern substringFromTokenRange:NSMakeRange(patternIndex, maxRangeLength)
                                                      includeSurroundingWhitepsace:NO];
                                suffix = (maxRangeLength == ([currentPattern numTokens] - nextPatternIndex)) ? @"" : @"...";
                                ns_errorf(@"***Explicit token or whitespace token must follow '%@': %@%@",
                                          tokenString,
                                          preview,
                                          suffix);
                                return NSMakeRange(NSNotFound, 0);
                            }
                            followingType = 9;
                        }
                    }

                    untilTokens = nil;
                    if (nextPatternIndex >= [currentPattern numTokens]) {
                        captureRange = [inputTok tokenRangeFromTokenIndex:inputIndex untilTokens:nil withType:tokenType];
                    } else if (followingType == 2) {
                        untilTokens = [currentPattern arrayOfSimpleTokensStartingAt:nextPatternIndex];
                        captureRange = [inputTok tokenRangeFromTokenIndex:inputIndex untilTokens:untilTokens withType:tokenType];
                    } else if (followingType == 9) {
                        untilTokens = [currentPattern arrayOfSimpleTokensStartingAt:nextPatternIndex + 1];
                        captureRange = [inputTok tokenRangeFromTokenIndex:inputIndex untilTokens:untilTokens withType:tokenType];
                    } else if ((followingType & ~1U) == 4) {
                        NSString *firstWhereSymbol;

                        firstWhereSymbol = [currentPattern substringAtIndex:nextPatternIndex];
                        captureRange = [inputTok tokenRangeFromTokenIndex:inputIndex
                                                   untilTokenFromWhereDict:[whereDict objectForKey:firstWhereSymbol]
                                                          firstWhereSymbol:firstWhereSymbol
                                                                  withType:tokenType];
                    } else {
                        if (tokenType == 8) {
                            break;
                        }
                        captureRange = NSMakeRange(0, 0);
                    }

                    if (tokenType == 8 &&
                        (!captureRange.length ||
                         (!allowUnanchoredExpressionMatch && captureRange.location != inputIndex))) {
                        break;
                    }

                    captureKey = [currentPattern substringAtIndex:patternIndex];
                    captureValue = [inputTok substringFromTokenRange:captureRange
                                         includeSurroundingWhitepsace:scopeConsumesWhitespace];
                    inputIndex += captureRange.length;
                    [bindings setObject:captureValue forKey:captureKey];

                    if (nextPatternIndex >= [currentPattern numTokens]) {
                        return NSMakeRange(startPosition, inputIndex - startPosition);
                    }
                    if (patternHasDuplicateMetaTokens) {
                        currentPattern = [currentPattern tokensByReplacingToken:captureKey withString:captureValue];
                    }
                    scopeConsumesWhitespace = NO;
                    patternIndex = nextPatternIndex;
                    if (inputIndex < inputTokenCount) {
                        continue;
                    }
                    return NSMakeRange(NSNotFound, 0);
                }

                case 9: {
                    nextPatternIndex = patternIndex + 1;
                    [bindings setObject:[inputTok substringOfWhitespaceBeforeTokenIndex:inputIndex]
                                 forKey:[currentPattern substringAtIndex:patternIndex]];
                    if (nextPatternIndex >= [currentPattern numTokens]) {
                        ns_errorf(@"***Pattern can't end on whitespace: '%@'", currentPattern);
                        return NSMakeRange(NSNotFound, 0);
                    }
                    patternIndex = nextPatternIndex;
                    if (inputIndex < inputTokenCount) {
                        continue;
                    }
                    return NSMakeRange(NSNotFound, 0);
                }

                case 11: {
                    NSUInteger consumedLength;
                    NSString *captureKey;
                    NSString *captureValue;

                    if (![[inputTok substringAtIndex:inputIndex] isEqualToString:@"("]) {
                        consumedLength = 0;
                        captureValue = @"";
                    } else {
                        NSRange typeRange;

                        typeRange = [inputTok tokenRangeFromTokenIndex:(inputIndex + 1) untilTokens:nil withType:7];
                        if (!typeRange.length ||
                            ![[inputTok substringAtIndex:(inputIndex + 1 + typeRange.length)] isEqualToString:@")"]) {
                            break;
                        }
                        consumedLength = typeRange.length + 2;
                        captureValue = [inputTok substringFromTokenRange:NSMakeRange(typeRange.location - 1, consumedLength)
                                             includeSurroundingWhitepsace:NO];
                    }

                    captureKey = [currentPattern substringAtIndex:patternIndex];
                    [bindings setObject:captureValue forKey:captureKey];
                    inputIndex += consumedLength;

                    nextPatternIndex = patternIndex + 1;
                    if (nextPatternIndex >= [currentPattern numTokens]) {
                        return NSMakeRange(startPosition, inputIndex - startPosition);
                    }
                    patternIndex = nextPatternIndex;
                    if (inputIndex < inputTokenCount) {
                        continue;
                    }
                    return NSMakeRange(NSNotFound, 0);
                }

                case 12: {
                    NSString *inputString;
                    NSString *patternString;

                    inputString = [inputTok substringAtIndex:inputIndex];
                    if (![inputString isEqualToString:@"-"] && ![inputString isEqualToString:@"+"]) {
                        break;
                    }

                    patternString = [currentPattern substringAtIndex:patternIndex];
                    [bindings setObject:inputString forKey:patternString];
                    inputIndex++;

                    nextPatternIndex = patternIndex + 1;
                    if (nextPatternIndex >= [currentPattern numTokens]) {
                        return NSMakeRange(startPosition, inputIndex - startPosition);
                    }
                    patternIndex = nextPatternIndex;
                    if (inputIndex < inputTokenCount) {
                        continue;
                    }
                    return NSMakeRange(NSNotFound, 0);
                }

                default:
                    ns_errorf(@"token type not implemented yet: '%@' , line %d",
                              [currentPattern substringAtIndex:patternIndex],
                              (int)[currentPattern lineAtIndex:patternIndex]);
                    patternIndex++;
                    if (patternIndex < [currentPattern numTokens] && inputIndex < inputTokenCount) {
                        continue;
                    }
                    return NSMakeRange(NSNotFound, 0);
            }

            position = startPosition + 1;
            if (anchored) {
                return NSMakeRange(NSNotFound, 0);
            }
            break;
        }
    }

    return NSMakeRange(NSNotFound, 0);
}

- (NSDictionary *)whereDictForBindings:(NSDictionary *)bindings
{
    NSEnumerator *whereEnumerator;
    NSMutableDictionary *resolvedWhereDict;
    NSString *whereSymbol;

    whereEnumerator = [whereDict keyEnumerator];
    resolvedWhereDict = [NSMutableDictionary dictionary];
    while ((whereSymbol = [whereEnumerator nextObject])) {
        NSDictionary *clauseDict;
        NSEnumerator *matchEnumerator;
        NSMutableDictionary *resolvedClauseDict;
        NSString *matchKey;

        clauseDict = [whereDict objectForKey:whereSymbol];
        matchEnumerator = [clauseDict keyEnumerator];
        resolvedClauseDict = [NSMutableDictionary dictionary];
        while ((matchKey = [matchEnumerator nextObject])) {
            NSArray *bindingList;
            NSMutableArray *resolvedBindingList;
            NSUInteger index;
            NSString *resolvedMatchKey;

            bindingList = [clauseDict objectForKey:matchKey];
            resolvedBindingList = [NSMutableArray array];
            for (index = 0; index < [bindingList count]; index++) {
                @autoreleasepool {
                    NSDictionary *binding;
                    NSEnumerator *bindingKeyEnumerator;
                    NSMutableDictionary *resolvedBinding;
                    NSString *bindingKey;

                    binding = [bindingList objectAtIndex:index];
                    bindingKeyEnumerator = [binding keyEnumerator];
                    resolvedBinding = [NSMutableDictionary dictionary];
                    while ((bindingKey = [bindingKeyEnumerator nextObject])) {
                        NSString *value;

                        value = [[[[TokenizedTopsInput alloc] initWithString:[binding objectForKey:bindingKey]
                                                                   delegate:self]
                                  tokensByReplacingMetaTokensWithBindings:bindings] stringContents];
                        [resolvedBinding setObject:value forKey:bindingKey];
                    }
                    [resolvedBindingList insertObject:resolvedBinding atIndex:index];
                }
            }

            resolvedMatchKey = [bindings objectForKey:matchKey];
            if (!resolvedMatchKey) {
                resolvedMatchKey = matchKey;
            }
            [resolvedClauseDict setObject:resolvedBindingList forKey:resolvedMatchKey];
        }
        [resolvedWhereDict setObject:resolvedClauseDict forKey:whereSymbol];
    }

    return resolvedWhereDict;
}

- (NSString *)description
{
    NSMutableString *descriptionString;

    descriptionString = [[NSMutableString alloc] init];
    [descriptionString appendFormat:@"patternTok = %@\n", patternTok];
    [descriptionString appendFormat:@"whereDict = %@\n", whereDict];
    return descriptionString;
}

@end
