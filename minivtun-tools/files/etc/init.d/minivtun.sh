#!/bin/sh /etc/rc.common
#
# Copyright (C) 2014 Justin Liu <rssnsj@gmail.com>
# https://github.com/rssnsj/network-feeds
#

START=93

VPN_ROUTE_FWMARK=199
VPN_IPROUTE_TABLE=virtual

__netmask_to_bits()
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

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

# New implementation:
# Attach rules to main 'dnsmasq' service and restart it.

start()
{
	local vt_enabled=`uci get minivtun.@minivtun[0].enabled 2>/dev/null`
	local vt_network=`uci get minivtun.@minivtun[0].network 2>/dev/null`
	local vt_server_addr=`uci get minivtun.@minivtun[0].server`
	local vt_server_port=`uci get minivtun.@minivtun[0].server_port`
	local vt_password=`uci get minivtun.@minivtun[0].password 2>/dev/null`
	local vt_local_ipaddr=`uci get minivtun.@minivtun[0].local_ipaddr 2>/dev/null`
	local vt_local_netmask=`uci get minivtun.@minivtun[0].local_netmask 2>/dev/null`
	local vt_local_ip6pair=`uci get minivtun.@minivtun[0].local_ip6pair 2>/dev/null`
	local vt_safe_dns=`uci get minivtun.@minivtun[0].safe_dns 2>/dev/null`
	local vt_safe_dns_port=`uci get minivtun.@minivtun[0].safe_dns_port 2>/dev/null`
	local vt_proxy_mode=`uci get minivtun.@minivtun[0].proxy_mode`
	#local vt_protocols=`uci get minivtun.@minivtun[0].protocols 2>/dev/null`
	# $covered_subnets, $local_addresses are not required
	local covered_subnets=`uci get minivtun.@minivtun[0].covered_subnets 2>/dev/null`
	local local_addresses=`uci get minivtun.@minivtun[0].local_addresses 2>/dev/null`

	# -----------------------------------------------------------------
	if [ "$vt_enabled" = 0 ]; then
		echo "WARNING: Mini Virtual Tunneller is disabled."
		return 1
	fi

	if [ -z "$vt_server_addr" -o -z "$vt_server_port" ]; then
		echo "WARNING: No server address configured, not starting."
		return 1
	fi
	[ -z "$vt_network" ] && vt_network="vt0"
	[ -z "$vt_local_netmask" ] && vt_local_netmask="255.255.255.0"
	[ -z "$vt_proxy_mode" ] && vt_proxy_mode=S
	[ -z "$vt_safe_dns_port" ] && vt_safe_dns_port=53
	# Get LAN settings as default parameters
	[ -f /lib/functions/network.sh ] && . /lib/functions/network.sh
	[ -z "$covered_subnets" ] && network_get_subnet covered_subnets lan
	[ -z "$local_addresses" ] && network_get_ipaddr local_addresses lan
	local vt_ifname="minivtun-$vt_network"
	local vt_local_prefix=`__netmask_to_bits "$vt_local_netmask"`
	local vt_gfwlist="china-banned"
	local vt_np_ipset="china"

	# -----------------------------------------------------------------
	/usr/sbin/minivtun -r $vt_server_addr:$vt_server_port \
		-a $vt_local_ipaddr/$vt_local_prefix -n $vt_ifname -e "$vt_password" \
		-d -p /var/run/$vt_ifname.pid || return 1

	# Create new interface if not exists
	local __ifname=`uci get network.$vt_network.ifname 2>/dev/null`
	if [ "$__ifname" != "$vt_ifname" ]; then
		uci delete network.$vt_network 2>/dev/null
		uci set network.$vt_network=interface
		uci set network.$vt_network.proto=none
		uci set network.$vt_network.ifname=$vt_ifname
		uci commit network

		# Attach this interface to firewall zone "wan"
		local i=0
		while true; do
			local __zone=`uci get firewall.@zone[$i].name`
			[ -z "$__zone" ] && break
			# Match zone "wan" to modify
			if [ "$__zone" = wan ]; then
				local __zone_nets=`uci get firewall.@zone[$i].network`
				uci delete firewall.@zone[$i].network
				uci set firewall.@zone[$i].network="$__zone_nets $vt_network"
				uci commit firewall
				break
			fi
			i=`expr $i + 1`
		done
	fi

	ifup $vt_network

	# -----------------------------------------------------------------
	###### IPv4 firewall rules and policy routing ######
	if ! grep '^175' /etc/iproute2/rt_tables >/dev/null; then
		( echo ""; echo "175   $VPN_IPROUTE_TABLE" ) >> /etc/iproute2/rt_tables
	fi

	if ! ip route add default dev $vt_ifname table $VPN_IPROUTE_TABLE; then
		echo "*** Unexpected error while setting default route for table 'virtual'."
		return 1
	fi
	ip rule add fwmark $VPN_ROUTE_FWMARK table $VPN_IPROUTE_TABLE

	iptables -t mangle -N minivtun_$vt_network
	iptables -t mangle -F minivtun_$vt_network
	iptables -t mangle -A minivtun_$vt_network -m set --match-set local dst -j RETURN || {
		iptables -t mangle -A minivtun_$vt_network -d 10.0.0.0/8 -j RETURN
		iptables -t mangle -A minivtun_$vt_network -d 127.0.0.0/8 -j RETURN
		iptables -t mangle -A minivtun_$vt_network -d 172.16.0.0/12 -j RETURN
		iptables -t mangle -A minivtun_$vt_network -d 192.168.0.0/16 -j RETURN
		iptables -t mangle -A minivtun_$vt_network -d 127.0.0.0/8 -j RETURN
		iptables -t mangle -A minivtun_$vt_network -d 224.0.0.0/3 -j RETURN
	}
	iptables -t mangle -A minivtun_$vt_network -d $vt_server_addr -j RETURN
	case "$vt_proxy_mode" in
		G) : ;;
		S)
			iptables -t mangle -A minivtun_$vt_network -m set --match-set $vt_np_ipset dst -j RETURN
			;;
		M)
			ipset create gfwlist hash:ip maxelem 65536
			[ -n "$vt_safe_dns" ] && ipset add gfwlist $vt_safe_dns
			iptables -t mangle -A minivtun_$vt_network -m set ! --match-set gfwlist dst -j RETURN
			iptables -t mangle -A minivtun_$vt_network -m set --match-set $vt_np_ipset dst -j RETURN
			;;
		V)
			vt_np_ipset=""
			vt_gfwlist="unblock-youku"
			ipset create gfwlist hash:ip maxelem 65536
			[ -n "$vt_safe_dns" ] && ipset add gfwlist $vt_safe_dns
			iptables -t mangle -A minivtun_$vt_network -m set ! --match-set gfwlist dst -j RETURN
			;;
	esac
	local subnet
	for subnet in $covered_subnets; do
		iptables -t mangle -A minivtun_$vt_network -s $subnet -j MARK --set-mark $VPN_ROUTE_FWMARK
	done
	[ -n "$vt_safe_dns" ] && \
		iptables -t mangle -A minivtun_$vt_network -d $vt_safe_dns -p udp --dport $vt_safe_dns_port -j MARK --set-mark $VPN_ROUTE_FWMARK
	iptables -t mangle -I PREROUTING -j minivtun_$vt_network
	iptables -t mangle -I OUTPUT -p udp --dport 53 -j minivtun_$vt_network  # DNS queries over tunnel

	# -----------------------------------------------------------------
	mkdir -p /var/etc/dnsmasq-go.d
	###### Anti-pollution configuration ######
	if [ -n "$vt_safe_dns" ]; then
		awk -vs="$vt_safe_dns#$vt_safe_dns_port" '!/^$/&&!/^#/{printf("server=/%s/%s\n",$0,s)}' \
			/etc/gfwlist/$vt_gfwlist > /var/etc/dnsmasq-go.d/01-pollution.conf
	else
		echo "WARNING: Not using secure DNS, DNS resolution might be polluted if you are in China."
	fi

	###### dnsmasq-to-ipset configuration ######
	case "$vt_proxy_mode" in
		M|V)
			awk '!/^$/&&!/^#/{printf("ipset=/%s/gfwlist\n",$0)}' \
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
			local dnsmasq_pid=`cat /var/run/dnsmasq.pid 2>/dev/null`
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
	local vt_network=`uci get minivtun.@minivtun[0].network 2>/dev/null`
	[ -z "$vt_network" ] && vt_network="vt0"
	local vt_ifname="minivtun-$vt_network"

	# -----------------------------------------------------------------
	rm -rf /var/etc/dnsmasq-go.d
	if [ -f /tmp/dnsmasq.d/dnsmasq-go.conf ]; then
		rm -f /tmp/dnsmasq.d/dnsmasq-go.conf
		/etc/init.d/dnsmasq restart
	fi

	# -----------------------------------------------------------------
	if iptables -t mangle -F minivtun_$vt_network 2>/dev/null; then
		while iptables -t mangle -D OUTPUT -p udp --dport 53 -j minivtun_$vt_network 2>/dev/null; do :; done
		while iptables -t mangle -D PREROUTING -j minivtun_$vt_network 2>/dev/null; do :; done
		iptables -t mangle -X minivtun_$vt_network 2>/dev/null
	fi

	# -----------------------------------------------------------------
	ipset destroy gfwlist 2>/dev/null

	# -----------------------------------------------------------------
	# We don't have to delete the default route in 'virtual', since
	# it will be brought down along with the interface.
	while ip rule del fwmark $VPN_ROUTE_FWMARK table $VPN_IPROUTE_TABLE 2>/dev/null; do :; done

	ifdown $vt_network
	if [ -f /var/run/$vt_ifname.pid ]; then
		kill -9 `cat /var/run/$vt_ifname.pid`
		rm -f /var/run/$vt_ifname.pid
	fi

}

