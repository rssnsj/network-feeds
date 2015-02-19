#
# Copyright (c) 2015 Justin Liu
# Author: Justin Liu <rssnsj@gmail.com>
# https://github.com/rssnsj/network-feeds
#

CC ?= gcc
CFLAGS += -Wall
HEADERS = p2pcat.h

p2pvtund: p2pvtund.o
	$(CC) $(LDFLAGS) -o $@ $< -lcrypto

%.o: %.c $(HEADERS)
	$(CC) $(CFLAGS) -c -o $@ $<

install: all
	cp -f p2pvtund /usr/sbin/

clean:
	rm -f p2pvtund *.o
