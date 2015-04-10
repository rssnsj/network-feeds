#
# Copyright (c) 2015 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
# https://github.com/rssnsj/network-feeds
#

include $(TOPDIR)/rules.mk

PKG_NAME:=minivtun
PKG_VERSION:=20150410
PKG_RELEASE=$(PKG_SOURCE_VERSION)

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.bz2
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE_URL:=https://github.com/rssnsj/minivtun.git
PKG_SOURCE_PROTO:=git
PKG_SOURCE_VERSION:=aec3ca5f7a152a8550756d85f7fa900dfb4f09f6

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

#define Build/Prepare
#	mkdir -p $(PKG_BUILD_DIR)
#	$(CP) ./src/* $(PKG_BUILD_DIR)/
#endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR)/src $(MAKE_OPTS)
endef

define Package/minivtun/install
	mkdir -p $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/minivtun $(1)/usr/sbin
	$(CP) -a files/* $(1)/
	mkdir -p $(1)/usr/lib/lua/luci/i18n
	$(BUILD_DIR)/luci/build/po2lmo po/zh_CN/minivtun.po $(1)/usr/lib/lua/luci/i18n/minivtun.zh-cn.lmo || :
endef

$(eval $(call BuildPackage,minivtun))

