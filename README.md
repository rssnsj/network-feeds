# network-feeds
Network accelerating extensions for OpenWrt (valuable Pull Requests are welcomed)  

### Components
* ipset-lists: 'ipset' lists with China IP assignments (data from apnic.net)
* minivtun-tools: Fast secure VPN in a custom protocol for rapidly deploying VPN services or getting through firewalls (refer to: [https://github.com/rssnsj/minivtun](https://github.com/rssnsj/minivtun))
* proto-bridge: Protocol-filtered ethernet bridging drivers and a VLAN implementation with compressed VLAN header (YaVLAN)
* file-storage: Toolset for automatically setting up Samba file shares with attached USB storages and SD cards

### How to install

    opkg update
    opkg install dnsmasq-full --force-overwrite
    opkg install ipset-lists_xxxx.ipk minivtun-tools_xxxx.ipk

