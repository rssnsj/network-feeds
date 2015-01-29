KERNSRC ?= /lib/modules/$(shell uname -r)/build

obj-m += ip6t_PREFIXDNAT.o

all: ip6t_PREFIXDNAT.ko libip6t_PREFIXDNAT.so

ip6t_PREFIXDNAT.ko: ip6t_PREFIXDNAT.c
	make -C $(KERNSRC) M=$(shell pwd) modules

libip6t_PREFIXDNAT.so: libip6t_PREFIXDNAT.c
	$(CC) -D_REENTRANT -DXTABLES_LIBDIR=\"/lib/xtables\" -DXTABLES_INTERNAL -Wp,-MMD,./.libip6t_PREFIXDNAT.oo.d,-MT,libip6t_PREFIXDNAT.oo -Wall -D_INIT=libip6t_PREFIXDNAT_init -DPIC -fPIC -g -O2 -o libip6t_PREFIXDNAT.oo -c libip6t_PREFIXDNAT.c
	$(CC) -shared  -o libip6t_PREFIXDNAT.so libip6t_PREFIXDNAT.oo

install: all
	cp -vf libip6t_PREFIXDNAT.so /lib/xtables/
	cp -vf ip6t_PREFIXDNAT.ko /lib/modules/$(shell uname -r)/kernel/
	depmod -a

run: install
	ip6tables -t nat -F
	rmmod ip6t_PREFIXDNAT || :
	ip6tables -t nat -A PREROUTING -d 2001:470:fc63:5::/64 -j PREFIXDNAT --to-prefix 2001:470:fc63:5::/96

clean:
	find . \( -name '.tmp_versions' -o -name '*.o' -o -name '*.ko' -o -name '.*.cmd' \
	  -o -name '.*.d' -o -name '*.mod.c' -o -name '*.symvers' -o -name '*~' \) -print | xargs rm -fr;
	rm -f *.so *.oo modules.order
