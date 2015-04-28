# network-feeds
OpenWrt下的网络加速扩展应用

### Components
* ipset-lists: 包含所有中国IP地址段的ipset列表（数据来自 apnic.net）
* proto-bridge: 区分协议的以太网桥接驱动，以及一种可压缩VLAN头的非标准VLAN技术（YaVLAN）
* shadowsocks-libev: Shadowsocks - v2.1.4
* shadowsocks-tools: OpenWrt下的Shadowsocks配置、启动脚本以及luci界面
* minivtun-tools: 一种安全、快速、部署便捷的非标准协议VPN，可用于防火墙穿越（服务器配置方法请见：[https://github.com/rssnsj/minivtun](https://github.com/rssnsj/minivtun)）

### 如何安装

##### 基于ar71xx的路由器

    opkg update
    opkg remove dnsmasq; opkg install dnsmasq-full
    opkg install luci libopenssl ipset
    opkg install http://rssn.cn/ar71xx/packages/base/ipset-lists_1-20150425_ar71xx.ipk
    opkg install http://rssn.cn/ar71xx/packages/base/shadowsocks-libev_2.1.4_ar71xx.ipk
    opkg install http://rssn.cn/ar71xx/packages/base/shadowsocks-tools_1-20150108_ar71xx.ipk
    opkg install http://rssn.cn/ar71xx/packages/base/minivtun_20150425-22ce99fd7398a9281fc52cf388dbd5da110e8090_ar71xx.ipk
    rm -f /tmp/luci-indexcache
    /etc/init.d/ipset.sh enable; /etc/init.d/ipset.sh restart
    /etc/init.d/minivtun.sh enable; /etc/init.d/minivtun.sh restart
    /etc/init.d/ss-redir.sh enable; /etc/init.d/ss-redir.sh restart
      
    reboot

##### 基于ramips的路由器

    opkg update
    opkg remove dnsmasq; opkg install dnsmasq-full
    opkg install luci libopenssl ipset
    opkg install http://rssn.cn/ramips/packages/base/ipset-lists_1-20150425_ramips_24kec.ipk
    opkg install http://rssn.cn/ramips/packages/base/shadowsocks-libev_2.1.4_ramips_24kec.ipk
    opkg install http://rssn.cn/ramips/packages/base/shadowsocks-tools_1-20150108_ramips_24kec.ipk
    opkg install http://rssn.cn/ramips/packages/base/minivtun_20150425-22ce99fd7398a9281fc52cf388dbd5da110e8090_ramips_24kec.ipk
    rm -f /tmp/luci-indexcache
    /etc/init.d/ipset.sh enable; /etc/init.d/ipset.sh restart
    /etc/init.d/minivtun.sh enable; /etc/init.d/minivtun.sh restart
    /etc/init.d/ss-redir.sh enable; /etc/init.d/ss-redir.sh restart
      
    reboot

##### 集成本项目的OpenWrt固件（仅支持市面上主流智能路由）
* 极路由HC5661/HC5761（极1S/极2）: https://github.com/rssnsj/openwrt-hc5761/releases
* 极路由HC6361（极1）: https://github.com/rssnsj/openwrt-hc6361/releases
* 小米路由mini: https://github.com/rssnsj/openwrt-xiaomi-mini/releases
