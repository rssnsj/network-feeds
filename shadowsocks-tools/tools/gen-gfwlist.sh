#!/bin/sh -e

GFWLIST_URL="http://autoproxy-gfwlist.googlecode.com/svn/trunk/gfwlist.txt"

wget "$GFWLIST_URL" -O- | base64 -d > gfwlist.1

cat gfwlist.1 | 
	sed 's#!.\+##; s#|##g; s#@##g; s#http:\/\/##; s#https:\/\/##;' |
	sed '/\*/d; /apple\.com/d; /sina\.cn/d; /sina\.com\.cn/d; /baidu\.com/d' |
	sed '/^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$/d' |
	grep '^[0-9a-zA-Z\.-]\+$' | grep '\.' | sed 's#^\.\+##' | sort -u

rm -f gfwlist.1

