/*
 * (C) 2014 Jianying Liu <rssnsj@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#include <linux/module.h>
#include <linux/skbuff.h>
#include <linux/netfilter.h>
#include <linux/netfilter/x_tables.h>
#include <net/netfilter/nf_nat_core.h>
#include <net/ipv6.h>
#include <linux/inet.h>

#include "prefix_defs.h"

static inline void __ipv6_change_prefix(struct in6_addr *dst,
	const struct in6_addr *addr, const struct in6_addr *pfx,
	unsigned int plen)
{
	/* caller must guarantee 0 <= plen <= 128 */
	int o = plen >> 3,
		b = plen & 0x7;

	memset(dst->s6_addr, 0, sizeof(dst->s6_addr));
	memcpy(dst->s6_addr, pfx->s6_addr, o);
	if (b != 0)
		dst->s6_addr[o] = (pfx->s6_addr[o] & (0xff00 >> b)) |
						  (addr->s6_addr[o] & (0xff >> b));
	memcpy(&dst->s6_addr[o], &addr->s6_addr[o], 16 - o);
}

static int xt_prefix_dnat_check(const struct xt_tgchk_param *par)
{
	const struct prefix_dnat_info *pdinfo = par->targinfo;

	if (pdinfo->prefix_len > 128) {
		printk(KERN_WARNING "[%s] Invalid prefix length %u.\n",
			__FUNCTION__, pdinfo->prefix_len);
		return -EINVAL;
	}
	return 0;
}

static unsigned int
xt_prefix_dnat_tg(struct sk_buff *skb, const struct xt_action_param *par)
{
	const struct prefix_dnat_info *pdinfo = par->targinfo;
	enum ip_conntrack_info ctinfo;
	struct nf_conn *ct;
	struct nf_nat_range range;
	struct in6_addr daddr;

	ct = nf_ct_get(skb, &ctinfo);
	NF_CT_ASSERT(ct != NULL &&
			(ctinfo == IP_CT_NEW || ctinfo == IP_CT_RELATED));

	__ipv6_change_prefix(&daddr, &ipv6_hdr(skb)->daddr,
			&pdinfo->prefix, pdinfo->prefix_len);

	memset(&range, 0, sizeof(range));
	range.flags = NF_NAT_RANGE_MAP_IPS;
	range.min_addr.in6 = daddr;
	range.max_addr.in6 = daddr;

	return nf_nat_setup_info(ct, &range, NF_NAT_MANIP_DST);
}

static struct xt_target xt_prefix_dnat_tg_reg[] __read_mostly = {
	{
		.name		= "PREFIXDNAT",
		.checkentry	= xt_prefix_dnat_check,
		.target		= xt_prefix_dnat_tg,
		.targetsize	= sizeof(struct prefix_dnat_info),
		.table		= "nat",
		.hooks		= (1 << NF_INET_PRE_ROUTING) |
					  (1 << NF_INET_LOCAL_OUT),
		.me			= THIS_MODULE,
	},
};

static int __init xt_prefix_nat_init(void)
{
	return xt_register_targets(xt_prefix_dnat_tg_reg,
			ARRAY_SIZE(xt_prefix_dnat_tg_reg));
}

static void __exit xt_prefix_nat_exit(void)
{
	xt_unregister_targets(xt_prefix_dnat_tg_reg,
			ARRAY_SIZE(xt_prefix_dnat_tg_reg));
}

module_init(xt_prefix_nat_init);
module_exit(xt_prefix_nat_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Jianying Liu <rssnsj@gmail.com>");
MODULE_ALIAS("ip6t_PREFIXDNAT");
