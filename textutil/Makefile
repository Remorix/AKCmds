PROG?=		textutil
TARGET?=	${PROG}

CC?=		cc

CFLAGS?=	-g -O2
WARNFLAGS?=	-Wall -Wextra -Wformat
OBJCFLAGS?=	-fobjc-arc
COMPILE_FLAGS=	${CPPFLAGS} ${CFLAGS} ${WARNFLAGS} ${OBJCFLAGS}
LINK_FLAGS=	${LDFLAGS}
LDADD?=		-framework Foundation -framework CoreFoundation -lobjc

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
SRCS=		textutil.m TextutilWebDelegate.m
LDADD+=		-framework AppKit -framework WebKit
else
SRCS=		textutil.m TextutilWebDelegate.m
LDADD+=		-framework UIKit
endif

OBJS=		${SRCS:.m=.o}

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
	@printf 'OBJS=%s\n' '${OBJS}'
	@printf 'LDADD=%s\n' '${LDADD}'

${TARGET}: ${OBJS}
	${CC} ${LINK_FLAGS} -o $@ ${OBJS} ${LDADD}

%.o: %.m
	${CC} ${COMPILE_FLAGS} -c $< -o $@

clean:
	rm -f ${OBJS} ${TARGET}
