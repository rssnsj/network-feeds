# Driver module

KERNSRC ?= /lib/modules/$(shell uname -r)/build
CC      ?= gcc

##EXTRA_CFLAGS = -g

obj-m := tayga.o
tayga-objs := netdev.o nat64.o params.o addrmap.o

tayga.ko: netdev.c tayga.h nat64.c params.c addrmap.c
	make -C $(KERNSRC) M=$(shell pwd) modules

clean:
	find . \( -name '.tmp_versions' -o -name '*.o' -o -name '*.ko' -o -name '.*.cmd' \
		-o -name '.*.d' -o -name '*.mod.c' -o -name '*.symvers' -o -name '*~' \) -print | xargs rm -fr;
	rm -f modules.order

install: tayga.ko
	cp -f tayga.ko /lib/modules/$(shell uname -r)/kernel/
	depmod

run: tayga.ko
	@echo 8 > /proc/sys/kernel/printk
	@ifdown nat64 || :
	@rmmod tayga.ko || :
	insmod tayga.ko ipv6_addr=2001:470:ef40:5:ff::2 ipv4_addr=10.41.0.2 \
	  prefix=2001:470:ef40:5::/96 dynamic_pool=10.40.0.0/16
	@ifup nat64
	@while true; do dmesg -c; sleep 0.1; done
#	@exec tcpdump -ni nat64

