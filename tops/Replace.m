#import "Replace.h"

#import "Common.h"
#import "Tops.h"

@implementation Replace

- (instancetype)initWithPatternString:(NSString *)patternString
                    replacementString:(NSString *)replacementString
                            whereDict:(NSDictionary *)aWhereDict
                            errorDict:(NSDictionary *)aErrorDict
                           withinDict:(NSDictionary *)aWithinDict
{
    self = [self initWithPatternStringNonrecursive:patternString
                                 replacementString:replacementString
                                         whereDict:aWhereDict
                                         errorDict:aErrorDict
                                        withinDict:aWithinDict];
    if (self) {
        positionToReapply = [self positionToReapplyForRecursiveTok];
    }
    return self;
}

- (instancetype)initWithPatternStringNonrecursive:(NSString *)patternString
                                 replacementString:(NSString *)replacementString
                                         whereDict:(NSDictionary *)aWhereDict
                                         errorDict:(NSDictionary *)aErrorDict
                                        withinDict:(NSDictionary *)aWithinDict
{
    self = [super initWithPatternString:patternString whereDict:aWhereDict];
    if (self) {
        withinDict = (aWithinDict && [aWithinDict count]) ? [[NSMutableDictionary alloc] initWithDictionary:aWithinDict] : nil;
        errorDict = [aErrorDict count] ? aErrorDict : nil;
        replacementTok = [[TokenizedTopsInput alloc] initWithString:replacementString delegate:self];
        positionToReapply = 2;
    }
    return self;
}

- (NSUInteger)positionToReapplyForRecursiveTokAux:(TokenizedInput *)tokens
{
    NSRange matchRange;

    matchRange = [self tokenRangeOfMatch:tokens position:0 bindings:nil anchored:NO];
    if (!matchRange.length) {
        return 0;
    }
    if (matchRange.location) {
        return 2;
    }

    matchRange = [self tokenRangeOfMatch:tokens position:1 bindings:nil anchored:NO];
    if (matchRange.length) {
        return 2;
    }
    return 1;
}

- (NSUInteger)positionToReapplyForRecursiveTok
{
    NSDictionary *aWhereDict;
    NSEnumerator *outerEnumerator;
    id outerObject;
    NSUInteger result;

    aWhereDict = whereDict;
    if (!aWhereDict) {
        return [self positionToReapplyForRecursiveTokAux:[replacementTok tokensByReplacingMetaTokens]];
    }

    outerEnumerator = [aWhereDict objectEnumerator];
    result = 0;
    while ((outerObject = [outerEnumerator nextObject])) {
        NSEnumerator *innerEnumerator;
        id innerObject;

        innerEnumerator = [outerObject objectEnumerator];
        while ((innerObject = [innerEnumerator nextObject])) {
            NSUInteger index;

            if (![innerObject count]) {
                continue;
            }
            for (index = 0; index < [innerObject count]; index++) {
                NSUInteger candidate;

                @autoreleasepool {
                    candidate = [self positionToReapplyForRecursiveTokAux:
                                 [[replacementTok tokensByReplacingMetaTokensWithBindings:[innerObject objectAtIndex:index]]
                                  tokensByReplacingMetaTokens]];
                }
                if (candidate > result) {
                    result = candidate;
                }
                if (result == 2) {
                    return result;
                }
            }
        }
    }
    return result;
}

