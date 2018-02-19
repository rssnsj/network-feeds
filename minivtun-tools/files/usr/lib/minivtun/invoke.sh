#!/bin/sh
#
# Copyright (C) 2014 Justin Liu <rssnsj@gmail.com>
# https://github.com/rssnsj/network-feeds
#

MAX_DNS_WAIT_DEFAULT=120
VPN_ROUTE_FWMARK=199
VPN_IPROUTE_TID=175

DNSMASQ_PORT=7053
DNSMASQ_PIDFILE=/var/run/dnsmask-go.pid

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

# $1: hostname to resolve
# $1: maximum seconds to wait until successful
wait_dns_ready()
{
	local host="$1"
	local timeo="$2"

	# Wait for domain name to be ready
	if expr "$host" : '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$' >/dev/null; then
		return 0
	else
		local dns_ok=N
		local ts_start=`date +%s`
		while :; do
			if minivtun -R "$host:1000" >/dev/null 2>&1; then
				dns_ok=Y
				return 0
			fi

			sleep 5

			local ts_tick=`date +%s`
			local ts_diff=`expr $ts_tick - $ts_start`
			if [ "$timeo" = 0 ]; then
				continue
			elif [ "$ts_diff" -gt 10000 ]; then
				# Eliminate time jumps on boot
				ts_start=$ts_tick
				continue
			elif ! [ "$ts_diff" -lt "$timeo" ]; then
				# Timed out
				return 1
			fi
		done

		# Never reaches here
		return 1
	fi
}

logger_warn()
{
	logger -s -t minivtun -p daemon.warn "$1"
}

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

__gfwlist_by_mode()
{
	case "$1" in
		V) echo unblock-youku;;
		*) echo china-banned;;
	esac
}

__restart_dnsmasq()
{
	# Our dedicated dnsmasq service - dnsmask
	[ -x /usr/lib/minivtun/dnsmask ] || ln -s /usr/sbin/dnsmasq /usr/lib/minivtun/dnsmask
	[ -x /usr/lib/minivtun/dnsmask ] || return 1

	while killall dnsmask 2>/dev/null; do sleep 0.2; done
	rm -f /tmp/dnsmask-go.conf

	if [ -d /var/etc/dnsmasq-go.d ]; then
		cat > /tmp/dnsmask-go.conf <<EOF
conf-dir=/var/etc/dnsmasq-go.d
EOF
		/usr/lib/minivtun/dnsmask -C /tmp/dnsmask-go.conf -p $DNSMASQ_PORT -u root -x $DNSMASQ_PIDFILE
		return $?
	else
		return 1
	fi
}

# New implementation:
# Attach rules to main 'dnsmasq' service and restart it.

