#include <linux/kernel.h>
#include <linux/version.h>
#include <linux/module.h>
#include <linux/types.h>
#include <linux/netdevice.h>
#include <linux/skbuff.h>
#include <linux/etherdevice.h>
#include <linux/if_ether.h>
#include <linux/if_vlan.h>
#include <net/rtnetlink.h>
#include <net/sock.h>

static char param_vlans[128] = "";
module_param_string(vlans, param_vlans, sizeof(param_vlans), 0644);
MODULE_PARM_DESC(vlans, "Definition of all VLANs");

static int param_proto = 0x7077;
module_param_named(proto, param_proto, int, 0644);
MODULE_PARM_DESC(proto, "Customized Ethernet type");

static int param_mtu = 0;
module_param_named(mtu, param_mtu, int, 0644);
MODULE_PARM_DESC(mtu, "Override VLAN interface MTU size");

static int param_packip = 0;
module_param_named(packip, param_packip, int, 0644);
MODULE_PARM_DESC(packip, "Encapsulate VID in Ethernet header for IPv4 to keep MTU <= 1500");

struct yavlan_info {
	unsigned short vid;
	char phy_ifname[IFNAMSIZ];
	char vlan_ifname[IFNAMSIZ];
	struct net_device *phy_dev;
	struct net_device *vlan_dev;
};

#define YAVLAN_LIST_SIZE  16
static struct yavlan_info *yavlan_list[YAVLAN_LIST_SIZE];
static int yavlan_list_len = 0;

static inline struct yavlan_info *yavlan_get_by_phydev_vid(
		struct net_device *phy_dev, unsigned short vid)
{
	int i;
	for (i = 0; i < yavlan_list_len; i++) {
		struct yavlan_info *vi = yavlan_list[i];
		if (!vi)
			continue;
		if (vi->phy_dev == phy_dev && vi->vid == vid)
			return vi;
	}
	return NULL;
}

static int yavlan_rcv(struct sk_buff *skb, struct net_device *dev,
		struct packet_type *pt, struct net_device *orig_dev)
{
	struct sk_buff *__skb;
	struct vlan_ethhdr veh;
	unsigned short vid, proto;
	struct yavlan_info *vi;

	/* Ignore non-ethernet packets */
	if (!vlan_eth_hdr(skb))
		goto out;

	/* Make a copy since data will be modified. */
	if (!(__skb = skb_copy(skb, GFP_ATOMIC)))
		goto out;
	kfree_skb(skb);
	skb = __skb;

	veh = *vlan_eth_hdr(skb);

	vid = ntohs(veh.h_vlan_TCI) & VLAN_VID_MASK;
	proto = veh.h_vlan_encapsulated_proto;

	if (!(vi = yavlan_get_by_phydev_vid(dev, vid)))
		goto out;

	/* Adjust MAC header pointer and overwrite VLAN tag. */
	skb_push(skb, ETH_HLEN - VLAN_HLEN);
	skb_reset_mac_header(skb);

	if (unlikely(!pskb_may_pull(skb, ETH_HLEN)))
		goto out;
	memcpy(eth_hdr(skb)->h_dest, veh.h_dest, ETH_ALEN);
	memcpy(eth_hdr(skb)->h_source, veh.h_source, ETH_ALEN);
	eth_hdr(skb)->h_proto = proto;

	/* Move back to real network header after stripping VLAN tag. */
	skb_pull_rcsum(skb, ETH_HLEN);
	skb_reset_network_header(skb);
	skb_reset_transport_header(skb);

	skb->dev = vi->vlan_dev;
	skb->protocol = proto;
	skb->ip_summed = CHECKSUM_NONE;
	vi->vlan_dev->stats.rx_bytes += skb->len;
	vi->vlan_dev->stats.rx_packets++;
	netif_rx(skb);

	return 0;

out:
	kfree_skb(skb);
	return 0;
}

