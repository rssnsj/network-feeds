#!/bin/sh /etc/rc.common
#
# Copyright (C) 2014 Justin Liu <rssnsj@gmail.com>
# https://github.com/rssnsj/network-feeds
#

START=93


VPN_ROUTE_FWMARK=175
VPN_ROUTE_TABLE=175

logger_warn() { logger -s -t minivtun -p daemon.warn "$1"; }

netmask_to_pfxlen()
{
	local netmask="$1"
	local __masklen=0
	local __byte

	for __byte in `echo "$netmask" | sed 's/\./ /g'`; do
		case "$__byte" in
			255) __masklen=`expr $__masklen + 8`;;
			254) __masklen=`expr $__masklen + 7`;;
			252) __masklen=`expr $__masklen + 6`;;
			248) __masklen=`expr $__masklen + 5`;;
			240) __masklen=`expr $__masklen + 4`;;
			224) __masklen=`expr $__masklen + 3`;;
			192) __masklen=`expr $__masklen + 2`;;
			128) __masklen=`expr $__masklen + 1`;;
			0) break;;
		esac
	done

	echo "$__masklen"
}

start()
{
	local enabled=`uci -q get minivtun.@global[0].enabled`
	local proxy_mode=`uci -q get minivtun.@global[0].proxy_mode`
	local safe_dns=`uci -q get minivtun.@global[0].safe_dns`
	local safe_dns_port=`uci -q get minivtun.@global[0].safe_dns_port`
	# Optional parameters
	local covered_subnets=`uci -q get minivtun.@global[0].covered_subnets`
	local excepted_subnets=`uci -q get minivtun.@global[0].excepted_subnets`
	local excepted_ttl=`uci -q get minivtun.@global[0].excepted_ttl`

	if [ "$enabled" = 0 ]; then
		echo "WARNING: 'minivtun' service is disabled."
		return 1
	fi
	[ -n "$safe_dns_port" ] || safe_dns_port=53
	[ -n "$proxy_mode" ] || proxy_mode=M
	# Use local LAN subnet as default
	if [ -z "$covered_subnets" ]; then
		. /lib/functions/network.sh
		network_get_subnet covered_subnets lan
	fi
	if [ "$proxy_mode" = V ]; then
		local gfwlist="unblock-youku"
	else
		local gfwlist="china-banned"
		[ -n "$safe_dns" ] || safe_dns="8.8.8.8";
	fi

	# -----------------------------------------------------------
	if ! ipset list local >/dev/null 2>&1; then
		/etc/init.d/ipset.sh start
	fi

	# IMPORTANT: 'rp_filter=1' will cause returned packets from
	# virtual interface being dropped, so we have to fix it.
	echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter

	# -----------------------------------------------------------
	# For each tunnel
	local i
	for i in 0 1 2 3 4 5; do
		uci -q get minivtun.@minivtun[$i] >/dev/null || break

		local server_addr=`uci -q get minivtun.@minivtun[$i].server`
		local server_port=`uci -q get minivtun.@minivtun[$i].server_port`
		local password=`uci -q get minivtun.@minivtun[$i].password`
		local algorithm=`uci -q get minivtun.@minivtun[$i].algorithm`
		local local_ipaddr=`uci -q get minivtun.@minivtun[$i].local_ipaddr`
		local local_netmask=`uci -q get minivtun.@minivtun[$i].local_netmask`
		local mtu=`uci -q get minivtun.@minivtun[$i].mtu`
		if [ -z "$server_addr" -o -z "$server_port" ]; then
			logger_warn "WARNING: No server address, ignoring the tunnel."
			continue
		fi
		[ -n "$algorithm" ] || algorithm="aes-128"
		[ -n "$mtu" ] || mtu=1300
		local ifname=minivtun-go$i

		# NOTICE: Empty '$password' is for no encryption
		/usr/sbin/minivtun -r [$server_addr]:$server_port -n $ifname \
			-a $local_ipaddr/`netmask_to_pfxlen $local_netmask` \
			-e "$password" -t "$algorithm" -m $mtu \
			-w -D -v 0.0.0.0/0 -T $VPN_ROUTE_TABLE -M 900 \
			-p /var/run/$ifname.pid -d || return 1

		echo 0 > /proc/sys/net/ipv4/conf/$ifname/rp_filter
	done

	# -----------------------------------------------------------
	ip rule add fwmark $VPN_ROUTE_FWMARK table $VPN_ROUTE_TABLE

	# Add basic firewall rules
	iptables -N minivtun_forward || iptables -F minivtun_forward
	iptables -I FORWARD -j minivtun_forward
	iptables -A minivtun_forward -o minivtun-+ -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
	iptables -A minivtun_forward -o minivtun-+ -j ACCEPT
	iptables -t nat -I POSTROUTING -o minivtun-+ -j MASQUERADE

	# -----------------------------------------------------------
	iptables -t mangle -N minivtun_go
	iptables -t mangle -F minivtun_go
	iptables -t mangle -A minivtun_go -m set --match-set local dst -j RETURN || {
			iptables -t mangle -A minivtun_go -d 10.0.0.0/8 -j RETURN
			iptables -t mangle -A minivtun_go -d 127.0.0.0/8 -j RETURN
			iptables -t mangle -A minivtun_go -d 172.16.0.0/12 -j RETURN
			iptables -t mangle -A minivtun_go -d 192.168.0.0/16 -j RETURN
			iptables -t mangle -A minivtun_go -d 127.0.0.0/8 -j RETURN
			iptables -t mangle -A minivtun_go -d 224.0.0.0/3 -j RETURN
		}
	case "$proxy_mode" in
		G)
			;;
		S)
			iptables -t mangle -A minivtun_go -m set --match-set china dst -j RETURN
			;;
		M)
			ipset create $gfwlist hash:ip maxelem 65536 2>/dev/null
			[ -n "$safe_dns" ] && ipset add $gfwlist $safe_dns 2>/dev/null
			iptables -t mangle -A minivtun_go -m set ! --match-set $gfwlist dst -j RETURN
			iptables -t mangle -A minivtun_go -m set --match-set china dst -j RETURN
			;;
		V)
			ipset create $gfwlist hash:ip maxelem 65536 2>/dev/null
			[ -n "$safe_dns" ] && ipset add $gfwlist $safe_dns 2>/dev/null
			iptables -t mangle -A minivtun_go -m set ! --match-set $gfwlist dst -j RETURN
			;;
	esac
	# Clients that do not use VPN
	local subnet
	for subnet in $excepted_subnets; do
		iptables -t mangle -A minivtun_go -s $subnet -j RETURN
	done
	local ttl
	for ttl in $excepted_ttl; do
		iptables -t mangle -A minivtun_go -m ttl --ttl-eq $ttl -j RETURN
	done
	# Clients that need VPN
	for subnet in $covered_subnets; do
		iptables -t mangle -A minivtun_go -s $subnet -j MARK --set-mark $VPN_ROUTE_FWMARK
	done
	if [ -n "$safe_dns" ]; then
		iptables -t mangle -A minivtun_go -d $safe_dns -p udp --dport $safe_dns_port \
			-j MARK --set-mark $VPN_ROUTE_FWMARK
	fi
	iptables -t mangle -A minivtun_go -m mark --mark $VPN_ROUTE_FWMARK -j ACCEPT  # stop further matches

	iptables -t mangle -I PREROUTING -j minivtun_go
	iptables -t mangle -I OUTPUT -p udp --dport 53 -j minivtun_go  # DNS queries over tunnel

	# -----------------------------------------------------------
	mkdir -p /var/etc/dnsmasq-go.d
	###### Anti-pollution configuration ######
	if [ -n "$safe_dns" ]; then
		( cat /etc/gfwlist/$gfwlist; cat /etc/gfwlist/$gfwlist.* 2>/dev/null; ) | \
			awk -vs="$safe_dns#$safe_dns_port" '!/^$/&&!/^#/{printf("server=/%s/%s\n",$0,s)}' \
			> /var/etc/dnsmasq-go.d/01-pollution.conf
	else
		logger_warn "WARNING: Not using safe DNS, might have DNS pollution issue in China."
	fi

	###### dnsmasq-to-ipset configuration ######
	case "$proxy_mode" in
		M|V)
			( cat /etc/gfwlist/$gfwlist; cat /etc/gfwlist/$gfwlist.* 2>/dev/null; ) | \
				awk '!/^$/&&!/^#/{printf("ipset=/%s/'"$gfwlist"'\n",$0)}' \
				> /var/etc/dnsmasq-go.d/02-ipset.conf
			;;
	esac

	# -----------------------------------------------------------
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
			if [ -f /var/run/dnsmasq.pid ]; then
				local dnsmasq_pid=`cat /var/run/dnsmasq.pid`
			elif [ -f /var/run/dnsmasq/dnsmasq.pid ]; then
				local dnsmasq_pid=`cat /var/run/dnsmasq/dnsmasq.pid`
			else
				local dnsmasq_pid=`cat /var/run/dnsmasq/dnsmasq.*.pid 2>/dev/null`
			fi
			if [ -n "$dnsmasq_pid" ]; then
				if kill -0 $dnsmasq_pid 2>/dev/null; then
					dnsmasq_ok=Y
					break
				fi
			fi
		done
		if [ "$dnsmasq_ok" != Y ]; then
			logger_warn "WARNING: Attached dnsmasq rules will cause the service startup failure. Removed those configurations."
			rm -f /tmp/dnsmasq.d/dnsmasq-go.conf
			/etc/init.d/dnsmasq restart
		fi
	fi
}

