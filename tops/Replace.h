#import <Foundation/Foundation.h>

#import "Find.h"

NS_ASSUME_NONNULL_BEGIN

@interface Replace : Find {
@protected
    TokenizedTopsInput *replacementTok;
    NSMutableDictionary *withinDict;
    NSDictionary *errorDict;
    NSUInteger positionToReapply;
}

- (nullable instancetype)initWithPatternString:(NSString *)patternString
                             replacementString:(NSString *)replacementString
                                     whereDict:(nullable NSDictionary *)whereDict
                                     errorDict:(nullable NSDictionary *)errorDict
                                    withinDict:(nullable NSDictionary *)withinDict;
- (nullable instancetype)initWithPatternStringNonrecursive:(NSString *)patternString
                                         replacementString:(NSString *)replacementString
                                                 whereDict:(nullable NSDictionary *)whereDict
                                                 errorDict:(nullable NSDictionary *)errorDict
                                                withinDict:(nullable NSDictionary *)withinDict;
- (NSUInteger)positionToReapplyForRecursiveTokAux:(TokenizedInput *)tokens;
- (NSUInteger)positionToReapplyForRecursiveTok;
- (TokenizedInput *)applyToTok:(TokenizedInput *)tokens
                        silent:(BOOL)silent
                      numFound:(NSUInteger *)numFound
                    numChanges:(NSUInteger *)numChanges;
- (id)ruleByReplacingMetaTokensWithBindings:(NSDictionary *)bindings;
- (void)applyAllWithinRulesWithBindings:(NSMutableDictionary *)bindings
                                 silent:(BOOL)silent
                               numFound:(NSUInteger *)numFound
                             numChanges:(NSUInteger *)numChanges;
+ (TokenizedInput *)tokensByApplyingWithinRules:(NSArray *)withinRules
                                         tokens:(TokenizedInput *)tokens
                                       bindings:(NSDictionary *)bindings
                                         silent:(BOOL)silent
                                       numFound:(NSUInteger *)numFound
                                     numChanges:(NSUInteger *)numChanges;
- (nullable NSDictionary *)withinDictForBindings:(NSDictionary *)bindings;
- (TokenizedInput *)tokensByInsertingErrorOrWarning:(TokenizedInput *)tokens
                                           bindings:(NSDictionary *)bindings
                                         matchRange:(NSRange)matchRange
                                           numFound:(NSUInteger *)numFound
                                         numChanges:(NSUInteger *)numChanges;

@end

NS_ASSUME_NONNULL_END
