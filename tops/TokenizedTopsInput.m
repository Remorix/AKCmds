#import "TokenizedTopsInput.h"

#import "Common.h"

#include <runetype.h>

static NSCharacterSet *gExpressionStartCharacterSet = nil;
static NSCharacterSet *gExpressionEndCharacterSet = nil;

@interface NSObject (TokenizedTopsInputDelegate)
- (void)setTokenTypesForTokens:(TokenizedTopsInput *)tokens;
@end

@implementation TokenizedTopsInput

- (instancetype)initWithString:(NSString *)aString
{
    return [self initWithString:aString delegate:nil];
}

- (instancetype)initWithString:(NSString *)aString delegate:(id)aDelegate
{
    TopsScannerState *scanner;

    self = [super init];
    if (!self) {
        return nil;
    }

    scanner = tops_scanner_create(aString);
    string = [aString copy];
    if (tops_scanner_next_token(scanner, YES)) {
        do {
            if (count + 1 > max) {
                max = (2 * max) | 1;
                tokens = realloc(tokens, sizeof(_Token) * max);
            }
            tokens[count].lineNumber = (unsigned int)scanner->tokenLine;
            tokens[count].cachedSubstring = NULL;
            tokens[count].modifiers = 0;
            tokens[count].cachedClassName = NULL;
            tokens[count].range = NSMakeRange(scanner->tokenStart, scanner->tokenLength);
            count++;
        } while (tops_scanner_next_token(scanner, YES));
    }
    delegate = aDelegate;
    if (aDelegate && [(id)aDelegate respondsToSelector:@selector(setTokenTypesForTokens:)]) {
        [(id)delegate setTokenTypesForTokens:self];
    } else {
        [self setDefaultTokenTypes];
    }
    free(scanner->characters);
    free(scanner);
    return self;
}

- (id)delegate
{
    return delegate;
}

- (TokenizedTopsInput *)tokensByReplacingMetaTokens
{
    TokenizedTopsInput *expanded;
    NSInteger index;

    expanded = self;
    if ([expanded numTokens]) {
        for (index = (NSInteger)[expanded numTokens] - 1; index >= 0; index--) {
            NSString *replacement;

            replacement = @"ROOT";
            switch ([expanded tokenTypeAtIndex:(NSUInteger)index]) {
                case 1:
                    break;
                case 2:
                    continue;
                case 3:
                    replacement = @"\"stringMatch\"";
                    break;
                case 5:
                case 6:
                case 7:
                case 8:
                case 10:
                    replacement = @"sequenceMatch";
                    break;
                case 9:
                    replacement = @" ";
                    break;
                case 11:
                    replacement = @"(type)";
                    break;
                case 12:
                    replacement = @"-";
                    break;
                default:
                    replacement = @"tokenMatch";
                    break;
            }

            expanded = [expanded tokensByReplacingRange:NSMakeRange((NSUInteger)index, 1)
                                              withTokens:[[TokenizedTopsInput alloc] initWithString:replacement
                                                                                           delegate:delegate]];
        }
    }

    return [[TokenizedTopsInput alloc] initWithString:[expanded stringContents] delegate:delegate];
}

- (NSString *)completeSubstringAtIndex:(NSUInteger)index
{
    if (tokens[index].type == 2) {
        return [self substringAtIndex:index];
    }
    return [string substringWithRange:tokens[index].range];
}

- (NSString *)classOfClassTokenAtIndex:(NSUInteger)index
{
    NSString *className;
    NSString *tokenString;
    NSRange leftParen;
    NSRange rightParen;

    NSCAssert([self tokenTypeAtIndex:index] == 1, @"Class requested of a non-class token");
    className = (__bridge id)tokens[index].cachedClassName;
    if (!className) {
        tokenString = [self completeSubstringAtIndex:index];
        leftParen = [tokenString rangeOfString:@"("];
        rightParen = [tokenString rangeOfString:@")"];
        NSCAssert(leftParen.location != NSNotFound && rightParen.location != NSNotFound,
                  @"Cannot provide class for class token; poorly formed class token: %@", tokenString);
        className = [tokenString substringWithRange:NSMakeRange(leftParen.location + 1,
                                                                rightParen.location - leftParen.location - 1)];
        tokens[index].cachedClassName = CFRetain((__bridge CFTypeRef)className);
    }
    return className;
}

- (NSString *)substringAtIndex:(NSUInteger)index
{
    NSString *tokenString;

    tokenString = (__bridge id)tokens[index].cachedSubstring;
    if (!tokenString) {
        tokenString = [string substringWithRange:tokens[index].range];
        if (tokens[index].type == 2) {
            if (tokens[index].modifiers == 4) {
                tokenString = @"<";
            }
        } else {
            tokenString = [TokenizedTopsInput identifierForMetaTokenString:[string substringWithRange:tokens[index].range]];
        }
        tokens[index].cachedSubstring = CFRetain((__bridge CFTypeRef)tokenString);
    }
    return tokenString;
}

