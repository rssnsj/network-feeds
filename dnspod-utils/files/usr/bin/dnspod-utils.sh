#!/bin/sh

#
# Copyright (c) 2020 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
#

DNSAPI_USERAGENT="OpenWrt-DDNS/0.1.0 (rssnsj@gmail.com)"
CURL_EXTRA_OPTS=
DDNS_MODE=N

# $1: URL
# $2: post data
__call_dnsapi()
{
	local api_url="$1" post_data="$2" api_resp= rc i
	for i in 2 2 5 5 10 10 20 20 0; do
		api_resp=`curl "$api_url" -d "$post_data" -A "$DNSAPI_USERAGENT" -f -s --connect-timeout 10 -m20 $CURL_EXTRA_OPTS`
		rc=$?
		if [ "$rc" = 60 -o "$rc" = 51 ]; then
			echo "*** Invalid certificate of '$api_url'" >&2
			return 1
		elif [ -z "$api_resp" ]; then
			echo "*** Network failure, retrying in ${i}s ..." >&2
			sleep $i
			continue
		else
			local err=`echo "$api_resp" | jq -r .status.code`
			if [ "$err" != 1 ]; then
				local errmsg=`echo "$api_resp" | jq -r .status.message`
				echo "*** $errmsg ($err)" >&2
				return 1
			fi
		fi
		#
		break
	done
	[ -n "$api_resp" ] && echo "$api_resp"
}

# $1: token (id,key)
# $2: domain
# $3: host
# $4: record type
# $*: values (allow empty with '-d')
dnspod_set()
{
	local api_token="$1" r_domain="$2" r_host="$3" r_type="$4"
	shift 4

	if ! [ -n "$api_token" -a -n "$r_domain" -a -n "$r_host" -a -n "$r_type" ]; then
		echo "*** Missing arguments" >&2
		return 1
	fi

	# Get record id(s)
	local r_ids=`__call_dnsapi "https://dnsapi.cn/Record.List" \
		"login_token=$api_token&format=json&domain=$r_domain&sub_domain=$r_host&record_type=$r_type" |
		jq -r '.records[] | select(.name=="'"$r_host"'" and .type=="'"$r_type"'" and .enabled=="1") | .id'`
	[ -n "$r_ids" ] || return 1

	# Update each record
	local r_id
	for r_id in $r_ids; do
		local r_value="$1"
		if [ "$DDNS_MODE" = Y ]; then
			local api_method="Record.Ddns"
		else
			local api_method="Record.Modify"
			[ -n "$r_value" ] || break
			shift 1
		fi
		local value_arg=
		if [ -n "$r_value" ]; then
			local value_arg="&value=$r_value"
		fi
		local api_resp=`__call_dnsapi "https://dnsapi.cn/$api_method" \
			"login_token=$api_token&format=json&domain=$r_domain&record_id=$r_id&sub_domain=$r_host$value_arg&record_type=$r_type&record_line=默认"`
		[ -n "$api_resp" ] || return 1
		local new_value=`echo "$api_resp" | jq -r '.record.value'`
		echo "OK: $r_host.$r_domain - $new_value"
	done
}

# No argument
openwrt_once()
{
	if ! [ -f /etc/config/dnspod ]; then
		echo "*** No /etc/config/dnspod found." >&2
		return 1
	fi

	DDNS_MODE=Y

	local i
	for i in 0 1 2 3 4 5 6 7 8 9; do
		uci -q get dnspod.@dnspod[$i] >/dev/null || break
		local enabled=`uci -q get dnspod.@dnspod[$i].enabled`
		[ "$enabled" = 0 ] && continue || :
		local login_token=`uci -q get dnspod.@dnspod[$i].login_token`
		local domain=`uci -q get dnspod.@dnspod[$i].domain`
		local subdomain=`uci -q get dnspod.@dnspod[$i].subdomain`
		local ipfrom=`uci -q get dnspod.@dnspod[$i].ipfrom`
		if [ "$ipfrom" = auto ]; then
			dnspod_set "$login_token" "$domain" "$subdomain" A
		elif [ -n "$ipfrom" ]; then
			. /lib/functions/network.sh
			network_get_ipaddr ip $ipfrom
			dnspod_set "$login_token" "$domain" "$subdomain" A "$ip"
		fi
	done
}

##
show_help()
{
	cat <<EOF
Usage:
  $0 [options] set  api_token domain name type value1 [value2 ...]
  $0 [options] once    # OpenWrt only
Options:
  -d sencods                delayed seconds before any operation
  -D                        use 'Record.Ddns' for update (10s TTL)
  -k                        pass '-k' to curl
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		-d) shift 1; sleep "$1";;
		-D) DDNS_MODE=Y;;
		-k) CURL_EXTRA_OPTS=-k;;
		-*) show_help; exit 1;;
		*) break;;
	esac
	shift 1
done

case "$1" in
	set) shift 1; dnspod_set "$@";;
	once) shift 1; openwrt_once;;
	*) show_help; exit 1;;
esac
