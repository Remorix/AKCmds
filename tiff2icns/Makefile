PROG?=		tiff2icns
SRCS=		tiff2icns.m
TARGET?=	${PROG}
OBJS=		${SRCS:.m=.o}

CC?=		cc

CFLAGS?=	-g -O2
LDADD?=		-framework Foundation -framework CoreFoundation -lobjc
WARNFLAGS?=	-Wall -Wextra -Wformat
OBJCFLAGS+=	-fobjc-arc
COMPILE_FLAGS=	${CPPFLAGS} ${CFLAGS} ${WARNFLAGS} ${OBJCFLAGS}
LINK_FLAGS=	${LDFLAGS}

CC_TARGET:=	$(shell ${CC} ${CPPFLAGS} ${CFLAGS} ${OBJCFLAGS} -dumpmachine 2>/dev/null || true)

TARGET_IS_MACOS:=	$(shell \
	if printf '%s\n' \
		'\#ifndef __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__' \
		'\#error not macos' \
		'\#endif' | \
		${CC} ${CPPFLAGS} ${CFLAGS} ${OBJCFLAGS} \
			-E -x objective-c - >/dev/null 2>&1; then \
		printf '%s\n' yes; \
	else \
		printf '%s\n' no; \
	fi)

ifeq ($(TARGET_IS_MACOS),yes)
SIGN_BINARY?=	no
LDADD+=		-framework AppKit \
		-framework ApplicationServices \
		-framework CoreServices
else
SIGN_BINARY?=	yes
LDADD+=		-framework CoreGraphics \
		-framework ImageIO \
		-framework MobileCoreServices
endif

CODESIGN?=		codesign
CODESIGN_FLAGS?=	--force --sign - --timestamp=none
LDID?=			ldid
LDID_FLAGS?=		-S

.PHONY: all clean show-config

all: ${TARGET}

show-config:
	@printf 'PROG=%s\n' '${PROG}'
	@printf 'CC=%s\n' '${CC}'
	@printf 'CC_TARGET=%s\n' '${CC_TARGET}'
	@printf 'CPPFLAGS=%s\n' '${CPPFLAGS}'
	@printf 'CFLAGS=%s\n' '${CFLAGS}'
	@printf 'WARNFLAGS=%s\n' '${WARNFLAGS}'
	@printf 'OBJCFLAGS=%s\n' '${OBJCFLAGS}'
	@printf 'LDFLAGS=%s\n' '${LDFLAGS}'
	@printf 'TARGET=%s\n' '${TARGET}'
	@printf 'TARGET_IS_MACOS=%s\n' '${TARGET_IS_MACOS}'
	@printf 'SRCS=%s\n' '${SRCS}'
	@printf 'LDADD=%s\n' '${LDADD}'
	@printf 'SIGN_BINARY=%s\n' '${SIGN_BINARY}'
	@printf 'CODESIGN=%s\n' '${CODESIGN}'
	@printf 'CODESIGN_FLAGS=%s\n' '${CODESIGN_FLAGS}'
	@printf 'LDID=%s\n' '${LDID}'
	@printf 'LDID_FLAGS=%s\n' '${LDID_FLAGS}'

${TARGET}: ${OBJS}
	${CC} ${LINK_FLAGS} -o $@ ${OBJS} ${LDADD}
ifeq ($(SIGN_BINARY),yes)
	@if command -v '${CODESIGN}' >/dev/null 2>&1; then \
		'${CODESIGN}' ${CODESIGN_FLAGS} $@; \
	elif command -v '${LDID}' >/dev/null 2>&1; then \
		'${LDID}' ${LDID_FLAGS} $@; \
	else \
		printf 'missing signing tool: %s or %s\n' '${CODESIGN}' '${LDID}' >&2; \
		exit 1; \
	fi
endif

%.o: %.m
	${CC} ${COMPILE_FLAGS} -c $< -o $@

clean:
	rm -f ${OBJS} ${TARGET}
