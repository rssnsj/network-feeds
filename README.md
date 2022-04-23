# network-feeds
Network accelerating extensions for OpenWrt (valuable Pull Requests are welcomed)  

### Components
* ipset-lists: 'ipset' lists with China IP assignments (data from apnic.net)
* minivtun-tools: Fast secure VPN in a custom protocol for rapidly deploying VPN services or getting through firewalls (refer to: [https://github.com/rssnsj/minivtun](https://github.com/rssnsj/minivtun))
* proto-bridge: Protocol-filtered ethernet bridging drivers and a VLAN implementation with compressed VLAN header (YaVLAN)
* file-storage: Toolset for automatically setting up Samba file shares with attached USB storages and SD cards

### Build `minivtun-tools` packages for OpenWrt

    # Download and extract an OpenWrt SDK (take MT7621 for example)
    wget https://downloads.openwrt.org/releases/21.02.0/targets/ramips/mt7621/openwrt-sdk-21.02.0-ramips-mt7621_gcc-8.4.0_musl.Linux-x86_64.tar.xz
    tar axf openwrt-sdk-21.02.0-ramips-mt7621_gcc-8.4.0_musl.Linux-x86_64.tar.xz
    cd openwrt-sdk-21.02.0-ramips-mt7621_gcc-8.4.0_musl.Linux-x86_64
    
    # Place the code under 'package' of the SDK directory
    cd package
    git clone https://github.com/rssnsj/network-feeds.git
    cd -
    
    # Install compile dependencies
    ./script/feeds update
    ./script/feeds install openssl
    make package/openssl/compile V=s -j
    
    # Compile the packages
    make package/ipset-lists/compile V=s -j
    make package/minivtun-tools/compile V=s -j
    
    # Then the packages 'ipset-lists' and 'minivtun-tools' are ready under 'bin/packages/mipsel_24kc/base/'


### Install `minivtun-tools` for OpenWrt

    opkg update
    opkg install dnsmasq-full --force-overwrite
    opkg install ipset-lists_xxxx.ipk minivtun-tools_xxxx.ipk

