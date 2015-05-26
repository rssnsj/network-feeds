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
ok, json = pcall(require, "json")
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
--  $dnspod_account: DNSPod username (e-mail address)
--  $dnspod_password: DNSPod login password
--  $top_domain: top-level domain name
--  $sub_domain: sub domain name (CAUSIOUS: empty string to set all sub domains)
--  $ip: IP address ('nil' for auto-select IP)
--  $safety_limit: set a small number (1 or 2) to avoid potential
--   damages to the whole domain; 0 for unlimited.
function ddns_set_hostname(dnspod_account, dnspod_password, top_domain, sub_domain, ip, safety_limit)
	local rc = 0
	local msg = ""
	local k, v, m, curl_cmd, reply_msg
	local curl_opts = ""
	local fp

	---- Choose a certificate to use
	local possible_certfiles = { os.getenv("HOME") .. "/etc/cacert.pem",
			"/etc/cacert.pem", "/etc/ca/gd-class2-root.crt" }
	for k, v in pairs(possible_certfiles) do
		if file_exists(v) then
			curl_opts = "--cacert " .. v
			break
		end
	end

	-- 1. Get 'record_id' or id list
	curl_cmd = string.format("curl -k %s -X POST https://dnsapi.cn/Record.List -A '%s' -d 'login_email=%s&login_password=%s&format=json&domain=%s&sub_domain=%s' 2>/dev/null",
			curl_opts, DNSAPI_USERAGENT, dnspod_account, dnspod_password, top_domain, sub_domain)
	fp = io.popen(curl_cmd, "r")
	reply_msg = fp:read("*a")
	fp:close()

	local record_list = json.decode(reply_msg)
	if record_list == nil then
		return 1, "Invalid response: " .. reply_msg
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
				curl_cmd = string.format("curl -k %s -X POST https://dnsapi.cn/Record.Modify -A '%s' -d 'login_email=%s&login_password=%s&format=json&domain=%s&record_id=%s&sub_domain=%s&value=%s&record_type=A&record_line=默认' 2>/dev/null",
					curl_opts, DNSAPI_USERAGENT, dnspod_account, dnspod_password, top_domain, v.id, v.name, ip)
			else
				curl_cmd = string.format("curl -k %s -X POST https://dnsapi.cn/Record.Ddns -A '%s' -d 'login_email=%s&login_password=%s&format=json&domain=%s&record_id=%s&sub_domain=%s&record_type=A&record_line=默认' 2>/dev/null",
					curl_opts, DNSAPI_USERAGENT, dnspod_account, dnspod_password, top_domain, v.id, v.name)
			end
			-- print(curl_cmd)
			fp = io.popen(curl_cmd, "r")
			reply_msg = fp:read("*a")
			fp:close()

			local actual_state = json.decode(reply_msg)
			if actual_state == nil then
				rc = rc + 1
				m = "Invalid response: " .. reply_msg
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
	local account = __c:get_first("dnspod", "dnspod", "account", "(null)")
	local password = __c:get_first("dnspod", "dnspod", "password", "(null)")
	local domain = __c:get_first("dnspod", "dnspod", "domain", "(null)")
	local subdomain = __c:get_first("dnspod", "dnspod", "subdomain", "(null)")
	local ipfrom = __c:get_first("dnspod", "dnspod", "ipfrom", "auto")

	if ipfrom == "wan" then
		-- Get the most possible public IP
		local script_choose_wan_ip = ". /lib/functions/network.sh; network_get_ipaddr ip wan; echo \"$ip\""
		local wanip = io.popen(script_choose_wan_ip):read("*l")
		-- print(wanip)
		rc, msg = ddns_set_hostname(account, password, domain, subdomain, wanip, 1)
	else
		rc, msg = ddns_set_hostname(account, password, domain, subdomain, nil, 1)
	end

	print(msg)
	return rc
end


if arg[1] == "set" and table.getn(arg) >= 6 then
	local rc, msg = ddns_set_hostname(arg[2], arg[3], arg[4], arg[5], arg[6], 0)
	print(msg)
	os.exit(rc)
elseif arg[1] == "set" and table.getn(arg) == 5 then
	local rc, msg = ddns_set_hostname(arg[2], arg[3], arg[4], arg[5], nil, 0)
	print(msg)
	os.exit(rc)
elseif arg[1] == "once" then
	local rc = run_task_once()
	os.exit(rc)
else
	print("Usage:")
	print(" dnspod-utils set <account> <password> <top domain> <sub domain> [bound_ip]")
	print("                             bind a domain name to specific IP")
	print(" dnspod-utils once           run DDNS synchronizing task once")
	os.exit(2)
end

