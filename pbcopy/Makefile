PROG?=		pbcopy
SRCS=		pbcopy.m
TARGET?=	${PROG}
OBJS=		pbcopy.o
LINKS=		pbpaste

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

USE_APPKIT?=			no
SIGN_WITH_ENTITLEMENTS?=	yes

ifeq ($(TARGET_IS_MACOS),yes)
USE_APPKIT=			yes
SIGN_WITH_ENTITLEMENTS=	no
else
USE_APPKIT?=			no
SIGN_WITH_ENTITLEMENTS?=	yes
endif

ifeq ($(USE_APPKIT),yes)
LDADD+=		-framework AppKit
else
LDADD+=		-framework UIKit \
		-framework MobileCoreServices \
		-framework UniformTypeIdentifiers
endif

ENTITLEMENTS?=		pbcopy.entitlements
CODESIGN?=		codesign
CODESIGN_FLAGS?=	--force --sign - --entitlements ${ENTITLEMENTS} --timestamp=none
LDID?=			ldid
LDID_FLAGS?=		-S${ENTITLEMENTS}

.PHONY: all check clean show-config

all: ${TARGET} ${LINKS}

check: ${TARGET} ${LINKS}

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
	@printf 'LINKS=%s\n' '${LINKS}'
	@printf 'LDADD=%s\n' '${LDADD}'
	@printf 'TARGET_IS_MACOS=%s\n' '${TARGET_IS_MACOS}'
	@printf 'USE_APPKIT=%s\n' '${USE_APPKIT}'
	@printf 'SIGN_WITH_ENTITLEMENTS=%s\n' '${SIGN_WITH_ENTITLEMENTS}'
	@printf 'ENTITLEMENTS=%s\n' '${ENTITLEMENTS}'
	@printf 'CODESIGN=%s\n' '${CODESIGN}'
	@printf 'CODESIGN_FLAGS=%s\n' '${CODESIGN_FLAGS}'
	@printf 'LDID=%s\n' '${LDID}'
	@printf 'LDID_FLAGS=%s\n' '${LDID_FLAGS}'

${TARGET}: ${OBJS}
	${CC} ${LINK_FLAGS} -o $@ ${OBJS} ${LDADD}
ifeq ($(SIGN_WITH_ENTITLEMENTS),yes)
	@if [ -n '${ENTITLEMENTS}' ]; then \
		if command -v '${CODESIGN}' >/dev/null 2>&1; then \
			'${CODESIGN}' ${CODESIGN_FLAGS} $@; \
		elif command -v '${LDID}' >/dev/null 2>&1; then \
			'${LDID}' ${LDID_FLAGS} $@; \
		else \
			printf 'missing signing tool: %s or %s\n' '${CODESIGN}' '${LDID}' >&2; \
			exit 1; \
		fi; \
	fi
endif

pbcopy.o: pbcopy.m
	${CC} ${COMPILE_FLAGS} -c pbcopy.m -o $@

pbpaste: ${TARGET}
	ln -sf ${TARGET} $@

clean:
	rm -f ${OBJS} ${TARGET} ${LINKS}
