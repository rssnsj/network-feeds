#!/bin/sh /etc/rc.common
#
# Copyright (C) 2014 Justin Liu <rssnsj@gmail.com>
# https://github.com/rssnsj/network-feeds
#

START=96

#
# Data source of /etc/gfwlist/china-banned:
#  https://github.com/zhiyi7/ddwrt/blob/master/jffs/vpn/dnsmasq-gfw.txt
#  http://code.google.com/p/autoproxy-gfwlist/
#

SS_REDIR_PORT=7070
SS_REDIR_PIDFILE=/var/run/ss-redir-go.pid 
DNSMASQ_PORT=7053
DNSMASQ_PIDFILE=/var/run/dnsmasq-go.pid
PDNSD_LOCAL_PORT=7453

start()
{
	local ss_enabled=`uci get shadowsocks.@shadowsocks[0].enabled 2>/dev/null`
	local ss_server_addr=`uci get shadowsocks.@shadowsocks[0].server`
	local ss_server_port=`uci get shadowsocks.@shadowsocks[0].server_port`
	local ss_password=`uci get shadowsocks.@shadowsocks[0].password 2>/dev/null`
	local ss_method=`uci get shadowsocks.@shadowsocks[0].method`
	local ss_timeout=`uci get shadowsocks.@shadowsocks[0].timeout 2>/dev/null`
	local ss_safe_dns=`uci get shadowsocks.@shadowsocks[0].safe_dns 2>/dev/null`
	local ss_safe_dns_port=`uci get shadowsocks.@shadowsocks[0].safe_dns_port 2>/dev/null`
	local ss_safe_dns_tcp=`uci get shadowsocks.@shadowsocks[0].safe_dns_tcp 2>/dev/null`
	local ss_proxy_mode=`uci get shadowsocks.@shadowsocks[0].proxy_mode`
	local ss_gfwlist=`uci get shadowsocks.@shadowsocks[0].gfwlist`
	# $covered_subnets, $local_addresses are not required
	local covered_subnets=`uci get shadowsocks.@shadowsocks[0].covered_subnets 2>/dev/null`
	local local_addresses=`uci get shadowsocks.@shadowsocks[0].local_addresses 2>/dev/null`

	/etc/init.d/pdnsd disable 2>/dev/null

	# -----------------------------------------------------------------
	if [ "$ss_enabled" = 0 ]; then
		echo "WARNING: Shadowsocks is disabled."
		return 1
	fi

	if [ -z "$ss_server_addr" -o -z "$ss_server_port" ]; then
		echo "WARNING: Shadowsocks not fully configured, not starting."
		return 1
	fi

	[ -z "$ss_proxy_mode" ] && ss_proxy_mode=S
	[ -z "$ss_method" ] && ss_method=table
	[ -z "$ss_timeout" ] && ss_timeout=60
	[ -z "$ss_safe_dns_port" ] && ss_safe_dns_port=53
	[ -z "$ss_gfwlist" ] && ss_gfwlist="china-banned"
	# Get LAN settings as default parameters
	[ -f /lib/functions/network.sh ] && . /lib/functions/network.sh
	[ -z "$covered_subnets" ] && network_get_subnet covered_subnets lan
	[ -z "$local_addresses" ] && network_get_ipaddr local_addresses lan

	# -----------------------------------------------------------------
	###### shadowsocks ######
	ss-redir -b:: -l$SS_REDIR_PORT -s$ss_server_addr -p$ss_server_port \
		-k"$ss_password" -m$ss_method -t$ss_timeout -f $SS_REDIR_PIDFILE || return 1

	# IPv4 firewall rules
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
	iptables -t nat -A shadowsocks_pre -d $ss_server_addr -j RETURN
	case "$ss_proxy_mode" in
		G) : ;;
		S)
			iptables -t nat -A shadowsocks_pre -m set --match-set china dst -j RETURN
			;;
		M)
			ipset create gfwlist hash:ip maxelem 65536
			iptables -t nat -A shadowsocks_pre -m set ! --match-set gfwlist dst -j RETURN
			iptables -t nat -A shadowsocks_pre -m set --match-set china dst -j RETURN
			;;
	esac
	local subnet
	for subnet in $covered_subnets; do
		iptables -t nat -A shadowsocks_pre -s $subnet -p tcp -j REDIRECT --to $SS_REDIR_PORT
	done
	iptables -t nat -I PREROUTING -p tcp -j shadowsocks_pre

	# -----------------------------------------------------------------
	###### dnsmasq main configuration ######
	mkdir -p /var/etc/dnsmasq-go.d
	cat > /var/etc/dnsmasq-go.conf <<EOF
