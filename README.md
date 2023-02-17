# network-feeds
Generic Linux-based version

### Installation for Ubuntu

Install the 'uci' utility

    apt-get install build-essential libssl-dev cmake libjson-c-dev ipset dnsmasq
    
    [ -d /usr/include/json ] || ln -s json-c /usr/include/json
    
    git clone http://git.nbd.name/luci2/libubox.git
    cd libubox
    cmake -DBUILD_LUA=off -DCMAKE_INSTALL_PREFIX:PATH=/usr
    make
    sudo make install
    
    git clone https://git.openwrt.org/project/uci.git
    cd uci
    cmake -DBUILD_LUA=off -DCMAKE_INSTALL_PREFIX:PATH=/usr
    make
    sudo make install

