--[[
 Customize /etc/gfwlist.list content
 Copyright (c) 2015 Justin Liu
 Author: Justin Liu <rssnsj@gmail.com>
 https://github.com/rssnsj/network-feeds
]]--

local fs = require "nixio.fs"

function sync_value_to_file(value, file)
	value = value:gsub("\r\n?", "\n")
	local old_value = nixio.fs.readfile(file)
	if value ~= old_value then
		nixio.fs.writefile(file, value)
	end
end

m = SimpleForm("gfwlist", translate("Proxy Domains"))

-- ---------------------------------------------------
glist = m:field(TextValue, "gfwlist", nil,
	translate("Content of /etc/gfwlist.list which will be used for anti-DNS-pollution and GFW-List based auto-proxy"))
glist.rmempty = false
glist.rows = 24

function glist.cfgvalue()
	return nixio.fs.readfile("/etc/gfwlist.list") or ""
end
function glist.write(self, section, value)
	sync_value_to_file(value, "/etc/gfwlist.list")
end

-- ---------------------------------------------------
-- ipchn = m:field(TextValue, "ipchn", translate("China IPSet"))
-- ipchn.rmempty = false
-- ipchn.rows = 20
-- function ipchn.cfgvalue()
-- 	return nixio.fs.readfile("/etc/ipset/china.ipset") or ""
-- end
-- function ipchn.write(self, section, value)
-- 	sync_value_to_file(value, "/etc/ipset/china.ipset")
-- end

return m
