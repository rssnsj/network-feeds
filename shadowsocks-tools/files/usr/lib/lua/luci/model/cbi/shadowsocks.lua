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
method:value("salsa20")
method:value("chacha20")

s:option(Flag, "more", translate("More Options"),
	translate("Options for advanced users"))

timeout = s:option(Value, "timeout", translate("Timeout"))
timeout.datatype = "range(0,10000)"
timeout.placeholder = "60"
timeout.optional = false
timeout:depends("more", "1")

-- fast_open = s:option(Flag, "fast_open", translate("TCP Fast Open"),
--	translate("Enable TCP fast open, only available on kernel > 3.7.0"))

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

safe_dns = s:option(Value, "safe_dns", translate("Safe DNS"),
	translate("8.8.8.8 or 8.8.4.4 is recommended"))
safe_dns.datatype = "ip4addr"
safe_dns.optional = false
safe_dns:depends("more", "1")

safe_dns_port = s:option(Value, "safe_dns_port", translate("Safe DNS Port"),
	translate("Foreign DNS on UDP port 53 might be polluted"))
safe_dns_port.datatype = "range(1,65535)"
safe_dns_port.placeholder = "53"
safe_dns_port.optional = false
safe_dns_port:depends("more", "1")

safe_dns_tcp = s:option(Flag, "safe_dns_tcp", translate("DNS uses TCP"),
	translate("TCP DNS queries will be done over Shadowsocks tunnel"))
safe_dns_tcp.rmempty = false
safe_dns_tcp:depends("more", "1")

-- ---------------------------------------------------
local apply = luci.http.formvalue("cbi.apply")
if apply then
	os.execute("/etc/init.d/ss-redir.sh restart >/dev/null 2>&1 &")
end

return m
