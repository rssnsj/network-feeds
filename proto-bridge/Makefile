#
# Copyright (C) Justin Liu, rssnsj@gmail.com
#

include $(TOPDIR)/rules.mk

PKG_NAME:=proto-bridge
PKG_RELEASE:=20150125

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/kernel.mk

define KernelPackage/proto-bridge
  SUBMENU:=Network Support
  TITLE:=Protocol-based bridging modules
  FILES:=$(PKG_BUILD_DIR)/pppoe_bridge.$(LINUX_KMOD_SUFFIX) $(PKG_BUILD_DIR)/6bridge.$(LINUX_KMOD_SUFFIX)
endef
define KernelPackage/proto-bridge/description
 Protocol-based bridging modules
endef

define KernelPackage/yavlan
  SUBMENU:=Network Support
  TITLE:=Yet another VLAN implementation
  FILES:=$(PKG_BUILD_DIR)/yavlan.$(LINUX_KMOD_SUFFIX) $(PKG_BUILD_DIR)/yavlan.$(LINUX_KMOD_SUFFIX)
endef
define KernelPackage/yavlan/description
 Yet another VLAN implementation
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) -av ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(MAKE) -C "$(LINUX_DIR)" CROSS_COMPILE="$(TARGET_CROSS)" \
		ARCH="$(LINUX_KARCH)" SUBDIRS="$(PKG_BUILD_DIR)" \
		EXTRA_CFLAGS="-I$(PKG_BUILD_DIR)/include" \
		modules
endef

$(eval $(call KernelPackage,proto-bridge))
$(eval $(call KernelPackage,yavlan))

