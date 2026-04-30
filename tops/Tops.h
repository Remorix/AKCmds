#import <Foundation/Foundation.h>

@class ClassHierarchy;

@interface Tops : NSObject {
@private
    BOOL performSubstitutions;
    BOOL showFileInfo;
    BOOL showSubstitutionContext;
    BOOL showSubstitutions;
    BOOL showProgress;

    NSMutableArray *sourceFiles;
    NSString *currentSourceFilename;
    NSMutableArray *rules;
    NSUInteger currentRuleIndex;
    ClassHierarchy *classHierarchy;
    NSString *classHierarchySourceFilename;
}

@property (nonatomic, readonly) BOOL performSubstitutions;
@property (nonatomic, readonly) BOOL showFileInfo;
@property (nonatomic, readonly) BOOL showSubstitutionContext;
@property (nonatomic, readonly) BOOL showSubstitutions;
@property (nonatomic, readonly) BOOL showProgress;

@property (nonatomic, readonly) NSString *currentSourceFilename;
@property (nonatomic, readonly) ClassHierarchy *classHierarchy;

- (instancetype)init;
- (instancetype)initWithCommandLine;

- (void)printHelp;
- (void)printHelpExtension;
- (BOOL)parseCommandLineWithHelpRequest:(BOOL *)withHelpRequest;

- (NSData *)dataByApplyingRulesToData:(NSData *)data numFound:(NSUInteger *)numFound numChanges:(NSUInteger *)numChanges;

- (void)applyRules;
- (void)applyRulesToAllSourceFiles;
- (void)applyRulesToSourceFileWithPath:(NSString *)path;
- (void)applyRulesToStandardInput;

- (void)updateStatusBar;

@end

extern Tops *gCurrentTops;
