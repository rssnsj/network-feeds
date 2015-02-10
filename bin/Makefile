#!/bin/sh

copy: .c/ramips .c/ar71xx
	@mkdir -p ramips ar71xx
	@cp -vf .c/ramips/packages/base/dnsmasq_*.ipk \
		.c/ramips/packages/base/ipset-lists_*.ipk \
		.c/ramips/packages/base/kmod-proto-bridge_*.ipk \
		.c/ramips/packages/base/shadowsocks-libev_*.ipk \
		.c/ramips/packages/base/shadowsocks-tools_*.ipk \
		ramips/
	@cp -vf .c/ar71xx/packages/base/dnsmasq_*.ipk \
		.c/ar71xx/packages/base/ipset-lists_*.ipk \
		.c/ar71xx/packages/base/kmod-proto-bridge_*.ipk \
		.c/ar71xx/packages/base/shadowsocks-libev_*.ipk \
		.c/ar71xx/packages/base/shadowsocks-tools_*.ipk \
		ar71xx/

.c/ramips .c/ar71xx:
	mkdir -p .c
	ln -s ~/openwrt-hc5761/openwrt-ramips/bin/ramips .c/ramips
	ln -s ~/openwrt-hc6361/openwrt-ar71xx/bin/ar71xx .c/ar71xx

up: copy
	rsync -rlptD -v ar71xx ramips root@rssn.cn:/www/network-feeds/

