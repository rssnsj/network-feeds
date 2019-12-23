#!/bin/sh -e

china_banned()
{
	if [ ! -f gfwlist.txt ]; then
		wget https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt -O gfwlist.b64 >&2
		cat gfwlist.b64 | base64 -d > gfwlist.txt
		rm -f gfwlist.b64
	fi

	cat gfwlist.txt base-gfwlist.txt | sort -u |
		sed '/^!/d; /^@@/d' |
		sed 's#!.\+##; s#|##g; s#@##g; s#https\?:\/\/##;' |
		sed '/\*/d; /apple\.com/d; /sina\.cn/d; /sina\.com\.cn/d; /baidu\.com/d; /qq\.com/d; /\<jd\.com/d; /\<hiwifi\.com/d;' |
		sed '/^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$/d' |
		grep '^[0-9a-z\.-]\+$' | grep '\.' | sed 's#^\.\+##' | rev | sort -u |
		awk '
BEGIN { prev = "________"; }  {
	cur = $0;
	if (index(cur, prev) == 1 && substr(cur, 1 + length(prev), 1) == ".") {
	} else {
		print cur;
		prev = cur;
	}
}' | rev | sort -u

}

china_banned

