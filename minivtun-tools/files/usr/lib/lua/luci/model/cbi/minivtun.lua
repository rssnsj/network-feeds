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

local state_msg = ""
local service_on = (luci.sys.call("pidof minivtun >/dev/null && iptables-save | grep minivtun_ >/dev/null") == 0)
if service_on then	
	state_msg = "<b><font color=\"green\">" .. translate("Running") .. "</font></b>"
else
	state_msg = "<b><font color=\"red\">" .. translate("Not running") .. "</font></b>"
end

local __c = uci.cursor()
local __c_port = __c:get_first("minivtun", "minivtun", "server_port", "0")
local __c_pwd = __c:get_first("minivtun", "minivtun", "password", "")
local __c_net =  __c:get_first("minivtun", "minivtun", "network", "go")
local __c_lip = __c:get_first("minivtun", "minivtun", "local_ipaddr", "0.0.0.0")
local __c_mask = __c:get_first("minivtun", "minivtun", "local_netmask", "255.255.255.0")
local __c_algo = __c:get_first("minivtun", "minivtun", "algorithm", "aes-128")

m = Map("minivtun", translate("Non-standard Virtual Tunneller"),
	translate("Non-standard VPN that helps you to get through firewalls") .. " - " .. state_msg .. "<br />" ..
	translate("Add the following commands to <b>/etc/rc.local</b> of your server according to your settings") .. ":<br />" ..
	"<pre>" ..
	"/usr/sbin/minivtun -l 0.0.0.0:" .. "<b>" .. __c_port .. "</b>" .. " -a " .. "<b>" .. ipv4_first_ip(__c_lip) .. "/" .. ipv4_mask_prefix(__c_mask) .. "</b>" .. " -n minivtun-" .. "<b>" ..__c_net .. "</b>" .. " -e " .. "<b>'" .. __c_pwd .. "'</b>" .. " -t " .. "<b>" .. __c_algo .. "</b>" .. " -d\n" ..
	"iptables -t nat -A POSTROUTING ! -o lo -j MASQUERADE   # " .. translate("Ensure NAT is enabled") .. "\n" .. 
	"echo 1 > /proc/sys/net/ipv4/ip_forward\n" ..
	"</pre>")


s = m:section(TypedSection, "minivtun", translate("Settings"))
s.anonymous = true

-- ---------------------------------------------------
switch = s:option(Flag, "enabled", translate("Enable"))
switch.rmempty = false

server = s:option(Value, "server", translate("Server Address"))
server.optional = false
server.datatype = "host"
server.rmempty = false

server_port = s:option(Value, "server_port", translate("Server Port"))
server_port.datatype = "range(1,65535)"
server_port.optional = false
server_port.rmempty = false

password = s:option(Value, "password", translate("Password"))
password.password = true

algorithm = s:option(Value, "algorithm", translate("Encryption algorithm"))
algorithm:value("aes-128")
algorithm:value("aes-256")
algorithm:value("des")
algorithm:value("desx")
algorithm:value("rc4")

local_ipaddr = s:option(Value, "local_ipaddr", translate("IPv4 address"))
local_ipaddr.datatype = "ip4addr"
local_ipaddr.optional = false

local_netmask = s:option(Value, "local_netmask", translate("IPv4 netmask"))
local_netmask.datatype = "ip4addr"
local_netmask:value("255.255.255.0")
local_netmask:value("255.255.0.0")
local_netmask:value("255.0.0.0")

s:option(Flag, "more", translate("More Options"),
	translate("Options for advanced users"))

proxy_mode = s:option(ListValue, "proxy_mode", translate("Proxy Mode"),
	translate("GFW-List mode requires flushing DNS cache") .. "<br /> " ..
	"<a href=\"" .. luci.dispatcher.build_url("admin", "services", "gfwlist") .. "\">" ..
	translate("Click here to customize your GFW-List") ..
	"</a>")
proxy_mode:value("M", translate("GFW-List based auto-proxy"))
proxy_mode:value("S", translate("All non-China IPs"))
proxy_mode:value("G", translate("All Public IPs"))
proxy_mode:value("V", translate("Watching Youku overseas"))
proxy_mode:depends("more", "1")

-- protocols = s:option(MultiValue, "protocols", translate("Protocols"))
-- protocols:value("T", translate("TCP"))
-- protocols:value("U", translate("UDP"))
-- protocols:value("I", translate("ICMP"))
-- protocols:value("O", translate("Others"))

safe_dns = s:option(Value, "safe_dns", translate("Safe DNS"),
	translate("8.8.8.8 or 8.8.4.4 is recommended"))
safe_dns.datatype = "ip4addr"
safe_dns.optional = false
safe_dns:depends("more", "1")

safe_dns_port = s:option(Value, "safe_dns_port", translate("Safe DNS Port"))
safe_dns_port.datatype = "range(1,65535)"
safe_dns_port.placeholder = "53"
safe_dns_port.optional = false
safe_dns_port:depends("more", "1")

-- ---------------------------------------------------
local apply = luci.http.formvalue("cbi.apply")
if apply then
	os.execute("/etc/init.d/minivtun.sh restart >/dev/null 2>&1 &")
end

return m
