#import "TokenizedInput.h"

#import <CoreFoundation/CoreFoundation.h>

#import "Common.h"
#import "TokenizedTopsInput.h"

#include <ctype.h>
#include <runetype.h>
#include <stdlib.h>

typedef struct TopsTokenMatchState {
    NSUInteger parenthesisDepth;
    NSUInteger bracketDepth;
    NSUInteger braceDepth;
    __unsafe_unretained NSArray *boundaryTokens;
    __unsafe_unretained NSDictionary *whereBindings;
    __unsafe_unretained NSString *primaryWhereSymbol;
    BOOL usesWhereBindings;
} TopsTokenMatchState;

#define TOPS_IS_CTYPE(character, mask) (__istype((int)(character), (mask)) != 0)
#define TOPS_IS_DECIMAL_DIGIT(character) ((character) >= '0' && (character) <= '9')
#define TOPS_IS_OCTAL_DIGIT(character) ((character) >= '0' && (character) <= '7')
#define TOPS_IS_IDENTIFIER_START_EXTRA(character) ((character) == '#' || (character) == '$' || (character) == '_')
#define TOPS_IS_IDENTIFIER_BODY_EXTRA(character) ((character) == '$' || (character) == '_')
#define TOPS_IS_METATOKEN_CLASS_EXTRA(character) ((character) == '$' || (character) == '<' || (character) == '>' || (character) == '_')
#define TOPS_IS_PREPROCESSOR_DIRECTIVE(tokenString) ([(tokenString) hasPrefix:@"#"])
#define TOPS_IS_DISALLOWED_TOP_LEVEL_EXPRESSION_TOKEN(tokenString) \
    ([(tokenString) isEqualToString:@"if"] || \
     [(tokenString) isEqualToString:@"else"] || \
     [(tokenString) isEqualToString:@"while"] || \
     [(tokenString) isEqualToString:@"switch"] || \
     [(tokenString) isEqualToString:@"case"] || \
     [(tokenString) isEqualToString:@"break"] || \
     [(tokenString) isEqualToString:@"return"] || \
     [(tokenString) isEqualToString:@"default"] || \
     [(tokenString) isEqualToString:@"goto"] || \
     [(tokenString) isEqualToString:@"typedef"] || \
     [(tokenString) isEqualToString:@"struct"] || \
     [(tokenString) isEqualToString:@"static"] || \
     [(tokenString) isEqualToString:@"extern"] || \
     [(tokenString) isEqualToString:@"do"] || \
     TOPS_IS_PREPROCESSOR_DIRECTIVE(tokenString))
#define TOPS_IS_CONDITIONAL_STATEMENT_KEYWORD(tokenString) \
    ([(tokenString) isEqualToString:@"if"] || \
     [(tokenString) isEqualToString:@"while"] || \
     [(tokenString) isEqualToString:@"switch"])
#define TOPS_IS_ASSIGNMENT_OPERATOR_PREFIX(character) \
    ((character) == '!' || (character) == '%' || (character) == '&' || (character) == '*' || \
     (character) == '+' || (character) == '-' || (character) == '/' || (character) == '<' || \
     (character) == '=' || (character) == '>' || (character) == '^' || (character) == '~' || \
     (character) == '|')

BOOL tops_is_simple_token_character(unichar character)
{
    return TOPS_IS_CTYPE(character, _CTYPE_A) || TOPS_IS_IDENTIFIER_START_EXTRA(character);
}

TopsScannerState * _Nullable tops_scanner_create(NSString *source)
{
    TopsScannerState *scanner;

    scanner = malloc(sizeof(*scanner));
    if (!scanner) {
        return NULL;
    }

    scanner->length = [source length];
    scanner->characters = malloc(sizeof(unichar) * scanner->length);
    [source getCharacters:scanner->characters];
    scanner->position = 0;
    scanner->lineNumber = 1;
    scanner->tokenStart = 0;
    scanner->tokenLength = 0;
    scanner->tokenLine = 1;
    return scanner;
}

TopsScannerState *tops_scanner_consume_escape_sequence(TopsScannerState *scanner)
{
    NSUInteger escapeCursor;
    unichar escapeCharacter;

    escapeCursor = scanner->position + 1;
    scanner->position = escapeCursor;
    escapeCharacter = scanner->characters[escapeCursor - 1];
    if (TOPS_IS_OCTAL_DIGIT(escapeCharacter)) {
        if (escapeCursor < scanner->length && TOPS_IS_OCTAL_DIGIT(scanner->characters[escapeCursor])) {
            scanner->position = escapeCursor + 1;
            if (escapeCursor + 1 < scanner->length && TOPS_IS_OCTAL_DIGIT(scanner->characters[escapeCursor + 1])) {
                scanner->position = escapeCursor + 2;
            }
        }
        return scanner;
    }

    if (escapeCharacter == '\n') {
        scanner->lineNumber++;
        return scanner;
    }

    if (escapeCharacter == 'x') {
        if (escapeCursor < scanner->length) {
            unichar hex = scanner->characters[escapeCursor];

            if (TOPS_IS_CTYPE(hex, _CTYPE_X)) {
                escapeCursor = scanner->position + 1;
                scanner->position = escapeCursor;
            }
        }
        if (escapeCursor < scanner->length) {
            unichar hex = scanner->characters[escapeCursor];

            if (TOPS_IS_CTYPE(hex, _CTYPE_X)) {
                scanner->position = escapeCursor + 1;
            }
        }
    }

    return scanner;
}

