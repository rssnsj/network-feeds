--[[
Shadowsocks LuCI Configuration Page.
References:
 https://github.com/ravageralpha/my_openwrt_mod  - by RA-MOD
 http://www.v2ex.com/t/139438  - by imcczy
 https://github.com/rssnsj/openwrt-feeds  - by Justin Liu
]]--

local fs = require "nixio.fs"

m = Map("shadowsocks", translate("Shadowsocks Transparent Proxy"),
	translatef("A fast tunnel proxy that help you get through firewalls.<br />Here you can setup a Shadowsocks Proxy on your router, and you should have a remote server."))

s = m:section(TypedSection, "shadowsocks", translate("Settings"))
s.anonymous = true

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

method = s:option(ListValue, "method", translate("Encryption Method"))
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

timeout = s:option(Value, "timeout", translate("Timeout"))
timeout.datatype = "range(0,10000)"
timeout.placeholder = "60"
timeout.optional = false

proxy_mode = s:option(ListValue, "proxy_mode", translate("Proxy Scope"))
proxy_mode:value("G", translate("All Public IPs"))
proxy_mode:value("S", translate("All non-China IPs"))
proxy_mode:value("M", translate("GFW-list based Smart Proxy"))

safe_dns = s:option(Value, "safe_dns", translate("Safe DNS"),
	translate("8.8.8.8, 8.8.4.4 will be used by default."))
safe_dns.datatype = "ip4addr"
safe_dns.optional = false

safe_dns_port = s:option(Value, "safe_dns_port", translate("Safe DNS Port"),
	translate("Foreign DNS on UDP port 53 might be polluted."))
safe_dns_port.datatype = "range(1,65535)"
safe_dns_port.placeholder = "53"
safe_dns_port.optional = false

safe_dns_tcp = s:option(Flag, "safe_dns_tcp", translate("DNS uses TCP"),
	translate("TCP DNS queries will be done over Shadowsocks tunnel."))
safe_dns_tcp.rmempty = false

local apply = luci.http.formvalue("cbi.apply")
if apply then
	os.execute("/etc/init.d/ss-redir.sh restart &")
end

return m
