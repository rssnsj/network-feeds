#!/usr/bin/lua

--
-- Debugging data:
--
-- https://dnsapi.cn/Record.List
-- {"status":{"code":"1","message":"Action completed successful","created_at":"2014-07-08 17:36:02"},"domain":{"id":"10913415","name":"abc.com","punycode":"abc.com","grade":"DP_Free","owner":"hello@qq.com"},"info":{"sub_domains":"12","record_total":1},"records":[{"id":"74436072","name":"www","line":"\u9ed8\u8ba4","type":"A","ttl":"600","value":"222.222.222.222","mx":"0","enabled":"1","status":"enabled","monitor_status":"","remark":"","updated_on":"2014-07-08 16:38:27","use_aqb":"no"}]}
--
-- https://dnsapi.cn/Record.Modify
-- {"status":{"code":"1","message":"Action completed successful","created_at":"2014-07-08 18:16:08"},"record":{"id":69007534,"name":"a","value":"134.34.34.34","status":"enable"}}
--
local uci = require("luci.model.uci")
local ok, json = pcall(require, "json")
if not ok then
	ok, json = pcall(require, "luci.json")
end
if not ok then
	print("*** No 'json' module candidate.")
	os.exit(9)
end

local DNSAPI_USERAGENT = "OpenWrt-DDNS/0.1.0 (rssnsj@gmail.com)"

function file_exists(filepath)
	local f = io.open(filepath, "r")
	if f then
		f:close()
		return true
	else
		return false
	end
end

function mkdirr(dirpath)
	os.execute("mkdir -p '" .. dirpath .. "' -m777")
end

-- Bind domain name to a specified IP or sync up a domain name
-- with current public IP (seen by DNSPod server)
-- Parameters:
--  $dnspod_token: DNSPod API Tokens (ID,Token; left 'nil' for username/password authentication)
--  $dnspod_account: DNSPod username (e-mail address)
--  $dnspod_password: DNSPod login password
--  $top_domain: top-level domain name
--  $sub_domain: sub domain name (CAUSIOUS: empty string to set all sub domains)
--  $ip: IP address ('nil' for auto-select IP)
--  $safety_limit: set a small number (1 or 2) to avoid potential
--   damages to the whole domain; 0 for unlimited.
function ddns_set_hostname(dnspod_token, dnspod_account, dnspod_password, top_domain, sub_domain, ip, safety_limit)
	local rc = 0
	local msg = ""
	local k, v, m, curl_script, curl_output
	local fp
	local login_parms=""

	if dnspod_token ~= nil then
		login_parms = string.format("login_token=%s", dnspod_token)
	elseif dnspod_account ~= nil and dnspod_password ~= nil then
		login_parms = string.format("login_email=%s&login_password=%s", dnspod_account, dnspod_password)
	else
		return 1, "Neither token or username/password were set."
	end

	-- 1. Get 'record_id' or id list
	curl_script = string.format("curl -k %s -X POST https://dnsapi.cn/Record.List -A '%s' -d '%s&format=json&domain=%s&sub_domain=%s' 2>/dev/null",
			"", DNSAPI_USERAGENT, login_parms, top_domain, sub_domain)
	fp = io.popen(curl_script, "r")
	curl_output = fp:read("*a")
	fp:close()

	local record_list = json.decode(curl_output)
	if record_list == nil then
		return 1, "Invalid response: " .. curl_output
	elseif tonumber(record_list.status.code) ~= 1 then
		m = string.format("Failed to query %s.%s: %s (%s)", sub_domain,
				top_domain, record_list.status.code, record_list.status.message)
		return 1, m
	end

	-- 2. Select corresponding  "A" or "CNAME" record and set it
	local d_count = 0
	for k, v in pairs(record_list.records) do
		-- print(v.id .. " " .. v.type)
		if v.type == "A" or v.type == "CNAME" then
			-- ------------------------------------------------
			if ip then
				curl_script = string.format("curl -k %s -X POST https://dnsapi.cn/Record.Modify -A '%s' -d '%s&format=json&domain=%s&record_id=%s&sub_domain=%s&value=%s&record_type=A&record_line=默认' 2>/dev/null",
					"", DNSAPI_USERAGENT, login_parms, top_domain, v.id, v.name, ip)
			else
				curl_script = string.format("curl -k %s -X POST https://dnsapi.cn/Record.Ddns -A '%s' -d '%s&format=json&domain=%s&record_id=%s&sub_domain=%s&record_type=A&record_line=默认' 2>/dev/null",
					"", DNSAPI_USERAGENT, login_parms, top_domain, v.id, v.name)
			end
			-- print(curl_script)
			fp = io.popen(curl_script, "r")
			curl_output = fp:read("*a")
			fp:close()

			local actual_state = json.decode(curl_output)
			if actual_state == nil then
				rc = rc + 1
				m = "Invalid response: " .. curl_output
			elseif tonumber(actual_state.status.code) == 1 then
				m = "Setting DNS OK: " .. v.name .. "." .. top_domain .. " -> " .. actual_state.record.value
			else
				rc = rc + 1
				m = "Operation failed: " .. actual_state.status.code .. " (" .. actual_state.status.message .. ")"
			end
			if msg == "" then
				msg = m
			else
				msg = msg .. "\n" .. m
			end
			-- ------------------------------------------------

			-- Check record limitation
			d_count = d_count + 1
			if safety_limit ~= 0 and d_count >= safety_limit then
				break
			end
		end
	end

	-- 3. Check if at least one record was treated
	if d_count == 0 then
		return 1, "No A or CNAME record matching '" .. sub_domain .. "." .. top_domain .. "'"
	end

	return rc, msg
