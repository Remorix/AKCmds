SUBDIRS=		pbcopy tops
CHECK_SUBDIRS=	pbcopy

.PHONY: all check clean show-config

all clean show-config:
	@for subdir in ${SUBDIRS}; do \
		${MAKE} -C "$$subdir" $@ || exit $$?; \
	done

check:
	@for subdir in ${CHECK_SUBDIRS}; do \
		${MAKE} -C "$$subdir" $@ || exit $$?; \
	done