- (NSString *)substringOfSimpleTokensStartingAt:(NSUInteger)index
{
    NSUInteger endIndex;
    NSUInteger tokenCount;

    tokenCount = [self numTokens];
    endIndex = index;
    if (tokenCount > index) {
        endIndex = index;
        while ([self tokenTypeAtIndex:endIndex] == 2) {
            endIndex++;
            if (endIndex == tokenCount) {
                break;
            }
        }
    }
    if (endIndex - 1 < index) {
        return @"";
    }
    return [self substringFromTokenRange:NSMakeRange(index, endIndex - index) includeSurroundingWhitepsace:NO];
}

- (void)setDefaultTokenTypes
{
    NSUInteger index;

    for (index = 0; index < count; index++) {
        NSString *tokenString;
        NSUInteger tokenLength;
        int tokenType;

        tokenLength = tokens[index].range.length;
        tokenString = [string substringWithRange:tokens[index].range];
        if (tokenLength >= 3 &&
            [tokenString hasPrefix:@"<"] &&
            [tokenString hasSuffix:@">"]) {
            NSArray *parts;

            parts = [[tokenString substringWithRange:NSMakeRange(1, [tokenString length] - 2)] componentsSeparatedByString:@" "];
            if ([parts count] != 1) {
                NSString *typeString;

                typeString = [parts objectAtIndex:0];
                if ([@"expression" hasPrefix:typeString]) {
                    tokenType = 8;
                } else if ([@"balanced" hasPrefix:typeString]) {
                    tokenType = 7;
                } else if ([@"token" hasPrefix:typeString]) {
                    tokenType = 0;
                } else if ([@"white" hasPrefix:typeString]) {
                    tokenType = 9;
                } else if ([@"string" hasPrefix:typeString]) {
                    tokenType = 3;
                } else if ([@"scope" hasPrefix:typeString]) {
                    tokenType = 10;
                } else if ([@"anything" hasPrefix:typeString]) {
                    tokenType = 6;
                } else if ([typeString hasPrefix:@"isKindOf("]) {
                    tokenType = 1;
                } else if ([@"mtype" hasPrefix:typeString]) {
                    tokenType = 11;
                } else if ([@"_tops_plusOrMinus" hasPrefix:typeString]) {
                    tokenType = 12;
                } else {
                    ns_errorf(@"***unknown token type for token: '%@'", tokenString);
                    tokenType = 2;
                }
            } else {
                tokenType = 8;
            }
        } else {
            if (tokenLength == 2 && [tokenString isEqualToString:@"\\<"]) {
                tokens[index].modifiers = 4;
            }
            tokenType = 2;
        }
        tokens[index].type = tokenType;
    }
}

- (void)setTokenType:(NSUInteger)tokenType atIndex:(NSUInteger)index
{
    tokens[index].type = (unsigned int)tokenType;
}

- (BOOL)containsDuplicatedMetaTokens
{
    NSMutableArray *seen;
    NSUInteger index;

    seen = [[NSMutableArray alloc] init];
    for (index = 0; index < [self numTokens]; index++) {
        int tokenType;

        tokenType = tokens[index].type;
        if (tokenType != 2 && tokenType != 9) {
            NSString *tokenString;

            tokenString = [self substringAtIndex:index];
            if ([seen containsObject:tokenString]) {
                return YES;
            }
            [seen addObject:tokenString];
        }
    }
    return NO;
}

- (TokenizedTopsInput *)tokensByReplacingRange:(NSRange)range withTokens:(TokenizedInput *)replacement
{
    TokenizedTopsInput *result;

    result = (TokenizedTopsInput *)[super tokensByReplacingRange:range withTokens:replacement];
    result->delegate = delegate;
    return result;
}

- (TokenizedTopsInput *)tokensByReplacingToken:(NSString *)token withString:(NSString *)replacement
{
    NSMutableString *updatedString;
    NSInteger index;

    updatedString = [[NSMutableString alloc] initWithString:string];
    if (count) {
        for (index = (NSInteger)count - 1; index >= 0; index--) {
            if ([self tokenTypeAtIndex:(NSUInteger)index] != 2 &&
                [[self substringAtIndex:(NSUInteger)index] isEqualToString:token]) {
                [updatedString replaceCharactersInRange:tokens[index].range withString:replacement];
            }
        }
    }
    return [[TokenizedTopsInput alloc] initWithString:updatedString delegate:delegate];
}

- (TokenizedTopsInput *)tokensByReplacingMetaTokensWithBindings:(NSDictionary *)bindings
{
    NSMutableString *updatedString;
    NSInteger index;

    updatedString = [[NSMutableString alloc] initWithString:string];
    if (count) {
        for (index = (NSInteger)count - 1; index >= 0; index--) {
            if ([self tokenTypeAtIndex:(NSUInteger)index] != 2) {
                NSString *replacement;

                replacement = [bindings objectForKey:[self substringAtIndex:(NSUInteger)index]];
                if (replacement) {
                    [updatedString replaceCharactersInRange:tokens[index].range withString:replacement];
                }
            }
        }
    }
    return [[TokenizedTopsInput alloc] initWithString:updatedString delegate:delegate];
}