static struct packet_type yavlan_ptype = {
	.type = __constant_htons(ETH_P_8021Q),
	.func = yavlan_rcv,
	.dev  = NULL,
};

/* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= */

struct yavlan_netdev_priv {
	struct yavlan_info *vi;
};

#define vlan_netdev_to_vi(dev) (((struct yavlan_netdev_priv *)netdev_priv(dev))->vi)

static int yavlan_start_xmit(struct sk_buff *skb, struct net_device *dev)
{
	struct yavlan_info *vi = vlan_netdev_to_vi(dev);
	struct ethhdr eh;

	if (skb_headroom(skb) < VLAN_HLEN) {
		struct sk_buff *__skb = skb_realloc_headroom(skb, VLAN_HLEN);
		if (!__skb) {
			dev->stats.tx_dropped++;
			goto out;
		}
		kfree_skb(skb);
		skb = __skb;
	} else {
		if (!(skb = skb_unshare(skb, GFP_ATOMIC))) {
			dev->stats.tx_dropped++;
			goto out;
		}
	}

	skb_orphan(skb);
	skb_dst_drop(skb);
	nf_reset(skb);

	skb_reset_mac_header(skb);
	eh = *eth_hdr(skb);
	skb_push(skb, VLAN_HLEN);
	skb_reset_mac_header(skb);

	/* Fill the VLAN-tagged Ethernet header. */
	memcpy(vlan_eth_hdr(skb)->h_dest, eh.h_dest, ETH_ALEN);
	memcpy(vlan_eth_hdr(skb)->h_source, eh.h_source, ETH_ALEN);
	vlan_eth_hdr(skb)->h_vlan_proto = htons(param_proto);
	vlan_eth_hdr(skb)->h_vlan_TCI = htons(vi->vid);
	vlan_eth_hdr(skb)->h_vlan_encapsulated_proto = eh.h_proto;

	skb->dev = vi->phy_dev;
	dev_queue_xmit(skb);

	dev->stats.tx_bytes += skb->len;
	dev->stats.tx_packets++;
	return NETDEV_TX_OK;

out:
	kfree_skb(skb);
	return NETDEV_TX_OK;
}

static int yavlan_start(struct net_device *dev)
{
	netif_tx_start_all_queues(dev);
	return 0;
}

static int yavlan_stop(struct net_device *dev)
{
	netif_tx_stop_all_queues(dev);
	return 0;
}

static const struct net_device_ops yavlan_netdev_ops = {
	.ndo_open       = yavlan_start,
	.ndo_stop       = yavlan_stop,
	.ndo_start_xmit = yavlan_start_xmit,
};

static void yavlan_netdev_setup(struct net_device *dev)
{
	ether_setup(dev);
	dev->netdev_ops = &yavlan_netdev_ops;
}

static int netdev_attach_yavlan(struct net_device *phy_dev, struct yavlan_info *vi)
{
	int err = -1;
	struct net_device *vlan_dev = NULL;

	dev_hold(phy_dev);
	dev_set_promiscuity(phy_dev, 1);

	if (!(vlan_dev = alloc_netdev(sizeof(struct yavlan_netdev_priv), vi->vlan_ifname,
		yavlan_netdev_setup))) {
		printk(KERN_ERR "YaVLAN: alloc_netdev() failed.\n");
		err = -ENOMEM;
		goto out;
	}
	vlan_netdev_to_vi(vlan_dev) = vi;
	if (param_mtu) {
		vlan_dev->mtu = param_mtu;
	} else {
		vlan_dev->mtu = phy_dev->mtu;
	}
	memcpy(vlan_dev->dev_addr, phy_dev->dev_addr, ETH_ALEN);

	if ((err = register_netdevice(vlan_dev)) < 0)
		goto out;

	netif_carrier_on(vlan_dev);

	vi->phy_dev = phy_dev;
	vi->vlan_dev = vlan_dev;
	/* FIXME: RCU synchronizing. */

	printk(KERN_INFO "YaVLAN: %u@%s hooked\n", vi->vid, vi->phy_ifname);
	return 0;

out:
	if (vlan_dev)
		free_netdev(vlan_dev);
	dev_set_promiscuity(phy_dev, -1);
	dev_put(phy_dev);
	return err;
}

