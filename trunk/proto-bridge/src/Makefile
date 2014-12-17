# Driver module

KERNSRC ?= /lib/modules/$(shell uname -r)/build
CC ?= gcc

obj-m := pppoe_bridge.o 6bridge.o yavlan.o

pppoe_bridge.ko: pppoe_bridge.c
	make -C $(KERNSRC) M=$(shell pwd) modules

6bridge.ko: 6bridge.c
	make -C $(KERNSRC) M=$(shell pwd) modules

yavlan.ko: yavlan.c
	make -C $(KERNSRC) M=$(shell pwd) modules

clean:
	find . \( -name '.tmp_versions' -o -name '*.o' -o -name '*.ko' -o -name '.*.cmd' \
		-o -name '.*.d' -o -name '*.mod.c' -o -name '*.symvers' -o -name '*~' \) -print | xargs rm -fr;
	rm -f modules.order

