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
PDNSD_LOCAL_PORT=7453

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

# New implementation:
# Attach rules to main 'dnsmasq' service and restart it.

__gfwlist_by_mode()
{
	case "$1" in
		V) echo unblock-youku;;
		*) echo china-banned;;
	esac
}

start()
{
	local vt_enabled=`uci get shadowsocks.@shadowsocks[0].enabled 2>/dev/null`
	local vt_server_addr=`uci get shadowsocks.@shadowsocks[0].server`
	local vt_server_port=`uci get shadowsocks.@shadowsocks[0].server_port`
	local vt_password=`uci get shadowsocks.@shadowsocks[0].password 2>/dev/null`
	local vt_method=`uci get shadowsocks.@shadowsocks[0].method`
	local vt_timeout=`uci get shadowsocks.@shadowsocks[0].timeout 2>/dev/null`
	local vt_safe_dns=`uci get shadowsocks.@shadowsocks[0].safe_dns 2>/dev/null`
	local vt_safe_dns_port=`uci get shadowsocks.@shadowsocks[0].safe_dns_port 2>/dev/null`
	local vt_safe_dns_tcp=`uci get shadowsocks.@shadowsocks[0].safe_dns_tcp 2>/dev/null`
	local vt_proxy_mode=`uci get shadowsocks.@shadowsocks[0].proxy_mode`
	# $covered_subnets, $local_addresses are not required
	local covered_subnets=`uci get shadowsocks.@shadowsocks[0].covered_subnets 2>/dev/null`
	local local_addresses=`uci get shadowsocks.@shadowsocks[0].local_addresses 2>/dev/null`

	/etc/init.d/pdnsd disable 2>/dev/null

	# -----------------------------------------------------------------
	if [ "$vt_enabled" = 0 ]; then
		echo "WARNING: Shadowsocks is disabled."
		return 1
	fi

	if [ -z "$vt_server_addr" -o -z "$vt_server_port" ]; then
		echo "WARNING: Shadowsocks not fully configured, not starting."
		return 1
	fi

	[ -z "$vt_proxy_mode" ] && vt_proxy_mode=M
	[ -z "$vt_method" ] && vt_method=table
	[ -z "$vt_timeout" ] && vt_timeout=60
	case "$vt_proxy_mode" in
		M|S|G)
			[ -z "$vt_safe_dns" ] && vt_safe_dns="8.8.8.8"
			[ -z "$vt_safe_dns_tcp" ] && vt_safe_dns_tcp=1
			;;
	esac
	[ -z "$vt_safe_dns_port" ] && vt_safe_dns_port=53
	# Get LAN settings as default parameters
	[ -f /lib/functions/network.sh ] && . /lib/functions/network.sh
	[ -z "$covered_subnets" ] && network_get_subnet covered_subnets lan
	[ -z "$local_addresses" ] && network_get_ipaddr local_addresses lan
	local vt_gfwlist=`__gfwlist_by_mode $vt_proxy_mode`
	vt_np_ipset="china"  # Must be global variable

	# -----------------------------------------------------------------
	###### shadowsocks ######
	/usr/bin/ss-redir -b0.0.0.0 -l$SS_REDIR_PORT -s$vt_server_addr -p$vt_server_port \
		-k"$vt_password" -m$vt_method -t$vt_timeout -f $SS_REDIR_PIDFILE || return 1

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
	iptables -t nat -A shadowsocks_pre -d $vt_server_addr -j RETURN
	case "$vt_proxy_mode" in
		G) : ;;
		S)
			iptables -t nat -A shadowsocks_pre -m set --match-set $vt_np_ipset dst -j RETURN
			;;
		M)
			ipset create $vt_gfwlist hash:ip maxelem 65536 2>/dev/null
			iptables -t nat -A shadowsocks_pre -m set ! --match-set $vt_gfwlist dst -j RETURN
			iptables -t nat -A shadowsocks_pre -m set --match-set $vt_np_ipset dst -j RETURN
			;;
		V)
			vt_np_ipset=""
			ipset create $vt_gfwlist hash:ip maxelem 65536 2>/dev/null
			iptables -t nat -A shadowsocks_pre -m set ! --match-set $vt_gfwlist dst -j RETURN
			;;
	esac
	local subnet
	for subnet in $covered_subnets; do
		iptables -t nat -A shadowsocks_pre -s $subnet -p tcp -j REDIRECT --to $SS_REDIR_PORT
	done
	iptables -t nat -I PREROUTING -p tcp -j shadowsocks_pre

	# -----------------------------------------------------------------
	mkdir -p /var/etc/dnsmasq-go.d
	###### Anti-pollution configuration ######
	if [ -n "$vt_safe_dns" ]; then
		if [ "$vt_safe_dns_tcp" = 1 ]; then
			start_pdnsd "$vt_safe_dns"
			awk -vs="127.0.0.1#$PDNSD_LOCAL_PORT" '!/^$/&&!/^#/{printf("server=/%s/%s\n",$0,s)}' \
				/etc/gfwlist/$vt_gfwlist > /var/etc/dnsmasq-go.d/01-pollution.conf
		else
			awk -vs="$vt_safe_dns#$vt_safe_dns_port" '!/^$/&&!/^#/{printf("server=/%s/%s\n",$0,s)}' \
				/etc/gfwlist/$vt_gfwlist > /var/etc/dnsmasq-go.d/01-pollution.conf
		fi
	else
		echo "WARNING: Not using secure DNS, DNS resolution might be polluted if you are in China."
	fi

	###### dnsmasq-to-ipset configuration ######
	case "$vt_proxy_mode" in
		M|V)
			awk '!/^$/&&!/^#/{printf("ipset=/%s/'"$vt_gfwlist"'\n",$0)}' \
				/etc/gfwlist/$vt_gfwlist > /var/etc/dnsmasq-go.d/02-ipset.conf
			;;
	esac

	# -----------------------------------------------------------------
	###### Restart main 'dnsmasq' service if needed ######
	if ls /var/etc/dnsmasq-go.d/* >/dev/null 2>&1; then
		mkdir -p /tmp/dnsmasq.d
		cat > /tmp/dnsmasq.d/dnsmasq-go.conf <<EOF
conf-dir=/var/etc/dnsmasq-go.d
EOF
		/etc/init.d/dnsmasq restart

		# Check if DNS service was really started
		local dnsmasq_ok=N
		local i
		for i in 0 1 2 3 4 5 6 7; do
			sleep 1
			local dnsmasq_pid=`cat /var/run/dnsmasq.pid 2>/dev/null || cat /var/run/dnsmasq/dnsmasq.pid 2>/dev/null`
			if [ -n "$dnsmasq_pid" ]; then
				if kill -0 "$dnsmasq_pid" 2>/dev/null; then
					dnsmasq_ok=Y
					break
				fi
			fi
		done
		if [ "$dnsmasq_ok" != Y ]; then
			echo "WARNING: Attached dnsmasq rules will cause the service startup failure. Removed those configurations."
			rm -f /tmp/dnsmasq.d/dnsmasq-go.conf
			/etc/init.d/dnsmasq restart
		fi
	fi

}

stop()
{
	local vt_proxy_mode=`uci get minivtun.@minivtun[0].proxy_mode`
	local vt_gfwlist=`__gfwlist_by_mode $vt_proxy_mode`

	# -----------------------------------------------------------------
	rm -rf /var/etc/dnsmasq-go.d
	if [ -f /tmp/dnsmasq.d/dnsmasq-go.conf ]; then
		rm -f /tmp/dnsmasq.d/dnsmasq-go.conf
		/etc/init.d/dnsmasq restart
	fi

	stop_pdnsd

	# -----------------------------------------------------------------
	if iptables -t nat -F shadowsocks_pre 2>/dev/null; then
		while iptables -t nat -D PREROUTING -p tcp -j shadowsocks_pre 2>/dev/null; do :; done
		iptables -t nat -X shadowsocks_pre 2>/dev/null
	fi

	# -----------------------------------------------------------------
	[ "$KEEP_GFWLIST" = Y ] || ipset destroy "$vt_gfwlist" 2>/dev/null

	# -----------------------------------------------------------------
	if [ -f $SS_REDIR_PIDFILE ]; then
		kill -9 `cat $SS_REDIR_PIDFILE`
		rm -f $SS_REDIR_PIDFILE
	fi
}

restart()
{
	KEEP_GFWLIST=Y
	stop
	start
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
		iptables -t nat -A pdnsd_output -m set --match-set $vt_np_ipset dst -j RETURN
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

