i18n: ipset-lists/files/usr/lib/lua/luci/i18n/gfwlist.zh-cn.lmo \
	minivtun-tools/files/usr/lib/lua/luci/i18n/minivtun.zh-cn.lmo

ipset-lists/files/usr/lib/lua/luci/i18n/gfwlist.zh-cn.lmo: ipset-lists/po/zh_CN/gfwlist.po
	mkdir -p ipset-lists/files/usr/lib/lua/luci/i18n
	po2lmo $< $@
minivtun-tools/files/usr/lib/lua/luci/i18n/minivtun.zh-cn.lmo: minivtun-tools/po/zh_CN/minivtun.po
	mkdir -p minivtun-tools/files/usr/lib/lua/luci/i18n
	po2lmo $< $@

