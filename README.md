# network-feeds
OpenWrt下的网络加速扩展应用

### Components
* ipset-lists: 包含所有中国IP地址段的ipset列表（数据来自 apnic.net）
* proto-bridge: 区分协议的以太网桥接驱动，以及一种可压缩VLAN头的非标准VLAN技术（YaVLAN）
* shadowsocks-libev: Shadowsocks - v2.1.4
* shadowsocks-tools: OpenWrt下的Shadowsocks配置、启动脚本以及luci界面
* minivtun-tools: 一种安全、快速、部署便捷的非标准协议VPN，可用于防火墙穿越（服务器配置方法请见：[https://github.com/rssnsj/minivtun](https://github.com/rssnsj/minivtun)）
* file-storage: USB存储、SD卡自动挂载与samba自动配置工具

### 如何安装

    mkdir -p /etc/opkg
    # 以下两条根据你的路由器架构选择执行（不要两条都执行）
    echo "src/gz rssnsj http://rssn.cn/openwrt-feeds/ar71xx" > /etc/opkg/rssnsj.conf  # 基于ar71xx的路由器
    echo "src/gz rssnsj http://rssn.cn/openwrt-feeds/ramips" > /etc/opkg/rssnsj.conf  # 基于ramips的路由器
      
    opkg update
    opkg install dnsmasq-full --force-overwrite
    opkg install ipset-lists shadowsocks-libev shadowsocks-tools minivtun file-storage
    /etc/init.d/uhttpd enable
    /etc/init.d/ipset.sh enable
    /etc/init.d/ss-redir.sh enable
    /etc/init.d/minivtun.sh enable
    /etc/init.d/file-storage enable
      
    reboot

##### 集成本项目的OpenWrt固件（仅支持市面上主流智能路由）
* 极路由HC5661/HC5761/HC5861（极1S/极2/极3）: https://github.com/rssnsj/openwrt-hc5x61/releases
* 极路由HC6361（极1）: https://github.com/rssnsj/openwrt-hc6361/releases
* 小米路由mini: https://github.com/rssnsj/openwrt-xiaomi-mini/releases