conf-dir=/var/etc/dnsmasq-go.d
EOF
	[ -f /tmp/resolv.conf.auto ] && echo "resolv-file=/tmp/resolv.conf.auto" >> /var/etc/dnsmasq-go.conf

	# -----------------------------------------------------------------
	###### Anti-pollution configuration ######
	if [ "$ss_safe_dns_tcp" = 1 ]; then
		# Just use 8.8.x.x when $ss_safe_dns left empty
		start_pdnsd "$ss_safe_dns"
		awk -vs="127.0.0.1#$PDNSD_LOCAL_PORT" '!/^$/&&!/^#/{printf("server=/%s/%s\n",$0,s)}' \
			/etc/gfwlist/$ss_gfwlist > /var/etc/dnsmasq-go.d/01-pollution.conf
	elif [ -n "$ss_safe_dns" ]; then
		awk -vs="$ss_safe_dns#$ss_safe_dns_port" '!/^$/&&!/^#/{printf("server=/%s/%s\n",$0,s)}' \
			/etc/gfwlist/$ss_gfwlist > /var/etc/dnsmasq-go.d/01-pollution.conf
	else
		echo "WARNING: Not using secure DNS, DNS resolution might be polluted."
	fi

	# -----------------------------------------------------------------
	###### dnsmasq-to-ipset configuration ######
	if [ "$ss_proxy_mode" = M ]; then
		awk '!/^$/&&!/^#/{printf("ipset=/%s/gfwlist\n",$0)}' \
			/etc/gfwlist/$ss_gfwlist > /var/etc/dnsmasq-go.d/02-ipset.conf
	fi

	# -----------------------------------------------------------------
	###### Start dnsmasq service ######
	if ls /var/etc/dnsmasq-go.d/* >/dev/null 2>&1; then
		dnsmasq -C /var/etc/dnsmasq-go.conf -p $DNSMASQ_PORT -x $DNSMASQ_PIDFILE || return 1

		# IPv4 firewall rules
		iptables -t nat -N dnsmasq_go_pre
		iptables -t nat -F dnsmasq_go_pre
		iptables -t nat -A dnsmasq_go_pre -p udp ! --dport 53 -j RETURN
		local loc_addr
		for loc_addr in $local_addresses; do
			iptables -t nat -A dnsmasq_go_pre -d $loc_addr -p udp -j REDIRECT --to $DNSMASQ_PORT
		done
		iptables -t nat -I PREROUTING -p udp -j dnsmasq_go_pre
	fi

}

stop()
{
	if iptables -t nat -F dnsmasq_go_pre 2>/dev/null; then
		while iptables -t nat -D PREROUTING -p udp -j dnsmasq_go_pre 2>/dev/null; do :; done
		iptables -t nat -X dnsmasq_go_pre
	fi

	if [ -f $DNSMASQ_PIDFILE ]; then
		kill -9 `cat $DNSMASQ_PIDFILE`
		rm -f $DNSMASQ_PIDFILE
	fi
	rm -f /var/etc/dnsmasq-go.conf
	rm -rf /var/etc/dnsmasq-go.d

	stop_pdnsd

	if iptables -t nat -F shadowsocks_pre 2>/dev/null; then
		while iptables -t nat -D PREROUTING -p tcp -j shadowsocks_pre 2>/dev/null; do :; done
		iptables -t nat -X shadowsocks_pre 2>/dev/null
	fi

	ipset destroy gfwlist 2>/dev/null

	if [ -f $SS_REDIR_PIDFILE ]; then
		kill -9 `cat $SS_REDIR_PIDFILE`
		rm -f $SS_REDIR_PIDFILE
	fi
}

# $1: upstream DNS server
start_pdnsd()
{
	local safe_dns="$1"

	local tcp_dns_list="8.8.8.8,8.8.4.4"
	[ -n "$safe_dns" ] && tcp_dns_list="$safe_dns,$tcp_dns_list"

	killall -9 pdnsd 2>/dev/null && sleep 1
	mkdir -p /var/etc /var/pdnsd
	cat > /var/etc/pdnsd.conf <<EOF
global {
	perm_cache=256;
	cache_dir="/var/pdnsd";
	pid_file = /var/run/pdnsd.pid;
	run_as="nobody";
	server_ip = 127.0.0.1;
	server_port = $PDNSD_LOCAL_PORT;
	status_ctl = on;
	query_method = tcp_only;
	min_ttl=15m;
	max_ttl=1w;
	timeout=10;
	neg_domain_pol=on;
	proc_limit=2;
	procq_limit=8;
}
server {
	label= "fwxxx";
	ip = $tcp_dns_list;
	timeout=6;
	uptest=none;
	interval=10m;
	purge_cache=off;
}
EOF

	/usr/sbin/pdnsd -c /var/etc/pdnsd.conf -d

	# Access TCP DNS server through Shadowsocks tunnel
	if iptables -t nat -N pdnsd_output; then
		iptables -t nat -A pdnsd_output -m set --match-set china dst -j RETURN
		iptables -t nat -A pdnsd_output -p tcp -j REDIRECT --to $SS_REDIR_PORT
	fi
	iptables -t nat -I OUTPUT -p tcp --dport 53 -j pdnsd_output
}

stop_pdnsd()
{
	if iptables -t nat -F pdnsd_output 2>/dev/null; then
		while iptables -t nat -D OUTPUT -p tcp --dport 53 -j pdnsd_output 2>/dev/null; do :; done
		iptables -t nat -X pdnsd_output
	fi
	killall -9 pdnsd 2>/dev/null
	rm -rf /var/pdnsd
	rm -f /var/etc/pdnsd.conf
}