do_start_wait()
{
	local vt_server_addr=`uci get minivtun.@minivtun[0].server`
	local vt_server_port=`uci get minivtun.@minivtun[0].server_port`
	local vt_password=`uci get minivtun.@minivtun[0].password 2>/dev/null`
	local vt_algorithm=`uci get minivtun.@minivtun[0].algorithm 2>/dev/null`
	local vt_local_ipaddr=`uci get minivtun.@minivtun[0].local_ipaddr 2>/dev/null`
	local vt_local_netmask=`uci get minivtun.@minivtun[0].local_netmask 2>/dev/null`
	local vt_local_ip6pair=`uci get minivtun.@minivtun[0].local_ip6pair 2>/dev/null`
	local vt_mtu=`uci get minivtun.@minivtun[0].mtu 2>/dev/null`
	local vt_safe_dns=`uci get minivtun.@minivtun[0].safe_dns 2>/dev/null`
	local vt_safe_dns_port=`uci get minivtun.@minivtun[0].safe_dns_port 2>/dev/null`
	local vt_proxy_mode=`uci get minivtun.@minivtun[0].proxy_mode 2>/dev/null`
	local vt_max_dns_wait=`uci get minivtun.@minivtun[0].max_dns_wait 2>/dev/null`
	#local vt_protocols=`uci get minivtun.@minivtun[0].protocols 2>/dev/null`
	# $covered_subnets, $excepted_subnets, $local_addresses are not required
	local covered_subnets=`uci get minivtun.@minivtun[0].covered_subnets 2>/dev/null`
	local excepted_subnets=`uci get minivtun.@minivtun[0].excepted_subnets 2>/dev/null`
	local excepted_ttl=`uci get minivtun.@minivtun[0].excepted_ttl 2>/dev/null`
	local local_addresses=`uci get minivtun.@minivtun[0].local_addresses 2>/dev/null`

	# -----------------------------------------------------------------
	if [ -z "$vt_server_addr" -o -z "$vt_server_port" ]; then
		logger_warn "WARNING: No server address configured, not starting."
		return 1
	fi

	[ -z "$vt_algorithm" ] && vt_algorithm="aes-128"
	[ -z "$vt_local_netmask" ] && vt_local_netmask="255.255.255.0"
	[ -z "$vt_proxy_mode" ] && vt_proxy_mode=M
	case "$vt_proxy_mode" in
		M|S|G) [ -z "$vt_safe_dns" ] && vt_safe_dns="8.8.8.8";;
	esac
	[ -z "$vt_safe_dns_port" ] && vt_safe_dns_port=53
	[ -z "$vt_max_dns_wait" ] && vt_max_dns_wait=$MAX_DNS_WAIT_DEFAULT
	# Get LAN settings as default parameters
	[ -f /lib/functions/network.sh ] && . /lib/functions/network.sh
	[ -z "$covered_subnets" ] && network_get_subnet covered_subnets lan
	[ -z "$local_addresses" ] && network_get_ipaddr local_addresses lan
	local vt_local_prefix=`__netmask_to_bits "$vt_local_netmask"`
	local vt_gfwlist=`__gfwlist_by_mode $vt_proxy_mode`
	local vt_np_ipset="china"
	local cmdline_opts=""
	[ -n "$vt_mtu" ] && cmdline_opts="-m$vt_mtu"

	# -----------------------------------------------------------------
	if ! wait_dns_ready "$vt_server_addr" "$vt_max_dns_wait"; then
		logger_warn "*** Failed to resolve '$vt_server_addr', quitted."
		return 1
	fi

	# NOTICE: Empty '$vt_password' is for no encryption
	/usr/sbin/minivtun -r [$vt_server_addr]:$vt_server_port \
		-a $vt_local_ipaddr/$vt_local_prefix -n minivtun-go \
		-e "$vt_password" -t "$vt_algorithm" $cmdline_opts -d \
			-p /var/run/minivtun-go.pid || return 1

	# IMPORTANT: 'rp_filter=1' will cause returned packets from
	# virtual interface being dropped, so we have to fix it.
	echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter
	echo 0 > /proc/sys/net/ipv4/conf/minivtun-go/rp_filter

	# Add basic firewall rules
	iptables -N minivtun_forward || iptables -F minivtun_forward
	iptables -I FORWARD -j minivtun_forward
	iptables -A minivtun_forward -o minivtun-+ -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
	iptables -A minivtun_forward -j ACCEPT
	iptables -t nat -I POSTROUTING -o minivtun-+ -j MASQUERADE

	# -----------------------------------------------------------------
	if ! ip route add default dev minivtun-go metric 900 table $VPN_IPROUTE_TID; then
		logger_warn "Unexpected error while setting default route for table '$VPN_IPROUTE_TID'."
		return 1
	fi
	ip rule add fwmark $VPN_ROUTE_FWMARK table $VPN_IPROUTE_TID

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
	iptables -t mangle -A minivtun_go -d $vt_server_addr -j RETURN
	case "$vt_proxy_mode" in
		G) : ;;
		S)
			iptables -t mangle -A minivtun_go -m set --match-set $vt_np_ipset dst -j RETURN
			;;
		M)
			ipset create $vt_gfwlist hash:ip maxelem 65536 2>/dev/null
			[ -n "$vt_safe_dns" ] && ipset add $vt_gfwlist $vt_safe_dns 2>/dev/null
			iptables -t mangle -A minivtun_go -m set ! --match-set $vt_gfwlist dst -j RETURN
			iptables -t mangle -A minivtun_go -m set --match-set $vt_np_ipset dst -j RETURN
			;;
		V)
			vt_np_ipset=""
			ipset create $vt_gfwlist hash:ip maxelem 65536 2>/dev/null
			[ -n "$vt_safe_dns" ] && ipset add $vt_gfwlist $vt_safe_dns 2>/dev/null
			iptables -t mangle -A minivtun_go -m set ! --match-set $vt_gfwlist dst -j RETURN
			;;
	esac

	# Bypass VPN traffic
	iptables -t mangle -A minivtun_go -p gre -j RETURN
	iptables -t mangle -A minivtun_go -p esp -j RETURN
	iptables -t mangle -A minivtun_go -p tcp --dport 1723 -j RETURN
	iptables -t mangle -A minivtun_go -p udp --dport 1701 -j RETURN
	iptables -t mangle -A minivtun_go -p udp --dport 1702:1703 -j RETURN
	iptables -t mangle -A minivtun_go -p udp --dport 500 -j RETURN
	iptables -t mangle -A minivtun_go -p udp --dport 4500 -j RETURN
	#
	iptables -t mangle -A minivtun_go -p udp --dport 8400:8499 -j RETURN

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
	[ -n "$vt_safe_dns" ] && \
		iptables -t mangle -A minivtun_go -d $vt_safe_dns -p udp --dport $vt_safe_dns_port -j MARK --set-mark $VPN_ROUTE_FWMARK
	iptables -t mangle -A minivtun_go -m mark --mark $VPN_ROUTE_FWMARK -j ACCEPT  # stop further matches

	iptables -t mangle -I PREROUTING -j minivtun_go
	iptables -t mangle -I OUTPUT -p udp --dport 53 -j minivtun_go  # DNS queries over tunnel

	# -----------------------------------------------------------------
	mkdir -p /var/etc/dnsmasq-go.d
	###### Anti-pollution configuration ######
	if [ -n "$vt_safe_dns" ]; then
		awk -vs="$vt_safe_dns#$vt_safe_dns_port" '!/^$/&&!/^#/{printf("server=/%s/%s\n",$0,s)}' \
			/etc/gfwlist/$vt_gfwlist > /var/etc/dnsmasq-go.d/01-pollution.conf
	else
		logger_warn "WARNING: Not using secure DNS, DNS resolution might be polluted if you are in China."
	fi

	###### dnsmasq-to-ipset configuration ######
	case "$vt_proxy_mode" in
		M|V)
			awk '!/^$/&&!/^#/{printf("ipset=/%s/'"$vt_gfwlist"'\n",$0)}' \
				/etc/gfwlist/$vt_gfwlist > /var/etc/dnsmasq-go.d/02-ipset.conf
			;;
	esac

	# -----------------------------------------------------------------
	###### Redirect all client DNS requests to our dedicated DNS 'dnsmask'
	if __restart_dnsmasq; then
		iptables -t nat -N dnsmasq_go_pre
		iptables -t nat -F dnsmasq_go_pre
		iptables -t nat -A dnsmasq_go_pre -p udp ! --dport 53 -j RETURN

		# Clients that do not use VPN
		for subnet in $excepted_subnets; do
			iptables -t nat -A dnsmasq_go_pre -s $subnet -j RETURN
		done
		for ttl in $excepted_ttl; do
			iptables -t nat -A dnsmasq_go_pre -m ttl --ttl-eq $ttl -j RETURN
		done
		# Clients that need VPN
		for subnet in $covered_subnets; do
			iptables -t nat -A dnsmasq_go_pre -s $subnet -p udp -j REDIRECT --to $DNSMASQ_PORT
		done

		iptables -t nat -I PREROUTING -p udp -j dnsmasq_go_pre
	fi
}

