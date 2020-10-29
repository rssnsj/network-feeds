help:
	@echo "Run 'make install' for install or update the scripts."

install:
	@cd ipset-lists/files || exit 1; \
	for f in `find * -type f`; do \
		mkdir -p /`dirname $$f` && cp -vf $$f /$$f || exit 1; \
	done
	@cd minivtun-tools/files || exit 1; \
	for f in `find etc/init.d -type f`; do \
		mkdir -p /`dirname $$f` && cp -vf $$f /$$f || exit 1; \
	done

