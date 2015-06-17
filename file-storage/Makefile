#
# Copyright (c) 2015 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
#

include $(TOPDIR)/rules.mk

PKG_NAME:=file-storage
PKG_VERSION:=20150617
PKG_RELEASE:=

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/file-storage
  CATEGORY:=Network
  TITLE:=Storage device automount and autoconfig scripts
  MAINTAINER:=Justin Liu <rssnsj@gmail.com>
  DEPENDS:=+samba36-server +kmod-usb-storage +kmod-fs-ext4 +kmod-fs-vfat +kmod-nls-cp437 +kmod-nls-iso8859-1 +kmod-nls-utf8 +ntfs-3g
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
	/etc/init.d/samba disable
	/etc/init.d/samba stop
	/etc/init.d/file-storage restart
	/etc/init.d/file-storage enable || :
	/etc/init.d/boot-mount enable || :
fi
endef

$(eval $(call BuildPackage,file-storage))
