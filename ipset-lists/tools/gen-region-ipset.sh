#!/bin/sh -e

#
# Script for generating country ipset tables with apnic.net official data.
#

SOURCE_FILE_URL="http://ftp.apnic.net/stats/apnic/delegated-apnic-latest"
DATA_FILE=`basename "$SOURCE_FILE_URL"`

check_data_file()
{
	[ -f $DATA_FILE ] || wget "$SOURCE_FILE_URL" -O $DATA_FILE || exit 1
}

# $1: country code in source file
# $2: ipset table name
gen_ipset_to_stdout()
{
	local ctcode="$1"
	local ctname="$2"

	check_data_file

	echo "create $ctname hash:net family inet hashsize 1024 maxelem 65536"

	cat $DATA_FILE | awk -F'|' -vc="$ctcode" '
function tobits(c) {for(n=0;c>=2;c/=2){n++;};return 32-n;}
$2==c&&$3=="ipv4"{printf("%s/%d\n",$4,tobits($5))}' |
	awk -vt="$ctname" '{printf("add %s %s\n",t,$0)}'
}

# $1: country code in source file
# $2: ipset table name
gen_rtable_to_stdout()
{
	local ctcode="$1"

	check_data_file

	cat $DATA_FILE | awk -F'|' -vc="$ctcode" '
function tobits(c) {for(n=0;c>=2;c/=2){n++;};return 32-n;}
$2==c&&$3=="ipv4"{printf("%s/%d\n",$4,tobits($5))}'

}

##
case "$2" in
	-r) cmd=gen_rtable_to_stdout;;
	*)  cmd=gen_ipset_to_stdout;;
esac

case "$1" in
	CN) $cmd $1 china;;
	TW) $cmd $1 taiwan;;
	HK) $cmd $1 hongkong;;
	SG) $cmd $1 singapore;;
	JP) $cmd $1 japan;;
	KR) $cmd $1 korea;;
	*)
		echo "Usage:"
		echo "  $0 <country_code> [-r]"
		echo "Supported countries:"
		echo "  CN, TW, HK, SG, JP, KR"
		echo "Examples:"
		echo "  $0 CN > ../files/etc/ipset/china"
		echo "  $0 TW > ../files/etc/ipset/taiwan"
		;;
esac