- (TokenizedInput *)applyToTok:(TokenizedInput *)tokens
                        silent:(BOOL)silent
                      numFound:(NSUInteger *)numFound
                    numChanges:(NSUInteger *)numChanges
{
    NSMutableDictionary *bindings;
    NSRange matchRange;

    bindings = [[NSMutableDictionary alloc] init];
    @autoreleasepool {
        matchRange = [self tokenRangeOfMatch:tokens position:0 bindings:bindings anchored:NO];
        while (matchRange.length) {
            TokenizedTopsInput *resolvedReplacementTok;
            NSString *preWithinReplacement;
            NSString *matchedString;
            NSUInteger nextPosition;

            [bindings setObject:[replacementTok stringContents] forKey:@"call"];
            preWithinReplacement = [[replacementTok tokensByReplacingMetaTokensWithBindings:bindings] stringContents];
            [self applyAllWithinRulesWithBindings:bindings
                                          silent:silent
                                        numFound:numFound
                                      numChanges:numChanges];
            resolvedReplacementTok = [replacementTok tokensByReplacingMetaTokensWithBindings:bindings];
            matchedString = [tokens substringFromTokenRange:matchRange includeSurroundingWhitepsace:NO];

            if (![matchedString isEqualToString:[resolvedReplacementTok stringContents]]) {
                if (![matchedString isEqualToString:preWithinReplacement] &&
                    !silent &&
                    [gCurrentTops showSubstitutions]) {
                    ns_printf(@"%@:%d: '%@' -> '%@'",
                              [gCurrentTops currentSourceFilename],
                              (int)[tokens lineAtIndex:matchRange.location],
                              matchedString,
                              [resolvedReplacementTok stringContents]);
                }
                tokens = [tokens tokensByReplacingRange:matchRange withTokens:resolvedReplacementTok];
                if (numChanges) {
                    ++*numChanges;
                }
                if (numFound) {
                    ++*numFound;
                }
            }

            tokens = [self tokensByInsertingErrorOrWarning:tokens
                                                  bindings:bindings
                                                matchRange:matchRange
                                                  numFound:numFound
                                                numChanges:numChanges];

            nextPosition = matchRange.location;
            if (positionToReapply == 1) {
                nextPosition++;
            } else if (positionToReapply == 2) {
                nextPosition += [resolvedReplacementTok numTokens];
            }

            [bindings removeAllObjects];
            matchRange = [self tokenRangeOfMatch:tokens
                                        position:nextPosition
                                        bindings:bindings
                                        anchored:NO];
        }
    }

    return tokens;
}

- (id)ruleByReplacingMetaTokensWithBindings:(NSDictionary *)bindings
{
    NSString *patternString;
    NSString *replacementString;
    NSDictionary *resolvedWhereDict;
    NSDictionary *resolvedWithinDict;

    patternString = [[patternTok tokensByReplacingMetaTokensWithBindings:bindings] stringContents];
    replacementString = [[replacementTok tokensByReplacingMetaTokensWithBindings:bindings] stringContents];
    resolvedWhereDict = (bindings && whereDict) ? [self whereDictForBindings:bindings] : nil;
    resolvedWithinDict = (bindings && withinDict) ? [self withinDictForBindings:bindings] : nil;
    return [[Replace alloc] initWithPatternString:patternString
                                replacementString:replacementString
                                        whereDict:resolvedWhereDict
                                        errorDict:errorDict
                                       withinDict:resolvedWithinDict];
}

- (void)applyAllWithinRulesWithBindings:(NSMutableDictionary *)bindings
                                 silent:(BOOL)silent
                               numFound:(NSUInteger *)numFound
                             numChanges:(NSUInteger *)numChanges
{
    NSEnumerator *keyEnumerator;
    NSString *key;

    keyEnumerator = [withinDict keyEnumerator];
    while ((key = [keyEnumerator nextObject])) {
        NSString *boundValue;

        @autoreleasepool {
            boundValue = [bindings objectForKey:key];
            if (boundValue) {
                [bindings setObject:[[[Replace tokensByApplyingWithinRules:[withinDict objectForKey:key]
                                                                    tokens:[[TokenizedInput alloc] initWithString:boundValue]
                                                                  bindings:bindings
                                                                    silent:silent
                                                                  numFound:numFound
                                                                numChanges:numChanges] stringContents]
                                   copy]
                             forKey:key];
            }
        }
    }
}

+ (TokenizedInput *)tokensByApplyingWithinRules:(NSArray *)withinRules
                                         tokens:(TokenizedInput *)tokens
                                       bindings:(NSDictionary *)bindings
                                         silent:(BOOL)silent
                                       numFound:(NSUInteger *)numFound
                                     numChanges:(NSUInteger *)numChanges
{
    NSUInteger index;

    for (index = 0; index < [withinRules count]; index++) {
        tokens = [[[withinRules objectAtIndex:index] ruleByReplacingMetaTokensWithBindings:bindings]
                  applyToTok:tokens
                  silent:silent
                  numFound:numFound
                  numChanges:numChanges];
    }
    return tokens;
}