static int netdev_detach_yavlan(struct net_device *phy_dev, struct yavlan_info *vi)
{
	struct net_device *vlan_dev = vi->vlan_dev;

	vi->vlan_dev = NULL;
	vi->phy_dev = NULL;
	synchronize_rcu();

	if (vlan_dev) {
		unregister_netdevice(vlan_dev);
		//free_netdev(vlan_dev);
	}

	dev_set_promiscuity(phy_dev, -1);
	dev_put(phy_dev);

	printk(KERN_INFO "YaVLAN: %u@%s unhooked\n", vi->vid, vi->phy_ifname);
	return 0;
}

/* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-= */

static int hooked_dev_event(struct notifier_block *unused,
	unsigned long event, void *ptr)
{
#if LINUX_VERSION_CODE >= KERNEL_VERSION(3, 11, 0)
	struct net_device *dev = netdev_notifier_info_to_dev(ptr);
#else
	struct net_device *dev = ptr;
#endif
	int i;

	for (i = 0; i < yavlan_list_len; i++) {
		struct yavlan_info *vi = yavlan_list[i];

		if (!vi)
			continue;
		if (event == NETDEV_REGISTER) {
			if (strcmp(vi->phy_ifname, dev->name) != 0)
				continue;
		} else if (vi->phy_dev != dev) {
			continue;
		}

		switch (event) {
		case NETDEV_REGISTER:
			/* Physical interface appears, hook it. */
			netdev_attach_yavlan(dev, yavlan_list[i]);
			break;
		case NETDEV_UNREGISTER:
			/* Physical interface is being removed, unhook from it. */
			netdev_detach_yavlan(dev, vi);
			break;
		case NETDEV_CHANGEADDR:
			memcpy(vi->vlan_dev->dev_addr, dev->dev_addr, ETH_ALEN);
			break;
		case NETDEV_CHANGEMTU:
			if (vi->vlan_dev->mtu > dev->mtu)
				dev_set_mtu(vi->vlan_dev, dev->mtu);
			break;
		case NETDEV_UP:
			if (!(vi->vlan_dev->flags & IFF_UP))
				dev_change_flags(vi->vlan_dev, vi->vlan_dev->flags | IFF_UP);
			break;
		case NETDEV_DOWN:
			if ((vi->vlan_dev->flags & IFF_UP))
				dev_change_flags(vi->vlan_dev, vi->vlan_dev->flags & ~IFF_UP);
			break;
		}
	}

	return NOTIFY_DONE;
}

static struct notifier_block hooked_dev_notifier = {
	.notifier_call = hooked_dev_event,
};

static void __try_release_vlan_defs(void)
{
	int i;

	for (i = 0; i < yavlan_list_len; i++) {
		if (yavlan_list[i]->phy_dev)
			netdev_detach_yavlan(yavlan_list[i]->phy_dev, yavlan_list[i]);
		kfree(yavlan_list[i]);
		yavlan_list[i] = NULL;
	}
	yavlan_list_len = 0;
}

