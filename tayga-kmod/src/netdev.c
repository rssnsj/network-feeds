/*
 * Driver for NAT64 Virtual Network Interface.
 *
 * Author: Jianying Liu <rssnsj@gmail.com>
 * Date: 2014/01/21
 *
 * This source code is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * version 2 as published by the Free Software Foundation.
 */

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/fs.h>
#include <linux/poll.h>
#include <linux/sched.h>
#include <linux/netdevice.h>
#include <linux/if.h>
#include <linux/if_ether.h>
#include <linux/if_arp.h>
#include <net/sock.h>

#include "tayga.h"

struct nat64_if_info {
	struct net_device *dev;
};

static int nat64_start_xmit(struct sk_buff *skb, struct net_device *dev)
{
	struct pkt pbuf;

	skb_orphan(skb);
	skb_dst_drop(skb);
	nf_reset(skb);

	if (skb_linearize(skb) < 0)
		return NETDEV_TX_OK;

	pbuf.dev = dev;
	pbuf.skb = skb;
	pbuf.ip4 = NULL;
	pbuf.ip6 = NULL;
	pbuf.ip6_frag = NULL;
	pbuf.icmp = NULL;
	pbuf.data_proto = 0;
	pbuf.data = skb->data;
	pbuf.data_len = skb->len;
	pbuf.header_len = 0;

	switch(ntohs(skb->protocol)) {
	case ETH_P_IP:
		handle_ip4(&pbuf);
		break;
	case ETH_P_IPV6:
		handle_ip6(&pbuf);
		break;
	default:
		printk(KERN_WARNING "tayga: Unknown protocol %u of packet.\n",
			ntohs(skb->protocol));
		dev->stats.tx_dropped++;
	}

	return NETDEV_TX_OK;
}

static int nat64_start(struct net_device *dev)
{
	netif_tx_start_all_queues(dev);
	return 0;
}

static int nat64_stop(struct net_device *dev)
{
	netif_tx_stop_all_queues(dev);
	return 0;
}

static const struct net_device_ops nat64_netdev_ops = {
	.ndo_open		= nat64_start,
	.ndo_stop		= nat64_stop,
	.ndo_start_xmit	= nat64_start_xmit,
};

static void nat64_setup(struct net_device *dev)
{
	struct nat64_if_info *nif = (struct nat64_if_info *)netdev_priv(dev);

	/* Point-to-Point interface */
	dev->netdev_ops = &nat64_netdev_ops;
	dev->hard_header_len = 0;
	dev->addr_len = 0;
	dev->mtu = 1500;
	dev->needed_headroom = sizeof(struct ip6) - sizeof(struct ip4);

	/* Zero header length */
	dev->type = ARPHRD_NONE;
	dev->flags = IFF_POINTOPOINT | IFF_NOARP | IFF_MULTICAST;
	dev->tx_queue_len = 500;  /* We prefer our own queue length */

	/* Setup private data */
	memset(nif, 0x0, sizeof(nif[0]));
	nif->dev = dev;
}

/* Handle of the NAT64 virtual interface */
static struct net_device *nat64_netdev = NULL;

int  __init nat64_module_init(void)
{
	struct net_device *dev;
	char s_addr4[20], s_addr6[40];
	int err = -1;

	if ((err = check_params()) < 0)
		goto err1;
	if ((err = init_addrmap()) < 0)
		goto err2;

	if (!(dev = alloc_netdev_mqs(sizeof(struct nat64_if_info), "nat64",
		nat64_setup, 8, 8))) {
		printk(KERN_ERR "tayga: alloc_netdev() failed.\n");
		err = -ENOMEM;
		goto err3;
	}

	if ((err = register_netdev(dev)) < 0)
		goto err4;

	nat64_netdev = dev;
	netif_carrier_on(dev);

	printk(KERN_INFO "Kernel NAT64 Transition Module, ported from \"tayga\"\n");
	printk(KERN_INFO "TAYGA's IPv4 address: %s\n",
			simple_inet_ntoa(&gcfg.local_addr4, s_addr4));
	printk(KERN_INFO "TAYGA's IPv6 address: %s\n",
			simple_inet6_ntoa(&gcfg.local_addr6, s_addr6));
	printk(KERN_INFO "NAT64 prefix: %s/%d\n",
			simple_inet6_ntoa(&gcfg.prefix, s_addr6), gcfg.prefix_len);
	printk(KERN_INFO "Dynamic pool: %s/%d\n",
			simple_inet_ntoa(&gcfg.dynamic_pool, s_addr4), gcfg.dynamic_pfxlen);
	return 0;

err4:
	free_netdev(dev);
err3:
	fini_addrmap();
err2:
	/* fini_config() */
err1:
	return err;
}

void __exit nat64_module_exit(void)
{
	unregister_netdev(nat64_netdev);
	free_netdev(nat64_netdev);
	/* fini_config() */
	fini_addrmap();
}

module_init(nat64_module_init);
module_exit(nat64_module_exit);

MODULE_DESCRIPTION("Kernel NAT64 Transition Module, ported from \"tayga\"");
MODULE_AUTHOR("Jianying Liu <rssnsj@gmail.com>");
MODULE_LICENSE("GPL");

