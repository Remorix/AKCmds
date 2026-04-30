#pragma once

#include <stdarg.h>
#import <Foundation/Foundation.h>

__BEGIN_DECLS

void ns_printf(NSString *format, ...);
void ns_errorf(NSString *format, ...);
void ns_vfprintf(NSFileHandle *fileHandle, NSString *format, va_list args);

__END_DECLS
