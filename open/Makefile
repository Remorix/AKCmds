PROG?=		open
TARGET?=	${PROG}

CC?=		cc

CFLAGS?=	-g -O2
WARNFLAGS?=	-Wall -Wextra -Wformat
OBJCFLAGS+=	-fblocks
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
SRCS=		open.m \
		header_search.m \
		utils.m
SIGN_WITH_ENTITLEMENTS?=	no
LDADD+=		-framework AppKit \
		-framework ApplicationServices
else
SRCS=		ios_open.m \
		header_search.m \
		utils.m
SIGN_WITH_ENTITLEMENTS?=	yes
ENTITLEMENTS?=		open.entitlements
SDKROOT?=		$(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
SDK_PRIVATE_FRAMEWORKS_DIR?=	$(if $(SDKROOT),$(SDKROOT)/System/Library/PrivateFrameworks,)
PRIVATE_FRAMEWORKS_DIR?=	$(SDK_PRIVATE_FRAMEWORKS_DIR)
ifeq ($(strip $(SDKROOT)),)
CPPFLAGS+=
else
CPPFLAGS+=	-isysroot $(SDKROOT)
ifneq ($(strip $(PRIVATE_FRAMEWORKS_DIR)),)
LINK_FLAGS+=	-F$(PRIVATE_FRAMEWORKS_DIR)
endif
endif
LDADD+=		-framework CoreServices \
		-framework UIKit \
		-framework FrontBoardServices \
		-framework BackBoardServices \
		-framework AssertionServices
endif

OBJS=		${SRCS:.m=.o}

CODESIGN?=		codesign
CODESIGN_FLAGS?=	--force --sign - --entitlements ${ENTITLEMENTS} --timestamp=none
LDID?=			ldid
LDID_FLAGS?=		-S${ENTITLEMENTS}

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
	@printf 'SDKROOT=%s\n' '${SDKROOT}'
	@printf 'SDK_PRIVATE_FRAMEWORKS_DIR=%s\n' '${SDK_PRIVATE_FRAMEWORKS_DIR}'
	@printf 'PRIVATE_FRAMEWORKS_DIR=%s\n' '${PRIVATE_FRAMEWORKS_DIR}'
	@printf 'SIGN_WITH_ENTITLEMENTS=%s\n' '${SIGN_WITH_ENTITLEMENTS}'
	@printf 'ENTITLEMENTS=%s\n' '${ENTITLEMENTS}'

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

%.o: %.m
	${CC} ${COMPILE_FLAGS} -c $< -o $@

clean:
	rm -f ${OBJS} ${TARGET} open.o header_search.o utils.o ios_open.o
	rm -rf .build
