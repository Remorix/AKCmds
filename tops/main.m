#import "Tops.h"

Tops *gCurrentTops = nil;

int main(int argc, char *argv[]) {
    @autoreleasepool {
        gCurrentTops = [[Tops alloc] initWithCommandLine];
        [gCurrentTops applyRules];
        gCurrentTops = nil;
    }
    return 0;
}
