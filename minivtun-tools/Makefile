#
# Copyright (c) 2020 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
# https://github.com/rssnsj/network-feeds
#

include $(TOPDIR)/rules.mk

PKG_NAME:=minivtun-tools
PKG_VERSION:=20250408
PKG_RELEASE=$(PKG_SOURCE_VERSION)

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/rssnsj/minivtun.git
PKG_SOURCE_VERSION:=d7007bd8a79eadcd38d8e652dffaca93c2580cd2
PKG_SOURCE:=minivtun-$(PKG_SOURCE_VERSION).tar.bz2

include $(INCLUDE_DIR)/package.mk

define Package/minivtun-tools
  CATEGORY:=Network
  TITLE:=Non-standard VPN that helps you to get through firewalls
  URL:=https://github.com/rssnsj/network-feeds
  MAINTAINER:=Justin Liu <rssnsj@gmail.com>
  DEPENDS:=+ip +ipset-lists +kmod-tun +libopenssl +luci
endef

define Package/minivtun-tools/conffiles
/etc/config/minivtun
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR)/src CC="$(TARGET_CROSS)gcc" \
		CFLAGS="$(TARGET_CPPFLAGS) $(TARGET_CFLAGS)"
endef

define Package/minivtun-tools/install
	mkdir -p $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/minivtun $(1)/usr/sbin
	$(CP) -a files/* $(1)/
endef

define Package/minivtun-tools/postinst
#!/bin/sh
if [ -e /etc/openwrt_release ]; then
	/etc/init.d/minivtun.sh enable || :
	cat /etc/crontabs/root 2>/dev/null | grep -v ' 5 \* \* \*  kill -USR1 .*minivtun-go' > /tmp/tmpcron
	a=`date +%s`
	r=`expr \( $$a + $$$$ \) % 58 + 1`
	echo "$$r"' 5 * * *  kill -USR1 `cat /var/run/minivtun-go*.pid`' > /tmp/tmpcron.add
	echo "Added crontab task for resetting dynamic route each day:"
	cat /tmp/tmpcron.add
	cat /tmp/tmpcron.add >> /tmp/tmpcron
	crontab -u root /tmp/tmpcron
	rm -f /tmp/tmpcron*
	/etc/init.d/cron reload
fi
endef

define Package/minivtun-tools/prerm
#!/bin/sh
if [ -e /etc/openwrt_release ]; then
	cat /etc/crontabs/root | grep -v ' 5 \* \* \*  kill -USR1 .*minivtun-go' > /tmp/tmpcron
	crontab -u root /tmp/tmpcron
	rm -f /tmp/tmpcron
fi
endef

$(eval $(call BuildPackage,minivtun-tools))
