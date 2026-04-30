#import <Foundation/Foundation.h>

#import "TokenizedInput.h"

NS_ASSUME_NONNULL_BEGIN

@interface TokenizedTopsInput : TokenizedInput {
@protected
    id delegate;
}

- (instancetype)initWithString:(NSString *)string;
- (instancetype)initWithString:(NSString *)string delegate:(nullable id)delegate;
- (nullable id)delegate;
- (TokenizedTopsInput *)tokensByReplacingMetaTokens;
- (nullable NSString *)completeSubstringAtIndex:(NSUInteger)index;
- (nullable NSString *)classOfClassTokenAtIndex:(NSUInteger)index;
- (nullable NSString *)substringAtIndex:(NSUInteger)index;
- (nullable NSString *)substringOfSimpleTokensStartingAt:(NSUInteger)index;
- (void)setDefaultTokenTypes;
- (void)setTokenType:(NSUInteger)tokenType atIndex:(NSUInteger)index;
- (BOOL)containsDuplicatedMetaTokens;
- (TokenizedTopsInput *)tokensByReplacingRange:(NSRange)range withTokens:(TokenizedInput *)tokens;
- (TokenizedTopsInput *)tokensByReplacingToken:(NSString *)token withString:(NSString *)string;
- (TokenizedTopsInput *)tokensByReplacingMetaTokensWithBindings:(NSDictionary *)bindings;
- (NSArray *)arrayOfSimpleTokensStartingAt:(NSUInteger)index;
- (BOOL)isValidCExpressionStartAtIndex:(NSUInteger)index;
- (BOOL)isValidCExpressionEndAtIndex:(NSUInteger)index;

+ (nullable NSString *)identifierForMetaTokenString:(NSString *)string;
+ (NSString *)metaTokenStringWithType:(NSUInteger)type label:(NSString *)label;
+ (NSRange)rangeOfMetaTokenInString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
