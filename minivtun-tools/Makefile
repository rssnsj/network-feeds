#
# Copyright (c) 2015 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
# https://github.com/rssnsj/network-feeds
#

include $(TOPDIR)/rules.mk

PKG_NAME:=minivtun
PKG_VERSION:=1
PKG_RELEASE:=20150219

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/minivtun
  CATEGORY:=Network
  TITLE:=Non-standard VPN that helps you to get through firewalls
  URL:=https://github.com/rssnsj/network-feeds
  MAINTAINER:=Justin Liu <rssnsj@gmail.com>
  DEPENDS:=+ipset-lists +kmod-tun +libopenssl +luci
endef

define Package/minivtun/conffiles
/etc/config/minivtun
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Package/minivtun/install
	mkdir -p $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/minivtun $(1)/usr/sbin
	$(CP) -a files/* $(1)/
	mkdir -p $(1)/usr/lib/lua/luci/i18n
	$(BUILD_DIR)/luci/build/po2lmo po/zh_CN/minivtun.po $(1)/usr/lib/lua/luci/i18n/minivtun.zh-cn.lmo || :
endef

$(eval $(call BuildPackage,minivtun))

