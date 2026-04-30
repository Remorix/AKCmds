#import <Foundation/Foundation.h>

#import "TokenizedTopsInput.h"

NS_ASSUME_NONNULL_BEGIN

@interface Find : NSObject {
@protected
    TokenizedTopsInput *patternTok;
    NSDictionary *whereDict;
}

- (nullable instancetype)initWithPatternString:(NSString *)patternString whereDict:(nullable NSDictionary *)whereDict;
- (id)ruleByReplacingMetaTokensWithBindings:(NSDictionary *)bindings;
- (NSRange)tokenRangeOfMatch:(TokenizedInput *)inputTok
                    position:(NSUInteger)position
                    bindings:(nullable NSMutableDictionary *)bindings
                    anchored:(BOOL)anchored;
- (TokenizedInput *)applyToTok:(TokenizedInput *)tokens
                        silent:(BOOL)silent
                      numFound:(NSUInteger *)numFound
                    numChanges:(NSUInteger *)numChanges;
- (void)setTokenTypesForTokens:(TokenizedTopsInput *)tokens;
- (BOOL)interpretMetatokens;
- (NSRange)tokenRangeOfMatchOfPatternTok:(TokenizedInput *)patternTok
                                inputTok:(TokenizedInput *)inputTok
                                position:(NSUInteger)position
                                bindings:(NSMutableDictionary *)bindings
                                anchored:(BOOL)anchored;
- (nullable NSDictionary *)whereDictForBindings:(NSDictionary *)bindings;

@end

NS_ASSUME_NONNULL_END
