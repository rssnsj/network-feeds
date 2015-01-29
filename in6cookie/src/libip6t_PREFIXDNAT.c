/*
 * Copyright (c) 2011 Patrick McHardy <kaber@trash.net>
 *
 * Based on Rusty Russell's IPv4 PREFIXDNAT target. Development of IPv6 NAT
 * funded by Astaro.
 */

#include <stdio.h>
#include <netdb.h>
#include <string.h>
#include <stdlib.h>
#include <xtables.h>
#include <arpa/inet.h>

#include "prefix_defs.h"

enum {
	O_TO_PREFIX = 0,
};

static void prefix_dnat_help(void)
{
	printf( "PREFIXDNAT target options:\n"
			" --to-prefix <prefix>/<prefix_len>\n"
			"        Address to map destination to.\n");
}

static const struct xt_option_entry prefix_dnat_opts[] = {
	{.name = "to-prefix", .id = O_TO_PREFIX, .type = XTTYPE_STRING,
	 .flags = XTOPT_MAND | XTOPT_MULTI},
	XTOPT_TABLEEND,
};

static int parse_prefix(const char *__src, struct in6_addr *prefix,
		unsigned int *prefix_len)
{
	char *p, *end, src[80];
	int a, r;

	memset(src, 0x0, sizeof(src));
	strncpy(src, __src, sizeof(src) - 1);

	p = strchr(src, '/');
	if (!p)
		return -1;
	*p = 0;
	a = (int)strtol(p + 1, &end, 10);
	r = *end || !inet_pton(AF_INET6, src, prefix);
	*p = '/';
	if (r)
		return -1;
	if (a < 0 || a > 128)
		return -1;

	*prefix_len = (unsigned int)a;
	return 0;
}

static void prefix_dnat_parse(struct xt_option_call *cb)
{
	struct prefix_dnat_info *pdinfo = cb->data;
	int rc;

	xtables_option_parse(cb);
	switch (cb->entry->id) {
	case O_TO_PREFIX:
		rc = parse_prefix(cb->arg, &pdinfo->prefix, &pdinfo->prefix_len);
		if (rc < 0)
			xtables_error(PARAMETER_PROBLEM, "Invalid prefix: %s", cb->arg);
		break;
	}
}

static void prefix_dnat_print(const void *ip, const struct xt_entry_target *target,
                       int numeric)
{
	const struct prefix_dnat_info *pdinfo = (const void *)target->data;
	char s1[50];

	printf(" to prefix: %s/%u",
		inet_ntop(AF_INET6, &pdinfo->prefix, s1, sizeof(s1)),
		pdinfo->prefix_len);
}

static void prefix_dnat_save(const void *ip, const struct xt_entry_target *target)
{
	const struct prefix_dnat_info *pdinfo = (const void *)target->data;
	char s1[50];

	printf(" --to-prefix %s/%u ",
		inet_ntop(AF_INET6, &pdinfo->prefix, s1, sizeof(s1)),
		pdinfo->prefix_len);
}

static struct xtables_target prefix_dnat_tg_reg = {
	.name		= "PREFIXDNAT",
	.version	= XTABLES_VERSION,
	.family		= NFPROTO_IPV6,
	//.revision	= 1,
	.size		= XT_ALIGN(sizeof(struct prefix_dnat_info)),
	.userspacesize	= XT_ALIGN(sizeof(struct prefix_dnat_info)),
	.help		= prefix_dnat_help,
	.x6_parse	= prefix_dnat_parse,
	.print		= prefix_dnat_print,
	.save		= prefix_dnat_save,
	.x6_options	= prefix_dnat_opts,
};

void _init(void)
{
	xtables_register_target(&prefix_dnat_tg_reg);
}
