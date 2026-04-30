#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct _Flags {
    BOOL dont;
    BOOL verbose;
    BOOL semiVerbose;
    BOOL noContext;
    BOOL noFileInfo;
    BOOL help;
} _Flags;

typedef NS_OPTIONS(uint64_t, TopsParserFlags) {
    TopsParserFlagDont = 1ULL << 0,
    TopsParserFlagVerbose = 1ULL << 8,
    TopsParserFlagSemiVerbose = 1ULL << 16,
    TopsParserFlagNoContext = 1ULL << 24,
    TopsParserFlagNoFileInfo = 1ULL << 32,
    TopsParserFlagHelp = 1ULL << 40,
};

@interface TopsParser : NSObject {
@private
    NSMutableString *string;
    NSMutableArray *parsedSourceFilenames;
    NSMutableArray *parsedRules;
    NSString *parsedClassFilename;
    _Flags parsedFlags;
    NSUInteger position;
    BOOL containsScriptFileInput;
}

- (instancetype)init;
- (nullable instancetype)initWithCommandLineArguments:(NSArray *)arguments;

- (void)error:(NSString *)message, ...;
- (void)skipWhitespaceAndComments;
- (BOOL)parseNextQuotedArgumentIntoString:(NSString * _Nullable * _Nonnull)string optional:(BOOL)optional;
- (BOOL)parseKeyword:(NSString *)keyword optional:(BOOL)optional;
- (int)nextRuleType;
- (NSDictionary *)generateMetatokenCacheFromMetarules;
- (NSDictionary *)parseRuleClausesWithMask:(NSUInteger)mask patternString:(NSString *)patternString;
- (void)prepareCachedSelectorsForSelectorRule:(NSMutableArray *)rule
                                permanentCopy:(NSArray *)permanentCopy
                                        cache:(NSDictionary *)cache;
- (void)prepareCachedSelectorsForDeclarationRule:(NSMutableArray *)rule
                                   permanentCopy:(NSArray *)permanentCopy
                                           cache:(NSDictionary *)cache
                                  metatokenCache:(NSDictionary *)metatokenCache
                                     replacement:(BOOL)replacement;
- (void)prepareCachedSelectorsForCallRule:(NSMutableArray *)rule
                            permanentCopy:(NSArray *)permanentCopy
                                    cache:(NSDictionary *)cache
                           metatokenCache:(NSDictionary *)metatokenCache
                              replacement:(BOOL)replacement;
- (void)generateSelectorRule:(NSMutableArray *)rules
                      search:(NSMutableArray *)search
                     replace:(NSMutableArray *)replace
                  permSearch:(NSArray *)permSearch
                 permReplace:(NSArray *)permReplace
                       cache:(NSDictionary *)cache
                        info:(void *)info
                     clauses:(NSDictionary *)clauses;
- (void)generateDeclarationRule:(NSMutableArray *)rules
                         search:(NSMutableArray *)search
                        replace:(NSMutableArray *)replace
                     permSearch:(NSArray *)permSearch
                    permReplace:(NSArray *)permReplace
                          cache:(NSDictionary *)cache
                           info:(void *)info
                        clauses:(NSDictionary *)clauses
                 metatokenCache:(NSDictionary *)metatokenCache;
- (void)generateCallRule:(NSMutableArray *)rules
                  search:(NSMutableArray *)search
                 replace:(NSMutableArray *)replace
              permSearch:(NSArray *)permSearch
             permReplace:(NSArray *)permReplace
                   cache:(NSDictionary *)cache
                    info:(void *)info
                 clauses:(NSDictionary *)clauses
          metatokenCache:(NSDictionary *)metatokenCache;
- (void)parseReplacemethodRuleIntoArray:(NSMutableArray *)rules;
- (BOOL)parse;
- (id)parseFindRule;
- (id)parseReplaceRule;
- (void)parseWhereClausesIntoDictionary:(NSMutableDictionary *)whereDict patternString:(NSString *)patternString;
- (void)parseWithinClauseIntoDictionary:(NSMutableDictionary *)withinDict;
- (void)cacheSelectorComponentsFromArray:(NSArray *)parts inDictionary:(NSMutableDictionary *)dictionary array:(NSMutableArray *)selectors;
- (void)cacheSelectorsInDictIntoArray:(NSMutableArray *)dictionary
                         replaceArray:(NSMutableArray *)replaceArray
                            whereDict:(NSDictionary *)whereDict
                                 info:(void *)info;

- (NSMutableArray *)parsedSourceFilenames;
- (nullable NSString *)parsedClassFilename;
- (TopsParserFlags)parsedFlags;
- (NSMutableArray *)parsedRules;

@end

NS_ASSUME_NONNULL_END
