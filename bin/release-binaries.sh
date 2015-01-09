#!/bin/sh

mkdir -p ramips ar71xx

cp -vf ~/openwrt-hc5761/openwrt-ramips/bin/ramips/packages/base/{dnsmasq_*.ipk,ipset-lists_*.ipk,kmod-proto-bridge_*.ipk,shadowsocks-libev_*.ipk,shadowsocks-tools_*.ipk} ramips/
cp -vf ~/openwrt-hc6361/openwrt-ar71xx/bin/ar71xx/packages/base/{dnsmasq_*.ipk,ipset-lists_*.ipk,kmod-proto-bridge_*.ipk,shadowsocks-libev_*.ipk,shadowsocks-tools_*.ipk} ar71xx/

