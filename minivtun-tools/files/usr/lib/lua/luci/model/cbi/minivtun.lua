--[[
 Non-standard VPN that helps you to get through firewalls
 Copyright (c) 2015 Justin Liu
 Author: Justin Liu <rssnsj@gmail.com>
 https://github.com/rssnsj/network-feeds
]]--

local fs = require("nixio.fs")

function ipv4_mask_prefix(mask)
	local a, b, c, d = mask:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)")
	local k, v
	local prefix = 0
	for k, v in pairs({a, b, c, d}) do
		if v == "255" then
			prefix = prefix + 8
		elseif v == "254" then
			prefix = prefix + 7
		elseif v == "252" then
			prefix = prefix + 6
		elseif v == "248" then
			prefix = prefix + 5
		elseif v == "240" then
			prefix = prefix + 4
		elseif v == "224" then
			prefix = prefix + 3
		elseif v == "192" then
			prefix = prefix + 2
		elseif v == "128" then
			prefix = prefix + 1
		end
	end
	return prefix
end

function ipv4_first_ip(ip)
	local a, d = ip:match("^(%d+%.%d+%.%d+%.)(%d+)")
	if tonumber(d) == 1 then
		return tostring(a) .. "2"
	else
		return tostring(a) .. "1"
	end
end

local state_html = ""
local service_on = (luci.sys.call("pidof minivtun >/dev/null && iptables-save | grep minivtun_ >/dev/null") == 0)
if service_on then	
	state_html = "<b><font color=\"green\">" .. translate("Running") .. "</font></b>"
else
	state_html = "<b><font color=\"red\">" .. translate("Not running") .. "</font></b>"
end

local c = luci.model.uci.cursor()
local c_port = c:get_first("minivtun", "minivtun", "server_port", "0")
local c_pwd  = c:get_first("minivtun", "minivtun", "password", "")
local c_lip  = c:get_first("minivtun", "minivtun", "local_ipaddr", "0.0.0.0")
local c_mask = c:get_first("minivtun", "minivtun", "local_netmask", "255.255.255.0")
local c_algo = c:get_first("minivtun", "minivtun", "algorithm", "aes-128")

m = Map("minivtun", translate("Non-standard Virtual Tunneller"),
	translate("Non-standard VPN that helps you to get through firewalls") .. " - " .. state_html .. "<br />" ..
	translate("Add the following commands to <b>/etc/rc.local</b> of your server according to your settings") .. ":<br />" ..
	"<pre>" ..
	"/usr/sbin/minivtun -l 0.0.0.0:<b>" .. c_port .. "</b> -a <b>" ..
		ipv4_first_ip(c_lip) .. "/" .. ipv4_mask_prefix(c_mask) .. "</b>" .. " -n mv0 -e <b>'" ..
		c_pwd .. "'</b> -t <b>" .. c_algo .. "</b> -d\n" ..
	"iptables -t nat -A POSTROUTING ! -o lo -j MASQUERADE   # " .. translate("Ensure NAT is enabled") .. "\n" .. 
	"echo 1 > /proc/sys/net/ipv4/ip_forward\n" ..
	"</pre>")

-- ---------------------------------------------------
s = m:section(TypedSection, "global", translate("Proxy Settings"))
s.anonymous = true

o = s:option(Flag, "enabled", translate("Enable"))
o.rmempty = false

s:option(Flag, "more", translate("More Options"), translate("Options for advanced users"))

o = s:option(ListValue, "proxy_mode", translate("Proxy Mode"),
	translate("GFW-List mode requires flushing DNS cache") .. "<br /> " ..
	"<a href=\"" .. luci.dispatcher.build_url("admin", "services", "gfwlist") .. "\">" ..
	translate("Click here to customize your GFW-List") ..
	"</a>")
o:value("M", translate("GFW-List based auto-proxy"))
o:value("S", translate("All non-China IPs"))
o:value("G", translate("All Public IPs"))
o:value("V", translate("Watching Youku overseas"))
o:depends("more", "1")

o = s:option(Value, "safe_dns", translate("Safe DNS"),
	translate("8.8.8.8 or 8.8.4.4 is recommended"))
o.datatype = "ip4addr"
o.placeholder = "8.8.8.8"
o:depends("more", "1")

o = s:option(Value, "safe_dns_port", translate("Safe DNS Port"))
o.datatype = "range(1,65535)"
o.placeholder = "53"
o:depends("more", "1")

o = s:option(Value, "max_droprate", translate("Maximum allowed packet drop") .. " (%)")
o.datatype = "range(1,100)"
o.placeholder = "100 (" .. translate("unlimited") .. ")"
o:depends("more", "1")

o = s:option(Value, "max_rtt", translate("Maximum allowed latency") .. " (ms)")
o.datatype = "range(1,10000)"
o.placeholder = "0 (" .. translate("unlimited") .. ")"
o:depends("more", "1")

-- ---------------------------------------------------
s = m:section(TypedSection, "minivtun", translate("Tunnellers"))
s.anonymous = true
s.addremove = true
s.template = "cbi/tblsection"

o = s:option(Flag, "enabled", translate("Enable"))
o.rmempty = false

o = s:option(Value, "server", translate("Server Address"))
o.datatype = "host"
o.rmempty = false
o.size = 12

o = s:option(Value, "server_port", translate("Server Port"))
o.datatype = "portrange"
-- o.datatype = "range(1,65535)"
o.rmempty = false
o.size = 10

o = s:option(Value, "password", translate("Password"))
-- o.password = true
o.size = 10

o = s:option(Value, "algorithm", translate("Encryption algorithm"))
o:value("aes-128")
o:value("aes-256")
o:value("des")
o:value("desx")
o:value("rc4")

o = s:option(Value, "local_ipaddr", translate("IPv4 address"))
o.datatype = "ip4addr"
o.size = 10

o = s:option(Value, "local_netmask", translate("IPv4 netmask"))
o.datatype = "ip4addr"
o:value("255.255.255.0")
o:value("255.255.0.0")
o:value("255.0.0.0")

o = s:option(Value, "mtu", translate("MTU"))
o.datatype = "range(1000,65520)"
o.placeholder = "1300"
o.size = 4

-- ---------------------------------------------------
local apply = luci.http.formvalue("cbi.apply")
if apply then
	os.execute("/etc/init.d/minivtun.sh restart >/dev/null 2>&1 &")
end

return m
