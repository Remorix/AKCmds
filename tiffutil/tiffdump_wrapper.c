#include <stdint.h>

#ifndef LOCAL_TIFFDUMP_PATH
#define LOCAL_TIFFDUMP_PATH ".libtiff/tools/tiffdump.c"
#endif

#define main libtiff_tiffdump_main
#include LOCAL_TIFFDUMP_PATH
#undef main

void
tiffdump_file(int fd, uint64_t diroff)
{
    dump(fd, diroff);
}
