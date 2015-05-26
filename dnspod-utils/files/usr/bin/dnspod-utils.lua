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

ok, json = pcall(require, "json")
if not ok then
	ok, json = pcall(require, "luci.json")
end
if not ok then
	print("*** No 'json' module candidate.")
	os.exit(9)
end

local DNSAPI_USERAGENT = "OpenWrt-DDNS/0.1.0 (rssnsj@gmail.com)"
local DNSPOD_CACHE_DIR = "/tmp/.dnspod/cache"
local DNSPOD_STATUS_FILE = "/tmp/.dnspod/status"

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
--  $max_records: set a small number (1 or 2) to avoid potential
--   damages to the whole domain; 0 for unlimited.
function bind_hostname_to_ip(dnspod_account, dnspod_password, top_domain, sub_domain, ip, max_records)
	local errcode = 0
	local errmsg = ""
	local __errmsg
	local curl_opts = ""

	---- Choose a certificate to use
	local possible_certfiles = { os.getenv("HOME") .. "/etc/cacert.pem",
			"/etc/cacert.pem", "/etc/ca/gd-class2-root.crt" }
	for __k, __cert in pairs(possible_certfiles) do
		if file_exists(__cert) then
			curl_opts = "--cacert " .. __cert
			break
		end
	end

	---- Check current IP with local cache
	local cache_file = DNSPOD_CACHE_DIR .. "/" .. sub_domain .. "." .. top_domain
	mkdirr(DNSPOD_CACHE_DIR)
	-- Check cache only when IP is specified
	if ip then
		if file_exists(cache_file) then
			local __f = io.open(cache_file)
			local __ip_cached = __f:read("*l")
			if ip == __ip_cached then
				return 0, "No modification, ignored."
			end
		end
	end

	-- Do not leave any trash here
	os.remove(cache_file)

	-- Get 'record_id' or id list
	local curl_cmd = string.format("curl -k %s -X POST https://dnsapi.cn/Record.List -A '%s' -d 'login_email=%s&login_password=%s&format=json&domain=%s&sub_domain=%s' 2>/dev/null",
			curl_opts, DNSAPI_USERAGENT, dnspod_account, dnspod_password, top_domain, sub_domain)
	local fp = io.popen(curl_cmd, "r")
	local record_list = json.decode(fp:read("*a"))
	fp:close()

	if tonumber(record_list.status.code) ~= 1 then
		__errmsg = string.format("Failed to query %s.%s: %s (%s)", sub_domain,
				top_domain, record_list.status.code, record_list.status.message)
		return 1, __errmsg
	end

	-- Select "A" or "CNAME" records and process
	local d_count = 0
	for __k, d_record in pairs(record_list.records) do
		-- print(d_record.id .. " " .. d_record.type)
		if d_record.type == "A" or d_record.type == "CNAME" then
			-- ------------------------------------------------
			local curl_cmd
			if ip then
				curl_cmd = string.format("curl -k %s -X POST https://dnsapi.cn/Record.Modify -A '%s' -d 'login_email=%s&login_password=%s&format=json&domain=%s&record_id=%s&sub_domain=%s&value=%s&record_type=A&record_line=默认' 2>/dev/null",
						curl_opts, DNSAPI_USERAGENT, dnspod_account, dnspod_password, top_domain, d_record.id, d_record.name, ip)
			else
				curl_cmd = string.format("curl -k %s -X POST https://dnsapi.cn/Record.Ddns -A '%s' -d 'login_email=%s&login_password=%s&format=json&domain=%s&record_id=%s&sub_domain=%s&record_type=A&record_line=默认' 2>/dev/null",
						curl_opts, DNSAPI_USERAGENT, dnspod_account, dnspod_password, top_domain, d_record.id, d_record.name)
			end
			-- print(curl_cmd)

			local fp = io.popen(curl_cmd, "r")
			local record_modify = json.decode(fp:read("*a"))
			if tonumber(record_modify.status.code) == 1 then
				io.open(cache_file, "w"):write(record_modify.record.value .. "\n")
				__errmsg = string.format("Setting DNS OK: %s.%s -> %s", d_record.name,
						top_domain, record_modify.record.value)
			else
				errcode = errcode + 1
				__errmsg = string.format("Operation failed: %s (%s)",
						record_modify.status.code, record_modify.status.message)
			end
			if errmsg == "" then
				errmsg = __errmsg
			else
				errmsg = errmsg .. "\n" .. __errmsg
			end
			-- ------------------------------------------------

			-- Check record limitation
			d_count = d_count + 1
			if max_records ~= 0 and d_count >= max_records then
				break
			end
		end
	end

	-- Check if at least one record was treated
	if d_count == 0 then
		return 1, "No A or CNAME record matching '" .. sub_domain .. "." .. top_domain .. "'"
	end

	return errcode, errmsg
end

function crontab_task_once()
	-- Translate shell parameters into JSON
	local __cmd = [[
####
F=/etc/default/dnspod.conf
if [ -f $F ]; then
	. $F
else
	echo "*** File '$F' not found." >&2
	exit 9
fi
cat <<EOF
{"account":"$DNSPODACCOUNT","password":"$DNSPODPASSWORD","domain":"$DNSPODDOMAIN",
 "subdomain":"$DNSPODSUBDOMAIN","ipfrom":"$DNSPODIPFROM"}
EOF
]]
	-- print(__cmd)
	local __params = json.decode(io.popen(__cmd):read("*a"))
	if __params == nil then
		return 1
	end
	-- print(__params.account)

	local rc, msg = 0, ""

	if __params.ipfrom == "wan" then
		-- Get the most possible public IP
		local script_choose_wan_ip = [[
####
. /lib/functions/network.sh
network_get_ipaddr public_ip wan
echo "$public_ip"
]]
		local public_ip = io.popen(script_choose_wan_ip):read("*l")
		-- print(public_ip)
		rc, msg = bind_hostname_to_ip(__params.account, __params.password,
				__params.domain, __params.subdomain, public_ip, 1)
	else
		rc, msg = bind_hostname_to_ip(__params.account, __params.password,
				__params.domain, __params.subdomain, nil, 1)
	end

	-- Write error message to file for showing by script:status()
	if rc == 0 then
		os.remove(DNSPOD_STATUS_FILE)
	else
		io.open(DNSPOD_STATUS_FILE, "w"):write(msg .. "\n")
	end
	print(msg)
	return rc
end


if arg[1] == "set" and table.getn(arg) >= 6 then
	local rc, msg = bind_hostname_to_ip(arg[2], arg[3], arg[4], arg[5], arg[6], 0)
	print(msg)
	os.exit(rc)
elseif arg[1] == "set" and table.getn(arg) == 5 then
	local rc, msg = bind_hostname_to_ip(arg[2], arg[3], arg[4], arg[5], nil, 0)
	print(msg)
	os.exit(rc)
elseif arg[1] == "cron" then
	local rc = crontab_task_once()
	os.exit(rc)
else
	print("Usage:")
	print(" dnspod-utils set <account> <password> <top domain> <sub domain> [bound IP]")
	print("                             -- bind a domain name to specified IP")
	print(" dnspod-utils cron           -- run the crontab task once, used by DNSPod App")
	os.exit(2)
end

