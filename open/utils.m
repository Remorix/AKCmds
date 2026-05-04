#import "open_internal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

NSString *stringFromArg(const char *cstr) {
    if (!cstr) return nil;
    NSString *s = [NSString stringWithUTF8String:cstr];
    if (!s) {
        s = [[[NSString alloc] initWithBytes:cstr
                                      length:strlen(cstr)
                                    encoding:[NSString defaultCStringEncoding]] autorelease];
    }
    return s;
}

void dieWithError(NSString *msg) {
    fputs([msg UTF8String], stderr);
    fputc('\n', stderr);
    exit(1);
}

NSString *joinArrayWithConjunction(NSArray *items, NSString *conj) {
    if (!items) return nil;
    NSUInteger n = items.count;
    if (!n) return @"";
    if (n == 1)
        return [NSString stringWithFormat:@"%@", items[0]];
    if (n == 2)
        return [NSString stringWithFormat:@"%@ %@ %@", items[0], conj, items[1]];
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < n; ++i) {
        if (i > 0) [s appendString:@", "];
        if (i == n - 1) [s appendFormat:@"%@ ", conj];
        [s appendFormat:@"%@", items[i]];
    }
    return s;
}

NSMutableArray *mapArrayWithSelector(NSArray *array, SEL sel) {
    if (!array) return nil;
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
    for (id obj in array) {
        id mapped = [obj performSelector:sel];
        [result addObject:mapped ?: obj];
    }
    return result;
}

void checkFilesExistForArguments(NSArray *urls, NSArray *origArgs) {
    NSMutableArray *missing = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSURL *url in urls) {
        if ([url isFileURL] && ![fm fileExistsAtPath:[url path]])
            [missing addObject:[url path]];
    }
    if (!missing.count) return;

    NSString *hint = @"";
    if (origArgs.count == 1) {
        NSString *arg   = [origArgs[0] lowercaseString];
        NSString *http  = [@"http://" stringByAppendingString:origArgs[0]];
        if ([NSURL URLWithString:http]
            && ([arg hasSuffix:@".com"] || [arg hasSuffix:@".org"] || [arg hasSuffix:@".net"]))
            hint = [NSString stringWithFormat:@"\nPerhaps you meant '%@'?", http];
    }
    NSString *list = joinArrayWithConjunction(missing, @"and");
    NSUInteger n   = missing.count;
    dieWithError([NSString stringWithFormat:
        @"The file%s %@ do%s not exist.%@",
        n == 1 ? "" : "s",
        list,
        n == 1 ? "es" : "",
        hint]);
}
