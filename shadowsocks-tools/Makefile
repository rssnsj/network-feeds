#
# Copyright (c) 2015 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
#

include $(TOPDIR)/rules.mk

PKG_NAME:=shadowsocks-tools
PKG_VERSION:=1
PKG_RELEASE:=20150108

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/shadowsocks-tools
  CATEGORY:=Network
  TITLE:=Shadowsocks configuration toolset for OpenWrt
  MAINTAINER:=Justin Liu <rssnsj@gmail.com>
  DEPENDS:=+ipset-lists +shadowsocks-libev +luci
endef

define Package/shadowsocks-tools/conffiles
/etc/config/shadowsocks
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile/Default

endef
Build/Compile = $(Build/Compile/Default)

define Package/shadowsocks-tools/install
	$(CP) -a files/* $(1)/
	mkdir -p $(1)/usr/lib/lua/luci/i18n
	$(BUILD_DIR)/luci/build/po2lmo po/zh_CN/shadowsocks.po $(1)/usr/lib/lua/luci/i18n/shadowsocks.zh-cn.lmo || :
endef

$(eval $(call BuildPackage,shadowsocks-tools))