int tops_scanner_next_significant_character(TopsScannerState *scanner, BOOL *didFail)
{
    NSUInteger cursor;
    NSUInteger sourceLength;

    *didFail = NO;
    sourceLength = scanner->length;
    cursor = scanner->position;
    if (cursor >= sourceLength) {
        *didFail = YES;
        return 0;
    }

    while (1) {
        NSUInteger nextCursor;
        unichar currentCharacter;

        nextCursor = cursor + 1;
        scanner->position = nextCursor;
        currentCharacter = scanner->characters[cursor];
        if (currentCharacter == 0) {
            *didFail = YES;
            return 0;
        }

        if (currentCharacter <= '.') {
            if (currentCharacter == '\n') {
                scanner->lineNumber++;
                goto advance_to_next_character;
            }
            if (currentCharacter == '#') {
                if (nextCursor >= sourceLength) {
                    return '#';
                }

                if (scanner->characters[nextCursor] == 'w') {
                    if (cursor + 8 >= sourceLength) {
                        return '#';
                    }
                    if (![[[NSString alloc] initWithCharactersNoCopy:scanner->characters + scanner->position - 1
                                                             length:8
                                                       freeWhenDone:NO] isEqualToString:@"#warning"]) {
                        return '#';
                    }
                } else if (scanner->characters[nextCursor] == 'e') {
                    if (cursor + 6 >= sourceLength) {
                        return '#';
                    }
                    if (![[[NSString alloc] initWithCharactersNoCopy:scanner->characters + scanner->position - 1
                                                             length:6
                                                       freeWhenDone:NO] isEqualToString:@"#error"]) {
                        return '#';
                    }
                } else {
                    if (cursor + 7 >= sourceLength ||
                        ![[[NSString alloc] initWithCharactersNoCopy:scanner->characters + scanner->position - 1
                                                             length:7
                                                       freeWhenDone:NO] isEqualToString:@"#pragma"]) {
                        return '#';
                    }
                }

                nextCursor = scanner->position + 1;
                scanner->position = nextCursor;
                while (nextCursor < sourceLength) {
                    cursor = nextCursor + 1;
                    scanner->position = cursor;
                    if (scanner->characters[nextCursor] == '\n') {
                        scanner->lineNumber++;
                        break;
                    }
                    nextCursor++;
                }
                cursor = nextCursor;
                goto advance_to_next_character;
            }
            goto inspect_character;
        }

        if (currentCharacter == '/') {
            unichar nextCharacter;

            nextCharacter = scanner->characters[nextCursor];
            if (nextCharacter == '*') {
                cursor += 2;
                scanner->position = cursor;
                if (cursor < sourceLength) {
                    while (1) {
                        NSUInteger followingCursor;
                        unichar commentCharacter;

                        followingCursor = cursor + 1;
                        commentCharacter = scanner->characters[cursor];
                        if (commentCharacter == '*') {
                            cursor += 2;
                            switch (scanner->characters[followingCursor]) {
                                case '\n':
                                    scanner->lineNumber++;
                                    break;
                                case '*':
                                    goto continue_scanning_block_comment;
                                case '/':
                                    scanner->position = cursor;
                                    goto advance_to_next_character;
                                default:
                                    break;
                            }
                        } else if (commentCharacter == '\n') {
                            scanner->lineNumber++;
                        }
continue_scanning_block_comment:
                        cursor = followingCursor;
                        if (cursor >= sourceLength) {
                            scanner->position = cursor;
                            *didFail = YES;
                            return 0;
                        }
                    }
                }
                *didFail = YES;
                return 0;
            }

            if (nextCharacter != '/') {
                return '/';
            }

            nextCursor = cursor + 2;
            scanner->position = nextCursor;
            while (nextCursor < sourceLength) {
                cursor = nextCursor + 1;
                scanner->position = cursor;
                if (scanner->characters[nextCursor] == '\n') {
                    scanner->lineNumber++;
                    break;
                }
                nextCursor++;
            }
            cursor = nextCursor;
            goto advance_to_next_character;
        }

        if (currentCharacter == 'd') {
            if (cursor + 8 < sourceLength &&
                [[[NSString alloc] initWithCharactersNoCopy:scanner->characters + scanner->position - 1
                                                    length:8
                                              freeWhenDone:NO] isEqualToString:@"defineps"]) {
                NSUInteger directiveCursor;

                sourceLength = scanner->length;
                directiveCursor = scanner->position + 7;
                scanner->position = directiveCursor;
                while (directiveCursor + 5 < sourceLength) {
                    unichar directiveCharacter;

                    directiveCharacter = scanner->characters[directiveCursor];
                    if (directiveCharacter == 'e') {
                        if ([[[NSString alloc] initWithCharactersNoCopy:scanner->characters + scanner->position
                                                                 length:5
                                                           freeWhenDone:NO] isEqualToString:@"endps"]) {
                            cursor = directiveCursor + 5;
                            scanner->position = cursor;
                            goto advance_to_next_character;
                        }
                        sourceLength = scanner->length;
                    } else if (directiveCharacter == '\n') {
                        scanner->lineNumber++;
                    }
                    scanner->position = ++directiveCursor;
                }
                *didFail = YES;
                return 0;
            }
        }

inspect_character:
        if (!TOPS_IS_CTYPE(currentCharacter, _CTYPE_S)) {
            return currentCharacter;
        }

advance_to_next_character:
        cursor = scanner->position;
        sourceLength = scanner->length;
        if (cursor >= sourceLength) {
            *didFail = YES;
            return 0;
        }
    }
}

