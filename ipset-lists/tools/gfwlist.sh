#!/bin/sh -e

china_banned()
{
	if [ ! -f gfwlist.txt ]; then
		wget https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt -O gfwlist.b64 >&2
		cat gfwlist.b64 | base64 -d > gfwlist.txt
		rm -f gfwlist.b64
	fi

	(
		cat gfwlist.txt |
			sed '/^!/d; /^@@/d; /^$/d; /^#/d' |
			sed 's/!.\+//; s/|//g; s/@//g; s/https\?:\/\///;' |
			sed '/\*/d; /apple\.com/d' |
			sed '/^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$/d' |
			grep '^[0-9a-z\.-]\+$' | grep '\.' | sed 's/^\.\+//'
		cat base-banned.txt
	) | rev | sort -u | awk '
			BEGIN { prev = "___"; }  {
				cur = $0;
				if (!(index(cur, prev) == 1 && substr(cur, 1 + length(prev), 1) == ".")) {
					print cur;
					prev = cur;
				}
			}' |
		rev | sort -u | sed '/^$/d'

}

china_banned
