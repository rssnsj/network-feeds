# network-feeds
Network extensions for special applications in OpenWrt package format

### Components
* ipset-lists: 'ipset' lists with China IP assignments (data from apnic.net)
* proto-bridge: Protocol based bridging drivers and Yet another VLAN implementation
* shadowsocks-libev: Shadowsocks binaries
* shadowsocks-tools: Shadowsocks configuration toolset for OpenWrt
* minivtun-tools: A fast secure VPN service in non-standard protocol for rapidly deploying VPN servers/clients or getting through firewalls (for server configration, please refer to: [https://github.com/rssnsj/minivtun](https://github.com/rssnsj/minivtun))
* file-storage: Auto-configuration toolset for mounting USB storage, SD card and configuring Samba server

### How to install

    mkdir -p /etc/opkg
    # Run the following two lines based on your router's architecture (DON'T run both)
    echo "src/gz rssnsj http://rssn.cn/roms/feeds/ar71xx" > /etc/opkg/rssnsj.conf  # ar71xx-based
    echo "src/gz rssnsj http://rssn.cn/roms/feeds/ramips" > /etc/opkg/rssnsj.conf  # ramips-based
      
    opkg update
    opkg install dnsmasq-full --force-overwrite
    opkg install ipset-lists shadowsocks-libev shadowsocks-tools minivtun file-storage
      
    rm -f /etc/opkg/rssnsj.conf

##### OpenWrt firmwares for major smart routers with these toolset integrated
* HiWiFi HC5661/HC5761/HC5861: https://github.com/rssnsj/openwrt-hc5x61/releases
* HiWiFi HC6361: https://github.com/rssnsj/openwrt-hc6361/releases
* Xiaomi Mini: https://github.com/rssnsj/openwrt-xiaomi-mini/releases
