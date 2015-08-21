# network-feeds
Network accelerating extensions for OpenWrt (valuable Pull Requests are welcomed)  

### Components
* ipset-lists: 'ipset' lists with China IP assignments (data from apnic.net)
* proto-bridge: Protocol-filtered ethernet bridging drivers and a VLAN implementation with compressed VLAN header (YaVLAN)
* shadowsocks-libev: Shadowsocks binaries
* shadowsocks-tools: Shadowsocks configuration toolset for OpenWrt
* minivtun-tools: Fast secure VPN in a custom protocol for rapidly deploying VPN services or getting through firewalls (refer to: [https://github.com/rssnsj/minivtun](https://github.com/rssnsj/minivtun))
* file-storage: Toolset for auto-setup Samba file shares with attached USB storages and SD cards

### How to install

    mkdir -p /etc/opkg
    # Run the following two lines according to the architecture of your router (DON'T run both)
    echo "src/gz rssnsj http://rssn.cn/roms/feeds/ar71xx" > /etc/opkg/rssnsj.conf  # ar71xx-based
    echo "src/gz rssnsj http://rssn.cn/roms/feeds/ramips" > /etc/opkg/rssnsj.conf  # ramips-based
      
    opkg update
    opkg install dnsmasq-full --force-overwrite
    opkg install ipset-lists shadowsocks-libev shadowsocks-tools minivtun file-storage
      
    rm -f /etc/opkg/rssnsj.conf

##### OpenWrt firmwares with this toolset integrated (only for the major "smart" models)
* HiWiFi HC5661/HC5761/HC5861: https://github.com/rssnsj/openwrt-hc5x61/releases
* HiWiFi HC6361: https://github.com/rssnsj/openwrt-hc6361/releases
* Xiaomi Mini: https://github.com/rssnsj/openwrt-xiaomi-mini/releases
