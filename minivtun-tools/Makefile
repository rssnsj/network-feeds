#
# Copyright (c) 2015 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
# https://github.com/rssnsj/network-feeds
#

include $(TOPDIR)/rules.mk

PKG_NAME:=minivtun
PKG_VERSION:=20151110
PKG_RELEASE=$(PKG_SOURCE_VERSION)

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.bz2
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE_URL:=https://github.com/rssnsj/minivtun.git
PKG_SOURCE_PROTO:=git
PKG_SOURCE_VERSION:=a82f23246b2a87ca86689b28c81d016539958c19

include $(INCLUDE_DIR)/package.mk

define Package/minivtun
  CATEGORY:=Network
  TITLE:=Non-standard VPN that helps you to get through firewalls
  URL:=https://github.com/rssnsj/network-feeds
  MAINTAINER:=Justin Liu <rssnsj@gmail.com>
  DEPENDS:=+ip +ipset-lists +kmod-tun +libopenssl +luci
endef

define Package/minivtun/conffiles
/etc/config/minivtun
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR)/src CC="$(TARGET_CROSS)gcc" \
		CFLAGS="$(TARGET_CPPFLAGS) $(TARGET_CFLAGS)"
endef

define Package/minivtun/install
	mkdir -p $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/minivtun $(1)/usr/sbin
	$(CP) -a files/* $(1)/
endef

define Package/minivtun/postinst
#!/bin/sh
if [ -e /etc/openwrt_release ]; then
	/etc/init.d/minivtun.sh enable || :
fi
endef

$(eval $(call BuildPackage,minivtun))

