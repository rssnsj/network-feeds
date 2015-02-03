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

