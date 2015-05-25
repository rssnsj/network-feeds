#
# Copyright (c) 2015 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ipset-lists
PKG_VERSION:=20150525
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
endef

define Package/ipset-lists/postinst
#!/bin/sh
/etc/init.d/ipset-lists start
/etc/init.d/ipset-lists enable
endef

$(eval $(call BuildPackage,ipset-lists))
