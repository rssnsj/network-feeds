#
# Copyright (c) 2025 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ipset-lists
PKG_VERSION:=15
PKG_RELEASE:=

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/ipset-lists
  CATEGORY:=Network
  TITLE:=Service for IPSET address tables
  MAINTAINER:=Justin Liu <rssnsj@gmail.com>
  DEPENDS:=+ipset +curl
endef

define Package/ipset-lists/conffiles
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
if [ -e /etc/openwrt_release ]; then
	/etc/init.d/ipset.sh enable || :
fi
endef

$(eval $(call BuildPackage,ipset-lists))
