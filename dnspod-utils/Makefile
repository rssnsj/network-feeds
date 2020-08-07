#
# Copyright (c) 2020 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
#

include $(TOPDIR)/rules.mk

PKG_NAME:=dnspod-utils
PKG_VERSION:=20200807
PKG_RELEASE:=

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/dnspod-utils
  CATEGORY:=Network
  TITLE:=DNSPod dynamic DNS support
  MAINTAINER:=Justin Liu <rssnsj@gmail.com>
  DEPENDS:=+uci +curl +jq
endef

define Package/dnspod-utils/conffiles
/etc/config/dnspod
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile/Default

endef
Build/Compile = $(Build/Compile/Default)

define Package/dnspod-utils/install
	$(CP) -a files/* $(1)/
endef

$(eval $(call BuildPackage,dnspod-utils))
