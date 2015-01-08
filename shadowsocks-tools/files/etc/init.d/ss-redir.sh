#!/bin/sh /etc/rc.common
# Copyright (C) 2014 Justin Liu <rssnsj@gmail.com>

START=96

#
# Data source of /etc/gfwlist.list:
#  https://github.com/zhiyi7/ddwrt/blob/master/jffs/vpn/dnsmasq-gfw.txt
#  http://code.google.com/p/autoproxy-gfwlist/
#

SS_REDIR_PORT=7070
SS_REDIR_PIDFILE=/var/run/ss-redir-go.pid 
DNSMASQ_PORT=7053
DNSMASQ_PIDFILE=/var/run/dnsmasq-go.pid

start()
{
	if [ -f /etc/default/ss-redir.defs.sh ]; then
		. /etc/default/ss-redir.defs.sh
	else
		echo "*** Parameter definition file '/etc/default/ss-redir.defs.sh' does not exist."
		return 1
	fi

	[ "$SS_DISABLED" = Y ] && return 1
	if [ -z "$SS_SERVER_ADDR" -o -z "$SS_SERVER_PORT" ]; then
		echo "WARNING: Shadowsocks not fully configured. Please edit /etc/default/ss-redir.defs.sh."
		return 1
	fi

	[ -z "$SS_SERVER_METHOD" ] && SS_SERVER_METHOD=table
	# Get LAN settings as default parameters
	[ -f /lib/functions/network.sh ] && . /lib/functions/network.sh
	[ -z "$COVERED_SUBNETS" ] && network_get_subnet COVERED_SUBNETS lan
	[ -z "$LOCAL_ADDRESSES" ] && network_get_ipaddr LOCAL_ADDRESSES lan

	local subnet gfw_host loc_addr

	###### shadowsocks
	ss-redir -b:: -l$SS_REDIR_PORT -s$SS_SERVER_ADDR -p$SS_SERVER_PORT \
		-k"$SS_SERVER_PASSWORD" -m$SS_SERVER_METHOD -f $SS_REDIR_PIDFILE || return 1

	###### IPv4 firewall rules
	iptables -t nat -N shadowsocks_pre
	iptables -t nat -F shadowsocks_pre
	iptables -t nat -A shadowsocks_pre -m set --match-set local dst -j RETURN || {
		iptables -t nat -A shadowsocks_pre -d 10.0.0.0/8 -j RETURN
		iptables -t nat -A shadowsocks_pre -d 127.0.0.0/8 -j RETURN
		iptables -t nat -A shadowsocks_pre -d 172.16.0.0/12 -j RETURN
		iptables -t nat -A shadowsocks_pre -d 192.168.0.0/16 -j RETURN
		iptables -t nat -A shadowsocks_pre -d 127.0.0.0/8 -j RETURN
		iptables -t nat -A shadowsocks_pre -d 224.0.0.0/3 -j RETURN
	}
	iptables -t nat -A shadowsocks_pre -m set --match-set china dst -j RETURN
	iptables -t nat -A shadowsocks_pre -d $SS_SERVER_ADDR -j RETURN
	for subnet in $COVERED_SUBNETS; do
		iptables -t nat -A shadowsocks_pre -s $subnet -p tcp -j REDIRECT --to $SS_REDIR_PORT
	done
	iptables -t nat -I PREROUTING -p tcp -j shadowsocks_pre

	###### dnsmasq
	if [ -n "$SAFE_DNS_SERVER" ]; then
		mkdir -p /var/dnsmasq-go.d
		(
			cat /etc/gfwlist.list |
			while read gfw_host; do
				[ -z "$gfw_host" ] && continue
				echo "server=/$gfw_host/$SAFE_DNS_SERVER"
			done
		) > /var/dnsmasq-go.d/gfwlist.conf

	cat > /var/run/dnsmasq-go.conf <<EOF
conf-dir=/var/dnsmasq-go.d
EOF
		[ -f /tmp/resolv.conf.auto ] && echo "resolv-file=/tmp/resolv.conf.auto" >> /var/run/dnsmasq-go.conf
		dnsmasq -C /var/run/dnsmasq-go.conf -p $DNSMASQ_PORT -x $DNSMASQ_PIDFILE

		## IPV4
		iptables -t nat -N dnsmasq_go_pre
		iptables -t nat -F dnsmasq_go_pre
		iptables -t nat -A dnsmasq_go_pre -p udp ! --dport 53 -j RETURN
		for loc_addr in $LOCAL_ADDRESSES; do
			iptables -t nat -A dnsmasq_go_pre -d $loc_addr -p udp -j REDIRECT --to $DNSMASQ_PORT
		done
		iptables -t nat -I PREROUTING -p udp -j dnsmasq_go_pre
	else
		echo "WARNING: Not using secure DNS, DNS resolution might be polluted."
	fi
}

stop()
{
	[ "$SS_DISABLED" = Y ] && return 1

	if iptables -t nat -F dnsmasq_go_pre 2>/dev/null; then
		iptables -t nat -D PREROUTING -p udp -j dnsmasq_go_pre
		iptables -t nat -X dnsmasq_go_pre
	fi

	if [ -f $DNSMASQ_PIDFILE ]; then
		kill -9 `cat $DNSMASQ_PIDFILE`
		rm -f $DNSMASQ_PIDFILE
	fi
	rm -f /var/run/dnsmasq-go.conf
	rm -f /var/dnsmasq-go.d/gfwlist.conf

	if iptables -t nat -F shadowsocks_pre 2>/dev/null; then
		iptables -t nat -D PREROUTING -p tcp -j shadowsocks_pre 2>/dev/null
		iptables -t nat -X shadowsocks_pre 2>/dev/null
	fi

	if [ -f $SS_REDIR_PIDFILE ]; then
		kill -9 `cat $SS_REDIR_PIDFILE`
		rm -f $SS_REDIR_PIDFILE
	fi
}

