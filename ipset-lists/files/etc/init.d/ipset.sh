#!/bin/sh /etc/rc.common
# Copyright (C) 2014 Justin Liu <rssnsj@gmail.com>

START=21

start()
{
	local file
	for file in /etc/ipset/*; do
		[ -f $file ] || continue
		case "$file" in
			*-opkg) continue;;
		esac
		ipset restore < $file
	done
}

stop()
{
	local file
	for file in /etc/ipset/*; do
		[ -f $file ] || continue
		case "$file" in
			*-opkg) continue;;
		esac
		# Parse the first line for the ipset name
		local name=`head -n1 $file | awk '/^create /{print $2}'`
		if [ -n "$name" ]; then
			ipset destroy $name
		fi
	done
}

restart()
{
	stop >/dev/null 2>&1
	start
}

