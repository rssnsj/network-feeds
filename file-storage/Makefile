#
# Copyright (c) 2015 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
#

include $(TOPDIR)/rules.mk

PKG_NAME:=file-storage
PKG_VERSION:=20150522
PKG_RELEASE:=

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/file-storage
  CATEGORY:=Network
  TITLE:=Storage device automount and autoconfig scripts
  MAINTAINER:=Justin Liu <rssnsj@gmail.com>
  DEPENDS:=+samba36-server
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile/Default

endef
Build/Compile = $(Build/Compile/Default)

define Package/file-storage/install
	$(CP) -a files/* $(1)/
endef

$(eval $(call BuildPackage,file-storage))
