# network-feeds
HiWiFi OS系统下的网络加速扩展应用（欢迎提交有价值优化的 Pull Requests）

### 包含的组件
* openssh-redir: “-D”模式下支持透明代理的ssh客户端
* autossh: 自动启动ssh tunnel、填写用户名/密码、自动保活的系统服务，为HiWiFi OS适配
* dnsmasq-salist: 支持域名解析-IP白名单（salist）联动的自定义dnsmasq服务，位于/usr/lib/vanillass/dnsmask
* vanillass-libev: Shadowsocks服务程序（来自：[https://github.com/shadowsocks/shadowsocks-libev](https://github.com/shadowsocks/shadowsocks-libev)），改名是为了防止与HiWiFi修改过的版本冲突
* shadowsocks-tools: 与HiWiFi OS集成的Shadowsocks图形化配置工具

### 如何安装

    mkdir -p /etc/opkg
    # 以下两条根据你的路由器架构选择执行（不要两条都执行）
    echo "src/gz rssnsj http://rssn.cn/roms/hifeeds/ar71xx" > /etc/opkg/rssnsj.conf  # 极1
    echo "src/gz rssnsj http://rssn.cn/roms/hifeeds/ralink" > /etc/opkg/rssnsj.conf  # 极1S(HC5661)、极2、极3
      
    opkg update
    opkg install openssh-redir autossh  dnsmasq-salist vanillass-libev
    opkg install shadowsocks-tools --force-overwrite
      
    rm -f /etc/opkg/rssnsj.conf