BOOL tops_scanner_consume_meta_token(TopsScannerState *scanner, unichar firstCharacter)
{
    NSUInteger index;
    NSUInteger length;
    unichar character;

    if (firstCharacter != '<') {
        return NO;
    }

    index = scanner->position;
    character = scanner->characters[index];
    if (!TOPS_IS_CTYPE(character, _CTYPE_A | _CTYPE_D) && !TOPS_IS_IDENTIFIER_BODY_EXTRA(character)) {
        return NO;
    }

    length = scanner->length;
    index++;
    while (index < length) {
        character = scanner->characters[index];
        if (TOPS_IS_CTYPE(character, _CTYPE_A | _CTYPE_D)) {
            index++;
            continue;
        }

        if (!TOPS_IS_IDENTIFIER_BODY_EXTRA(character)) {
            break;
        }
        index++;
    }

    if (character == '(' && index < length) {
        NSUInteger classIndex;

        classIndex = index + 1;
        if (classIndex >= length) {
            return NO;
        }

        while (1) {
            character = scanner->characters[classIndex];
            if (!TOPS_IS_CTYPE(character, _CTYPE_A | _CTYPE_D) &&
                !TOPS_IS_METATOKEN_CLASS_EXTRA(character)) {
                break;
            }
            classIndex++;
            if (classIndex >= length) {
                break;
            }
        }

        if (character != ')' || classIndex >= length) {
            return NO;
        }
        index = classIndex + 1;
        character = ')';
    }

    if (index < length) {
        NSUInteger labelIndex;
        unichar labelCharacter;

        labelIndex = index + 1;
        character = scanner->characters[index];
        if (character == ' ') {
            if (labelIndex >= length) {
                return NO;
            }

            labelCharacter = scanner->characters[labelIndex];
            if (!TOPS_IS_CTYPE(labelCharacter, _CTYPE_A | _CTYPE_D) &&
                !TOPS_IS_IDENTIFIER_BODY_EXTRA(labelCharacter)) {
                return NO;
            }

            for (index += 2; index < scanner->length; index++) {
                labelCharacter = scanner->characters[index];
                if (TOPS_IS_CTYPE(labelCharacter, _CTYPE_A | _CTYPE_D)) {
                    continue;
                }
                if (!TOPS_IS_IDENTIFIER_BODY_EXTRA(labelCharacter)) {
                    break;
                }
            }

            if (labelCharacter != '>') {
                return NO;
            }
            scanner->position = index + 1;
            return YES;
        }

        index++;
    }

    if (character != '>') {
        return NO;
    }

    scanner->position = index;
    return YES;
}

