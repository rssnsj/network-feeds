#
# Copyright (C) 2006-2013 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=dnsmasq-salist
PKG_VERSION:=2.71
PKG_RELEASE:=1

PKG_SOURCE:=dnsmasq-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=http://thekelleys.org.uk/dnsmasq
PKG_MD5SUM:=15a68f7f6cc0119e843f67d2f79598f1

PKG_LICENSE:=GPLv2
PKG_LICENSE_FILES:=COPYING

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(BUILD_VARIANT)/dnsmasq-$(PKG_VERSION)

PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/dnsmasq-salist/Default
  SECTION:=net
  CATEGORY:=Network
  TITLE:=A port of dnsmasq with 'ipset' migrated to 'salist'
  URL:=http://www.thekelleys.org.uk/dnsmasq/
##  DEPENDS:=+kmod-salist
endef

define Package/dnsmasq-salist
$(call Package/dnsmasq-salist/Default)
  VARIANT:=nodhcpv6
endef

define Package/dnsmasq-salist/description
  A port of dnsmasq with 'ipset' migrated to 'salist'.
endef

TARGET_CFLAGS += -ffunction-sections -fdata-sections
TARGET_LDFLAGS += -Wl,--gc-sections

COPTS = $(if $(CONFIG_IPV6),,-DNO_IPV6)

ifeq ($(BUILD_VARIANT),nodhcpv6)
	COPTS += -DNO_DHCP6
endif

ifeq ($(BUILD_VARIANT),full)
	COPTS += -DHAVE_DNSSEC
	COPTS += $(if $(CONFIG_LIBNETTLE_MINI),-DNO_GMP,)
else
	COPTS += -DNO_AUTH
endif

MAKE_FLAGS := \
	$(TARGET_CONFIGURE_OPTS) \
	CFLAGS="$(TARGET_CFLAGS)" \
	LDFLAGS="$(TARGET_LDFLAGS)" \
	COPTS="$(COPTS)" \
	PREFIX="/usr"

define Package/dnsmasq-salist/install
	$(INSTALL_DIR) $(1)/usr/lib/vanillass
	$(CP) $(PKG_INSTALL_DIR)/usr/sbin/dnsmasq $(1)/usr/lib/vanillass/dnsmask
endef

$(eval $(call BuildPackage,dnsmasq-salist))
