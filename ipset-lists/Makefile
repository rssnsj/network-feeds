#
# Copyright (c) 2015 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ipset-lists
PKG_VERSION:=20150510
PKG_RELEASE:=

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/ipset-lists
  CATEGORY:=Network
  TITLE:=Service for IPSET address tables
  MAINTAINER:=Justin Liu <rssnsj@gmail.com>
  DEPENDS:=+ipset +luci
endef

define Package/ipset-lists/conffiles
/etc/gfwlist/china-banned
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile/Default

endef
Build/Compile = $(Build/Compile/Default)

define Package/ipset-lists/install
	$(CP) -a files/* $(1)/
	mkdir -p $(1)/usr/lib/lua/luci/i18n
	$(BUILD_DIR)/luci/build/po2lmo po/zh_CN/gfwlist.po $(1)/usr/lib/lua/luci/i18n/gfwlist.zh-cn.lmo || :
endef

$(eval $(call BuildPackage,ipset-lists))