BOOL tops_scanner_next_token(TopsScannerState *scanner, BOOL allowMetaTokens)
{
    BOOL didFail;
    unichar firstCharacter;
    NSUInteger index;
    NSUInteger length;

    didFail = NO;
    firstCharacter = (unichar)tops_scanner_next_significant_character(scanner, &didFail);
    if (didFail) {
        return NO;
    }

    scanner->tokenLine = scanner->lineNumber;
    scanner->tokenStart = scanner->position - 1;
    if (allowMetaTokens && tops_scanner_consume_meta_token(scanner, firstCharacter)) {
        scanner->tokenLength = scanner->position - scanner->tokenStart;
        return YES;
    }

    if (firstCharacter == '\\') {
        index = scanner->position;
        if (index < scanner->length && scanner->characters[index] == '<') {
            scanner->position = index + 1;
            scanner->tokenLength = scanner->position - scanner->tokenStart;
            return YES;
        }
    }

    if (firstCharacter == '"') {
        NSUInteger oldPosition;
        NSUInteger oldLine;

        oldPosition = scanner->position;
        oldLine = scanner->lineNumber;
        index = scanner->position;
        length = scanner->length;
        while (index < length) {
            unichar character;

            character = scanner->characters[index++];
            scanner->position = index;
            switch (character) {
                case '\n':
                    scanner->lineNumber++;
                    break;
                case '\\':
                    tops_scanner_consume_escape_sequence(scanner);
                    length = scanner->length;
                    index = scanner->position;
                    break;
                case '"':
                    scanner->tokenLength = index - scanner->tokenStart;
                    return YES;
                default:
                    break;
            }
        }
        scanner->position = oldPosition;
        scanner->lineNumber = oldLine;
        scanner->tokenLength = oldPosition - scanner->tokenStart;
        return YES;
    }

    if (TOPS_IS_CTYPE(firstCharacter, _CTYPE_A)) {
scan_identifier_token:
        index = scanner->position;
        if (index >= scanner->length) {
            scanner->tokenLength = index - scanner->tokenStart;
            return YES;
        }
        while (1) {
            unichar character;

            character = scanner->characters[index];
            if (TOPS_IS_CTYPE(character, _CTYPE_A | _CTYPE_D)) {
advance_identifier_token:
                scanner->position = scanner->position + 1;
                index = scanner->position;
                if (index >= scanner->length) {
                    scanner->tokenLength = index - scanner->tokenStart;
                    return YES;
                }
                continue;
            }
            if (TOPS_IS_IDENTIFIER_BODY_EXTRA(character)) {
                goto advance_identifier_token;
            }
            scanner->tokenLength = index - scanner->tokenStart;
            return YES;
        }
    }

    if (firstCharacter != '-' && firstCharacter != '.' && !TOPS_IS_DECIMAL_DIGIT(firstCharacter)) {
        index = scanner->position;
        if (firstCharacter == '\'') {
            if (index < scanner->length) {
                unichar character;

                character = scanner->characters[index];
                scanner->position = index + 1;
                if (character == '\\') {
                    tops_scanner_consume_escape_sequence(scanner);
                    index = scanner->position;
                } else {
                    index++;
                }
                while (index < scanner->length) {
                    character = scanner->characters[index];
                    scanner->position = index + 1;
                    index++;
                    if (character == '\'') {
                        scanner->tokenLength = scanner->position - scanner->tokenStart;
                        return YES;
                    }
                }
            }
            ns_errorf(@"***Unterminated character constant at line %d", (int)scanner->lineNumber);
            return NO;
        }

        if (index + 1 < scanner->length) {
            unichar nextCharacter;

            nextCharacter = scanner->characters[index];
            if (nextCharacter == '=') {
                if ((firstCharacter == '<' && scanner->characters[index - 1] == '<') ||
                    (firstCharacter == '>' && scanner->characters[index - 1] == '>')) {
                    scanner->position = index + 2;
                    scanner->tokenLength = 3;
                    return YES;
                }
                scanner->position = index + 1;
                scanner->tokenLength = 2;
                return YES;
            }
            if (nextCharacter == '.' && firstCharacter == '.' && scanner->characters[index - 1] == '.') {
                scanner->position = index + 2;
                scanner->tokenLength = 3;
                return YES;
            }
        }

        if (index < scanner->length) {
            unichar nextCharacter;

            nextCharacter = scanner->characters[index];
            if ((firstCharacter == '&' && nextCharacter == '&') ||
                (firstCharacter == '|' && nextCharacter == '|') ||
                (firstCharacter == '+' && nextCharacter == '+') ||
                (firstCharacter == '-' && nextCharacter == '-') ||
                (firstCharacter == '<' && nextCharacter == '<') ||
                (firstCharacter == '>' && nextCharacter == '>') ||
                (firstCharacter == '-' && nextCharacter == '>') ||
                (nextCharacter == '=' && TOPS_IS_ASSIGNMENT_OPERATOR_PREFIX(firstCharacter))) {
                scanner->position = index + 1;
                scanner->tokenLength = 2;
                return YES;
            }
        }

        if (TOPS_IS_CTYPE(firstCharacter, _CTYPE_P)) {
            scanner->tokenLength = 1;
            return YES;
        }

        ns_errorf(@"***Lexing error at line %d", (int)scanner->lineNumber);
        return NO;
    }

    length = scanner->length;
    index = scanner->position;
    if (firstCharacter == '0' && index < length - 2) {
        if ((scanner->characters[index] | 0x20) == 'x') {
            unichar hex = scanner->characters[index + 1];

            if (TOPS_IS_CTYPE(hex, _CTYPE_X)) {
                index += 2;
                while (index < length) {
                    unichar digit;

                    digit = scanner->characters[index];
                    if (!TOPS_IS_CTYPE(digit, _CTYPE_X)) {
                        break;
                    }
                    index++;
                    if (index == length) {
                        break;
                    }
                }
                scanner->position = index;
                firstCharacter = (index < length) ? scanner->characters[index] : 0;
                goto consume_numeric_suffix;
            }
        }
    }

    while (index < length) {
        unichar digit;

        digit = scanner->characters[index];
        if (digit != '.' && (unsigned int)(digit - '0') > 9) {
            break;
        }
        scanner->position = ++index;
        if (index == length) {
            break;
        }
    }

    firstCharacter = (index < length) ? scanner->characters[index] : 0;
    if ((firstCharacter == 'E' || firstCharacter == 'e') &&
        index < length - 1 &&
        (TOPS_IS_DECIMAL_DIGIT(scanner->characters[index + 1]) ||
         scanner->characters[index + 1] == '-' ||
         scanner->characters[index + 1] == '+')) {
        index += 2;
        while (index < length) {
            unichar digit;

            digit = scanner->characters[index];
            if (!TOPS_IS_DECIMAL_DIGIT(digit)) {
                break;
            }
            index++;
            if (index == length) {
                break;
            }
        }
        scanner->position = index;
        firstCharacter = (index < length) ? scanner->characters[index] : 0;
    }

consume_numeric_suffix:
    if (index < length && (firstCharacter == 'F' || firstCharacter == 'f')) {
        scanner->position = ++index;
        firstCharacter = (index < length) ? scanner->characters[index] : 0;
    }
    if (index < length && (firstCharacter == 'U' || firstCharacter == 'u')) {
        scanner->position = ++index;
        firstCharacter = (index < length) ? scanner->characters[index] : 0;
    }
    if (index < length && (firstCharacter == 'L' || firstCharacter == 'l')) {
        scanner->position = ++index;
        firstCharacter = (index < length) ? scanner->characters[index] : 0;
    }
    if (index < length && (firstCharacter == 'L' || firstCharacter == 'l')) {
        scanner->position = ++index;
        firstCharacter = (index < length) ? scanner->characters[index] : 0;
    }
    if (index < length && (firstCharacter == 'L' || firstCharacter == 'l')) {
        index++;
    }
    scanner->position = index;
    scanner->tokenLength = scanner->position - scanner->tokenStart;
    return YES;
}

