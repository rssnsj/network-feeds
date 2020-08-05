#!/bin/sh

#
# Copyright (c) 2020 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
#

DNSAPI_USERAGENT="OpenWrt-DDNS/0.1.0 (rssnsj@gmail.com)"
DNSAPI_TOKEN=
CURL_EXTRA_OPTS=
DDNS_MODE=N
ASSUME_YES=N

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

# $1: domain
# $2: sub_domain
# $3: record type
# $*: values (allow empty when DDNS_MODE=Y)
dnspod_set()
{
	if [ $# -lt 3 ]; then
		echo "*** Missing arguments" >&2
		return 1
	fi

	local r_domain="$1" r_host="$2" r_type="$3"
	shift 3

	# Get record id(s)
	local r_ids=`__call_dnsapi "https://dnsapi.cn/Record.List" \
		"login_token=$DNSAPI_TOKEN&format=json&domain=$r_domain&sub_domain=$r_host&record_type=$r_type" |
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
			"login_token=$DNSAPI_TOKEN&format=json&domain=$r_domain&record_id=$r_id&sub_domain=$r_host$value_arg&record_type=$r_type&record_line=默认"`
		[ -n "$api_resp" ] || return 1
		local new_value=`echo "$api_resp" | jq -r '.record.value'`
		echo "OK: $r_host.$r_domain - $new_value"
	done
}

# $1: domain
# $2: sub_domain
# $3: record type
# $*: values
dnspod_add()
{
	if [ $# -lt 4 ]; then
		echo "*** Missing arguments" >&2
		return 1
	fi

	local r_domain="$1" r_host="$2" r_type="$3"
	shift 3

	# Create each record
	local r_value
	for r_value in "$@"; do
		local api_resp=`__call_dnsapi "https://dnsapi.cn/Record.Create" \
			"login_token=$DNSAPI_TOKEN&format=json&domain=$r_domain&record_id=$r_id&sub_domain=$r_host&value=$r_value&record_type=$r_type&record_line=默认"`
		[ -n "$api_resp" ] || return 1
		local new_host=`echo "$api_resp" | jq -r '.record.name'`
		echo "OK: $new_host.$r_domain - $r_value"
	done
}

# $1: domain
# $2: sub_domain
# $3: record type
dnspod_del()
{
	if [ $# -lt 3 ]; then
		echo "*** Missing arguments" >&2
		return 1
	fi

	local r_domain="$1" r_host="$2" r_type="$3"

	# Get record id(s)
	local r_rows=`__call_dnsapi "https://dnsapi.cn/Record.List" \
		"login_token=$DNSAPI_TOKEN&format=json&domain=$r_domain&sub_domain=$r_host&record_type=$r_type" |
		jq -r '.records[] | select(.name=="'"$r_host"'" and .type=="'"$r_type"'") | (.id + "|" + .line + "|" + .value)'`
	[ -n "$r_rows" ] || return 1

	# Delete each record
	IFS=$'\n'
	local r_row c
	for r_row in $r_rows; do
		local r_id=`echo "$r_row" | awk -F\| '{print $1}'`
		local r_line=`echo "$r_row" | awk -F\| '{print $2}'`
		local r_value=`echo "$r_row" | awk -F\| '{print $3}'`
		if [ "$ASSUME_YES" = Y ]; then
			echo "Deleting $r_host.$r_domain - $r_value ($r_line)"
		else
			read -p "Delete $r_host.$r_domain - $r_value ($r_line)? [N/y] " c
			case "$c" in
				y|Y) ;;
				*) continue;;
			esac
		fi
		local api_resp=`__call_dnsapi "https://dnsapi.cn/Record.Remove" \
			"login_token=$DNSAPI_TOKEN&format=json&domain=$r_domain&record_id=$r_id"`
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
		DNSAPI_TOKEN=$login_token
		local domain=`uci -q get dnspod.@dnspod[$i].domain`
		local subdomain=`uci -q get dnspod.@dnspod[$i].subdomain`
		local ipfrom=`uci -q get dnspod.@dnspod[$i].ipfrom`
		if [ "$ipfrom" = auto ]; then
			dnspod_set "$domain" "$subdomain" A
		elif [ -n "$ipfrom" ]; then
			. /lib/functions/network.sh
			network_get_ipaddr ip $ipfrom
			dnspod_set "$domain" "$subdomain" A "$ip"
		fi
	done
}

##
show_help()
{
	cat <<EOF
Usage:
  dnspod-utils.sh [options] set  domain sub_domain type value1 [value2 ...]
  dnspod-utils.sh [options] add  domain sub_domain type value
  dnspod-utils.sh [options] del  domain sub_domain type
  dnspod-utils.sh [options] once          # OpenWrt only
Options:
  -t api_token              DNSPod API token in 'id,key' format
  -d sencods                delayed seconds before any operation
  -D                        use 'Record.Ddns' for update (10s TTL)
  -k                        pass '-k' to curl
  -y                        assume yes for delete
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		-t) shift 1; DNSAPI_TOKEN="$1";;
		-d) shift 1; sleep "$1";;
		-D) DDNS_MODE=Y;;
		-k) CURL_EXTRA_OPTS=-k;;
		-y) ASSUME_YES=Y;;
		-*) echo "*** Invalid option: '$1'" >&2; exit 1;;
		*) break;;
	esac
	shift 1
done

command="$1"; shift 1

if [ -z "$command" ]; then
	show_help
	exit 1
elif [ "$command" = once ]; then
	openwrt_once
	exit 0
elif [ -z "$DNSAPI_TOKEN" ]; then
	echo "*** Missing API token" >&2
	exit 1
fi

case "$command" in
	set) dnspod_set "$@";;
	add) dnspod_add "$@";;
	del) dnspod_del "$@";;
	*) echo "*** Invalid command: '$command'" >&2; exit 1;;
esac
