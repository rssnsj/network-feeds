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

m = Map("p2pvtun", translate("P2P-based Virtual Tunneller"),
	translatef("Non-standard VPN that helps you to get through firewalls") .. " - " .. state_msg)

s = m:section(TypedSection, "p2pvtun", translate("Settings"))
s.anonymous = true

s:tab("general", translate("General Settings"))
s:tab("gfwlist", translate("Customize Domain Names"))

-- ---------------------------------------------------
switch = s:taboption("general", Flag, "enabled", translate("Enable"))
switch.rmempty = false

server = s:taboption("general", Value, "server", translate("Server Address"))
server.optional = false
server.datatype = "host"
server.rmempty = false

server_port = s:taboption("general", Value, "server_port", translate("Server Port"))
server_port.datatype = "range(1,65535)"
server_port.optional = false
server_port.rmempty = false

password = s:taboption("general", Value, "password", translate("Password"))
password.password = true

local_ipaddr = s:taboption("general", Value, "local_ipaddr", translate("Local Virtual IP"))
local_ipaddr.datatype = "ip4addr"
local_ipaddr.optional = false

remote_ipaddr = s:taboption("general", Value, "remote_ipaddr", translate("Remote Virtual IP"))
remote_ipaddr.datatype = "ip4addr"
remote_ipaddr.optional = false

proxy_mode = s:taboption("general", ListValue, "proxy_mode", translate("Proxy Scope"))
proxy_mode:value("G", translate("All Public IPs"))
proxy_mode:value("S", translate("All non-China IPs"))
proxy_mode:value("M", translate("GFW-List based auto-proxy"))

-- protocols = s:taboption("general", MultiValue, "protocols", translate("Protocols"))
-- protocols:value("T", translate("TCP"))
-- protocols:value("U", translate("UDP"))
-- protocols:value("I", translate("ICMP"))
-- protocols:value("O", translate("Others"))

safe_dns = s:taboption("general", Value, "safe_dns", translate("Safe DNS"))
safe_dns.datatype = "ip4addr"
safe_dns.optional = false

safe_dns_port = s:taboption("general", Value, "safe_dns_port", translate("Safe DNS Port"))
safe_dns_port.datatype = "range(1,65535)"
safe_dns_port.placeholder = "53"
safe_dns_port.optional = false

-- ---------------------------------------------------
glist = s:taboption("gfwlist", Value, "_glist",
	translate("Domain Names"),
	translate("Content of /etc/gfwlist.list which will be used for anti-DNS-pollution and GFW-List based auto-proxy"))
glist.template = "cbi/tvalue"
glist.rows = 24
function glist.cfgvalue(self, section)
	return nixio.fs.readfile("/etc/gfwlist.list")
end
function glist.write(self, section, value)
	value = value:gsub("\r\n?", "\n")
	local old_value = nixio.fs.readfile("/etc/gfwlist.list")
	if value ~= old_value then
		nixio.fs.writefile("/etc/gfwlist.list", value)
	end
end

-- ---------------------------------------------------
local apply = luci.http.formvalue("cbi.apply")
if apply then
	os.execute("/etc/init.d/p2pvtun.sh restart >/dev/null 2>&1 &")
end

return m
