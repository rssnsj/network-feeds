# network-feeds
Network extensions for special applications in OpenWrt package format - adapted for HiWiFi only

### Components
* vanillass-libev: Shadowsocks - v1.6.2, renamed to avoid conficting with HiWiFi official package name
* autossh: Customized 'autossh' service for automatically inputing username and password
* dnsmasq-salist: DNS resolution to salist IP list auto-proxy dnsmasq daemon, placed at /usr/lib/vanillass/dnsmask
* openssh-redir: 'ssh' with tiny modification that enables '-D' tunnelling running in transparent proxy mode
* shadowsocks-tools: Shadowsocks configuration toolset for HiWiFi firmware
