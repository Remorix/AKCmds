PROG?=		tiffutil
TIFFUTIL_VERSION?=345.6
SRCS=		tiffutil.m tiffdump_wrapper.c
TARGET?=	${PROG}
OBJS=		${SRCS:.m=.o}
OBJS:=		${OBJS:.c=.o}

CC?=		cc

CFLAGS?=	-g -O2
WARNFLAGS?=	-Wall -Wextra -Wformat
OBJCFLAGS+=	-fobjc-arc
COMPILE_FLAGS=	${CPPFLAGS} ${CFLAGS} ${WARNFLAGS} ${OBJCFLAGS}
LINK_FLAGS=	${LDFLAGS}
LDADD?=		-framework Foundation \
		-framework ApplicationServices \
		-framework CoreGraphics \
		-framework ImageIO \
		-lobjc

LOCAL_TIFF_BUILD?=	$(CURDIR)/.libtiff-build
LOCAL_TIFF_SRC?=	$(CURDIR)/.libtiff
LOCAL_TIFF_CACHE?=	$(LOCAL_TIFF_BUILD)/CMakeCache.txt
LOCAL_TIFF_STATIC?=	$(LOCAL_TIFF_BUILD)/libtiff/libtiff.a
LOCAL_TIFF_TIFFDUMP?=	$(LOCAL_TIFF_SRC)/tools/tiffdump.c
LOCAL_TIFF_TIFFIOP?=	$(LOCAL_TIFF_SRC)/libtiff/tiffiop.h
LOCAL_TIFF_CONFIG?=	$(LOCAL_TIFF_BUILD)/libtiff/tif_config.h
LOCAL_TIFF_PORT_CONFIG?=	$(LOCAL_TIFF_BUILD)/port/libport_config.h
LOCAL_TIFFDUMP_DEFINE?=	-DLOCAL_TIFFDUMP_PATH=\"$(LOCAL_TIFF_TIFFDUMP)\"
LOCAL_TIFF_DEP_LIBS:=	$(strip $(shell awk -F= '\
/^zlib:BOOL=/ { zlib = ($$2 == "ON") } \
/^libdeflate:BOOL=/ { libdeflate = ($$2 == "ON") } \
/^jpeg:BOOL=/ { jpeg = ($$2 == "ON") } \
/^jbig:BOOL=/ { jbig = ($$2 == "ON") } \
/^lerc:BOOL=/ { lerc = ($$2 == "ON") } \
/^lzma:BOOL=/ { lzma = ($$2 == "ON") } \
/^zstd:BOOL=/ { zstd = ($$2 == "ON") } \
/^webp:BOOL=/ { webp = ($$2 == "ON") } \
/^ZLIB_LIBRARY_RELEASE:FILEPATH=/ { zlib_path = $$2 } \
/^Deflate_LIBRARY_RELEASE:FILEPATH=/ { libdeflate_path = $$2 } \
/^JPEG_LIBRARY_RELEASE:FILEPATH=/ { jpeg_path = $$2 } \
/^JBIG_LIBRARY_RELEASE:FILEPATH=/ { jbig_path = $$2 } \
/^LERC_LIBRARY_RELEASE:FILEPATH=/ { lerc_path = $$2 } \
/^LIBLZMA_LIBRARY_RELEASE:FILEPATH=/ { lzma_path = $$2 } \
/^ZSTD_LIBRARY_RELEASE:FILEPATH=/ { zstd_path = $$2 } \
/^WebP_LIBRARY_RELEASE:FILEPATH=/ { webp_path = $$2 } \
END { \
	if (zlib && zlib_path !~ /-NOTFOUND$$/) printf "%s ", zlib_path; \
	if (libdeflate && libdeflate_path !~ /-NOTFOUND$$/) printf "%s ", libdeflate_path; \
	if (jpeg && jpeg_path !~ /-NOTFOUND$$/) printf "%s ", jpeg_path; \
	if (jbig && jbig_path !~ /-NOTFOUND$$/) printf "%s ", jbig_path; \
	if (lerc && lerc_path !~ /-NOTFOUND$$/) printf "%s ", lerc_path; \
	if (lzma && lzma_path !~ /-NOTFOUND$$/) printf "%s ", lzma_path; \
	if (zstd && zstd_path !~ /-NOTFOUND$$/) printf "%s ", zstd_path; \
	if (webp && webp_path !~ /-NOTFOUND$$/) printf "%s ", webp_path; \
}' "$(LOCAL_TIFF_CACHE)" 2>/dev/null))
LOCAL_TIFF_CFLAGS:=	-I$(LOCAL_TIFF_BUILD)/libtiff \
			-I$(LOCAL_TIFF_BUILD)/port \
			-I$(LOCAL_TIFF_SRC)/libtiff \
			-I$(LOCAL_TIFF_SRC)/port \
			$(LOCAL_TIFFDUMP_DEFINE)
