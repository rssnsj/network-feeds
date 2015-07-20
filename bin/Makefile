#!/bin/sh

AR71XX_SDK ?= $(HOME)/hc6361/platform
RALINK_SDK ?= $(HOME)/hc5x61/platform

PACKAGE_LIST := autossh-renamed openssh-redir-client dnsmasq-salist vanillass-libev shadowsocks-tools
PACKAGE_DIRS := autossh-renamed openssh-redir dnsmasq-salist vanillass-libev shadowsocks-tools

help:
	@echo "Usage:"
	@echo " make AR71XX | RALINK      compile packages of specified architecture"
	@echo " make cp                   copy package files to current directory"
	@echo " make up                   upload packages to servers"

all: AR71XX RALINK

AR71XX:
	$(foreach d,$(PACKAGE_DIRS),make -C $(AR71XX_SDK) package/$(d)/compile V=s || exit $$?;)

RALINK:
	$(foreach d,$(PACKAGE_DIRS),make -C $(RALINK_SDK) package/$(d)/compile V=s || exit $$?;)

cp: $(AR71XX_SDK)/bin/ar71xx/packages $(RALINK_SDK)/bin/ralink/packages
	mkdir -p ar71xx ralink
	$(foreach p,$(PACKAGE_LIST),cp $(AR71XX_SDK)/bin/ar71xx/packages/$(p)_*_ar71xx.ipk ar71xx/ || exit $$?;)
	cd ar71xx && $(AR71XX_SDK)/scripts/ipkg-make-index.sh . > Packages && gzip -9c Packages > Packages.gz
	$(foreach p,$(PACKAGE_LIST),cp $(RALINK_SDK)/bin/ralink/packages/$(p)_*_ralink.ipk ralink/ || exit $$?;)
	cd ralink && $(RALINK_SDK)/scripts/ipkg-make-index.sh . > Packages && gzip -9c Packages > Packages.gz

clean:
	rm -rf ar71xx ralink

up: cp
	@rsync -rlptD --delete -v ar71xx ralink root@rssn.cn:/www/roms/hifeeds/
	@rsync -rlptD --delete -v ar71xx ralink root@s.rssn.cn:/www/roms/hifeeds/

