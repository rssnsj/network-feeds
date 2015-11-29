#!/bin/sh -e

#
# Script for generating country ipset tables with apnic.net official data.
#

SOURCE_DOWNLOAD_URL="http://ftp.apnic.net/stats/apnic/delegated-apnic-latest"
LOCAL_SOURCE_TMPFILE=`basename "$SOURCE_DOWNLOAD_URL"`

check_data_file()
{
	if ! [ -f $LOCAL_SOURCE_TMPFILE ]; then
		if which axel >/dev/null 2>&1; then
			axel "$SOURCE_DOWNLOAD_URL" -o $LOCAL_SOURCE_TMPFILE -n16 || exit 1
		else
			wget "$SOURCE_DOWNLOAD_URL" -O $LOCAL_SOURCE_TMPFILE || exit 1
		fi
	fi
}

# $1: country code in source file
generate_cidr_pairs()
{
	local ctcode="$1"

	cat $LOCAL_SOURCE_TMPFILE | awk -F'|' -vc="$ctcode" '
function tobits(c) { for(n=0; c>=2; c/=2) n++; return 32-n; }
$2==c&&$3=="ipv4" { printf("%s/%d\n", $4, tobits($5)) }' |
	xargs netmask | awk '{print $1}'

}

# $1: country code in source file
# $2: ipset table name
generate_ipset_rules()
{
	local ctcode="$1"
	local ctname="$2"

	echo "create $ctname hash:net family inet hashsize 1024 maxelem 65536"
	generate_cidr_pairs "$ctcode" | awk -vt="$ctname" '{ printf("add %s %s\n", t, $0) }'
}

# No argument
generate_inverted_china_routes()
{
	(
		generate_cidr_pairs CN
		echo 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 172.16.0.0/12 192.168.0.0/16 224.0.0.0/5
	) |
	xargs netmask -r | awk '{print $1}' |
	awk -F- '
function iptoint(ip) { split(ip,arr,"."); n=0; for(i=1;i<=4;i++) n=n*256+arr[i]; return n; }
function inttoip(n) { a=int(n/16777216); b=int(n%16777216/65536); c=int(n%65536/256); d=n%256; return a "." b "." c "." d; }
BEGIN { st=0 }
{ x=st; y=iptoint($1); st=iptoint($2)+1; if(y>x) { print inttoip(x) ":" inttoip(y-1); } }' |
	xargs netmask | awk '{print $1}'
}


##
case "$2" in
	-r) cmd=generate_cidr_pairs;;
	*)  cmd=generate_ipset_rules;;
esac

if [ -z "$1" ]; then
	echo "Usage:"
	echo "  $0 <country_code> [-r]"
	echo "Supported countries:"
	echo "  CN, TW, HK, SG, JP, KR"
	echo "Examples:"
	echo "  $0 CN"
	echo "  $0 -u               update the 'china' ipset data"
	echo "  $0 -I               generate inverted China route table"

	exit 1
fi

case "$2" in
	-r) cmd=generate_cidr_pairs;;
	*)  cmd=generate_ipset_rules;;
esac

check_data_file

case "$1" in
	CN) $cmd $1 china;;
	TW) $cmd $1 taiwan;;
	HK) $cmd $1 hongkong;;
	SG) $cmd $1 singapore;;
	JP) $cmd $1 japan;;
	KR) $cmd $1 korea;;
	-u) generate_ipset_rules CN china > china.tmp && mv -v china.tmp ../files/etc/ipset/china;;
	-I) generate_inverted_china_routes;;
	*) echo "*** Invalid arguments." >&2; exit 1;;
esac