- (NSDictionary *)withinDictForBindings:(NSDictionary *)bindings
{
    NSMutableDictionary *resolvedWithinDict;
    NSEnumerator *keyEnumerator;
    NSString *key;

    resolvedWithinDict = [NSMutableDictionary dictionary];
    keyEnumerator = [withinDict keyEnumerator];
    while ((key = [keyEnumerator nextObject])) {
        NSMutableArray *resolvedRules;
        NSArray *rulesForKey;
        NSUInteger index;

        resolvedRules = [NSMutableArray array];
        rulesForKey = [withinDict objectForKey:key];
        for (index = 0; index < [rulesForKey count]; index++) {
            [resolvedRules insertObject:[[rulesForKey objectAtIndex:index] ruleByReplacingMetaTokensWithBindings:bindings]
                                atIndex:index];
        }
        [resolvedWithinDict setObject:resolvedRules forKey:key];
    }
    return resolvedWithinDict;
}

- (TokenizedInput *)tokensByInsertingErrorOrWarning:(TokenizedInput *)tokens
                                           bindings:(NSDictionary *)bindings
                                         matchRange:(NSRange)matchRange
                                           numFound:(NSUInteger *)numFound
                                         numChanges:(NSUInteger *)numChanges
{
    NSString *directiveKind;
    NSString *messagePattern;
    NSUInteger insertionPoint;
    TokenizedTopsInput *directiveTokens;
    NSString *prefix;
    NSString *directiveLine;
    NSMutableString *updatedString;

    if (!errorDict) {
        return tokens;
    }

    directiveKind = @"error";
    messagePattern = [errorDict objectForKey:directiveKind];
    if (!messagePattern) {
        directiveKind = @"warning";
        messagePattern = [errorDict objectForKey:directiveKind];
        if (!messagePattern) {
            return tokens;
        }
    }

    insertionPoint = [[tokens stringContents] rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n\f"]
                                                              options:NSBackwardsSearch
                                                                range:NSMakeRange(0, [tokens subrangeAtIndex:matchRange.location].location)].location;
    if (insertionPoint == NSNotFound) {
        insertionPoint = 0;
    } else {
        insertionPoint++;
    }

    directiveTokens = [[TokenizedTopsInput alloc] initWithString:messagePattern delegate:self];
    directiveTokens = [directiveTokens tokensByReplacingMetaTokensWithBindings:bindings];
    prefix = insertionPoint ? @"" : @"\n";
    directiveLine = [NSString stringWithFormat:@"%@#%@ %@\n",
                                               prefix,
                                               directiveKind,
                                               [directiveTokens stringContents]];
    updatedString = [[NSMutableString alloc] initWithString:[tokens stringContents]];
    [updatedString insertString:directiveLine atIndex:insertionPoint];
    if (numChanges) {
        ++*numChanges;
    }
    if (numFound) {
        ++*numFound;
    }
    return [[TokenizedInput alloc] initWithString:updatedString];
}

- (NSString *)description
{
    NSMutableString *descriptionString;
    NSString *positionString;

    descriptionString = [[NSMutableString alloc] init];
    [descriptionString appendFormat:@"patternTok = %@\n", patternTok];
    [descriptionString appendFormat:@"replacementTok = %@\n", replacementTok];
    [descriptionString appendFormat:@"whereDict = %@\n", whereDict];
    [descriptionString appendFormat:@"errorDict = %@\n", errorDict];
    [descriptionString appendFormat:@"withinDict = %@\n", withinDict];
    positionString = @"AfterReplacement";
    if (positionToReapply == 1) {
        positionString = @"AtNextToken";
    } else if (positionToReapply == 0) {
        positionString = @"SamePosition";
    }
    [descriptionString appendFormat:@"positionToReapply = %@\n", positionString];
    return descriptionString;
}

@end