BOOTSTRAP_LOCAL_TIFF?=	$(CURDIR)/bootstrap-libtiff.sh
TIFF_CFLAGS?=	$(shell pkg-config --cflags libtiff-4 2>/dev/null)
TIFF_LIBS?=	$(shell pkg-config --libs libtiff-4 2>/dev/null)

ifeq ($(strip $(TIFF_LIBS)),)
TIFF_LIBS=	-ltiff
endif

ifneq ($(wildcard $(LOCAL_TIFF_STATIC)),)
TIFF_CFLAGS:=	$(LOCAL_TIFF_CFLAGS)
TIFF_LIBS:=	$(LOCAL_TIFF_STATIC) $(LOCAL_TIFF_DEP_LIBS)
endif

CPPFLAGS+=	${TIFF_CFLAGS}
CPPFLAGS+=	-DTIFFUTIL_VERSION=${TIFFUTIL_VERSION}
LDADD+=		${TIFF_LIBS}

.PHONY: all bootstrap-libtiff clean show-config

all: ${TARGET}

bootstrap-libtiff:
	LIBTIFF_SRC='$(LOCAL_TIFF_SRC)' LIBTIFF_BUILD='$(LOCAL_TIFF_BUILD)' \
		sh '$(BOOTSTRAP_LOCAL_TIFF)'

show-config:
	@printf 'PROG=%s\n' '${PROG}'
	@printf 'TIFFUTIL_VERSION=%s\n' '${TIFFUTIL_VERSION}'
	@printf 'CC=%s\n' '${CC}'
	@printf 'CPPFLAGS=%s\n' '${CPPFLAGS}'
	@printf 'CFLAGS=%s\n' '${CFLAGS}'
	@printf 'WARNFLAGS=%s\n' '${WARNFLAGS}'
	@printf 'OBJCFLAGS=%s\n' '${OBJCFLAGS}'
	@printf 'LDFLAGS=%s\n' '${LDFLAGS}'
	@printf 'TARGET=%s\n' '${TARGET}'
	@printf 'SRCS=%s\n' '${SRCS}'
	@printf 'LDADD=%s\n' '${LDADD}'
	@printf 'TIFF_CFLAGS=%s\n' '${TIFF_CFLAGS}'
	@printf 'TIFF_LIBS=%s\n' '${TIFF_LIBS}'
	@printf 'LOCAL_TIFF_BUILD=%s\n' '${LOCAL_TIFF_BUILD}'
	@printf 'LOCAL_TIFF_SRC=%s\n' '${LOCAL_TIFF_SRC}'
	@printf 'LOCAL_TIFF_CACHE=%s\n' '${LOCAL_TIFF_CACHE}'
	@printf 'LOCAL_TIFF_STATIC=%s\n' '${LOCAL_TIFF_STATIC}'
	@printf 'LOCAL_TIFF_DEP_LIBS=%s\n' '${LOCAL_TIFF_DEP_LIBS}'
	@printf 'BOOTSTRAP_LOCAL_TIFF=%s\n' '${BOOTSTRAP_LOCAL_TIFF}'

${TARGET}: ${OBJS}
	${CC} ${LINK_FLAGS} -o $@ ${OBJS} ${LDADD}

tiffdump_wrapper.o: ${LOCAL_TIFF_TIFFDUMP} ${LOCAL_TIFF_TIFFIOP} ${LOCAL_TIFF_CONFIG} ${LOCAL_TIFF_PORT_CONFIG}

%.o: %.m
	${CC} ${COMPILE_FLAGS} -c $< -o $@

%.o: %.c
	${CC} ${CPPFLAGS} ${CFLAGS} ${WARNFLAGS} -c $< -o $@

clean:
	rm -f ${OBJS} ${TARGET}
