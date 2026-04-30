#import "Common.h"

void ns_printf(NSString *format, ...) {
    va_list ap;
    static NSFileHandle *stdoutFileHandle = nil;

    if (!stdoutFileHandle) {
        stdoutFileHandle = NSFileHandle.fileHandleWithStandardOutput;
    }

    va_start(ap, format);
    ns_vfprintf(stdoutFileHandle, format, ap);
    va_end(ap);
}

void ns_errorf(NSString *format, ...) {
    va_list ap;
    static NSFileHandle *stderrFileHandle = nil;

    if (!stderrFileHandle) {
        stderrFileHandle = NSFileHandle.fileHandleWithStandardError;
    }

    va_start(ap, format);
    ns_vfprintf(stderrFileHandle, format, ap);
    va_end(ap);
}

void ns_vfprintf(NSFileHandle *fileHandle, NSString *format, va_list args) {
    NSMutableString *string;

    string = [[NSMutableString alloc] initWithFormat:format arguments:args];
    [string appendString:@"\n"];
    [fileHandle writeData:[string dataUsingEncoding:NSASCIIStringEncoding]];
}
