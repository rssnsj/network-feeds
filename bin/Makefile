#!/bin/sh

H ?= rssn.cn

copy: .c/ralink .c/ar71xx
	@mkdir -p hc5x61 hc6361
	@cp -vf .c/ralink/packages/autossh_*_ralink.ipk \
		.c/ralink/packages/dnsmasq-salist_*_ralink.ipk \
		.c/ralink/packages/openssh-redir-client_*_ralink.ipk \
		.c/ralink/packages/vanillass-libev_*_ralink.ipk \
		.c/ralink/packages/shadowsocks-tools_*_ralink.ipk \
		hc5x61/
	@cp -vf .c/ar71xx/packages/autossh_*_ar71xx.ipk \
		.c/ar71xx/packages/dnsmasq-salist_*_ar71xx.ipk \
		.c/ar71xx/packages/openssh-redir-client_*_ar71xx.ipk \
		.c/ar71xx/packages/vanillass-libev_*_ar71xx.ipk \
		.c/ar71xx/packages/shadowsocks-tools_*_ar71xx.ipk \
		hc6361/

.c/ralink .c/ar71xx:
	mkdir -p .c
	ln -s ~/hc5x61/platform/bin/ralink .c/ralink
	ln -s ~/hc6361/platform/bin/ar71xx .c/ar71xx

up: copy
	rsync -rlptD -v hc5x61 hc6361 root@$(H):/www/network-feeds/

