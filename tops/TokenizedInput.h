#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct _Token {
    CFTypeRef cachedSubstring;
    NSRange range;
    unsigned int type;
    unsigned int lineNumber;
    uintptr_t modifiers;
    CFTypeRef cachedClassName;
} _Token;

typedef struct TopsScannerState {
    unichar *characters;
    NSUInteger length;
    NSUInteger position;
    NSUInteger lineNumber;
    NSUInteger tokenStart;
    NSUInteger tokenLength;
    NSUInteger tokenLine;
} TopsScannerState;

BOOL tops_is_simple_token_character(unichar character);
TopsScannerState * _Nullable tops_scanner_create(NSString *source);
TopsScannerState *tops_scanner_consume_escape_sequence(TopsScannerState *scanner);
int tops_scanner_next_significant_character(TopsScannerState *scanner, BOOL *didFail);
BOOL tops_scanner_consume_meta_token(TopsScannerState *scanner, unichar firstCharacter);
BOOL tops_scanner_next_token(TopsScannerState *scanner, BOOL allowMetaTokens);

@interface TokenizedInput : NSObject <NSCopying> {
@protected
    NSString *string;
    _Token *tokens;
    NSUInteger count;
    NSUInteger max;
}

- (id)copy;
- (instancetype)initWithString:(NSString *)string;
- (TokenizedInput *)tokensByReplacingRange:(NSRange)range withTokens:(TokenizedInput *)tokens;
- (TokenizedInput *)subtokensFromIndex:(NSUInteger)index;
- (NSString *)stringContents;
- (nullable NSString *)substringAtIndex:(NSUInteger)index;
- (nullable NSString *)substringFromTokenRange:(NSRange)tokenRange includeSurroundingWhitepsace:(BOOL)includeSurroundingWhitespace;
- (nullable NSString *)substringOfWhitespaceBeforeTokenIndex:(NSUInteger)index;
- (nullable NSString *)lineIncluding:(NSUInteger)index;
- (NSUInteger)tokenTypeAtIndex:(NSUInteger)index;
- (NSUInteger)tokenModifiersAtIndex:(NSUInteger)index;
- (NSString *)description;
- (unichar)char:(NSUInteger)characterOffset atIndex:(NSUInteger)tokenIndex;
- (NSRange)subrangeAtIndex:(NSUInteger)index;
- (NSUInteger)lineAtIndex:(NSUInteger)index;
- (BOOL)isSimpleTokenAtIndex:(NSUInteger)index;
- (NSUInteger)numTokens;
- (NSRange)charRangeFromTokenRange:(NSRange)tokenRange includeSurroundingWhitepsace:(BOOL)includeSurroundingWhitespace;
- (NSRange)tokenRangeFromTokenIndex:(NSUInteger)index
            untilTokenFromWhereDict:(NSDictionary *)whereDict
                   firstWhereSymbol:(NSString *)firstWhereSymbol
                           withType:(NSUInteger)tokenType;
- (NSRange)tokenRangeFromTokenIndex:(NSUInteger)index
                        untilTokens:(nullable NSArray *)tokens
                           withType:(NSUInteger)tokenType;
- (NSArray *)arrayOfSimpleTokensStartingAt:(NSUInteger)index;
- (BOOL)isValidCExpressionStartAtIndex:(NSUInteger)index;
- (BOOL)isValidCExpressionEndAtIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