end

function run_task_once()
	local __c = uci.cursor()
	local login_token = __c:get_first("dnspod", "dnspod", "login_token", nil)
	local account = __c:get_first("dnspod", "dnspod", "account", nil)
	local password = __c:get_first("dnspod", "dnspod", "password", nil)
	local domain = __c:get_first("dnspod", "dnspod", "domain", "(null)")
	local subdomain = __c:get_first("dnspod", "dnspod", "subdomain", "(null)")
	local ipfrom = __c:get_first("dnspod", "dnspod", "ipfrom", "auto")
	local enabled = __c:get_first("dnspod", "dnspod", "enabled", "0")

	if enabled == "0" then
		print("WARNING: DNSPod is disabled in /etc/config/dnspod.")
		return 1
	end
	if login_token == "" then
		login_token = nil
	end

	if ipfrom == "auto" or ipfrom == "" then
		rc, msg = ddns_set_hostname(login_token, account, password, domain, subdomain, nil, 1)
	else
		-- Get interface IP of the specified network
		local script_choose_wan_ip = ". /lib/functions/network.sh; network_get_ipaddr ip " .. ipfrom .. "; echo \"$ip\""
		local wanip = io.popen(script_choose_wan_ip):read("*l")
		-- print(wanip)
		rc, msg = ddns_set_hostname(login_token, account, password, domain, subdomain, wanip, 1)
	end

	print(msg)
	return rc
end


if arg[1] == "set" and table.getn(arg) == 6 then
	local rc, msg = ddns_set_hostname(nil, arg[2], arg[3], arg[4], arg[5], arg[6], 0)
	print(msg)
	os.exit(rc)
elseif arg[1] == "set" and table.getn(arg) == 5 then
	local rc, msg = ddns_set_hostname(nil, arg[2], arg[3], arg[4], arg[5], nil, 0)
	print(msg)
	os.exit(rc)
elseif arg[1] == "sett" and table.getn(arg) == 5 then
	local rc, msg = ddns_set_hostname(arg[2], nil, nil, arg[3], arg[4], arg[5], 0)
	print(msg)
	os.exit(rc)
elseif arg[1] == "sett" and table.getn(arg) == 4 then
	local rc, msg = ddns_set_hostname(arg[2], nil, nil, arg[3], arg[4], nil, 0)
	print(msg)
	os.exit(rc)
elseif arg[1] == "once" then
	local rc = run_task_once()
	os.exit(rc)
else
	print("Usage:")
	print(" dnspod-utils set <account> <password> <top_domain> <sub_domain> [bound_ip]")
	print("                                 set domain name by username/password")
	print(" dnspod-utils sett <token> <top_domain> <sub_domain> [bound_ip]")
	print("                                 set domain name by DNSPod token")
	print(" dnspod-utils once               run DDNS synchronizing task once")
	os.exit(2)
end

