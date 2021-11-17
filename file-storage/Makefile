#
# Copyright (c) 2021 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
#

include $(TOPDIR)/rules.mk

PKG_NAME:=file-storage
PKG_VERSION:=20211117
PKG_RELEASE:=

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/file-storage
  CATEGORY:=Network
  TITLE:=Storage device automount and autoconfig scripts
  MAINTAINER:=Justin Liu <rssnsj@gmail.com>
  DEPENDS:=+blkid +kmod-fs-ext4 +kmod-fs-vfat +kmod-usb-storage
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
endef

define Package/file-storage/prerm
#!/bin/sh
[ -L /etc/init.d/samba ] && rm -f /etc/init.d/samba || :
[ -L /etc/config/samba ] && rm -f /etc/config/samba || :
endef

$(eval $(call BuildPackage,file-storage))
