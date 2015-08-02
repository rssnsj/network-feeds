#!/bin/sh -e

#
# Script for generating country ipset tables with apnic.net official data.
#

SOURCE_FILE_URL="http://ftp.apnic.net/stats/apnic/delegated-apnic-latest"
OUTPUT_LIST_FILE=

# $1: country code in source file
# $2: ipset table name
gen_ipset_to_stdout()
{
	local ctcode="$1"
	local ctname="$2"
	local tmpfile=`basename "$SOURCE_FILE_URL"`

	[ -f $tmpfile  ] || wget "$SOURCE_FILE_URL" -O $tmpfile || return 1

	echo "create $ctname hash:net family inet hashsize 1024 maxelem 65536"

	cat $tmpfile | awk -F'|' -vc="$ctcode" '
function tobits(c) {for(n=0;c>=2;c/=2){n++;};return 32-n;}
$2==c&&$3=="ipv4"{printf("%s/%d\n",$4,tobits($5))}' |
	awk -vt="$ctname" '{printf("add %s %s\n",t,$0)}'
}

gen_apnic_to_file()
{
	local ctcode="$1"
	local ctname="$2"

	[ -n "$OUTPUT_LIST_FILE" ] || OUTPUT_LIST_FILE="../files/etc/ipset/$ctname"

	if [ "$OUTPUT_LIST_FILE" = "-" ]; then
		gen_ipset_to_stdout $ctcode "$ctname"
	else
		gen_ipset_to_stdout $ctcode "$ctname" > "$OUTPUT_LIST_FILE"
	fi
}

##
[ "$2" = "-o" ] && OUTPUT_LIST_FILE="$3" || :
case "$1" in
	CN) gen_apnic_to_file $1 china;;
	TW) gen_apnic_to_file $1 taiwan;;
	HK) gen_apnic_to_file $1 hongkong;;
	SG) gen_apnic_to_file $1 singapore;;
	JP) gen_apnic_to_file $1 japan;;
	KR) gen_apnic_to_file $1 korea;;
	*)
		echo "Usage:"
		echo "  $0 <country_code|carrier_name> [-o output_file]"
		echo "Supported countries:"
		echo "  CN, TW, HK, SG, JP, KR"
		echo "Examples:"
		echo "  $0 CN            written to ../files/etc/ipset/china"
		echo "  $0 TW            written to ../files/etc/ipset/taiwan"
		;;
esac
