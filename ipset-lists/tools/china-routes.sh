#!/bin/bash -e

#
# Script for generating China IPv4 route table by merging APNIC.net data and IPIP.net data
#

china_routes_apnic() {
	if [ ! -f apnic.txt ]; then
		wget -4 http://ftp.apnic.net/stats/apnic/delegated-apnic-latest -O apnic.txt >&2 || { rm -f apnic.txt; exit 1; }
	fi
	cat apnic.txt | awk -F'|' '
			function tobits(c) { for(n=0; c>=2; c/=2) n++; return 32-n; }
			$2=="CN"&&$3=="ipv4" { printf("%s/%d\n", $4, tobits($5)) }' |
		xargs ./netmask/netmask | awk '{print $1}' | awk -F/ '$2<=24'
}

china_routes_ipip() {
	if [ ! -f ipip.txt ]; then
		wget -4 https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt -O ipip.txt >&2 || { rm -f ipip.txt; exit 1; }
	fi
	cat ipip.txt | xargs ./netmask/netmask | awk '{print $1}' | awk -F/ '$2<=24'
}

china_routes_maxmind() {
	local maxmind_db=GeoLite2-Country-Blocks-IPv4.csv
	if [ ! -f $maxmind_db ]; then
		echo "*** Missing '$maxmind_db'." >&2
		exit 1
	fi
	cat $maxmind_db | awk -F, '$2==1814991 && $3==1814991 {print $1}' |
		xargs ./netmask/netmask | awk '{print $1}' | awk -F/ '$2<=24'
}

china_routes_merged() {
	china_routes_apnic > china.apnic
	china_routes_ipip > china.ipip
	# Merge them together
	cat china.apnic china.ipip | ./ipv4-merger/ipv4-merger | sed 's/\-/:/g' |
		xargs ./netmask/netmask | awk '{print $1}' > china.merged
	cat china.merged
}

# $1: ipset name
convert_routes_to_ipset() {
	local ipset_name="$1"
	echo "create $ipset_name hash:net family inet hashsize 1024 maxelem 65536"
	awk -vt="$ipset_name" '{ printf("add %s %s\n", t, $0) }'
}

inverted_china_routes() {
	(
		echo 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 172.16.0.0/12 192.168.0.0/16 224.0.0.0/3
		echo 169.254.0.0/16 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24
		china_routes_merged
	) | xargs ./netmask/netmask -r | awk '{print $1}' |
		awk -F- '
			function ip2long(ip) { split(ip,arr,"."); n=0; for(i=1;i<=4;i++) n=n*256+arr[i]; return n; }
			function long2ip(n) { a=int(n/16777216); b=int(n%16777216/65536); c=int(n%65536/256); d=n%256; return a "." b "." c "." d; }
			BEGIN { st=0 }
			{ x=st; y=ip2long($1); st=ip2long($2)+1; if(y>x) { print long2ip(x) ":" long2ip(y-1); } }' |
		xargs ./netmask/netmask | awk '{print $1}'
}


##
[ -x ./ipv4-merger/ipv4-merger ] || make -C ipv4-merger >&2
[ -x ./netmask/netmask ] || make -C netmask >&2
##
case "$1" in
	"")
		# ipset
		china_routes_merged | convert_routes_to_ipset china
		;;
	-c)
		china_routes_merged
		;;
	-r)
		inverted_china_routes
		;;
	china_routes_*)
		"$@"
		;;
	*)
		echo "Usage:"
		echo " $0              generate China routes in 'ipset' format"
		echo " $0 -c           generate China routes in IP/prefix format"
		echo " $0 -r           generate invert China routes"
		;;
esac
