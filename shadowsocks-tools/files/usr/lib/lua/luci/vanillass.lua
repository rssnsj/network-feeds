--[[
Shadowsocks - Shadowsocks configuration interface
Author: Justin <rssnsj@gmail.com>
Copyright: 2014
]]--

local os, io, print, tostring, tonumber, string = os, io, print, tostring, tonumber, string
local luci = require "luci"
local ok, json = pcall(require, "hiwifi.json")
if not ok then
	ok, json = pcall(require, "json")
end
if not ok then
	ok, json = pcall(require, "luci.json")
end
if not ok then
	print("*** No 'json' module candidate.")
	os.exit(9)
end

module "luci.vanillass"

-- -------------------------------------------------

function is_shadowsocks_on()
	local rc = os.execute([[
if iptables-save | grep 'shadowsocks_pre.*REDIRECT' >/dev/null && pidof ss-redir >/dev/null; then
	exit 0
else
	exit 1
fi
]])
	if rc == 0 then
		return true
	else
		return false
	end
end

function is_shadowsocks_en()
	if os.execute("/etc/init.d/vanillass enabled") == 0 then
		return true
	else
		return false
	end
end

-- -------------------------------------------------

function do_ss_save_params()
	local ss_server_addr = tostring(luci.http.formvalue("SS_SERVER_ADDR"))
	local ss_server_port = tonumber(luci.http.formvalue("SS_SERVER_PORT"))
	local ss_server_passwd = tostring(luci.http.formvalue("SS_SERVER_PASSWORD"))
	local ss_server_method = tostring(luci.http.formvalue("SS_SERVER_METHOD"))
	local safe_dns_server = tostring(luci.http.formvalue("SAFE_DNS_SERVER"))
	local safe_dns_port = tonumber(luci.http.formvalue("SAFE_DNS_PORT"))
	local ss_mode = tonumber(luci.http.formvalue("SS_MODE"))
	local __safe_dns_addr = ""

	local failure_msg = nil

	if not string.match(ss_server_addr, '^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$') and
		not string.match(ss_server_addr, '^[A-Za-z0-9_:\.-]\+$') then
		failure_msg = "配置错误：无效的服务器IP地址或域名"
	elseif ss_server_port == nil then
		failure_msg = "配置错误：无效的服务器端口号"
	elseif ss_server_method == "" then
		failure_msg = "配置错误：无效的加密类型"
	elseif safe_dns_server ~= "" and
		not string.match(safe_dns_server, '^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$') and
		not string.match(safe_dns_server, '^[0-9a-f:\.]\+$') then
		failure_msg = "配置错误：无效的DNS服务器IP"
	end

	if safe_dns_server ~= "" then
		if safe_dns_port == nil or safe_dns_port <= 0 or safe_dns_port > 65535 then
			safe_dns_port = 53
		end
		__safe_dns_addr = safe_dns_server .. "#" .. safe_dns_port
	end

	local code, msg, status = 0, "", ""
	if failure_msg then
		code = -1
		msg = failure_msg
		status = "stopped"
	else
		-- Write configuration to file
		os.execute("mkdir -p /etc/default")
		local fp = io.open("/etc/default/ss-redir.defs.sh", "w")
		fp:write(string.format([[
SS_SERVER_ADDR='%s'
SS_SERVER_PORT='%d'
SS_SERVER_PASSWORD='%s'
SS_SERVER_METHOD='%s'
SAFE_DNS_SERVER='%s'
SS_MODE='%s'
]], ss_server_addr, ss_server_port, ss_server_passwd, ss_server_method, __safe_dns_addr, ss_mode))
		fp:close()

		if is_shadowsocks_en() or is_shadowsocks_on() then
			if os.execute("/etc/init.d/vanillass restart") == 0 then
				code = 0
				msg = "OK"
			else
				code = -1
				msg = "配置成功，但启动失败"
			end
		else
			code = 0
			msg = "OK"
		end
	end

	if is_shadowsocks_on() then
		status = "running"
	else
		status = "stopped"
	end

	print("{\"code\":\"" .. code .. "\", \"msg\":\"" .. msg .. "\", \"status\":\"" .. status .. "\"}")
end

function do_ss_get_status()
	if is_shadowsocks_on() then
		print("{\"status\":\"running\"}")
	else
		print("{\"status\":\"stopped\"}")
	end
end

function do_ss_start()
	os.execute("/etc/init.d/vanillass start || exit 1; /etc/init.d/vanillass enable || :")
	if is_shadowsocks_on() then
		print("{\"status\":\"running\"}")
	else
		print("{\"status\":\"stopped\"}")
	end
end

function do_ss_stop()
	os.execute("/etc/init.d/vanillass stop; /etc/init.d/vanillass disable")
	if is_shadowsocks_on() then
		print("{\"status\":\"running\"}")
	else
		print("{\"status\":\"stopped\"}")
	end
end

function get_params_in_table()
	-- Translate shell parameters into JSON
	local __cmd = [[
###
[ -f /etc/default/ss-redir.defs.sh ] && . /etc/default/ss-redir.defs.sh
SAFE_DNS_PORT=`echo "$SAFE_DNS_SERVER" | awk -F'#' '{print $2}'`
SAFE_DNS_SERVER=`echo "$SAFE_DNS_SERVER" | awk -F'#' '{print $1}'`
cat <<EOF
{"SS_SERVER_ADDR":"$SS_SERVER_ADDR","SS_SERVER_PORT":"$SS_SERVER_PORT","SS_SERVER_PASSWORD":"$SS_SERVER_PASSWORD",
 "SS_SERVER_METHOD":"$SS_SERVER_METHOD","SAFE_DNS_SERVER":"$SAFE_DNS_SERVER","SAFE_DNS_PORT":"$SAFE_DNS_PORT",
 "SS_MODE":"$SS_MODE"}
EOF
]]
	return json.decode(io.popen(__cmd):read("*a"))
end

