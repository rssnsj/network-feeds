include $(TOPDIR)/rules.mk

PKG_NAME:=vanillass-libev
PKG_VERSION:=1.6.2
PKG_RELEASE=$(PKG_SOURCE_VERSION)

PKG_SOURCE_URL:=https://github.com/shadowsocks/shadowsocks-libev/archive
PKG_SOURCE:=v$(PKG_VERSION).tar.gz
PKG_MAINTAINER:=Max Lv <max.c.lv@gmail.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(BUILD_VARIANT)/$(PKG_NAME)-$(PKG_VERSION)

PKG_INSTALL:=1
PKG_FIXUP:=autoreconf
PKG_USE_MIPS16:=0
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/vanillass-libev/Default
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Lightweight Secured Socks5 Proxy
  URL:=https://github.com/madeye/shadowsocks-libev
endef

define Package/vanillass-libev
  $(call Package/vanillass-libev/Default)
  TITLE+= (OpenSSL)
  VARIANT:=openssl
  DEPENDS:=+libopenssl
endef

define Package/vanillass-libev-polarssl
  $(call Package/vanillass-libev/Default)
  TITLE+= (PolarSSL)
  VARIANT:=polarssl
  DEPENDS:=+libpolarssl
endef

define Package/vanillass-libev/description
Shadowsocks-libev is a lightweight secured scoks5 proxy for embedded devices and low end boxes.
endef

Package/vanillass-libev-polarssl/description=$(Package/vanillass-libev/description)

ifeq ($(BUILD_VARIANT),polarssl)
	CONFIGURE_ARGS += --with-crypto-library=polarssl
endif

define Package/vanillass-libev/install
	$(INSTALL_DIR) $(1)/usr/lib/vanillass
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/ss-{local,redir} $(1)/usr/lib/vanillass
endef

Package/vanillass-libev-polarssl/install=$(Package/vanillass-libev/install)

$(eval $(call BuildPackage,vanillass-libev))
$(eval $(call BuildPackage,vanillass-libev-polarssl))