static BOOL tops_advance_token_match_state(TopsTokenMatchState *state,
                                           NSUInteger tokenType,
                                           TokenizedInput *input,
                                           _Token *rawTokens,
                                           NSUInteger *currentIndex,
                                           NSRange *currentRange)
{
    NSString *sourceString;
    NSUInteger tokenCount;
    _Token *currentToken;
    NSUInteger tokenLocation;
    NSUInteger tokenLength;
    unichar firstCharacter;
    NSUInteger tokenIndex;

    sourceString = [input stringContents];
    tokenCount = [input numTokens];
    currentToken = &rawTokens[*currentIndex];
    tokenLocation = currentToken->range.location;
    tokenLength = currentToken->range.length;
    firstCharacter = [sourceString characterAtIndex:tokenLocation];
    tokenIndex = *currentIndex;

    if (tokenType != 8) {
        if (tokenType == 6 || tokenLength != 1) {
            return YES;
        }
    } else if (state->parenthesisDepth || state->bracketDepth || state->braceDepth) {
        if (tokenLength != 1) {
            NSString *tokenString;

            tokenString = [sourceString substringWithRange:NSMakeRange(tokenLocation, tokenLength)];
            return !TOPS_IS_DISALLOWED_TOP_LEVEL_EXPRESSION_TOKEN(tokenString);
        }
    } else {
        BOOL currentStartsWithIdentifier;
        BOOL currentLooksLikeWord;
        BOOL currentIsBrace;
        BOOL nextLooksLikeWord;
        BOOL previousEndsLikeWord;
        unichar previousCharacter;
        NSUInteger nextIndex;

        currentStartsWithIdentifier = TOPS_IS_CTYPE(firstCharacter, _CTYPE_A);
        currentIsBrace = (firstCharacter == '{');
        currentLooksLikeWord = currentIsBrace || currentStartsWithIdentifier || TOPS_IS_IDENTIFIER_START_EXTRA(firstCharacter);
        if (!currentLooksLikeWord) {
            goto handle_punctuation;
        }

        nextIndex = tokenIndex + 1;
        if (nextIndex < tokenCount) {
            unichar nextCharacter;
            BOOL nextStartsWithIdentifier;

            nextCharacter = [sourceString characterAtIndex:rawTokens[nextIndex].range.location];
            nextStartsWithIdentifier = TOPS_IS_CTYPE(nextCharacter, _CTYPE_A);
            nextLooksLikeWord = nextStartsWithIdentifier || TOPS_IS_IDENTIFIER_START_EXTRA(nextCharacter);
        } else {
            nextLooksLikeWord = NO;
        }

        if (tokenIndex) {
            BOOL previousIsIdentifierCharacter;

            previousCharacter = [sourceString characterAtIndex:(rawTokens[tokenIndex - 1].range.location + rawTokens[tokenIndex - 1].range.length - 1)];
            previousIsIdentifierCharacter = TOPS_IS_CTYPE(previousCharacter, _CTYPE_A | _CTYPE_D) ||
                                            TOPS_IS_IDENTIFIER_BODY_EXTRA(previousCharacter);
            previousEndsLikeWord = previousIsIdentifierCharacter;
            if (currentIsBrace && previousEndsLikeWord) {
                return NO;
            }
            if (nextLooksLikeWord) {
                if (previousCharacter != ']' &&
                    !previousEndsLikeWord &&
                    previousCharacter != ';' &&
                    previousCharacter != '{') {
                    goto handle_punctuation;
                }
            }
        } else {
            previousEndsLikeWord = NO;
            previousCharacter = 0;
        }

        if (previousEndsLikeWord && tokenIndex) {
            NSString *previousToken;

            previousToken = [sourceString substringWithRange:rawTokens[tokenIndex - 1].range];
            if (![previousToken isEqualToString:@"return"]) {
                return NO;
            }
        }

        if (nextLooksLikeWord || previousEndsLikeWord) {
            return NO;
        }

        if (previousCharacter > 92) {
            if (previousCharacter != ']' && previousCharacter != '}') {
                goto check_expression_word;
            }
        } else if (previousCharacter != '"') {
            if (previousCharacter == ')' && (nextIndex < tokenCount)) {
                unichar nextCharacter;

                nextCharacter = [sourceString characterAtIndex:rawTokens[nextIndex].range.location];
                if ((nextCharacter == ']' || nextCharacter == ':') &&
                    !tops_is_simple_token_character(firstCharacter)) {
                    return NO;
                }
            }
            goto check_expression_word;
        }

        if (nextIndex < tokenCount) {
            unichar nextCharacter;

            nextCharacter = [sourceString characterAtIndex:rawTokens[nextIndex].range.location];
            if (nextCharacter == ':' || nextCharacter == ']') {
                return NO;
            }
        }

check_expression_word:
        if (tokenLength != 1) {
            NSString *tokenString;

            tokenString = [sourceString substringWithRange:NSMakeRange(tokenLocation, tokenLength)];
            return !TOPS_IS_DISALLOWED_TOP_LEVEL_EXPRESSION_TOKEN(tokenString);
        }
    }

handle_punctuation:
    if ((int)firstCharacter <= '>') {
        if ((int)firstCharacter > '+') {
            if (firstCharacter == ',') {
                if (tokenType != 8) {
                    return YES;
                }
                if (state->parenthesisDepth || state->bracketDepth || state->braceDepth) {
                    return YES;
                }
                currentRange->length = 0;
                return NO;
            }
            if (firstCharacter == ':') {
                return tokenType != 8 || state->parenthesisDepth || state->bracketDepth || state->braceDepth;
            }
            if (firstCharacter != ';' || tokenType != 8) {
                return YES;
            }
            if (state->parenthesisDepth || state->bracketDepth || state->braceDepth) {
                currentRange->length = 0;
                return NO;
            }
            return NO;
        }

        if (firstCharacter == '(') {
            if (tokenType == 8 && !state->parenthesisDepth && !state->bracketDepth && !state->braceDepth && tokenIndex) {
                NSString *previousToken;

                previousToken = [sourceString substringWithRange:rawTokens[tokenIndex - 1].range];
                if (TOPS_IS_CONDITIONAL_STATEMENT_KEYWORD(previousToken)) {
                    return NO;
                }
            }
            state->parenthesisDepth++;
            return YES;
        }

        if (firstCharacter == ')') {
            if (!state->parenthesisDepth) {
                return NO;
            }
            state->parenthesisDepth--;
            return YES;
        }
        return YES;
    }

    if ((int)firstCharacter <= '\\') {
        if (firstCharacter == '?') {
            if (tokenType == 8) {
                NSUInteger secondIndex;
                NSRange secondRange;
                NSRange thirdRange;

                secondIndex = tokenIndex + 1;
                if (state->usesWhereBindings) {
                    secondRange = [input tokenRangeFromTokenIndex:secondIndex
                                           untilTokenFromWhereDict:state->whereBindings
                                                  firstWhereSymbol:state->primaryWhereSymbol
                                                          withType:8];
                } else {
                    secondRange = [input tokenRangeFromTokenIndex:secondIndex
                                                       untilTokens:state->boundaryTokens
                                                          withType:8];
                }
                if (!secondRange.length) {
                    return NO;
                }
                if (![[sourceString substringWithRange:rawTokens[tokenIndex + secondRange.length + 1].range] isEqualToString:@":"]) {
                    return NO;
                }
                secondIndex = tokenIndex + secondRange.length + 2;
                if (state->usesWhereBindings) {
                    thirdRange = [input tokenRangeFromTokenIndex:secondIndex
                                          untilTokenFromWhereDict:state->whereBindings
                                                 firstWhereSymbol:state->primaryWhereSymbol
                                                         withType:8];
                } else {
                    thirdRange = [input tokenRangeFromTokenIndex:secondIndex
                                                       untilTokens:state->boundaryTokens
                                                          withType:8];
                }
                if (!thirdRange.length) {
                    return NO;
                }
                currentRange->length += secondRange.length + thirdRange.length + 1;
                *currentIndex += secondRange.length + thirdRange.length + 1;
            }
            return YES;
        }

        if (firstCharacter == '[') {
            state->bracketDepth++;
            return YES;
        }
    } else {
        if (firstCharacter == ']') {
            if (!state->bracketDepth) {
                return NO;
            }
            state->bracketDepth--;
            return YES;
        }
        if (firstCharacter == '{') {
            state->braceDepth++;
            return YES;
        }
        if (firstCharacter == '}') {
            if (!state->braceDepth) {
                return NO;
            }
            state->braceDepth--;
            return YES;
        }
        return YES;
    }

    return YES;
}

