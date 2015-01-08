--[[
Shadowsocks LuCI Configuration Page.
References:
 https://github.com/ravageralpha/my_openwrt_mod  - by RA-MOD
 http://www.v2ex.com/t/139438  - by imcczy
 https://github.com/rssnsj/openwrt-feeds  - by Justin Liu
]]--

local fs = require "nixio.fs"

m = Map("shadowsocks", translate("Shadowsocks Client"),
        translatef("A fast tunnel proxy that help you get through firewalls.<br />Here you can setup a Shadowsocks Client on your router, and you should have a remote server."))

s = m:section(TypedSection, "shadowsocks", translate("Settings"))
s.anonymous = true

switch = s:option(Flag, "enabled", translate("Enable"))
switch.rmempty = false

server = s:option(Value, "server", translate("Server Address"))
server.optional = false

server_port = s:option(Value, "server_port", translate("Server Port"))
server_port.datatype = "range(1,65535)"
server_port.optional = false

password = s:option(Value, "password", translate("Password"))
password.password = true

cipher = s:option(ListValue, "method", translate("Cipher Method"))
cipher:value("table")
cipher:value("rc4")
cipher:value("rc4-md5")
cipher:value("aes-128-cfb")
cipher:value("aes-192-cfb")
cipher:value("aes-256-cfb")
cipher:value("bf-cfb")
cipher:value("cast5-cfb")
cipher:value("des-cfb")
cipher:value("camellia-128-cfb")
cipher:value("camellia-192-cfb")
cipher:value("camellia-256-cfb")
cipher:value("idea-cfb")
cipher:value("rc2-cfb")
cipher:value("seed-cfb")

-- timeout = s:option(Value, "timeout", translate("Timeout"))
-- timeout.optional = false

proxy_mode = s:option(ListValue, "proxy_mode", translate("Proxy Mode"))
proxy_mode:value("G")
proxy_mode:value("S")
proxy_mode:value("M")

safe_dns = s:option(Value, "safe_dns", translate("Safe DNS"))
safe_dns.optional = false

safe_dns_port = s:option(Value, "safe_dns_port", translate("Safe DNS Port"))
safe_dns_port.datatype = "range(1,65535)"
safe_dns_port.optional = false

local apply = luci.http.formvalue("cbi.apply")
if apply then
	os.execute("/etc/init.d/ss-redir.sh restart &")
end

return m