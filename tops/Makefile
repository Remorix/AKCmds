PROG?=		tops

SRCS=		main.m \
		ClassHierarchy.m \
		Common.m \
		Find.m \
		Replace.m \
		TokenizedInput.m \
		TokenizedTopsInput.m \
		Tops.m \
		TopsParser.m
TARGET?=	${PROG}
OBJS=		${SRCS:.m=.o}

CC?=		cc

CFLAGS?=	-g -O2
WARNFLAGS?=	-Wall -Wextra -Wformat
OBJCFLAGS+=	-fobjc-arc
COMPILE_FLAGS=	${CPPFLAGS} ${CFLAGS} ${WARNFLAGS} ${OBJCFLAGS}
LINK_FLAGS=	${LDFLAGS}
LDADD?=		-framework Foundation -lobjc

.PHONY: all clean show-config

all: ${TARGET}

show-config:
	@printf 'PROG=%s\n' '${PROG}'
	@printf 'CC=%s\n' '${CC}'
	@printf 'CPPFLAGS=%s\n' '${CPPFLAGS}'
	@printf 'CFLAGS=%s\n' '${CFLAGS}'
	@printf 'LDFLAGS=%s\n' '${LDFLAGS}'
	@printf 'TARGET=%s\n' '${TARGET}'

${TARGET}: ${OBJS}
	${CC} ${LINK_FLAGS} -o $@ ${OBJS} ${LDADD}

%.o: %.m
	${CC} ${COMPILE_FLAGS} -c $< -o $@

clean:
	rm -f ${OBJS} ${TARGET}