do_stop()
{
	local vt_proxy_mode=`uci get minivtun.@minivtun[0].proxy_mode 2>/dev/null`
	local vt_gfwlist=`__gfwlist_by_mode $vt_proxy_mode`

	# -----------------------------------------------------------------
	if iptables -t nat -F dnsmasq_go_pre 2>/dev/null; then
		while iptables -t nat -D PREROUTING -p udp -j dnsmasq_go_pre 2>/dev/null; do :; done
		iptables -t nat -X dnsmasq_go_pre
	fi
	rm -rf /var/etc/dnsmasq-go.d
	__restart_dnsmasq

	# -----------------------------------------------------------------
	if iptables -t mangle -F minivtun_go 2>/dev/null; then
		while iptables -t mangle -D OUTPUT -p udp --dport 53 -j minivtun_go 2>/dev/null; do :; done
		while iptables -t mangle -D PREROUTING -j minivtun_go 2>/dev/null; do :; done
		iptables -t mangle -X minivtun_go 2>/dev/null
	fi

	# -----------------------------------------------------------------
	[ "$KEEP_GFWLIST" = Y -a "$vt_proxy_mode" = M ] || ipset destroy "$vt_gfwlist" 2>/dev/null

	# -----------------------------------------------------------------
	# We don't have to delete the default route, since it will be
	# brought down along with the interface.
	while ip rule del fwmark $VPN_ROUTE_FWMARK table $VPN_IPROUTE_TID 2>/dev/null; do :; done

	# Delete basic firewall rules
	while iptables -t nat -D POSTROUTING -o minivtun-+ -j MASQUERADE 2>/dev/null; do :; done
	while iptables -D FORWARD -j minivtun_forward 2>/dev/null; do :; done
	iptables -F minivtun_forward 2>/dev/null
	iptables -X minivtun_forward 2>/dev/null

	if [ -f /var/run/minivtun-go.pid ]; then
		kill -9 `cat /var/run/minivtun-go.pid`
		rm -f /var/run/minivtun-go.pid
	fi
}

#
case "$1" in
	-s) do_start_wait;;
	-k) do_stop;;
	-r) do_stop; sleep 1; do_start_wait;;
	*)
		 echo "Usage:"
		 echo " $0 -s       start the service (will wait for DNS ready)"
		 echo " $0 -k       fully stop the service"
		 echo " $0 -p       pause the service (keep the tunnel on for recovery detection)"
		 echo " $0 -r       restart the service (call this to bring up a 'paused' service)"
		 ;;
esac