@implementation TokenizedInput

- (void)dealloc
{
    NSUInteger index;

    for (index = 0; index < count; index++) {
        if (tokens[index].cachedSubstring) {
            CFRelease(tokens[index].cachedSubstring);
        }
        if (tokens[index].cachedClassName) {
            CFRelease(tokens[index].cachedClassName);
        }
    }
    free(tokens);
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[[self class] allocWithZone:zone] initWithString:string];
}

- (id)copy
{
    return [self copyWithZone:nil];
}

- (instancetype)initWithString:(NSString *)aString
{
    TopsScannerState *scanner;

    self = [super init];
    if (!self) {
        return nil;
    }

    scanner = tops_scanner_create(aString);
    string = [aString copy];
    if (tops_scanner_next_token(scanner, NO)) {
        do {
            if (count + 1 > max) {
                max = (2 * max) | 1;
                tokens = realloc(tokens, sizeof(_Token) * max);
            }
            tokens[count].lineNumber = (unsigned int)scanner->tokenLine;
            tokens[count].cachedSubstring = NULL;
            tokens[count].type = 2;
            tokens[count].modifiers = 0;
            tokens[count].cachedClassName = NULL;
            tokens[count].range = NSMakeRange(scanner->tokenStart, scanner->tokenLength);
            count++;
        } while (tops_scanner_next_token(scanner, NO));
    }

    free(scanner->characters);
    free(scanner);
    return self;
}

- (TokenizedInput *)tokensByReplacingRange:(NSRange)range withTokens:(TokenizedInput *)replacement
{
    NSMutableString *updatedString;
    NSRange characterRange;

    updatedString = [[NSMutableString alloc] initWithString:string];
    characterRange = [self charRangeFromTokenRange:range includeSurroundingWhitepsace:NO];
    [updatedString replaceCharactersInRange:characterRange withString:[replacement stringContents]];
    return [[[self class] alloc] initWithString:updatedString];
}

- (TokenizedInput *)subtokensFromIndex:(NSUInteger)index
{
    TokenizedInput *emptyTokens;

    emptyTokens = [[TokenizedInput alloc] initWithString:@""];
    return [self tokensByReplacingRange:NSMakeRange(0, index) withTokens:emptyTokens];
}

