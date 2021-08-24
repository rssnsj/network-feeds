help:
	@echo "Run 'make install' for install or update the scripts."

install: uci/uci
	cp uci/libuci.so /usr/lib/
	cp uci/uci /usr/bin/
	@cd ipset-lists/files || exit 1; \
	for f in `find * -type f`; do \
		mkdir -p /`dirname $$f` && cp -vf $$f /$$f || exit 1; \
	done
	@cd minivtun-tools/files || exit 1; \
	for f in `find etc/init.d -type f`; do \
		mkdir -p /`dirname $$f` && cp -vf $$f /$$f || exit 1; \
	done

libubox/libubox.so:
	[ -d libubox ] || git clone http://git.nbd.name/luci2/libubox.git
	cd libubox && cmake -DBUILD_LUA=off
	make ubox -C libubox

uci/uci: libubox/libubox.so
	[ -e /usr/lib/libubox.so ] || cp libubox/libubox.so /usr/lib/
	[ -d uci ] || git clone https://git.openwrt.org/project/uci.git
	cd uci && cmake -DBUILD_LUA=off -Dubox_include_dir=..
	make -C uci

clean:
	rm -rf libubox uci