static int generate_vlan_defs_by_param(const char *param_vlans)
{
	int err = -EINVAL;
	char *cp, *__vlans = NULL;

	if (strlen(param_vlans) == 0) {
		printk(KERN_WARNING "YaVLAN: No VLAN definition specified\n");
		goto out;
	}

	/* Parse parameter 'vlans': 10@eth1@eth1-10,11@eth1,12@eth0,... */
	if (!(__vlans = kmalloc(sizeof(param_vlans), GFP_KERNEL))) {
		err = -ENOMEM;
		goto out;
	}
	strncpy(__vlans, param_vlans, sizeof(param_vlans));

	cp = __vlans;
	do {
		char *cp_vid = NULL, *cp_pname = NULL, *cp_vname = NULL;
		unsigned vid = 0;
		struct yavlan_info *vi;

		/* VLAN id. */
		cp_vid = cp;
		if ((cp = strchr(cp, ','))) {
			*(cp++) = '\0';
		}

		/* Physical interface name. */
		if (!(cp_pname = strchr(cp_vid, '@'))) {
			printk(KERN_WARNING "YaVLAN: Invalid VLAN description: '%s'\n", cp_vid);
			goto out;
		}
		*(cp_pname++) = '\0';
		/* Custom VLAN interface name. */
		if ((cp_vname = strchr(cp_pname, '@'))) {
			*(cp_vname++) = '\0';
		}

		if (sscanf(cp_vid, "%u", &vid) != 1) {
			printk(KERN_WARNING "YaVLAN: Invalid VLAN ID: '%s'\n", cp_vid);
			goto out;
		}
		if (vid == 0 || vid >= VLAN_N_VID) {
			printk(KERN_WARNING "YaVLAN: Invalid VLAN ID: '%u'\n", vid);
			goto out;
		}

		/* Add a VLAN description. */
		if (!(vi = kmalloc(sizeof(struct yavlan_info), GFP_KERNEL))) {
			printk(KERN_WARNING "YaVLAN: kmalloc() error\n");
			err = -ENOMEM;
			goto out;
		}
		memset(vi, 0x0, sizeof(*vi));
		vi->vid = (unsigned short)vid;
		strncpy(vi->phy_ifname, cp_pname, IFNAMSIZ);
		if (cp_vname) {
			strncpy(vi->vlan_ifname, cp_vname, IFNAMSIZ);
		} else {
			snprintf(vi->vlan_ifname, IFNAMSIZ, "%s-%u", vi->phy_ifname, vi->vid);
		}

		if (yavlan_list_len >= YAVLAN_LIST_SIZE) {
			printk(KERN_WARNING "YaVLAN: VLAN definition list is full\n");
			kfree(vi);
			break;
		}
		yavlan_list[yavlan_list_len++] = vi;
	} while (cp);

	kfree(__vlans);
	return 0;

out:
	if (__vlans)
		kfree(__vlans);
	__try_release_vlan_defs();
	return err;
}

int __init yavlan_init(void)
{
	int err = -EINVAL, rc;

	/* Check parameter 'proto', expecting a valid Ethernet protocol. */
	if (param_proto < 0x100) {
		printk(KERN_WARNING "YaVLAN: Invalid Ethernet protocol '0x%04x'\n", param_proto);
		goto out;
	}
	yavlan_ptype.type = htons(param_proto);
	/* Check parameter 'mtu'. */
	if (param_mtu) {
		if (param_mtu < 1000 || param_mtu > 8192) {
			printk(KERN_WARNING "YaVLAN: Illegal MTU size: %d\n", param_mtu);
			goto out;
		}
	}

	if ((rc = generate_vlan_defs_by_param(param_vlans)) < 0)
		goto out;

	/* This calls the notifier callback in which the hook is added. */
	register_netdevice_notifier(&hooked_dev_notifier);

	dev_add_pack(&yavlan_ptype);

	printk(KERN_INFO "YaVLAN - Yet another VLAN implementation\n");
	return 0;

out:
	__try_release_vlan_defs();
	return err;
}

void __exit yavlan_exit(void)
{
	dev_remove_pack(&yavlan_ptype);
	unregister_netdevice_notifier(&hooked_dev_notifier);

	__try_release_vlan_defs();
}

module_init(yavlan_init);
module_exit(yavlan_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Jianying Liu");
MODULE_DESCRIPTION("YaVLAN - Yet another VLAN implementation");
MODULE_VERSION("0.0.1");