- (NSString *)stringContents
{
    return string;
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

- (NSString *)substringFromTokenRange:(NSRange)tokenRange includeSurroundingWhitepsace:(BOOL)includeSurroundingWhitespace
{
    NSRange characterRange;

    if (!tokenRange.length) {
        return @"";
    }
    characterRange = [self charRangeFromTokenRange:tokenRange includeSurroundingWhitepsace:includeSurroundingWhitespace];
    return [string substringWithRange:characterRange];
}

- (NSString *)substringOfWhitespaceBeforeTokenIndex:(NSUInteger)index
{
    NSUInteger location;
    NSUInteger previousEnd;

    location = tokens[index].range.location;
    if (!index) {
        return [string substringToIndex:location];
    }
    previousEnd = tokens[index - 1].range.location + tokens[index - 1].range.length;
    return [string substringWithRange:NSMakeRange(previousEnd, location - previousEnd)];
}

- (NSString *)lineIncluding:(NSUInteger)index
{
    NSUInteger location;
    NSUInteger start;
    NSUInteger lengthValue;

    location = tokens[index].range.location;
    if (location) {
        lengthValue = 0;
        start = location;
        while (1) {
            NSUInteger previous;

            previous = start - 1;
            if ([string characterAtIndex:start - 1] == '\n') {
                location = lengthValue;
                break;
            }
            lengthValue++;
            start--;
            if (!previous) {
                break;
            }
        }
    } else {
        start = 0;
    }

    while (start + location < [string length]) {
        if ([string characterAtIndex:start + location] == '\n') {
            break;
        }
        location++;
    }
    return [string substringWithRange:NSMakeRange(start, location)];
}

- (NSUInteger)tokenTypeAtIndex:(NSUInteger)index
{
    return tokens[index].type;
}

- (NSUInteger)tokenModifiersAtIndex:(NSUInteger)index
{
    return tokens[index].modifiers;
}

- (NSString *)description
{
    return string;
}

- (unichar)char:(NSUInteger)characterOffset atIndex:(NSUInteger)tokenIndex
{
    return [string characterAtIndex:tokens[tokenIndex].range.location + characterOffset];
}

- (NSRange)subrangeAtIndex:(NSUInteger)index
{
    return tokens[index].range;
}

- (NSUInteger)lineAtIndex:(NSUInteger)index
{
    return tokens[index].lineNumber;
}

- (BOOL)isSimpleTokenAtIndex:(NSUInteger)index
{
    return tokens[index].type == 2;
}

- (NSUInteger)numTokens
{
    return count;
}

- (NSRange)charRangeFromTokenRange:(NSRange)tokenRange includeSurroundingWhitepsace:(BOOL)includeSurroundingWhitespace
{
    NSUInteger location;
    NSUInteger endLocation;

    if (tokenRange.length) {
        if (includeSurroundingWhitespace && tokenRange.location) {
            location = tokens[tokenRange.location - 1].range.location + tokens[tokenRange.location - 1].range.length;
        } else {
            location = tokens[tokenRange.location].range.location;
        }
        if (includeSurroundingWhitespace && NSMaxRange(tokenRange) < [self numTokens]) {
            endLocation = tokens[NSMaxRange(tokenRange)].range.location;
        } else {
            endLocation = tokens[NSMaxRange(tokenRange) - 1].range.location + tokens[NSMaxRange(tokenRange) - 1].range.length;
        }
        return NSMakeRange(location, endLocation - location);
    }
    return NSMakeRange(0, 0);
}

- (NSRange)tokenRangeFromTokenIndex:(NSUInteger)index
            untilTokenFromWhereDict:(NSDictionary *)aWhereDict
                   firstWhereSymbol:(NSString *)firstWhereSymbol
                           withType:(NSUInteger)tokenType
{
    TopsTokenMatchState state;
    NSUInteger currentIndex;
    NSRange matchRange;
    NSUInteger matchedLength;

    matchRange = NSMakeRange(index, 0);
    currentIndex = index;
    matchedLength = 0;
    memset(&state, 0, sizeof(state));
    state.boundaryTokens = nil;
    state.whereBindings = aWhereDict;
    state.primaryWhereSymbol = firstWhereSymbol;
    state.usesWhereBindings = YES;

    if (tokenType == 8 &&
        [self numTokens] > index &&
        ![self isValidCExpressionStartAtIndex:index]) {
        return NSMakeRange(0, 0);
    }

    if ([self numTokens] <= index) {
        return NSMakeRange(matchRange.location, 0);
    }

    while (1) {
        id possibilities;
        NSUInteger possibilityIndex;
        BOOL exactMatch;
        BOOL expressionAtBoundary;

        possibilities = [aWhereDict objectForKey:[self substringAtIndex:currentIndex]];
        if (possibilities && [possibilities count]) {
            BOOL accepted;

            possibilityIndex = 0;
            expressionAtBoundary = (tokenType == 8 && matchedLength == 0);
            accepted = NO;
            while (possibilityIndex < [possibilities count]) {
                NSArray *simpleTokens;
                NSUInteger tokenIndex;

                simpleTokens = [[[TokenizedTopsInput alloc] initWithString:[[possibilities objectAtIndex:possibilityIndex] objectForKey:firstWhereSymbol]]
                                arrayOfSimpleTokensStartingAt:0];
                exactMatch = YES;
                for (tokenIndex = 0; tokenIndex < [simpleTokens count]; tokenIndex++) {
                    if (currentIndex + tokenIndex >= count ||
                        ![[self substringAtIndex:currentIndex + tokenIndex] isEqualToString:[simpleTokens objectAtIndex:tokenIndex]]) {
                        exactMatch = NO;
                        break;
                    }
                }
                if (exactMatch && !expressionAtBoundary) {
                    accepted = YES;
                    break;
                }
                possibilityIndex++;
                if (possibilityIndex == [possibilities count]) {
                    break;
                }
            }

            if (accepted) {
                if (tokenType == 8 &&
                    matchedLength &&
                    ![self isValidCExpressionEndAtIndex:(matchedLength + matchRange.location - 1)]) {
                    matchedLength = 0;
                    matchRange.length = 0;
                }
                return NSMakeRange(matchRange.location, matchedLength);
            }
        }

        if (!tops_advance_token_match_state(&state, tokenType, self, tokens, &currentIndex, &matchRange)) {
            if (state.parenthesisDepth || state.bracketDepth || state.braceDepth) {
                return NSMakeRange(0, 0);
            }
            if (tokenType == 8 && matchRange.length) {
                if (![self isValidCExpressionEndAtIndex:(matchRange.length + matchRange.location - 1)]) {
                    matchedLength = 0;
                } else {
                    matchedLength = matchRange.length;
                }
                return NSMakeRange(matchRange.location, matchedLength);
            }
            return NSMakeRange(matchRange.location, matchRange.length);
        }

        currentIndex++;
        matchedLength = ++matchRange.length;
        if (currentIndex >= [self numTokens]) {
            if (tokenType == 8 && matchedLength) {
                if (![self isValidCExpressionEndAtIndex:(matchRange.location + matchedLength - 1)]) {
                    matchedLength = 0;
                }
                return NSMakeRange(matchRange.location, matchedLength);
            }
            return NSMakeRange(matchRange.location, 0);
        }
    }
}

- (NSRange)tokenRangeFromTokenIndex:(NSUInteger)index
                        untilTokens:(NSArray *)untilTokens
                           withType:(NSUInteger)tokenType
{
    TopsTokenMatchState state;
    NSUInteger currentIndex;
    NSRange matchRange;
    NSUInteger matchedLength;

    matchRange = NSMakeRange(index, 0);
    currentIndex = index;
    matchedLength = 0;
    memset(&state, 0, sizeof(state));
    state.boundaryTokens = untilTokens;

    if (tokenType == 8 &&
        [self numTokens] > index &&
        ![self isValidCExpressionStartAtIndex:index]) {
        return NSMakeRange(0, 0);
    }

    if ([self numTokens] <= index) {
        return NSMakeRange(matchRange.location, 0);
    }

    while (1) {
        BOOL exactMatch;

        exactMatch = NO;
        if (untilTokens) {
            NSUInteger tokenIndex;

            exactMatch = YES;
            for (tokenIndex = 0; tokenIndex < [untilTokens count]; tokenIndex++) {
                if (currentIndex + tokenIndex >= count ||
                    ![[self substringAtIndex:currentIndex + tokenIndex] isEqualToString:[untilTokens objectAtIndex:tokenIndex]]) {
                    exactMatch = NO;
                    break;
                }
            }
        }

        if (tokenType == 8 && matchedLength && exactMatch) {
            if (![self isValidCExpressionEndAtIndex:(matchedLength + matchRange.location - 1)]) {
                matchedLength = 0;
            }
            return NSMakeRange(matchRange.location, matchedLength);
        }

        if (!tops_advance_token_match_state(&state, tokenType, self, tokens, &currentIndex, &matchRange)) {
            if (state.parenthesisDepth || state.bracketDepth || state.braceDepth) {
                return NSMakeRange(0, 0);
            }
            if (tokenType == 8 && matchRange.length) {
                if (![self isValidCExpressionEndAtIndex:(matchRange.location + matchRange.length - 1)]) {
                    return NSMakeRange(0, 0);
                }
            }
            return NSMakeRange(matchRange.location, matchRange.length);
        }

        matchedLength = ++matchRange.length;
        currentIndex++;
        if (currentIndex >= [self numTokens]) {
            if (tokenType == 8 && matchedLength) {
                if (![self isValidCExpressionEndAtIndex:(matchedLength + matchRange.location - 1)]) {
                    matchedLength = 0;
                }
                return NSMakeRange(matchRange.location, matchedLength);
            }
            return NSMakeRange(matchRange.location, matchedLength);
        }

        if (!untilTokens) {
            continue;
        }
    }
}

- (NSArray *)arrayOfSimpleTokensStartingAt:(NSUInteger)index
{
    NSMutableArray *simpleTokens;
    NSUInteger limit;

    simpleTokens = [NSMutableArray array];
    limit = [self numTokens];
    if (limit > index) {
        while ([self tokenTypeAtIndex:index] == 2) {
            [simpleTokens addObject:[self substringAtIndex:index++]];
            if (index == limit) {
                break;
            }
        }
    }
    return simpleTokens;
}

- (BOOL)isValidCExpressionStartAtIndex:(NSUInteger)index
{
    static NSCharacterSet *characterSet = nil;
    unichar character;
    NSString *tokenString;

    if (!characterSet) {
        characterSet = [NSCharacterSet characterSetWithCharactersInString:@"[!~(@*_[{$'&\""];
    }

    character = [string characterAtIndex:tokens[index].range.location];
    if (TOPS_IS_CTYPE(character, _CTYPE_A)) {
        return YES;
    }
    if (TOPS_IS_IDENTIFIER_START_EXTRA(character)) {
        return YES;
    }
    if (character == '-' || character == '.' || TOPS_IS_DECIMAL_DIGIT(character)) {
        return YES;
    }
    if ([characterSet characterIsMember:character]) {
        return YES;
    }
    tokenString = [self substringAtIndex:index];
    if ([tokenString hasPrefix:@"++"]) {
        return YES;
    }
    return [tokenString hasPrefix:@"--"];
}

- (BOOL)isValidCExpressionEndAtIndex:(NSUInteger)index
{
    static NSCharacterSet *characterSet = nil;
    unichar character;
    NSString *tokenString;

    if (!characterSet) {
        characterSet = [NSCharacterSet characterSetWithCharactersInString:@"]})\"'"];
    }

    character = [string characterAtIndex:tokens[index].range.location + tokens[index].range.length - 1];
    if (TOPS_IS_CTYPE(character, _CTYPE_A | _CTYPE_D)) {
        return YES;
    }

    if (TOPS_IS_IDENTIFIER_BODY_EXTRA(character)) {
        return YES;
    }
    if (character == '.' || TOPS_IS_DECIMAL_DIGIT(character)) {
        return YES;
    }
    if ([characterSet characterIsMember:character]) {
        return YES;
    }
    tokenString = [self substringAtIndex:index];
    if ([tokenString hasSuffix:@"++"]) {
        return YES;
    }
    return [tokenString hasSuffix:@"--"];
}

@end