stop()
{
	# -----------------------------------------------------------
	rm -rf /var/etc/dnsmasq-go.d
	if [ -f /tmp/dnsmasq.d/dnsmasq-go.conf ]; then
		rm -f /tmp/dnsmasq.d/dnsmasq-go.conf
		/etc/init.d/dnsmasq restart
	fi

	# -----------------------------------------------------------
	if iptables -t mangle -F minivtun_go 2>/dev/null; then
		while iptables -t mangle -D OUTPUT -p udp --dport 53 -j minivtun_go 2>/dev/null; do :; done
		while iptables -t mangle -D PREROUTING -j minivtun_go 2>/dev/null; do :; done
		iptables -t mangle -X minivtun_go 2>/dev/null
	fi

	# -----------------------------------------------------------
	if [ "$KEEP_GFWLIST" != Y ]; then
		ipset destroy china-banned 2>/dev/null
		ipset destroy unblock-youku 2>/dev/null
	fi

	# -----------------------------------------------------------
	# We don't have to delete the default route, since it will be
	# brought down along with the interface down.
	while ip rule del fwmark $VPN_ROUTE_FWMARK table $VPN_ROUTE_TABLE 2>/dev/null; do :; done

	# Delete basic firewall rules
	while iptables -t nat -D POSTROUTING -o minivtun-+ -j MASQUERADE 2>/dev/null; do :; done
	while iptables -D FORWARD -j minivtun_forward 2>/dev/null; do :; done
	iptables -F minivtun_forward 2>/dev/null
	iptables -X minivtun_forward 2>/dev/null

	local pidfile
	for pidfile in /var/run/minivtun-go*.pid; do
		[ -f "$pidfile" ] || continue
		kill -9 `cat $pidfile`
		rm -f $pidfile
	done
}

restart()
{
	KEEP_GFWLIST=Y
	stop
	sleep 1
	start
}

