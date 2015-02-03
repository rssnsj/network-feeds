#!/bin/sh /etc/rc.common
# Copyright (C) 2014 Justin Liu <rssnsj@gmail.com>

START=96

SS_REDIR_PORT=7070

get_random_port()
{
	local secs=`date +%s`
	[ -z "$secs" ] && secs=$$
	local port=`expr 20000 + \( $secs % 12767 \)`
	echo $port
}

start()
{
	local ss_enabled=`uci get shadowsocks.@shadowsocks[0].enabled`
	local ss_server=`uci get shadowsocks.@shadowsocks[0].server`
	local ss_server_port=`uci get shadowsocks.@shadowsocks[0].server_port`
	local ss_username=`uci get shadowsocks.@shadowsocks[0].username`
	local ss_password=`uci get shadowsocks.@shadowsocks[0].password`
	local ss_method=`uci get shadowsocks.@shadowsocks[0].method`
	local monitor_port=`get_random_port`

	# -----------------------------------------------------------------
	if [ "$ss_enabled" = 0 ]; then
		echo "WARNING: SSH / Shadowsocks proxy was disabled in /etc/config/shadowsocks."
		return 1
	fi

	if [ "$ss_method" = ssh ]; then
		## /etc/init.d/ss-redir.sh disable
		export SSH_PASSWORD="$ss_password"
		export AUTOSSH_GATETIME=0
		export AUTOSSH_POLL=30
		export AUTOSSH_FIRST_POLL="10"
		export AUTOSSH_PATH="/usr/lib/vanillass/ssh"
		# NOTICE: TRANSPARENT_DYNAMIC=1 makes 'ssh' running in
		# transparent proxy mode, important!!!
		export TRANSPARENT_DYNAMIC=1

		service_start /usr/sbin/autossh -M $monitor_port \
			-f -CNg -D 0.0.0.0:$SS_REDIR_PORT -p ${ss_server_port:-22} \
			-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
			-l ${ss_username:-root} $ss_server
	else
		## /etc/init.d/ss-redir.sh disable
		/etc/init.d/ss-redir.sh start
	fi
}

stop()
{
	service_stop /usr/sbin/autossh
	killall -9 ssh 2>/dev/null
	rm -f /var/run/openssh.status
	/etc/init.d/ss-redir.sh stop >/dev/null 2>&1
	return 0
}

