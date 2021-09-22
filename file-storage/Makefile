#
# Copyright (c) 2021 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
#

include $(TOPDIR)/rules.mk

PKG_NAME:=file-storage
PKG_VERSION:=20210922
PKG_RELEASE:=

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/file-storage
  CATEGORY:=Network
  TITLE:=Storage device automount and autoconfig scripts
  MAINTAINER:=Justin Liu <rssnsj@gmail.com>
  DEPENDS:=+blkid +kmod-fs-vfat
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

define Package/file-storage/postinst
#!/bin/sh
if [ -e /etc/openwrt_release ]; then
	if [ -f /etc/init.d/samba4 ]; then
		/etc/init.d/samba4 disable
		ln -sf samba4 /etc/init.d/samba
	fi
	if [ -f /etc/config/samba4 ]; then
		ln -sf samba4 /etc/config/samba
	fi
	/etc/init.d/samba stop
	/etc/init.d/samba disable
	/etc/init.d/boot-mount enable || :
fi
endef

$(eval $(call BuildPackage,file-storage))
