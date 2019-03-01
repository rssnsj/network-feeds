-- Copyright (C) 2016 zhangzf@kunteng.org
-- Licensed to the public under the GNU General Public License v3.

module("luci.controller.xkcptun", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/xkcptun") then
		luci.sys.exec("touch /etc/config/xkcptun")
	end

	entry({"admin", "services", "xkcptun"}, cbi("xkcptun"), _("Xkcptun加速"), 40).index = true
end
