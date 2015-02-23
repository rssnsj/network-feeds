--[[
 Non-standard VPN that helps you to get through firewalls
 Copyright (c) 2015 Justin Liu
 Author: Justin Liu <rssnsj@gmail.com>
 https://github.com/rssnsj/network-feeds
]]--

local fs = require "nixio.fs"

local state_msg = ""
local service_on = (luci.sys.call("pidof p2pvtund >/dev/null && iptables-save | grep p2pvtun_ >/dev/null") == 0)
if service_on then	
	state_msg = "<b><font color=\"green\">" .. translate("Running") .. "</font></b>"
else
	state_msg = "<b><font color=\"red\">" .. translate("Not running") .. "</font></b>"
end

local __c = uci.cursor()
local __c_port = "<b>" .. __c:get_first("p2pvtun", "p2pvtun", "server_port", "(null)") .. "</b>"
local __c_lip = "<b>" .. __c:get_first("p2pvtun", "p2pvtun", "local_ipaddr", "(null)") .. "</b>"
local __c_rip = "<b>" .. __c:get_first("p2pvtun", "p2pvtun", "remote_ipaddr", "(null)") .. "</b>"
local __c_pwd = "<b>" .. __c:get_first("p2pvtun", "p2pvtun", "password", "(null)") .. "</b>"
local __c_net = "<b>" .. __c:get_first("p2pvtun", "p2pvtun", "network", "go") .. "</b>"

m = Map("p2pvtun", translate("P2P-based Virtual Tunneller"),
	translate("Non-standard VPN that helps you to get through firewalls") .. " - " .. state_msg .. "<br />" ..
	translate("Add the following commands to <b>/etc/rc.local</b> of your server according to your settings") .. ":<br />" ..
	"<pre>" ..
	"/usr/sbin/p2pvtund -l 0.0.0.0:" .. __c_port .. " -a " .. __c_rip .. "/" .. __c_lip .. " -n p2pvtun-" .. __c_net .. " -e '" .. __c_pwd .. "' -d\n" ..
	"iptables -t nat -A POSTROUTING ! -o lo -j MASQUERADE   # Ensure NAT is enabled\n" .. 
	"echo 1 > /proc/sys/net/ipv4/ip_forward\n" ..
	"</pre>")


s = m:section(TypedSection, "p2pvtun", translate("Settings"))
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

local_ipaddr = s:option(Value, "local_ipaddr", translate("Local Virtual IP"))
local_ipaddr.datatype = "ip4addr"
local_ipaddr.optional = false

remote_ipaddr = s:option(Value, "remote_ipaddr", translate("Remote Virtual IP"))
remote_ipaddr.datatype = "ip4addr"
remote_ipaddr.optional = false

proxy_mode = s:option(ListValue, "proxy_mode", translate("Proxy Scope"))
proxy_mode:value("G", translate("All Public IPs"))
proxy_mode:value("S", translate("All non-China IPs"))
proxy_mode:value("M", translate("GFW-List based auto-proxy"))

-- protocols = s:option(MultiValue, "protocols", translate("Protocols"))
-- protocols:value("T", translate("TCP"))
-- protocols:value("U", translate("UDP"))
-- protocols:value("I", translate("ICMP"))
-- protocols:value("O", translate("Others"))

safe_dns = s:option(Value, "safe_dns", translate("Safe DNS"))
safe_dns.datatype = "ip4addr"
safe_dns.optional = false

safe_dns_port = s:option(Value, "safe_dns_port", translate("Safe DNS Port"))
safe_dns_port.datatype = "range(1,65535)"
safe_dns_port.placeholder = "53"
safe_dns_port.optional = false

-- ---------------------------------------------------
local apply = luci.http.formvalue("cbi.apply")
if apply then
	os.execute("/etc/init.d/p2pvtun.sh restart >/dev/null 2>&1 &")
end

return m
