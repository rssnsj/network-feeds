-- Copyright (C) 2017 zhangzengfei@kunteng.org
-- Licensed to the public under the GNU General Public License v3.

local sys = require "luci.sys"
local opkg = require "luci.model.ipkg"

local packageName = "xkcptun"
local m, s

if not opkg.status(packageName)[packageName] then
	return Map(packageName, translate("Xkcptun"), translate('<b style="color:red">Xkcptun 未安装到当前系统.</b>'))
end

m = Map("xkcptun", translate("xkcptun"), translate("<a target=\"_blank\" href=\"https://github.com/liudf0716/xkcptun\">Xkcptun</a>" .. 
															"是用c语言实现的kcptun，专为openwrt，lede平台开发" ))

s = m:section(TypedSection, "client", translate("客户端配置"))
s.anonymous = true
s.addremove = false

s:tab("general", translate("基本设置"))
s:tab("advanced", translate("高级设置"))

-- 基本设置
Enable = s:taboption("general", Flag, "enable", translate("启用"),translate("启用加速服务"))
Enable.default = Enable.enabled

LocalInterface = s:taboption("general", Value, "localinterface", translate("内网接口"), translate("指定程序监听的网络接口，默认'br-lan'"))
LocalInterface.default = "br-lan"
for _, e in ipairs(sys.net.devices()) do
	if e ~= "lo" then LocalInterface:value(e) end
end

LocalPort = s:taboption("general", Value, "localport", translate("监听端口"), translate("本地监听端口"))
LocalPort.datatype = "port"
LocalPort.rmempty = false

ServerAddr = s:taboption("general", Value, "remoteaddr", translate("服务端地址"), translate("Xkcptun服务端地址"))
ServerAddr.rmempty = false

ServerPort = s:taboption("general", Value, "remoteport", translate("服务器端口"), translate("Xkcptun服务端绑定端口"))
ServerPort.datatype = "port"
ServerPort.rmempty = false

Key = s:taboption("general", Value, "key", translate("会话秘钥"), translate("连接服务端的会话密码"))
Key.rmempty = false

-- 高级设置
MTU = s:taboption("advanced", Value, "mtu", translate("MTU"), translate("maximum transmission unit for UDP packets"))
MTU.datatype = "uinteger"
MTU.placeholder=1350
MTU.rmempty = true

SendWnd = s:taboption("advanced", Value, "sndwnd", translate("sndwnd"), translate("send window size(num of packets)"))
SendWnd.datatype = "uinteger"
SendWnd.placeholder=1024
SendWnd.rmempty = true

RendWnd = s:taboption("advanced", Value, "rcvwnd", translate("rcvwnd"), translate("receive window size(num of packets)"))
RendWnd.datatype = "uinteger"
RendWnd.placeholder=1024
RendWnd.rmempty = true

DataShard = s:taboption("advanced", Value, "datashard", translate("datashard"), translate("reed-solomon erasure coding"))
DataShard.datatype = "uinteger"
DataShard.placeholder=10
DataShard.rmempty = true

Parityshard = s:taboption("advanced", Value, "parityshard", translate("parityshard"), translate("reed-solomon erasure coding"))
Parityshard.datatype = "uinteger"
Parityshard.placeholder=3
Parityshard.rmempty = true

DSCP = s:taboption("advanced", Value, "dscp", translate("dscp"), translate("DSCP(6bit)"))
DSCP.datatype = "uinteger"
DSCP.placeholder=0
DSCP.rmempty = true

NoComp = s:taboption("advanced", Flag, "nocomp", translate("nocomp"), translate("disable compression"))
NoComp.default = NoComp.enabled

AckNodelay = s:taboption("advanced", Flag, "acknodelay", translate("acknodelay"), translate("set ack no delay"))
AckNodelay.default = AckNodelay.disabled

Nodelay = s:taboption("advanced", Flag, "nodelay", translate("nodelay"), translate("set all conn no delay"))
Nodelay.default = Nodelay.disabled

return m