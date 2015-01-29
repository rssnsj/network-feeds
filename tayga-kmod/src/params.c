/*
 *  conffile.c -- config file parser
 *
 *  part of TAYGA <http://www.litech.org/tayga/>
 *  Copyright (C) 2010  Nathan Lutchansky <lutchann@litech.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 */

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/inet.h>

#include "tayga.h"

struct config gcfg;

int validate_ip4_addr(const struct in_addr *a)
{
	/* First octet == 0 */
	if (!(a->s_addr & htonl(0xff000000)))
		return -1;

	/* First octet == 127 */
	if ((a->s_addr & htonl(0xff000000)) == htonl(0x7f000000))
		return -1;

	/* Link-local block 169.254.0.0/16 */
	if ((a->s_addr & htonl(0xffff0000)) == htonl(0xa9fe0000))
		return -1;

	/* Class D & E */
	if ((a->s_addr & htonl(0xe0000000)) == htonl(0xe0000000))
		return -1;

	return 0;
}

int validate_ip6_addr(const struct in6_addr *a)
{
	/* Well-known prefix for NAT64 */
	if (a->s6_addr32[0] == WKPF && !a->s6_addr32[1] && !a->s6_addr32[2])
		return 0;

	/* Reserved per RFC 2373 */
	if (!a->s6_addr[0])
		return -1;

	/* Multicast addresses */
	if (a->s6_addr[0] == 0xff)
		return -1;

	/* Link-local unicast addresses */
	if ((a->s6_addr16[0] & htons(0xffc0)) == htons(0xfe80))
		return -1;

	return 0;
}

int is_private_ip4_addr(const struct in_addr *a)
{
	/* 10.0.0.0/8 */
	if ((a->s_addr & htonl(0xff000000)) == htonl(0x0a000000))
		return -1;

	/* 172.16.0.0/12 */
	if ((a->s_addr & htonl(0xfff00000)) == htonl(0xac100000))
		return -1;

	/* 192.0.2.0/24 */
	if ((a->s_addr & htonl(0xffffff00)) == htonl(0xc0000200))
		return -1;

	/* 192.168.0.0/16 */
	if ((a->s_addr & htonl(0xffff0000)) == htonl(0xc0a80000))
		return -1;

	/* 198.18.0.0/15 */
	if ((a->s_addr & htonl(0xfffe0000)) == htonl(0xc6120000))
		return -1;

	/* 198.51.100.0/24 */
	if ((a->s_addr & htonl(0xffffff00)) == htonl(0xc6336400))
		return -1;

	/* 203.0.113.0/24 */
	if ((a->s_addr & htonl(0xffffff00)) == htonl(0xcb007100))
		return -1;

	return 0;
}

int calc_ip4_mask(struct in_addr *mask, const struct in_addr *addr, int len)
{
	mask->s_addr = htonl(~((1 << (32 - len)) - 1));
	if (addr && (addr->s_addr & ~mask->s_addr))
		return -1;
	return 0;

}

int calc_ip6_mask(struct in6_addr *mask, const struct in6_addr *addr, int len)
{
	if (len > 32) {
		mask->s6_addr32[0] = ~0;
		if (len > 64) {
			mask->s6_addr32[1] = ~0;
			if (len > 96) {
				mask->s6_addr32[2] = ~0;
				mask->s6_addr32[3] =
					htonl(~((1 << (128 - len)) - 1));
			} else {
				mask->s6_addr32[2] =
					htonl(~((1 << (96 - len)) - 1));
				mask->s6_addr32[3] = 0;
			}
		} else {
			mask->s6_addr32[1] = htonl(~((1 << (64 - len)) - 1));
			mask->s6_addr32[2] = 0;
			mask->s6_addr32[3] = 0;
		}
	} else {
		mask->s6_addr32[0] = htonl(~((1 << (32 - len)) - 1));
		mask->s6_addr32[1] = 0;
		mask->s6_addr32[2] = 0;
		mask->s6_addr32[3] = 0;
	}
	if (!addr)
		return 0;
	if ((addr->s6_addr32[0] & ~mask->s6_addr32[0]) ||
			(addr->s6_addr32[1] & ~mask->s6_addr32[1]) ||
			(addr->s6_addr32[2] & ~mask->s6_addr32[2]) ||
			(addr->s6_addr32[3] & ~mask->s6_addr32[3]))
		return -1;
	return 0;
}

static int parse_prefix(int af, const char *__src, void *prefix, int *prefix_len)
{
	char *p, *end;
	long int a;
	int r;
	char src[80];

	memset(src, 0x0, sizeof(src));
	strncpy(src, __src, sizeof(src) - 1);

	p = strchr(src, '/');
	if (!p)
		return -EINVAL;
	*p = 0;
	a = simple_strtoul(p + 1, &end, 10);
	if (af == AF_INET) {
		r = *end || !in4_pton(src, -1, (u8 *)prefix, -1, NULL);
	} else if (af == AF_INET6) {
		r = *end || !in6_pton(src, -1, (u8 *)prefix, -1, NULL);
	} else {
		return -EINVAL;
	}
	*p = '/';
	if (r)
		return -EINVAL;
	if (a < 0 || a > (af == AF_INET6 ? 128 : 32))
		return -EINVAL;

	*prefix_len = a;
	return 0;
}

