--[[
 Non-standard VPN that helps you to get through firewalls
 Copyright (c) 2015 Justin Liu
 Author: Justin Liu <rssnsj@gmail.com>
 https://github.com/rssnsj/network-feeds
]]--

module("luci.controller.minivtun", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/minivtun") then
		return
	end

	local page
	page = entry({"admin", "services", "minivtun"}, cbi("minivtun"), _("Mini Virtual Tunneller"))
	page.dependent = true
end
