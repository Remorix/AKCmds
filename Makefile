SUBDIRS=		open pbcopy tiff2icns tiffutil tops
CHECK_SUBDIRS=	open pbcopy

.PHONY: all check clean show-config

all clean show-config:
	@for subdir in ${SUBDIRS}; do \
		${MAKE} -C "$$subdir" $@ || exit $$?; \
	done

check:
	@for subdir in ${CHECK_SUBDIRS}; do \
		${MAKE} -C "$$subdir" $@ || exit $$?; \
	done
