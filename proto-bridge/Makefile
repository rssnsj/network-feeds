#
# Copyright (c) 2021 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
# https://github.com/rssnsj/network-feeds
#

include $(TOPDIR)/rules.mk

PKG_NAME:=proto-bridge
PKG_VERSION:=20220727
PKG_RELEASE=$(PKG_SOURCE_VERSION)

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.bz2
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE_URL:=https://github.com/rssnsj/proto-bridge.git
PKG_SOURCE_PROTO:=git
PKG_SOURCE_VERSION:=10068ead58d3619e599b2f34f0c1fc173adca8cf

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/kernel.mk

define KernelPackage/proto-bridge
  SUBMENU:=Network Support
  TITLE:=Protocol-based bridging modules
  URL:=https://github.com/rssnsj/proto-bridge
  FILES:=$(PKG_BUILD_DIR)/src/pppoe_bridge.$(LINUX_KMOD_SUFFIX) $(PKG_BUILD_DIR)/src/6bridge.$(LINUX_KMOD_SUFFIX)
endef
define KernelPackage/proto-bridge/description
 Protocol-based bridging modules for PPPoE bridge & IPv6 bridge
endef

define KernelPackage/yavlan
  SUBMENU:=Network Support
  TITLE:=Yet another VLAN implementation
  URL:=https://github.com/rssnsj/proto-bridge
  FILES:=$(PKG_BUILD_DIR)/src/yavlan.$(LINUX_KMOD_SUFFIX)
endef
define KernelPackage/yavlan/description
 Yet another VLAN implementation
endef

define Build/Compile
	$(MAKE) -C "$(LINUX_DIR)" CROSS_COMPILE="$(TARGET_CROSS)" ARCH="$(LINUX_KARCH)" \
		SUBDIRS="$(PKG_BUILD_DIR)/src" M="$(PKG_BUILD_DIR)/src" \
		modules
endef

$(eval $(call KernelPackage,proto-bridge))
$(eval $(call KernelPackage,yavlan))

