--[[
Shadowsocks LuCI Configuration Page.
References:
 https://github.com/ravageralpha/my_openwrt_mod  - by RA-MOD
 http://www.v2ex.com/t/139438  - by imcczy
 https://github.com/rssnsj/network-feeds  - by Justin Liu
]]--

local fs = require "nixio.fs"

local state_msg = ""
local ss_redir_on = (luci.sys.call("pidof ss-redir > /dev/null") == 0)
if ss_redir_on then	
	state_msg = "<b><font color=\"green\">" .. translate("Running") .. "</font></b>"
else
	state_msg = "<b><font color=\"red\">" .. translate("Not running") .. "</font></b>"
end

m = Map("shadowsocks", translate("Shadowsocks Transparent Proxy"),
	translate("A fast secure tunnel proxy that help you get through firewalls on your router") .. " - " .. state_msg)

s = m:section(TypedSection, "shadowsocks", translate("Settings"))
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

method = s:taboption("general", ListValue, "method", translate("Encryption Method"))
method:value("table")
method:value("rc4")
method:value("rc4-md5")
method:value("aes-128-cfb")
method:value("aes-192-cfb")
method:value("aes-256-cfb")
method:value("bf-cfb")
method:value("cast5-cfb")
method:value("des-cfb")
method:value("camellia-128-cfb")
method:value("camellia-192-cfb")
method:value("camellia-256-cfb")
method:value("idea-cfb")
method:value("rc2-cfb")
method:value("seed-cfb")

timeout = s:taboption("general", Value, "timeout", translate("Timeout"))
timeout.datatype = "range(0,10000)"
timeout.placeholder = "60"
timeout.optional = false

-- fast_open = s:taboption("general", Flag, "fast_open", translate("TCP Fast Open"),
--	translate("Enable TCP fast open, only available on kernel > 3.7.0"))

proxy_mode = s:taboption("general", ListValue, "proxy_mode", translate("Proxy Scope"))
proxy_mode:value("G", translate("All Public IPs"))
proxy_mode:value("S", translate("All non-China IPs"))
proxy_mode:value("M", translate("GFW-List based auto-proxy"))

safe_dns = s:taboption("general", Value, "safe_dns", translate("Safe DNS"),
	translate("8.8.8.8, 8.8.4.4 will be added by default"))
safe_dns.datatype = "ip4addr"
safe_dns.optional = false

safe_dns_port = s:taboption("general", Value, "safe_dns_port", translate("Safe DNS Port"),
	translate("Foreign DNS on UDP port 53 might be polluted"))
safe_dns_port.datatype = "range(1,65535)"
safe_dns_port.placeholder = "53"
safe_dns_port.optional = false

safe_dns_tcp = s:taboption("general", Flag, "safe_dns_tcp", translate("DNS uses TCP"),
	translate("TCP DNS queries will be done over Shadowsocks tunnel"))
safe_dns_tcp.rmempty = false

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
	os.execute("/etc/init.d/ss-redir.sh restart >/dev/null 2>&1 &")
end

return m