static int config_ipv4_addr(const char *arg)
{
	if (gcfg.local_addr4.s_addr) {
		printk(KERN_ERR "Error: duplicate ipv4-addr directive\n");
		return -EINVAL;
	}
	if (!in4_pton(arg, -1, (u8 *)&gcfg.local_addr4, -1, NULL)) {
		printk(KERN_ERR "Expected an IPv4 address but found \"%s\"\n", arg);
		return -EINVAL;
	}
	if (validate_ip4_addr(&gcfg.local_addr4) < 0) {
		printk(KERN_ERR "Cannot use reserved address %s in ipv4-addr "
				"directive, aborting...\n", arg);
		return -EINVAL;
	}
	return 0;
}

static int config_ipv6_addr(const char *arg)
{
	if (gcfg.local_addr6.s6_addr[0]) {
		printk(KERN_ERR "Error: duplicate ipv6-addr directive\n");
		return -EINVAL;
	}
	if (!in6_pton(arg, -1, (u8 *)&gcfg.local_addr6, -1, NULL)) {
		printk(KERN_ERR "Expected an IPv6 address but found \"%s\"\n", arg);
		return -EINVAL;
	}
	if (validate_ip6_addr(&gcfg.local_addr6) < 0) {
		printk(KERN_ERR "Cannot use reserved address %s in ipv6-addr "
				"directive, aborting...\n", arg);
		return -EINVAL;
	}
	if (gcfg.local_addr6.s6_addr32[0] == WKPF) {
		printk(KERN_ERR "Error: ipv6-addr directive cannot contain an "
				"address in the Well-Known Prefix "
				"(64:ff9b::/96)\n");
		return -EINVAL;
	}
	return 0;
}

static int config_prefix(const char *arg)
{
	if (parse_prefix(AF_INET6, arg, &gcfg.prefix, &gcfg.prefix_len) ||
			calc_ip6_mask(&gcfg.prefix_mask, &gcfg.prefix, gcfg.prefix_len)) {
		printk(KERN_ERR "Expected an IPv6 prefix but found \"%s\"\n", arg);
		return -EINVAL;
	}
	if (validate_ip6_addr(&gcfg.prefix) < 0) {
		printk(KERN_ERR "Cannot use reserved address %s in prefix "
				"directive, aborting...\n", arg);
		return -EINVAL;
	}
	if (gcfg.prefix_len != 32 && gcfg.prefix_len != 40 &&
		gcfg.prefix_len != 48 && gcfg.prefix_len != 56 &&
		gcfg.prefix_len != 64 && gcfg.prefix_len != 96) {
		printk(KERN_ERR "NAT prefix length must be 32, 40, 48, 56, 64 "
				"or 96 only, aborting...\n");
		return -EINVAL;
	}
	return 0;
}

static int config_dynamic_pool(const char *arg)
{
	if (parse_prefix(AF_INET, arg, &gcfg.dynamic_pool, &gcfg.dynamic_pfxlen) ||
		calc_ip4_mask(&gcfg.dynamic_mask, &gcfg.dynamic_pool, gcfg.dynamic_pfxlen)) {
		printk(KERN_ERR "Expected an IPv4 prefix but found \"%s\"\n", arg);
		return -EINVAL;
	}
	if (validate_ip4_addr(&gcfg.dynamic_pool) < 0) {
		printk(KERN_ERR "Cannot use reserved address %s in dynamic-pool "
				"directive, aborting...\n", arg);
		return -EINVAL;
	}
	if (gcfg.dynamic_pfxlen < 8 || gcfg.dynamic_pfxlen > 31) {
		printk(KERN_ERR "Cannot use a prefix shorter than 8 or "
				"longer than /31 in dynamic-pool directive\n");
		return -EINVAL;
	}
	return 0;
}

static char s_ipv6_addr[50];
module_param_string(ipv6_addr, s_ipv6_addr, sizeof(s_ipv6_addr), 0644);
MODULE_PARM_DESC(ipv6_addr, "IPv6 address");

static char s_ipv4_addr[20];
module_param_string(ipv4_addr, s_ipv4_addr, sizeof(s_ipv4_addr), 0644);
MODULE_PARM_DESC(ipv4_addr, "IPv4 address");

static char s_prefix[50];
module_param_string(prefix, s_prefix, sizeof(s_prefix), 0644);
MODULE_PARM_DESC(prefix, "NAT64 IPv6 prefix");

static char s_dynamic_pool[20];
module_param_string(dynamic_pool, s_dynamic_pool, sizeof(s_dynamic_pool), 0644);
MODULE_PARM_DESC(dynamic_pool, "Dynamic address pool");

int check_params(void)
{
	int rc;

	//gcfg.dyn_min_lease = HZ * (7200 + 4 * 60); /* just over two hours */
	//gcfg.dyn_max_lease = HZ * 14 * 86400;
	//gcfg.max_commit_delay = gcfg.dyn_max_lease / 4;
	gcfg.allow_ident_gen = 1;
	gcfg.ipv6_offlink_mtu = 1280;
	gcfg.lazy_frag_hdr = 1;
	gcfg.dynamic_pool_timeo = 120;

	if ((rc = config_ipv6_addr(s_ipv6_addr)) < 0)
		return rc;
	if ((rc = config_ipv4_addr(s_ipv4_addr)) < 0)
		return rc;
	if ((rc = config_prefix(s_prefix)) < 0)
		return rc;
	if ((rc = config_dynamic_pool(s_dynamic_pool)) < 0)
		return rc;

	if (!gcfg.local_addr4.s_addr) {
		printk(KERN_ERR "Error: no ipv4-addr directive found\n");
		return -EINVAL;
	}

	gcfg.mtu = 1500;
	get_random_bytes(gcfg.rand, sizeof(gcfg.rand));
	gcfg.rand[0] |= 1; /* need an odd number for IPv4 hash */

	return 0;
}

