#!/bin/sh

mkdir -p ramips ar71xx

cp -f ~/openwrt-hc5761/openwrt-ramips/bin/ramips/packages/base/dnsmasq_*.ipk \
	~/openwrt-hc5761/openwrt-ramips/bin/ramips/packages/base/ipset-lists_*.ipk \
	~/openwrt-hc5761/openwrt-ramips/bin/ramips/packages/base/kmod-proto-bridge_*.ipk \
	~/openwrt-hc5761/openwrt-ramips/bin/ramips/packages/base/shadowsocks-libev_*.ipk \
	~/openwrt-hc5761/openwrt-ramips/bin/ramips/packages/base/shadowsocks-tools_*.ipk \
	ramips/

cp -f ~/openwrt-hc6361/openwrt-ar71xx/bin/ar71xx/packages/base/dnsmasq_*.ipk \
	~/openwrt-hc6361/openwrt-ar71xx/bin/ar71xx/packages/base/ipset-lists_*.ipk \
	~/openwrt-hc6361/openwrt-ar71xx/bin/ar71xx/packages/base/kmod-proto-bridge_*.ipk \
	~/openwrt-hc6361/openwrt-ar71xx/bin/ar71xx/packages/base/shadowsocks-libev_*.ipk \
	~/openwrt-hc6361/openwrt-ar71xx/bin/ar71xx/packages/base/shadowsocks-tools_*.ipk \
	ar71xx/

