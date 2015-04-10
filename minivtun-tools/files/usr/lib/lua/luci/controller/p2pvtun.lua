--[[
 Non-standard VPN that helps you to get through firewalls
 Copyright (c) 2015 Justin Liu
 Author: Justin Liu <rssnsj@gmail.com>
 https://github.com/rssnsj/network-feeds
]]--

module("luci.controller.p2pvtun", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/p2pvtun") then
		return
	end

	local page
	page = entry({"admin", "services", "p2pvtun"}, cbi("p2pvtun"), _("P2P Virtual Tunneller"))
	page.dependent = true
end
