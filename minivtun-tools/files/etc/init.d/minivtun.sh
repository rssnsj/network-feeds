#!/bin/sh /etc/rc.common
#
# Copyright (C) 2014 Justin Liu <rssnsj@gmail.com>
# https://github.com/rssnsj/network-feeds
#

START=93

start()
{
	local vt_enabled=`uci get minivtun.@minivtun[0].enabled 2>/dev/null`
	local vt_server_addr=`uci get minivtun.@minivtun[0].server`
	local vt_server_port=`uci get minivtun.@minivtun[0].server_port`

	if [ "$vt_enabled" = 0 ]; then
		echo "WARNING: Mini Virtual Tunneller is disabled."
		return 1
	fi
	if [ -z "$vt_server_addr" -o -z "$vt_server_port" ]; then
		echo "WARNING: No server address configured, not starting."
		return 1
	fi

	killall -9 invoke.sh 2>/dev/null && sleep 1
	# The startup script might wait for DNS resolution to be
	# ready, so execute in background.
	start-stop-daemon -S -b -x /usr/lib/minivtun/invoke.sh -- -s
}

stop()
{
	/usr/lib/minivtun/invoke.sh -k
	killall -9 invoke.sh 2>/dev/null && sleep 1 || :
}

restart()
{
	export KEEP_GFWLIST=Y
	stop
	start
}

