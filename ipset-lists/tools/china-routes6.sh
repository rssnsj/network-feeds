#!/bin/bash -e

#
# Script for generating China IPv4 route table by merging APNIC.net data and IPIP.net data
#

china_routes_apnic() {
	[ -f apnic.txt ] || exit 1
	cat apnic.txt | \
		awk -F\| '$2=="CN"&&$3=="ipv6" { printf("%s/%d\n", $4, $5) }' |
		awk '{print $1}'
}

china_routes_merged() {
	china_routes_apnic
}

# $1: ipset name
convert_routes_to_ipset() {
	local ipset_name="$1"
	echo "create $ipset_name hash:net family inet6 hashsize 1024 maxelem 65536"
	awk -vt="$ipset_name" '{ printf("add %s %s\n", t, $0) }'
}

##
case "$1" in
	"")
		# ipset
		china_routes_merged | convert_routes_to_ipset china6
		;;
	-c)
		china_routes_merged
		;;
	*)
		echo "Usage:"
		echo " $0              generate China routes in ipset format"
		echo " $0 -c           generate China routes in IP/prefix format"
		;;
	*)
esac
