#!/bin/sh -e

LEAST_V2=9011


do_the_job()
{
	# Check for HiWiFi OS
	if [ ! -f $X/etc/.build ]; then
		echo "*** Cannot be installed on routers other than HiWiFi 1, 1S, 2."
		exit 1
	fi

	# Check HiWiFi firmware version
	V1=`awk -F. '{print $1}' $X/etc/.build`
	V2=`awk -F. '{print $2}' $X/etc/.build`
	if ! [ "$V1" -ge 1 -o "$V2" -ge "$LEAST_V2" ]; then
		echo "*** You must have your firmware upgraded at lease 0.$LEAST_V2."
		exit 1
	fi

	mkdir -p $X/etc/opkg

	# Select CPU architecture
	[ -f $X/etc/openwrt_release ] && . $X/etc/openwrt_release || :

	local P=`echo "$DISTRIB_TARGET" | awk -F/ '{print $1}'`
	case "$P" in
		ar71xx)
			echo "src/gz rssnsj http://rssn.cn/roms/hifeeds/ar71xx" > $X/etc/opkg/rssnsj.conf  # 极1
			;;
		ralink)
			echo "src/gz rssnsj http://rssn.cn/roms/hifeeds/ralink" > $X/etc/opkg/rssnsj.conf  # 极1S(HC5661)、极2、极3
			;;
		mediatek)
			echo -e "src/gz rssnsj http://rssn.cn/roms/hifeeds/ralink\narch all 100\narch ralink 200\narch mediatek 300" > $X/etc/opkg/rssnsj.conf  # 新极1S(HC5661A)
			;;
		*)
			echo "*** Unsupported hardware architecture '$P'."
			return 1
			;;
	esac

	# Install our customized packages
	rm -f /var/opkg-lists/rssnsj || :
	opkg update
	opkg install openssh-redir-client autossh-renamed dnsmasq-salist vanillass-libev pdnsd || :
	opkg install shadowsocks-tools --force-overwrite || :

	rm -f $X/etc/opkg/rssnsj.conf
}

do_the_job

