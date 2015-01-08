#!/bin/sh /etc/rc.common
# Copyright (C) 2014 Justin Liu <rssnsj@gmail.com>

START=21

start()
{
	local file
	for file in /etc/ipset/*; do
		ipset restore < $file
	done
}

stop()
{
	ipset destroy
}

