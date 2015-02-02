#
# Copyright (C) 2006-2011 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=openssh-redir
PKG_VERSION:=6.1p1
PKG_RELEASE:=20150202

PKG_SOURCE:=openssh-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=ftp://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable/ \
		ftp://openbsd.wiretapped.net/pub/OpenBSD/OpenSSH/portable/ \
		ftp://ftp.belnet.be/packages/openbsd/OpenSSH/portable/ \
		ftp://ftp.de.openbsd.org/pub/unix/OpenBSD/OpenSSH/portable/
PKG_MD5SUM:=3345cbf4efe90ffb06a78670ab2d05d5

PKG_BUILD_DEPENDS:=libopenssl

PKG_BUILD_DIR:=$(BUILD_DIR)/openssh-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/openssh-redir/Default
  SECTION:=net
  CATEGORY:=Network
  DEPENDS:=+libopenssl +zlib +SSP_SUPPORT:libssp
  TITLE:=OpenSSH
  MAINTAINER:=Peter Wagner <tripolar@gmx.at>
  URL:=http://www.openssh.com/
  SUBMENU:=SSH
endef

define Package/openssh-redir-client
  $(call Package/openssh-redir/Default)
  TITLE+= client
endef

define Package/openssh-redir-client/description
OpenSSH client.
endef

define Package/openssh-redir-client-utils
  $(call Package/openssh-redir/Default)
  DEPENDS+= +openssh-redir-client +openssh-redir-keygen
  TITLE+= client utilities
endef

define Package/openssh-redir-client-utils/description
OpenSSH client utilities.
endef

define Package/openssh-redir-keygen
  $(call Package/openssh-redir/Default)
  TITLE+= keygen
endef

define Package/openssh-redir-keygen/description
OpenSSH keygen.
endef

CONFIGURE_ARGS+= \
	$(DISABLE_NLS) \
	--sysconfdir=/etc/ssh \
	--with-privsep-user=sshd \
	--with-privsep-path=/var/empty \
	--enable-shared \
	--disable-static \
	--disable-debug \
	--disable-strip \
	--disable-etc-default-login \
	--disable-lastlog \
	--disable-utmp \
	--disable-utmpx \
	--disable-wtmp \
	--disable-wtmpx \
	--without-bsd-auth \
	--without-kerberos5 \
	--without-pam \
	--without-x

ifeq ($(CONFIG_OPENSSL_ENGINE),y)
CONFIGURE_ARGS+= \
	--with-ssl-engine
endif

ifneq ($(CONFIG_SSP_SUPPORT),y)
CONFIGURE_ARGS += \
	--without-stackprotect
endif

CONFIGURE_VARS += LD="$(TARGET_CC)"

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		DESTDIR="$(PKG_INSTALL_DIR)" \
		LIBS="" \
		sftp-server
	$(MAKE) -C $(PKG_BUILD_DIR) \
		DESTDIR="$(PKG_INSTALL_DIR)" \
		STRIP_OPT="" \
		all install
endef

define Package/openssh-redir-client/install
	$(INSTALL_DIR) $(1)/etc/ssh
	chmod 0700 $(1)/etc/ssh
	$(CP) $(PKG_INSTALL_DIR)/etc/ssh/ssh_config $(1)/etc/ssh/
	$(INSTALL_DIR) $(1)/usr/lib/vanillass
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/ssh $(1)/usr/lib/vanillass/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/scp $(1)/usr/lib/vanillass/
endef

define Package/openssh-redir-client-utils/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(foreach bin,add agent keyscan keysign,$(PKG_BUILD_DIR)/ssh-$(bin)) $(1)/usr/bin/
endef

define Package/openssh-redir-keygen/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/ssh-keygen $(1)/usr/bin/
endef

$(eval $(call BuildPackage,openssh-redir-client))
$(eval $(call BuildPackage,openssh-redir-client-utils))
$(eval $(call BuildPackage,openssh-redir-keygen))
