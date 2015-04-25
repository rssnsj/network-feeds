# network-feeds
Network extensions for special applications in OpenWrt package format

### Components
* ipset-lists: 'ipset' lists with China IP assignments (data from apnic.net)
* proto-bridge: Protocol based bridging drivers and Yet another VLAN implementation
* shadowsocks-libev: Shadowsocks - v1.6.2
* shadowsocks-tools: Shadowsocks configuration toolset for OpenWrt
* minivtun-tools: A fast secure VPN service in non-standard protocol for rapidly deploying VPN servers/clients or getting through firewalls

### How to install

##### Installation for 'ar71xx' based routers

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

##### Installation for 'ramips' based routers

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

#### All-in-one firmware for HiWiFi and Xiaomi Mini routers
* HiWiFi HC5661/HC5761: https://github.com/rssnsj/openwrt-hc5761/releases
* HiWiFi HC6361: https://github.com/rssnsj/openwrt-hc6361/releases
* https://github.com/rssnsj/openwrt-xiaomi-mini/releases