- (NSArray *)arrayOfSimpleTokensStartingAt:(NSUInteger)index
{
    NSMutableArray *simpleTokens;
    NSUInteger tokenCount;

    simpleTokens = [NSMutableArray array];
    tokenCount = [self numTokens];
    if (tokenCount > index) {
        while ([self tokenTypeAtIndex:index] == 2) {
            [simpleTokens addObject:[self substringAtIndex:index++]];
            if (index == tokenCount) {
                break;
            }
        }
    }
    return simpleTokens;
}

- (BOOL)isValidCExpressionStartAtIndex:(NSUInteger)index
{
    unichar character;

    if (!gExpressionStartCharacterSet) {
        gExpressionStartCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"[!~(@*_[{$'&+-\""];
    }

    character = [string characterAtIndex:tokens[index].range.location];
    if (character > 0x7f) {
        if ((unsigned int)__maskrune(character, 0x100)) {
            return YES;
        }
    } else if ((_DefaultRuneLocale.__runetype[character] & 0x100) != 0) {
        return YES;
    }

    if ((unsigned int)(character - 35) <= 0x3c &&
        ((1ULL << ((unsigned char)character - 35)) & 0x1000000000000003ULL) != 0) {
        return YES;
    }
    if ((unsigned int)(character - 45) < 2 || (unsigned int)(character - 48) < 10) {
        return YES;
    }
    return [gExpressionStartCharacterSet characterIsMember:character];
}

- (BOOL)isValidCExpressionEndAtIndex:(NSUInteger)index
{
    unichar character;
    NSString *tokenString;

    if (!gExpressionEndCharacterSet) {
        gExpressionEndCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"]})\"'"];
    }

    character = [string characterAtIndex:tokens[index].range.location + tokens[index].range.length - 1];
    if (character <= 0x7f) {
        if ((_DefaultRuneLocale.__runetype[character] & 0x500) != 0) {
            return YES;
        }
    } else if ((unsigned int)__maskrune(character, 0x500)) {
        return YES;
    }

    if (character == '$' || character == '_') {
        return YES;
    }
    if ([gExpressionEndCharacterSet characterIsMember:character]) {
        return YES;
    }
    tokenString = [self substringAtIndex:index];
    if ([tokenString hasSuffix:@"++"]) {
        return YES;
    }
    return [tokenString hasSuffix:@"--"];
}

+ (NSString *)identifierForMetaTokenString:(NSString *)tokenString
{
    if ([tokenString hasPrefix:@"<"] && [tokenString hasSuffix:@">"]) {
        return [NSString stringWithFormat:@"<%@>",
                [[[tokenString substringWithRange:NSMakeRange(1, [tokenString length] - 2)]
                   componentsSeparatedByString:@" "] lastObject]];
    }
    return [tokenString copy];
}

+ (NSString *)metaTokenStringWithType:(NSUInteger)type label:(NSString *)label
{
    NSString *typeString;

    switch (type) {
        case 0:
            typeString = @"token";
            break;
        case 1:
            typeString = @"isKindOf";
            break;
        case 2:
            typeString = @"simple";
            break;
        case 3:
            typeString = @"string";
            break;
        case 4:
            typeString = @"whereToken";
            break;
        case 5:
            typeString = @"whereSequence";
            break;
        case 6:
            typeString = @"anything";
            break;
        case 7:
            typeString = @"balanced";
            break;
        case 8:
            typeString = @"expression";
            break;
        case 9:
            typeString = @"white";
            break;
        case 10:
            typeString = @"scope";
            break;
        case 11:
            typeString = @"mtype";
            break;
        case 12:
            typeString = @"_tops_plusOrMinus";
            break;
        default:
            typeString = @"";
            break;
    }
    return [NSString stringWithFormat:@"<%@ %@>", typeString, label];
}

+ (NSRange)rangeOfMetaTokenInString:(NSString *)tokenString
{
    TopsScannerState *scanner;
    BOOL didFail;
    NSUInteger location;
    NSUInteger length;
    unichar character;
    BOOL matched;

    didFail = NO;
    scanner = tops_scanner_create(tokenString);
    if (scanner->position >= scanner->length) {
        location = NSNotFound;
        length = 0;
    } else {
        do {
            character = (unichar)tops_scanner_next_significant_character(scanner, &didFail);
            if (didFail) {
                location = NSNotFound;
                length = 0;
                goto done;
            }
            scanner->tokenStart = scanner->position - 1;
            matched = tops_scanner_consume_meta_token(scanner, character);
        } while (scanner->position + 1 < scanner->length && !matched);
        if (!matched) {
            location = NSNotFound;
            length = 0;
        } else {
            location = scanner->tokenStart;
            length = scanner->position - location;
        }
    }

done:
    free(scanner->characters);
    free(scanner);
    return NSMakeRange(location, length);
}

@end
