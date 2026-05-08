SUBDIRS=		open pbcopy textutil tiff2icns tiffutil tops

.PHONY: all clean show-config

all clean show-config:
	@for subdir in ${SUBDIRS}; do \
		${MAKE} -C "$$subdir" $@ || exit $$?; \
	done
