#!/bin/sh /etc/rc.common
# Copyright (C) 2006 OpenWrt.org

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

