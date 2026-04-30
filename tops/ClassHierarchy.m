#import "ClassHierarchy.h"

@interface ClassHierarchy () {
    NSMutableDictionary *classHierarchy;
}
@end

@implementation ClassHierarchy

- (instancetype)init {
    self = [super init];
    self->classHierarchy = [NSMutableDictionary dictionary];
    return self;
}

- (instancetype)initWithFile:(NSString *)path {
    NSData *data = [[NSData alloc] initWithContentsOfFile:path];
    static NSMutableCharacterSet *charset = nil;

    if (!charset) {
        charset = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
        [charset addCharactersInString:@"_%"];
    }

    self = [self init];
    if (self == nil)
        return nil;

    if (data == nil)
        return nil;

    NSString *string = [[NSString alloc] initWithData:data encoding:NSNEXTSTEPStringEncoding];
    NSScanner *scanner = [NSScanner scannerWithString:string];

    while (![scanner isAtEnd]) {
        NSString *className = nil;
        NSString *superclassName = nil;

        [scanner scanCharactersFromSet:charset intoString:&className];
        [scanner scanUpToCharactersFromSet:charset intoString:NULL];
        [scanner scanCharactersFromSet:charset intoString:&superclassName];

        if (className == nil || superclassName == nil)
            return nil;

        [self setSuperclass:superclassName forClass:className];
    }

    return self;
}

- (NSString *)description {
    return self->classHierarchy.description;
}

- (NSEnumerator *)classEnumerator {
    return self->classHierarchy.keyEnumerator;
}

- (BOOL)class:(NSString *)className descendsFrom:(NSString *)superclassName {
    NSString *directSuperclass;

    directSuperclass = [classHierarchy objectForKey:className];
    if (directSuperclass == nil)
        return NO;

    if ([superclassName isEqualToString:className] ||
        [directSuperclass isEqualToString:superclassName] ||
        [superclassName isEqualToString:@"ROOT"]) {
        return YES;
    }

    return [self class:directSuperclass descendsFrom:superclassName];
}

- (NSString *)superclassOfClass:(NSString *)className {
    return self->classHierarchy[className];
}

- (void)setSuperclass:(NSString *)superclassName forClass:(NSString *)className {
    [self->classHierarchy setObject:superclassName forKey:className];
}

- (void)removeSuperclassForClass:(NSString *)className {
    NSArray *allKeys = [self->classHierarchy allKeysForObject:className];

    if (allKeys) {
        NSUInteger count = allKeys.count;
        if (count) {
            for (int i = 0; i < count; ++i) {
                [self removeSuperclassForClass:allKeys[i]];
            }
        }
    }

    [self->classHierarchy removeObjectForKey:className];
}

- (void)renameClass:(NSString *)oldName toName:(NSString *)newName {
    NSArray *allKeys = [self->classHierarchy allKeysForObject:oldName];

    if (allKeys) {
        NSUInteger count = allKeys.count;
        if (count) {
            for (int i = 0; i < count; ++i) {
                [self setSuperclass:newName forClass:allKeys[i]];
            }
        }
    }

    [self setSuperclass:[self superclassOfClass:oldName] forClass:newName];
    [self->classHierarchy removeObjectForKey:oldName];
}

- (BOOL)writeToFile:(NSString *)path {
    NSEnumerator *enumerator;
    NSMutableString *string;
    NSString *className;

    enumerator = self->classHierarchy.keyEnumerator;
    string = [[NSMutableString alloc] init];

    while ((className = [enumerator nextObject])) {
        [string appendFormat:@"%@ , %@\n", className, [self superclassOfClass:className]];
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [string writeToFile:path atomically:YES];
#pragma clang diagnostic pop
}

@end
